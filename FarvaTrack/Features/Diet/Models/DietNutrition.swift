import Foundation

// MARK: - Besin değerleri

/// Kalori ve makrolar (bir porsiyon, öğün, gün ya da ortalama için).
struct DietNutrition: Codable, Equatable, Hashable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static let zero = DietNutrition()

    init(calories: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    init(template: FoodTemplate) {
        self.init(calories: template.calories, protein: template.protein, carbs: template.carbs, fat: template.fat)
    }

    static func + (lhs: DietNutrition, rhs: DietNutrition) -> DietNutrition {
        DietNutrition(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
                      carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }

    static func - (lhs: DietNutrition, rhs: DietNutrition) -> DietNutrition {
        DietNutrition(calories: lhs.calories - rhs.calories, protein: lhs.protein - rhs.protein,
                      carbs: lhs.carbs - rhs.carbs, fat: lhs.fat - rhs.fat)
    }

    static func += (lhs: inout DietNutrition, rhs: DietNutrition) { lhs = lhs + rhs }

    func scaled(_ factor: Double) -> DietNutrition {
        DietNutrition(calories: calories * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }

    func grams(of kind: MacroKind) -> Double {
        switch kind {
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        }
    }

    /// Makrolardan gelen enerji.
    var macroEnergy: Double {
        MacroKind.allCases.reduce(0) { $0 + grams(of: $1) * $1.kcalPerGram }
    }

    /// Makronun enerji payı (0…1). Makro yoksa 0.
    func energyShare(of kind: MacroKind) -> Double {
        let total = macroEnergy
        guard total > 0 else { return 0 }
        return grams(of: kind) * kind.kcalPerGram / total
    }

    /// "P %22 · K %46 · Y %29"
    var shareText: String {
        "P %\(Int((energyShare(of: .protein) * 100).rounded())) · K %\(Int((energyShare(of: .carbs) * 100).rounded())) · Y %\(Int((energyShare(of: .fat) * 100).rounded()))"
    }

    /// "P 45 g · K 50 g · Y 13 g"
    var macroText: String {
        "P \(Int(protein.rounded())) g · K \(Int(carbs.rounded())) g · Y \(Int(fat.rounded())) g"
    }

    var kcal: Int { Int(calories.rounded()) }

    static func sum<S: Sequence>(_ values: S) -> DietNutrition where S.Element == DietNutrition {
        values.reduce(.zero, +)
    }
}

// MARK: - Biçimlendirme

enum DietFormat {
    static let locale = Locale(identifier: "tr_TR")

    /// 1,5 · 12 · 0,25
    static func number(_ value: Double, maxFraction: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFraction)).locale(locale))
    }

    /// 1.650
    static func kcal(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(locale))
    }

    static func time(minutes: Int) -> String {
        let clamped = max(0, min(minutes, 24 * 60 - 1))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// "08:30", "8.30", "8" → dakika. Excel saat kesri (0,354…) de kabul edilir.
    static func minutes(fromTime text: String) -> Int? {
        let raw = text.trimmed
        if raw.isEmpty { return nil }
        if let value = Double(raw.replacingOccurrences(of: ",", with: ".")) {
            // Excel saat hücresi: günün kesri (0,354… = 08:30).
            if value > 0, value < 1 { return Int((value * 24 * 60).rounded()) }
            if value >= 0, value < 24, value == value.rounded() { return Int(value) * 60 }
        }
        let parts = raw.replacingOccurrences(of: ".", with: ":").split(separator: ":").map { String($0) }
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1].prefix(2)),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// "1,5" / "1.5" / "½" → sayı.
    static func amount(from text: String) -> Double? {
        let clean = text.trimmed
            .replacingOccurrences(of: "½", with: "0.5")
            .replacingOccurrences(of: "¼", with: "0.25")
            .replacingOccurrences(of: "¾", with: "0.75")
            .replacingOccurrences(of: ",", with: ".")
        if let value = Double(clean) { return value }
        // "1/2"
        let parts = clean.split(separator: "/")
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { return a / b }
        return nil
    }

    static func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Bugün" }
        if Calendar.current.isDateInYesterday(date) { return "Dün" }
        if Calendar.current.isDateInTomorrow(date) { return "Yarın" }
        return date.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(locale))
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(locale))
    }
}

// MARK: - Türkçe metin eşleştirme

enum DietText {
    private static let turkish = Locale(identifier: "tr_TR")

    /// Küçük harf, aksansız, ı/i farksız; fazla boşluklar tek boşluk.
    static func fold(_ text: String) -> String {
        text
            .lowercased(with: turkish)
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Parantezsiz ad: "Tavuk göğsü (ızgara)" → "tavuk gogsu".
    static func baseName(_ text: String) -> String {
        let base = text.split(separator: "(").first.map(String.init) ?? text
        return fold(base)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
