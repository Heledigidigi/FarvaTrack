import Foundation

/// Uygulamayla gelen klasik programlar. Kullanıcı "Bu programı kullan" deyince
/// şablonları ve programı kendi hesabına kopyalanır; sonra istediği gibi düzenler.
struct PresetProgram: Identifiable {
    struct Day {
        let name: String
        let exercises: [TemplateExercise]
    }

    let id: String
    let name: String
    let summary: String
    let level: String
    let kind: ProgramKind
    let days: [Day]
    /// Haftalık programlarda her günün hangi şablona denk geldiği (0 = Pazartesi, `nil` dinlenme).
    let weeklyLayout: [Int?]
}

enum PresetPrograms {
    /// Kütüphanedeki egzersizden hedefli şablon egzersizi üretir.
    private static func ex(_ slug: String, _ sets: Int, _ reps: Int, rest: Int = 90) -> TemplateExercise {
        let template = ExerciseLibrary.template(forKey: "preset.\(slug)")
            ?? ExerciseTemplate(key: "preset.\(slug)", name: slug, category: .strength, mode: .sets, met: 5)
        return TemplateExercise(template: template, sets: sets, reps: reps, restSeconds: rest)
    }

    private static func timed(_ slug: String, minutes: Double) -> TemplateExercise {
        let template = ExerciseLibrary.template(forKey: "preset.\(slug)")
            ?? ExerciseTemplate(key: "preset.\(slug)", name: slug, category: .strength, mode: .duration, met: 3.5)
        return TemplateExercise(template: template, durationMinutes: minutes, restSeconds: 60)
    }

    static let all: [PresetProgram] = [
        PresetProgram(
            id: "full-body-3",
            name: "Tam Vücut • 3 Gün",
            summary: "Haftada 3 gün, her antrenmanda tüm vücut. Yeni başlayanlar için.",
            level: "Başlangıç",
            kind: .weekly,
            days: [
                .init(name: "Tam Vücut A", exercises: [
                    ex("squat", 3, 8, rest: 120), ex("bench-press", 3, 8, rest: 120),
                    ex("barbell-row", 3, 10), ex("lateral-raise", 2, 12, rest: 60), timed("plank", minutes: 3)
                ]),
                .init(name: "Tam Vücut B", exercises: [
                    ex("deadlift", 3, 5, rest: 180), ex("overhead-press", 3, 8, rest: 120),
                    ex("lat-pulldown", 3, 10), ex("lunge", 3, 10), ex("crunch", 3, 15, rest: 45)
                ])
            ],
            weeklyLayout: [0, nil, 1, nil, 0, nil, nil]
        ),
        PresetProgram(
            id: "upper-lower-4",
            name: "Üst / Alt • 4 Gün",
            summary: "Üst ve alt vücut dönüşümlü, haftada 4 gün. Orta seviye.",
            level: "Orta",
            kind: .weekly,
            days: [
                .init(name: "Üst Vücut A", exercises: [
                    ex("bench-press", 4, 6, rest: 150), ex("barbell-row", 4, 8, rest: 120),
                    ex("overhead-press", 3, 8), ex("lat-pulldown", 3, 10), ex("biceps-curl", 2, 12, rest: 60)
                ]),
                .init(name: "Alt Vücut A", exercises: [
                    ex("squat", 4, 6, rest: 180), ex("romanian-deadlift", 3, 8, rest: 120),
                    ex("leg-press", 3, 12), ex("calf-raise", 3, 15, rest: 60)
                ]),
                .init(name: "Üst Vücut B", exercises: [
                    ex("incline-dumbbell-press", 4, 10), ex("pull-up", 4, 8, rest: 120),
                    ex("lateral-raise", 3, 12, rest: 60), ex("cable-row", 3, 12), ex("triceps-pushdown", 2, 12, rest: 60)
                ]),
                .init(name: "Alt Vücut B", exercises: [
                    ex("deadlift", 3, 5, rest: 180), ex("lunge", 3, 10),
                    ex("leg-curl", 3, 12), ex("calf-raise", 3, 15, rest: 60), timed("plank", minutes: 3)
                ])
            ],
            weeklyLayout: [0, 1, nil, 2, 3, nil, nil]
        ),
        PresetProgram(
            id: "push-pull-legs",
            name: "İtiş / Çekiş / Bacak",
            summary: "Üç antrenman sırayla döner; haftada 3–6 gün, hangi gün gidersen sıradaki.",
            level: "Orta–İleri",
            kind: .rotation,
            days: [
                .init(name: "İtiş", exercises: [
                    ex("bench-press", 4, 8, rest: 150), ex("overhead-press", 3, 8, rest: 120),
                    ex("incline-dumbbell-press", 3, 10), ex("lateral-raise", 3, 15, rest: 60),
                    ex("triceps-pushdown", 3, 12, rest: 60)
                ]),
                .init(name: "Çekiş", exercises: [
                    ex("deadlift", 3, 5, rest: 180), ex("pull-up", 3, 8, rest: 120),
                    ex("barbell-row", 3, 10), ex("cable-row", 3, 12), ex("biceps-curl", 3, 12, rest: 60)
                ]),
                .init(name: "Bacak", exercises: [
                    ex("squat", 4, 8, rest: 180), ex("romanian-deadlift", 3, 10, rest: 120),
                    ex("leg-press", 3, 12), ex("leg-curl", 3, 12), ex("calf-raise", 4, 15, rest: 60)
                ])
            ],
            weeklyLayout: []
        )
    ]
}
