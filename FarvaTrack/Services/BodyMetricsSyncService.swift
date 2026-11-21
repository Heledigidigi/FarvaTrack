import Foundation

protocol BodyMetricsSyncing {
    func uploadWeight(_ entry: WeightDTO, userID: String) async throws
    func deleteWeight(id: String, userID: String) async throws
    func fetchWeights(userID: String, since: Date) async throws -> [WeightDTO]

    func uploadMeasurement(_ entry: MeasurementDTO, userID: String) async throws
    func deleteMeasurement(id: String, userID: String) async throws
    func fetchMeasurements(userID: String, since: Date) async throws -> [MeasurementDTO]
}

final class FirestoreBodyMetricsSyncService: BodyMetricsSyncing {
    private let weights = FirestoreCollectionClient(collectionName: Constants.Collection.weight)
    private let measurements = FirestoreCollectionClient(collectionName: Constants.Collection.measurements)

    func uploadWeight(_ entry: WeightDTO, userID: String) async throws {
        try await weights.upload(entry, id: entry.id, userID: userID)
    }

    func deleteWeight(id: String, userID: String) async throws {
        try await weights.delete(id: id, userID: userID)
    }

    /// Kayıt tarihleri geriye dönük girilebildiği için `updatedAt` alanına göre çekilir.
    func fetchWeights(userID: String, since: Date) async throws -> [WeightDTO] {
        try await weights.fetch(WeightDTO.self, userID: userID, since: since, dateField: "updatedAt")
    }

    func uploadMeasurement(_ entry: MeasurementDTO, userID: String) async throws {
        try await measurements.upload(entry, id: entry.id, userID: userID)
    }

    func deleteMeasurement(id: String, userID: String) async throws {
        try await measurements.delete(id: id, userID: userID)
    }

    func fetchMeasurements(userID: String, since: Date) async throws -> [MeasurementDTO] {
        try await measurements.fetch(MeasurementDTO.self, userID: userID, since: since, dateField: "updatedAt")
    }
}
