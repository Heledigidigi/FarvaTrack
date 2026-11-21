import Foundation
import SwiftData

// MARK: - Şablondaki egzersiz
/// Şablon içindeki bir egzersiz ve hedefleri. Şablonla birlikte tek parça saklanır (SwiftData'da Codable dizi).
struct TemplateExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseKey: String
    var name: String
    var categoryRaw: String
    var modeRaw: String
    var met: Double
    /// Set modunda hedefler
    var targetSets: Int
    var targetReps: Int
    var targetWeightKg: Double?
    /// Süre modunda hedef süre
    var durationMinutes: Double
    /// Setler arası dinlenme (saniye)
    var restSeconds: Int

    static let setRange = 1...10
    static let repRange = 1...100
    static let restOptions = [30, 45, 60, 90, 120, 180, 240]

    init(template: ExerciseTemplate, sets: Int = 3, reps: Int = 10, weightKg: Double? = nil,
         durationMinutes: Double = 20, restSeconds: Int = 90) {
        exerciseKey = template.key
        name = template.name
        categoryRaw = template.category.rawValue
        modeRaw = template.mode.rawValue
        met = template.met
        targetSets = sets
        targetReps = reps
        targetWeightKg = weightKg
        self.durationMinutes = durationMinutes
        self.restSeconds = restSeconds
    }

    var category: ExerciseCategory { ExerciseCategory(rawValue: categoryRaw) ?? .other }
    var mode: TrackingMode { TrackingMode(rawValue: modeRaw) ?? .duration }

    var exerciseTemplate: ExerciseTemplate {
        ExerciseTemplate(key: exerciseKey, name: name, category: category, mode: mode, met: met)
    }

    var targetText: String {
        switch mode {
        case .duration:
            return "\(Int(durationMinutes)) dk"
        case .sets:
            let weight = targetWeightKg.map { " • \($0.formatted(.number.precision(.fractionLength(0...1)))) kg" } ?? ""
            return "\(targetSets) × \(targetReps)\(weight)"
        }
    }

    var isValid: Bool {
        switch mode {
        case .duration: return durationMinutes > 0
        case .sets: return Self.setRange.contains(targetSets) && Self.repRange.contains(targetReps) && (targetWeightKg ?? 0) >= 0
        }
    }
}

// MARK: - Antrenman şablonu
@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var name: String
    var exercises: [TemplateExercise]
    var needsSync: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), ownerID: String, name: String, exercises: [TemplateExercise]) {
        self.id = id
        self.ownerID = ownerID
        self.name = name
        self.exercises = exercises
        self.needsSync = true
        self.createdAt = .now
        self.updatedAt = .now
    }

    static func make(from dto: WorkoutTemplateDTO, ownerID: String) -> WorkoutTemplate {
        let template = WorkoutTemplate(id: UUID(uuidString: dto.id) ?? UUID(), ownerID: ownerID, name: dto.name, exercises: dto.exercises)
        template.createdAt = dto.createdAt
        template.updatedAt = dto.updatedAt
        template.needsSync = false
        return template
    }

    func apply(_ dto: WorkoutTemplateDTO) {
        name = dto.name
        exercises = dto.exercises
        updatedAt = dto.updatedAt
        needsSync = false
    }

    var dto: WorkoutTemplateDTO {
        WorkoutTemplateDTO(id: id.uuidString, name: name, exercises: exercises, createdAt: createdAt, updatedAt: updatedAt)
    }

    var summaryText: String {
        let count = exercises.count
        let minutes = Int(exercises.reduce(0) { $0 + ($1.mode == .duration ? $1.durationMinutes : Double($1.targetSets) * Constants.Training.minutesPerSet) })
        return "\(count) egzersiz • ~\(minutes) dk"
    }
}

struct WorkoutTemplateDTO: Codable, Equatable {
    var id: String
    var name: String
    var exercises: [TemplateExercise]
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Program
enum ProgramKind: String, Codable, CaseIterable, Identifiable {
    /// Şablonlar haftanın günlerine atanır.
    case weekly
    /// Şablonlar sırayla döner; hangi gün gidilirse sıradaki yapılır.
    case rotation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: return "Haftalık"
        case .rotation: return "Sıralı döngü"
        }
    }

    var detail: String {
        switch self {
        case .weekly: return "Her şablon haftanın belirli günlerine atanır."
        case .rotation: return "Gün önemli değil; her antrenmandan sonra sıradaki şablon önerilir."
        }
    }
}

@Model
final class TrainingProgram {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var name: String
    var kindRaw: String
    /// Haftalık: 7 eleman, 0 = Pazartesi. Boş metin dinlenme günüdür.
    var weekdayTemplateIDs: [String]
    /// Döngü: şablon kimlikleri sırasıyla.
    var rotationTemplateIDs: [String]
    /// Döngüde planlanan antrenman günleri (0 = Pazartesi). Hatırlatıcı ve uyum hesabında kullanılır.
    var rotationDays: [Int] = [0, 2, 4]
    var isActive: Bool
    /// Döngüde sıranın sayılmaya başladığı an (programı yeniden etkinleştirince sıfırlanır).
    var activatedAt: Date
    var needsSync: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), ownerID: String, name: String, kind: ProgramKind,
         weekdayTemplateIDs: [String] = Array(repeating: "", count: 7), rotationTemplateIDs: [String] = []) {
        self.id = id
        self.ownerID = ownerID
        self.name = name
        self.kindRaw = kind.rawValue
        self.weekdayTemplateIDs = weekdayTemplateIDs
        self.rotationTemplateIDs = rotationTemplateIDs
        self.isActive = false
        self.activatedAt = .now
        self.needsSync = true
        self.createdAt = .now
        self.updatedAt = .now
    }

    var kind: ProgramKind {
        get { ProgramKind(rawValue: kindRaw) ?? .weekly }
        set { kindRaw = newValue.rawValue }
    }

    static func make(from dto: TrainingProgramDTO, ownerID: String) -> TrainingProgram {
        let program = TrainingProgram(id: UUID(uuidString: dto.id) ?? UUID(), ownerID: ownerID, name: dto.name, kind: .weekly)
        program.apply(dto)
        program.createdAt = dto.createdAt
        return program
    }

    func apply(_ dto: TrainingProgramDTO) {
        name = dto.name
        kindRaw = dto.kind
        weekdayTemplateIDs = TrainingProgram.normalizedWeek(dto.weekdayTemplateIDs)
        rotationTemplateIDs = dto.rotationTemplateIDs
        rotationDays = TrainingProgram.normalizedDays(dto.rotationDays ?? [0, 2, 4])
        isActive = dto.isActive
        activatedAt = dto.activatedAt
        updatedAt = dto.updatedAt
        needsSync = false
    }

    var dto: TrainingProgramDTO {
        TrainingProgramDTO(
            id: id.uuidString, name: name, kind: kindRaw,
            weekdayTemplateIDs: weekdayTemplateIDs, rotationTemplateIDs: rotationTemplateIDs,
            isActive: isActive, activatedAt: activatedAt, createdAt: createdAt, updatedAt: updatedAt,
            rotationDays: rotationDays
        )
    }

    var snapshot: ProgramSnapshot {
        ProgramSnapshot(
            id: id, kind: kind,
            weekly: TrainingProgram.normalizedWeek(weekdayTemplateIDs).map { UUID(uuidString: $0) },
            rotation: rotationTemplateIDs.compactMap(UUID.init(uuidString:)),
            activatedAt: activatedAt,
            rotationDays: TrainingProgram.normalizedDays(rotationDays)
        )
    }

    /// Kullanılan tüm şablon kimlikleri (şablon silinirken programdan çıkarmak için).
    var templateIDs: Set<String> {
        Set(weekdayTemplateIDs.filter { !$0.isEmpty } + rotationTemplateIDs)
    }

    static func normalizedWeek(_ ids: [String]) -> [String] {
        Array((ids + Array(repeating: "", count: 7)).prefix(7))
    }

    /// 0–6 arası, tekrarsız ve sıralı gün listesi.
    static func normalizedDays(_ days: [Int]) -> [Int] {
        Array(Set(days.filter { (0...6).contains($0) })).sorted()
    }
}

struct TrainingProgramDTO: Codable, Equatable {
    var id: String
    var name: String
    var kind: String
    var weekdayTemplateIDs: [String]
    var rotationTemplateIDs: [String]
    var isActive: Bool
    var activatedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var rotationDays: [Int]?
}

// MARK: - Planlayıcı
/// Programın SwiftData'dan bağımsız hali (test edilebilir).
struct ProgramSnapshot: Equatable {
    var id: UUID
    var kind: ProgramKind
    /// 0 = Pazartesi; `nil` dinlenme günü.
    var weekly: [UUID?]
    var rotation: [UUID]
    var activatedAt: Date
    /// Döngüde planlanan günler (0 = Pazartesi)
    var rotationDays: [Int] = [0, 2, 4]

    /// Haftada planlanan antrenman günleri (0 = Pazartesi).
    var plannedWeekdays: [Int] {
        switch kind {
        case .weekly: return weekly.indices.filter { weekly[$0] != nil }
        case .rotation: return rotationDays
        }
    }

    /// Programa ait şablonlar (uyum hesabında hangi antrenmanların sayılacağı).
    var templateIDs: Set<UUID> {
        Set(weekly.compactMap { $0 } + rotation)
    }
}

struct CompletedSession: Equatable {
    var date: Date
    var templateID: UUID?
}

struct UpcomingSession: Equatable {
    var date: Date
    var templateID: UUID
}

enum TodayPlan: Equatable {
    /// Aktif program yok
    case none
    /// Bugün dinlenme; varsa sıradaki antrenman
    case rest(next: UpcomingSession?)
    case workout(templateID: UUID, isDone: Bool)
}

enum ProgramPlanner {
    static let weekdayNames = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
    static let weekdayShortNames = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]

    /// Takvim gününden program indeksi (0 = Pazartesi).
    static func weekdayIndex(of date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    static func plan(
        for program: ProgramSnapshot?,
        completed: [CompletedSession],
        on date: Date,
        existingTemplates: Set<UUID>,
        calendar: Calendar = .current
    ) -> TodayPlan {
        guard let program else { return .none }
        let doneToday = completed.filter { calendar.isDate($0.date, inSameDayAs: date) }

        switch program.kind {
        case .weekly:
            let week = program.weekly.map { id in id.flatMap { existingTemplates.contains($0) ? $0 : nil } }
            guard week.contains(where: { $0 != nil }) else { return .none }
            if let templateID = week[weekdayIndex(of: date, calendar: calendar)] {
                return .workout(templateID: templateID, isDone: doneToday.contains { $0.templateID == templateID })
            }
            return .rest(next: nextWeekly(week, after: date, calendar: calendar))

        case .rotation:
            let rotation = program.rotation.filter { existingTemplates.contains($0) }
            guard let first = rotation.first else { return .none }
            // Bugün döngüden bir antrenman yapıldıysa onu "tamamlandı" göster.
            if let today = doneToday.last(where: { session in session.templateID.map { rotation.contains($0) } ?? false }), let id = today.templateID {
                return .workout(templateID: id, isDone: true)
            }
            let relevant = completed
                .filter { session in session.date >= program.activatedAt && (session.templateID.map { rotation.contains($0) } ?? false) }
                .sorted { $0.date < $1.date }
            guard let last = relevant.last?.templateID, let index = rotation.firstIndex(of: last) else {
                return .workout(templateID: first, isDone: false)
            }
            return .workout(templateID: rotation[(index + 1) % rotation.count], isDone: false)
        }
    }

    /// Haftalık programda bugünden sonraki ilk antrenman günü (en fazla 7 gün ileri).
    static func nextWeekly(_ week: [UUID?], after date: Date, calendar: Calendar = .current) -> UpcomingSession? {
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else { continue }
            if let id = week[weekdayIndex(of: day, calendar: calendar)] {
                return UpcomingSession(date: day, templateID: id)
            }
        }
        return nil
    }

    /// Bir egzersizin en son yapıldığı antrenmandaki setler (en yeni önce verilmiş listeden).
    static func lastPerformance(of exerciseKey: String, in workouts: [Workout]) -> [WorkoutSet]? {
        for workout in workouts.sorted(by: { $0.date > $1.date }) {
            if let entry = workout.sortedEntries.first(where: { $0.exerciseKey == exerciseKey && !$0.sets.isEmpty }) {
                return entry.sets
            }
        }
        return nil
    }
}

// MARK: - Program uyumu
struct WeekAdherence: Identifiable, Equatable {
    let weekStart: Date
    let planned: Int
    let done: Int
    /// İçinde bulunulan hafta (henüz bitmedi).
    let isCurrent: Bool

    var id: Date { weekStart }
    var ratio: Double { planned > 0 ? min(Double(done) / Double(planned), 1) : 0 }
    var isComplete: Bool { planned > 0 && done >= planned }
}

enum AdherenceCalculator {
    /// Son `count` haftanın (Pazartesi başlangıçlı) planlanan/yapılan sayıları, eskiden yeniye.
    /// Program etkinleştirilmeden önceki haftalar dahil edilmez. Aynı gün yapılan birden çok antrenman bir sayılır.
    static func weeks(
        program: ProgramSnapshot,
        completed: [CompletedSession],
        count: Int = 8,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [WeekAdherence] {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        guard let currentWeek = mondayCalendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let activationWeek = mondayCalendar.dateInterval(of: .weekOfYear, for: program.activatedAt)?.start else { return [] }

        let planned = program.plannedWeekdays.count
        let ids = program.templateIDs
        let sessionDays = Set(completed.compactMap { session -> Date? in
            guard let id = session.templateID, ids.contains(id) else { return nil }
            return calendar.startOfDay(for: session.date)
        })

        return (0..<max(count, 1)).reversed().compactMap { offset -> WeekAdherence? in
            guard let start = mondayCalendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  start >= activationWeek,
                  let end = mondayCalendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            let done = sessionDays.filter { $0 >= start && $0 < end }.count
            return WeekAdherence(weekStart: start, planned: planned, done: done, isCurrent: offset == 0)
        }
    }

    /// Biten haftalardan geriye doğru, planın tamamlandığı ardışık hafta sayısı.
    static func completeWeekStreak(_ weeks: [WeekAdherence]) -> Int {
        var streak = 0
        for week in weeks.reversed() where !week.isCurrent {
            guard week.isComplete else { break }
            streak += 1
        }
        // Bu hafta da şimdiden tamamlandıysa seriye eklenir.
        if let current = weeks.last, current.isCurrent, current.isComplete { streak += 1 }
        return streak
    }

    /// Biten haftaların ortalama uyum oranı (yüzde).
    static func averagePercent(_ weeks: [WeekAdherence]) -> Int? {
        let finished = weeks.filter { !$0.isCurrent && $0.planned > 0 }
        guard !finished.isEmpty else { return nil }
        return Int((finished.reduce(0) { $0 + $1.ratio } / Double(finished.count) * 100).rounded())
    }
}
