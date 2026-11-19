import Foundation
import SwiftData

// MARK: - DTO (tek belge: users/{uid}/library/main)
struct LibraryDTO: Codable, Equatable {
    var exercises: [ExerciseItem]
    var foods: [FoodItem]
    var favorites: [FavoriteItem]
    var updatedAt: Date

    struct ExerciseItem: Codable, Equatable {
        var id: String
        var name: String
        var category: String
        var mode: String
        var met: Double
        var createdAt: Date
    }

    struct FoodItem: Codable, Equatable {
        var id: String
        var name: String
        var servingLabel: String
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var createdAt: Date
    }

    struct FavoriteItem: Codable, Equatable {
        var foodKey: String
        var name: String
        var servingLabel: String
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var addedAt: Date
    }
}

protocol LibraryRemoting {
    func fetch(userID: String) async throws -> LibraryDTO?
    func upload(_ library: LibraryDTO, userID: String) async throws
}

final class FirestoreLibraryRemote: LibraryRemoting {
    private let client = FirestoreCollectionClient(collectionName: Constants.Collection.library)

    func fetch(userID: String) async throws -> LibraryDTO? {
        try await client.fetchDocument(LibraryDTO.self, id: "main", userID: userID)
    }

    func upload(_ library: LibraryDTO, userID: String) async throws {
        try await client.upload(library, id: "main", userID: userID)
    }
}

/// Özel egzersiz, özel yiyecek ve favorileri tek belge olarak yedekler.
/// Kural: yerelde bekleyen değişiklik varsa yerel kazanır (silmeler dahil); yoksa daha yeni olan bulut sürümü alınır.
@MainActor
final class LibrarySyncService {
    static let shared = LibrarySyncService()

    private let remote: LibraryRemoting
    private let defaults: UserDefaults
    private var isSyncing = false

    init(remote: LibraryRemoting = FirestoreLibraryRemote(), defaults: UserDefaults = .standard) {
        self.remote = remote
        self.defaults = defaults
    }

    private func dirtyKey(_ userID: String) -> String { "librarySync.dirty.\(userID)" }
    private func stampKey(_ userID: String) -> String { "librarySync.localStamp.\(userID)" }
    private func appliedKey(_ userID: String) -> String { "librarySync.appliedRemote.\(userID)" }

    /// Yerelde bir değişiklik olduğunda çağrılır; hemen eşitlemeyi dener.
    func localChange(context: ModelContext, userID: String, now: Date = .now) {
        defaults.set(true, forKey: dirtyKey(userID))
        defaults.set(now, forKey: stampKey(userID))
        Task { await sync(context: context, userID: userID) }
    }

    func sync(context: ModelContext, userID: String) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Bulutta hiç belge yokken yerelde öğe varsa ilk yükleme için ikinci tur gerekir.
        for _ in 0..<2 {
            guard let again = try? await performSync(context: context, userID: userID), again else { return }
        }
    }

    /// `true` dönerse bir tur daha çalışması gerekir.
    private func performSync(context: ModelContext, userID: String) async throws -> Bool {
        if defaults.bool(forKey: dirtyKey(userID)) {
            let stamp = (defaults.object(forKey: stampKey(userID)) as? Date) ?? .now
            let snapshot = makeSnapshot(context: context, userID: userID, updatedAt: stamp)
            try await remote.upload(snapshot, userID: userID)

            // Yükleme sürerken yeni bir yerel değişiklik olduysa kirli işaretini koru.
            if (defaults.object(forKey: stampKey(userID)) as? Date) == stamp {
                defaults.set(false, forKey: dirtyKey(userID))
            }
            defaults.set(stamp, forKey: appliedKey(userID))
            return false
        }

        guard let remoteLibrary = try await remote.fetch(userID: userID) else {
            if hasLocalItems(context: context, userID: userID) {
                defaults.set(true, forKey: dirtyKey(userID))
                defaults.set(Date.now, forKey: stampKey(userID))
                return true
            }
            return false
        }

        let applied = (defaults.object(forKey: appliedKey(userID)) as? Date) ?? .distantPast
        if remoteLibrary.updatedAt > applied {
            apply(remoteLibrary, context: context, userID: userID)
            defaults.set(remoteLibrary.updatedAt, forKey: appliedKey(userID))
        }
        return false
    }

    // MARK: - Yerel ↔ DTO
    private func hasLocalItems(context: ModelContext, userID: String) -> Bool {
        let exercises = (try? context.fetchCount(FetchDescriptor<Exercise>(predicate: #Predicate { $0.ownerID == userID }))) ?? 0
        let foods = (try? context.fetchCount(FetchDescriptor<CustomFood>(predicate: #Predicate { $0.ownerID == userID }))) ?? 0
        let favorites = (try? context.fetchCount(FetchDescriptor<FavoriteFood>(predicate: #Predicate { $0.ownerID == userID }))) ?? 0
        return exercises + foods + favorites > 0
    }

    func makeSnapshot(context: ModelContext, userID: String, updatedAt: Date) -> LibraryDTO {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
        let foods = (try? context.fetch(FetchDescriptor<CustomFood>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
        let favorites = (try? context.fetch(FetchDescriptor<FavoriteFood>(predicate: #Predicate { $0.ownerID == userID }))) ?? []

        return LibraryDTO(
            exercises: exercises.map {
                .init(id: $0.id.uuidString, name: $0.name, category: $0.categoryRaw, mode: $0.modeRaw, met: $0.met, createdAt: $0.createdAt)
            },
            foods: foods.map {
                .init(id: $0.id.uuidString, name: $0.name, servingLabel: $0.servingLabel, calories: $0.calories,
                      protein: $0.protein, carbs: $0.carbs, fat: $0.fat, createdAt: $0.createdAt)
            },
            favorites: favorites.map {
                .init(foodKey: $0.foodKey, name: $0.name, servingLabel: $0.servingLabel, calories: $0.calories,
                      protein: $0.protein, carbs: $0.carbs, fat: $0.fat, addedAt: $0.addedAt)
            },
            updatedAt: updatedAt
        )
    }

    /// Yerel kümeyi bulut sürümüyle birebir eşitler (eksikleri ekler, fazlaları siler, var olanları günceller).
    private func apply(_ dto: LibraryDTO, context: ModelContext, userID: String) {
        // Egzersizler
        let localExercises = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
        let remoteExerciseIDs = Set(dto.exercises.compactMap { UUID(uuidString: $0.id) })
        for exercise in localExercises where !remoteExerciseIDs.contains(exercise.id) { context.delete(exercise) }
        let exercisesByID = Dictionary(localExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in dto.exercises {
            guard let uuid = UUID(uuidString: item.id) else { continue }
            if let existing = exercisesByID[uuid] {
                existing.name = item.name
                existing.categoryRaw = item.category
                existing.modeRaw = item.mode
                existing.met = item.met
            } else {
                let exercise = Exercise(
                    ownerID: userID, name: item.name,
                    category: ExerciseCategory(rawValue: item.category) ?? .other,
                    mode: TrackingMode(rawValue: item.mode) ?? .duration, met: item.met
                )
                exercise.id = uuid
                exercise.createdAt = item.createdAt
                context.insert(exercise)
            }
        }

        // Özel yiyecekler
        let localFoods = (try? context.fetch(FetchDescriptor<CustomFood>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
        let remoteFoodIDs = Set(dto.foods.compactMap { UUID(uuidString: $0.id) })
        for food in localFoods where !remoteFoodIDs.contains(food.id) { context.delete(food) }
        let foodsByID = Dictionary(localFoods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in dto.foods {
            guard let uuid = UUID(uuidString: item.id) else { continue }
            if let existing = foodsByID[uuid] {
                existing.name = item.name
                existing.servingLabel = item.servingLabel
                existing.calories = item.calories
                existing.protein = item.protein
                existing.carbs = item.carbs
                existing.fat = item.fat
            } else {
                let food = CustomFood(
                    ownerID: userID, name: item.name, servingLabel: item.servingLabel,
                    calories: item.calories, protein: item.protein, carbs: item.carbs, fat: item.fat
                )
                food.id = uuid
                food.createdAt = item.createdAt
                context.insert(food)
            }
        }

        // Favoriler
        let localFavorites = (try? context.fetch(FetchDescriptor<FavoriteFood>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
        let remoteKeys = Set(dto.favorites.map(\.foodKey))
        for favorite in localFavorites where !remoteKeys.contains(favorite.foodKey) { context.delete(favorite) }
        let localKeys = Set(localFavorites.map(\.foodKey))
        for item in dto.favorites where !localKeys.contains(item.foodKey) {
            let template = FoodTemplate(
                key: item.foodKey, name: item.name, servingLabel: item.servingLabel,
                calories: item.calories, protein: item.protein, carbs: item.carbs, fat: item.fat
            )
            let favorite = FavoriteFood(ownerID: userID, template: template)
            favorite.addedAt = item.addedAt
            context.insert(favorite)
        }

        try? context.save()
    }
}