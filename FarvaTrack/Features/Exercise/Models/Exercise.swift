import SwiftUI
import SwiftData

// MARK: - Enum'lar
enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case strength, cardio, hiit, flexibility, sports, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: return "Kuvvet"
        case .cardio: return "Kardiyo"
        case .hiit: return "HIIT"
        case .flexibility: return "Esneklik"
        case .sports: return "Spor"
        case .other: return "Diğer"
        }
    }

    var systemImage: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .hiit: return "bolt.heart.fill"
        case .flexibility: return "figure.yoga"
        case .sports: return "sportscourt.fill"
        case .other: return "figure.mixed.cardio"
        }
    }

    var tint: Color {
        switch self {
        case .strength: return Color.ftExercise
        case .cardio: return Color.ftCalories
        case .hiit: return Color(hex: "#FF5D8F")
        case .flexibility: return Color.ftSleep
        case .sports: return Color.ftWater
        case .other: return Color.ftTextSecondary
        }
    }
}

enum TrackingMode: String, Codable, CaseIterable, Identifiable {
    case sets, duration
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sets: return "Set × Tekrar"
        case .duration: return "Süre"
        }
    }
}

/// Özel egzersizlerde kalori tahmini için yoğunluk (MET karşılığı).
enum ExerciseIntensity: String, CaseIterable, Identifiable {
    case light, moderate, vigorous
    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Hafif"
        case .moderate: return "Orta"
        case .vigorous: return "Yüksek"
        }
    }

    var met: Double {
        switch self {
        case .light: return 3.0
        case .moderate: return 5.0
        case .vigorous: return 8.0
        }
    }
}

// MARK: - Şablon (hazır + özel egzersizlerin ortak temsili)
struct ExerciseTemplate: Identifiable, Hashable {
    /// Hazır: "preset.bench-press", özel: "custom.<uuid>"
    let key: String
    let name: String
    let category: ExerciseCategory
    let mode: TrackingMode
    let met: Double

    var id: String { key }
    var isCustom: Bool { key.hasPrefix("custom.") }
}

// MARK: - Hazır kütüphane (MET değerleri yaklaşık, Compendium of Physical Activities baz alınmıştır)
enum ExerciseLibrary {
    static func template(forKey key: String) -> ExerciseTemplate? {
        presets.first { $0.key == key }
    }

    private static func make(
        _ slug: String, _ name: String, _ category: ExerciseCategory, _ mode: TrackingMode, _ met: Double
    ) -> ExerciseTemplate {
        ExerciseTemplate(key: "preset.\(slug)", name: name, category: category, mode: mode, met: met)
    }

    static let presets: [ExerciseTemplate] = [
        // Kuvvet
        make("bench-press", "Bench Press", .strength, .sets, 5.0),
        make("incline-dumbbell-press", "Eğimli Dumbbell Press", .strength, .sets, 5.0),
        make("squat", "Squat", .strength, .sets, 5.5),
        make("deadlift", "Deadlift", .strength, .sets, 6.0),
        make("overhead-press", "Omuz Press", .strength, .sets, 5.0),
        make("barbell-row", "Barbell Row", .strength, .sets, 5.0),
        make("lat-pulldown", "Lat Pulldown", .strength, .sets, 4.5),
        make("pull-up", "Barfiks", .strength, .sets, 5.5),
        make("push-up", "Şınav", .strength, .sets, 4.0),
        make("biceps-curl", "Biceps Curl", .strength, .sets, 3.5),
        make("triceps-pushdown", "Triceps Pushdown", .strength, .sets, 3.5),
        make("leg-press", "Leg Press", .strength, .sets, 5.0),
        make("lunge", "Lunge", .strength, .sets, 4.5),
        make("crunch", "Mekik", .strength, .sets, 3.8),
        make("plank", "Plank", .strength, .duration, 3.5),
        // Kardiyo
        make("running", "Koşu", .cardio, .duration, 9.8),
        make("walking", "Yürüyüş", .cardio, .duration, 3.5),
        make("cycling", "Bisiklet", .cardio, .duration, 7.5),
        make("swimming", "Yüzme", .cardio, .duration, 8.0),
        make("rowing", "Kürek Makinesi", .cardio, .duration, 7.0),
        make("elliptical", "Eliptik", .cardio, .duration, 5.0),
        make("jump-rope", "İp Atlama", .cardio, .duration, 11.0),
        make("stair-climbing", "Merdiven Çıkma", .cardio, .duration, 8.0),
        // HIIT
        make("hiit-circuit", "HIIT Devre", .hiit, .duration, 8.0),
        make("tabata", "Tabata", .hiit, .duration, 8.0),
        make("burpee", "Burpee", .hiit, .duration, 8.0),
        // Esneklik
        make("yoga", "Yoga", .flexibility, .duration, 2.5),
        make("stretching", "Esneme", .flexibility, .duration, 2.3),
        make("pilates", "Pilates", .flexibility, .duration, 3.0),
        // Spor
        make("football", "Futbol", .sports, .duration, 7.0),
        make("basketball", "Basketbol", .sports, .duration, 6.5),
        make("tennis", "Tenis", .sports, .duration, 7.3),
        make("volleyball", "Voleybol", .sports, .duration, 4.0)
    ]
}

// MARK: - SwiftData: kullanıcının özel egzersizi
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var name: String
    var categoryRaw: String
    var modeRaw: String
    var met: Double
    var createdAt: Date

    init(ownerID: String, name: String, category: ExerciseCategory, mode: TrackingMode, met: Double) {
        self.id = UUID()
        self.ownerID = ownerID
        self.name = name
        self.categoryRaw = category.rawValue
        self.modeRaw = mode.rawValue
        self.met = met
        self.createdAt = .now
    }

    var template: ExerciseTemplate {
        ExerciseTemplate(
            key: "custom.\(id.uuidString)",
            name: name,
            category: ExerciseCategory(rawValue: categoryRaw) ?? .other,
            mode: TrackingMode(rawValue: modeRaw) ?? .duration,
            met: met
        )
    }
}