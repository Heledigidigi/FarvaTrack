import Foundation

// MARK: - Toplu düzenleme

/// Toplu işlemin kapsamı. Günler 0'dan başlar.
struct DietBulkScope: Hashable {
    enum Days: Hashable {
        case all
        /// Bu günden (dahil) sonrası.
        case from(Int)
        case selected(Set<Int>)
    }

    var days: Days = .all
    /// Yalnızca bu öğünlerde (ad, katlanmış). Boşsa hepsi.
    var mealNames: Set<String> = []

    func includes(day: Int) -> Bool {
        switch days {
        case .all: return true
        case .from(let start): return day >= start
        case .selected(let set): return set.contains(day)
        }
    }

    func includes(meal: DietMeal) -> Bool {
        mealNames.isEmpty || mealNames.contains(DietText.fold(meal.name))
    }
}

enum DietReplaceAmount: Hashable {
    /// Aynı miktar ve ölçü.
    case same
    /// Kalorisi eşit olacak miktar.
    case equalCalories
    case manual(Double, DietUnit)
}

struct DietBulkResult: Hashable {
    var plan: DietPlan
    /// Değişen öğün sayısı.
    var mealCount: Int
    /// Değişen günler (1'den başlar).
    var days: [Int]
    /// Etkilenen günlerde günlük ortalama fark.
    var averageDelta: DietNutrition
}

enum DietBulkEdit {
    /// Bir yiyeceği başka bir yiyecekle değiştirir (değişim listelerinde de).
    static func replaceFood(in plan: DietPlan, key: String, with food: DietFood, amount: DietReplaceAmount,
                            scope: DietBulkScope) -> DietBulkResult {
        transform(plan, scope: scope) { item in
            var changed = false
            func replaced(_ portion: DietPortion) -> DietPortion {
                switch amount {
                case .same:
                    return DietPortion(food: food, amount: portion.amount, unit: food.suggestedUnits.contains(portion.unit) || portion.unit.defaultGrams != nil ? portion.unit : .serving)
                case .equalCalories:
                    let target = DietUnitTable.equalCalorieAmount(for: portion.nutrition.calories, food: food)
                    return DietPortion(food: food, amount: target.amount, unit: target.unit)
                case .manual(let value, let unit):
                    return DietPortion(food: food, amount: value, unit: unit)
                }
            }
            if item.portion.food.key == key {
                item.portion = replaced(item.portion)
                changed = true
            }
            for index in item.alternatives.indices where item.alternatives[index].food.key == key {
                item.alternatives[index] = replaced(item.alternatives[index])
                changed = true
            }
            return changed
        }
    }

    /// Miktarı artırır/azaltır (aynı ölçüde). Sıfıra inen yiyecek öğünden çıkar.
    static func adjustPortion(in plan: DietPlan, key: String, delta: Double, scope: DietBulkScope) -> DietBulkResult {
        var result = transform(plan, scope: scope) { item in
            guard item.portion.food.key == key else { return false }
            item.portion.amount = max(0, item.portion.amount + delta)
            return true
        }
        for d in result.plan.days.indices {
            for m in result.plan.days[d].meals.indices {
                result.plan.days[d].meals[m].items.removeAll { $0.portion.amount <= 0 }
            }
        }
        return result
    }

    /// Bir günün öğünlerini seçilen günlere kopyalar (öğün kimlikleri korunur, kayıtlar eşleşsin).
    static func copyDay(_ source: Int, to targets: Set<Int>, in plan: DietPlan) -> DietBulkResult {
        guard let day = plan.day(source) else { return DietBulkResult(plan: plan, mealCount: 0, days: [], averageDelta: .zero) }
        var copy = plan
        var changedDays: [Int] = []
        var delta = DietNutrition.zero
        for target in targets.sorted() where target != source && copy.days.indices.contains(target) {
            delta += day.nutrition - copy.days[target].nutrition
            copy.days[target] = DietDay(meals: day.meals.map { meal in
                var newMeal = meal
                newMeal.items = meal.items.map { DietItem(portion: $0.portion, alternatives: $0.alternatives) }
                return newMeal
            })
            changedDays.append(target + 1)
        }
        let average = changedDays.isEmpty ? .zero : delta.scaled(1 / Double(changedDays.count))
        return DietBulkResult(plan: copy, mealCount: changedDays.count * day.meals.count, days: changedDays, averageDelta: average)
    }

    /// Planda geçen yiyecekler (çok kullanılandan aza) ve kaç öğünde geçtikleri.
    static func foodUsage(in plan: DietPlan, scope: DietBulkScope = DietBulkScope()) -> [(food: DietFood, count: Int)] {
        var counts: [String: Int] = [:]
        var foods: [String: DietFood] = [:]
        for (d, day) in plan.days.enumerated() where scope.includes(day: d) {
            for meal in day.meals where scope.includes(meal: meal) {
                for item in meal.items {
                    counts[item.portion.food.key, default: 0] += 1
                    foods[item.portion.food.key] = item.portion.food
                }
            }
        }
        return counts.sorted { $0.value == $1.value ? (foods[$0.key]?.name ?? "") < (foods[$1.key]?.name ?? "") : $0.value > $1.value }
            .compactMap { pair -> (food: DietFood, count: Int)? in
                guard let food = foods[pair.key] else { return nil }
                return (food: food, count: pair.value)
            }
    }

    /// Plandaki farklı öğün adları (sıralı).
    static func mealNames(in plan: DietPlan) -> [String] {
        var seen = Set<String>()
        var names: [(String, Int)] = []
        for day in plan.days {
            for meal in day.meals where seen.insert(DietText.fold(meal.name)).inserted {
                names.append((meal.name, meal.minutes))
            }
        }
        return names.sorted { $0.1 < $1.1 }.map(\.0)
    }

    private static func transform(_ plan: DietPlan, scope: DietBulkScope, _ body: (inout DietItem) -> Bool) -> DietBulkResult {
        var copy = plan
        var mealCount = 0
        var days: [Int] = []
        var delta = DietNutrition.zero
        for d in copy.days.indices where scope.includes(day: d) {
            let before = copy.days[d].nutrition
            var dayChanged = false
            for m in copy.days[d].meals.indices where scope.includes(meal: copy.days[d].meals[m]) {
                var mealChanged = false
                for i in copy.days[d].meals[m].items.indices {
                    if body(&copy.days[d].meals[m].items[i]) { mealChanged = true }
                }
                if mealChanged { mealCount += 1; dayChanged = true }
            }
            if dayChanged {
                days.append(d + 1)
                delta += copy.days[d].nutrition - before
            }
        }
        let average = days.isEmpty ? .zero : delta.scaled(1 / Double(days.count))
        return DietBulkResult(plan: copy, mealCount: mealCount, days: days, averageDelta: average)
    }
}
