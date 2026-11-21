import Foundation
import FirebaseFirestore

protocol WasteSyncing {
    func uploadEntry(_ entry: WasteDTO, userID: String) async throws
    func deleteEntry(id: String, userID: String) async throws
    func fetchEntries(userID: String, since: Date) async throws -> [WasteDTO]
    func uploadDaily(_ daily: WasteDailyDTO, userID: String) async throws
    /// Yönetici: tüm kullanıcılar ve son günlerin günlük toplamları.
    func fetchAllUsersDaily(since: Date) async throws -> [WasteUserSummary]
}

final class FirestoreWasteSyncService: WasteSyncing {
    private let entries = FirestoreCollectionClient(collectionName: Constants.Collection.waste)
    private let daily = FirestoreCollectionClient(collectionName: Constants.Collection.wasteDaily)

    func uploadEntry(_ entry: WasteDTO, userID: String) async throws {
        try await entries.upload(entry, id: entry.id, userID: userID)
    }

    func deleteEntry(id: String, userID: String) async throws {
        try await entries.delete(id: id, userID: userID)
    }

    func fetchEntries(userID: String, since: Date) async throws -> [WasteDTO] {
        try await entries.fetch(WasteDTO.self, userID: userID, since: since)
    }

    func uploadDaily(_ dto: WasteDailyDTO, userID: String) async throws {
        try await daily.upload(dto, id: dto.id, userID: userID)
    }

    /// Firestore kuralları bu okumayı yalnızca `role: admin` hesaplara izin verir.
    func fetchAllUsersDaily(since: Date) async throws -> [WasteUserSummary] {
        guard FirebaseBootstrap.isConfigured else { throw AppError.firebaseNotConfigured }
        do {
            let snapshot = try await Firestore.firestore().collection(Constants.Collection.users).getDocuments()
            var result: [WasteUserSummary] = []
            for document in snapshot.documents {
                let data = document.data()
                let days = try await daily.fetch(WasteDailyDTO.self, userID: document.documentID, since: since, dateField: "day")
                result.append(WasteUserSummary(
                    id: document.documentID,
                    displayName: data["displayName"] as? String ?? "",
                    email: data["email"] as? String ?? "",
                    days: days.sorted { $0.id < $1.id }
                ))
            }
            return result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            throw AppError.map(error)
        }
    }
}
