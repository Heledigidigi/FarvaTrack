import XCTest
import SwiftData
@testable import FarvaTrack

final class MockWorkoutSync: WorkoutSyncing {
    var remote: [WorkoutDTO] = []
    private(set) var uploaded: [WorkoutDTO] = []
    private(set) var deleted: [String] = []

    func upload(_ workout: WorkoutDTO, userID: String) async throws { uploaded.append(workout) }
    func deleteWorkout(id: String, userID: String) async throws { deleted.append(id) }
    func fetchWorkouts(userID: String) async throws -> [WorkoutDTO] { remote }
}

@MainActor
final class ExerciseViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var sync: MockWorkoutSync!
    private var sut: ExerciseViewModel!

    private var benchPress: ExerciseTemplate { ExerciseLibrary.template(forKey: "preset.bench-press")! }
    private var running: ExerciseTemplate { ExerciseLibrary.template(forKey: "preset.running")! }

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "pendingWorkoutDeletes.uid-1")

        container = try ModelContainer(
            for: Workout.self, WorkoutEntry.self, Exercise.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        sync = MockWorkoutSync()

        var user = AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test")
        user.weightKg = 80

        sut = ExerciseViewModel(sync: sync)
        sut.configure(context: context, user: user)
    }

    /// Arka plan görevleri bitmeden bellek içi veritabanı bırakılmaz (sonraki testlerde çökmeyi önler).
    override func tearDown() async throws {
        await settleTasks()
        try await super.tearDown()
    }

    private func draft(with entries: [DraftEntry]) -> WorkoutDraft {
        var draft = WorkoutDraft()
        draft.entries = entries
        return draft
    }

    private func benchEntry(sets: Int = 3) -> DraftEntry {
        var entry = DraftEntry(template: benchPress)
        entry.sets = (0..<sets).map { _ in WorkoutSet(reps: 10, weightKg: 60) }
        return entry
    }

    private func workoutCount() throws -> Int {
        try context.fetch(FetchDescriptor<Workout>()).count
    }

    // MARK: - Kaydetme
    func testSaveComputesDurationAndCalories() throws {
        // 3 set × 2,5 dk = 7,5 dk; MET 5,0 × 80 kg × 7,5/60 = 50 kcal
        let workout = try sut.save(draft(with: [benchEntry()]))
        XCTAssertEqual(workout.durationMinutes, 7.5, accuracy: 0.001)
        XCTAssertEqual(workout.caloriesBurned, 50, accuracy: 0.01)
        XCTAssertTrue(workout.needsSync)
    }

    func testDurationEntryUsesEnteredMinutes() throws {
        var entry = DraftEntry(template: running)
        entry.durationMinutes = 30
        // 9,8 × 80 × 0,5 = 392
        let workout = try sut.save(draft(with: [entry]))
        XCTAssertEqual(workout.durationMinutes, 30, accuracy: 0.001)
        XCTAssertEqual(workout.caloriesBurned, 392, accuracy: 0.01)
    }

    func testSaveRejectsEmptyDraft() {
        XCTAssertThrowsError(try sut.save(WorkoutDraft()))
    }

    func testSaveRejectsSetWithZeroReps() {
        var entry = benchEntry(sets: 1)
        entry.sets[0].reps = 0
        XCTAssertThrowsError(try sut.save(draft(with: [entry])))
    }

    func testEmptyTitleIsGeneratedFromExercises() throws {
        let workout = try sut.save(draft(with: [benchEntry(), DraftEntry(template: running)]))
        XCTAssertEqual(workout.title, "Bench Press +1")
    }

    // MARK: - Düzenleme / silme / tekrarlama
    func testEditReplacesEntriesWithoutLeavingOrphans() throws {
        let workout = try sut.save(draft(with: [benchEntry(), DraftEntry(template: running)]))
        XCTAssertEqual(workout.entries.count, 2)

        try sut.save(draft(with: [benchEntry(sets: 2)]), editing: workout)

        XCTAssertEqual(workout.entries.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEntry>()).count, 1)
        XCTAssertEqual(try workoutCount(), 1)
    }

    func testDeleteRemovesWorkoutAndNotifiesServer() async throws {
        let workout = try sut.save(draft(with: [benchEntry()]))
        let id = workout.id.uuidString

        sut.delete(workout)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(try workoutCount(), 0)
        XCTAssertEqual(sync.deleted, [id])
        XCTAssertTrue(PendingDeletionStore(userID: "uid-1").ids.isEmpty)
    }

    func testDuplicateCreatesSecondWorkout() throws {
        let workout = try sut.save(draft(with: [benchEntry()]))
        sut.duplicate(workout)
        XCTAssertEqual(try workoutCount(), 2)
    }

    // MARK: - Özel egzersiz
    func testCustomExerciseRejectsPresetName() {
        XCTAssertThrowsError(
            try sut.createCustomExercise(name: "bench press", category: .strength, mode: .sets, intensity: .moderate)
        )
    }

    func testCustomExerciseIsCreated() throws {
        let template = try sut.createCustomExercise(
            name: "Kettlebell Swing", category: .hiit, mode: .duration, intensity: .vigorous
        )
        XCTAssertTrue(template.isCustom)
        XCTAssertEqual(template.met, 8.0)
    }

    // MARK: - Senkronizasyon
    func testUploadClearsNeedsSyncFlag() async throws {
        let workout = try sut.save(draft(with: [benchEntry()]))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(workout.needsSync)
        XCTAssertEqual(sync.uploaded.count, 1)
    }

    func testSyncAllInsertsRemoteWorkouts() async throws {
        let dto = WorkoutDTO(
            id: UUID().uuidString, title: "Uzak Antrenman", date: .now, notes: "",
            durationMinutes: 30, caloriesBurned: 200,
            entries: [.init(id: UUID().uuidString, order: 0, exerciseKey: "preset.running", name: "Koşu",
                            category: "cardio", mode: "duration", met: 9.8, durationMinutes: 30, sets: [])],
            createdAt: .now, updatedAt: .now
        )
        sync.remote = [dto]

        await sut.syncAll()

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts.first?.title, "Uzak Antrenman")
        XCTAssertEqual(workouts.first?.entries.count, 1)
        XCTAssertEqual(workouts.first?.needsSync, false)
    }

    func testSyncAllKeepsLocalChangesThatAreStillPending() async throws {
        let workout = try sut.save(draft(with: [benchEntry()]))
        workout.needsSync = true   // henüz yüklenmemiş yerel değişiklik

        var remote = workout.dto
        remote.title = "Uzaktan Gelen Başlık"
        remote.updatedAt = workout.updatedAt.addingTimeInterval(60)
        sync.remote = [remote]

        await sut.syncAll()

        XCTAssertNotEqual(workout.title, "Uzaktan Gelen Başlık")
    }
}
