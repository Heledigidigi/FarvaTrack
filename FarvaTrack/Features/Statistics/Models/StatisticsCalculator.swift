import Foundation

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Hafta"
        case .month: return "Ay"
        case .year: return "Yıl"
        }
    }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }

    var axisStyle: ChartView.XAxisStyle {
        switch self {
        case .week: return .weekday
        case .month: return .dayOfMonth
        case .year: return .monthOfYear
        }
    }

    var barUnit: Calendar.Component { self == .year ? .month : .day }
}

/// Bir metriğin dönem özeti. Ortalama, kayıt olan günler üzerinden hesaplanır.
struct MetricSummary: Equatable {
    var total: Double
    var average: Double?
    var best: DailyValue?
    var recordedDays: Int
    /// Hedefe ulaşılan gün sayısı (hedef yoksa `nil`).
    var goalDays: Int?
    /// Önceki eşit uzunluktaki döneme göre ortalamadaki değişim (yüzde).
    var changePercent: Double?
}

enum StatisticsCalculator {
    /// Örnekleri günlere toplar; dönemin her günü için bir değer döner (eskiden yeniye).
    static func dailyTotals(
        _ samples: [(date: Date, value: Double)],
        days: Int,
        endingOn end: Date,
        calendar: Calendar = .current
    ) -> [DailyValue] {
        var sums: [Date: Double] = [:]
        for sample in samples { sums[calendar.startOfDay(for: sample.date), default: 0] += sample.value }
        let today = calendar.startOfDay(for: end)
        return (0..<max(days, 1)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyValue(date: day, value: sums[day] ?? 0)
        }
    }

    /// Her gün için son değeri alır (kilo gibi anlık ölçümler); ölçüm olmayan gün 0'dır.
    static func dailyLatest(
        _ samples: [(date: Date, value: Double)],
        days: Int,
        endingOn end: Date,
        calendar: Calendar = .current
    ) -> [DailyValue] {
        var latest: [Date: (Date, Double)] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            if let existing = latest[day], existing.0 >= sample.date { continue }
            latest[day] = (sample.date, sample.value)
        }
        let today = calendar.startOfDay(for: end)
        return (0..<max(days, 1)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyValue(date: day, value: latest[day]?.1 ?? 0)
        }
    }

    /// Grafik serisi: hafta/ay için günlük; yıl için ay başına kayıtlı günlerin ortalaması.
    static func chartSeries(_ daily: [DailyValue], period: StatsPeriod, calendar: Calendar = .current) -> [DailyValue] {
        guard period == .year else { return daily }
        var buckets: [Date: [Double]] = [:]
        var order: [Date] = []
        for item in daily {
            guard let month = calendar.date(from: calendar.dateComponents([.year, .month], from: item.date)) else { continue }
            if buckets[month] == nil {
                buckets[month] = []
                order.append(month)
            }
            if item.value > 0 { buckets[month]?.append(item.value) }
        }
        return order.map { month in
            let values = buckets[month] ?? []
            return DailyValue(date: month, value: values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count))
        }
    }

    static func summary(_ daily: [DailyValue], goal: Double? = nil, previous: [DailyValue] = []) -> MetricSummary {
        let recorded = daily.filter { $0.value > 0 }
        let total = recorded.reduce(0) { $0 + $1.value }
        let average = recorded.isEmpty ? nil : total / Double(recorded.count)

        var change: Double?
        let previousRecorded = previous.filter { $0.value > 0 }
        if let average, !previousRecorded.isEmpty {
            let previousAverage = previousRecorded.reduce(0) { $0 + $1.value } / Double(previousRecorded.count)
            if previousAverage > 0 { change = (average - previousAverage) / previousAverage * 100 }
        }

        return MetricSummary(
            total: total,
            average: average,
            best: recorded.max { $0.value < $1.value },
            recordedDays: recorded.count,
            goalDays: goal.map { goal in recorded.filter { $0.value >= goal }.count },
            changePercent: change
        )
    }
}

// MARK: - Rozetler
enum Badge: String, CaseIterable, Identifiable {
    case firstWorkout, workouts10, workouts50
    case steps10k, stepGoalStreak7
    case waterStreak7, waterStreak30
    case mealStreak7
    case sleepLog7
    case weighIn4, firstMeasurement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstWorkout: return "İlk Adım"
        case .workouts10: return "Kararlı"
        case .workouts50: return "Demir İrade"
        case .steps10k: return "10 Bin"
        case .stepGoalStreak7: return "Yürüyüş Serisi"
        case .waterStreak7: return "Su Kaynağı"
        case .waterStreak30: return "Okyanus"
        case .mealStreak7: return "Not Defteri"
        case .sleepLog7: return "Uyku Günlüğü"
        case .weighIn4: return "Düzenli Tartı"
        case .firstMeasurement: return "Mezura"
        }
    }

    var detail: String {
        switch self {
        case .firstWorkout: return "İlk antrenmanını kaydet"
        case .workouts10: return "10 antrenman kaydet"
        case .workouts50: return "50 antrenman kaydet"
        case .steps10k: return "Bir günde 10.000 adım at"
        case .stepGoalStreak7: return "7 gün üst üste adım hedefine ulaş"
        case .waterStreak7: return "7 gün üst üste su hedefine ulaş"
        case .waterStreak30: return "30 gün üst üste su hedefine ulaş"
        case .mealStreak7: return "7 gün üst üste öğün kaydet"
        case .sleepLog7: return "7 gece uyku kaydet"
        case .weighIn4: return "4 farklı günde tartıl"
        case .firstMeasurement: return "İlk vücut ölçünü gir"
        }
    }

    var systemImage: String {
        switch self {
        case .firstWorkout, .workouts10, .workouts50: return "dumbbell.fill"
        case .steps10k, .stepGoalStreak7: return "figure.walk"
        case .waterStreak7, .waterStreak30: return "drop.fill"
        case .mealStreak7: return "fork.knife"
        case .sleepLog7: return "moon.stars.fill"
        case .weighIn4: return "scalemass.fill"
        case .firstMeasurement: return "ruler.fill"
        }
    }

    var target: Int {
        switch self {
        case .firstWorkout, .firstMeasurement: return 1
        case .workouts10: return 10
        case .workouts50: return 50
        case .steps10k: return 10_000
        case .stepGoalStreak7, .waterStreak7, .mealStreak7, .sleepLog7: return 7
        case .waterStreak30: return 30
        case .weighIn4: return 4
        }
    }
}

struct BadgeStatus: Identifiable, Equatable {
    let badge: Badge
    let current: Int

    var id: String { badge.id }
    var isEarned: Bool { current >= badge.target }
    var progress: Double { min(Double(current) / Double(badge.target), 1) }
}

/// Rozetler kaydedilmez; her seferinde mevcut verilerden hesaplanır (cihazlar arası tutarlı kalır).
struct BadgeInput {
    var workoutCount = 0
    /// Gün başlangıcı → adım
    var dailySteps: [Date: Int] = [:]
    var stepGoal = Constants.Defaults.stepGoal
    /// Gün başlangıcı → ml
    var dailyWater: [Date: Int] = [:]
    var waterGoal = Constants.Defaults.waterGoalMl
    var mealDays: Set<Date> = []
    var sleepNights = 0
    var weighInDays: Set<Date> = []
    var measurementCount = 0
}

enum BadgeEngine {
    static func evaluate(_ input: BadgeInput, calendar: Calendar = .current) -> [BadgeStatus] {
        let stepGoalDays = Set(input.dailySteps.filter { $0.value >= max(input.stepGoal, 1) }.keys)
        let waterGoalDays = Set(input.dailyWater.filter { $0.value >= max(input.waterGoal, 1) }.keys)
        let waterStreak = longestStreak(waterGoalDays, calendar: calendar)

        return Badge.allCases.map { badge in
            let current: Int
            switch badge {
            case .firstWorkout, .workouts10, .workouts50: current = input.workoutCount
            case .steps10k: current = input.dailySteps.values.max() ?? 0
            case .stepGoalStreak7: current = longestStreak(stepGoalDays, calendar: calendar)
            case .waterStreak7, .waterStreak30: current = waterStreak
            case .mealStreak7: current = longestStreak(input.mealDays, calendar: calendar)
            case .sleepLog7: current = input.sleepNights
            case .weighIn4: current = input.weighInDays.count
            case .firstMeasurement: current = input.measurementCount
            }
            return BadgeStatus(badge: badge, current: current)
        }
    }

    /// Ardışık günlerden oluşan en uzun seri.
    static func longestStreak(_ days: Set<Date>, calendar: Calendar = .current) -> Int {
        let sorted = Set(days.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0
        var current = 0
        var previous: Date?
        for day in sorted {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }
        return best
    }
}
