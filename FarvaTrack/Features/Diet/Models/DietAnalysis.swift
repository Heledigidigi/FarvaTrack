import Foundation

// MARK: - Program dışı (Ekstra) kayıt

/// Serbest beslenme kaydından (MealEntry) gelen, program dışında yenen yiyecek.
struct DietExtra: Hashable, Identifiable {
    var id: String
    var date: Date
    var name: String
    var amountText: String
    var nutrition: DietNutrition
}

// MARK: - Gün özeti

struct DietMealSnapshot: Hashable, Identifiable {
    var meal: DietMeal
    var log: DietMealLog?
    /// Gün geçtiyse ve işaretlenmediyse true.
    var isMissed: Bool

    var id: String { meal.id }

    var status: DietMealStatus? { log?.status.isMarked == true ? log?.status : nil }

    /// Yenen değerler (işaretlenmediyse sıfır).
    var eatenNutrition: DietNutrition {
        guard let log, log.status == .eaten || log.status == .changed else { return .zero }
        return log.eatenNutrition
    }

    var plannedNutrition: DietNutrition { meal.nutrition }
}

struct DietDaySummary: Hashable, Identifiable {
    var date: Date
    var dayKey: String
    /// Program günü (1…); program dışı günlerde nil.
    var programDay: Int?
    var meals: [DietMealSnapshot]
    var extras: [DietExtra]
    var note: DietDayNote?
    var isFuture: Bool
    var isToday: Bool

    var id: String { dayKey }

    var planned: DietNutrition { DietNutrition.sum(meals.map(\.plannedNutrition)) }
    var eaten: DietNutrition { DietNutrition.sum(meals.map(\.eatenNutrition)) + DietNutrition.sum(extras.map(\.nutrition)) }

    func count(_ status: DietMealStatus) -> Int { meals.filter { $0.status == status }.count }
    var missedCount: Int { meals.filter(\.isMissed).count }
    var pendingCount: Int { meals.filter { $0.status == nil && !$0.isMissed }.count }
    var markedCount: Int { meals.filter { $0.status != nil }.count }

    /// Uyum: planına uyulan öğün / değerlendirilebilen öğün (işaretlenen + kaçırılan).
    var adherence: Double? {
        let judged = markedCount + missedCount
        guard judged > 0 else { return nil }
        return Double(count(.eaten)) / Double(judged)
    }

    var photoCount: Int { meals.filter { $0.log?.hasPhoto == true }.count }
}

// MARK: - Aralık özeti

struct DietRangeSummary: Hashable {
    var days: [DietDaySummary]

    var pastDays: [DietDaySummary] { days.filter { !$0.isFuture } }
    /// Ortalamada bugünü saymıyoruz (gün bitmedi); başka gün yoksa bugün de sayılır.
    var completedDays: [DietDaySummary] {
        let finished = pastDays.filter { !$0.isToday && $0.programDay != nil }
        return finished.isEmpty ? pastDays.filter { $0.programDay != nil } : finished
    }

    var followed: Int { pastDays.reduce(0) { $0 + $1.count(.eaten) } }
    var changed: Int { pastDays.reduce(0) { $0 + $1.count(.changed) } }
    var skipped: Int { pastDays.reduce(0) { $0 + $1.count(.skipped) } }
    var missed: Int { pastDays.reduce(0) { $0 + $1.missedCount } }
    var judged: Int { pastDays.reduce(0) { $0 + $1.markedCount + $1.missedCount } }
    var extraCount: Int { pastDays.reduce(0) { $0 + $1.extras.count } }

    var adherence: Double? { judged > 0 ? Double(followed) / Double(judged) : nil }
    var adherencePercent: Int? { adherence.map { Int(($0 * 100).rounded()) } }

    var averageEaten: DietNutrition {
        let source = completedDays
        guard !source.isEmpty else { return .zero }
        return DietNutrition.sum(source.map(\.eaten)).scaled(1 / Double(source.count))
    }

    var averagePlanned: DietNutrition {
        let source = completedDays
        guard !source.isEmpty else { return .zero }
        return DietNutrition.sum(source.map(\.planned)).scaled(1 / Double(source.count))
    }

    /// Öğün adına göre: uydu / değişim / atladı (+ işaretlenmedi).
    struct MealStats: Hashable, Identifiable {
        var name: String
        var minutes: Int
        var eaten = 0
        var changed = 0
        var skipped = 0
        var missed = 0
        var id: String { name }
    }

    var mealStats: [MealStats] {
        var table: [String: MealStats] = [:]
        for day in pastDays {
            for snapshot in day.meals {
                let key = DietText.fold(snapshot.meal.name)
                var stats = table[key] ?? MealStats(name: snapshot.meal.name, minutes: snapshot.meal.minutes)
                switch snapshot.status {
                case .eaten: stats.eaten += 1
                case .changed: stats.changed += 1
                case .skipped: stats.skipped += 1
                default: if snapshot.isMissed { stats.missed += 1 }
                }
                table[key] = stats
            }
        }
        return table.values.sorted { $0.minutes < $1.minutes }
    }

    /// En sık değişimler ("Elma → Armut", kaç kez).
    var frequentSwaps: [(text: String, count: Int)] {
        var counts: [String: Int] = [:]
        for day in pastDays {
            for snapshot in day.meals {
                for swap in snapshot.log?.swaps ?? [] { counts[Self.swapKey(swap), default: 0] += 1 }
            }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (text: $0.key, count: $0.value) }
    }

    /// "Elma → Armut 1 orta" → "Elma → Armut" (miktar farkları aynı değişim sayılsın).
    static func swapKey(_ swap: String) -> String {
        let parts = swap.components(separatedBy: " → ")
        guard parts.count == 2 else { return swap }
        let target = parts[1].split(separator: " ").prefix { Double($0.replacingOccurrences(of: ",", with: ".")) == nil }.joined(separator: " ")
        return "\(parts[0]) → \(target.isEmpty ? parts[1] : target)"
    }

    var frequentExtras: [(text: String, count: Int, calories: Double)] {
        var table: [String: (Int, Double)] = [:]
        for day in pastDays {
            for extra in day.extras {
                let current = table[extra.name] ?? (0, 0)
                table[extra.name] = (current.0 + 1, current.1 + extra.nutrition.calories)
            }
        }
        return table.sorted { $0.value.0 == $1.value.0 ? $0.key < $1.key : $0.value.0 > $1.value.0 }
            .map { (text: $0.key, count: $0.value.0, calories: $0.value.1 / Double(max(1, $0.value.0))) }
    }

    var tagCounts: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for day in days { for tag in day.note?.tags ?? [] { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { (tag: $0.key, count: $0.value) }
    }
}

// MARK: - Yiyecek katkısı

struct DietContribution: Hashable, Identifiable {
    var name: String
    var mealName: String
    var grams: Double
    var share: Double
    var id: String { "\(name)|\(mealName)" }
}

enum DietAnalysis {
    /// Bir program için tarih aralığındaki günlerin özeti.
    static func summarize(program: DietProgram, from start: Date, to end: Date, logs: [DietMealLog],
                          notes: [DietDayNote], extras: [DietExtra], now: Date = .now,
                          calendar: Calendar = .current) -> DietRangeSummary {
        let logsByID = Dictionary(logs.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        let notesByDay = Dictionary(notes.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })
        let extrasByDay = Dictionary(grouping: extras) { DietDayKey.make($0.date, calendar: calendar) }
        let today = calendar.startOfDay(for: now)
        var days: [DietDaySummary] = []
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while cursor <= last {
            let key = DietDayKey.make(cursor, calendar: calendar)
            let number = program.programDay(on: cursor, calendar: calendar)
            let planned = program.plannedDay(on: cursor, calendar: calendar)
            let isFuture = cursor > today
            let meals = (planned?.sortedMeals ?? []).map { meal -> DietMealSnapshot in
                let log = logsByID[DietMealLog.makeID(dayKey: key, mealID: meal.id)]
                let marked = log?.status.isMarked == true
                return DietMealSnapshot(meal: meal, log: log, isMissed: !marked && cursor < today)
            }
            days.append(DietDaySummary(date: cursor, dayKey: key, programDay: number, meals: meals,
                                       extras: number == nil ? [] : (extrasByDay[key] ?? []),
                                       note: notesByDay[key], isFuture: isFuture, isToday: cursor == today))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return DietRangeSummary(days: days)
    }

    /// Bir makronun hangi yiyecekten geldiği (en çoktan aza).
    static func contributions(of kind: MacroKind, in days: [DietDaySummary]) -> [DietContribution] {
        var table: [String: DietContribution] = [:]
        var total = 0.0
        for day in days {
            for snapshot in day.meals {
                guard let log = snapshot.log, log.status == .eaten || log.status == .changed else { continue }
                for portion in log.eaten {
                    let grams = portion.nutrition.grams(of: kind)
                    total += grams
                    let key = "\(portion.food.name)|\(days.count == 1 ? snapshot.meal.name : "")"
                    var entry = table[key] ?? DietContribution(name: portion.food.name, mealName: days.count == 1 ? snapshot.meal.name : "", grams: 0, share: 0)
                    entry.grams += grams
                    table[key] = entry
                }
            }
            for extra in day.extras {
                let grams = extra.nutrition.grams(of: kind)
                total += grams
                let key = "\(extra.name)|Ekstra"
                var entry = table[key] ?? DietContribution(name: extra.name, mealName: "Ekstra", grams: 0, share: 0)
                entry.grams += grams
                table[key] = entry
            }
        }
        guard total > 0 else { return [] }
        return table.values
            .map { var c = $0; c.share = c.grams / total; return c }
            .filter { $0.grams > 0.05 }
            .sorted { $0.grams > $1.grams }
    }

    /// Kilo değişimi (ilk ve son ölçüm).
    static func weightChange(_ metrics: DietMetricsSummary?) -> (first: Double, last: Double)? {
        guard let points = metrics?.weights.sorted(by: { $0.date < $1.date }), let first = points.first, let last = points.last,
              points.count >= 1 else { return nil }
        return (first.value, last.value)
    }
}
