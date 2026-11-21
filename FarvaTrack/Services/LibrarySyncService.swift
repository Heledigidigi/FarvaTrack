import Foundation
import SwiftData

/// `users/{uid}/library/{id}`: özel yiyecekler, favoriler ve özel egzersizler.
/// Kayıtlar düzenlenmez; yalnızca eklenir ve silinir. Bu yüzden eşitleme "eksik olanı tamamla" mantığıyla çalışır.
struct LibraryItemDTO: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case customFood, favorite, customExercise
    }

    var id: String
    var kind: Kind
    var name: String
    var updatedAt: Date

    // Yiyecek alanları (özel yiyecek ve favori)
    var foodKey: String?
    var servingLabel: String?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    // Egzersiz alanları
    var category: String?
    var mode: String?
    var met: Double?
}

enum LibraryID {
    static func customFood(_ id: UUID) -> String { "food-\(id.uuidString)" }
    static func customExercise(_ id: UUID) -> String { "exercise-\(id.uuidString)" }
    /// Firestore belge kimliğinde "/" olamaz; yiyecek anahtarları zaten "preset.x" / "custom.<uuid>" biçiminde.
    static func favorite(_ foodKey: String) -> String { "fav-" + foodKey.replacingOccurrences(of: "/", with: "_") }
}

extension CustomFood {
    var libraryDTO: LibraryItemDTO {
        LibraryItemDTO(
            id: LibraryID.customFood(id), kind: .customFood, name: name, updatedAt: createdAt,
            servingLabel: servingLabel, calories: calories, protein: protein, carbs: carbs, fat: fat
        )
    }
}

extension FavoriteFood {
    var libraryDTO: LibraryItemDTO {
        LibraryItemDTO(
            id: LibraryID.favorite(foodKey), kind: .favorite, name: name, updatedAt: addedAt,
            foodKey: foodKey, servingLabel: servingLabel, calories: calories, protein: protein, carbs: carbs, fat: fat
        )
    }
}

extension Exercise {
    var libraryDTO: LibraryItemDTO {
        LibraryItemDTO(
            id: LibraryID.customExercise(id), kind: .customExercise, name: name, updatedAt: createdAt,
            category: categoryRaw, mode: modeRaw, met: met
        )
    }
}

protocol LibrarySyncing {
    func upload(_ item: LibraryItemDTO, userID: String) async throws
    func delete(id: String, userID: String) async throws
    func fetchAll(userID: String) async throws -> [LibraryItemDTO]
}

final class FirestoreLibrarySyncService: LibrarySyncing {
    private let client = FirestoreCollectionClient(collectionName: Constants.Collection.library)

    func upload(_ item: LibraryItemDTO, userID: String) async throws {
        try await client.upload(item, id: item.id, userID: userID)
    }

    func delete(id: String, userID: String) async throws {
        try await client.delete(id: id, userID: userID)
    }

    func fetchAll(userID: String) async throws -> [LibraryItemDTO] {
        try await client.fetchAll(LibraryItemDTO.self, userID: userID)
    }
}

/// Kütüphane eşitleyicisi. Silmeler `PendingDeletionStore(scope: "Library")` kuyruğundan okunur;
/// ViewModel'ler yalnızca kuyruğa ekler, ağ işi burada yapılır.
@MainActor
final class LibrarySynchronizer {
    private let sync: LibrarySyncing
    private let defaults: UserDefaults
    private var isSyncing = false

    init(sync: LibrarySyncing = FirestoreLibrarySyncService(), defaults: UserDefaults = .standard) {
        self.sync = sync
        self.defaults = defaults
    }

    static func recordDeletion(_ id: String, userID: String, defaults: UserDefaults = .standard) {
        PendingDeletionStore(userID: userID, scope: "Library", defaults: defaults).add(id)
    }

    func syncAll(context: ModelContext, userID: String) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let pending = PendingDeletionStore(userID: userID, scope: "Library", defaults: defaults)
        var local = localItems(context: context, userID: userID)

        // 1) Silmeler. Yerelde yeniden eklenmişse (ör. tekrar favorilenmiş) silme iptal edilir.
        for id in pending.ids {
            if local[id] != nil {
                pending.remove(id)
                continue
            }
            do {
                try await sync.delete(id: id, userID: userID)
                pending.remove(id)
            } catch {}
        }

        // 2) Uzakta olup yerelde olmayanları ekle, yerelde olup uzakta olmayanları yükle.
        guard let remote = try? await sync.fetchAll(userID: userID) else { return }
        let stillPending = pending.ids
        let remoteIDs = Set(remote.map(\.id))

        for item in remote where local[item.id] == nil && !stillPending.contains(item.id) {
            if insert(item, context: context, userID: userID) { local[item.id] = item }
        }
        try? context.save()

        for (id, item) in local where !remoteIDs.contains(id) {
            try? await sync.upload(item, userID: userID)
        }
    }

    private func localItems(context: ModelContext, userID: String) -> [String: LibraryItemDTO] {
        var items: [String: LibraryItemDTO] = [:]
        let foods = (try? context.fetch(FetchDescriptor<CustomFood>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
        let favorites = (try? context.fetch(FetchDescriptor<FavoriteFood>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
        for dto in foods.map(\.libraryDTO) + favorites.map(\.libraryDTO) + exercises.map(\.libraryDTO) {
            items[dto.id] = dto
        }
        return items
    }

    /// Uzaktaki öğeyi yerel modele çevirir. Eksik alanlı (bozuk) öğe atlanır.
    private func insert(_ item: LibraryItemDTO, context: ModelContext, userID: String) -> Bool {
        switch item.kind {
        case .customFood:
            guard let uuid = UUID(uuidString: String(item.id.dropFirst("food-".count))),
                  let calories = item.calories else { return false }
            let food = CustomFood(
                ownerID: userID, name: item.name, servingLabel: item.servingLabel ?? "1 porsiyon",
                calories: calories, protein: item.protein ?? 0, carbs: item.carbs ?? 0, fat: item.fat ?? 0
            )
            food.id = uuid
            food.createdAt = item.updatedAt
            context.insert(food)

        case .favorite:
            guard let foodKey = item.foodKey, let calories = item.calories else { return false }
            let template = FoodTemplate(
                key: foodKey, name: item.name, servingLabel: item.servingLabel ?? "1 porsiyon",
                calories: calories, protein: item.protein ?? 0, carbs: item.carbs ?? 0, fat: item.fat ?? 0
            )
            let favorite = FavoriteFood(ownerID: userID, template: template)
            favorite.addedAt = item.updatedAt
            context.insert(favorite)

        case .customExercise:
            guard let uuid = UUID(uuidString: String(item.id.dropFirst("exercise-".count))),
                  let met = item.met else { return false }
            let exercise = Exercise(
                ownerID: userID, name: item.name,
                category: ExerciseCategory(rawValue: item.category ?? "") ?? .other,
                mode: TrackingMode(rawValue: item.mode ?? "") ?? .duration,
                met: met
            )
            exercise.id = uuid
            exercise.createdAt = item.updatedAt
            context.insert(exercise)
        }
        return true
    }
}
