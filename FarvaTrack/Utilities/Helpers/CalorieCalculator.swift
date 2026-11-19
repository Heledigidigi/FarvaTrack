import Foundation

enum CalorieCalculator {
    /// BMR: Basal Metabolic Rate (Mifflin-St Jeor)
    static func bmr(weightKg: Double, heightCm: Double, age: Int, gender: Gender) -> Double {
        let base = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age))
        return gender == .male ? base + 5 : base - 161
    }

    /// TDEE: Total Daily Energy Expenditure
    static func tdee(bmr: Double, activityLevel: ActivityLevel) -> Double {
        let multiplier: Double
        switch activityLevel {
        case .sedentary: multiplier = 1.2
        case .lightlyActive: multiplier = 1.375
        case .moderatelyActive: multiplier = 1.55
        case .veryActive: multiplier = 1.725
        }
        return bmr * multiplier
    }

    /// Egzersiz kalorisi: MET × kilo (kg) × süre (saat).
    static func exerciseCalories(met: Double, weightKg: Double, minutes: Double) -> Double {
        met * weightKg * minutes / 60
    }
}
