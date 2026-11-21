import Foundation

protocol WaterSyncing {
    func upload(_ entry: WaterDTO, userID: String) async throws
    func deleteEntry(id: String, userID: String) async throws
    func fetchEntries(userID: String, since: Date) async throws -> [WaterDTO]
}

final class FirestoreWaterSyncService: WaterSyncing {
    private let client = FirestoreCollectionClient(collectionName: Constants.Collection.water)

    func upload(_ entry: WaterDTO, userID: String) async throws {
        try await client.upload(entry, id: entry.id, userID: userID)
    }

    func deleteEntry(id: String, userID: String) async throws {
        try await client.delete(id: id, userID: userID)
    }

    func fetchEntries(userID: String, since: Date) async throws -> [WaterDTO] {
        try await client.fetch(WaterDTO.self, userID: userID, since: since)
    }
}
