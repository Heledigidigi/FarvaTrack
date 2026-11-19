import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

final class FirebaseManager {
    static let shared = FirebaseManager()
    
    let auth = Auth.auth()
    let firestore = Firestore.firestore()
    let storage = Storage.storage()

    private init() {}

    func uploadProfileImage(_ data: Data, uid: String) async throws -> URL {
        let ref = storage.reference().child("\(Constants.StoragePath.profileImages)/\(uid).jpg")
        _ = try await ref.putDataAsync(data)
        return try await ref.downloadURL()
    }
}

// MARK: - Profil fotoğrafı protokolü
protocol ProfilePhotoStoring {
    func uploadPhoto(_ data: Data, uid: String) async throws -> URL
    func deletePhoto(uid: String) async
}

extension FirebaseManager: ProfilePhotoStoring {
    func uploadPhoto(_ data: Data, uid: String) async throws -> URL {
        try await uploadProfileImage(data, uid: uid)
    }

    func deletePhoto(uid: String) async {
        let reference = storage.reference().child("\(Constants.StoragePath.profileImages)/\(uid).jpg")
        try? await reference.delete()
    }
}
