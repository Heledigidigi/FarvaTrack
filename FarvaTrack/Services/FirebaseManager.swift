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
            try db.collection(Constants.Collection.users)
                .document(user.id)
                .setData(from: user, merge: true)
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
