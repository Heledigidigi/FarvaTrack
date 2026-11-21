import Foundation
import Observation
import SwiftData

/// Salonda canlı mod: setleri işaretleme, dinlenme sayacı, yarım kalan oturumu koruma.
@MainActor
@Observable
final class LiveWorkoutViewModel {
    private(set) var session: LiveSession? {
        didSet { persist() }
    }
    var errorMessage: String?

    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private let store: LiveSessionStoring
    @ObservationIgnored private let restScheduler: RestTimerScheduling
    @ObservationIgnored private let now: () -> Date

    static let restAdjustment = 15
    static let maxSetsPerExercise = 12

    init(
        store: LiveSessionStoring = UserDefaultsLiveSessionStore(),
        restScheduler: RestTimerScheduling = NotificationManager.shared,
        now: @escaping () -> Date = { .now }
    ) {
        self.store = store
        self.restScheduler = restScheduler
        self.now = now
    }

    var isActive: Bool { session != nil }

    /// Kullanıcı değişince (veya uygulama açılınca) yarım kalan oturumu geri yükler.
    func configure(userID: String) {
        guard self.userID != userID else { return }
        self.userID = userID
        restTask?.cancel()
        session = store.load(userID: userID)
        if let end = session?.restEndsAt {
            if end > now() { scheduleRestHaptic(until: end) } else { session?.restEndsAt = nil }
        }
    }

    // MARK: - Başlat / bitir
    func start(template: WorkoutTemplate, programID: String?, workouts: [Workout]) {
        guard session == nil else {
            errorMessage = "Devam eden bir antrenman var. Önce onu bitir veya iptal et."
            return
        }
        session = LiveSession.make(from: template, programID: programID, previous: { key in
            ProgramPlanner.lastPerformance(of: key, in: workouts)
        }, now: now())
        Haptics.impact(.medium)
    }

    /// Kaydedilecek taslağı döner. Hiç işaretlenmiş set yoksa (ve plandaki gibi değilse) hata verir.
    func finishDraft(asPlanned: Bool) throws -> WorkoutDraft {
        guard let session else { throw AppError.invalidInput("Devam eden antrenman yok.") }
        let draft = session.draft(asPlanned: asPlanned)
        guard draft.isValid else {
            throw AppError.invalidInput("Henüz hiçbir seti tamamlamadın. Setleri işaretle ya da \"Plandaki gibi tamamladım\"ı seç.")
        }
        return draft
    }

    /// Antrenman kaydedildikten sonra oturumu kapatır.
    func end() {
        restTask?.cancel()
        Task { await restScheduler.cancelRestEnd() }
        session = nil
    }

    func discard() {
        end()
        Haptics.impact(.light)
    }

    // MARK: - Setler
    func toggleSet(exerciseID: UUID, setID: UUID) {
        guard var current = session,
              let e = current.exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = current.exercises[e].sets.firstIndex(where: { $0.id == setID }) else { return }
        current.exercises[e].sets[s].isDone.toggle()
        let isDone = current.exercises[e].sets[s].isDone
        session = current
        Haptics.selection()

        if isDone {
            let isLastStep = current.progress.done == current.progress.total
            if !isLastStep { startRest(seconds: current.exercises[e].exercise.restSeconds, after: e) }
            else { skipRest(); Haptics.success() }
        }
    }

    func updateSet(exerciseID: UUID, setID: UUID, reps: Int? = nil, weightKg: Double? = nil) {
        guard var current = session,
              let e = current.exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = current.exercises[e].sets.firstIndex(where: { $0.id == setID }) else { return }
        if let reps { current.exercises[e].sets[s].reps = min(max(reps, 1), TemplateExercise.repRange.upperBound) }
        if let weightKg { current.exercises[e].sets[s].weightKg = min(max(weightKg, 0), 1_000) }
        session = current
    }

    /// Son setin kopyasını ekler.
    func addSet(exerciseID: UUID) {
        guard var current = session, let e = current.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        guard current.exercises[e].sets.count < Self.maxSetsPerExercise else { return }
        let last = current.exercises[e].sets.last
        current.exercises[e].sets.append(LiveSet(
            reps: last?.reps ?? current.exercises[e].exercise.targetReps,
            weightKg: last?.weightKg ?? current.exercises[e].exercise.targetWeightKg ?? 0
        ))
        session = current
        Haptics.selection()
    }

    func removeSet(exerciseID: UUID, setID: UUID) {
        guard var current = session, let e = current.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        guard current.exercises[e].sets.count > 1 else { return }
        current.exercises[e].sets.removeAll { $0.id == setID }
        session = current
    }

    func toggleDuration(exerciseID: UUID) {
        guard var current = session, let e = current.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        current.exercises[e].isDurationDone.toggle()
        session = current
        Haptics.selection()
        if current.exercises[e].isDurationDone, current.progress.done == current.progress.total {
            Haptics.success()
        }
    }

    func updateDuration(exerciseID: UUID, minutes: Double) {
        guard var current = session, let e = current.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        current.exercises[e].durationMinutes = min(max(minutes, 1), 300)
        session = current
    }

    // MARK: - Dinlenme
    var restRemaining: TimeInterval {
        guard let end = session?.restEndsAt else { return 0 }
        return max(end.timeIntervalSince(now()), 0)
    }

    func startRest(seconds: Int, after exerciseIndex: Int? = nil) {
        guard var current = session, seconds > 0 else { return }
        let end = now().addingTimeInterval(TimeInterval(seconds))
        current.restEndsAt = end
        current.restTotalSeconds = seconds
        session = current

        let nextName = nextExerciseName(from: exerciseIndex) ?? "Antrenman"
        Task { await restScheduler.scheduleRestEnd(after: TimeInterval(seconds), exerciseName: nextName) }
        scheduleRestHaptic(until: end)
    }

    func adjustRest(by seconds: Int) {
        guard var current = session, let end = current.restEndsAt else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(seconds))
        guard newEnd > now() else {
            skipRest()
            return
        }
        current.restEndsAt = newEnd
        current.restTotalSeconds = max(current.restTotalSeconds + seconds, 1)
        session = current
        let remaining = newEnd.timeIntervalSince(now())
        Task { await restScheduler.scheduleRestEnd(after: remaining, exerciseName: "Sıradaki set") }
        scheduleRestHaptic(until: newEnd)
    }

    func skipRest() {
        restTask?.cancel()
        guard session?.restEndsAt != nil else { return }
        session?.restEndsAt = nil
        Task { await restScheduler.cancelRestEnd() }
    }

    private func scheduleRestHaptic(until end: Date) {
        restTask?.cancel()
        let delay = max(end.timeIntervalSince(now()), 0)
        restTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.session?.restEndsAt == end else { return }
            self.session?.restEndsAt = nil
            Haptics.success()
        }
    }

    /// Henüz bitmemiş ilk egzersizin adı (bildirim metni için).
    private func nextExerciseName(from index: Int?) -> String? {
        guard let exercises = session?.exercises else { return nil }
        let start = index ?? 0
        let ordered = Array(exercises[start...]) + Array(exercises[..<start])
        return ordered.first { !$0.isComplete }?.exercise.name
    }

    private func persist() {
        guard let userID else { return }
        if let session {
            store.save(session, userID: userID)
        } else {
            store.clear(userID: userID)
        }
    }
}
