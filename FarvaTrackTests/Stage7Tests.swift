import XCTest
import SwiftData
@testable import FarvaTrack

// MARK: - Ölçü karşılaştırma
final class TrendComparisonTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    func testMeasuresListWristAndForearmButNotHip() {
        let titles = BodyMeasure.allCases.map(\.title)
        XCTAssertTrue(titles.contains("Bilek"))
        XCTAssertTrue(titles.contains("Ön Kol"))
        XCTAssertFalse(titles.contains("Kalça"))
        XCTAssertEqual(TrendSeries.all.count, BodyMeasure.allCases.count + 1)
    }

    func testModesDependOnUnits() {
        XCTAssertEqual(TrendComparison.allowedModes(for: [.measure(.arm), .measure(.forearm)]), [.value, .percent])
        XCTAssertEqual(TrendComparison.allowedModes(for: [.measure(.arm), .weight]), [.percent])
    }

    func testValuePointsFilterRangeAndSort() {
        let samples: [(date: Date, value: Double)] = [(daysAgo(10), 39), (daysAgo(400), 35), (daysAgo(20), 38)]
        let points = TrendComparison.points(series: .measure(.arm), samples: samples, range: .threeMonths, mode: .value, now: now)
        XCTAssertEqual(points.map(\.plotted), [38, 39])
        XCTAssertEqual(TrendComparison.points(series: .measure(.arm), samples: samples, range: .all, mode: .value, now: now).count, 3)
    }

    func testPercentChangeRelativeToFirstInRange() {
        let arm: [(date: Date, value: Double)] = [(daysAgo(20), 38), (daysAgo(10), 39.9)]
        let weight: [(date: Date, value: Double)] = [(daysAgo(25), 80), (daysAgo(5), 76)]
        let armPoints = TrendComparison.points(series: .measure(.arm), samples: arm, range: .sixMonths, mode: .percent, now: now)
        let weightPoints = TrendComparison.points(series: .weight, samples: weight, range: .sixMonths, mode: .percent, now: now)
        XCTAssertEqual(armPoints.map(\.plotted)[0], 0, accuracy: 0.001)
        XCTAssertEqual(armPoints.map(\.plotted)[1], 5, accuracy: 0.001)
        XCTAssertEqual(weightPoints.map(\.plotted)[1], -5, accuracy: 0.001)
        XCTAssertEqual(weightPoints[1].raw, 76)
    }

    func testSummary() {
        let points = TrendComparison.points(series: .measure(.wrist), samples: [(daysAgo(30), 17), (daysAgo(15), 16.5), (daysAgo(1), 17.2)],
                                            range: .all, mode: .value, now: now)
        let summary = TrendComparison.summary(points)!
        XCTAssertEqual(summary.first, 17)
        XCTAssertEqual(summary.last, 17.2)
        XCTAssertEqual(summary.minimum, 16.5)
        XCTAssertEqual(summary.change, 0.2, accuracy: 0.0001)
        XCTAssertNil(TrendComparison.summary([]))
    }

    @MainActor
    func testMeasurementEntryStoresNewFieldsAndKeepsLegacyHip() throws {
        let container = try ModelContainer(for: MeasurementEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let entry = MeasurementEntry(ownerID: "u", date: .now, values: [.wrist: 17, .forearm: 30])
        entry.hipCm = 100
        container.mainContext.insert(entry)
        XCTAssertEqual(entry.value(for: .wrist), 17)
        XCTAssertEqual(entry.dto.forearmCm, 30)
        XCTAssertEqual(entry.dto.hipCm, 100, "eski kalça verisi senkronda kaybolmaz")
        XCTAssertNil(entry.values[.chest])
    }
}

// MARK: - Program uyumu
final class AdherenceTests: XCTestCase {
    private let calendar = utcCalendar()
    private let a = UUID(), b = UUID()

    /// 2026-11-16 Pazartesi
    private func day(_ n: Int, hour: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: n, hour: hour))!
    }

    func testWeeklyAdherenceCountsDistinctProgramDays() {
        let program = ProgramSnapshot(id: UUID(), kind: .weekly, weekly: [a, nil, b, nil, a, nil, nil], rotation: [],
                                      activatedAt: day(2))
        let sessions = [
            // 2–8 Kasım: 3/3
            CompletedSession(date: day(2), templateID: a), CompletedSession(date: day(4), templateID: b),
            CompletedSession(date: day(6), templateID: a), CompletedSession(date: day(6, hour: 20), templateID: a),
            // 9–15 Kasım: 2/3 (+ serbest antrenman sayılmaz)
            CompletedSession(date: day(9), templateID: a), CompletedSession(date: day(11), templateID: b),
            CompletedSession(date: day(12), templateID: nil),
            // Bu hafta: 1/3
            CompletedSession(date: day(16), templateID: a)
        ]
        let weeks = AdherenceCalculator.weeks(program: program, completed: sessions, count: 8, now: day(17), calendar: calendar)
        XCTAssertEqual(weeks.count, 3, "etkinleştirmeden önceki haftalar dahil değil")
        XCTAssertEqual(weeks.map(\.done), [3, 2, 1])
        XCTAssertEqual(weeks.map(\.planned), [3, 3, 3])
        XCTAssertTrue(weeks.last!.isCurrent)
        XCTAssertEqual(AdherenceCalculator.completeWeekStreak(weeks), 0, "geçen hafta eksik")
        XCTAssertEqual(AdherenceCalculator.averagePercent(weeks), 83)
    }

    func testRotationUsesSelectedDaysAndStreak() {
        var program = ProgramSnapshot(id: UUID(), kind: .rotation, weekly: [], rotation: [a, b], activatedAt: day(2))
        program.rotationDays = [1, 3]
        let sessions = [day(3), day(5), day(10), day(12), day(16), day(18)].enumerated().map {
            CompletedSession(date: $0.element, templateID: $0.offset % 2 == 0 ? a : b)
        }
        let weeks = AdherenceCalculator.weeks(program: program, completed: sessions, count: 8, now: day(19), calendar: calendar)
        XCTAssertEqual(weeks.map(\.planned), [2, 2, 2])
        XCTAssertEqual(weeks.map(\.done), [2, 2, 2])
        XCTAssertEqual(AdherenceCalculator.completeWeekStreak(weeks), 3, "bu hafta da tamamlandı")
        XCTAssertEqual(weeks.first!.ratio, 1)
    }

    func testBadgesUseProgramStreak() {
        var input = BadgeInput()
        input.programWeekStreak = 5
        let result = Dictionary(uniqueKeysWithValues: BadgeEngine.evaluate(input).map { ($0.badge, $0) })
        XCTAssertTrue(result[.programWeeks4]!.isEarned)
        XCTAssertFalse(result[.programWeeks12]!.isEarned)
    }
}

// MARK: - Antrenman hatırlatıcısı
@MainActor
final class WorkoutReminderTests: XCTestCase {
    private var container: ModelContainer!
    private var scheduler: MockNotificationScheduler!
    private var defaults: UserDefaults!
    private var sut: TrainingViewModel!
    private var bench: ExerciseTemplate { ExerciseLibrary.template(forKey: "preset.bench-press")! }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: WorkoutTemplate.self, TrainingProgram.self, Workout.self, WorkoutEntry.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        scheduler = MockNotificationScheduler()
        defaults = makeTestDefaults("workoutReminder")
        sut = TrainingViewModel(sync: MockTrainingSync(), scheduler: scheduler, defaults: defaults)
        sut.configure(context: container.mainContext, user: AppUser.makeNew(id: "u1", email: "a@b.com", displayName: "Test"))
    }

    func testCalendarWeekdayMapping() {
        XCTAssertEqual(TrainingViewModel.calendarWeekday(fromIndex: 0), 2)   // Pazartesi
        XCTAssertEqual(TrainingViewModel.calendarWeekday(fromIndex: 5), 7)   // Cumartesi
        XCTAssertEqual(TrainingViewModel.calendarWeekday(fromIndex: 6), 1)   // Pazar
    }

    func testWeeklySlotsAndApply() async throws {
        let push = try sut.saveTemplate(name: "İtiş", exercises: [TemplateExercise(template: bench)])
        let legs = try sut.saveTemplate(name: "Bacak", exercises: [TemplateExercise(template: bench)])
        var week = Array(repeating: "", count: 7)
        week[0] = push.id.uuidString
        week[3] = legs.id.uuidString
        try sut.saveProgram(name: "Haftalık", kind: .weekly, weekly: week, rotation: [])

        XCTAssertEqual(sut.reminderSlots(), [
            WorkoutReminderSlot(weekday: 2, body: "Bugün: İtiş"),
            WorkoutReminderSlot(weekday: 5, body: "Bugün: Bacak")
        ])

        var settings = WorkoutReminderSettings()
        settings.isEnabled = true
        settings.hour = 7
        settings.minute = 30
        let ok = await sut.applyReminder(settings)
        XCTAssertTrue(ok)
        XCTAssertEqual(scheduler.workoutSlots?.count, 2)
        XCTAssertEqual(scheduler.workoutTime?.hour, 7)
        XCTAssertEqual(WorkoutReminderSettings.load(defaults: defaults), settings)
    }

    func testRotationSlotsUseSelectedDaysAndNextTemplate() throws {
        let a = try sut.saveTemplate(name: "A Günü", exercises: [TemplateExercise(template: bench)])
        let b = try sut.saveTemplate(name: "B Günü", exercises: [TemplateExercise(template: bench)])
        try sut.saveProgram(name: "Döngü", kind: .rotation, weekly: [], rotation: [a.id.uuidString, b.id.uuidString], rotationDays: [1, 4, 1])
        XCTAssertThrowsError(try sut.saveProgram(name: "Boş günler", kind: .rotation, weekly: [], rotation: [a.id.uuidString], rotationDays: []))

        let slots = sut.reminderSlots()
        XCTAssertEqual(slots.map(\.weekday), [3, 6], "Salı ve Cuma, tekrarsız")
        XCTAssertTrue(slots.allSatisfy { $0.body == "Sıradaki antrenman: A Günü" })

        let done = Workout(ownerID: "u1", title: "A", date: .now)
        done.templateID = a.id.uuidString
        container.mainContext.insert(done)
        try container.mainContext.save()
        XCTAssertTrue(sut.reminderSlots().allSatisfy { $0.body == "Sıradaki antrenman: B Günü" })
    }

    func testDeniedPermissionDisables() async {
        scheduler.status = .denied
        var settings = WorkoutReminderSettings()
        settings.isEnabled = true
        let ok = await sut.applyReminder(settings)
        XCTAssertFalse(ok)
        XCTAssertFalse(sut.reminderSettings.isEnabled)
        XCTAssertGreaterThan(scheduler.workoutCancelled, 0)
    }
}

// MARK: - Form ipuçları
final class ExerciseGuideTests: XCTestCase {
    func testEveryStrengthPresetHasGuide() {
        for template in ExerciseLibrary.presets where template.category == .strength {
            let guide = ExerciseGuides.guide(for: template.key)
            XCTAssertNotNil(guide, template.name)
            XCTAssertGreaterThanOrEqual(guide?.steps.count ?? 0, 3, template.name)
            XCTAssertFalse(guide?.mistakes.isEmpty ?? true, template.name)
            XCTAssertFalse(guide?.muscles.isEmpty ?? true, template.name)
        }
        XCTAssertNil(ExerciseGuides.guide(for: "custom.\(UUID().uuidString)"))
    }

    func testVideoSearchURLIsEncoded() {
        let url = ExerciseGuide.videoSearchURL(for: "Bench Press")
        XCTAssertEqual(url?.host, "www.youtube.com")
        XCTAssertTrue(url?.absoluteString.contains("search_query=Bench%20Press") ?? false)
    }
}
