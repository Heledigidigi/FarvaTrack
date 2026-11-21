import XCTest
import SwiftData
@testable import FarvaTrack

final class MockMealSync: MealSyncing {
    var remote: [MealDTO] = []
    private(set) var uploaded: [MealDTO] = []
    private(set) var deleted: [String] = []

    func upload(_ meal: MealDTO, userID: String) async throws { uploaded.append(meal) }
    func deleteMeal(id: String, userID: String) async throws { deleted.append(id) }
    func fetchMeals(userID: String, since: Date) async throws -> [MealDTO] { remote }
}

@MainActor
final class NutritionViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var sync: MockMealSync!
    private var sut: NutritionViewModel!

    private var egg: FoodTemplate { FoodLibrary.template(forKey: "preset.boiled-egg")! }

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "pendingMealDeletes.uid-1")
        container = try ModelContainer(
            for: MealEntry.self, CustomFood.self, FavoriteFood.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        sync = MockMealSync()

        var user = AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test")
        user.dailyCalorieGoal = 2_000
        user.goal = .maintain
        sut = NutritionViewModel(sync: sync)
        sut.configure(context: context, user: user)
    }

    private func meals() throws -> [MealEntry] { try context.fetch(FetchDescriptor<MealEntry>()) }

    func testAddMealScalesNutrition() throws {
        let entry = try sut.addMeal(template: egg, quantity: 2, mealType: .breakfast, day: .now)
        XCTAssertEqual(entry.calories, 156, accuracy: 0.01)
        XCTAssertEqual(entry.protein, 12.6, accuracy: 0.01)
        XCTAssertTrue(entry.needsSync)
        XCTAssertEqual(try meals().count, 1)
    }

    func testAddMealUploadsAndMarksSynced() async throws {
        let entry = try sut.addMeal(template: egg, quantity: 1, mealType: .breakfast, day: .now)
        await settleTasks()
        XCTAssertEqual(sync.uploaded.map(\.id), [entry.id.uuidString])
        XCTAssertFalse(entry.needsSync)
    }

    func testQuantityValidation() {
        XCTAssertThrowsError(try sut.addMeal(template: egg, quantity: 0, mealType: .snack, day: .now))
        XCTAssertThrowsError(try sut.addMeal(template: egg, quantity: 25, mealType: .snack, day: .now))
    }

    func testPastDayUsesMealDefaultHour() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let entry = try sut.addMeal(template: egg, quantity: 1, mealType: .dinner, day: yesterday)
        XCTAssertEqual(Calendar.current.component(.hour, from: entry.date), 19)
    }

    func testCannotNavigateIntoFuture() {
        sut.shiftDay(by: 1)
        XCTAssertTrue(Calendar.current.isDateInToday(sut.selectedDate))
        sut.shiftDay(by: -1)
        XCTAssertTrue(sut.canGoForward)
    }

    func testUpdateMeal() throws {
        let entry = try sut.addMeal(template: egg, quantity: 1, mealType: .breakfast, day: .now)
        try sut.updateMeal(entry, quantity: 3, mealType: .snack)
        XCTAssertEqual(entry.calories, 234, accuracy: 0.01)
        XCTAssertEqual(entry.mealType, .snack)
    }

    func testDeleteQueuesRemoteDeletion() async throws {
        let entry = try sut.addMeal(template: egg, quantity: 1, mealType: .breakfast, day: .now)
        let id = entry.id.uuidString
        sut.delete(entry)
        await settleTasks()
        XCTAssertEqual(try meals().count, 0)
        XCTAssertEqual(sync.deleted, [id])
    }

    func testCustomFoodValidationAndDuplicates() throws {
        XCTAssertThrowsError(try sut.createCustomFood(name: "A", servingLabel: "", calories: 100, protein: 1, carbs: 1, fat: 1))
        XCTAssertThrowsError(try sut.createCustomFood(name: "Menemen", servingLabel: "", calories: 100, protein: 1, carbs: 1, fat: 1))
        XCTAssertThrowsError(try sut.createCustomFood(name: "Kek", servingLabel: "", calories: -5, protein: 1, carbs: 1, fat: 1))

        let food = try sut.createCustomFood(name: "Annemin keki", servingLabel: " ", calories: 300, protein: 5, carbs: 40, fat: 12)
        XCTAssertTrue(food.isCustom)
        XCTAssertEqual(food.servingLabel, "1 porsiyon")
        XCTAssertThrowsError(try sut.createCustomFood(name: "annemin KEKI", servingLabel: "", calories: 1, protein: 0, carbs: 0, fat: 0))
    }

    func testFavoriteToggle() throws {
        sut.toggleFavorite(egg)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FavoriteFood>()).count, 1)
        sut.toggleFavorite(egg)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FavoriteFood>()).count, 0)
    }

    func testSyncInsertsRemoteAndKeepsPendingLocal() async throws {
        let local = try sut.addMeal(template: egg, quantity: 1, mealType: .breakfast, day: .now)
        local.updatedAt = .now.addingTimeInterval(1)   // yüklenmemiş yerel değişiklik
        local.needsSync = true

        var newer = local.dto
        newer.quantity = 5
        newer.updatedAt = .now.addingTimeInterval(3_600)

        let remoteOnly = MealDTO(
            id: UUID().uuidString, date: .now, mealType: MealType.lunch.rawValue, foodKey: egg.key,
            name: egg.name, servingLabel: egg.servingLabel, quantity: 1,
            caloriesPerServing: egg.calories, proteinPerServing: egg.protein,
            carbsPerServing: egg.carbs, fatPerServing: egg.fat,
            createdAt: .now, updatedAt: .now
        )
        sync.remote = [newer, remoteOnly]
        await sut.syncAll()

        XCTAssertEqual(try meals().count, 2)
        XCTAssertEqual(local.quantity, 1, "bekleyen yerel değişiklik kazanmalı")
    }

    func testSyncAppliesNewerRemoteWhenNoLocalChange() async throws {
        let local = try sut.addMeal(template: egg, quantity: 1, mealType: .breakfast, day: .now)
        await settleTasks()
        XCTAssertFalse(local.needsSync)

        var newer = local.dto
        newer.quantity = 4
        newer.updatedAt = local.updatedAt.addingTimeInterval(60)
        sync.remote = [newer]
        await sut.syncAll()
        XCTAssertEqual(local.quantity, 4)
    }
}

final class FoodLibraryAndMacroTests: XCTestCase {
    func testLibraryKeysAreUniqueAndValid() {
        let keys = FoodLibrary.all.map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count)
        XCTAssertGreaterThan(keys.count, 50)
        for food in FoodLibrary.all {
            XCTAssertTrue(food.key.hasPrefix("preset."))
            XCTAssertGreaterThanOrEqual(food.calories, 0, food.name)
            XCTAssertGreaterThanOrEqual(food.protein, 0, food.name)
            XCTAssertGreaterThanOrEqual(food.carbs, 0, food.name)
            XCTAssertGreaterThanOrEqual(food.fat, 0, food.name)
        }
    }

    func testMacroEnergyIsPlausible() {
        // Makrolardan hesaplanan enerji, kayıtlı kaloriden çok sapmamalı (veri girişi hatası yakalar).
        for food in FoodLibrary.all where food.calories >= 40 {
            let energy = food.protein * 4 + food.carbs * 4 + food.fat * 9
            XCTAssertEqual(energy, food.calories, accuracy: max(food.calories * 0.35, 25), food.name)
        }
    }

    func testMacroTargetsSplit() {
        let targets = CalorieCalculator.macroTargets(calories: 2_000, goal: .maintain)
        XCTAssertEqual(targets.proteinG, 100)
        XCTAssertEqual(targets.carbsG, 250)
        XCTAssertEqual(targets.fatG, 67)
    }
}
