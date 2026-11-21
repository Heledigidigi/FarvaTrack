import Foundation
import Observation

enum StepPeriod: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Gün"
        case .week: return "Hafta"
        case .month: return "Ay"
        }
    }

    var scopeTitle: String {
        switch self {
        case .day: return "Bugünkü"
        case .week: return "Bu haftaki"
        case .month: return "Bu ayki"
        }
    }

    var chartTitle: String {
        switch self {
        case .day: return "Son 7 Gün"
        case .week: return "Bu Hafta"
        case .month: return "Bu Ay"
        }
    }
}

struct StepPeriodStats: Equatable {
    var steps: Int
    var distanceKm: Double
    var calories: Int
    var caloriesAreEstimated: Bool
    var goal: Int
    var dayCount: Int

    var progress: Double { goal > 0 ? Double(steps) / Double(goal) : 0 }
    var remaining: Int { max(goal - steps, 0) }
    var dailyAverage: Int { dayCount > 0 ? steps / dayCount : 0 }
}

@MainActor
@Observable
final class StepsViewModel {

    enum AccessState: Equatable {
        case loading, unavailable, needsPermission, ready
    }

    private(set) var access: AccessState = .loading
    private(set) var days: [DailyActivity] = []
    private(set) var lastUpdated: Date?
    private(set) var hasLoaded = false
    private(set) var dailyGoal = Constants.Defaults.stepGoal
    private var weightKg: Double?
    private var heightCm: Double?

    var period: StepPeriod = .day
    var errorMessage: String?

    @ObservationIgnored private let health: HealthDataProviding
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let widgetPublisher: (StepsSnapshot) -> Void
    @ObservationIgnored private var liveTask: Task<Void, Never>?

    init(
        health: HealthDataProviding = HealthKitManager.shared,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
        widgetPublisher: @escaping (StepsSnapshot) -> Void = { SharedStore.save($0) }
    ) {
        self.health = health
        self.calendar = calendar
        self.now = now
        self.widgetPublisher = widgetPublisher
    }

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    // MARK: - Yapılandırma ve yaşam döngüsü
    func configure(user: AppUser) {
        dailyGoal = max(user.dailyStepGoal, 1)
        weightKg = user.weightKg
        heightCm = user.heightCm
        if hasLoaded { publishWidgetSnapshot() }
    }

    /// İzin durumuna bakar; izin istenmişse canlı güncellemeyi başlatır.
    func start() async {
        guard health.isHealthDataAvailable else {
            access = .unavailable
            return
        }
        switch await health.requestStatus() {
        case .unavailable:
            access = .unavailable
        case .notDetermined:
            access = .needsPermission
        case .requested:
            access = .ready
            startLiveUpdates()
        }
    }

    func requestAccess() async {
        do {
            try await health.requestAuthorization()
            Haptics.success()
            access = .ready
            startLiveUpdates()
        } catch {
            errorMessage = AppError.map(error).errorDescription
            Haptics.error()
        }
    }

    func stop() {
        liveTask?.cancel()
        liveTask = nil
    }

    private func startLiveUpdates() {
        liveTask?.cancel()
        let range = fetchRange()
        let stream = health.liveActivity(from: range.start, to: range.end)
        liveTask = Task { [weak self] in
            do {
                for try await result in stream {
                    self?.apply(result)
                }
            } catch is CancellationError {
                // ekran kapandı
            } catch {
                self?.errorMessage = AppError.map(error).errorDescription
            }
        }
    }

    private func apply(_ result: [DailyActivity]) {
        days = result.sorted { $0.date < $1.date }
        lastUpdated = now()
        hasLoaded = true
        publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot() {
        let day = days.first { $0.date == today } ?? .empty(on: today)
        widgetPublisher(StepsSnapshot(steps: day.steps, goal: dailyGoal, distanceKm: day.distanceKm, updatedAt: now()))
    }

    // MARK: - Tarih aralıkları
    private var today: Date { calendar.startOfDay(for: now()) }
    private var weekStart: Date { calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today }
    private var monthStart: Date { calendar.dateInterval(of: .month, for: today)?.start ?? today }
    private var daysInMonth: Int { calendar.range(of: .day, in: .month, for: today)?.count ?? 30 }

    /// Gün, hafta ve ay ihtiyacını tek sorguyla karşılayan en geniş aralık.
    private func fetchRange() -> (start: Date, end: Date) {
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let start = min(sevenDaysAgo, weekStart, monthStart)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: today) ?? now()
        return (start, end)
    }

    private func headlineRange(_ period: StepPeriod) -> ClosedRange<Date> {
        switch period {
        case .day: return today...today
        case .week: return weekStart...today
        case .month: return monthStart...today
        }
    }

    // MARK: - Hesaplamalar
    func goal(for period: StepPeriod) -> Int {
        switch period {
        case .day: return dailyGoal
        case .week: return dailyGoal * 7
        case .month: return dailyGoal * daysInMonth
        }
    }

    func stats(for period: StepPeriod) -> StepPeriodStats {
        let range = headlineRange(period)
        let included = days.filter { range.contains($0.date) }

        let steps = included.reduce(0) { $0 + $1.steps }
        var distance = included.reduce(0) { $0 + $1.distanceKm }
        if distance == 0, steps > 0, let heightCm {
            distance = CalorieCalculator.estimatedDistanceKm(steps: steps, heightCm: heightCm)
        }

        let energy = included.reduce(0) { $0 + $1.activeEnergyKcal }
        let calories: Double
        let estimated: Bool
        if energy > 0 {
            calories = energy
            estimated = false
        } else {
            calories = CalorieCalculator.walkingCalories(
                distanceKm: distance,
                weightKg: weightKg ?? Constants.Training.fallbackWeightKg
            )
            estimated = steps > 0
        }

        let dayCount = (calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 0) + 1
        return StepPeriodStats(
            steps: steps,
            distanceKm: distance,
            calories: Int(calories.rounded()),
            caloriesAreEstimated: estimated,
            goal: goal(for: period),
            dayCount: dayCount
        )
    }

    /// Grafik için günlük adım değerleri (olmayan günler sıfır).
    func chartData(for period: StepPeriod) -> [DailyValue] {
        let dates: [Date]
        switch period {
        case .day:
            dates = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        case .week:
            dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        case .month:
            let count = (calendar.dateComponents([.day], from: monthStart, to: today).day ?? 0) + 1
            dates = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: monthStart) }
        }
        let stepsByDay = Dictionary(
            days.map { (calendar.startOfDay(for: $0.date), $0.steps) },
            uniquingKeysWith: { first, _ in first }
        )
        return dates.map { DailyValue(date: $0, value: Double(stepsByDay[calendar.startOfDay(for: $0)] ?? 0)) }
    }

    var isTodayGoalReached: Bool {
        stats(for: .day).progress >= 1
    }

    /// İzin verilmiş ama hiç veri yoksa kullanıcıya Sağlık ayarını kontrol etmesini öneririz.
    var showsNoDataHint: Bool {
        access == .ready && hasLoaded && days.allSatisfy { $0.steps == 0 }
    }
}
