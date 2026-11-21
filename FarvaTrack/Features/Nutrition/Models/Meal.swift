import SwiftUI
import SwiftData

// MARK: - Öğün ve makro türleri
enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return "Kahvaltı"
        case .lunch: return "Öğle Yemeği"
        case .dinner: return "Akşam Yemeği"
        case .snack: return "Atıştırmalık"
        }
    }

    var shortTitle: String {
        switch self {
        case .breakfast: return "Kahvaltı"
        case .lunch: return "Öğle"
        case .dinner: return "Akşam"
        case .snack: return "Ara öğün"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .snack: return "cup.and.saucer.fill"
        }
    }

    var tint: Color {
        switch self {
        case .breakfast: return Color.ftStats
        case .lunch: return Color.ftCalories
        case .dinner: return Color.ftSleep
        case .snack: return Color.ftWeight
        }
    }

    /// Geçmiş bir güne kayıt eklenirken kullanılan varsayılan saat.
    var defaultHour: Int {
        switch self {
        case .breakfast: return 8
        case .lunch: return 13
        case .dinner: return 19
        case .snack: return 16
        }
    }

    static func suggested(at date: Date = .now) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<17: return .snack
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

enum MacroKind: CaseIterable, Identifiable {
    case protein, carbs, fat
    var id: Self { self }

    var title: String {
        switch self {
        case .protein: return "Protein"
        case .carbs: return "Karbonhidrat"
        case .fat: return "Yağ"
        }
    }

    var color: Color {
        switch self {
        case .protein: return Color.ftExercise
        case .carbs: return Color.ftStats
        case .fat: return Color.ftWeight
        }
    }

    var kcalPerGram: Double { self == .fat ? 9 : 4 }
}

// MARK: - Yiyecek şablonu (kütüphane, özel ve favori için ortak)
struct FoodTemplate: Identifiable, Hashable {
    /// Hazır: "preset.menemen", özel: "custom.<uuid>"
    let key: String
    let name: String
    let servingLabel: String
    /// Besin değerleri 1 porsiyon içindir.
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    var id: String { key }
    var isCustom: Bool { key.hasPrefix("custom.") }

    func grams(of kind: MacroKind) -> Double {
        switch kind {
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        }
    }
}

// MARK: - Günlük toplamlar
struct NutritionTotals: Equatable {
    var calories = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0

    init() {}

    init(entries: [MealEntry]) {
        for entry in entries {
            calories += entry.calories
            protein += entry.protein
            carbs += entry.carbs
            fat += entry.fat
        }
    }

    func grams(of kind: MacroKind) -> Double {
        switch kind {
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        }
    }

    /// Makrolardan gelen enerji (pasta grafik bununla çizilir).
    var macroEnergy: Double {
        MacroKind.allCases.reduce(0) { $0 + grams(of: $1) * $1.kcalPerGram }
    }
}

// MARK: - SwiftData modelleri
@Model
final class MealEntry {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var date: Date
    var mealTypeRaw: String
    var foodKey: String
    var name: String
    var servingLabel: String
    var quantity: Double
    var caloriesPerServing: Double
    var proteinPerServing: Double
    var carbsPerServing: Double
    var fatPerServing: Double
    var needsSync: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), ownerID: String, date: Date, mealType: MealType, template: FoodTemplate, quantity: Double) {
        self.id = id
        self.ownerID = ownerID
        self.date = date
        self.mealTypeRaw = mealType.rawValue
        self.foodKey = template.key
        self.name = template.name
        self.servingLabel = template.servingLabel
        self.quantity = quantity
        self.caloriesPerServing = template.calories
        self.proteinPerServing = template.protein
        self.carbsPerServing = template.carbs
        self.fatPerServing = template.fat
        self.needsSync = true
        self.createdAt = .now
        self.updatedAt = .now
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var calories: Double { caloriesPerServing * quantity }
    var protein: Double { proteinPerServing * quantity }
    var carbs: Double { carbsPerServing * quantity }
    var fat: Double { fatPerServing * quantity }

    var template: FoodTemplate {
        FoodTemplate(
            key: foodKey, name: name, servingLabel: servingLabel,
            calories: caloriesPerServing, protein: proteinPerServing,
            carbs: carbsPerServing, fat: fatPerServing
        )
    }

    func apply(_ dto: MealDTO) {
        date = dto.date
        mealTypeRaw = dto.mealType
        quantity = dto.quantity
        name = dto.name
        servingLabel = dto.servingLabel
        caloriesPerServing = dto.caloriesPerServing
        proteinPerServing = dto.proteinPerServing
        carbsPerServing = dto.carbsPerServing
        fatPerServing = dto.fatPerServing
        updatedAt = dto.updatedAt
        needsSync = false
    }

    static func make(from dto: MealDTO, ownerID: String) -> MealEntry {
        let entry = MealEntry(
            id: UUID(uuidString: dto.id) ?? UUID(),
            ownerID: ownerID,
            date: dto.date,
            mealType: MealType(rawValue: dto.mealType) ?? .snack,
            template: FoodTemplate(
                key: dto.foodKey, name: dto.name, servingLabel: dto.servingLabel,
                calories: dto.caloriesPerServing, protein: dto.proteinPerServing,
                carbs: dto.carbsPerServing, fat: dto.fatPerServing
            ),
            quantity: dto.quantity
        )
        entry.createdAt = dto.createdAt
        entry.updatedAt = dto.updatedAt
        entry.needsSync = false
        return entry
    }
}

@Model
final class CustomFood {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var name: String
    var servingLabel: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var createdAt: Date

    init(ownerID: String, name: String, servingLabel: String, calories: Double, protein: Double, carbs: Double, fat: Double) {
        self.id = UUID()
        self.ownerID = ownerID
        self.name = name
        self.servingLabel = servingLabel
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.createdAt = .now
    }

    var template: FoodTemplate {
        FoodTemplate(
            key: "custom.\(id.uuidString)", name: name, servingLabel: servingLabel,
            calories: calories, protein: protein, carbs: carbs, fat: fat
        )
    }
}

@Model
final class FavoriteFood {
    /// "<ownerID>|<foodKey>": kullanıcı başına yiyecek başına tek favori.
    @Attribute(.unique) var compositeKey: String
    var ownerID: String
    var foodKey: String
    var name: String
    var servingLabel: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var addedAt: Date

    init(ownerID: String, template: FoodTemplate) {
        self.compositeKey = "\(ownerID)|\(template.key)"
        self.ownerID = ownerID
        self.foodKey = template.key
        self.name = template.name
        self.servingLabel = template.servingLabel
        self.calories = template.calories
        self.protein = template.protein
        self.carbs = template.carbs
        self.fat = template.fat
        self.addedAt = .now
    }

    var template: FoodTemplate {
        FoodTemplate(
            key: foodKey, name: name, servingLabel: servingLabel,
            calories: calories, protein: protein, carbs: carbs, fat: fat
        )
    }
}

// MARK: - Firestore DTO
struct MealDTO: Codable, Equatable {
    var id: String
    var date: Date
    var mealType: String
    var foodKey: String
    var name: String
    var servingLabel: String
    var quantity: Double
    var caloriesPerServing: Double
    var proteinPerServing: Double
    var carbsPerServing: Double
    var fatPerServing: Double
    var createdAt: Date
    var updatedAt: Date
}

extension MealEntry {
    var dto: MealDTO {
        MealDTO(
            id: id.uuidString, date: date, mealType: mealTypeRaw, foodKey: foodKey, name: name,
            servingLabel: servingLabel, quantity: quantity,
            caloriesPerServing: caloriesPerServing, proteinPerServing: proteinPerServing,
            carbsPerServing: carbsPerServing, fatPerServing: fatPerServing,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
