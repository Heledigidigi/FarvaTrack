import Foundation

/// Arka planda (HealthKit teslimi) bugünün adımlarını okuyup widget özetini günceller.
enum StepsWidgetRefresher {
    static func refresh(health: HealthDataProviding = HealthKitManager.shared) async {
        let today = Calendar.current.startOfDay(for: .now)
        guard let day = try? await health.activity(from: today, to: Date.now.endOfDay).last else { return }

        // Hedef, uygulama açıkken yazılan son özetten alınır.
        let goal = SharedStore.loadSteps()?.goal ?? Constants.Defaults.stepGoal
        SharedStore.save(StepsSnapshot(steps: day.steps, goal: goal, distanceKm: day.distanceKm, updatedAt: .now))
    }
}
