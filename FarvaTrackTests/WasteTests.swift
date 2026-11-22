import XCTest
import SwiftData
@testable import FarvaTrack

final class MockWasteSync: WasteSyncing {
    var remote: [WasteDTO] = []
    var adminResult: Result<[WasteUserSummary], Error> = .success([])
    var failDaily = false
    private(set) var uploaded: [WasteDTO] = []
    private(set) var deleted: [String] = []
    private(set) var dailyUploads: [WasteDailyDTO] = []

    func uploadEntry(_ entry: WasteDTO, userID: String) async throws { mockLock.withLock { uploaded.append(entry) } }
    func deleteEntry(id: String, userID: String) async throws { mockLock.withLock { deleted.append(id) } }
    func fetchEntries(userID: String, since: Date) async throws -> [WasteDTO] { remote }
    func uploadDaily(_ daily: WasteDailyDTO, userID: String) async throws {
        if failDaily { throw AppError.network }
        dailyUploads.append(daily)
    }
    func fetchAllUsersDaily(since: Date) async throws -> [WasteUserSummary] { try adminResult.get() }
}

final class MockWasteWidget: WasteWidgetStoring {
    var pending: [PendingWasteTap] = []
    private(set) var published: [WasteSnapshot] = []

    var undos: [UUID] = []

    func pendingTaps() -> [PendingWasteTap] { pending }
    func removePending(ids: [UUID]) { pending.removeAll { ids.contains($0.id) } }
    func publish(_ snapshot: WasteSnapshot) { published.append(snapshot) }
    func pendingUndos() -> [UUID] { undos }
    func removeUndos(ids: [UUID]) { undos.removeAll { ids.contains($0) } }
}

final class WasteAnalyzerTests: XCTestCase {
    private let calendar = utcCalendar()
    private var end: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15))! }

    func testDayKeyRoundTrip() {
        XCTAssertEqual(WasteAnalyzer.dayKey(end, calendar: calendar), "2026-11-20")
        XCTAssertEqual(WasteAnalyzer.day(fromKey: "2026-11-20", calendar: calendar), calendar.startOfDay(for: end))
        XCTAssertNil(WasteAnalyzer.day(fromKey: "bozuk", calendar: calendar))
    }

    func testDailyCountsFromDates() {
        let dates = [end, end.addingTimeInterval(-3_600), end.addingTimeInterval(-86_400 * 2)]
        let series = WasteAnalyzer.dailyCounts(dates: dates, endingOn: end, days: 7, calendar: calendar)
        XCTAssertEqual(series.count, 7)
        XCTAssertEqual(series.map(\.value), [0, 0, 0, 0, 1, 0, 2])
    }

    func testDailyCountsFromAdminDocuments() {
        let daily = [
            WasteDailyDTO(id: "2026-11-20", day: calendar.startOfDay(for: end), count: 4, updatedAt: end),
            WasteDailyDTO(id: "2026-11-18", day: calendar.startOfDay(for: end), count: 2, updatedAt: end)
        ]
        let series = WasteAnalyzer.dailyCounts(daily: daily, endingOn: end, days: 3, calendar: calendar)
        XCTAssertEqual(series.map(\.value), [2, 0, 4], "gün anahtarı belge kimliğinden okunur")
    }

    func testStatsIgnoreDaysBeforeFirstUse() {
        let series = [0, 0, 3, 0, 1].enumerated().map {
            DailyValue(date: end.addingTimeInterval(Double($0.offset) * 86_400), value: Double($0.element))
        }
        let stats = WasteAnalyzer.stats(series)
        XCTAssertEqual(stats.today, 1)
        XCTAssertEqual(stats.average, 4.0 / 3, accuracy: 0.001)
        XCTAssertEqual(stats.maximum, 3)
        XCTAssertEqual(stats.activeDays, 2)
        XCTAssertEqual(WasteAnalyzer.stats([]).activeDays, 0)
    }
}

@MainActor
final class WasteViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var sync: MockWasteSync!
    private var widget: MockWasteWidget!
    private var defaults: UserDefaults!
    private var sut: WasteViewModel!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: WasteEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        sync = MockWasteSync()
        widget = MockWasteWidget()
        defaults = makeTestDefaults("waste")
        sut = WasteViewModel(sync: sync, widget: widget, defaults: defaults)
        sut.configure(context: context, user: AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test"))
    }

    /// Arka plan görevleri bitmeden bellek içi veritabanı bırakılmaz (sonraki testlerde çökmeyi önler).
    override func tearDown() async throws {
        await settleTasks()
        try await super.tearDown()
    }

    private func entries() throws -> [WasteEntry] { try context.fetch(FetchDescriptor<WasteEntry>()) }

    func testAddUploadsEntryAndDailyTotalOnly() async throws {
        try sut.add()
        try sut.add()
        await settleTasks()
        XCTAssertEqual(sut.count(on: .now), 2)
        XCTAssertEqual(sync.uploaded.count, 2)
        XCTAssertEqual(widget.published.last?.count, 2)
        // Yöneticinin göreceği belge yalnızca gün anahtarı ve sayı taşır.
        let last = try XCTUnwrap(sync.dailyUploads.last)
        XCTAssertEqual(last.id, WasteAnalyzer.dayKey(.now))
        XCTAssertEqual(last.count, 2)
    }

    func testWidgetUndoDeletesImportedTap() async throws {
        let tapID = UUID()
        widget.pending = [PendingWasteTap(id: tapID, date: .now)]
        sut.importWidgetTaps()
        await settleTasks()
        XCTAssertEqual(sut.count(on: .now), 1)

        // Uygulama dokunuşu aktardıktan sonra widget'tan "Geri al" geldi.
        widget.undos = [tapID]
        sut.importWidgetTaps()
        await settleTasks()
        XCTAssertEqual(sut.count(on: .now), 0)
        XCTAssertTrue(widget.undos.isEmpty)
        XCTAssertEqual(widget.published.last?.count, 0)
    }

    func testPublishedSnapshotCarriesLastEntryTime() throws {
        let entry = try sut.add()
        XCTAssertEqual(widget.published.last?.lastAt, entry.date)
    }

    func testDailyLimit() throws {
        for _ in 0..<SharedStore.maxDailyWasteCount { try sut.add() }
        XCTAssertThrowsError(try sut.add())
    }

    func testUndoDeletesAndUpdatesDailyTotal() async throws {
        try sut.add()
        await settleTasks()
        sut.undo()
        await settleTasks()
        XCTAssertTrue(try entries().isEmpty)
        XCTAssertEqual(sync.deleted.count, 1)
        XCTAssertEqual(sync.dailyUploads.last?.count, 0)
        XCTAssertNil(sut.lastAddedID)
    }

    func testFailedDailyUploadIsRetried() async throws {
        sync.failDaily = true
        try sut.add()
        await settleTasks()
        XCTAssertTrue(sync.dailyUploads.isEmpty)

        sync.failDaily = false
        await sut.flushDirtyDays()
        XCTAssertEqual(sync.dailyUploads.last?.count, 1)

        let before = sync.dailyUploads.count
        await sut.flushDirtyDays()
        XCTAssertEqual(sync.dailyUploads.count, before, "başarılı yüklemeden sonra gün temizlenir")
    }

    func testImportWidgetTapsIsIdempotent() throws {
        let existing = try sut.add()
        widget.pending = [
            PendingWasteTap(id: existing.id, date: .now),
            PendingWasteTap(id: UUID(), date: .now)
        ]
        sut.importWidgetTaps()
        sut.importWidgetTaps()
        XCTAssertEqual(try entries().count, 2)
        XCTAssertTrue(widget.pending.isEmpty)
    }

    func testSyncAddsMissingRemoteEntries() async throws {
        sync.remote = [WasteDTO(id: UUID().uuidString, date: .now, createdAt: .now, updatedAt: .now)]
        await sut.syncAll()
        await sut.syncAll()
        XCTAssertEqual(try entries().count, 1)
    }

    func testAdminOverview() async {
        let user = WasteUserSummary(id: "u2", displayName: "Ayşe", email: "a@b.com", days: [])
        sync.adminResult = .success([user])
        await sut.loadAdminOverview()
        XCTAssertEqual(sut.adminUsers, [user])
        XCTAssertNil(sut.adminError)

        sync.adminResult = .failure(AppError.notAuthorized)
        await sut.loadAdminOverview()
        XCTAssertNotNil(sut.adminError)
    }
}
