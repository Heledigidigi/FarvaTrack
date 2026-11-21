import Foundation
import Observation
import SwiftData
import SwiftUI

enum StatMetric: String, CaseIterable, Identifiable {
    case steps, calories, water, sleep, workout, weight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Adım"
        case .calories: return "Alınan Kalori"
        case .water: return "Su"
        case .sleep: return "Uyku"
        case .workout: return "Antrenman"
        case .weight: return "Kilo"
        }
    }

    var unit: String {
        switch self {
        case .steps: return "adım"
        case .calories: return "kcal"
        case .water: return "ml"
        case .sleep: return "sa"
        case .workout: return "dk"
        case .weight: return "kg"
        }
    }

    var systemImage: String {
        switch self {
        case .steps: return "figure.walk"
        case .calories: return "flame.fill"
        case .water: return "drop.fill"
        case .sleep: return "moon.stars.fill"
        case .workout: return "dumbbell.fill"
        case .weight: return "scalemass.fill"
        }
    }

    var tint: Color {
        switch self {
        case .steps: return .ftAccentLight
        case .calories: return .ftCalories
        case .water: return .ftWater
        case .sleep: return .ftSleep
        case .workout: return .ftExercise
        case .weight: return .ftWeight
        }
    }

    var fractionDigits: Int { (self == .sleep || self == .weight) ? 1 : 0 }
}

struct MetricCard: Identifiable, Equatable {
    let metric: StatMetric
    let chart: [DailyValue]
    let summary: MetricSummary
    let goal: Double?

    var id: String { metric.id }
}

/// Ham veriler (SwiftData + HealthKit); testte doğrudan verilebilir.
struct StatisticsSamples {
    var steps: [(date: Date, value: Double)] = []
    var calories: [(date: Date, value: Double)] = []
    var water: [(date: Date, value: Double)] = []
    var sleep: [(date: Date, value: Double)] = []
    var workout: [(date: Date, value: Double)] = []
    var weight: [(date: Date, value: Double)] = []
}

@MainActor
@Observable
final class StatisticsViewModel {
    var period: StatsPeriod = .week
    private(set) var cards: [MetricCard] = []
    private(set) var badges: [BadgeStatus] = []
    private(set) var isLoading = false

    @ObservationIgnored private var samples = StatisticsSamples()
    @ObservationIgnored private var goals: [StatMetric: Double] = [:]
    @ObservationIgnored private let health: HealthDataProviding
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    init(
        health: HealthDataProviding = HealthKitManager.shared,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.health = health
        self.calendar = calendar
        self.now = now
    }

    var earnedCount: Int { badges.filter(\.isEarned).count }

    /// Son iki yılın verisini okur (yıllık karşılaştırma için), kartları ve rozetleri hesaplar.
    func load(context: ModelContext, user: AppUser) async {
        isLoading = true
        defer { isLoading = false }

        let owner = user.id
        let end = now()
        let start = calendar.date(byAdding: .day, value: -730, to: calendar.startOfDay(for: end)) ?? .distantPast

        var data = StatisticsSamples()
        var activity: [DailyActivity] = []
        if health.isHealthDataAvailable {
            activity = (try? await health.activity(from: start, to: end)) ?? []
        }
        let manual = StepMerger.manualMap(context: context, ownerID: owner, since: start)
        activity = StepMerger.merge(health: activity, manual: manual, heightCm: user.heightCm, calendar: calendar)
        data.steps = activity.map { ($0.date, Double($0.steps)) }

        let meals = (try? context.fetch(FetchDescriptor<MealEntry>(predicate: #Predicate { $0.ownerID == owner && $0.date >= start }))) ?? []
        data.calories = meals.map { ($0.date, $0.calories) }

        let water = (try? context.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.ownerID == owner && $0.date >= start }))) ?? []
        data.water = water.map { ($0.date, Double($0.amountMl)) }

        let sleep = (try? context.fetch(FetchDescriptor<SleepEntry>(predicate: #Predicate { $0.ownerID == owner && $0.day >= start }))) ?? []
        data.sleep = sleep.map { ($0.day, $0.durationHours) }

        let workouts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.ownerID == owner && $0.date >= start }))) ?? []
        data.workout = workouts.map { ($0.date, $0.durationMinutes) }

        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.ownerID == owner && $0.date >= start }))) ?? []
        data.weight = weights.map { ($0.date, $0.weightKg) }

        goals = [
            .steps: Double(user.dailyStepGoal),
            .calories: Double(user.dailyCalorieGoal),
            .water: Double(user.dailyWaterGoalMl),
            .sleep: user.sleepGoalHours
        ]
        samples = data
        rebuild()

        badges = BadgeEngine.evaluate(badgeInput(context: context, user: user, steps: data.steps), calendar: calendar)
    }

    func setPeriod(_ newPeriod: StatsPeriod) {
        guard newPeriod != period else { return }
        Haptics.selection()
        period = newPeriod
        rebuild()
    }

    /// Örneklerden kartları yeniden üretir (dönem değişince veri okumadan).
    func apply(samples: StatisticsSamples, goals: [StatMetric: Double]) {
        self.samples = samples
        self.goals = goals
        rebuild()
    }

    private func rebuild() {
        let end = now()
        let previousEnd = calendar.date(byAdding: .day, value: -period.days, to: end) ?? end

        cards = StatMetric.allCases.compactMap { metric in
            let source = values(for: metric)
            let isLatest = metric == .weight
            let daily = isLatest
                ? StatisticsCalculator.dailyLatest(source, days: period.days, endingOn: end, calendar: calendar)
                : StatisticsCalculator.dailyTotals(source, days: period.days, endingOn: end, calendar: calendar)
            let previous = isLatest
                ? StatisticsCalculator.dailyLatest(source, days: period.days, endingOn: previousEnd, calendar: calendar)
                : StatisticsCalculator.dailyTotals(source, days: period.days, endingOn: previousEnd, calendar: calendar)

            let summary = StatisticsCalculator.summary(daily, goal: goals[metric], previous: previous)
            // Hiç verisi olmayan metrik gösterilmez (ör. HealthKit izni yoksa adım).
            guard summary.recordedDays > 0 else { return nil }
            return MetricCard(
                metric: metric,
                chart: StatisticsCalculator.chartSeries(daily, period: period, calendar: calendar),
                summary: summary,
                goal: goals[metric]
            )
        }
    }

    private func values(for metric: StatMetric) -> [(date: Date, value: Double)] {
        switch metric {
        case .steps: return samples.steps
        case .calories: return samples.calories
        case .water: return samples.water
        case .sleep: return samples.sleep
        case .workout: return samples.workout
        case .weight: return samples.weight
        }
    }

    private func badgeInput(context: ModelContext, user: AppUser, steps: [(date: Date, value: Double)]) -> BadgeInput {
        let owner = user.id
        var input = BadgeInput()
        input.stepGoal = user.dailyStepGoal
        input.waterGoal = user.dailyWaterGoalMl

        input.workoutCount = (try? context.fetchCount(FetchDescriptor<Workout>(predicate: #Predicate { $0.ownerID == owner }))) ?? 0
        input.sleepNights = (try? context.fetchCount(FetchDescriptor<SleepEntry>(predicate: #Predicate { $0.ownerID == owner }))) ?? 0
        input.measurementCount = (try? context.fetchCount(FetchDescriptor<MeasurementEntry>(predicate: #Predicate { $0.ownerID == owner }))) ?? 0

        for sample in steps { input.dailySteps[calendar.startOfDay(for: sample.date)] = Int(sample.value) }

        let water = (try? context.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.ownerID == owner }))) ?? []
        for entry in water { input.dailyWater[calendar.startOfDay(for: entry.date), default: 0] += entry.amountMl }

        let meals = (try? context.fetch(FetchDescriptor<MealEntry>(predicate: #Predicate { $0.ownerID == owner }))) ?? []
        input.mealDays = Set(meals.map { calendar.startOfDay(for: $0.date) })

        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.ownerID == owner }))) ?? []
        input.weighInDays = Set(weights.map { calendar.startOfDay(for: $0.date) })
        return input
    }
}
