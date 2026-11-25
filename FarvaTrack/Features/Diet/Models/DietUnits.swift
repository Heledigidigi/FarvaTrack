import Foundation

// MARK: - Ölçü birimleri

/// Programda kullanılan ölçüler. Gram karşılıkları genel ortalamadır; bazı yiyeceklerde
/// `DietUnitTable.overrides` daha doğru değer verir.
enum DietUnit: String, Codable, CaseIterable, Identifiable, Hashable {
    case gram, ml, serving, piece, slice, tablespoon, dessertSpoon, teaspoon, waterGlass, teaGlass, bowl, handful, pack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gram: return "g"
        case .ml: return "ml"
        case .serving: return "porsiyon"
        case .piece: return "adet"
        case .slice: return "dilim"
        case .tablespoon: return "yemek kaşığı"
        case .dessertSpoon: return "tatlı kaşığı"
        case .teaspoon: return "çay kaşığı"
        case .waterGlass: return "su bardağı"
        case .teaGlass: return "çay bardağı"
        case .bowl: return "kase"
        case .handful: return "avuç"
        case .pack: return "paket"
        }
    }

    var shortTitle: String {
        switch self {
        case .tablespoon: return "yk"
        case .dessertSpoon: return "tk"
        case .teaspoon: return "çk"
        case .waterGlass: return "su b."
        case .teaGlass: return "çay b."
        default: return title
        }
    }

    /// Genel gram karşılığı (bir birim için). Porsiyon, adet ve paket yiyeceğe bağlıdır.
    var defaultGrams: Double? {
        switch self {
        case .gram, .ml: return 1
        case .tablespoon: return 15
        case .dessertSpoon: return 7
        case .teaspoon: return 3
        case .waterGlass: return 200
        case .teaGlass: return 100
        case .bowl: return 150
        case .handful: return 30
        case .slice: return 30
        case .serving, .piece, .pack: return nil
        }
    }

    var isMass: Bool { self == .gram || self == .ml }

    /// Metindeki birim ("yk", "Yemek Kaşığı", "gr", "adet"…).
    static func parse(_ text: String) -> DietUnit? {
        let key = DietText.fold(text).replacingOccurrences(of: ".", with: "")
        if key.isEmpty { return nil }
        if let exact = aliases[key] { return exact }
        // "yemek kasigi" + çoğul/ek: "yemek kasiklari"
        for (alias, unit) in aliases where alias.count >= 4 && key.hasPrefix(alias) { return unit }
        return nil
    }

    private static let aliases: [String: DietUnit] = [
        "g": .gram, "gr": .gram, "gram": .gram, "grm": .gram,
        "ml": .ml, "mililitre": .ml, "cc": .ml,
        "porsiyon": .serving, "pors": .serving, "servis": .serving,
        "adet": .piece, "ad": .piece, "tane": .piece, "orta": .piece, "buyuk": .piece, "kucuk": .piece,
        "dilim": .slice,
        "yk": .tablespoon, "yemek kasigi": .tablespoon, "y kasigi": .tablespoon, "ykasigi": .tablespoon, "yemek k": .tablespoon,
        "tk": .dessertSpoon, "tatli kasigi": .dessertSpoon, "tatli k": .dessertSpoon,
        "ck": .teaspoon, "cay kasigi": .teaspoon, "cay k": .teaspoon,
        "su bardagi": .waterGlass, "bardak": .waterGlass, "sb": .waterGlass, "su b": .waterGlass, "su bardak": .waterGlass,
        "cay bardagi": .teaGlass, "cb": .teaGlass, "cay b": .teaGlass,
        "kase": .bowl, "kâse": .bowl, "tabak": .bowl,
        "avuc": .handful, "avuç": .handful,
        "paket": .pack, "kutu": .pack
    ]
}

// MARK: - Porsiyon bilgisi

/// Kütüphane etiketinden çıkarılan porsiyon: "5 adet (20 g)" → 5 adet, 20 g.
struct DietServing: Equatable, Hashable {
    var count: Double
    var unit: DietUnit?
    var grams: Double?

    static func parse(_ label: String) -> DietServing {
        var grams: Double?
        if let open = label.firstIndex(of: "("), let close = label.lastIndex(of: ")"), open < close {
            let inside = String(label[label.index(after: open)..<close])
            let tokens = inside.split(separator: " ").map(String.init)
            if let first = tokens.first, let value = DietFormat.amount(from: first),
               tokens.count >= 2, let unit = DietUnit.parse(tokens[1]), unit.isMass {
                grams = value
            }
        }
        let head = (label.split(separator: "(").first.map(String.init) ?? label).trimmed
        let parts = head.split(separator: " ", maxSplits: 1).map(String.init)
        var count = 1.0
        var unit: DietUnit?
        if let first = parts.first, let value = DietFormat.amount(from: first) {
            count = value
            if parts.count > 1 { unit = DietUnit.parse(parts[1]) }
        } else {
            unit = DietUnit.parse(head)
        }
        if grams == nil, let unit, unit.isMass { grams = count }
        return DietServing(count: max(count, 0.01), unit: unit, grams: grams)
    }
}

// MARK: - Yiyecek

/// Programda saklanan yiyecek: kütüphanedeki değerlerin kopyası (kütüphane değişse de program bozulmaz).
struct DietFood: Codable, Hashable, Identifiable {
    var key: String
    var name: String
    var servingLabel: String
    /// 1 porsiyonun değerleri.
    var perServing: DietNutrition

    var id: String { key }

    init(key: String, name: String, servingLabel: String, perServing: DietNutrition) {
        self.key = key
        self.name = name
        self.servingLabel = servingLabel
        self.perServing = perServing
    }

    init(template: FoodTemplate) {
        self.init(key: template.key, name: template.name, servingLabel: template.servingLabel,
                  perServing: DietNutrition(template: template))
    }

    var template: FoodTemplate {
        FoodTemplate(key: key, name: name, servingLabel: servingLabel, calories: perServing.calories,
                     protein: perServing.protein, carbs: perServing.carbs, fat: perServing.fat)
    }

    var serving: DietServing { DietServing.parse(servingLabel) }

    /// Kütüphanede olmayan, değerleri bilinmeyen yiyecek (içe aktarmada atlanmadan önce).
    static func placeholder(name: String) -> DietFood {
        DietFood(key: "unknown.\(DietText.fold(name).replacingOccurrences(of: " ", with: "-"))", name: name,
                 servingLabel: "1 porsiyon", perServing: .zero)
    }

    var isPlaceholder: Bool { key.hasPrefix("unknown.") }

    /// Yiyeceğe uygun ölçüler (seçicide önce bunlar).
    var suggestedUnits: [DietUnit] {
        var units: [DietUnit] = []
        if let unit = serving.unit, !unit.isMass { units.append(unit) }
        for unit in DietUnitTable.overrides[key]?.keys.sorted(by: { $0.rawValue < $1.rawValue }) ?? [] where !units.contains(unit) {
            units.append(unit)
        }
        for unit in [DietUnit.serving, serving.unit == .ml ? .ml : .gram] where !units.contains(unit) {
            units.append(unit)
        }
        return units
    }
}

// MARK: - Dönüşüm tablosu

enum DietUnitTable {
    /// Yiyeceğe özgü gram karşılıkları (bir birim için).
    static let overrides: [String: [DietUnit: Double]] = [
        "preset.rice-pilaf": [.tablespoon: 15, .bowl: 150],
        "preset.bulgur-pilaf": [.tablespoon: 15, .bowl: 150],
        "preset.pasta": [.tablespoon: 15, .bowl: 150],
        "preset.oats": [.tablespoon: 8, .waterGlass: 90],
        "preset.honey": [.tablespoon: 20, .teaspoon: 7],
        "preset.jam": [.tablespoon: 20, .teaspoon: 7],
        "preset.butter": [.tablespoon: 14, .teaspoon: 5],
        "preset.yogurt": [.tablespoon: 15, .waterGlass: 200],
        "preset.milk": [.teaGlass: 100],
        "preset.ayran": [.teaGlass: 100],
        "preset.white-cheese": [.tablespoon: 15, .handful: 30],
        "preset.black-olive": [.piece: 4],
        "preset.boiled-egg": [.piece: 50]
    ]

    /// Bir birimin gram karşılığı.
    static func grams(per unit: DietUnit, for food: DietFood) -> Double? {
        if let value = overrides[food.key]?[unit] { return value }
        let serving = food.serving
        switch unit {
        case .gram, .ml:
            return 1
        case .serving:
            return serving.grams
        default:
            if unit == serving.unit, let grams = serving.grams { return grams / serving.count }
            if unit == .piece, serving.unit == nil, let grams = serving.grams { return grams }
            return unit.defaultGrams
        }
    }

    /// Miktarın kaç porsiyon ettiği (besin değerleri porsiyon başına).
    static func servings(amount: Double, unit: DietUnit, food: DietFood) -> Double {
        let serving = food.serving
        if unit == .serving { return amount }
        if unit == serving.unit, overrides[food.key]?[unit] == nil { return amount / serving.count }
        if let servingGrams = serving.grams, servingGrams > 0, let perUnit = grams(per: unit, for: food) {
            return amount * perUnit / servingGrams
        }
        // Gram karşılığı bilinmiyorsa 1 birim = 1 porsiyon varsayılır.
        return amount
    }

    static func grams(amount: Double, unit: DietUnit, food: DietFood) -> Double? {
        if unit == .serving, let grams = food.serving.grams { return grams * amount }
        return grams(per: unit, for: food).map { $0 * amount }
    }

    /// Kalorisi aynı kalacak miktar (yeni yiyeceğin önerilen biriminde, yarım birime yuvarlı).
    static func equalCalorieAmount(for calories: Double, food: DietFood) -> (amount: Double, unit: DietUnit) {
        let unit = food.suggestedUnits.first ?? .serving
        let perUnit = food.perServing.calories * servings(amount: 1, unit: unit, food: food)
        guard perUnit > 0 else { return (1, unit) }
        let raw = calories / perUnit
        let step: Double = unit.isMass ? 5 : 0.5
        return (max(step, (raw / step).rounded() * step), unit)
    }
}

// MARK: - Porsiyon (yiyecek + miktar)

struct DietPortion: Codable, Hashable {
    var food: DietFood
    var amount: Double
    var unit: DietUnit

    init(food: DietFood, amount: Double, unit: DietUnit) {
        self.food = food
        self.amount = amount
        self.unit = unit
    }

    /// Kütüphanedeki tek porsiyon.
    init(food: DietFood) {
        let serving = food.serving
        if let unit = serving.unit, !unit.isMass {
            self.init(food: food, amount: serving.count, unit: unit)
        } else if let grams = serving.grams {
            self.init(food: food, amount: grams, unit: serving.unit == .ml ? .ml : .gram)
        } else {
            self.init(food: food, amount: 1, unit: .serving)
        }
    }

    var servings: Double { DietUnitTable.servings(amount: amount, unit: unit, food: food) }
    var nutrition: DietNutrition { food.perServing.scaled(servings) }
    var grams: Double? { DietUnitTable.grams(amount: amount, unit: unit, food: food) }

    /// "5 yemek kaşığı"
    var amountText: String { "\(DietFormat.number(amount, maxFraction: 2)) \(unit.title)" }
    /// "5 yk"
    var shortAmountText: String { "\(DietFormat.number(amount, maxFraction: 2)) \(unit.shortTitle)" }

    /// "≈ 75 g" (gram/ml dışındaki ölçülerde).
    var gramsHint: String? {
        guard !unit.isMass, let grams else { return nil }
        let rounded = grams >= 20 ? (grams / 5).rounded() * 5 : grams.rounded()
        return "≈ \(DietFormat.number(rounded)) \(food.serving.unit == .ml || unit == .waterGlass || unit == .teaGlass ? "ml" : "g")"
    }

    /// "Bulgur pilavı 5 yk"
    var label: String { "\(food.name) \(shortAmountText)" }
}
