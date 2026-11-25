import Foundation

// MARK: - Plan parçaları

/// Öğündeki bir yiyecek ve diyetisyenin verdiği değişimler ("ya da").
struct DietItem: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var portion: DietPortion
    var alternatives: [DietPortion] = []

    init(id: String = UUID().uuidString, portion: DietPortion, alternatives: [DietPortion] = []) {
        self.id = id
        self.portion = portion
        self.alternatives = alternatives
    }
}

struct DietMeal: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    /// Günün kaçıncı dakikası (08:30 → 510).
    var minutes: Int
    var items: [DietItem] = []

    init(id: String = UUID().uuidString, name: String, minutes: Int, items: [DietItem] = []) {
        self.id = id
        self.name = name
        self.minutes = minutes
        self.items = items
    }

    var nutrition: DietNutrition { DietNutrition.sum(items.map(\.portion.nutrition)) }
    var timeText: String { DietFormat.time(minutes: minutes) }
    var portions: [DietPortion] { items.map(\.portion) }
    var summaryText: String { items.map(\.portion.label).joined(separator: " · ") }

    /// Yeni bir program için önerilen öğünler.
    static func defaultSlots() -> [DietMeal] {
        [DietMeal(name: "Kahvaltı", minutes: 8 * 60), DietMeal(name: "Ara öğün", minutes: 11 * 60),
         DietMeal(name: "Öğle", minutes: 13 * 60 + 30), DietMeal(name: "İkindi", minutes: 16 * 60 + 30),
         DietMeal(name: "Akşam", minutes: 19 * 60 + 30)]
    }
}

struct DietDay: Codable, Hashable {
    var meals: [DietMeal]

    init(meals: [DietMeal] = []) { self.meals = meals }

    var nutrition: DietNutrition { DietNutrition.sum(meals.map(\.nutrition)) }
    var sortedMeals: [DietMeal] { meals.sorted { $0.minutes < $1.minutes } }
}

// MARK: - Plan

/// Programın bir sürümündeki tüm günler. Firestore belge sınırı (1 MB) için yiyecekler tek bir
/// tabloda saklanır; günlerde yalnızca anahtar ve miktar yazar.
struct DietPlan: Hashable {
    var days: [DietDay]

    init(days: [DietDay] = []) { self.days = days }

    var dayCount: Int { days.count }

    func day(_ index: Int) -> DietDay? { days.indices.contains(index) ? days[index] : nil }

    /// Günlük ortalama.
    var averageNutrition: DietNutrition {
        guard !days.isEmpty else { return .zero }
        return DietNutrition.sum(days.map(\.nutrition)).scaled(1 / Double(days.count))
    }

    var averageMealsPerDay: Double {
        guard !days.isEmpty else { return 0 }
        return Double(days.reduce(0) { $0 + $1.meals.count }) / Double(days.count)
    }

    var alternativeCount: Int {
        days.reduce(0) { $0 + $1.meals.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.alternatives.count } } }
    }

    /// Plandaki tüm yiyecekler (anahtara göre).
    var foods: [String: DietFood] {
        var table: [String: DietFood] = [:]
        for day in days {
            for meal in day.meals {
                for item in meal.items {
                    table[item.portion.food.key] = item.portion.food
                    for alternative in item.alternatives { table[alternative.food.key] = alternative.food }
                }
            }
        }
        return table
    }

    var isEmpty: Bool { days.allSatisfy { $0.meals.allSatisfy { $0.items.isEmpty } } }

    /// Boş bir program: istenen gün sayısı, her gün varsayılan öğünler.
    static func empty(days count: Int) -> DietPlan {
        DietPlan(days: (0..<max(1, count)).map { _ in DietDay(meals: DietMeal.defaultSlots()) })
    }
}

extension DietPlan: Codable {
    private struct CompactPortion: Codable, Hashable {
        var k: String
        var a: Double
        var u: DietUnit
    }

    private struct CompactItem: Codable, Hashable {
        var id: String
        var p: CompactPortion
        var alt: [CompactPortion]?
    }

    private struct CompactMeal: Codable, Hashable {
        var id: String
        var name: String
        var minutes: Int
        var items: [CompactItem]
    }

    private struct CompactDay: Codable, Hashable {
        var meals: [CompactMeal]
    }

    private enum CodingKeys: String, CodingKey { case foods, days }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let foods = try container.decodeIfPresent([String: DietFood].self, forKey: .foods) ?? [:]
        let compact = try container.decodeIfPresent([CompactDay].self, forKey: .days) ?? []
        func portion(_ p: CompactPortion) -> DietPortion {
            DietPortion(food: foods[p.k] ?? .placeholder(name: p.k), amount: p.a, unit: p.u)
        }
        days = compact.map { day in
            DietDay(meals: day.meals.map { meal in
                DietMeal(id: meal.id, name: meal.name, minutes: meal.minutes, items: meal.items.map { item in
                    DietItem(id: item.id, portion: portion(item.p), alternatives: (item.alt ?? []).map(portion))
                })
            })
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        func compact(_ p: DietPortion) -> CompactPortion { CompactPortion(k: p.food.key, a: p.amount, u: p.unit) }
        try container.encode(foods, forKey: .foods)
        try container.encode(days.map { day in
            CompactDay(meals: day.meals.map { meal in
                CompactMeal(id: meal.id, name: meal.name, minutes: meal.minutes, items: meal.items.map { item in
                    CompactItem(id: item.id, p: compact(item.portion), alt: item.alternatives.isEmpty ? nil : item.alternatives.map(compact))
                })
            })
        }, forKey: .days)
    }
}

// MARK: - Sürüm

struct DietVersion: Codable, Hashable, Identifiable {
    var number: Int
    /// Bu sürüm bu günden (gün başı) itibaren geçerli.
    var effectiveFrom: Date
    var createdAt: Date
    var authorID: String
    var authorName: String?
    /// "Excel'den aktarıldı", "Toplu düzenleme: Beyaz peynir → Lor", öneri notu…
    var note: String
    var plan: DietPlan

    var id: Int { number }
}

enum DietEndBehavior: String, Codable, CaseIterable, Identifiable {
    case stop, loop
    var id: String { rawValue }
    var title: String { self == .stop ? "Dur" : "Başa dön" }
}

/// Program süresince kilo ve ölçüler (programı inceleyen kişi görebilsin diye programa yazılır).
struct DietMetricsSummary: Codable, Hashable {
    struct Point: Codable, Hashable {
        var date: Date
        var value: Double
    }

    var weights: [Point] = []
    /// Ölçü adı ("Bel") → ilk ve son değer.
    var measurements: [String: [Point]] = [:]
    var updatedAt: Date = .now
}

// MARK: - Program

/// `dietPrograms/{id}`: kullanıcının takip ettiği program. İzin verilen kişiler (`viewerIDs`) okuyabilir.
struct DietProgram: Codable, Hashable, Identifiable {
    var id: String
    var ownerID: String
    var ownerName: String?
    var viewerIDs: [String]
    var name: String
    var startDate: Date
    var endBehavior: DietEndBehavior
    var versions: [DietVersion]
    var isArchived: Bool
    /// Programı sohbetten gönderen kişi (kabul edilen tekliften).
    var sharedByID: String?
    var sharedByName: String?
    var metrics: DietMetricsSummary?
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, ownerID: String, ownerName: String? = nil, viewerIDs: [String] = [],
         name: String, startDate: Date, endBehavior: DietEndBehavior = .stop, plan: DietPlan,
         note: String = "", authorName: String? = nil, sharedByID: String? = nil, sharedByName: String? = nil,
         now: Date = .now) {
        self.id = id
        self.ownerID = ownerID
        self.ownerName = ownerName
        self.viewerIDs = viewerIDs
        self.name = name
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endBehavior = endBehavior
        self.versions = [DietVersion(number: 1, effectiveFrom: Calendar.current.startOfDay(for: startDate), createdAt: now,
                                     authorID: ownerID, authorName: authorName, note: note, plan: plan)]
        self.isArchived = false
        self.sharedByID = sharedByID
        self.sharedByName = sharedByName
        self.metrics = nil
        self.createdAt = now
        self.updatedAt = now
    }

    private enum CodingKeys: String, CodingKey {
        case id, ownerID, ownerName, viewerIDs, name, startDate, endBehavior, versions, isArchived
        case sharedByID, sharedByName, metrics, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        ownerID = try c.decode(String.self, forKey: .ownerID)
        ownerName = try c.decodeIfPresent(String.self, forKey: .ownerName)
        viewerIDs = try c.decodeIfPresent([String].self, forKey: .viewerIDs) ?? []
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Diyet programı"
        startDate = try c.decode(Date.self, forKey: .startDate)
        endBehavior = try c.decodeIfPresent(DietEndBehavior.self, forKey: .endBehavior) ?? .stop
        versions = try c.decodeIfPresent([DietVersion].self, forKey: .versions) ?? []
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        sharedByID = try c.decodeIfPresent(String.self, forKey: .sharedByID)
        sharedByName = try c.decodeIfPresent(String.self, forKey: .sharedByName)
        metrics = try c.decodeIfPresent(DietMetricsSummary.self, forKey: .metrics)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? startDate
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        if versions.isEmpty {
            versions = [DietVersion(number: 1, effectiveFrom: startDate, createdAt: createdAt, authorID: ownerID,
                                    authorName: nil, note: "", plan: DietPlan())]
        }
    }

    // MARK: Sürümler

    var latest: DietVersion { versions.max(by: { $0.number < $1.number }) ?? versions[0] }
    var latestPlan: DietPlan { latest.plan }
    var dayCount: Int { latestPlan.dayCount }

    /// O gün geçerli sürüm: etkinlik tarihi o güne kadar olan en yeni sürüm.
    func version(on date: Date, calendar: Calendar = .current) -> DietVersion {
        let day = calendar.startOfDay(for: date)
        let sorted = versions.sorted { $0.number < $1.number }
        return sorted.last(where: { $0.effectiveFrom <= day }) ?? sorted.first ?? latest
    }

    // MARK: Takvim

    /// Başlangıçtan bu yana geçen gün (0 = ilk gün). Başlangıçtan önceyse negatif.
    func dayOffset(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Program günü (1'den başlar). Başlamadıysa ya da (bitince dur) bittiyse `nil`.
    func programDay(on date: Date, calendar: Calendar = .current) -> Int? {
        let offset = dayOffset(of: date, calendar: calendar)
        let count = version(on: date, calendar: calendar).plan.dayCount
        guard offset >= 0, count > 0 else { return nil }
        if offset >= count {
            guard endBehavior == .loop else { return nil }
            return offset % count + 1
        }
        return offset + 1
    }

    /// O günün planı.
    func plannedDay(on date: Date, calendar: Calendar = .current) -> DietDay? {
        guard let number = programDay(on: date, calendar: calendar) else { return nil }
        return version(on: date, calendar: calendar).plan.day(number - 1)
    }

    /// Tekrarın kaçıncı turu (0 = ilk tur).
    func cycle(on date: Date, calendar: Calendar = .current) -> Int {
        let count = max(1, version(on: date, calendar: calendar).plan.dayCount)
        return max(0, dayOffset(of: date, calendar: calendar)) / count
    }

    var endDate: Date? {
        guard endBehavior == .stop, dayCount > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: dayCount - 1, to: startDate)
    }

    func isActive(on date: Date) -> Bool { !isArchived && programDay(on: date) != nil }

    /// Bugün program sürüyor mu ya da yakında başlayacak mı.
    func isCurrentOrUpcoming(now: Date = .now) -> Bool {
        guard !isArchived else { return false }
        if dayOffset(of: now) < 0 { return true }
        return programDay(on: now) != nil
    }

    // MARK: Düzenleme

    /// Yeni sürüm ekler. Program henüz başlamadıysa ya da aynı güne zaten bir sürüm varsa o sürüm güncellenir.
    mutating func apply(plan: DietPlan, effectiveFrom date: Date, authorID: String, authorName: String?,
                        note: String, now: Date = .now) {
        let day = Calendar.current.startOfDay(for: date)
        if day <= startDate, versions.count == 1 {
            versions[0].plan = plan
            versions[0].note = note.isEmpty ? versions[0].note : note
            versions[0].createdAt = now
        } else if let index = versions.firstIndex(where: { $0.effectiveFrom == day && $0.number == latest.number }) {
            versions[index].plan = plan
            versions[index].note = note
            versions[index].createdAt = now
            versions[index].authorID = authorID
            versions[index].authorName = authorName
        } else {
            versions.append(DietVersion(number: latest.number + 1, effectiveFrom: max(day, startDate), createdAt: now,
                                        authorID: authorID, authorName: authorName, note: note, plan: plan))
        }
        updatedAt = now
    }
}

// MARK: - Sürüm farkı

/// İki plan arasındaki değişikliklerin okunur özeti ("+ İkindi: Yoğurt 1 kase · 12 gün").
struct DietPlanChange: Hashable, Identifiable {
    enum Kind: Hashable { case added, removed, changed, replaced }

    var kind: Kind
    var mealName: String
    var text: String
    var days: [Int]

    var id: String { "\(kind)|\(mealName)|\(text)" }

    var symbol: String {
        switch kind {
        case .added: return "+"
        case .removed: return "−"
        case .changed: return "↺"
        case .replaced: return "↺"
        }
    }

    var daysText: String {
        if days.count == 1 { return "Gün \(days[0])" }
        return "\(days.count) gün"
    }
}

enum DietPlanDiff {
    static func changes(from old: DietPlan, to new: DietPlan) -> [DietPlanChange] {
        var grouped: [String: DietPlanChange] = [:]
        var order: [String] = []
        func add(_ kind: DietPlanChange.Kind, _ meal: String, _ text: String, day: Int) {
            let key = "\(kind)|\(meal)|\(text)"
            if grouped[key] == nil {
                grouped[key] = DietPlanChange(kind: kind, mealName: meal, text: text, days: [])
                order.append(key)
            }
            grouped[key]?.days.append(day)
        }

        let count = max(old.dayCount, new.dayCount)
        for index in 0..<count {
            let dayNumber = index + 1
            let oldDay = old.day(index)
            let newDay = new.day(index)
            if oldDay == nil { add(.added, "Program", "Yeni gün eklendi", day: dayNumber); continue }
            if newDay == nil { add(.removed, "Program", "Gün çıkarıldı", day: dayNumber); continue }
            guard let oldDay, let newDay else { continue }
            for newMeal in newDay.meals {
                let oldMeal = oldDay.meals.first(where: { $0.id == newMeal.id })
                    ?? oldDay.meals.first(where: { DietText.fold($0.name) == DietText.fold(newMeal.name) })
                guard let oldMeal else {
                    add(.added, newMeal.name, "Öğün eklendi", day: dayNumber)
                    continue
                }
                let oldByKey = Dictionary(oldMeal.items.map { ($0.portion.food.key, $0.portion) }, uniquingKeysWith: { a, _ in a })
                let newByKey = Dictionary(newMeal.items.map { ($0.portion.food.key, $0.portion) }, uniquingKeysWith: { a, _ in a })
                let removed = oldMeal.items.map(\.portion).filter { newByKey[$0.food.key] == nil }
                let added = newMeal.items.map(\.portion).filter { oldByKey[$0.food.key] == nil }
                if removed.count == 1, added.count == 1 {
                    add(.replaced, newMeal.name, "\(removed[0].food.name) → \(added[0].label)", day: dayNumber)
                } else {
                    for portion in added { add(.added, newMeal.name, "\(portion.food.name) \(portion.amountText) eklendi", day: dayNumber) }
                    for portion in removed { add(.removed, newMeal.name, "\(portion.food.name) çıkarıldı", day: dayNumber) }
                }
                for portion in newMeal.items.map(\.portion) {
                    guard let before = oldByKey[portion.food.key] else { continue }
                    if before.amount != portion.amount || before.unit != portion.unit {
                        add(.changed, newMeal.name, "\(portion.food.name) \(before.shortAmountText) → \(portion.shortAmountText)", day: dayNumber)
                    }
                }
            }
            for oldMeal in oldDay.meals where !newDay.meals.contains(where: { $0.id == oldMeal.id || DietText.fold($0.name) == DietText.fold(oldMeal.name) }) {
                add(.removed, oldMeal.name, "Öğün çıkarıldı", day: dayNumber)
            }
        }
        return order.compactMap { grouped[$0] }
    }
}
