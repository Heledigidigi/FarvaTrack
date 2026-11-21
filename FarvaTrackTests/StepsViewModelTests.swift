import XCTest
@testable import FarvaTrack

final class MockHealthProvider: HealthDataProviding {
    var isHealthDataAvailable = true
    var status: HealthAccessStatus = .requested
    var days: [DailyActivity] = []
    var failAuthorization = false
    private(set) var authorizationRequested = false

    func requestStatus() async -> HealthAccessStatus { status }

    func requestAuthorization() async throws {
        if failAuthorization { throw AppError.healthUnavailable }
        authorizationRequested = true
        status = .requested
    }

    func activity(from start: Date, to end: Date) async throws -> [DailyActivity] { days }

    func liveActivity(from start: Date, to end: Date) -> AsyncThrowingStream<[DailyActivity], Error> {
        let snapshot = days
        return AsyncThrowingStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }
}

@MainActor
final class StepsViewModelTests: XCTestCase {

    private var health: MockHealthProvider!
    private var published: [StepsSnapshot] = []
    private var calendar: Calendar!
    private var sut: StepsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        cal.firstWeekday = 2                       // Pazartesi
        calendar = cal

        health = MockHealthProvider()
        published = []

        // Salı, 17 Kasım 2026 12:00
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 12)) ?? .now
        sut = StepsViewModel(
            health: health,
            calendar: cal,
            now: { now },
            widgetPublisher: { [unowned self] in self.published.append($0) }
        )

        var user = AppUser.makeNew(id: "u1", email: "a@b.com", displayName: "Test")
        user.dailyStepGoal = 8_000
        user.weightKg = 70
        user.heightCm = 175
        sut.configure(user: user)
    }

    private func day(_ dayOfMonth: Int, steps: Int, km: Double = 0, kcal: Double = 0) -> DailyActivity {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: dayOfMonth)) ?? .now
        return DailyActivity(date: date, steps: steps, distanceKm: km, activeEnergyKcal: kcal)
    }

    private func loadAndWait(_ days: [DailyActivity]) async throws {
        health.days = days
        await sut.start()
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    // MARK: - İzin akışı
    func testUnavailableDevice() async {
        health.isHealthDataAvailable = false
        await sut.start()
        XCTAssertEqual(sut.access, .unavailable)
    }

    func testNeedsPermissionWhenNeverAsked() async {
        health.status = .notDetermined
        await sut.start()
        XCTAssertEqual(sut.access, .needsPermission)
    }

    func testRequestAccessMovesToReady() async {
        health.status = .notDetermined
        await sut.start()
        await sut.requestAccess()
        XCTAssertTrue(health.authorizationRequested)
        XCTAssertEqual(sut.access, .ready)
    }

    func testRequestAccessFailureShowsError() async {
        health.failAuthorization = true
        await sut.requestAccess()
        XCTAssertNotNil(sut.errorMessage)
    }

    // MARK: - İstatistikler
    func testDayStatsUseOnlyToday() async throws {
        try await loadAndWait([day(16, steps: 3_000), day(17, steps: 6_000)])
        let stats = sut.stats(for: .day)
        XCTAssertEqual(stats.steps, 6_000)
        XCTAssertEqual(stats.goal, 8_000)
        XCTAssertEqual(stats.progress, 0.75, accuracy: 0.001)
        XCTAssertEqual(stats.remaining, 2_000)
    }

    func testWeekStartsOnMondayAndGoalIsSevenTimesDaily() async throws {
        // 15 Kasım Pazar (önceki hafta), 16 Pazartesi, 17 Salı
        try await loadAndWait([day(15, steps: 5_000), day(16, steps: 4_000), day(17, steps: 6_000)])
        let stats = sut.stats(for: .week)
        XCTAssertEqual(stats.steps, 10_000)
        XCTAssertEqual(stats.goal, 56_000)
        XCTAssertEqual(stats.dayCount, 2)
        XCTAssertEqual(stats.dailyAverage, 5_000)
    }

    func testMonthGoalUsesDaysInMonth() async throws {
        try await loadAndWait([day(1, steps: 1_000), day(17, steps: 2_000)])
        let stats = sut.stats(for: .month)
        XCTAssertEqual(stats.steps, 3_000)
        XCTAssertEqual(stats.goal, 8_000 * 30)     // Kasım 30 gün
    }

    func testCaloriesFallBackToEstimateWithoutActiveEnergy() async throws {
        try await loadAndWait([day(17, steps: 10_000, km: 7)])
        let stats = sut.stats(for: .day)
        XCTAssertEqual(stats.calories, 260)         // 7 × 70 × 0,53 = 259,7
        XCTAssertTrue(stats.caloriesAreEstimated)
    }

    func testCaloriesUseHealthKitEnergyWhenAvailable() async throws {
        try await loadAndWait([day(17, steps: 10_000, km: 7, kcal: 300)])
        let stats = sut.stats(for: .day)
        XCTAssertEqual(stats.calories, 300)
        XCTAssertFalse(stats.caloriesAreEstimated)
    }

    func testDistanceIsEstimatedFromHeightWhenMissing() async throws {
        try await loadAndWait([day(17, steps: 10_000)])
        // 10000 × 175 × 0,415 / 100000 = 7,2625 km
        XCTAssertEqual(sut.stats(for: .day).distanceKm, 7.2625, accuracy: 0.001)
    }

    // MARK: - Grafik, ipucu, widget
    func testWeekChartAlwaysHasSevenDaysIncludingFuture() async throws {
        try await loadAndWait([day(16, steps: 4_000), day(17, steps: 6_000)])
        let data = sut.chartData(for: .week)
        XCTAssertEqual(data.count, 7)
        XCTAssertEqual(data[1].value, 6_000)       // Salı
        XCTAssertEqual(data.last?.value, 0)        // Pazar (gelecek)
    }

    func testMonthChartCoversFirstDayThroughToday() async throws {
        try await loadAndWait([day(17, steps: 100)])
        XCTAssertEqual(sut.chartData(for: .month).count, 17)
    }

    func testNoDataHintAppearsWhenAllZero() async throws {
        try await loadAndWait([day(16, steps: 0), day(17, steps: 0)])
        XCTAssertTrue(sut.showsNoDataHint)
    }

    func testWidgetSnapshotIsPublishedWithTodaySteps() async throws {
        try await loadAndWait([day(17, steps: 4_321, km: 3)])
        XCTAssertEqual(published.last?.steps, 4_321)
        XCTAssertEqual(published.last?.goal, 8_000)
    }
}
