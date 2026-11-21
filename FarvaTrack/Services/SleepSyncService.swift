import Foundation

protocol SleepSyncing {
    func upload(_ entry: SleepDTO, userID: String) async throws
    func deleteEntry(id: String, userID: String) async throws
    func fetchEntries(userID: String, since: Date) async throws -> [SleepDTO]
}

final class FirestoreSleepSyncService: SleepSyncing {
    private let client = FirestoreCollectionClient(collectionName: Constants.Collection.sleep)

    func upload(_ entry: SleepDTO, userID: String) async throws {
        try await client.upload(entry, id: entry.id, userID: userID)
    }

    func deleteEntry(id: String, userID: String) async throws {
        try await client.delete(id: id, userID: userID)
    }

    func fetchEntries(userID: String, since: Date) async throws -> [SleepDTO] {
        try await client.fetch(SleepDTO.self, userID: userID, since: since, dateField: "day")
    }
}
