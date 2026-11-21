import Foundation

protocol MealSyncing {
    func upload(_ meal: MealDTO, userID: String) async throws
    func deleteMeal(id: String, userID: String) async throws
    func fetchMeals(userID: String, since: Date) async throws -> [MealDTO]
}

final class FirestoreMealSyncService: MealSyncing {
    private let client = FirestoreCollectionClient(collectionName: Constants.Collection.meals)

    func upload(_ meal: MealDTO, userID: String) async throws {
        try await client.upload(meal, id: meal.id, userID: userID)
    }

    func deleteMeal(id: String, userID: String) async throws {
        try await client.delete(id: id, userID: userID)
    }

    func fetchMeals(userID: String, since: Date) async throws -> [MealDTO] {
        try await client.fetch(MealDTO.self, userID: userID, since: since)
    }
}
