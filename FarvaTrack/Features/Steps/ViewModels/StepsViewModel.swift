import Foundation
import Observation
import SwiftData

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
    /// Apple Sağlık'tan gelen ham günler
    private(set) var healthDays: [DailyActivity] = []
    /// Elle girilen adımlar (gün başlangıcı → adım); Sağlık verisinin yerine geçer.
    private(set) var manualSteps: [Date: Int] = [:]
    /// Sağlık'a erişilemediğinde ekranda gösterilen açıklama (ör. imzada HealthKit izni yok).
    private(set) var healthIssue: String?
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
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var manualDeletions: PendingDeletionStore?
    @ObservationIgnored private let manualSync: ManualStepSyncing

    init(
        health: HealthDataProviding = HealthKitManager.shared,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
        widgetPublisher: @escaping (StepsSnapshot) -> Void = { SharedStore.save($0) },
        manualSync: ManualStepSyncing = FirestoreManualStepSyncService()
    ) {
        self.manualSync = manualSync
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
            healthIssue = nil
            access = .ready
            startLiveUpdates()
        } catch {
            errorMessage = AppError.map(error).errorDescription
            healthIssue = Self.issueText(for: error)
            Haptics.error()
        }
    }

    /// Kullanıcıya gösterilecek açıklama; imza kaynaklı HealthKit hatasını ayrıca anlatır.
    static func issueText(for error: Error) -> String {
        let text = "\(error)"
        if text.localizedCaseInsensitiveContains("entitlement") {
            return "Bu kurulumda Apple Sağlık izni yok (uygulama ücretsiz Apple ID ile imzalandığında olabilir). Adımlarını elle girebilirsin."
        }
        return "Apple Sağlık verisi okunamadı. Adımlarını elle girebilirsin."
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
                self?.healthIssue = Self.issueText(for: error)
            }
        }
    }

    private func apply(_ result: [DailyActivity]) {
        healthDays = result.sorted { $0.date < $1.date }
        lastUpdated = now()
        hasLoaded = true
        publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot() {
        let day = days.first { $0.date == today } ?? .empty(on: today)
        widgetPublisher(StepsSnapshot(steps: day.steps, goal: dailyGoal, distanceKm: day.distanceKm, updatedAt: now()))
    }

    /// Sağlık ve elle girilen verinin birleşimi; tüm hesaplar bunu kullanır.
    var days: [DailyActivity] {
        StepMerger.merge(health: healthDays, manual: manualSteps, heightCm: heightCm, calendar: calendar)
    }

    // MARK: - Elle giriş
    func attach(context: ModelContext, userID: String) {
        self.context = context
        if self.userID != userID {
            self.userID = userID
            manualDeletions = PendingDeletionStore(userID: userID, scope: "ManualStep")
        }
        reloadManual()
    }

    func manualValue(for day: Date) -> Int? {
        manualSteps[calendar.startOfDay(for: day)]
    }

    var isTodayManual: Bool { manualValue(for: today) != nil }

    /// Aynı güne kayıt varsa günceller.
    func saveManual(steps: Int, for day: Date) throws {
        guard let context, let userID else { throw AppError.notAuthenticated }
        guard (0...StepMerger.maxDailySteps).contains(steps) else {
            throw AppError.invalidInput("Adım 0–\(StepMerger.maxDailySteps.formatted()) arasında olmalı.")
        }
        let start = calendar.startOfDay(for: day)
        guard start <= today else { throw AppError.invalidInput("Gelecek bir gün için adım girilemez.") }

        let entry: ManualStepEntry
        if let existing = manualEntry(for: start) {
            entry = existing
            entry.steps = steps
        } else {
            entry = ManualStepEntry(ownerID: userID, day: start, steps: steps)
            context.insert(entry)
        }
        entry.updatedAt = .now
        entry.needsSync = true
        do { try context.save() } catch { throw AppError.unknown(error.localizedDescription) }

        reloadManual()
        hasLoaded = true
        publishWidgetSnapshot()
        Haptics.success()
        uploadManual(entry)
    }

    /// Elle girilen değeri siler; o gün yeniden Sağlık verisi kullanılır.
    func deleteManual(for day: Date) {
        guard let context, let userID, let entry = manualEntry(for: calendar.startOfDay(for: day)) else { return }
        let id = entry.id.uuidString
        context.delete(entry)
        try? context.save()
        reloadManual()
        publishWidgetSnapshot()
        Haptics.impact(.light)
        manualDeletions?.add(id)
        let store = manualDeletions
        let sync = manualSync
        Task {
            do {
                try await sync.delete(id: id, userID: userID)
                store?.remove(id)
            } catch {}
        }
    }

    func syncManual() async {
        guard let context, let userID else { return }
        let pending = manualDeletions?.ids ?? []
        for id in pending {
            do {
                try await manualSync.delete(id: id, userID: userID)
                manualDeletions?.remove(id)
            } catch {}
        }
        let since = calendar.date(byAdding: .year, value: -1, to: today) ?? .distantPast
        guard let remote = try? await manualSync.fetch(userID: userID, since: since) else { return }
        let local = (try? context.fetch(FetchDescriptor<ManualStepEntry>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
        var byID = Dictionary(local.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in remote where !pending.contains(dto.id) {
            if let existing = byID[dto.id] {
                if !existing.needsSync, dto.updatedAt > existing.updatedAt { existing.apply(dto) }
            } else {
                let entry = ManualStepEntry.make(from: dto, ownerID: userID)
                context.insert(entry)
                byID[dto.id] = entry
            }
        }
        try? context.save()
        for entry in local where entry.needsSync { uploadManual(entry) }
        reloadManual()
        if !manualSteps.isEmpty {
            hasLoaded = true
            publishWidgetSnapshot()
        }
    }

    private func manualEntry(for day: Date) -> ManualStepEntry? {
        guard let context, let userID else { return nil }
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return try? context.fetch(FetchDescriptor<ManualStepEntry>(
            predicate: #Predicate { $0.ownerID == userID && $0.day >= day && $0.day < end }
        )).first
    }

    private func reloadManual() {
        guard let context, let userID else { return }
        let since = calendar.date(byAdding: .day, value: -400, to: today) ?? .distantPast
        manualSteps = StepMerger.manualMap(context: context, ownerID: userID, since: since)
    }

    private func uploadManual(_ entry: ManualStepEntry) {
        guard let userID else { return }
        let dto = entry.dto
        let id = entry.id
        let updatedAt = entry.updatedAt
        let sync = manualSync
        Task {
            do {
                try await sync.upload(dto, userID: userID)
                if let context, let item = try? context.fetch(FetchDescriptor<ManualStepEntry>(predicate: #Predicate { $0.id == id })).first,
                   item.updatedAt == updatedAt {
                    item.needsSync = false
                    try? context.save()
                }
            } catch {}
        }
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
