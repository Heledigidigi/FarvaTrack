import XCTest
import SwiftData
@testable import FarvaTrack

final class MockSleepSync: SleepSyncing {
    var remote: [SleepDTO] = []
    private(set) var uploaded: [SleepDTO] = []
    private(set) var deleted: [String] = []

    func upload(_ entry: SleepDTO, userID: String) async throws { uploaded.append(entry) }
    func deleteEntry(id: String, userID: String) async throws { deleted.append(id) }
    func fetchEntries(userID: String, since: Date) async throws -> [SleepDTO] { remote }
}

final class SleepAnalyzerTests: XCTestCase {
    private let calendar = utcCalendar()

    /// `daysAgo` gün önce uyanılan, `hours` saat süren kayıt (uyanış 07:00).
    private func record(daysAgo: Int, hours: Double, quality: Int = 3, end: Date) -> SleepRecord {
        let wakeDay = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: end))!
        let wake = calendar.date(byAdding: .hour, value: 7, to: wakeDay)!
        return SleepRecord(day: wakeDay, bedtime: wake.addingTimeInterval(-hours * 3_600), wakeTime: wake, quality: quality)
    }

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))! }

    func testWeeklyReport() {
        let records = [
            record(daysAgo: 0, hours: 7, quality: 4, end: now),
            record(daysAgo: 1, hours: 6, quality: 2, end: now),
            record(daysAgo: 3, hours: 8, quality: 5, end: now),
            record(daysAgo: 9, hours: 5, end: now)   // önceki hafta
        ]
        let report = SleepAnalyzer.report(records: records, endingOn: now, goalHours: 8, calendar: calendar)
        XCTAssertEqual(report.nights.count, 7)
        XCTAssertEqual(report.recorded.count, 3)
        XCTAssertEqual(report.averageHours!, 7, accuracy: 0.001)
        XCTAssertEqual(report.averageQuality!, 11.0 / 3, accuracy: 0.001)
        XCTAssertEqual(report.debtHours, 3, accuracy: 0.001)       // (8-7) + (8-6) + 0
        XCTAssertEqual(report.deltaMinutesVsPrevious, 120)          // 7 sa vs 5 sa
        XCTAssertEqual(report.best?.quality, 5)
        XCTAssertEqual(report.worst?.quality, 2)
        XCTAssertEqual(report.durationChart.last?.value ?? 0, 7, accuracy: 0.001)
    }

    func testDebtNeverNegative() {
        let records = [record(daysAgo: 0, hours: 10, end: now)]
        let report = SleepAnalyzer.report(records: records, endingOn: now, goalHours: 8, calendar: calendar)
        XCTAssertEqual(report.debtHours, 0)
        XCTAssertNil(report.worst, "tek kayıtta en kötü gece gösterilmez")
    }

    func testEmptySummary() {
        let report = SleepAnalyzer.report(records: [], endingOn: now, goalHours: 8, calendar: calendar)
        XCTAssertNil(report.averageHours)
        XCTAssertEqual(SleepAnalyzer.summary(report: report, goalHours: 8), "Bu hafta henüz uyku kaydın yok.")
    }

    func testRegularityNeedsThreeRecordsAndHandlesMidnight() {
        XCTAssertNil(SleepAnalyzer.regularity(records: [record(daysAgo: 0, hours: 8, end: now)], calendar: calendar))

        // Aynı saatlerde: 23:00 → 07:00
        let steady = (0..<5).map { record(daysAgo: $0, hours: 8, end: now) }
        let perfect = SleepAnalyzer.regularity(records: steady, calendar: calendar)!
        XCTAssertEqual(perfect.score, 100)
        XCTAssertEqual(perfect.averageBedtimeMinutes, 23 * 60)
        XCTAssertEqual(perfect.averageWakeMinutes, 7 * 60)

        // Gece yarısının iki yanında (23:30 ve 00:30) yatışlar sapmayı küçük tutmalı.
        let mixed = [7.5, 6.5, 7.5, 6.5].enumerated().map { record(daysAgo: $0.offset, hours: $0.element, end: now) }
        let score = SleepAnalyzer.regularity(records: mixed, calendar: calendar)!.score
        XCTAssertGreaterThan(score, 60)
    }

    func testNormalizedBedtime() {
        XCTAssertEqual(SleepAnalyzer.normalizedBedtime(30), 1_470)
        XCTAssertEqual(SleepAnalyzer.normalizedBedtime(23 * 60), 23 * 60)
    }

    func testDurationText() {
        XCTAssertEqual(SleepAnalyzer.durationText(hours: 7.5), "7 sa 30 dk")
        XCTAssertEqual(SleepAnalyzer.durationText(hours: 8), "8 sa")
        XCTAssertEqual(SleepAnalyzer.durationText(hours: 0.75), "45 dk")
        XCTAssertEqual(SleepAnalyzer.timeText(minutes: 425), "07:05")
    }

    func testPlannerSuggestions() {
        // 07:00 uyanış, 8 sa hedef → 5 döngü (7,5 sa) en yakın: 07:00 − 450 − 15 = 23:15
        let suggestions = SleepPlanner.suggestions(wakeMinutes: 7 * 60, goalHours: 8)
        XCTAssertEqual(suggestions.map(\.cycles), [6, 5, 4])
        XCTAssertEqual(suggestions.first { $0.isRecommended }?.cycles, 5)
        XCTAssertEqual(SleepPlanner.recommendedBedtimeMinutes(wakeMinutes: 7 * 60, goalHours: 8), 23 * 60 + 15)
        XCTAssertEqual(suggestions.first?.bedtimeMinutes, 21 * 60 + 45)   // 6 döngü
    }

    func testPlannerPrefersLongerOnTieAndWrapsMidnight() {
        // 6,75 sa hedef: 4 döngü (6 sa) ve 5 döngü (7,5 sa) eşit uzaklıkta → daha uzun olan
        XCTAssertEqual(SleepPlanner.suggestions(wakeMinutes: 5 * 60, goalHours: 6.75).first { $0.isRecommended }?.cycles, 5)
        // 05:00 uyanış, 4 döngü: 05:00 − 360 − 15 = 22:45 (önceki gün)
        XCTAssertEqual(SleepPlanner.suggestions(wakeMinutes: 5 * 60, goalHours: 6).last?.bedtimeMinutes, 22 * 60 + 45)
    }

    func testResolveBedtimeCrossesMidnight() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20))!
        let times = SleepViewModel.resolve(bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60, wakeDay: day, calendar: calendar)
        XCTAssertEqual(times.wakeTime.timeIntervalSince(times.bedtime), 8 * 3_600)
        XCTAssertEqual(calendar.component(.day, from: times.bedtime), 19)

        let nap = SleepViewModel.resolve(bedtimeMinutes: 1 * 60, wakeMinutes: 9 * 60, wakeDay: day, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: nap.bedtime), 20)
    }
}

@MainActor
final class SleepViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var sync: MockSleepSync!
    private var scheduler: MockNotificationScheduler!
    private var defaults: UserDefaults!
    private var sut: SleepViewModel!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "pendingSleepDeletes.uid-1")
        container = try ModelContainer(for: SleepEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        sync = MockSleepSync()
        scheduler = MockNotificationScheduler()
        defaults = makeTestDefaults("sleep")

        var user = AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test")
        user.sleepGoalHours = 8
        sut = SleepViewModel(sync: sync, scheduler: scheduler, defaults: defaults)
        sut.configure(context: context, user: user)
    }

    /// Arka plan görevleri bitmeden bellek içi veritabanı bırakılmaz (sonraki testlerde çökmeyi önler).
    override func tearDown() async throws {
        await settleTasks()
        try await super.tearDown()
    }

    private var lastNight: (Date, Date) {
        let wake = Calendar.current.date(byAdding: .hour, value: -1, to: .now)!
        return (wake.addingTimeInterval(-7.5 * 3_600), wake)
    }

    private func entries() throws -> [SleepEntry] { try context.fetch(FetchDescriptor<SleepEntry>()) }

    func testSaveCreatesEntryAndUploads() async throws {
        let (bed, wake) = lastNight
        let entry = try sut.save(bedtime: bed, wakeTime: wake, quality: 4)
        await settleTasks()
        XCTAssertEqual(entry.durationHours, 7.5, accuracy: 0.001)
        XCTAssertEqual(entry.day, Calendar.current.startOfDay(for: wake))
        XCTAssertEqual(sync.uploaded.count, 1)
        XCTAssertFalse(entry.needsSync)
    }

    func testSecondSaveSameDayUpdatesInsteadOfDuplicating() throws {
        let (bed, wake) = lastNight
        try sut.save(bedtime: bed, wakeTime: wake, quality: 2)
        try sut.save(bedtime: bed.addingTimeInterval(1_800), wakeTime: wake, quality: 9)
        let all = try entries()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.quality, 5, "kalite 1–5 aralığına sıkıştırılır")
        XCTAssertEqual(all.first?.durationHours ?? 0, 7, accuracy: 0.001)
    }

    func testValidation() {
        let wake = Date.now.addingTimeInterval(-3_600)
        XCTAssertThrowsError(try sut.save(bedtime: wake.addingTimeInterval(-600), wakeTime: wake, quality: 3))
        XCTAssertThrowsError(try sut.save(bedtime: wake.addingTimeInterval(-21 * 3_600), wakeTime: wake, quality: 3))
        let future = Date.now.addingTimeInterval(3 * 3_600)
        XCTAssertThrowsError(try sut.save(bedtime: future.addingTimeInterval(-8 * 3_600), wakeTime: future, quality: 3))
    }

    func testDeleteQueuesRemoteDeletion() async throws {
        let (bed, wake) = lastNight
        let entry = try sut.save(bedtime: bed, wakeTime: wake, quality: 3)
        let id = entry.id.uuidString
        sut.delete(entry)
        await settleTasks()
        XCTAssertTrue(try entries().isEmpty)
        XCTAssertEqual(sync.deleted, [id])
    }

    func testReminderSchedulesBeforeRecommendedBedtime() async {
        var settings = SleepSettings()
        settings.targetWakeMinutes = 7 * 60
        settings.reminderEnabled = true
        settings.reminderLeadMinutes = 30
        let ok = await sut.applySettings(settings)
        XCTAssertTrue(ok)
        // Önerilen 23:15 → 30 dk önce 22:45
        XCTAssertEqual(scheduler.sleepScheduled?.hour, 22)
        XCTAssertEqual(scheduler.sleepScheduled?.minute, 45)
        XCTAssertEqual(scheduler.sleepScheduled?.bedtimeText, "23:15")
        XCTAssertEqual(SleepSettings.load(defaults: defaults), settings)
    }

    func testReminderOffWhenPermissionDenied() async {
        scheduler.status = .denied
        var settings = SleepSettings()
        settings.reminderEnabled = true
        let ok = await sut.applySettings(settings)
        XCTAssertFalse(ok)
        XCTAssertFalse(sut.settings.reminderEnabled)
        XCTAssertTrue(scheduler.sleepCancelled)
    }

    func testSyncConflictRules() async throws {
        let (bed, wake) = lastNight
        let entry = try sut.save(bedtime: bed, wakeTime: wake, quality: 3)
        await settleTasks()

        var newer = entry.dto
        newer.quality = 1
        newer.updatedAt = entry.updatedAt.addingTimeInterval(60)
        let other = SleepDTO(
            id: UUID().uuidString, day: Calendar.current.startOfDay(for: wake.addingTimeInterval(-86_400)),
            bedtime: bed.addingTimeInterval(-86_400), wakeTime: wake.addingTimeInterval(-86_400),
            quality: 4, createdAt: .now, updatedAt: .now
        )
        sync.remote = [newer, other]
        await sut.syncAll()

        XCTAssertEqual(try entries().count, 2)
        XCTAssertEqual(entry.quality, 1, "yerelde bekleyen değişiklik yoksa daha yeni uzak kayıt kazanır")
    }
}
