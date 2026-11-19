import Foundation
import FirebaseFirestore

protocol WorkoutSyncing {
    func upload(_ workout: WorkoutDTO, userID: String) async throws
    func deleteWorkout(id: String, userID: String) async throws
    func fetchWorkouts(userID: String) async throws -> [WorkoutDTO]
}

/// Çevrimdışıyken `upload` ve `deleteWorkout` sunucu onayı gelene kadar bekler (Firestore yazmayı
/// kendi kuyruğunda tutar). Bu yüzden çağıran taraf bunları arka plan Task'ında çalıştırmalıdır.
final class FirestoreWorkoutSyncService: WorkoutSyncing {

    private func collection(for userID: String) -> CollectionReference {
        Firestore.firestore()
            .collection(Constants.Collection.users)
            .document(userID)
            .collection(Constants.Collection.workouts)
    }

    func upload(_ workout: WorkoutDTO, userID: String) async throws {
        let reference = collection(for: userID).document(workout.id)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try reference.setData(from: workout, merge: false) { error in
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

    func deleteWorkout(id: String, userID: String) async throws {
        do {
            try await collection(for: userID).document(id).delete()
        } catch {
            throw AppError.map(error)
        }
    }

    func fetchWorkouts(userID: String) async throws -> [WorkoutDTO] {
        do {
            let snapshot = try await collection(for: userID).getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: WorkoutDTO.self) }
        } catch {
            throw AppError.map(error)
        }
    }
}

/// Sunucuya henüz iletilmemiş silmeleri hatırlar (silinen antrenman yeniden eşitlemede geri gelmesin).
struct PendingDeletionStore {
    private let key: String
    private let defaults: UserDefaults

    init(userID: String, defaults: UserDefaults = .standard) {
        self.key = "pendingWorkoutDeletes.\(userID)"
        self.defaults = defaults
    }

    var ids: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func add(_ id: String) {
        var current = ids
        current.insert(id)
        defaults.set(Array(current), forKey: key)
    }

    func remove(_ id: String) {
        var current = ids
        current.remove(id)
        defaults.set(Array(current), forKey: key)
    }
}