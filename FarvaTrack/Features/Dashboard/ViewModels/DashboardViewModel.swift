import Foundation
import Observation

// MARK: - Modeller
/// Dashboard'un bugün için gösterdiği toplu veriler.
struct DashboardSummary: Equatable {
    var steps = 0
    var caloriesBurned = 0
    var distanceKm = 0.0
    var caloriesConsumed = 0
    var waterMl = 0
    var sleepHours: Double?
    var latestWeightKg: Double?
    var workoutMinutes = 0
    var weeklySteps: [DailyValue] = []
}

/// Kullanıcının hedefleri ve profilden gelen referans değerler.
struct DashboardGoals: Equatable {
    var steps = Constants.Defaults.stepGoal
    var calories = Constants.Defaults.calorieGoal
    var waterMl = Constants.Defaults.waterGoalMl
    var sleepHours = Constants.Defaults.sleepGoalHours
    var profileWeightKg: Double?
    var heightCm: Double?
    var targetWeightKg: Double?

    init() {}

    init(user: AppUser) {
        steps = user.dailyStepGoal
        calories = user.dailyCalorieGoal
        waterMl = user.dailyWaterGoalMl
        sleepHours = user.sleepGoalHours
        profileWeightKg = user.weightKg
        heightCm = user.heightCm
        targetWeightKg = user.targetWeightKg
    }
}

// MARK: - Veri kaynağı
protocol DashboardDataSource {
    func summary(for date: Date) async throws -> DashboardSummary
}

/// Modüller (Faz 3–9) bağlanana kadar kullanılan boş kaynak.
struct EmptyDashboardDataSource: DashboardDataSource {
    func summary(for date: Date) async throws -> DashboardSummary {
        var summary = DashboardSummary()
        summary.weeklySteps = (0..<7).reversed().map { offset in
            DailyValue(
                date: Calendar.current.date(byAdding: .day, value: -offset, to: date.startOfDay) ?? date,
                value: 0
            )
        }
        return summary
    }
}

#if DEBUG
/// Arayüzü verili görmek için geçici örnek veri.
struct SampleDashboardDataSource: DashboardDataSource {
    func summary(for date: Date) async throws -> DashboardSummary {
        var summary = DashboardSummary()
        summary.steps = 6_240
        summary.caloriesBurned = 310
        summary.distanceKm = 4.6
        summary.caloriesConsumed = 1_450
        summary.waterMl = 1_500
        summary.sleepHours = 7.2
        summary.latestWeightKg = 72.4
        summary.workoutMinutes = 35

        let values: [Double] = [5_400, 8_200, 10_300, 7_600, 9_100, 4_300, 6_240]
        summary.weeklySteps = values.enumerated().map { index, value in
            DailyValue(
                date: Calendar.current.date(byAdding: .day, value: index - 6, to: date.startOfDay) ?? date,
                value: value
            )
        }
        return summary
    }
}
#endif

// MARK: - ViewModel
@MainActor
@Observable
final class DashboardViewModel {
    private(set) var summary = DashboardSummary()
    private(set) var goals = DashboardGoals()
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    @ObservationIgnored private let dataSource: DashboardDataSource

    init(dataSource: DashboardDataSource = EmptyDashboardDataSource()) {
        self.dataSource = dataSource
    }

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    // MARK: Yükleme
    func updateGoals(from user: AppUser) {
        goals = DashboardGoals(user: user)
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            summary = try await dataSource.summary(for: .now)
        } catch {
            errorMessage = AppError.map(error).errorDescription
        }
    }

    // MARK: İlerleme oranları (1'i geçebilir; halka/çubuk kendi içinde sınırlar)
    var stepProgress: Double { ratio(Double(summary.steps), Double(goals.steps)) }
    var calorieProgress: Double { ratio(Double(summary.caloriesConsumed), Double(goals.calories)) }
    var waterProgress: Double { ratio(Double(summary.waterMl), Double(goals.waterMl)) }
    var sleepProgress: Double { ratio(summary.sleepHours ?? 0, goals.sleepHours) }

    var hasWeeklyStepData: Bool {
        summary.weeklySteps.contains { $0.value > 0 }
    }

    // MARK: Kilo / BMI
    var displayedWeightKg: Double? {
        summary.latestWeightKg ?? goals.profileWeightKg
    }

    var bmi: Double? {
        guard let weight = displayedWeightKg, let height = goals.heightCm, height > 0 else { return nil }
        let meters = height / 100
        return weight / (meters * meters)
    }

    // MARK: Selamlama
    var greeting: String {
        Self.greeting(forHour: Calendar.current.component(.hour, from: .now))
    }

    static func greeting(forHour hour: Int) -> String {
        switch hour {
        case 5..<12: return "Günaydın"
        case 12..<18: return "İyi günler"
        case 18..<22: return "İyi akşamlar"
        default: return "İyi geceler"
        }
    }

    private func ratio(_ value: Double, _ goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return max(value / goal, 0)
    }
}