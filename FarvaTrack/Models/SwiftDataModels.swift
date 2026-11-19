import Foundation
import SwiftData

@Model
final class LocalUserProfile {
    @Attribute(.unique) var uid: String
    var displayName: String
    var email: String
    var photoURL: String?
    var birthDate: Date?
    var heightCm: Double?
    var genderRaw: String?
    var activityLevelRaw: String
    var goalRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        uid: String,
        displayName: String,
        email: String,
        photoURL: String? = nil,
        birthDate: Date? = nil,
        heightCm: Double? = nil,
        genderRaw: String? = nil,
        activityLevelRaw: String = "moderatelyActive",
        goalRaw: String = "buildMuscle",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.uid = uid
        self.displayName = displayName
        self.email = email
        self.photoURL = photoURL
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.genderRaw = genderRaw
        self.activityLevelRaw = activityLevelRaw
        self.goalRaw = goalRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class MealEntry {
    @Attribute(.unique) var id: String
    var ownerID: String
    var name: String
    var mealType: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var date: Date

    init(id: String = UUID().uuidString, ownerID: String, name: String, mealType: String = "Öğün", calories: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0, date: Date = .now) {
        self.id = id
        self.ownerID = ownerID
        self.name = name
        self.mealType = mealType
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.date = date
    }
}

@Model
final class CustomFood {
    @Attribute(.unique) var id: String
    var ownerID: String
    var name: String
    var caloriesPer100g: Double

    init(id: String = UUID().uuidString, ownerID: String, name: String, caloriesPer100g: Double) {
        self.id = id
        self.ownerID = ownerID
        self.name = name
        self.caloriesPer100g = caloriesPer100g
    }
}

@Model
final class FavoriteFood {
    @Attribute(.unique) var id: String
    var ownerID: String
    var foodId: String

    init(id: String = UUID().uuidString, ownerID: String, foodId: String) {
        self.id = id
        self.ownerID = ownerID
        self.foodId = foodId
    }
}

@Model
final class WaterEntry {
    @Attribute(.unique) var id: String
    var ownerID: String
    var amountMl: Double
    var date: Date

    init(id: String = UUID().uuidString, ownerID: String, amountMl: Double, date: Date = .now) {
        self.id = id
        self.ownerID = ownerID
        self.amountMl = amountMl
        self.date = date
    }
}

@Model
final class SleepEntry {
    @Attribute(.unique) var id: String
    var ownerID: String
    var day: Date
    var durationHours: Double
    var qualityScore: Int

    init(id: String = UUID().uuidString, ownerID: String, day: Date = .now.startOfDay, durationHours: Double = 7.5, qualityScore: Int = 4) {
        self.id = id
        self.ownerID = ownerID
        self.day = day
        self.durationHours = durationHours
        self.qualityScore = qualityScore
    }
}

@Model
final class WeightEntry {
    @Attribute(.unique) var id: String
    var ownerID: String
    var weightKg: Double
    var date: Date

    init(id: String = UUID().uuidString, ownerID: String, weightKg: Double, date: Date = .now) {
        self.id = id
        self.ownerID = ownerID
        self.weightKg = weightKg
        self.date = date
    }
}

@Model
final class MeasurementEntry {
    @Attribute(.unique) var id: String
    var ownerID: String
    var chestCm: Double?
    var waistCm: Double?
    var hipsCm: Double?
    var date: Date

    init(id: String = UUID().uuidString, ownerID: String, chestCm: Double? = nil, waistCm: Double? = nil, hipsCm: Double? = nil, date: Date = .now) {
        self.id = id
        self.ownerID = ownerID
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.hipsCm = hipsCm
        self.date = date
    }
}

@Model
final class WasteEntry {
    @Attribute(.unique) var id: String
    var ownerID: String
    var bristolScale: Int
    var date: Date
    var notes: String?

    init(id: String = UUID().uuidString, ownerID: String, bristolScale: Int = 4, date: Date = .now, notes: String? = nil) {
        self.id = id
        self.ownerID = ownerID
        self.bristolScale = bristolScale
        self.date = date
        self.notes = notes
    }
}

@Model
final class BadgeUnlock {
    @Attribute(.unique) var id: String
    var ownerID: String
    var badgeId: String
    var unlockedAt: Date

    init(id: String = UUID().uuidString, ownerID: String, badgeId: String, unlockedAt: Date = .now) {
        self.id = id
        self.ownerID = ownerID
        self.badgeId = badgeId
        self.unlockedAt = unlockedAt
    }
}
