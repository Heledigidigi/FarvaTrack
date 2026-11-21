import XCTest
import SwiftData
@testable import FarvaTrack

final class MockBodyMetricsSync: BodyMetricsSyncing {
    var remoteWeights: [WeightDTO] = []
    var remoteMeasurements: [MeasurementDTO] = []
    private(set) var uploadedWeights: [WeightDTO] = []
    private(set) var uploadedMeasurements: [MeasurementDTO] = []
    private(set) var deletedWeights: [String] = []
    private(set) var deletedMeasurements: [String] = []

    func uploadWeight(_ entry: WeightDTO, userID: String) async throws { uploadedWeights.append(entry) }
    func deleteWeight(id: String, userID: String) async throws { deletedWeights.append(id) }
    func fetchWeights(userID: String, since: Date) async throws -> [WeightDTO] { remoteWeights }

    func uploadMeasurement(_ entry: MeasurementDTO, userID: String) async throws { uploadedMeasurements.append(entry) }
    func deleteMeasurement(id: String, userID: String) async throws { deletedMeasurements.append(id) }
    func fetchMeasurements(userID: String, since: Date) async throws -> [MeasurementDTO] { remoteMeasurements }
}

final class WeightAnalyzerTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func point(_ day: Int, _ kg: Double) -> WeightPoint {
        WeightPoint(date: base.addingTimeInterval(Double(day) * 86_400), weightKg: kg)
    }

    func testBMIAndCategory() {
        let bmi = WeightAnalyzer.bmi(weightKg: 70, heightCm: 175)!
        XCTAssertEqual(bmi, 22.857, accuracy: 0.001)
        XCTAssertEqual(BMICategory(bmi: bmi), .normal)
        XCTAssertEqual(BMICategory(bmi: 18.4), .underweight)
        XCTAssertEqual(BMICategory(bmi: 27), .overweight)
        XCTAssertEqual(BMICategory(bmi: 31), .obese)
        XCTAssertNil(WeightAnalyzer.bmi(weightKg: 70, heightCm: 0))
    }

    func testHealthyRange() {
        let range = WeightAnalyzer.healthyRange(heightCm: 180)!
        XCTAssertEqual(range.lowerBound, 59.94, accuracy: 0.01)
        XCTAssertEqual(range.upperBound, 80.676, accuracy: 0.01)
        XCTAssertEqual(WeightAnalyzer.minimumHealthyWeight(heightCm: 180), 60.0)
    }

    func testGoalValidationBlocksUnderweightTarget() {
        XCTAssertEqual(
            WeightAnalyzer.validateGoal(targetKg: 55, currentKg: 70, heightCm: 180, age: 30),
            .belowHealthyBMI(minimumKg: 60.0)
        )
        XCTAssertEqual(WeightAnalyzer.validateGoal(targetKg: 60, currentKg: 70, heightCm: 180, age: 30), .ok)
        // Önerilen alt sınır gerçekten BMI ≥ 18,5 olmalı.
        let minimum = WeightAnalyzer.minimumHealthyWeight(heightCm: 167)!
        XCTAssertGreaterThanOrEqual(WeightAnalyzer.bmi(weightKg: minimum, heightCm: 167)!, 18.5)
    }

    func testGoalValidationBlocksWeightLossForMinors() {
        XCTAssertEqual(WeightAnalyzer.validateGoal(targetKg: 60, currentKg: 70, heightCm: 170, age: 16), .minorWeightLoss)
        XCTAssertEqual(WeightAnalyzer.validateGoal(targetKg: 70, currentKg: 70, heightCm: 170, age: 16), .ok)
        XCTAssertEqual(WeightAnalyzer.validateGoal(targetKg: 74, currentKg: 70, heightCm: 170, age: 16), .ok)
    }

    func testGoalValidationRange() {
        XCTAssertEqual(WeightAnalyzer.validateGoal(targetKg: 10, currentKg: nil, heightCm: nil, age: nil), .outOfRange)
        XCTAssertNotNil(WeightGoalValidation.minorWeightLoss.message)
        XCTAssertNil(WeightGoalValidation.ok.message)
    }

    func testMovingAverage() {
        let points = [point(0, 80), point(1, 82), point(2, 81), point(10, 79)]
        let trend = WeightAnalyzer.movingAverage(points)
        XCTAssertEqual(trend.map(\.weightKg)[0], 80, accuracy: 0.001)
        XCTAssertEqual(trend.map(\.weightKg)[2], 81, accuracy: 0.001)
        XCTAssertEqual(trend.map(\.weightKg)[3], 79, accuracy: 0.001, "7 günden eski tartılar ortalamaya girmez")
    }

    func testChangeAndProgress() {
        let now = base.addingTimeInterval(10 * 86_400)
        let points = [point(0, 80), point(5, 79), point(10, 78)]
        XCTAssertEqual(WeightAnalyzer.change(points, days: 7, now: now)!, -1, accuracy: 0.001)
        XCTAssertEqual(WeightAnalyzer.change(points, days: 30, now: now)!, -2, accuracy: 0.001)
        XCTAssertNil(WeightAnalyzer.change([point(10, 78)], days: 7, now: now))

        XCTAssertEqual(WeightAnalyzer.goalProgress(start: 80, current: 78, target: 75), 0.4, accuracy: 0.001)
        XCTAssertEqual(WeightAnalyzer.goalProgress(start: 80, current: 82, target: 75), 0)
        XCTAssertEqual(WeightAnalyzer.goalProgress(start: 60, current: 63, target: 65), 0.6, accuracy: 0.001)
    }

    func testWeeklyRateAndWeeksToGoal() {
        // Günde 0,1 kg azalma → haftada −0,7 kg
        let points = (0...21).map { point($0, 80 - Double($0) * 0.1) }
        let rate = WeightAnalyzer.weeklyRate(points)!
        XCTAssertEqual(rate, -0.7, accuracy: 0.001)
        XCTAssertEqual(WeightAnalyzer.weeksToGoal(current: 77.9, target: 75, weeklyRate: rate), 5)
        XCTAssertNil(WeightAnalyzer.weeksToGoal(current: 77.9, target: 80, weeklyRate: rate), "ters yönde tahmin yok")
        XCTAssertNil(WeightAnalyzer.weeklyRate(Array(points.prefix(5))), "14 günden az veri")
    }

    func testKgText() {
        XCTAssertEqual(WeightAnalyzer.kgText(0.02, signed: true), "0,0 kg")
        XCTAssertTrue(WeightAnalyzer.kgText(-1.2, signed: true).hasPrefix("−"))
        XCTAssertTrue(WeightAnalyzer.kgText(0.5, signed: true).hasPrefix("+"))
    }
}

@MainActor
final class BodyMetricsViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var sync: MockBodyMetricsSync!
    private var scheduler: MockNotificationScheduler!
    private var defaults: UserDefaults!
    private var sut: BodyMetricsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "pendingWeightDeletes.uid-1")
        UserDefaults.standard.removeObject(forKey: "pendingMeasurementDeletes.uid-1")
        container = try ModelContainer(
            for: WeightEntry.self, MeasurementEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        sync = MockBodyMetricsSync()
        scheduler = MockNotificationScheduler()
        defaults = makeTestDefaults("body")

        var user = AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test")
        user.heightCm = 180
        user.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)
        sut = BodyMetricsViewModel(sync: sync, scheduler: scheduler, defaults: defaults)
        sut.configure(context: context, user: user)
    }

    private func weights() throws -> [WeightEntry] { try context.fetch(FetchDescriptor<WeightEntry>()) }

    func testSaveWeightRoundsAndUploads() async throws {
        let entry = try sut.saveWeight(72.345, note: "  sabah  ")
        await settleTasks()
        XCTAssertEqual(entry.weightKg, 72.3, accuracy: 0.0001)
        XCTAssertEqual(entry.note, "sabah")
        XCTAssertEqual(sync.uploadedWeights.count, 1)
        XCTAssertEqual(sut.latestWeight() ?? 0, 72.3, accuracy: 0.0001)
        XCTAssertEqual(sut.bmi(for: 72.3) ?? 0, 22.31, accuracy: 0.01)
    }

    func testOneWeighInPerDay() throws {
        try sut.saveWeight(72, note: "")
        try sut.saveWeight(71.5, note: nil)
        XCTAssertEqual(try weights().count, 1)
        XCTAssertEqual(try weights().first?.weightKg, 71.5)
        XCTAssertNil(try weights().first?.note)

        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        try sut.saveWeight(73, date: lastWeek)
        XCTAssertEqual(try weights().count, 2)
        XCTAssertEqual(sut.latestWeight(), 71.5, "en son tarihli tartı döner")
    }

    func testWeightValidation() {
        XCTAssertThrowsError(try sut.saveWeight(10))
        XCTAssertThrowsError(try sut.saveWeight(500))
        XCTAssertThrowsError(try sut.saveWeight(70, date: .now.addingTimeInterval(86_400)))
    }

    func testDeleteWeightQueuesRemoteDeletion() async throws {
        let entry = try sut.saveWeight(70)
        let id = entry.id.uuidString
        sut.deleteWeight(entry)
        await settleTasks()
        XCTAssertTrue(try weights().isEmpty)
        XCTAssertEqual(sync.deletedWeights, [id])
    }

    func testGoalValidationUsesProfile() {
        XCTAssertEqual(sut.validateGoal(55, currentKg: 70), .belowHealthyBMI(minimumKg: 60))
        XCTAssertEqual(sut.validateGoal(65, currentKg: 70), .ok)
    }

    func testMinorCannotSetWeightLossGoal() {
        var teen = AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test")
        teen.heightCm = 170
        teen.birthDate = Calendar.current.date(byAdding: .year, value: -15, to: .now)
        sut.configure(context: context, user: teen)
        XCTAssertEqual(sut.validateGoal(60, currentKg: 65), .minorWeightLoss)
    }

    func testMeasurementsSaveValidateAndChanges() throws {
        XCTAssertThrowsError(try sut.saveMeasurement([:]))
        XCTAssertThrowsError(try sut.saveMeasurement([.waist: 5]))

        let older = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        try sut.saveMeasurement([.waist: 90, .wrist: 17], date: older)
        XCTAssertThrowsError(try sut.saveMeasurement([.wrist: 45]), "bilek aralık dışı")
        try sut.saveMeasurement([.waist: 87.54])

        let all = try context.fetch(FetchDescriptor<MeasurementEntry>())
        XCTAssertEqual(all.count, 2)
        let changes = BodyMetricsViewModel.latestChanges(all)
        XCTAssertEqual(changes[.waist]?.value ?? 0, 87.5, accuracy: 0.001)
        XCTAssertEqual(changes[.waist]?.change ?? 0, -2.5, accuracy: 0.001)
        XCTAssertEqual(changes[.wrist]?.value, 17)
        XCTAssertNil(changes[.wrist]?.change)
        XCTAssertNil(changes[.neck])
    }

    func testWeighInReminder() async {
        var settings = WeighInReminderSettings()
        settings.isEnabled = true
        settings.weekday = 2
        settings.hour = 7
        settings.minute = 30
        let ok = await sut.applyReminder(settings)
        XCTAssertTrue(ok)
        XCTAssertEqual(scheduler.weighInScheduled?.weekday, 2)
        XCTAssertEqual(scheduler.weighInScheduled?.hour, 7)
        XCTAssertEqual(WeighInReminderSettings.load(defaults: defaults), settings)

        scheduler.status = .denied
        let denied = await sut.applyReminder(settings)
        XCTAssertFalse(denied)
        XCTAssertFalse(sut.reminderSettings.isEnabled)
    }

    func testSyncMergesRemote() async throws {
        let local = try sut.saveWeight(70)
        await settleTasks()
        var newer = local.dto
        newer.weightKg = 69
        newer.updatedAt = local.updatedAt.addingTimeInterval(60)
        let remoteOnly = WeightDTO(
            id: UUID().uuidString, date: .now.addingTimeInterval(-10 * 86_400), weightKg: 72,
            note: nil, createdAt: .now, updatedAt: .now
        )
        let measurement = MeasurementDTO(
            id: UUID().uuidString, date: .now, waistCm: 85, chestCm: nil, hipCm: nil,
            armCm: nil, thighCm: nil, neckCm: nil, createdAt: .now, updatedAt: .now
        )
        sync.remoteWeights = [newer, remoteOnly]
        sync.remoteMeasurements = [measurement]
        await sut.syncAll()

        XCTAssertEqual(try weights().count, 2)
        XCTAssertEqual(local.weightKg, 69)
        let measurements = try context.fetch(FetchDescriptor<MeasurementEntry>())
        XCTAssertEqual(measurements.first?.waistCm, 85)
        XCTAssertFalse(measurements.first?.needsSync ?? true)
    }
}
