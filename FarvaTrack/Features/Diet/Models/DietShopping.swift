import Foundation

// MARK: - Alışveriş listesi

enum DietShoppingCategory: String, CaseIterable, Identifiable, Hashable {
    case dairy, protein, produce, grains, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dairy: return "Süt ürünleri"
        case .protein: return "Et, tavuk, balık, yumurta"
        case .produce: return "Sebze ve meyve"
        case .grains: return "Tahıl, ekmek, bakliyat"
        case .other: return "Diğer"
        }
    }

    private static let keywords: [(DietShoppingCategory, [String])] = [
        (.dairy, ["sut", "yogurt", "ayran", "peynir", "kefir", "lor", "kasar", "tereyag", "labne", "krema", "kaymak"]),
        (.protein, ["tavuk", "et ", "kofte", "kiyma", "balik", "somon", "ton", "yumurta", "omlet", "hindi", "dana", "kuzu", "sucuk", "doner", "sis", "biftek", "levrek", "cupra", "hamsi"]),
        (.produce, ["elma", "armut", "muz", "portakal", "mandalina", "cilek", "uzum", "karpuz", "kavun", "kivi", "nar", "salata", "domates", "salatalik", "biber", "marul", "roka", "maydanoz", "havuc", "brokoli", "kabak", "patlican", "ispanak", "fasulye taze", "taze fasulye", "sebze", "zeytin", "limon", "avokado", "yesillik", "turlu", "mantar", "sogan", "sarimsak", "patates"]),
        (.grains, ["ekmek", "galeta", "yulaf", "bulgur", "pirinc", "pilav", "makarna", "simit", "lavas", "tortilla", "mercimek", "nohut", "kuru fasulye", "barbunya", "borek", "pide", "lahmacun", "kinoa", "cavdar", "gevrek", "manti", "corba"])
    ]

    static func of(_ name: String) -> DietShoppingCategory {
        let folded = " " + DietText.fold(name) + " "
        for (category, words) in keywords where words.contains(where: { folded.contains(" " + $0) || folded.contains($0 + " ") }) {
            return category
        }
        return .other
    }
}

struct DietShoppingItem: Hashable, Identifiable {
    var food: DietFood
    var category: DietShoppingCategory
    /// Toplam gram/ml (bilinmiyorsa nil).
    var grams: Double?
    /// Toplam porsiyon.
    var servings: Double
    /// Adetle alınanlar (yumurta, meyve) için toplam adet.
    var pieces: Double?
    /// Kaç öğünde geçiyor ve hangi günlerde.
    var mealCount: Int
    var dayNumbers: [Int]
    /// Değişim listesinde bunun yerine geçebilecekler.
    var alternatives: [String]

    var id: String { food.key }

    var isLiquid: Bool { food.serving.unit == .ml || food.serving.unit == .waterGlass || food.serving.unit == .teaGlass }

    /// "9 adet", "720 g", "1,2 L", "3 porsiyon"
    var quantityText: String {
        if let pieces, pieces > 0 { return "\(Int(pieces.rounded(.up))) adet" }
        if let grams, grams > 0 {
            if isLiquid {
                return grams >= 1000 ? "\(DietFormat.number(grams / 1000)) L" : "\(Int((grams / 50).rounded(.up) * 50)) ml"
            }
            if grams >= 1000 { return "\(DietFormat.number(grams / 1000, maxFraction: 2)) kg" }
            return "\(Int((grams / 10).rounded(.up) * 10)) g"
        }
        return "\(DietFormat.number(servings)) porsiyon"
    }

    var detailText: String {
        var parts: [String] = []
        if dayNumbers.count <= 3 {
            parts.append(dayNumbers.map { "Gün \($0)" }.joined(separator: ", "))
        } else {
            parts.append("\(mealCount) öğün")
        }
        if !alternatives.isEmpty { parts.append("ya da " + alternatives.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

enum DietShoppingState: Int, Codable {
    case none = 0, bought = 1, atHome = 2

    var next: DietShoppingState {
        switch self {
        case .none: return .bought
        case .bought: return .atHome
        case .atHome: return .none
        }
    }
}

enum DietShopping {
    /// Tarih aralığındaki (dahil) planlanan yiyecekler, reyonlara göre.
    static func items(program: DietProgram, from start: Date, to end: Date, calendar: Calendar = .current) -> [DietShoppingItem] {
        var table: [String: DietShoppingItem] = [:]
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while cursor <= last {
            if let number = program.programDay(on: cursor, calendar: calendar),
               let day = program.plannedDay(on: cursor, calendar: calendar) {
                for meal in day.meals {
                    for item in meal.items {
                        let portion = item.portion
                        var entry = table[portion.food.key] ?? DietShoppingItem(
                            food: portion.food, category: DietShoppingCategory.of(portion.food.name), grams: 0,
                            servings: 0, pieces: nil, mealCount: 0, dayNumbers: [], alternatives: [])
                        if let grams = portion.grams, entry.grams != nil {
                            entry.grams = (entry.grams ?? 0) + grams
                        } else {
                            entry.grams = nil
                        }
                        entry.servings += portion.servings
                        if portion.unit == .piece || (portion.unit == .serving && portion.food.serving.unit == .piece) {
                            let count = portion.unit == .piece ? portion.amount : portion.amount * portion.food.serving.count
                            entry.pieces = (entry.pieces ?? 0) + count
                        }
                        entry.mealCount += 1
                        if !entry.dayNumbers.contains(number) { entry.dayNumbers.append(number) }
                        for alternative in item.alternatives where !entry.alternatives.contains(alternative.food.name) {
                            entry.alternatives.append(alternative.food.name)
                        }
                        table[portion.food.key] = entry
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        // Adetle sayılmayan karışık kullanımda adet bilgisi yanıltıcı olur.
        return table.values.sorted { lhs, rhs in
            lhs.category == rhs.category ? lhs.food.name < rhs.food.name
                : DietShoppingCategory.allCases.firstIndex(of: lhs.category)! < DietShoppingCategory.allCases.firstIndex(of: rhs.category)!
        }
    }

    /// Paylaşılacak düz metin.
    static func text(items: [DietShoppingItem], states: [String: DietShoppingState], title: String) -> String {
        var lines = [title]
        for category in DietShoppingCategory.allCases {
            let group = items.filter { $0.category == category && states[$0.id] != .atHome }
            guard !group.isEmpty else { continue }
            lines.append("")
            lines.append(category.title)
            for item in group {
                let mark = states[item.id] == .bought ? "✓" : "•"
                lines.append("\(mark) \(item.food.name) — \(item.quantityText)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Listede işaretlenenler: program başına cihazda saklanır. "Evde var" bir sonraki listede de çizili gelir.
struct DietShoppingStore {
    let defaults: UserDefaults
    let programID: String

    private var key: String { "diet.shopping.\(programID)" }

    func load() -> [String: DietShoppingState] {
        guard let data = defaults.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return raw.compactMapValues { DietShoppingState(rawValue: $0) }
    }

    func save(_ states: [String: DietShoppingState]) {
        let raw = states.filter { $0.value != .none }.mapValues(\.rawValue)
        if let data = try? JSONEncoder().encode(raw) { defaults.set(data, forKey: key) }
    }

    /// Yeni alışveriş: alınanlar sıfırlanır, "evde var" kalır.
    func resetBought() {
        save(load().filter { $0.value == .atHome })
    }
}
