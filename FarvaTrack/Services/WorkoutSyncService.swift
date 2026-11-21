import Foundation

protocol WorkoutSyncing {
    func upload(_ workout: WorkoutDTO, userID: String) async throws
    func deleteWorkout(id: String, userID: String) async throws
    func fetchWorkouts(userID: String) async throws -> [WorkoutDTO]
}

final class FirestoreWorkoutSyncService: WorkoutSyncing {
    private let client = FirestoreCollectionClient(collectionName: Constants.Collection.workouts)

    func upload(_ workout: WorkoutDTO, userID: String) async throws {
        try await client.upload(workout, id: workout.id, userID: userID)
    }

    func deleteWorkout(id: String, userID: String) async throws {
        try await client.delete(id: id, userID: userID)
    }

    func fetchWorkouts(userID: String) async throws -> [WorkoutDTO] {
        try await client.fetchAll(WorkoutDTO.self, userID: userID)
    }
}
