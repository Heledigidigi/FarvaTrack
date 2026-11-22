import XCTest
import SwiftData
@testable import FarvaTrack

final class MockWaterSync: WaterSyncing {
    var remote: [WaterDTO] = []
    private(set) var uploaded: [WaterDTO] = []
    private(set) var deleted: [String] = []

    func upload(_ entry: WaterDTO, userID: String) async throws { mockLock.withLock { uploaded.append(entry) } }
    func deleteEntry(id: String, userID: String) async throws { mockLock.withLock { deleted.append(id) } }
    func fetchEntries(userID: String, since: Date) async throws -> [WaterDTO] { remote }
}

final class MockWaterWidget: WaterWidgetStoring {
    var pending: [PendingWaterAdd] = []
    private(set) var published: [WaterSnapshot] = []

    func pendingAdds() -> [PendingWaterAdd] { pending }
    func removePending(ids: [UUID]) { pending.removeAll { ids.contains($0.id) } }
    func publish(_ snapshot: WaterSnapshot) { published.append(snapshot) }
}

@MainActor
final class WaterViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var sync: MockWaterSync!
    private var widget: MockWaterWidget!
    private var scheduler: MockNotificationScheduler!
    private var defaults: UserDefaults!
    private var sut: WaterViewModel!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "pendingWaterDeletes.uid-1")
        container = try ModelContainer(for: WaterEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        sync = MockWaterSync()
        widget = MockWaterWidget()
        scheduler = MockNotificationScheduler()
        defaults = makeTestDefaults("water")

        var user = AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test")
        user.dailyWaterGoalMl = 2_400
        sut = WaterViewModel(sync: sync, widget: widget, scheduler: scheduler, defaults: defaults)
        sut.configure(context: context, user: user)
    }

    /// Arka plan görevleri bitmeden bellek içi veritabanı bırakılmaz (sonraki testlerde çökmeyi önler).
    override func tearDown() async throws {
        await settleTasks()
        try await super.tearDown()
    }

    private func entries() throws -> [WaterEntry] { try context.fetch(FetchDescriptor<WaterEntry>()) }

    func testAddPublishesSnapshotAndUploads() async throws {
        try sut.add(amountMl: 250)
        try sut.add(amountMl: 500)
        await settleTasks()
        XCTAssertEqual(widget.published.last?.totalMl, 750)
        XCTAssertEqual(widget.published.last?.goalMl, 2_400)
        XCTAssertEqual(sync.uploaded.count, 2)
        XCTAssertNotNil(sut.undoToken)
    }

    func testAmountValidation() {
        XCTAssertThrowsError(try sut.add(amountMl: 10))
        XCTAssertThrowsError(try sut.add(amountMl: SharedStore.maxSingleWaterMl + 1))
    }

    func testDailyLimit() throws {
        try sut.add(amountMl: 2_000)
        try sut.add(amountMl: 2_000)
        try sut.add(amountMl: 2_000)
        XCTAssertThrowsError(try sut.add(amountMl: 100))
    }

    func testUndoRemovesLastEntry() async throws {
        try sut.add(amountMl: 200)
        sut.undo()
        await settleTasks()
        XCTAssertEqual(try entries().count, 0)
        XCTAssertNil(sut.undoToken)
        XCTAssertEqual(sync.deleted.count, 1)
        XCTAssertEqual(widget.published.last?.totalMl, 0)
    }

    func testImportWidgetAddsIsIdempotent() throws {
        let existing = try sut.add(amountMl: 300)
        widget.pending = [
            PendingWaterAdd(id: existing.id, amountMl: 300, date: .now),   // zaten aktarılmış
            PendingWaterAdd(id: UUID(), amountMl: 200, date: .now)
        ]
        sut.importWidgetAdds()
        XCTAssertEqual(try entries().count, 2)
        XCTAssertTrue(widget.pending.isEmpty)

        sut.importWidgetAdds()
        XCTAssertEqual(try entries().count, 2)
    }

    func testRemindersRequestPermission() async {
        scheduler.status = .notDetermined
        var settings = WaterReminderSettings()
        settings.isEnabled = true
        let ok = await sut.applyReminders(settings)
        XCTAssertTrue(ok)
        XCTAssertTrue(scheduler.requestedAuthorization)
        XCTAssertEqual(scheduler.waterScheduled, settings)
        XCTAssertEqual(WaterReminderSettings.load(defaults: defaults), settings)
    }

    func testRemindersDisabledWhenPermissionDenied() async {
        scheduler.status = .notDetermined
        scheduler.grantOnRequest = false
        var settings = WaterReminderSettings()
        settings.isEnabled = true
        let ok = await sut.applyReminders(settings)
        XCTAssertFalse(ok)
        XCTAssertFalse(sut.reminderSettings.isEnabled)
        XCTAssertNil(scheduler.waterScheduled)
    }

    func testReminderTimes() {
        var settings = WaterReminderSettings()
        settings.startHour = 8
        settings.endHour = 12
        settings.intervalMinutes = 120
        let times = NotificationManager.reminderTimes(for: settings)
        XCTAssertEqual(times.map(\.hour), [8, 10, 12])
    }

    func testSyncAddsMissingRemoteEntries() async throws {
        sync.remote = [WaterDTO(id: UUID().uuidString, date: .now, amountMl: 330, createdAt: .now, updatedAt: .now)]
        await sut.syncAll()
        XCTAssertEqual(try entries().map(\.amountMl), [330])
        await sut.syncAll()
        XCTAssertEqual(try entries().count, 1)
    }

    func testDailyTotals() {
        let calendar = utcCalendar()
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        let a = WaterEntry(ownerID: "u", date: end, amountMl: 200)
        let b = WaterEntry(ownerID: "u", date: end.addingTimeInterval(-3_600), amountMl: 300)
        let c = WaterEntry(ownerID: "u", date: end.addingTimeInterval(-86_400 * 2), amountMl: 500)
        let totals = WaterViewModel.dailyTotals(entries: [a, b, c], endingOn: end, days: 7, calendar: calendar)
        XCTAssertEqual(totals.count, 7)
        XCTAssertEqual(totals.last?.value, 500)
        XCTAssertEqual(totals[4].value, 500)
        XCTAssertEqual(totals.first?.value, 0)
    }
}
