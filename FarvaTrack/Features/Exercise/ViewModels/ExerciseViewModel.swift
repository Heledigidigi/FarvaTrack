import Foundation
import Observation
import SwiftData

// MARK: - Taslak modeller (form düzenlenirken kullanılır, kaydedilene kadar veritabanına dokunmaz)
struct DraftEntry: Identifiable, Equatable {
    var id = UUID()
    var template: ExerciseTemplate
    var durationMinutes: Double
    var sets: [WorkoutSet]

    init(template: ExerciseTemplate) {
        self.template = template
        self.durationMinutes = 20
        self.sets = template.mode == .sets ? [WorkoutSet(reps: 10, weightKg: 0)] : []
    }

    init(entry: WorkoutEntry) {
        self.template = ExerciseTemplate(
            key: entry.exerciseKey,
            name: entry.name,
            category: entry.category,
            mode: entry.mode,
            met: entry.met
        )
        self.durationMinutes = entry.durationMinutes
        self.sets = entry.sets.map { WorkoutSet(reps: $0.reps, weightKg: $0.weightKg) }
    }

    var estimatedMinutes: Double {
        template.mode == .duration
            ? durationMinutes
            : Double(sets.count) * Constants.Training.minutesPerSet
    }

    var isValid: Bool {
        switch template.mode {
        case .duration: return durationMinutes > 0
        case .sets: return !sets.isEmpty && sets.allSatisfy { $0.reps > 0 && $0.weightKg >= 0 }
        }
    }
}

struct WorkoutDraft: Equatable {
    var title = ""
    var date = Date.now
    var notes = ""
    var entries: [DraftEntry] = []

    init() {}

    init(workout: Workout) {
        title = workout.title
        date = workout.date
        notes = workout.notes
        entries = workout.sortedEntries.map(DraftEntry.init(entry:))
    }

    var isValid: Bool {
        !entries.isEmpty && entries.allSatisfy(\.isValid)
    }

    /// Başlık boşsa ilk egzersizin adından üretilir.
    var resolvedTitle: String {
        let trimmedTitle = title.trimmed
        if !trimmedTitle.isEmpty { return trimmedTitle }
        guard let first = entries.first else { return "Antrenman" }
        return entries.count == 1 ? first.template.name : "\(first.template.name) +\(entries.count - 1)"
    }

    var estimatedMinutes: Double {
        entries.reduce(0) { $0 + $1.estimatedMinutes }
    }

    func estimatedCalories(weightKg: Double) -> Double {
        entries.reduce(0) {
            $0 + CalorieCalculator.exerciseCalories(met: $1.template.met, weightKg: weightKg, minutes: $1.estimatedMinutes)
        }
    }
}

// MARK: - ViewModel
@MainActor
@Observable
final class ExerciseViewModel {
    var errorMessage: String?
    private(set) var weightKg = Constants.Training.fallbackWeightKg
    private(set) var isSyncing = false

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var deletions: PendingDeletionStore?
    @ObservationIgnored private let sync: WorkoutSyncing

    init(sync: WorkoutSyncing = FirestoreWorkoutSyncService()) {
        self.sync = sync
    }

    var currentUserID: String? { userID }

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func configure(context: ModelContext, user: AppUser) {
        self.context = context
        if userID != user.id {
            userID = user.id
            deletions = PendingDeletionStore(userID: user.id, scope: "Workout")
        }
        weightKg = user.weightKg ?? Constants.Training.fallbackWeightKg
    }

    // MARK: - Antrenman CRUD
    /// Yeni antrenman oluşturur veya `existing` verilmişse günceller.
    @discardableResult
    func save(_ draft: WorkoutDraft, editing existing: Workout? = nil) throws -> Workout {
        guard let context, let userID else { throw AppError.notAuthenticated }
        guard draft.isValid else {
            throw AppError.invalidInput("En az bir egzersiz ekle ve set/süre değerlerini kontrol et.")
        }

        let workout: Workout
        if let existing {
            workout = existing
            for entry in existing.entries { context.delete(entry) }
            existing.entries = []
        } else {
            workout = Workout(ownerID: userID, title: "", date: draft.date)
            context.insert(workout)
        }

        workout.title = draft.resolvedTitle
        workout.date = draft.date
        workout.notes = draft.notes.trimmed

        for (index, item) in draft.entries.enumerated() {
            let entry = WorkoutEntry(
                order: index,
                template: item.template,
                durationMinutes: item.durationMinutes,
                sets: item.sets
            )
            context.insert(entry)
            workout.entries.append(entry)
        }

        workout.recalculate(weightKg: weightKg)
        workout.updatedAt = .now
        workout.needsSync = true

        do {
            try context.save()
        } catch {
            throw AppError.unknown(error.localizedDescription)
        }

        Haptics.success()
        scheduleUpload(workout)
        return workout
    }

    func delete(_ workout: Workout) {
        guard let context, let userID else { return }
        let id = workout.id.uuidString

        context.delete(workout)
        do {
            try context.save()
        } catch {
            present(error)
            return
        }

        Haptics.impact(.medium)
        deletions?.add(id)
        scheduleDelete(id: id, userID: userID)
    }

    func duplicate(_ workout: Workout) {
        var draft = WorkoutDraft(workout: workout)
        draft.date = .now
        do {
            try save(draft)
        } catch {
            present(error)
        }
    }

    // MARK: - Özel egzersizler
    @discardableResult
    func createCustomExercise(
        name: String,
        category: ExerciseCategory,
        mode: TrackingMode,
        intensity: ExerciseIntensity
    ) throws -> ExerciseTemplate {
        guard let context, let userID else { throw AppError.notAuthenticated }

        let cleanName = name.trimmed
        guard (2...40).contains(cleanName.count) else {
            throw AppError.invalidInput("Egzersiz adı 2–40 karakter olmalı.")
        }

        let existing = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.ownerID == userID })
        )) ?? []
        let takenNames = ExerciseLibrary.presets.map(\.name) + existing.map(\.name)
        guard !takenNames.contains(where: { $0.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            throw AppError.invalidInput("Bu isimde bir egzersiz zaten var.")
        }

        let exercise = Exercise(ownerID: userID, name: cleanName, category: category, mode: mode, met: intensity.met)
        context.insert(exercise)
        do {
            try context.save()
        } catch {
            throw AppError.unknown(error.localizedDescription)
        }
        Haptics.success()
        return exercise.template
    }

    func deleteCustomExercise(_ exercise: Exercise) {
        guard let context else { return }
        context.delete(exercise)
        do {
            try context.save()
        } catch {
            present(error)
        }
    }

    // MARK: - Senkronizasyon
    /// Uzaktaki antrenmanları yerelle birleştirir, bekleyen yükleme ve silmeleri yeniden dener.
    func syncAll() async {
        guard let context, let userID, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let pendingDeletes = deletions?.ids ?? []
        for id in pendingDeletes { scheduleDelete(id: id, userID: userID) }

        do {
            let remote = try await sync.fetchWorkouts(userID: userID)
            let local = try context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.ownerID == userID }))
            let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            for dto in remote where !pendingDeletes.contains(dto.id) {
                guard let uuid = UUID(uuidString: dto.id) else { continue }
                if let existing = localByID[uuid] {
                    // Bekleyen yerel değişiklik varsa yerel kazanır; yoksa daha yeni olan kazanır.
                    if !existing.needsSync, dto.updatedAt > existing.updatedAt {
                        existing.replaceContent(with: dto, context: context)
                    }
                } else {
                    let workout = Workout(id: uuid, ownerID: userID, title: dto.title, date: dto.date)
                    context.insert(workout)
                    workout.replaceContent(with: dto, context: context)
                }
            }

            try context.save()
            for workout in local where workout.needsSync { scheduleUpload(workout) }
        } catch {
            // Çevrimdışı olabilir; bir sonraki açılışta tekrar denenir.
        }
    }

    // MARK: - Arka plan işleri
    private func scheduleUpload(_ workout: Workout) {
        guard let userID else { return }
        let dto = workout.dto
        let id = workout.id
        let updatedAt = workout.updatedAt

        Task {
            do {
                try await sync.upload(dto, userID: userID)
                markSynced(id: id, updatedAt: updatedAt)
            } catch {
                // needsSync true kalır; sonraki syncAll'da yeniden denenir.
            }
        }
    }

    private func markSynced(id: UUID, updatedAt: Date) {
        guard let context else { return }
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        // Bu arada başka bir düzenleme olduysa (updatedAt değiştiyse) bayrağı kaldırma.
        if let workout = try? context.fetch(descriptor).first, workout.updatedAt == updatedAt {
            workout.needsSync = false
            try? context.save()
        }
    }

    private func scheduleDelete(id: String, userID: String) {
        let store = deletions
        Task {
            do {
                try await sync.deleteWorkout(id: id, userID: userID)
                store?.remove(id)
            } catch {
                // Kayıt "bekleyen silme" olarak kalır.
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = AppError.map(error).errorDescription
        Haptics.error()
    }
}
