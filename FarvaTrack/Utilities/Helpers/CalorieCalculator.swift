import Foundation

/// BMR ve günlük hedef hesaplamaları (Mifflin-St Jeor).
enum CalorieCalculator {

    struct Recommendation: Equatable {
        let bmr: Int
        let tdee: Int
        let calorieGoal: Int
        let waterGoalMl: Int
        let stepGoal: Int
        let sleepHours: Double
    }

    struct MacroTargets: Equatable {
        let proteinG: Int
        let carbsG: Int
        let fatG: Int
    }

    /// Bazal metabolizma hızı (kcal/gün).
    static func bmr(weightKg: Double, heightCm: Double, age: Int, gender: Gender) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch gender {
        case .male: return base + 5
        case .female: return base - 161
        case .other: return base - 78   // erkek/kadın ortalaması
        }
    }

    /// Günlük toplam enerji harcaması.
    static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * activity.multiplier
    }

    static func calorieGoal(tdee: Double, goal: FitnessGoal) -> Int {
        let adjusted = max(tdee + goal.calorieAdjustment, 1_200)
        return Int((adjusted / 10).rounded() * 10)
    }

    /// Kilo başına 33 ml + aktiviteye göre ek, 50 ml'ye yuvarlanır.
    static func waterGoalMl(weightKg: Double, activity: ActivityLevel) -> Int {
        let raw = weightKg * 33 + activity.waterBonusMl
        return Int((raw / 50).rounded() * 50)
    }

    static func stepGoal(goal: FitnessGoal, activity: ActivityLevel) -> Int {
        let base = goal.baseStepGoal
        return activity == .sedentary ? min(base, 7_000) : base
    }

    static func sleepHours(age: Int) -> Double {
        switch age {
        case ..<18: return 9.0
        case 18..<65: return 8.0
        default: return 7.5
        }
    }

    static func recommendation(
        weightKg: Double,
        heightCm: Double,
        age: Int,
        gender: Gender,
        activity: ActivityLevel,
        goal: FitnessGoal
    ) -> Recommendation {
        let bmrValue = bmr(weightKg: weightKg, heightCm: heightCm, age: age, gender: gender)
        let tdeeValue = tdee(bmr: bmrValue, activity: activity)
        return Recommendation(
            bmr: Int(bmrValue.rounded()),
            tdee: Int(tdeeValue.rounded()),
            calorieGoal: calorieGoal(tdee: tdeeValue, goal: goal),
            waterGoalMl: waterGoalMl(weightKg: weightKg, activity: activity),
            stepGoal: stepGoal(goal: goal, activity: activity),
            sleepHours: sleepHours(age: age)
        )
    }

    /// Egzersiz kalorisi: MET × kilo (kg) × süre (saat).
    static func exerciseCalories(met: Double, weightKg: Double, minutes: Double) -> Double {
        met * weightKg * minutes / 60
    }

    /// Yürüyüş kalorisi tahmini (net): ≈ 0,53 kcal × kg × km.
    static func walkingCalories(distanceKm: Double, weightKg: Double) -> Double {
        distanceKm * weightKg * 0.53
    }

    /// Adım uzunluğu ≈ boy × 0,415 varsayımıyla mesafe tahmini.
    static func estimatedDistanceKm(steps: Int, heightCm: Double) -> Double {
        Double(steps) * heightCm * 0.415 / 100_000
    }

    /// Hedefe göre genel makro oranları (protein ve karbonhidrat 4, yağ 9 kcal/g).
    static func macroTargets(calories: Int, goal: FitnessGoal) -> MacroTargets {
        let split: (protein: Double, carbs: Double, fat: Double)
        switch goal {
        case .loseWeight: split = (0.30, 0.40, 0.30)
        case .maintain: split = (0.20, 0.50, 0.30)
        case .gainMuscle: split = (0.30, 0.45, 0.25)
        case .improveFitness: split = (0.25, 0.50, 0.25)
        }
        let total = Double(calories)
        return MacroTargets(
            proteinG: Int((total * split.protein / 4).rounded()),
            carbsG: Int((total * split.carbs / 4).rounded()),
            fatG: Int((total * split.fat / 9).rounded())
        )
    }
}
