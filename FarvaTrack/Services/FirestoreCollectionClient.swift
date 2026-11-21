import Foundation
import FirebaseFirestore

/// `users/{uid}/{collectionName}` altında genel yükleme, silme ve okuma.
struct FirestoreCollectionClient {
    let collectionName: String

    private func collection(for userID: String) throws -> CollectionReference {
        guard FirebaseBootstrap.isConfigured else { throw AppError.firebaseNotConfigured }
        return Firestore.firestore()
            .collection(Constants.Collection.users)
            .document(userID)
            .collection(collectionName)
    }

    /// Çevrimdışıyken sunucu onayına kadar bekler; çağıran taraf arka planda çalıştırmalıdır.
    func upload<T: Encodable>(_ value: T, id: String, userID: String) async throws {
        let reference = try collection(for: userID).document(id)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try reference.setData(from: value, merge: false) { error in
                    if let error {
                        continuation.resume(throwing: AppError.map(error))
                    } else {
                        continuation.resume()
                    }
                }
            } catch {
                continuation.resume(throwing: AppError.map(error))
            }
        }
    }

    func delete(id: String, userID: String) async throws {
        do {
            try await collection(for: userID).document(id).delete()
        } catch {
            throw AppError.map(error)
        }
    }

    /// `dateField` alanı `since` tarihinden sonra olan belgeler.
    func fetch<T: Decodable>(_ type: T.Type, userID: String, since: Date, dateField: String = "date") async throws -> [T] {
        do {
            let snapshot = try await collection(for: userID)
                .whereField(dateField, isGreaterThanOrEqualTo: since)
                .getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: T.self) }
        } catch {
            throw AppError.map(error)
        }
    }

    /// Tüm belgeler.
    func fetchAll<T: Decodable>(_ type: T.Type, userID: String) async throws -> [T] {
        do {
            let snapshot = try await collection(for: userID).getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: T.self) }
        } catch {
            throw AppError.map(error)
        }
    }

    /// Tek bir belge (yoksa `nil`).
    func fetchDocument<T: Decodable>(_ type: T.Type, id: String, userID: String) async throws -> T? {
        do {
            let snapshot = try await collection(for: userID).document(id).getDocument()
            guard snapshot.exists else { return nil }
            return try snapshot.data(as: T.self)
        } catch {
            throw AppError.map(error)
        }
    }
}
