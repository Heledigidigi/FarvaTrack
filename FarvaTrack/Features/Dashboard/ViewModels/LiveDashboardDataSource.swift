import Foundation
import SwiftData

/// Özet ekranının gerçek veri kaynağı: bugünün antrenman, beslenme, su, uyku ve kilo kayıtları (SwiftData)
/// ile adım/mesafe/kalori (HealthKit + elle girilen adımlar).
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

        // 2) Beslenme, su, uyku, kilo
        let meals = try context.fetch(FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.ownerID == owner && $0.date >= today && $0.date <= end }
        ))
        summary.caloriesConsumed = Int(meals.reduce(0) { $0 + $1.calories }.rounded())

        let water = try context.fetch(FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.ownerID == owner && $0.date >= today && $0.date <= end }
        ))
        summary.waterMl = water.reduce(0) { $0 + $1.amountMl }

        let sleep = try context.fetch(FetchDescriptor<SleepEntry>(
            predicate: #Predicate { $0.ownerID == owner && $0.day == today }
        ))
        summary.sleepHours = sleep.first?.durationHours

        var weightDescriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.ownerID == owner },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        weightDescriptor.fetchLimit = 1
        summary.latestWeightKg = try context.fetch(weightDescriptor).first?.weightKg

        summary.wasteCount = try context.fetchCount(FetchDescriptor<WasteEntry>(
            predicate: #Predicate { $0.ownerID == owner && $0.date >= today && $0.date <= end }
        ))

        // 3) HealthKit (izin yoksa boş döner, hata değil)
        var activity: [DailyActivity] = []
        let weekAgo = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        if health.isHealthDataAvailable {
            activity = (try? await health.activity(from: weekAgo, to: end)) ?? []
        }
        // Elle girilen adımlar o günün Sağlık verisinin yerine geçer.
        let manual = StepMerger.manualMap(context: context, ownerID: owner, since: weekAgo)
        activity = StepMerger.merge(health: activity, manual: manual, heightCm: heightCm)
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

        // 4) Yakılan kalori (çifte sayımı önleyen kural)
        let healthKcal = todayActivity?.activeEnergyKcal ?? 0
        let burned: Double
        if healthKcal > 0 {
            burned = max(healthKcal, workoutKcal)     // HealthKit antrenmanları da içerebilir
        } else {
            let walking = CalorieCalculator.walkingCalories(
                distanceKm: distanceKm,
                weightKg: summary.latestWeightKg ?? weightKg ?? Constants.Training.fallbackWeightKg
            )
            burned = walking + workoutKcal
        }
        summary.caloriesBurned = Int(burned.rounded())

        // 5) Widget özeti
        if health.isHealthDataAvailable || !manual.isEmpty {
            SharedStore.save(StepsSnapshot(steps: steps, goal: stepGoal, distanceKm: distanceKm, updatedAt: .now))
        }
        return summary
    }
}
