import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Başlatma
/// Firebase'i yalnızca `GoogleService-Info.plist` pakette varsa başlatır.
/// Dosya yoksa (ör. CI testleri, yapılandırılmamış derleme) uygulama çökmez; kurulum ekranı gösterilir.
enum FirebaseBootstrap {
    private(set) static var isConfigured = false

    static func configureIfPossible() {
        guard !isConfigured else { return }
        if FirebaseApp.app() != nil {
            isConfigured = true
            return
        }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return
        }
        FirebaseApp.configure()
        isConfigured = FirebaseApp.app() != nil
    }
}

// MARK: - Servis protokolü
struct AppleSignInResult {
    let uid: String
    let email: String?
    let isNewUser: Bool
}

/// ViewModel'lerin Firebase'e doğrudan bağımlı olmaması için protokol (test edilebilirlik).
protocol FirebaseServicing: AnyObject {
    var currentUserID: String? { get }

    func observeAuthState(_ handler: @escaping (String?) -> Void) -> Any
    func stopObserving(_ token: Any)

    func signIn(email: String, password: String) async throws -> String
    func register(email: String, password: String) async throws -> String
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AppleSignInResult
    func signOut() throws
    func sendPasswordReset(email: String) async throws

    func fetchUser(uid: String) async throws -> AppUser?
    func saveUser(_ user: AppUser) async throws
    func uploadProfileImage(_ data: Data, uid: String) async throws -> URL

    // Hesap yönetimi
    /// Oturumdaki hesabın e-posta/şifre ile mi açıldığı (yeniden doğrulamada şifre istenir).
    var usesPasswordSignIn: Bool { get }
    func reauthenticate(email: String, password: String) async throws
    /// Firestore'daki tüm kullanıcı verilerini, profil fotoğrafını ve Auth hesabını siler.
    func deleteAccount(uid: String) async throws
}

/// `saveUser` için Firestore alanları. Boş (nil) isteğe bağlı alanlar silinir; `role` istemciden asla yazılmaz.
enum UserDocumentEncoder {
    static let optionalKeys = ["birthDate", "heightCm", "weightKg", "gender", "photoURL", "targetWeightKg", "startWeightKg"]

    static func fields(for user: AppUser, deleteMarker: Any) throws -> [String: Any] {
        var data = try Firestore.Encoder().encode(user)
        data.removeValue(forKey: "role")
        for key in optionalKeys where data[key] == nil || data[key] is NSNull {
            data[key] = deleteMarker
        }
        return data
    }
}

// MARK: - Firebase uygulaması
final class FirebaseManager: FirebaseServicing {
    static let shared = FirebaseManager()
    private init() {}

    // Tembel erişim: Firebase yalnızca başlatıldıktan sonra kullanılır.
    private var auth: Auth { Auth.auth() }
    private var db: Firestore { Firestore.firestore() }
    var storage: Storage { Storage.storage() }

    var currentUserID: String? {
        FirebaseBootstrap.isConfigured ? auth.currentUser?.uid : nil
    }

    // MARK: Oturum durumu
    func observeAuthState(_ handler: @escaping (String?) -> Void) -> Any {
        guard FirebaseBootstrap.isConfigured else {
            handler(nil)
            return NSObject()
        }
        return auth.addStateDidChangeListener { _, user in
            handler(user?.uid)
        }
    }

    func stopObserving(_ token: Any) {
        guard FirebaseBootstrap.isConfigured, let handle = token as? NSObjectProtocol else { return }
        auth.removeStateDidChangeListener(handle)
    }

    // MARK: Kimlik doğrulama
    func signIn(email: String, password: String) async throws -> String {
        try ensureConfigured()
        return try await perform {
            try await self.auth.signIn(withEmail: email, password: password).user.uid
        }
    }

    func register(email: String, password: String) async throws -> String {
        try ensureConfigured()
        return try await perform {
            try await self.auth.createUser(withEmail: email, password: password).user.uid
        }
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AppleSignInResult {
        try ensureConfigured()
        return try await perform {
            let credential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: rawNonce,
                fullName: fullName
            )
            let result = try await self.auth.signIn(with: credential)
            return AppleSignInResult(
                uid: result.user.uid,
                email: result.user.email,
                isNewUser: result.additionalUserInfo?.isNewUser ?? false
            )
        }
    }

    func signOut() throws {
        guard FirebaseBootstrap.isConfigured else { return }
        do {
            try auth.signOut()
        } catch {
            throw AppError.map(error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        try ensureConfigured()
        try await perform {
            try await self.auth.sendPasswordReset(withEmail: email)
        }
    }

    // MARK: Firestore
    func fetchUser(uid: String) async throws -> AppUser? {
        try ensureConfigured()
        return try await perform {
            // Çevrimdışıysa Firestore otomatik olarak yerel önbelleğe düşer.
            let snapshot = try await self.db.collection(Constants.Collection.users).document(uid).getDocument()
            guard snapshot.exists else { return nil }
            return try snapshot.data(as: AppUser.self)
        }
    }

    func saveUser(_ user: AppUser) async throws {
        try ensureConfigured()
        do {
            // Senkron `setData` bilerek kullanılıyor: yazma önce yerel önbelleğe gider,
            // internet yokken bloklamaz ve bağlantı gelince otomatik eşitlenir.
            let fields = try UserDocumentEncoder.fields(for: user, deleteMarker: FieldValue.delete())
            db.collection(Constants.Collection.users)
                .document(user.id)
                .setData(fields, merge: true)
        } catch {
            throw AppError.map(error)
        }
    }

    // MARK: Storage
    func uploadProfileImage(_ data: Data, uid: String) async throws -> URL {
        try ensureConfigured()
        do {
            let ref = storage.reference().child("\(Constants.StoragePath.profileImages)/\(uid).jpg")
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await ref.putDataAsync(data, metadata: metadata)
            return try await ref.downloadURL()
        } catch {
            throw AppError.storage(error.localizedDescription)
        }
    }

    // MARK: Hesap yönetimi
    var usesPasswordSignIn: Bool {
        guard FirebaseBootstrap.isConfigured, let user = auth.currentUser else { return false }
        return user.providerData.contains { $0.providerID == "password" }
    }

    func reauthenticate(email: String, password: String) async throws {
        try ensureConfigured()
        guard let user = auth.currentUser else { throw AppError.notAuthenticated }
        try await perform {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            _ = try await user.reauthenticate(with: credential)
        }
    }

    /// Sıra önemli: önce veriler (kurallar oturum ister), en son Auth hesabı.
    func deleteAccount(uid: String) async throws {
        try ensureConfigured()
        guard let user = auth.currentUser, user.uid == uid else { throw AppError.notAuthenticated }

        let userDocument = db.collection(Constants.Collection.users).document(uid)
        try await perform {
            for name in Constants.Collection.userSubcollections {
                try await self.deleteAllDocuments(in: userDocument.collection(name))
            }
        }

        // Profil fotoğrafı yoksa ya da Storage kurulmadıysa hata yok sayılır.
        try? await storage.reference().child("\(Constants.StoragePath.profileImages)/\(uid).jpg").delete()

        try await perform {
            try await userDocument.delete()
            try await user.delete()
        }
    }

    /// Koleksiyonu 400'lük gruplar halinde siler (Firestore toplu yazma sınırı 500).
    private func deleteAllDocuments(in collection: CollectionReference) async throws {
        while true {
            let snapshot = try await collection.limit(to: 400).getDocuments()
            guard !snapshot.documents.isEmpty else { return }
            let batch = db.batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
        }
    }

    // MARK: Yardımcılar
    private func ensureConfigured() throws {
        guard FirebaseBootstrap.isConfigured else { throw AppError.firebaseNotConfigured }
    }

    private func perform<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw AppError.map(error)
        }
    }
}
