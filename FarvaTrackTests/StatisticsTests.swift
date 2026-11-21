import XCTest
@testable import FarvaTrack

final class StatisticsCalculatorTests: XCTestCase {
    private let calendar = utcCalendar()
    private var end: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))! }

    private func daysAgo(_ n: Int, hour: Int = 10) -> Date {
        let day = calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: end))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    func testDailyTotalsSumsPerDay() {
        let samples: [(date: Date, value: Double)] = [(daysAgo(0), 200), (daysAgo(0, hour: 18), 300), (daysAgo(2), 500), (daysAgo(10), 999)]
        let daily = StatisticsCalculator.dailyTotals(samples, days: 7, endingOn: end, calendar: calendar)
        XCTAssertEqual(daily.count, 7)
        XCTAssertEqual(daily.last?.value, 500)
        XCTAssertEqual(daily[4].value, 500)
        XCTAssertEqual(daily.reduce(0) { $0 + $1.value }, 1_000, "pencere dışı örnekler sayılmaz")
    }

    func testDailyLatestKeepsLastMeasurementOfDay() {
        let samples: [(date: Date, value: Double)] = [(daysAgo(0, hour: 20), 70.4), (daysAgo(0, hour: 7), 71.0)]
        let daily = StatisticsCalculator.dailyLatest(samples, days: 3, endingOn: end, calendar: calendar)
        XCTAssertEqual(daily.last?.value, 70.4)
        XCTAssertEqual(daily.first?.value, 0)
    }

    func testSummaryAveragesRecordedDaysAndCountsGoals() {
        let daily = [0.0, 8_000, 12_000, 10_000].enumerated().map { DailyValue(date: daysAgo(3 - $0.offset), value: $0.element) }
        let previous = [5_000.0, 5_000].enumerated().map { DailyValue(date: daysAgo(10 - $0.offset), value: $0.element) }
        let summary = StatisticsCalculator.summary(daily, goal: 10_000, previous: previous)
        XCTAssertEqual(summary.recordedDays, 3)
        XCTAssertEqual(summary.average ?? 0, 10_000, accuracy: 0.001)
        XCTAssertEqual(summary.total, 30_000)
        XCTAssertEqual(summary.best?.value, 12_000)
        XCTAssertEqual(summary.goalDays, 2)
        XCTAssertEqual(summary.changePercent ?? 0, 100, accuracy: 0.001)
    }

    func testEmptySummary() {
        let summary = StatisticsCalculator.summary([DailyValue(date: end, value: 0)])
        XCTAssertNil(summary.average)
        XCTAssertNil(summary.best)
        XCTAssertNil(summary.goalDays)
        XCTAssertNil(summary.changePercent)
    }

    func testYearChartBucketsByMonthAverage() {
        var samples: [(date: Date, value: Double)] = []
        samples.append((calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!, 4))
        samples.append((calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!, 8))
        samples.append((calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!, 5))
        let daily = StatisticsCalculator.dailyTotals(samples, days: 365, endingOn: end, calendar: calendar)
        let chart = StatisticsCalculator.chartSeries(daily, period: .year, calendar: calendar)

        XCTAssertEqual(chart.count, 13, "365 gün 13 ayı kapsar (kısmi ilk ay dahil)")
        XCTAssertEqual(chart.last?.value, 6, "boş günler ortalamaya girmez")
        XCTAssertEqual(chart[chart.count - 2].value, 5)
        XCTAssertEqual(StatisticsCalculator.chartSeries(daily, period: .month, calendar: calendar).count, 365)
    }
}

final class BadgeEngineTests: XCTestCase {
    private let calendar = utcCalendar()
    private func day(_ n: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: n))! }

    func testLongestStreak() {
        XCTAssertEqual(BadgeEngine.longestStreak([], calendar: calendar), 0)
        let days: Set<Date> = [day(1), day(2), day(3), day(5), day(6), day(10)]
        XCTAssertEqual(BadgeEngine.longestStreak(days, calendar: calendar), 3)
        // Aynı günün farklı saatleri tek gün sayılır.
        let sameDay: Set<Date> = [day(1), day(1).addingTimeInterval(3_600), day(2)]
        XCTAssertEqual(BadgeEngine.longestStreak(sameDay, calendar: calendar), 2)
    }

    func testEvaluate() {
        var input = BadgeInput()
        input.workoutCount = 12
        input.stepGoal = 8_000
        input.dailySteps = [day(1): 8_500, day(2): 11_000, day(3): 3_000]
        input.waterGoal = 2_000
        input.dailyWater = Dictionary(uniqueKeysWithValues: (1...7).map { (day($0), 2_100) })
        input.mealDays = [day(1), day(2)]
        input.sleepNights = 7
        input.weighInDays = [day(1)]
        input.measurementCount = 0

        let result = Dictionary(uniqueKeysWithValues: BadgeEngine.evaluate(input, calendar: calendar).map { ($0.badge, $0) })
        XCTAssertEqual(result.count, Badge.allCases.count)
        XCTAssertTrue(result[.firstWorkout]!.isEarned)
        XCTAssertTrue(result[.workouts10]!.isEarned)
        XCTAssertFalse(result[.workouts50]!.isEarned)
        XCTAssertEqual(result[.workouts50]!.progress, 12.0 / 50, accuracy: 0.001)
        XCTAssertTrue(result[.steps10k]!.isEarned)
        XCTAssertEqual(result[.stepGoalStreak7]!.current, 2)
        XCTAssertTrue(result[.waterStreak7]!.isEarned)
        XCTAssertFalse(result[.waterStreak30]!.isEarned)
        XCTAssertEqual(result[.mealStreak7]!.current, 2)
        XCTAssertTrue(result[.sleepLog7]!.isEarned)
        XCTAssertFalse(result[.firstMeasurement]!.isEarned)
        XCTAssertEqual(result[.firstMeasurement]!.progress, 0)
    }
}

@MainActor
final class StatisticsViewModelTests: XCTestCase {
    private let calendar = utcCalendar()

    func testCardsSkipEmptyMetricsAndRespondToPeriod() {
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        let sut = StatisticsViewModel(health: MockHealthProvider(), calendar: calendar, now: { end })

        var samples = StatisticsSamples()
        samples.water = [(end, 1_500), (end.addingTimeInterval(-20 * 86_400), 2_500)]
        samples.weight = [(end, 70)]
        sut.apply(samples: samples, goals: [.water: 2_000])

        XCTAssertEqual(sut.cards.map(\.metric), [.water, .weight], "verisi olmayan metrikler gösterilmez")
        XCTAssertEqual(sut.cards.first?.summary.recordedDays, 1)
        XCTAssertEqual(sut.cards.first?.summary.goalDays, 0)

        sut.setPeriod(.month)
        XCTAssertEqual(sut.cards.first?.summary.recordedDays, 2)
        XCTAssertEqual(sut.cards.first?.chart.count, 30)

        sut.setPeriod(.year)
        XCTAssertEqual(sut.cards.first?.chart.count, 13)
    }
}
