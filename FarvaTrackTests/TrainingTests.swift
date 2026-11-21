import XCTest
import SwiftData
@testable import FarvaTrack

final class MockTrainingSync: TrainingSyncing {
    var remoteTemplates: [WorkoutTemplateDTO] = []
    var remotePrograms: [TrainingProgramDTO] = []
    private(set) var uploadedTemplates: [WorkoutTemplateDTO] = []
    private(set) var uploadedPrograms: [TrainingProgramDTO] = []
    private(set) var deletedTemplates: [String] = []
    private(set) var deletedPrograms: [String] = []

    func uploadTemplate(_ dto: WorkoutTemplateDTO, userID: String) async throws { uploadedTemplates.append(dto) }
    func deleteTemplate(id: String, userID: String) async throws { deletedTemplates.append(id) }
    func fetchTemplates(userID: String) async throws -> [WorkoutTemplateDTO] { remoteTemplates }
    func uploadProgram(_ dto: TrainingProgramDTO, userID: String) async throws { uploadedPrograms.append(dto) }
    func deleteProgram(id: String, userID: String) async throws { deletedPrograms.append(id) }
    func fetchPrograms(userID: String) async throws -> [TrainingProgramDTO] { remotePrograms }
}

final class MockRestScheduler: RestTimerScheduling {
    private(set) var scheduled: [TimeInterval] = []
    private(set) var cancelled = 0
    func scheduleRestEnd(after seconds: TimeInterval, exerciseName: String) async { scheduled.append(seconds) }
    func cancelRestEnd() async { cancelled += 1 }
}

final class MemoryLiveStore: LiveSessionStoring {
    var stored: [String: LiveSession] = [:]
    func load(userID: String) -> LiveSession? { stored[userID] }
    func save(_ session: LiveSession, userID: String) { stored[userID] = session }
    func clear(userID: String) { stored[userID] = nil }
}

// MARK: - Planlayıcı
final class ProgramPlannerTests: XCTestCase {
    private let calendar = utcCalendar()
    private let a = UUID(), b = UUID(), c = UUID()

    /// 2026-11-16 Pazartesi
    private func day(_ n: Int, hour: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: n, hour: hour))!
    }

    func testWeekdayIndexStartsMonday() {
        XCTAssertEqual(ProgramPlanner.weekdayIndex(of: day(16), calendar: calendar), 0)
        XCTAssertEqual(ProgramPlanner.weekdayIndex(of: day(22), calendar: calendar), 6)
    }

    func testNoProgram() {
        XCTAssertEqual(ProgramPlanner.plan(for: nil, completed: [], on: day(16), existingTemplates: [a], calendar: calendar), .none)
    }

    func testWeeklyWorkoutRestAndDone() {
        let program = ProgramSnapshot(id: UUID(), kind: .weekly, weekly: [a, nil, b, nil, a, nil, nil], rotation: [], activatedAt: day(1))
        let all: Set<UUID> = [a, b]

        XCTAssertEqual(ProgramPlanner.plan(for: program, completed: [], on: day(16), existingTemplates: all, calendar: calendar),
                       .workout(templateID: a, isDone: false))
        XCTAssertEqual(ProgramPlanner.plan(for: program, completed: [CompletedSession(date: day(16, hour: 9), templateID: a)],
                                           on: day(16), existingTemplates: all, calendar: calendar),
                       .workout(templateID: a, isDone: true))

        // Salı dinlenme, sıradaki Çarşamba B
        let rest = ProgramPlanner.plan(for: program, completed: [], on: day(17), existingTemplates: all, calendar: calendar)
        XCTAssertEqual(rest, .rest(next: UpcomingSession(date: calendar.startOfDay(for: day(18)), templateID: b)))

        // Cumartesi → sıradaki Pazartesi
        let weekend = ProgramPlanner.plan(for: program, completed: [], on: day(21), existingTemplates: all, calendar: calendar)
        XCTAssertEqual(weekend, .rest(next: UpcomingSession(date: calendar.startOfDay(for: day(23)), templateID: a)))
    }

    func testWeeklyIgnoresDeletedTemplates() {
        let program = ProgramSnapshot(id: UUID(), kind: .weekly, weekly: [a, nil, nil, nil, nil, nil, nil], rotation: [], activatedAt: day(1))
        XCTAssertEqual(ProgramPlanner.plan(for: program, completed: [], on: day(16), existingTemplates: [b], calendar: calendar), .none)
    }

    func testRotationAdvancesAfterEachSession() {
        let program = ProgramSnapshot(id: UUID(), kind: .rotation, weekly: [], rotation: [a, b, c], activatedAt: day(10))
        let all: Set<UUID> = [a, b, c]

        XCTAssertEqual(ProgramPlanner.plan(for: program, completed: [], on: day(16), existingTemplates: all, calendar: calendar),
                       .workout(templateID: a, isDone: false))

        let history = [CompletedSession(date: day(12), templateID: a), CompletedSession(date: day(14), templateID: b)]
        XCTAssertEqual(ProgramPlanner.plan(for: program, completed: history, on: day(16), existingTemplates: all, calendar: calendar),
                       .workout(templateID: c, isDone: false))

        let wrapped = history + [CompletedSession(date: day(15), templateID: c)]
        XCTAssertEqual(ProgramPlanner.plan(for: program, completed: wrapped, on: day(16), existingTemplates: all, calendar: calendar),
                       .workout(templateID: a, isDone: false))

        // Bugün yapıldıysa tamamlandı görünür
        let today = history + [CompletedSession(date: day(16, hour: 8), templateID: c)]
        XCTAssertEqual(ProgramPlanner.plan(for: program, completed: today, on: day(16), existingTemplates: all, calendar: calendar),
                       .workout(templateID: c, isDone: true))
    }

    func testRotationIgnoresSessionsBeforeActivationAndOtherWorkouts() {
        let program = ProgramSnapshot(id: UUID(), kind: .rotation, weekly: [], rotation: [a, b], activatedAt: day(14))
        let history = [
            CompletedSession(date: day(12), templateID: a),     // etkinleştirmeden önce
            CompletedSession(date: day(15), templateID: nil)     // serbest antrenman
        ]
        XCTAssertEqual(ProgramPlanner.plan(for: program, completed: history, on: day(16), existingTemplates: [a, b], calendar: calendar),
                       .workout(templateID: a, isDone: false))
    }

    func testPresetsAreValidAndUseLibraryExercises() {
        for preset in PresetPrograms.all {
            XCTAssertFalse(preset.days.isEmpty, preset.name)
            for day in preset.days {
                XCTAssertTrue(day.exercises.allSatisfy(\.isValid), day.name)
                for exercise in day.exercises {
                    XCTAssertNotNil(ExerciseLibrary.template(forKey: exercise.exerciseKey), "\(preset.name): \(exercise.exerciseKey)")
                }
            }
            if preset.kind == .weekly {
                XCTAssertEqual(preset.weeklyLayout.count, 7, preset.name)
                XCTAssertTrue(preset.weeklyLayout.compactMap { $0 }.allSatisfy { $0 < preset.days.count }, preset.name)
            }
        }
    }
}

// MARK: - ViewModel
@MainActor
final class TrainingViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var sync: MockTrainingSync!
    private var sut: TrainingViewModel!

    private var bench: ExerciseTemplate { ExerciseLibrary.template(forKey: "preset.bench-press")! }
    private var running: ExerciseTemplate { ExerciseLibrary.template(forKey: "preset.running")! }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: WorkoutTemplate.self, TrainingProgram.self, Workout.self, WorkoutEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        sync = MockTrainingSync()
        sut = TrainingViewModel(sync: sync, defaults: makeTestDefaults("training"))
        sut.configure(context: context, user: AppUser.makeNew(id: "u1", email: "a@b.com", displayName: "Test"))
    }

    /// Arka plandaki yükleme / hatırlatıcı görevleri bitmeden bellek içi veritabanı bırakılmaz
    /// (aksi halde sonraki testlerde kapanmış veritabanına erişilip çökme olabiliyordu).
    override func tearDown() async throws {
        await settleTasks()
        sut = nil
        sync = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func testTemplateValidation() {
        XCTAssertThrowsError(try sut.saveTemplate(name: "A", exercises: [TemplateExercise(template: bench)]))
        XCTAssertThrowsError(try sut.saveTemplate(name: "İtiş", exercises: []))
        var bad = TemplateExercise(template: bench)
        bad.targetReps = 0
        XCTAssertThrowsError(try sut.saveTemplate(name: "İtiş", exercises: [bad]))
    }

    func testTemplateSaveUploadsAndRejectsDuplicateName() async throws {
        try sut.saveTemplate(name: "İtiş", exercises: [TemplateExercise(template: bench)])
        await settleTasks()
        XCTAssertEqual(sync.uploadedTemplates.map(\.name), ["İtiş"])
        XCTAssertThrowsError(try sut.saveTemplate(name: "itiş", exercises: [TemplateExercise(template: bench)]))
    }

    func testTemplateFromWorkoutUsesCommonRepsAndLastWeight() throws {
        let workout = Workout(ownerID: "u1", title: "Göğüs", date: .now)
        context.insert(workout)
        let entry = WorkoutEntry(order: 0, template: bench, durationMinutes: 0, sets: [
            WorkoutSet(reps: 8, weightKg: 60), WorkoutSet(reps: 8, weightKg: 62.5), WorkoutSet(reps: 6, weightKg: 65)
        ])
        context.insert(entry)
        workout.entries.append(entry)
        let cardio = WorkoutEntry(order: 1, template: running, durationMinutes: 25, sets: [])
        context.insert(cardio)
        workout.entries.append(cardio)

        let exercises = TrainingViewModel.templateExercises(from: workout)
        XCTAssertEqual(exercises.count, 2)
        XCTAssertEqual(exercises[0].targetSets, 3)
        XCTAssertEqual(exercises[0].targetReps, 8)
        XCTAssertEqual(exercises[0].targetWeightKg, 65)
        XCTAssertEqual(exercises[1].mode, .duration)
        XCTAssertEqual(exercises[1].durationMinutes, 25)
    }

    func testProgramValidationAndSingleActive() throws {
        let push = try sut.saveTemplate(name: "İtiş", exercises: [TemplateExercise(template: bench)])
        XCTAssertThrowsError(try sut.saveProgram(name: "Boş", kind: .weekly, weekly: [], rotation: []))
        XCTAssertThrowsError(try sut.saveProgram(name: "Boş", kind: .rotation, weekly: [], rotation: ["olmayan"]))

        let first = try sut.saveProgram(name: "Program 1", kind: .weekly, weekly: [push.id.uuidString], rotation: [])
        XCTAssertTrue(first.isActive, "ilk program kendiliğinden aktif olur")

        let second = try sut.saveProgram(name: "Program 2", kind: .rotation, weekly: [], rotation: [push.id.uuidString], activate: true)
        XCTAssertTrue(second.isActive)
        XCTAssertFalse(first.isActive)
        XCTAssertEqual(sut.activeProgram()?.id, second.id)

        sut.setActive(nil)
        XCTAssertNil(sut.activeProgram())
    }

    func testDeletingTemplateRemovesItFromPrograms() async throws {
        let push = try sut.saveTemplate(name: "İtiş", exercises: [TemplateExercise(template: bench)])
        let pull = try sut.saveTemplate(name: "Çekiş", exercises: [TemplateExercise(template: bench)])
        let program = try sut.saveProgram(
            name: "PPL", kind: .rotation, weekly: [push.id.uuidString],
            rotation: [push.id.uuidString, pull.id.uuidString]
        )
        let pushID = push.id.uuidString
        sut.deleteTemplate(push)
        await settleTasks()
        XCTAssertEqual(program.rotationTemplateIDs, [pull.id.uuidString])
        XCTAssertEqual(TrainingProgram.normalizedWeek(program.weekdayTemplateIDs)[0], "")
        XCTAssertEqual(sync.deletedTemplates, [pushID])
    }

    func testAdoptPresetCreatesTemplatesAndActiveProgram() throws {
        let preset = PresetPrograms.all.first { $0.id == "push-pull-legs" }!
        let program = try sut.adopt(preset)
        XCTAssertTrue(program.isActive)
        XCTAssertEqual(program.kind, .rotation)
        XCTAssertEqual(program.rotationTemplateIDs.count, 3)
        XCTAssertEqual(Set(sut.templates().map(\.name)), ["İtiş", "Çekiş", "Bacak"])

        // İkinci kez eklenince isimler çakışmaz
        let again = try sut.adopt(preset)
        XCTAssertEqual(sut.templates().count, 6)
        XCTAssertNotEqual(again.name, program.name)
        XCTAssertTrue(again.isActive)
        XCTAssertFalse(program.isActive)

        let weekly = try sut.adopt(PresetPrograms.all.first { $0.id == "full-body-3" }!)
        XCTAssertEqual(weekly.weekdayTemplateIDs.filter { !$0.isEmpty }.count, 3)
    }

    func testTodayPlanUsesCompletedWorkouts() throws {
        let push = try sut.saveTemplate(name: "İtiş", exercises: [TemplateExercise(template: bench)])
        let pull = try sut.saveTemplate(name: "Çekiş", exercises: [TemplateExercise(template: bench)])
        try sut.saveProgram(name: "Döngü", kind: .rotation, weekly: [], rotation: [push.id.uuidString, pull.id.uuidString])
        XCTAssertEqual(sut.todayPlan(), .workout(templateID: push.id, isDone: false))

        let workout = Workout(ownerID: "u1", title: "İtiş", date: .now)
        workout.templateID = push.id.uuidString
        context.insert(workout)
        try context.save()
        XCTAssertEqual(sut.todayPlan(), .workout(templateID: push.id, isDone: true))
        XCTAssertEqual(sut.todayPlan(on: .now.addingTimeInterval(86_400)), .workout(templateID: pull.id, isDone: false))
    }

    func testSyncDownloadsAndKeepsSingleActive() async throws {
        let local = try sut.saveTemplate(name: "Yerel", exercises: [TemplateExercise(template: bench)])
        let localProgram = try sut.saveProgram(name: "Yerel Program", kind: .weekly, weekly: [local.id.uuidString], rotation: [])
        await settleTasks()

        let remoteTemplate = WorkoutTemplateDTO(id: UUID().uuidString, name: "Uzak", exercises: [TemplateExercise(template: running)],
                                                createdAt: .now, updatedAt: .now)
        let remoteProgram = TrainingProgramDTO(
            id: UUID().uuidString, name: "Uzak Program", kind: "rotation", weekdayTemplateIDs: [],
            rotationTemplateIDs: [remoteTemplate.id], isActive: true, activatedAt: .now.addingTimeInterval(60),
            createdAt: .now, updatedAt: .now
        )
        sync.remoteTemplates = [remoteTemplate]
        sync.remotePrograms = [remoteProgram]
        await sut.syncAll()

        XCTAssertEqual(Set(sut.templates().map(\.name)), ["Yerel", "Uzak"])
        XCTAssertEqual(sut.programs().filter(\.isActive).count, 1)
        XCTAssertEqual(sut.activeProgram()?.name, "Uzak Program", "en son etkinleştirilen kalır")
        XCTAssertFalse(localProgram.isActive)
    }
}

// MARK: - Canlı mod
@MainActor
final class LiveWorkoutTests: XCTestCase {
    private var store: MemoryLiveStore!
    private var rest: MockRestScheduler!
    private var clock: Date!
    private var sut: LiveWorkoutViewModel!
    private var container: ModelContainer!

    private var bench: ExerciseTemplate { ExerciseLibrary.template(forKey: "preset.bench-press")! }
    private var plank: ExerciseTemplate { ExerciseLibrary.template(forKey: "preset.plank")! }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: WorkoutTemplate.self, Workout.self, WorkoutEntry.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = MemoryLiveStore()
        rest = MockRestScheduler()
        clock = Date(timeIntervalSince1970: 1_795_000_000)
        sut = LiveWorkoutViewModel(store: store, restScheduler: rest, now: { [unowned self] in self.clock })
        sut.configure(userID: "u1")
    }

    /// Arka plan görevleri bitmeden bellek içi veritabanı bırakılmaz (sonraki testlerde çökmeyi önler).
    override func tearDown() async throws {
        await settleTasks()
        try await super.tearDown()
    }

    private func makeTemplate() -> WorkoutTemplate {
        let template = WorkoutTemplate(ownerID: "u1", name: "İtiş", exercises: [
            TemplateExercise(template: bench, sets: 2, reps: 8, weightKg: 50, restSeconds: 90),
            TemplateExercise(template: plank, durationMinutes: 3)
        ])
        container.mainContext.insert(template)
        return template
    }

    private func previousWorkout() -> Workout {
        let workout = Workout(ownerID: "u1", title: "Eski", date: clock.addingTimeInterval(-3 * 86_400))
        container.mainContext.insert(workout)
        let entry = WorkoutEntry(order: 0, template: bench, durationMinutes: 0, sets: [WorkoutSet(reps: 8, weightKg: 60), WorkoutSet(reps: 7, weightKg: 62.5)])
        container.mainContext.insert(entry)
        workout.entries.append(entry)
        return workout
    }

    func testStartPrefillsFromPreviousPerformance() throws {
        sut.start(template: makeTemplate(), programID: "p1", workouts: [previousWorkout()])
        let session = try XCTUnwrap(sut.session)
        XCTAssertEqual(session.exercises[0].sets.map(\.weightKg), [60, 62.5])
        XCTAssertEqual(session.exercises[0].sets.map(\.reps), [8, 8], "tekrar hedeften gelir")
        XCTAssertTrue(session.exercises[0].previousText(at: 1)?.hasSuffix("kg × 7") ?? false)
        XCTAssertNil(session.exercises[0].previousText(at: 5))
        XCTAssertEqual(session.exercises[1].durationMinutes, 3)
        XCTAssertEqual(session.progress.total, 3)
        XCTAssertNotNil(store.stored["u1"], "oturum her değişiklikte kaydedilir")
    }

    func testStartWithoutHistoryUsesTargetWeight() throws {
        sut.start(template: makeTemplate(), programID: nil, workouts: [])
        XCTAssertEqual(sut.session?.exercises[0].sets.map(\.weightKg), [50, 50])
    }

    func testToggleSetStartsRestAndLastStepDoesNot() async throws {
        sut.start(template: makeTemplate(), programID: nil, workouts: [])
        let exercise = try XCTUnwrap(sut.session?.exercises[0])
        sut.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        XCTAssertEqual(sut.session?.restEndsAt, clock.addingTimeInterval(90))
        XCTAssertEqual(sut.restRemaining, 90, accuracy: 0.001)

        sut.adjustRest(by: 15)
        XCTAssertEqual(sut.session?.restEndsAt, clock.addingTimeInterval(105))
        sut.adjustRest(by: -200)
        XCTAssertNil(sut.session?.restEndsAt, "süre sıfırın altına inerse dinlenme biter")

        sut.toggleSet(exerciseID: exercise.id, setID: exercise.sets[1].id)
        let plank = try XCTUnwrap(sut.session?.exercises[1])
        sut.toggleDuration(exerciseID: plank.id)
        XCTAssertEqual(sut.session?.progress.done, 3)
        await settleTasks()
        XCTAssertFalse(rest.scheduled.isEmpty)
    }

    func testFinishDraftOnlyDoneSetsOrAsPlanned() throws {
        sut.start(template: makeTemplate(), programID: "p1", workouts: [])
        XCTAssertThrowsError(try sut.finishDraft(asPlanned: false), "hiç set işaretlenmedi")

        let planned = try sut.finishDraft(asPlanned: true)
        XCTAssertEqual(planned.entries.count, 2)
        XCTAssertEqual(planned.entries[0].sets.count, 2)
        XCTAssertEqual(planned.programID, "p1")
        XCTAssertNotNil(planned.templateID)

        let exercise = try XCTUnwrap(sut.session?.exercises[0])
        sut.updateSet(exerciseID: exercise.id, setID: exercise.sets[0].id, reps: 10, weightKg: 55)
        sut.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        let partial = try sut.finishDraft(asPlanned: false)
        XCTAssertEqual(partial.entries.count, 1, "yapılmayan süre egzersizi kaydedilmez")
        XCTAssertEqual(partial.entries[0].sets.map(\.reps), [10])
        XCTAssertEqual(partial.entries[0].sets.map(\.weightKg), [55])
    }

    func testAddRemoveSetsAndLimits() throws {
        sut.start(template: makeTemplate(), programID: nil, workouts: [])
        let id = try XCTUnwrap(sut.session?.exercises[0].id)
        sut.addSet(exerciseID: id)
        XCTAssertEqual(sut.session?.exercises[0].sets.count, 3)
        for set in sut.session!.exercises[0].sets { sut.removeSet(exerciseID: id, setID: set.id) }
        XCTAssertEqual(sut.session?.exercises[0].sets.count, 1, "son set silinemez")
    }

    func testSessionSurvivesRestartAndEndClears() throws {
        sut.start(template: makeTemplate(), programID: nil, workouts: [])
        let restored = LiveWorkoutViewModel(store: store, restScheduler: rest, now: { [unowned self] in self.clock })
        restored.configure(userID: "u1")
        XCTAssertEqual(restored.session?.title, "İtiş")

        // Başka oturum açıkken yenisi başlamaz
        restored.start(template: makeTemplate(), programID: nil, workouts: [])
        XCTAssertNotNil(restored.errorMessage)

        restored.end()
        XCTAssertNil(store.stored["u1"])
    }
}

// MARK: - Elle adım
final class StepMergerTests: XCTestCase {
    private let calendar = utcCalendar()
    private func day(_ n: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: n))! }

    func testManualOverridesHealthAndAddsMissingDays() {
        let health = [
            DailyActivity(date: day(16), steps: 4_000, distanceKm: 3, activeEnergyKcal: 150),
            DailyActivity(date: day(17), steps: 2_000, distanceKm: 1.5, activeEnergyKcal: 80)
        ]
        let merged = StepMerger.merge(health: health, manual: [day(17).addingTimeInterval(3_600): 9_000, day(18): 5_000],
                                      heightCm: 175, calendar: calendar)
        XCTAssertEqual(merged.map(\.steps), [4_000, 9_000, 5_000])
        XCTAssertEqual(merged[0].activeEnergyKcal, 150)
        XCTAssertEqual(merged[1].activeEnergyKcal, 0, "elle girilen günde kalori adımdan tahmin edilir")
        XCTAssertGreaterThan(merged[1].distanceKm, 5)
        XCTAssertEqual(StepMerger.merge(health: health, manual: [:], heightCm: nil, calendar: calendar), health)
    }
}

@MainActor
final class ManualStepTests: XCTestCase {
    final class MockManualSync: ManualStepSyncing {
        var remote: [ManualStepDTO] = []
        private(set) var uploaded: [ManualStepDTO] = []
        private(set) var deleted: [String] = []
        func upload(_ entry: ManualStepDTO, userID: String) async throws { uploaded.append(entry) }
        func delete(id: String, userID: String) async throws { deleted.append(id) }
        func fetch(userID: String, since: Date) async throws -> [ManualStepDTO] { remote }
    }

    private var container: ModelContainer!
    private var sync: MockManualSync!
    private var health: MockHealthProvider!
    private var published: [StepsSnapshot] = []
    private var sut: StepsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: ManualStepEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sync = MockManualSync()
        health = MockHealthProvider()
        health.isHealthDataAvailable = false
        published = []
        sut = StepsViewModel(health: health, widgetPublisher: { [unowned self] in self.published.append($0) }, manualSync: sync)
        var user = AppUser.makeNew(id: "u1", email: "a@b.com", displayName: "Test")
        user.heightCm = 175
        user.dailyStepGoal = 8_000
        sut.configure(user: user)
        sut.attach(context: container.mainContext, userID: "u1")
        await sut.start()
    }

    /// Arka plan görevleri bitmeden bellek içi veritabanı bırakılmaz (sonraki testlerde çökmeyi önler).
    override func tearDown() async throws {
        await settleTasks()
        try await super.tearDown()
    }

    func testManualStepsWorkWithoutHealth() async throws {
        XCTAssertEqual(sut.access, .unavailable)
        try sut.saveManual(steps: 6_500, for: .now)
        await settleTasks()
        XCTAssertEqual(sut.stats(for: .day).steps, 6_500)
        XCTAssertTrue(sut.isTodayManual)
        XCTAssertEqual(published.last?.steps, 6_500)
        XCTAssertEqual(sync.uploaded.count, 1)

        // Aynı güne ikinci kayıt günceller
        try sut.saveManual(steps: 7_000, for: .now)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<ManualStepEntry>()).count, 1)
        XCTAssertEqual(sut.stats(for: .day).steps, 7_000)
    }

    func testValidationAndDelete() async throws {
        XCTAssertThrowsError(try sut.saveManual(steps: -1, for: .now))
        XCTAssertThrowsError(try sut.saveManual(steps: 1_000, for: .now.addingTimeInterval(3 * 86_400)))

        try sut.saveManual(steps: 3_000, for: .now)
        sut.deleteManual(for: .now)
        await settleTasks()
        XCTAssertFalse(sut.isTodayManual)
        XCTAssertEqual(sut.stats(for: .day).steps, 0)
        XCTAssertEqual(sync.deleted.count, 1)
    }

    func testSyncDownloadsRemoteEntries() async {
        sync.remote = [ManualStepDTO(id: UUID().uuidString, day: Calendar.current.startOfDay(for: .now), steps: 4_200,
                                     createdAt: .now, updatedAt: .now)]
        await sut.syncManual()
        XCTAssertEqual(sut.manualValue(for: .now), 4_200)
    }
}
