import Foundation
import Network
import FirebaseAuth
import FirebaseFirestore

protocol AccountDeleting {
    /// Oturumdaki hesabın giriş yöntemleri ("password", "apple.com").
    var providerIDs: [String] { get }

    func isOnline() async -> Bool
    func reauthenticate(password: String) async throws
    func reauthenticateWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws
    func deleteRemoteData(userID: String, includeAdminCollections: Bool) async throws
    func deleteProfilePhoto(userID: String) async
    func revokeAppleToken(authorizationCode: String) async throws
    func deleteAuthUser() async throws
}

final class FirebaseAccountDeletionService: AccountDeleting {
    private var auth: Auth { Auth.auth() }

    private static let userCollections = [
        Constants.Collection.workouts, Constants.Collection.meals, Constants.Collection.water,
        Constants.Collection.sleep, Constants.Collection.weight, Constants.Collection.measurements,
        Constants.Collection.library
    ]

    var providerIDs: [String] {
        auth.currentUser?.providerData.map(\.providerID) ?? []
    }

    func isOnline() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "farvatrack.network-check")
            var finished = false
            monitor.pathUpdateHandler = { path in
                guard !finished else { return }       // işleyici aynı kuyrukta sıralı çalışır
                finished = true
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: queue)
        }
    }

    func reauthenticate(password: String) async throws {
        guard let user = auth.currentUser, let email = user.email else { throw AppError.notAuthenticated }
        do {
            _ = try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password))
        } catch {
            throw AppError.map(error)
        }
    }

    func reauthenticateWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        guard let user = auth.currentUser else { throw AppError.notAuthenticated }
        let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: fullName)
        do {
            _ = try await user.reauthenticate(with: credential)
        } catch {
            throw AppError.map(error)
        }
    }

    func deleteRemoteData(userID: String, includeAdminCollections: Bool) async throws {
        let db = Firestore.firestore()
        let userReference = db.collection(Constants.Collection.users).document(userID)

        var names = Self.userCollections
        // Yönetici koleksiyonuna kurallar gereği yalnızca admin hesaplar erişebilir.
        if includeAdminCollections { names.append(Constants.Collection.waste) }

        do {
            for name in names {
                try await deleteCollection(userReference.collection(name))
            }
            try await userReference.delete()
        } catch {
            throw AppError.map(error)
        }
    }

    /// 400'lük gruplar hâlinde siler (batch sınırı 500).
    private func deleteCollection(_ collection: CollectionReference) async throws {
        while true {
            let snapshot = try await collection.limit(to: 400).getDocuments()
            if snapshot.documents.isEmpty { return }
            let batch = collection.firestore.batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
        }
    }

    func deleteProfilePhoto(userID: String) async {
        await FirebaseManager.shared.deletePhoto(uid: userID)
    }

    func revokeAppleToken(authorizationCode: String) async throws {
        do {
            try await auth.revokeToken(withAuthorizationCode: authorizationCode)
        } catch {
            throw AppError.map(error)
        }
    }

    func deleteAuthUser() async throws {
        guard let user = auth.currentUser else { throw AppError.notAuthenticated }
        do {
            try await user.delete()
        } catch {
            throw AppError.map(error)
        }
    }
}