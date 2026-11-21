import Foundation
import SwiftData

/// Özet ekranının gerçek veri kaynağı: bugünün antrenmanları (SwiftData) ve adım/mesafe/kalori (HealthKit).
/// Beslenme, su, uyku ve kilo modülleri eklendikçe genişleyecek.
struct LiveDashboardDataSource: DashboardDataSource {
    let context: ModelContext
    let ownerID: String
    var health: HealthDataProviding = HealthKitManager.shared
    var weightKg: Double?
    var heightCm: Double?
    var stepGoal: Int = Constants.Defaults.stepGoal

    @MainActor
    func summary(for date: Date) async throws -> DashboardSummary {
        var summary = try await EmptyDashboardDataSource().summary(for: date)
        let today = date.startOfDay
        let owner = ownerID
        let end = date.endOfDay

        // 1) Antrenmanlar
        let workouts = try context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.ownerID == owner && $0.date >= today && $0.date <= end }
        ))
        let workoutKcal = workouts.reduce(0) { $0 + $1.caloriesBurned }
        summary.workoutMinutes = Int(workouts.reduce(0) { $0 + $1.durationMinutes }.rounded())

        // 2) HealthKit (izin yoksa boş döner, hata değil)
        var activity: [DailyActivity] = []
        if health.isHealthDataAvailable {
            let weekAgo = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
            activity = (try? await health.activity(from: weekAgo, to: end)) ?? []
        }
        if !activity.isEmpty {
            summary.weeklySteps = activity.map { DailyValue(date: $0.date, value: Double($0.steps)) }
        }

        let todayActivity = activity.last { $0.date == today }
        let steps = todayActivity?.steps ?? 0
        var distanceKm = todayActivity?.distanceKm ?? 0
        if distanceKm == 0, steps > 0, let heightCm {
            distanceKm = CalorieCalculator.estimatedDistanceKm(steps: steps, heightCm: heightCm)
        }
        summary.steps = steps
        summary.distanceKm = distanceKm

        // 3) Yakılan kalori (çifte sayımı önleyen kural)
        let healthKcal = todayActivity?.activeEnergyKcal ?? 0
        let burned: Double
        if healthKcal > 0 {
            burned = max(healthKcal, workoutKcal)     // HealthKit antrenmanları da içerebilir
        } else {
            let walking = CalorieCalculator.walkingCalories(
                distanceKm: distanceKm,
                weightKg: weightKg ?? Constants.Training.fallbackWeightKg
            )
            burned = walking + workoutKcal
        }
        summary.caloriesBurned = Int(burned.rounded())

        // 4) Widget özeti
        if health.isHealthDataAvailable {
            SharedStore.save(StepsSnapshot(steps: steps, goal: stepGoal, distanceKm: distanceKm, updatedAt: .now))
        }
        return summary
    }
}
