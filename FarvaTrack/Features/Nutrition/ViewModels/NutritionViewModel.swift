import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class NutritionViewModel {
    var selectedDate = Date.now
    var errorMessage: String?
    private(set) var calorieGoal = Constants.Defaults.calorieGoal
    private(set) var macroTargets = CalorieCalculator.macroTargets(
        calories: Constants.Defaults.calorieGoal, goal: .maintain
    )
    private(set) var isSyncing = false

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var deletions: PendingDeletionStore?
    @ObservationIgnored private let sync: MealSyncing

    init(sync: MealSyncing = FirestoreMealSyncService()) {
        self.sync = sync
    }

    var currentUserID: String? { userID }

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    var canGoForward: Bool { !Calendar.current.isDateInToday(selectedDate) }

    func configure(context: ModelContext, user: AppUser) {
        self.context = context
        if userID != user.id {
            userID = user.id
            deletions = PendingDeletionStore(userID: user.id, scope: "Meal")
        }
        calorieGoal = max(user.dailyCalorieGoal, 1)
        macroTargets = CalorieCalculator.macroTargets(calories: calorieGoal, goal: user.goal)
    }

    // MARK: - Gün gezgini
    func shiftDay(by days: Int) {
        guard let shifted = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        guard shifted.startOfDay <= Date.now.startOfDay else { return }
        Haptics.selection()
        selectedDate = shifted
    }

    /// Bugüne eklenen kayıt şimdiki zamanı, geçmiş güne eklenen ise öğünün varsayılan saatini alır.
    func entryDate(day: Date, mealType: MealType) -> Date {
        if Calendar.current.isDateInToday(day) { return .now }
        return Calendar.current.date(bySettingHour: mealType.defaultHour, minute: 0, second: 0, of: day) ?? day
    }

    // MARK: - Öğün CRUD
    @discardableResult
    func addMeal(template: FoodTemplate, quantity: Double, mealType: MealType, day: Date) throws -> MealEntry {
        guard let context, let userID else { throw AppError.notAuthenticated }
        try validate(quantity)

        let entry = MealEntry(
            ownerID: userID,
            date: entryDate(day: day, mealType: mealType),
            mealType: mealType,
            template: template,
            quantity: quantity
        )
        context.insert(entry)
        try commit()
        Haptics.success()
        scheduleUpload(entry)
        return entry
    }

    func updateMeal(_ entry: MealEntry, quantity: Double, mealType: MealType) throws {
        try validate(quantity)
        entry.quantity = quantity
        entry.mealType = mealType
        entry.updatedAt = .now
        entry.needsSync = true
        try commit()
        Haptics.success()
        scheduleUpload(entry)
    }

    func delete(_ entry: MealEntry) {
        guard let context, let userID else { return }
        let id = entry.id.uuidString
        context.delete(entry)
        do {
            try commit()
        } catch {
            present(error)
            return
        }
        Haptics.impact(.medium)
        deletions?.add(id)
        scheduleDelete(id: id, userID: userID)
    }

    // MARK: - Favoriler ve özel yiyecekler
    func toggleFavorite(_ template: FoodTemplate) {
        guard let context, let userID else { return }
        let key = "\(userID)|\(template.key)"
        let existing = try? context.fetch(
            FetchDescriptor<FavoriteFood>(predicate: #Predicate { $0.compositeKey == key })
        ).first
        if let existing {
            context.delete(existing)
        } else {
            context.insert(FavoriteFood(ownerID: userID, template: template))
        }
        try? context.save()
        Haptics.selection()
    }

    @discardableResult
    func createCustomFood(
        name: String, servingLabel: String,
        calories: Double, protein: Double, carbs: Double, fat: Double
    ) throws -> FoodTemplate {
        guard let context, let userID else { throw AppError.notAuthenticated }

        let cleanName = name.trimmed
        guard (2...60).contains(cleanName.count) else {
            throw AppError.invalidInput("Yiyecek adı 2–60 karakter olmalı.")
        }
        guard (0...5_000).contains(calories), (0...1_000).contains(protein),
              (0...1_000).contains(carbs), (0...1_000).contains(fat) else {
            throw AppError.invalidInput("Besin değerleri makul bir aralıkta ve sıfırdan küçük olmayan sayılar olmalı.")
        }

        let existing = (try? context.fetch(
            FetchDescriptor<CustomFood>(predicate: #Predicate { $0.ownerID == userID })
        )) ?? []
        let taken = FoodLibrary.all.map(\.name) + existing.map(\.name)
        guard !taken.contains(where: { $0.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            throw AppError.invalidInput("Bu isimde bir yiyecek zaten var.")
        }

        let serving = servingLabel.trimmed.isEmpty ? "1 porsiyon" : servingLabel.trimmed
        let food = CustomFood(
            ownerID: userID, name: cleanName, servingLabel: serving,
            calories: calories, protein: protein, carbs: carbs, fat: fat
        )
        context.insert(food)
        try commit()
        Haptics.success()
        return food.template
    }

    func deleteCustomFood(_ food: CustomFood) {
        guard let context else { return }
        context.delete(food)
        try? context.save()
    }

    // MARK: - Senkronizasyon
    func syncAll() async {
        guard let context, let userID, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let pending = deletions?.ids ?? []
        for id in pending { scheduleDelete(id: id, userID: userID) }

        do {
            let since = Calendar.current.date(byAdding: .day, value: -60, to: Date.now.startOfDay) ?? .distantPast
            let remote = try await sync.fetchMeals(userID: userID, since: since)
            let local = try context.fetch(FetchDescriptor<MealEntry>(predicate: #Predicate { $0.ownerID == userID }))
            let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            for dto in remote where !pending.contains(dto.id) {
                guard let uuid = UUID(uuidString: dto.id) else { continue }
                if let existing = localByID[uuid] {
                    // Bekleyen yerel değişiklik varsa yerel kazanır; yoksa daha yeni olan kazanır.
                    if !existing.needsSync, dto.updatedAt > existing.updatedAt {
                        existing.apply(dto)
                    }
                } else {
                    context.insert(MealEntry.make(from: dto, ownerID: userID))
                }
            }
            try context.save()
            for entry in local where entry.needsSync { scheduleUpload(entry) }
        } catch {
            // Çevrimdışı olabilir; bir sonraki açılışta tekrar denenir.
        }
    }

    // MARK: - Yardımcılar
    private func validate(_ quantity: Double) throws {
        guard (0.25...20).contains(quantity) else {
            throw AppError.invalidInput("Miktar 0,25 ile 20 porsiyon arasında olmalı.")
        }
    }

    private func commit() throws {
        guard let context else { throw AppError.notAuthenticated }
        do {
            try context.save()
        } catch {
            throw AppError.unknown(error.localizedDescription)
        }
    }

    private func scheduleUpload(_ entry: MealEntry) {
        guard let userID else { return }
        let dto = entry.dto
        let id = entry.id
        let updatedAt = entry.updatedAt

        Task {
            do {
                try await sync.upload(dto, userID: userID)
                markSynced(id: id, updatedAt: updatedAt)
            } catch {
                // needsSync true kalır; sonraki syncAll'da yeniden denenir.
            }
        }
    }

    private func markSynced(id: UUID, updatedAt: Date) {
        guard let context else { return }
        let descriptor = FetchDescriptor<MealEntry>(predicate: #Predicate { $0.id == id })
        if let entry = try? context.fetch(descriptor).first, entry.updatedAt == updatedAt {
            entry.needsSync = false
            try? context.save()
        }
    }

    private func scheduleDelete(id: String, userID: String) {
        let store = deletions
        Task {
            do {
                try await sync.deleteMeal(id: id, userID: userID)
                store?.remove(id)
            } catch {
                // "bekleyen silme" olarak kalır.
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = AppError.map(error).errorDescription
        Haptics.error()
    }
}
