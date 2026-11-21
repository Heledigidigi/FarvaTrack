import Foundation

/// Profil düzenleme formunun durumu. Doğrulama ve öneri hesabı burada; görünümden bağımsız test edilir.
struct ProfileDraft: Equatable {
    var displayName: String
    var birthDate: Date?
    var gender: Gender?
    var heightCm: Double?
    var activity: ActivityLevel
    var goal: FitnessGoal
    var dailyCalorieGoal: Int
    var dailyWaterGoalMl: Int
    var dailyStepGoal: Int
    var sleepGoalHours: Double

    static let nameLength = 2...50
    static let heightRange = 100.0...250.0
    static let ageRange = 13...100
    static let calorieRange = 1_200...5_000
    static let waterRange = 500...6_000
    static let stepRange = 1_000...50_000
    static let sleepRange = 5.0...11.0

    init(user: AppUser) {
        displayName = user.displayName
        birthDate = user.birthDate
        gender = user.gender
        heightCm = user.heightCm
        activity = user.activityLevel
        goal = user.goal
        dailyCalorieGoal = user.dailyCalorieGoal
        dailyWaterGoalMl = user.dailyWaterGoalMl
        dailyStepGoal = user.dailyStepGoal
        sleepGoalHours = user.sleepGoalHours
    }

    func age(now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let birthDate else { return nil }
        return calendar.dateComponents([.year], from: birthDate, to: now).year
    }

    func isMinor(now: Date = .now) -> Bool {
        (age(now: now) ?? 18) < 18
    }

    /// İlk hatanın açıklaması; geçerliyse `nil`.
    func validationError(now: Date = .now) -> String? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !Self.nameLength.contains(name.count) { return "Ad \(Self.nameLength.lowerBound)–\(Self.nameLength.upperBound) karakter olmalı." }
        if let age = age(now: now), !Self.ageRange.contains(age) { return "Doğum tarihi geçerli görünmüyor (\(Self.ageRange.lowerBound)–\(Self.ageRange.upperBound) yaş)." }
        if let heightCm, !Self.heightRange.contains(heightCm) { return "Boy \(Int(Self.heightRange.lowerBound))–\(Int(Self.heightRange.upperBound)) cm arasında olmalı." }
        if isMinor(now: now) && goal == .loseWeight { return "18 yaşından küçükler için kilo verme hedefi seçilemez." }
        if !Self.calorieRange.contains(dailyCalorieGoal) { return "Kalori hedefi \(Self.calorieRange.lowerBound.formatted())–\(Self.calorieRange.upperBound.formatted()) kcal arasında olmalı." }
        if !Self.waterRange.contains(dailyWaterGoalMl) { return "Su hedefi \(Self.waterRange.lowerBound)–\(Self.waterRange.upperBound.formatted()) ml arasında olmalı." }
        if !Self.stepRange.contains(dailyStepGoal) { return "Adım hedefi \(Self.stepRange.lowerBound.formatted())–\(Self.stepRange.upperBound.formatted()) arasında olmalı." }
        if !Self.sleepRange.contains(sleepGoalHours) { return "Uyku hedefi 5–11 saat arasında olmalı." }
        return nil
    }

    /// Profil bilgilerine göre önerilen günlük hedefler. Eksik bilgi varsa `nil`.
    func recommendation(weightKg: Double?, now: Date = .now) -> CalorieCalculator.Recommendation? {
        guard let weightKg, let heightCm, let age = age(now: now), let gender else { return nil }
        // Reşit olmayanlarda kalori açığı önerilmez.
        let safeGoal: FitnessGoal = (age < 18 && goal == .loseWeight) ? .maintain : goal
        return CalorieCalculator.recommendation(
            weightKg: weightKg, heightCm: heightCm, age: age,
            gender: gender, activity: activity, goal: safeGoal
        )
    }

    mutating func applyRecommendation(_ recommendation: CalorieCalculator.Recommendation) {
        dailyCalorieGoal = recommendation.calorieGoal
        dailyWaterGoalMl = min(max(recommendation.waterGoalMl, Self.waterRange.lowerBound), Self.waterRange.upperBound)
        dailyStepGoal = recommendation.stepGoal
        sleepGoalHours = recommendation.sleepHours
    }

    /// Taslağı kullanıcıya uygular (kilo bilgisi Kilo modülünden yönetilir).
    func applied(to user: AppUser) -> AppUser {
        var updated = user
        updated.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.birthDate = birthDate
        updated.gender = gender
        updated.heightCm = heightCm
        updated.activityLevel = activity
        updated.goal = goal
        updated.dailyCalorieGoal = dailyCalorieGoal
        updated.dailyWaterGoalMl = dailyWaterGoalMl
        updated.dailyStepGoal = dailyStepGoal
        updated.sleepGoalHours = sleepGoalHours
        return updated
    }
}
