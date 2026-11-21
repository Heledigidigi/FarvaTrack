import Foundation

// MARK: - Canlı antrenman oturumu
/// Salonda set set ilerlerken tutulan durum. Her değişiklikte kaydedilir; uygulama kapansa da kaybolmaz.
struct LiveSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var reps: Int
    var weightKg: Double
    var isDone = false
}

struct LiveExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var exercise: TemplateExercise
    var sets: [LiveSet]
    var durationMinutes: Double
    var isDurationDone = false
    /// Bu egzersizin en son yapıldığı antrenmandaki setler ("geçen sefer").
    var previous: [WorkoutSet]?

    var isComplete: Bool {
        exercise.mode == .duration ? isDurationDone : (!sets.isEmpty && sets.allSatisfy(\.isDone))
    }

    func previousText(at index: Int) -> String? {
        guard let previous, index < previous.count else { return nil }
        let set = previous[index]
        let weight = set.weightKg > 0 ? "\(set.weightKg.formatted(.number.precision(.fractionLength(0...1)))) kg × " : ""
        return "\(weight)\(set.reps)"
    }
}

struct LiveSession: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var templateID: String?
    var programID: String?
    var startedAt: Date
    var exercises: [LiveExercise]
    /// Dinlenme sayacının bittiği an; `nil` ise sayaç yok.
    var restEndsAt: Date?
    var restTotalSeconds: Int = 0

    /// Tamamlanan / toplam adım (set modunda her set, süre modunda egzersizin kendisi).
    var progress: (done: Int, total: Int) {
        exercises.reduce((0, 0)) { result, item in
            if item.exercise.mode == .duration {
                return (result.0 + (item.isDurationDone ? 1 : 0), result.1 + 1)
            }
            return (result.0 + item.sets.filter(\.isDone).count, result.1 + item.sets.count)
        }
    }

    /// Şablondan oturum kurar. Ağırlıklar geçen seferden, yoksa şablon hedefinden doldurulur.
    static func make(
        from template: WorkoutTemplate,
        programID: String?,
        previous: (String) -> [WorkoutSet]?,
        now: Date = .now
    ) -> LiveSession {
        let exercises = template.exercises.map { item -> LiveExercise in
            let last = previous(item.exerciseKey)
            let sets: [LiveSet]
            if item.mode == .sets {
                sets = (0..<max(item.targetSets, 1)).map { index in
                    let fromLast = last.flatMap { index < $0.count ? $0[index] : $0.last }
                    let weight = fromLast?.weightKg ?? item.targetWeightKg ?? 0
                    return LiveSet(reps: item.targetReps, weightKg: weight)
                }
            } else {
                sets = []
            }
            return LiveExercise(exercise: item, sets: sets, durationMinutes: item.durationMinutes, previous: last)
        }
        return LiveSession(
            title: template.name,
            templateID: template.id.uuidString,
            programID: programID,
            startedAt: now,
            exercises: exercises
        )
    }

    /// Kaydedilecek antrenman taslağı. `asPlanned` true ise işaretlenmemiş setler de plandaki gibi yapılmış sayılır.
    func draft(asPlanned: Bool) -> WorkoutDraft {
        var draft = WorkoutDraft()
        draft.title = title
        draft.date = startedAt
        draft.templateID = templateID
        draft.programID = programID
        draft.entries = exercises.compactMap { item in
            var entry = DraftEntry(template: item.exercise.exerciseTemplate)
            switch item.exercise.mode {
            case .duration:
                guard asPlanned || item.isDurationDone else { return nil }
                entry.durationMinutes = item.durationMinutes
            case .sets:
                let chosen = item.sets.filter { asPlanned || $0.isDone }
                guard !chosen.isEmpty else { return nil }
                entry.sets = chosen.map { WorkoutSet(reps: $0.reps, weightKg: $0.weightKg) }
            }
            return entry
        }
        return draft
    }
}

// MARK: - Kalıcılık
protocol LiveSessionStoring {
    func load(userID: String) -> LiveSession?
    func save(_ session: LiveSession, userID: String)
    func clear(userID: String)
}

struct UserDefaultsLiveSessionStore: LiveSessionStoring {
    var defaults: UserDefaults = .standard

    private func key(_ userID: String) -> String { "liveWorkout.\(userID)" }

    func load(userID: String) -> LiveSession? {
        guard let data = defaults.data(forKey: key(userID)) else { return nil }
        return try? JSONDecoder().decode(LiveSession.self, from: data)
    }

    func save(_ session: LiveSession, userID: String) {
        defaults.set(try? JSONEncoder().encode(session), forKey: key(userID))
    }

    func clear(userID: String) {
        defaults.removeObject(forKey: key(userID))
    }
}
