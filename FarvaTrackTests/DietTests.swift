import XCTest
import SwiftData
import Compression
@testable import FarvaTrack

// MARK: - Sahte diyet servisi

final class MockDietSync: DietSyncing {
    var remotePrograms: [DietProgram] = []
    var remoteLogs: [String: [DietMealLog]] = [:]
    var sharedPrograms: [DietProgram] = []
    var offers: [String: DietOffer] = [:]
    var isOffline = false
    private(set) var uploadedPrograms: [DietProgram] = []
    private(set) var uploadedLogs: [DietMealLog] = []
    private(set) var uploadedNotes: [DietDayNote] = []
    private(set) var comments: [DietComment] = []
    private(set) var suggestions: [DietSuggestion] = []
    private(set) var decisions: [(String, DietSuggestionStatus)] = []
    private(set) var offerDecisions: [(String, DietOfferStatus, String?)] = []
    private(set) var deletedPrograms: [String] = []

    private func check() throws { if isOffline { throw AppError.network } }

    func uploadProgram(_ program: DietProgram) async throws { try check(); mockLock.withLock { uploadedPrograms.append(program) } }
    func deleteProgram(id: String) async throws { try check(); mockLock.withLock { deletedPrograms.append(id) } }
    func fetchMyPrograms(userID: String) async throws -> [DietProgram] { try check(); return remotePrograms }
    func fetchSharedPrograms(viewerID: String) async throws -> [DietProgram] { try check(); return sharedPrograms }
    func fetchProgram(id: String) async throws -> DietProgram? { (remotePrograms + sharedPrograms).first { $0.id == id } }
    func uploadLog(_ log: DietMealLog) async throws { try check(); mockLock.withLock { uploadedLogs.append(log) } }
    func deleteLog(id: String, programID: String) async throws { try check() }
    func fetchLogs(programID: String) async throws -> [DietMealLog] { try check(); return remoteLogs[programID] ?? [] }
    func uploadNote(_ note: DietDayNote) async throws { try check(); mockLock.withLock { uploadedNotes.append(note) } }
    func fetchNotes(programID: String) async throws -> [DietDayNote] { [] }
    func addComment(_ comment: DietComment) async throws { try check(); mockLock.withLock { comments.append(comment) } }
    func deleteComment(id: String, programID: String) async throws {}
    func fetchComments(programID: String) async throws -> [DietComment] { comments.filter { $0.programID == programID } }
    func createSuggestion(_ suggestion: DietSuggestion) async throws { mockLock.withLock { suggestions.append(suggestion) } }
    func fetchSuggestions(programID: String) async throws -> [DietSuggestion] { suggestions.filter { $0.programID == programID } }
    func decideSuggestion(id: String, programID: String, status: DietSuggestionStatus, at: Date) async throws {
        mockLock.withLock { decisions.append((id, status)) }
    }
    func createOffer(_ offer: DietOffer) async throws { try check(); mockLock.withLock { offers[offer.id] = offer } }
    func fetchOffer(id: String) async throws -> DietOffer? { offers[id] }
    func decideOffer(id: String, status: DietOfferStatus, programID: String?, at: Date) async throws {
        mockLock.withLock { offerDecisions.append((id, status, programID)) }
    }
    func purge(userID: String) async throws {}
}

// MARK: - Örnek veri

private enum DietFixtures {
    static func food(_ key: String) -> DietFood {
        DietFood(template: FoodLibrary.template(forKey: "preset.\(key)")!)
    }

    static func plan(days: Int = 3) -> DietPlan {
        let breakfast = DietMeal(id: "kahvalti", name: "Kahvaltı", minutes: 8 * 60, items: [
            DietItem(portion: DietPortion(food: food("boiled-egg"), amount: 2, unit: .piece)),
            DietItem(portion: DietPortion(food: food("white-cheese"), amount: 1, unit: .slice),
                     alternatives: [DietPortion(food: food("kashar"), amount: 1, unit: .slice)])
        ])
        let lunch = DietMeal(id: "ogle", name: "Öğle", minutes: 13 * 60, items: [
            DietItem(portion: DietPortion(food: food("chicken-breast"), amount: 120, unit: .gram)),
            DietItem(portion: DietPortion(food: food("bulgur-pilaf"), amount: 5, unit: .tablespoon))
        ])
        return DietPlan(days: (0..<days).map { _ in DietDay(meals: [breakfast, lunch]) })
    }
}

// MARK: - Birimler ve plan

final class DietModelTests: XCTestCase {
    func testServingLabelParsing() {
        XCTAssertEqual(DietServing.parse("5 adet (20 g)"), DietServing(count: 5, unit: .piece, grams: 20))
        XCTAssertEqual(DietServing.parse("1 su bardağı (200 ml)").unit, .waterGlass)
        XCTAssertEqual(DietServing.parse("1 porsiyon (150 g)").grams, 150)
        XCTAssertNil(DietServing.parse("1 adet").grams)
        XCTAssertEqual(DietUnit.parse("Yemek Kaşığı"), .tablespoon)
        XCTAssertEqual(DietUnit.parse("yk"), .tablespoon)
        XCTAssertEqual(DietUnit.parse("gr"), .gram)
        XCTAssertEqual(DietUnit.parse("su bardağı"), .waterGlass)
        XCTAssertNil(DietUnit.parse("bilinmeyen birim"))
    }

    func testUnitConversionUsesFoodServing() {
        let bulgur = DietPortion(food: DietFixtures.food("bulgur-pilaf"), amount: 5, unit: .tablespoon)
        XCTAssertEqual(bulgur.grams, 75, "pilavda 1 yk = 15 g")
        XCTAssertEqual(bulgur.servings, 0.5, accuracy: 0.001, "porsiyon 150 g")
        XCTAssertEqual(bulgur.nutrition.calories, 100, accuracy: 0.5)
        XCTAssertEqual(bulgur.gramsHint, "≈ 75 g")

        let olives = DietPortion(food: DietFixtures.food("black-olive"), amount: 10, unit: .piece)
        XCTAssertEqual(olives.servings, 2, accuracy: 0.001, "porsiyon 5 adet")
        let eggs = DietPortion(food: DietFixtures.food("boiled-egg"), amount: 2, unit: .piece)
        XCTAssertEqual(eggs.nutrition.calories, 156, accuracy: 0.5)
        let chicken = DietPortion(food: DietFixtures.food("chicken-breast"), amount: 120, unit: .gram)
        XCTAssertEqual(chicken.nutrition.protein, 37.2, accuracy: 0.1)
        XCTAssertNil(chicken.gramsHint)
    }

    func testEqualCalorieAmount() {
        let target = DietUnitTable.equalCalorieAmount(for: 160, food: DietFixtures.food("rice-pilaf"))
        let portion = DietPortion(food: DietFixtures.food("rice-pilaf"), amount: target.amount, unit: target.unit)
        XCTAssertEqual(portion.nutrition.calories, 160, accuracy: 25)
    }

    func testPlanCodableRoundTripStoresFoodsOnce() throws {
        let plan = DietFixtures.plan(days: 28)
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(DietPlan.self, from: data)
        XCTAssertEqual(decoded, plan)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["foods"] as? [String: Any])?.count, 5, "yiyecek tablosu tek")
        XCTAssertLessThan(data.count, 40_000, "28 günlük plan Firestore belgesine rahat sığar")
    }

    func testProgramDaysVersionsAndLoop() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        var program = DietProgram(ownerID: "u1", name: "Test", startDate: start, endBehavior: .stop, plan: DietFixtures.plan(days: 3))
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: start)! }
        XCTAssertNil(program.programDay(on: day(-1)))
        XCTAssertEqual(program.programDay(on: day(0)), 1)
        XCTAssertEqual(program.programDay(on: day(2)), 3)
        XCTAssertNil(program.programDay(on: day(3)), "bitince dur")
        program.endBehavior = .loop
        XCTAssertEqual(program.programDay(on: day(4)), 2)
        XCTAssertEqual(program.cycle(on: day(4)), 1)

        var changed = DietFixtures.plan(days: 3)
        changed.days[1].meals[1].items.removeLast()
        program.apply(plan: changed, effectiveFrom: day(1), authorID: "u1", authorName: nil, note: "ekmek azaldı")
        XCTAssertEqual(program.versions.count, 2)
        XCTAssertEqual(program.version(on: day(0)).number, 1, "geçmiş gün eski sürümle")
        XCTAssertEqual(program.version(on: day(1)).number, 2)
        XCTAssertEqual(program.plannedDay(on: day(1))?.meals[1].items.count, 1)
        // Aynı güne ikinci düzenleme yeni sürüm açmaz.
        program.apply(plan: DietFixtures.plan(days: 3), effectiveFrom: day(1), authorID: "u1", authorName: nil, note: "geri")
        XCTAssertEqual(program.versions.count, 2)
    }

    func testProgramDecodesOldDocumentsWithDefaults() throws {
        let json = #"{"id":"p","ownerID":"u","startDate":0}"#
        let program = try DietJSON.decoder.decode(DietProgram.self, from: Data(json.utf8))
        XCTAssertEqual(program.viewerIDs, [])
        XCTAssertEqual(program.endBehavior, .stop)
        XCTAssertEqual(program.versions.count, 1)
    }

    func testPlanDiffGroupsAcrossDays() {
        let old = DietFixtures.plan(days: 4)
        var new = old
        for d in new.days.indices {
            new.days[d].meals[1].items[1].portion = DietPortion(food: DietFixtures.food("rice-pilaf"), amount: 4, unit: .tablespoon)
            new.days[d].meals[0].items[0].portion.amount = 1
        }
        let changes = DietPlanDiff.changes(from: old, to: new)
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.contains { $0.kind == .replaced && $0.text.hasPrefix("Bulgur pilavı → Pirinç pilavı") && $0.days.count == 4 })
        XCTAssertTrue(changes.contains { $0.kind == .changed && $0.text.contains("2 adet → 1 adet") })
    }
}

// MARK: - Toplu düzenleme

final class DietBulkEditTests: XCTestCase {
    func testReplaceFoodWithEqualCaloriesFromDay() {
        let plan = DietFixtures.plan(days: 5)
        let rice = DietFixtures.food("rice-pilaf")
        let result = DietBulkEdit.replaceFood(in: plan, key: "preset.bulgur-pilaf", with: rice, amount: .equalCalories,
                                              scope: DietBulkScope(days: .from(2)))
        XCTAssertEqual(result.days, [3, 4, 5])
        XCTAssertEqual(result.mealCount, 3)
        XCTAssertEqual(result.plan.days[0].meals[1].items[1].portion.food.key, "preset.bulgur-pilaf", "geçmiş gün değişmez")
        XCTAssertEqual(result.plan.days[4].meals[1].items[1].portion.food.key, "preset.rice-pilaf")
        XCTAssertLessThan(abs(result.averageDelta.calories), 25)
    }

    func testReplaceAlsoUpdatesAlternativesAndMealFilter() {
        let plan = DietFixtures.plan(days: 2)
        let lor = DietFood(key: "custom.lor", name: "Lor", servingLabel: "1 yemek kaşığı (15 g)", perServing: DietNutrition(calories: 14, protein: 2, carbs: 0.5, fat: 0.4))
        let result = DietBulkEdit.replaceFood(in: plan, key: "preset.kashar", with: lor, amount: .manual(3, .tablespoon),
                                              scope: DietBulkScope(days: .all, mealNames: [DietText.fold("Kahvaltı")]))
        XCTAssertEqual(result.plan.days[1].meals[0].items[1].alternatives.first?.food.key, "custom.lor")
        XCTAssertEqual(result.plan.days[1].meals[0].items[1].alternatives.first?.amount, 3)
    }

    func testAdjustPortionRemovesZeroAndCopyDay() {
        var plan = DietFixtures.plan(days: 3)
        plan.days[0].meals[0].items[0].portion.amount = 1
        let adjusted = DietBulkEdit.adjustPortion(in: plan, key: "preset.boiled-egg", delta: -1, scope: DietBulkScope())
        XCTAssertEqual(adjusted.plan.days[0].meals[0].items.count, 1, "sıfıra inen çıkar")
        XCTAssertEqual(adjusted.plan.days[1].meals[0].items[0].portion.amount, 1)

        let copied = DietBulkEdit.copyDay(0, to: [1, 2], in: adjusted.plan)
        XCTAssertEqual(copied.days, [2, 3])
        XCTAssertEqual(copied.plan.days[2].meals[0].items.count, 1)
        XCTAssertEqual(copied.plan.days[2].meals[0].id, "kahvalti", "öğün kimliği korunur")
    }
}

// MARK: - Excel

final class DietSpreadsheetTests: XCTestCase {
    func testXLSXRoundTrip() throws {
        let rows = [["Gün", "Öğün", "Yiyecek"], ["1", "Kahvaltı", "Tam buğday ekmeği & bal <özel>"], ["2", "", "Elma"]]
        let data = XLSX.write(sheets: [XLSX.Sheet(name: "Program", rows: rows)])
        let read = try XLSX.read(data)
        XCTAssertEqual(read[0], rows[0])
        XCTAssertEqual(read[1], rows[1])
        XCTAssertEqual(read[2].first, "2")
        XCTAssertEqual(read[2].last, "Elma")
    }

    func testZipReadsDeflatedEntries() throws {
        let text = Data(String(repeating: "FarvaTrack diyet ", count: 200).utf8)
        let deflated = try Self.deflate(text)
        XCTAssertLessThan(deflated.count, text.count)
        XCTAssertEqual(try ZipArchive.inflate(deflated, expected: text.count), text)
    }

    func testCSVWithSemicolonsAndQuotes() throws {
        let csv = "Gün;Öğün;Yiyecek;Miktar;Birim\n1;Kahvaltı;\"Peynir; beyaz\";1;dilim\r\n"
        let rows = try XLSX.readCSV(Data(csv.utf8))
        XCTAssertEqual(rows[1], ["1", "Kahvaltı", "Peynir; beyaz", "1", "dilim"])
    }

    func testColumnReferences() {
        XCTAssertEqual(XLSX.column(0), "A")
        XCTAssertEqual(XLSX.column(27), "AB")
        XCTAssertEqual(XLSX.columnIndex("AB12"), 27)
    }

    func testTemplateImportsBackIntoPlan() throws {
        let data = DietImport.templateData(foods: FoodLibrary.all)
        let rows = try DietImport.rows(from: data, fileName: "sablon.xlsx")
        let draft = DietImport.draft(from: rows, foods: FoodLibrary.all)
        XCTAssertEqual(draft.dayCount, 2)
        let plan = draft.makePlan()
        XCTAssertEqual(plan.days[0].meals.map(\.name), ["Kahvaltı", "Ara öğün", "Öğle", "Akşam"])
        XCTAssertEqual(plan.days[0].meals[0].id, plan.days[1].meals[0].id, "aynı adlı öğün günler arasında aynı kimlik")
        let bulgur = plan.days[0].meals[2].items.first { $0.portion.food.key == "preset.bulgur-pilaf" }
        XCTAssertEqual(bulgur?.portion.unit, .tablespoon)
        XCTAssertEqual(bulgur?.alternatives.first?.food.key, "preset.rice-pilaf")
    }

    func testUnknownFoodsBecomeIssuesAndResolve() {
        let table = [
            ["Gün", "Öğün", "Saat", "Yiyecek", "Miktar", "Birim", "Değişim"],
            ["1", "Kahvaltı", "08:30", "Tam buğday galeta", "2", "adet", ""],
            ["3", "Kahvaltı", "", "Tam bugday galeta", "2", "adet", ""],
            ["3", "Akşam", "19:00", "Zeytinyağı", "", "", ""],
            ["3", "Akşam", "19:00", "Tavuk gogsu", "120", "gr", "Izgara kofte 5 adet"]
        ]
        var draft = DietImport.draft(from: table, foods: FoodLibrary.all)
        XCTAssertEqual(draft.dayCount, 3)
        XCTAssertEqual(draft.unknownFoodIssues.count, 2, "galeta (iki yazım tek sorun) + zeytinyağı")
        XCTAssertNotNil(draft.matches[DietText.fold("Tavuk gogsu")], "yazım farkı ve parantez eşleşir")
        XCTAssertTrue(draft.hasOpenIssue(day: 3))
        XCTAssertFalse(draft.hasOpenIssue(day: 2))
        let galeta = draft.unknownFoodIssues.first { $0.title.contains("galeta") }!
        XCTAssertEqual(galeta.days, [1, 3])
        draft.resolutions[galeta.id] = .matched(DietFixtures.food("whole-bread"))
        let plan = draft.makePlan()
        XCTAssertEqual(plan.days[0].meals[0].minutes, 8 * 60 + 30)
        XCTAssertEqual(plan.days[2].meals.first { $0.name == "Kahvaltı" }?.items.first?.portion.food.key, "preset.whole-bread")
        XCTAssertEqual(plan.days[1].meals.count, 0, "boş gün")
    }

    func testAlternativeParsing() {
        let alternatives = DietImport.parseAlternatives("Pirinç pilavı 4 yk; Tam buğday ekmeği 2 dilim veya Elma")
        XCTAssertEqual(alternatives.count, 3)
        XCTAssertEqual(alternatives[0].name, "Pirinç pilavı")
        XCTAssertEqual(alternatives[0].amount, 4)
        XCTAssertEqual(alternatives[0].unit, .tablespoon)
        XCTAssertEqual(alternatives[1].unit, .slice)
        XCTAssertEqual(alternatives[2].unit, .serving)
        XCTAssertEqual(DietFormat.minutes(fromTime: "0.354166"), 510)
        XCTAssertEqual(DietFormat.minutes(fromTime: "13.30"), 13 * 60 + 30)
    }

    private static func deflate(_ data: Data) throws -> Data {
        var output = Data(count: data.count + 64)
        let size = output.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, data.count + 64,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard size > 0 else { throw ZipArchive.ZipError.unsupported }
        return output.prefix(size)
    }
}

// MARK: - Analiz ve alışveriş

final class DietAnalysisTests: XCTestCase {
    private let calendar = Calendar.current

    func testSummaryAdherenceMissedAndContributions() {
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -2, to: today)!
        let program = DietProgram(ownerID: "u", name: "P", startDate: start, plan: DietFixtures.plan(days: 3))
        let plan = program.latestPlan
        let day0 = DietDayKey.make(start)
        let day1 = DietDayKey.make(calendar.date(byAdding: .day, value: 1, to: start)!)
        var changed = DietMealLog(programID: program.id, dayKey: day1, programDay: 2, meal: plan.days[1].meals[1], status: .changed,
                                  eaten: [DietPortion(food: DietFixtures.food("chicken-breast"), amount: 120, unit: .gram)],
                                  swaps: ["Bulgur pilavı yenmedi"])
        changed.updatedAt = .now
        let logs = [
            DietMealLog(programID: program.id, dayKey: day0, programDay: 1, meal: plan.days[0].meals[0], status: .eaten, eaten: plan.days[0].meals[0].portions),
            DietMealLog(programID: program.id, dayKey: day0, programDay: 1, meal: plan.days[0].meals[1], status: .skipped, eaten: []),
            changed
        ]
        let extra = DietExtra(id: "e", date: calendar.date(byAdding: .hour, value: 15, to: start)!, name: "Kurabiye", amountText: "1", nutrition: DietNutrition(calories: 110, protein: 1, carbs: 15, fat: 5))
        let summary = DietAnalysis.summarize(program: program, from: start, to: today, logs: logs, notes: [], extras: [extra])
        XCTAssertEqual(summary.days.count, 3)
        XCTAssertEqual(summary.followed, 1)
        XCTAssertEqual(summary.changed, 1)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.missed, 1, "dünün kahvaltısı işaretlenmedi")
        XCTAssertEqual(summary.days[2].pendingCount, 2, "bugün bekliyor")
        XCTAssertEqual(summary.adherencePercent, 25)
        XCTAssertEqual(summary.extraCount, 1)
        XCTAssertEqual(summary.days[0].eaten.calories, 78 * 2 + 80 + 110, accuracy: 1)

        let protein = DietAnalysis.contributions(of: .protein, in: summary.pastDays)
        XCTAssertEqual(protein.first?.name, "Tavuk göğsü (ızgara)")
        XCTAssertEqual(protein.reduce(0) { $0 + $1.share }, 1, accuracy: 0.001)
    }

    func testShoppingAggregatesAcrossDays() {
        let start = calendar.startOfDay(for: .now)
        let program = DietProgram(ownerID: "u", name: "P", startDate: start, plan: DietFixtures.plan(days: 3))
        let items = DietShopping.items(program: program, from: start, to: calendar.date(byAdding: .day, value: 2, to: start)!)
        let eggs = items.first { $0.food.key == "preset.boiled-egg" }
        XCTAssertEqual(eggs?.pieces, 6)
        XCTAssertEqual(eggs?.quantityText, "6 adet")
        XCTAssertEqual(eggs?.category, .protein)
        let chicken = items.first { $0.food.key == "preset.chicken-breast" }
        XCTAssertEqual(chicken?.grams, 360)
        XCTAssertEqual(chicken?.dayNumbers, [1, 2, 3])
        XCTAssertEqual(items.first { $0.food.key == "preset.white-cheese" }?.alternatives, ["Kaşar peyniri"])
        XCTAssertEqual(DietShoppingCategory.of("Bulgur pilavı"), .grains)
        XCTAssertEqual(DietShoppingCategory.of("Yoğurt (tam yağlı)"), .dairy)

        let text = DietShopping.text(items: items, states: ["preset.boiled-egg": .atHome], title: "Liste")
        XCTAssertFalse(text.contains("Haşlanmış yumurta"), "evde olan listede yok")
    }

    func testShoppingStoreKeepsAtHomeOnReset() {
        let defaults = makeTestDefaults()
        let store = DietShoppingStore(defaults: defaults, programID: "p")
        store.save(["a": .bought, "b": .atHome])
        store.resetBought()
        XCTAssertEqual(store.load(), ["b": .atHome])
    }

    func testSwapKeyIgnoresAmounts() {
        XCTAssertEqual(DietRangeSummary.swapKey("Elma → Armut 1 orta"), "Elma → Armut")
    }
}

// MARK: - Depo

@MainActor
final class DietStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockDietSync!
    private var chat: MockChatSync!
    private var media: MockMediaStore!
    private var notifier: MockNotifier!
    private var sut: DietStore!
    private var defaults: UserDefaults!
    private var files: DietPhotoFiles!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: DietRecord.self, MealEntry.self, CustomFood.self, WeightEntry.self, MeasurementEntry.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sync = MockDietSync()
        chat = MockChatSync()
        media = MockMediaStore()
        notifier = MockNotifier()
        defaults = makeTestDefaults("dietStore")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diet-tests-\(UUID().uuidString)")
        files = DietPhotoFiles(root: root.appendingPathComponent("own"), cache: root.appendingPathComponent("cache"))
        sut = DietStore(sync: sync, media: media, chat: chat, notifier: notifier, files: files, defaults: defaults)
        sut.configure(context: container.mainContext, user: AppUser.makeNew(id: "u1", email: "a@b.com", displayName: "Ada"))
    }

    override func tearDown() async throws {
        await settleTasks()
        files.removeAll()
        sut = nil
        container = nil
        try await super.tearDown()
    }

    func testCreateMarkAndSwap() async throws {
        let program = try sut.createProgram(name: "  Kış ", plan: DietFixtures.plan(days: 3), startDate: .now, endBehavior: .stop, note: "")
        XCTAssertEqual(sut.activeProgram()?.name, "Kış")
        let meal = program.latestPlan.days[0].meals[1]
        try sut.mark(program: program, date: .now, meal: meal, status: .eaten)
        XCTAssertEqual(sut.log(programID: program.id, dayKey: DietDayKey.make(.now), mealID: meal.id)?.eaten.count, 2)

        let rice = DietPortion(food: DietFixtures.food("rice-pilaf"), amount: 4, unit: .tablespoon)
        try sut.mark(program: program, date: .now, meal: meal, status: .changed, eaten: [meal.items[0].portion, rice],
                     swaps: ["Bulgur pilavı → \(rice.label)"], note: "dışarıda")
        let log = try XCTUnwrap(sut.log(programID: program.id, dayKey: DietDayKey.make(.now), mealID: meal.id))
        XCTAssertEqual(log.status, .changed)
        XCTAssertEqual(log.note, "dışarıda")
        XCTAssertEqual(log.planned.count, 2, "plan anlık görüntüsü saklanır")
        await settleTasks()
        XCTAssertEqual(sync.uploadedLogs.last?.status, .changed)
        XCTAssertFalse(sync.uploadedPrograms.isEmpty)

        try sut.unmark(program: program, date: .now, meal: meal)
        XCTAssertEqual(sut.log(programID: program.id, dayKey: DietDayKey.make(.now), mealID: meal.id)?.status, .pending, "not kalır")
    }

    func testPhotoBeforeMarkingIsKeptAndUploaded() async throws {
        let program = try sut.createProgram(name: "P", plan: DietFixtures.plan(days: 1), startDate: .now, endBehavior: .stop, note: "")
        let meal = program.latestPlan.days[0].meals[0]
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        try sut.attachPhoto(image, program: program, date: .now, meal: meal)
        let pending = try XCTUnwrap(sut.log(programID: program.id, dayKey: DietDayKey.make(.now), mealID: meal.id))
        XCTAssertEqual(pending.status, .pending)
        let path = try XCTUnwrap(pending.photoPath)
        XCTAssertTrue(path.hasPrefix("diet/\(program.id)/"))
        XCTAssertNotNil(sut.photoURL(path))
        try sut.mark(program: program, date: .now, meal: meal, status: .eaten)
        XCTAssertEqual(sut.log(programID: program.id, dayKey: DietDayKey.make(.now), mealID: meal.id)?.photoPath, path, "işaretleyince fotoğraf kalır")
        await settleTasks()
        XCTAssertEqual(media.uploads.first?.path, path)
        XCTAssertEqual(media.uploads.first?.contentType, "image/jpeg")
    }

    func testSyncMergesRemoteNewerButKeepsPendingLocal() async throws {
        let program = try sut.createProgram(name: "Yerel", plan: DietFixtures.plan(days: 2), startDate: .now, endBehavior: .stop, note: "")
        await settleTasks()
        var remote = program
        remote.name = "Sunucu"
        remote.updatedAt = Date.now.addingTimeInterval(60)
        var other = DietProgram(ownerID: "u1", name: "Diğer", startDate: .now.addingTimeInterval(86_400 * 10), plan: DietFixtures.plan())
        other.updatedAt = .now
        sync.remotePrograms = [remote, other]
        await sut.syncAll()
        XCTAssertEqual(sut.program(id: program.id)?.name, "Sunucu")
        XCTAssertNotNil(sut.program(id: other.id))

        sync.isOffline = true
        try sut.rename(program.id, to: "Çevrimdışı")
        sync.isOffline = false
        remote.name = "Eski sunucu"
        remote.updatedAt = Date.now.addingTimeInterval(120)
        sync.remotePrograms = [remote]
        await sut.syncAll()
        XCTAssertEqual(sut.program(id: program.id)?.name, "Çevrimdışı", "bekleyen yerel değişiklik kazanır")
    }

    func testShareSendsOfferAndCardAcceptCreatesProgram() async throws {
        let program = try sut.createProgram(name: "Kış", plan: DietFixtures.plan(days: 3), startDate: .now, endBehavior: .stop, note: "")
        let room = ChatRoomDTO(id: "u1_u2", members: ["u1", "u2"], names: ["u1": "Ada", "u2": "Ece"], createdAt: .now)
        await sut.share(program.id, with: room)
        let offer = try XCTUnwrap(sync.offers.values.first)
        XCTAssertEqual(offer.toID, "u2")
        XCTAssertEqual(offer.plan.dayCount, 3)
        let message = try XCTUnwrap(chat.sent.last)
        XCTAssertEqual(message.type, .diet)
        XCTAssertEqual(message.diet?.offerID, offer.id)
        XCTAssertEqual(message.diet?.days, 3)

        // Alıcı (başka kullanıcı) kabul eder.
        sut.configure(context: container.mainContext, user: AppUser.makeNew(id: "u2", email: "e@b.com", displayName: "Ece"))
        let accepted = try await sut.accept(offer, startDate: .now, endBehavior: .loop, allowViewer: true)
        XCTAssertEqual(accepted.ownerID, "u2")
        XCTAssertEqual(accepted.viewerIDs, ["u1"])
        XCTAssertEqual(accepted.sharedByName, "Ada")
        XCTAssertEqual(sync.offerDecisions.last?.1, .accepted)
        XCTAssertEqual(sync.offerDecisions.last?.2, accepted.id)
    }

    func testSuggestionAcceptCreatesVersionFromDate() async throws {
        let program = try sut.createProgram(name: "P", plan: DietFixtures.plan(days: 3), startDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
                                            endBehavior: .stop, note: "")
        var plan = program.latestPlan
        plan.days[2].meals[0].items.removeLast()
        let suggestion = DietSuggestion(id: "s1", programID: program.id, authorID: "u9", authorName: "Diyetisyen", note: "peynir azalsın",
                                        basedOnVersion: 1, plan: plan, status: .pending, createdAt: .now, decidedAt: nil)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        await sut.decide(suggestion, accept: true, effectiveFrom: tomorrow)
        let updated = try XCTUnwrap(sut.program(id: program.id))
        XCTAssertEqual(updated.versions.count, 2)
        XCTAssertEqual(updated.latest.authorName, "Diyetisyen")
        XCTAssertEqual(updated.version(on: .now).number, 1)
        XCTAssertEqual(updated.version(on: tomorrow).number, 2)
        XCTAssertEqual(sync.decisions.last?.1, .accepted)
    }

    func testExtrasComeFromFreeLogging() throws {
        let entry = MealEntry(ownerID: "u1", date: .now, mealType: .snack, template: FoodLibrary.template(forKey: "preset.simit")!, quantity: 1)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        let extras = sut.extras(from: .now, to: .now)
        XCTAssertEqual(extras.map(\.name), ["Simit"])
        XCTAssertEqual(extras.first?.nutrition.calories, 330)
    }
}
