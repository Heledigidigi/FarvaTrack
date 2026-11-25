import Foundation

// MARK: - Excel şablonu ve içe aktarma

enum DietExcelColumn: String, CaseIterable {
    case day = "Gün"
    case meal = "Öğün"
    case time = "Saat"
    case food = "Yiyecek"
    case amount = "Miktar"
    case unit = "Birim"
    case alternatives = "Değişim"

    static func detect(_ header: String) -> DietExcelColumn? {
        let key = DietText.fold(header)
        switch key {
        case "gun", "gun no", "day": return .day
        case "ogun", "meal": return .meal
        case "saat", "time": return .time
        case "yiyecek", "besin", "food", "icerik": return .food
        case "miktar", "adet", "amount": return .amount
        case "birim", "olcu", "unit": return .unit
        case "degisim", "degisimler", "alternatif", "ya da", "yerine": return .alternatives
        default: return nil
        }
    }
}

/// İçe aktarma sırasında elde edilen ham satır.
struct DietImportRow: Hashable, Identifiable {
    var id: Int { line }
    var line: Int
    var day: Int
    var mealName: String
    var minutes: Int?
    var foodName: String
    var amount: Double?
    var unit: DietUnit?
    var unitText: String
    /// "Pirinç pilavı 4 yk; Ekmek 2 dilim" → (ad, miktar, birim)
    var alternatives: [(name: String, amount: Double, unit: DietUnit)]

    static func == (lhs: DietImportRow, rhs: DietImportRow) -> Bool { lhs.line == rhs.line }
    func hash(into hasher: inout Hasher) { hasher.combine(line) }
}

/// Çözülmesi gereken sorun: kütüphanede olmayan yiyecek ya da eksik bilgi.
struct DietImportIssue: Hashable, Identifiable {
    enum Kind: Hashable {
        case unknownFood(name: String)
        case missingAmount
        case unknownUnit(String)
    }

    var kind: Kind
    /// Etkilenen satırlar.
    var lines: [Int]
    var days: [Int]
    var mealNames: [String]
    var sampleAmount: String

    var id: String {
        switch kind {
        case .unknownFood(let name): return "food|\(DietText.fold(name))"
        case .missingAmount: return "amount|\(lines.first ?? 0)"
        case .unknownUnit(let unit): return "unit|\(unit)|\(lines.first ?? 0)"
        }
    }

    var title: String {
        switch kind {
        case .unknownFood(let name): return "\"\(name)\""
        case .missingAmount: return "Satır \(lines.first ?? 0)"
        case .unknownUnit(let unit): return "\"\(unit)\" birimi"
        }
    }

    var detail: String {
        let dayText = days.count <= 4 ? "Gün " + days.map(String.init).joined(separator: ", ") : "\(days.count) gün"
        return "\(dayText) · \(mealNames.prefix(2).joined(separator: ", "))\(sampleAmount.isEmpty ? "" : " · \(sampleAmount)")"
    }
}

/// Sorunun nasıl çözüldüğü.
enum DietImportResolution: Hashable {
    case matched(DietFood)
    case skip
    case amount(Double, DietUnit)
}

struct DietImportDraft {
    var rows: [DietImportRow]
    /// Katlanmış ad → eşleşen yiyecek.
    var matches: [String: DietFood]
    var issues: [DietImportIssue]
    var resolutions: [String: DietImportResolution] = [:]

    var dayCount: Int { rows.map(\.day).max() ?? 0 }
    var mealCount: Int { Set(rows.map { "\($0.day)|\(DietText.fold($0.mealName))" }).count }
    var matchedRowCount: Int { rows.filter { matches[DietText.fold($0.foodName)] != nil && $0.amount != nil && $0.unit != nil }.count }

    var unknownFoodIssues: [DietImportIssue] { issues.filter { if case .unknownFood = $0.kind { return true }; return false } }
    var rowIssues: [DietImportIssue] { issues.filter { if case .unknownFood = $0.kind { return false }; return true } }
    var unresolved: [DietImportIssue] { issues.filter { resolutions[$0.id] == nil } }

    /// Çözümler uygulanmış plan. Atlanan ya da hâlâ çözülmemiş satırlar plana girmez.
    func makePlan() -> DietPlan {
        guard dayCount > 0 else { return DietPlan() }
        var days: [DietDay] = (0..<dayCount).map { _ in DietDay() }
        var mealIDs: [String: String] = [:]
        for row in rows {
            guard let food = food(for: row.foodName) else { continue }
            var amount = row.amount
            var unit = row.unit
            if amount == nil || unit == nil {
                if let issue = issues.first(where: { $0.lines.contains(row.line) && $0.kind != .unknownFood(name: row.foodName) }),
                   case .amount(let fixed, let fixedUnit)? = resolutions[issue.id] {
                    amount = fixed
                    unit = fixedUnit
                }
            }
            guard let amount, amount > 0 else { continue }
            let portion = DietPortion(food: food, amount: amount, unit: unit ?? .serving)
            let alternatives = row.alternatives.compactMap { alt -> DietPortion? in
                guard let altFood = self.food(for: alt.name) else { return nil }
                return DietPortion(food: altFood, amount: alt.amount, unit: alt.unit)
            }
            let dayIndex = row.day - 1
            guard days.indices.contains(dayIndex) else { continue }
            let mealKey = DietText.fold(row.mealName)
            // Aynı ad, aynı kimlik: günler arasında öğün kimliği ortak olur (Gün 1 kahvaltı = Gün 2 kahvaltı).
            let mealID = mealIDs[mealKey] ?? UUID().uuidString
            mealIDs[mealKey] = mealID
            if let index = days[dayIndex].meals.firstIndex(where: { DietText.fold($0.name) == mealKey }) {
                days[dayIndex].meals[index].items.append(DietItem(portion: portion, alternatives: alternatives))
                if let minutes = row.minutes, days[dayIndex].meals[index].minutes == DietImport.defaultMinutes(for: row.mealName) {
                    days[dayIndex].meals[index].minutes = minutes
                }
            } else {
                days[dayIndex].meals.append(DietMeal(id: mealID, name: row.mealName.trimmed,
                                                     minutes: row.minutes ?? DietImport.defaultMinutes(for: row.mealName),
                                                     items: [DietItem(portion: portion, alternatives: alternatives)]))
            }
        }
        for index in days.indices { days[index].meals.sort { $0.minutes < $1.minutes } }
        return DietPlan(days: days)
    }

    func food(for name: String) -> DietFood? {
        let key = DietText.fold(name)
        if let issue = issues.first(where: { $0.kind == .unknownFood(name: name) || $0.id == "food|\(key)" }) {
            if case .matched(let food)? = resolutions[issue.id] { return food }
            return nil
        }
        return matches[key]
    }

    /// Takvimde gösterilecek: bu program gününde çözülmemiş sorun var mı.
    func hasOpenIssue(day: Int) -> Bool {
        unresolved.contains { $0.days.contains(day) }
    }

    func openIssueText(day: Int) -> String? {
        guard let issue = unresolved.first(where: { $0.days.contains(day) }) else { return nil }
        switch issue.kind {
        case .unknownFood(let name): return "\"\(name)\" kütüphanede yok"
        case .missingAmount: return "Satır \(issue.lines.first ?? 0): miktar boş"
        case .unknownUnit(let unit): return "\"\(unit)\" birimi tanınmadı"
        }
    }
}

enum DietImport {
    /// Şablonun ilk sayfası (örnek satırlarla) ve ikinci sayfa (yiyecekler ve birimler).
    static func templateData(foods: [FoodTemplate]) -> Data {
        let header = DietExcelColumn.allCases.map(\.rawValue)
        let sample: [[String]] = [
            ["1", "Kahvaltı", "08:00", "Haşlanmış yumurta", "2", "adet", ""],
            ["1", "Kahvaltı", "08:00", "Tam buğday ekmeği", "1", "dilim", "Yulaf ezmesi (kuru) 3 yk"],
            ["1", "Kahvaltı", "08:00", "Beyaz peynir", "1", "dilim", "Lor 3 yk"],
            ["1", "Ara öğün", "11:00", "Elma", "1", "adet", "Armut 1 adet"],
            ["1", "Öğle", "13:30", "Tavuk göğsü (ızgara)", "120", "g", ""],
            ["1", "Öğle", "13:30", "Bulgur pilavı", "5", "yemek kaşığı", "Pirinç pilavı 4 yk"],
            ["1", "Öğle", "13:30", "Yoğurt (tam yağlı)", "1", "kase", ""],
            ["1", "Akşam", "19:30", "Mercimek çorbası", "1", "kase", ""],
            ["2", "Kahvaltı", "08:00", "Omlet (2 yumurta)", "1", "porsiyon", ""]
        ]
        var units: [[String]] = []
        for unit in DietUnit.allCases {
            let grams: String = unit.defaultGrams.map { DietFormat.number($0) + " g" } ?? "yiyeceğe göre"
            units.append([unit.title, unit.shortTitle, grams])
        }
        var foodRows: [[String]] = []
        for food in foods { foodRows.append([food.name, food.servingLabel, DietFormat.kcal(food.calories)]) }
        var reference: [[String]] = [["Yiyecek", "1 porsiyon", "kcal", "", "Birim", "Kısa", "Yaklaşık"]]
        let empty = ["", "", ""]
        for i in 0..<max(foodRows.count, units.count) {
            var row: [String] = i < foodRows.count ? foodRows[i] : empty
            row.append("")
            row.append(contentsOf: i < units.count ? units[i] : empty)
            reference.append(row)
        }
        return XLSX.write(sheets: [
            XLSX.Sheet(name: "Program", rows: [header] + sample),
            XLSX.Sheet(name: "Yiyecekler ve birimler", rows: reference)
        ])
    }

    /// Programı Excel'e yazar (aynı şablon biçiminde, düzenleyip geri yüklemek için).
    static func exportData(plan: DietPlan) -> Data {
        var rows = [DietExcelColumn.allCases.map(\.rawValue)]
        for (index, day) in plan.days.enumerated() {
            for meal in day.sortedMeals {
                for item in meal.items {
                    rows.append([String(index + 1), meal.name, meal.timeText, item.portion.food.name,
                                 DietFormat.number(item.portion.amount, maxFraction: 2), item.portion.unit.title,
                                 item.alternatives.map { "\($0.food.name) \(DietFormat.number($0.amount, maxFraction: 2)) \($0.unit.shortTitle)" }.joined(separator: "; ")])
                }
            }
        }
        return XLSX.write(sheets: [XLSX.Sheet(name: "Program", rows: rows)])
    }

    /// Dosya içeriğini (xlsx ya da csv) satırlara çevirir.
    static func rows(from data: Data, fileName: String) throws -> [[String]] {
        if fileName.lowercased().hasSuffix(".csv") || fileName.lowercased().hasSuffix(".txt") { return try XLSX.readCSV(data) }
        do { return try XLSX.read(data) } catch {
            // Uzantısı yanlış bir CSV olabilir.
            if let rows = try? XLSX.readCSV(data), rows.first?.count ?? 0 >= 4 { return rows }
            throw error
        }
    }

    /// Satırları ayrıştırır ve yiyecekleri kütüphaneyle eşleştirir.
    static func draft(from table: [[String]], foods: [FoodTemplate]) -> DietImportDraft {
        guard let headerIndex = table.firstIndex(where: { row in row.compactMap(DietExcelColumn.detect).count >= 3 }) else {
            return DietImportDraft(rows: [], matches: [:], issues: [])
        }
        var columns: [DietExcelColumn: Int] = [:]
        for (index, header) in table[headerIndex].enumerated() {
            if let column = DietExcelColumn.detect(header), columns[column] == nil { columns[column] = index }
        }
        func cell(_ row: [String], _ column: DietExcelColumn) -> String {
            guard let index = columns[column], row.indices.contains(index) else { return "" }
            return row[index].trimmed
        }

        var rows: [DietImportRow] = []
        var lastDay = 1
        var lastMeal = "Öğün"
        var lastMinutes: Int?
        for (offset, raw) in table.enumerated() where offset > headerIndex {
            let foodName = cell(raw, .food)
            if foodName.isEmpty { continue }
            let dayText = cell(raw, .day)
            let day = Int(DietFormat.amount(from: dayText.filter { $0.isNumber || $0 == "," || $0 == "." }) ?? Double(lastDay))
            let mealText = cell(raw, .meal)
            let meal = mealText.isEmpty ? lastMeal : mealText
            let minutes = DietFormat.minutes(fromTime: cell(raw, .time)) ?? (meal == lastMeal ? lastMinutes : nil)
            let unitText = cell(raw, .unit)
            var amount = DietFormat.amount(from: cell(raw, .amount))
            var unit = unitText.isEmpty ? nil : DietUnit.parse(unitText)
            // "5 yk" tek hücrede yazıldıysa.
            if amount == nil, unit == nil, let split = splitAmount(cell(raw, .amount)) { amount = split.0; unit = split.1 }
            if unit == nil, unitText.isEmpty, amount != nil { unit = .serving }
            rows.append(DietImportRow(line: offset + 1, day: max(1, day), mealName: meal, minutes: minutes, foodName: foodName,
                                      amount: amount, unit: unit, unitText: unitText,
                                      alternatives: parseAlternatives(cell(raw, .alternatives))))
            lastDay = max(1, day)
            lastMeal = meal
            lastMinutes = minutes
        }

        var matches: [String: DietFood] = [:]
        var unknown: [String: (name: String, lines: [Int], days: [Int], meals: [String], amount: String)] = [:]
        var issues: [DietImportIssue] = []
        let index = FoodIndex(foods: foods)
        func register(_ name: String, row: DietImportRow, amount: String) {
            let key = DietText.fold(name)
            if matches[key] != nil { return }
            if let food = index.match(name) {
                matches[key] = DietFood(template: food)
            } else {
                var entry = unknown[key] ?? (name: name, lines: [Int](), days: [Int](), meals: [String](), amount: amount)
                entry.lines.append(row.line)
                if !entry.days.contains(row.day) { entry.days.append(row.day) }
                if !entry.meals.contains(row.mealName) { entry.meals.append(row.mealName) }
                unknown[key] = entry
            }
        }
        for row in rows {
            let amountText = [row.amount.map { DietFormat.number($0, maxFraction: 2) }, row.unit?.title ?? (row.unitText.isEmpty ? nil : row.unitText)]
                .compactMap { $0 }.joined(separator: " ")
            register(row.foodName, row: row, amount: amountText)
            for alt in row.alternatives { register(alt.name, row: row, amount: "") }
            if row.amount == nil {
                issues.append(DietImportIssue(kind: .missingAmount, lines: [row.line], days: [row.day], mealNames: [row.mealName],
                                              sampleAmount: "\"\(row.foodName)\" miktarı boş"))
            } else if row.unit == nil {
                issues.append(DietImportIssue(kind: .unknownUnit(row.unitText), lines: [row.line], days: [row.day], mealNames: [row.mealName],
                                              sampleAmount: row.foodName))
            }
        }
        let foodIssues = unknown.values.sorted { ($0.lines.first ?? 0) < ($1.lines.first ?? 0) }.map {
            DietImportIssue(kind: .unknownFood(name: $0.name), lines: $0.lines, days: $0.days.sorted(), mealNames: $0.meals, sampleAmount: $0.amount)
        }
        return DietImportDraft(rows: rows, matches: matches, issues: foodIssues + issues)
    }

    static func defaultMinutes(for mealName: String) -> Int {
        let key = DietText.fold(mealName)
        if key.contains("kahvalti") { return 8 * 60 }
        if key.contains("ogle") { return 13 * 60 }
        if key.contains("ikindi") { return 16 * 60 + 30 }
        if key.contains("aksam") { return 19 * 60 + 30 }
        if key.contains("gece") || key.contains("yatmadan") { return 22 * 60 }
        if key.contains("ara") { return 11 * 60 }
        return 12 * 60
    }

    /// "4 yk" / "2 dilim" → (4, .tablespoon)
    static func splitAmount(_ text: String) -> (Double, DietUnit)? {
        let tokens = text.split(separator: " ").map(String.init)
        guard tokens.count >= 2, let amount = DietFormat.amount(from: tokens[0]),
              let unit = DietUnit.parse(tokens.dropFirst().joined(separator: " ")) else { return nil }
        return (amount, unit)
    }

    /// "Pirinç pilavı 4 yk; Tam buğday ekmeği 2 dilim" (ayraç: ; / ya da "veya").
    static func parseAlternatives(_ text: String) -> [(name: String, amount: Double, unit: DietUnit)] {
        let normalized = text.replacingOccurrences(of: " veya ", with: ";").replacingOccurrences(of: " ya da ", with: ";")
            .replacingOccurrences(of: "/", with: ";").replacingOccurrences(of: "\n", with: ";")
        return normalized.split(separator: ";").compactMap { part -> (name: String, amount: Double, unit: DietUnit)? in
            let tokens = part.split(separator: " ").map(String.init)
            guard !tokens.isEmpty else { return nil }
            // Sondan miktar + birim ara: "... 4 yk", "... 1 su bardağı", "... 2 adet"
            if let split = tokens.indices.reversed().first(where: { $0 >= 1 && DietFormat.amount(from: tokens[$0]) != nil }),
               let amount = DietFormat.amount(from: tokens[split]) {
                let unitText = tokens[(split + 1)...].joined(separator: " ")
                let name = tokens[..<split].joined(separator: " ").trimmed
                if !name.isEmpty {
                    let unit = unitText.isEmpty ? DietUnit.serving : (DietUnit.parse(unitText) ?? .serving)
                    return (name: name, amount: amount, unit: unit)
                }
            }
            let name = String(part).trimmed
            return name.isEmpty ? nil : (name: name, amount: 1, unit: DietUnit.serving)
        }
    }
}

// MARK: - Yiyecek eşleştirme

struct FoodIndex {
    let foods: [FoodTemplate]
    private let exact: [String: FoodTemplate]
    private let base: [String: FoodTemplate]

    init(foods: [FoodTemplate]) {
        self.foods = foods
        var exact: [String: FoodTemplate] = [:]
        var base: [String: FoodTemplate] = [:]
        for food in foods {
            let folded = DietText.fold(food.name)
            if exact[folded] == nil { exact[folded] = food }
            let b = DietText.baseName(food.name)
            if base[b] == nil { base[b] = food }
        }
        self.exact = exact
        self.base = base
    }

    func match(_ name: String) -> FoodTemplate? {
        let folded = DietText.fold(name)
        if let food = exact[folded] ?? base[folded] ?? base[DietText.baseName(name)] { return food }
        // Hafif yazım farkları: 6+ harfte 2, 4–5 harfte 1 harf.
        let limit = folded.count >= 6 ? 2 : (folded.count >= 4 ? 1 : 0)
        guard limit > 0 else { return nil }
        var best: (FoodTemplate, Int)?
        for (key, food) in base {
            let distance = DietText.levenshtein(folded, key)
            if distance <= limit, distance < (best?.1 ?? Int.max) { best = (food, distance) }
        }
        return best?.0
    }

    /// Arama (içeren + benzer), seçici için.
    func search(_ query: String, limit: Int = 30) -> [FoodTemplate] {
        let folded = DietText.fold(query)
        guard !folded.isEmpty else { return Array(foods.prefix(limit)) }
        let contains = foods.filter { DietText.fold($0.name).contains(folded) }
        if !contains.isEmpty { return Array(contains.prefix(limit)) }
        return foods.filter { DietText.levenshtein(DietText.baseName($0.name), folded) <= 2 }.prefix(limit).map { $0 }
    }
}
