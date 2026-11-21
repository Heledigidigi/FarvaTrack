import Foundation
import SwiftData

// MARK: - Set
struct WorkoutSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var reps: Int
    var weightKg: Double
}

// MARK: - Antrenmandaki egzersiz
@Model
final class WorkoutEntry {
    @Attribute(.unique) var id: UUID
    var order: Int
    var exerciseKey: String
    var name: String
    var categoryRaw: String
    var modeRaw: String
    var met: Double
    var durationMinutes: Double
    var sets: [WorkoutSet]
    var workout: Workout?

    init(order: Int, template: ExerciseTemplate, durationMinutes: Double, sets: [WorkoutSet]) {
        self.id = UUID()
        self.order = order
        self.exerciseKey = template.key
        self.name = template.name
        self.categoryRaw = template.category.rawValue
        self.modeRaw = template.mode.rawValue
        self.met = template.met
        self.durationMinutes = durationMinutes
        self.sets = sets
    }

    init(dto: WorkoutDTO.EntryDTO) {
        self.id = UUID(uuidString: dto.id) ?? UUID()
        self.order = dto.order
        self.exerciseKey = dto.exerciseKey
        self.name = dto.name
        self.categoryRaw = dto.category
        self.modeRaw = dto.mode
        self.met = dto.met
        self.durationMinutes = dto.durationMinutes
        self.sets = dto.sets
    }

    var category: ExerciseCategory { ExerciseCategory(rawValue: categoryRaw) ?? .other }
    var mode: TrackingMode { TrackingMode(rawValue: modeRaw) ?? .duration }

    /// Süre modunda girilen süre; set modunda set sayısına göre tahmin.
    var estimatedMinutes: Double {
        mode == .duration ? durationMinutes : Double(sets.count) * Constants.Training.minutesPerSet
    }

    var totalVolumeKg: Double {
        sets.reduce(0) { $0 + Double($1.reps) * $1.weightKg }
    }

    var summaryText: String {
        switch mode {
        case .duration:
            return "\(Int(durationMinutes)) dk"
        case .sets:
            let reps = sets.reduce(0) { $0 + $1.reps }
            return "\(sets.count) set • \(reps) tekrar"
        }
    }
}

// MARK: - Antrenman
@Model
final class Workout {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var title: String
    var date: Date
    var notes: String
    var durationMinutes: Double
    var caloriesBurned: Double
    /// true ise Firestore'a henüz yüklenmemiş bir değişiklik var.
    var needsSync: Bool
    var createdAt: Date
    var updatedAt: Date
    /// Şablondan başlatıldıysa şablonun kimliği (program takibi ve "geçen sefer" için).
    var templateID: String?
    var programID: String?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutEntry.workout)
    var entries: [WorkoutEntry] = []

    init(id: UUID = UUID(), ownerID: String, title: String, date: Date, notes: String = "") {
        self.id = id
        self.ownerID = ownerID
        self.title = title
        self.date = date
        self.notes = notes
        self.durationMinutes = 0
        self.caloriesBurned = 0
        self.needsSync = true
        self.createdAt = .now
        self.updatedAt = .now
    }
}

extension Workout {
    /// İlişki dizisinin sırası garanti olmadığı için `order`'a göre sıralanır.
    var sortedEntries: [WorkoutEntry] {
        entries.sorted { $0.order < $1.order }
    }

    var categories: [ExerciseCategory] {
        var seen = Set<ExerciseCategory>()
        return sortedEntries.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    var totalVolumeKg: Double {
        entries.reduce(0) { $0 + $1.totalVolumeKg }
    }

    /// Süre ve kaloriyi egzersizlerden yeniden hesaplar.
    func recalculate(weightKg: Double) {
        durationMinutes = entries.reduce(0) { $0 + $1.estimatedMinutes }
        caloriesBurned = entries.reduce(0) {
            $0 + CalorieCalculator.exerciseCalories(met: $1.met, weightKg: weightKg, minutes: $1.estimatedMinutes)
        }
    }
}

// MARK: - Özet istatistik
struct WorkoutStats: Equatable {
    var count = 0
    var minutes = 0.0
    var calories = 0.0

    init(workouts: [Workout]) {
        count = workouts.count
        minutes = workouts.reduce(0) { $0 + $1.durationMinutes }
        calories = workouts.reduce(0) { $0 + $1.caloriesBurned }
    }
}

// MARK: - Firestore DTO
struct WorkoutDTO: Codable, Equatable {
    var id: String
    var title: String
    var date: Date
    var notes: String
    var durationMinutes: Double
    var caloriesBurned: Double
    var entries: [EntryDTO]
    var createdAt: Date
    var updatedAt: Date
    var templateID: String?
    var programID: String?

    struct EntryDTO: Codable, Equatable {
        var id: String
        var order: Int
        var exerciseKey: String
        var name: String
        var category: String
        var mode: String
        var met: Double
        var durationMinutes: Double
        var sets: [WorkoutSet]
    }
}

extension Workout {
    var dto: WorkoutDTO {
        WorkoutDTO(
            id: id.uuidString,
            title: title,
            date: date,
            notes: notes,
            durationMinutes: durationMinutes,
            caloriesBurned: caloriesBurned,
            entries: sortedEntries.map {
                WorkoutDTO.EntryDTO(
                    id: $0.id.uuidString,
                    order: $0.order,
                    exerciseKey: $0.exerciseKey,
                    name: $0.name,
                    category: $0.categoryRaw,
                    mode: $0.modeRaw,
                    met: $0.met,
                    durationMinutes: $0.durationMinutes,
                    sets: $0.sets
                )
            },
            createdAt: createdAt,
            updatedAt: updatedAt,
            templateID: templateID,
            programID: programID
        )
    }

    /// Uzaktan gelen içerikle yerel kaydı değiştirir (eski egzersizler silinir).
    func replaceContent(with dto: WorkoutDTO, context: ModelContext) {
        title = dto.title
        date = dto.date
        notes = dto.notes
        durationMinutes = dto.durationMinutes
        caloriesBurned = dto.caloriesBurned
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        templateID = dto.templateID
        programID = dto.programID
        needsSync = false

        for entry in entries { context.delete(entry) }
        entries = []
        for entryDTO in dto.entries {
            let entry = WorkoutEntry(dto: entryDTO)
            context.insert(entry)
            entries.append(entry)
        }
    }
}
