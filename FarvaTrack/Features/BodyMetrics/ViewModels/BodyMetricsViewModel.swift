import Foundation
import Observation
import SwiftData
import UserNotifications

typealias WeighInNotificationScheduling = NotificationScheduling & WeighInReminderScheduling

struct MeasureChange: Equatable {
    let value: Double
    /// Bir önceki ölçüme göre fark (cm); ilk ölçümse `nil`.
    let change: Double?
}

@MainActor
@Observable
final class BodyMetricsViewModel {
    var errorMessage: String?
    private(set) var heightCm: Double?
    private(set) var age: Int?
    private(set) var targetWeightKg: Double?
    private(set) var startWeightKg: Double?
    private(set) var reminderSettings: WeighInReminderSettings
    private(set) var isSyncing = false

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var weightDeletions: PendingDeletionStore?
    @ObservationIgnored private var measurementDeletions: PendingDeletionStore?
    @ObservationIgnored private let sync: BodyMetricsSyncing
    @ObservationIgnored private let scheduler: WeighInNotificationScheduling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    init(
        sync: BodyMetricsSyncing = FirestoreBodyMetricsSyncService(),
        scheduler: WeighInNotificationScheduling = NotificationManager.shared,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.sync = sync
        self.scheduler = scheduler
        self.defaults = defaults
        self.calendar = calendar
        self.reminderSettings = WeighInReminderSettings.load(defaults: defaults)
    }

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func configure(context: ModelContext, user: AppUser) {
        self.context = context
        if userID != user.id {
            userID = user.id
            weightDeletions = PendingDeletionStore(userID: user.id, scope: "Weight")
            measurementDeletions = PendingDeletionStore(userID: user.id, scope: "Measurement")
        }
        heightCm = user.heightCm
        age = user.age
        targetWeightKg = user.targetWeightKg
        startWeightKg = user.startWeightKg
    }

    // MARK: - Hesaplar
    func bmi(for weightKg: Double) -> Double? {
        guard let heightCm else { return nil }
        return WeightAnalyzer.bmi(weightKg: weightKg, heightCm: heightCm)
    }

    func validateGoal(_ targetKg: Double, currentKg: Double?) -> WeightGoalValidation {
        WeightAnalyzer.validateGoal(targetKg: targetKg, currentKg: currentKg, heightCm: heightCm, age: age)
    }

    /// Profil güncellemesi için en son tartı (tarihe göre).
    func latestWeight() -> Double? {
        guard let context, let userID else { return nil }
        var descriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.ownerID == userID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.weightKg
    }

    // MARK: - Kilo
    /// Aynı güne ait tartı varsa günceller (günde tek kayıt).
    @discardableResult
    func saveWeight(_ kg: Double, date: Date = .now, note: String? = nil, editing: WeightEntry? = nil) throws -> WeightEntry {
        guard let context, let userID else { throw AppError.notAuthenticated }
        guard WeightAnalyzer.isValid(kg) else {
            throw AppError.invalidInput("Kilo \(Int(WeightAnalyzer.validRange.lowerBound))–\(Int(WeightAnalyzer.validRange.upperBound)) kg arasında olmalı.")
        }
        guard date <= Date.now.addingTimeInterval(60) else {
            throw AppError.invalidInput("Gelecek tarihli tartı eklenemez.")
        }
        let rounded = (kg * 10).rounded() / 10
        let cleanNote: String? = {
            guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(200))
        }()

        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date

        let target: WeightEntry
        if let editing {
            target = editing
        } else if let existing = try? context.fetch(FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.ownerID == userID && $0.date >= start && $0.date < end }
        )).first {
            target = existing
        } else {
            target = WeightEntry(ownerID: userID, date: date, weightKg: rounded, note: cleanNote)
            context.insert(target)
        }

        target.date = date
        target.weightKg = rounded
        target.note = cleanNote
        target.updatedAt = .now
        target.needsSync = true

        try commit()
        Haptics.success()
        uploadWeight(target)
        return target
    }

    func deleteWeight(_ entry: WeightEntry) {
        guard let context, let userID else { return }
        let id = entry.id.uuidString
        context.delete(entry)
        do { try commit() } catch { present(error); return }
        Haptics.impact(.medium)
        weightDeletions?.add(id)
        deleteRemoteWeight(id: id, userID: userID)
    }

    // MARK: - Ölçüler
    @discardableResult
    func saveMeasurement(_ values: [BodyMeasure: Double], date: Date = .now, editing: MeasurementEntry? = nil) throws -> MeasurementEntry {
        guard let context, let userID else { throw AppError.notAuthenticated }
        guard !values.isEmpty else { throw AppError.invalidInput("En az bir ölçü gir.") }
        for (measure, value) in values where !measure.validRange.contains(value) {
            throw AppError.invalidInput("\(measure.title) ölçüsü \(Int(measure.validRange.lowerBound))–\(Int(measure.validRange.upperBound)) cm arasında olmalı.")
        }
        guard date <= Date.now.addingTimeInterval(60) else {
            throw AppError.invalidInput("Gelecek tarihli ölçü eklenemez.")
        }

        let target: MeasurementEntry
        if let editing {
            target = editing
        } else {
            target = MeasurementEntry(ownerID: userID, date: date)
            context.insert(target)
        }
        for measure in BodyMeasure.allCases {
            target.setValue(values[measure].map { ($0 * 10).rounded() / 10 }, for: measure)
        }
        target.date = date
        target.updatedAt = .now
        target.needsSync = true

        try commit()
        Haptics.success()
        uploadMeasurement(target)
        return target
    }

    func deleteMeasurement(_ entry: MeasurementEntry) {
        guard let context, let userID else { return }
        let id = entry.id.uuidString
        context.delete(entry)
        do { try commit() } catch { present(error); return }
        Haptics.impact(.medium)
        measurementDeletions?.add(id)
        deleteRemoteMeasurement(id: id, userID: userID)
    }

    /// Her ölçü için en son iki değerin farkı (en yeni − önceki).
    nonisolated static func latestChanges(_ entries: [MeasurementEntry]) -> [BodyMeasure: MeasureChange] {
        let sorted = entries.sorted { $0.date > $1.date }
        var result: [BodyMeasure: MeasureChange] = [:]
        for measure in BodyMeasure.allCases {
            let values = sorted.compactMap { $0.value(for: measure) }
            guard let latest = values.first else { continue }
            result[measure] = MeasureChange(value: latest, change: values.count > 1 ? latest - values[1] : nil)
        }
        return result
    }

    // MARK: - Hatırlatıcı
    @discardableResult
    func applyReminder(_ settings: WeighInReminderSettings) async -> Bool {
        var updated = settings
        defer {
            reminderSettings = updated
            updated.save(defaults: defaults)
        }
        guard settings.isEnabled else {
            await scheduler.cancelWeighInReminder()
            return true
        }

        var status = await scheduler.authorizationStatus()
        if status == .notDetermined {
            _ = try? await scheduler.requestAuthorization()
            status = await scheduler.authorizationStatus()
        }
        guard status.allowsNotifications else {
            updated.isEnabled = false
            await scheduler.cancelWeighInReminder()
            return false
        }

        do {
            try await scheduler.scheduleWeighInReminder(weekday: settings.weekday, hour: settings.hour, minute: settings.minute)
            return true
        } catch {
            updated.isEnabled = false
            present(error)
            return false
        }
    }

    // MARK: - Senkronizasyon
    func syncAll() async {
        guard let context, let userID, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let pendingWeights = weightDeletions?.ids ?? []
        let pendingMeasurements = measurementDeletions?.ids ?? []
        for id in pendingWeights { deleteRemoteWeight(id: id, userID: userID) }
        for id in pendingMeasurements { deleteRemoteMeasurement(id: id, userID: userID) }

        // Kilo geçmişi uzun vadeli olduğundan son bir yıl içinde değişen kayıtlar alınır.
        let since = calendar.date(byAdding: .year, value: -1, to: .now) ?? .distantPast

        do {
            let remote = try await sync.fetchWeights(userID: userID, since: since)
            let local = try context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.ownerID == userID }))
            var byID = Dictionary(local.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
            for dto in remote where !pendingWeights.contains(dto.id) {
                if let existing = byID[dto.id] {
                    if !existing.needsSync, dto.updatedAt > existing.updatedAt { existing.apply(dto) }
                } else {
                    let entry = WeightEntry.make(from: dto, ownerID: userID)
                    context.insert(entry)
                    byID[dto.id] = entry
                }
            }
            try context.save()
            for entry in local where entry.needsSync { uploadWeight(entry) }
        } catch {
            // Çevrimdışı olabilir.
        }

        do {
            let remote = try await sync.fetchMeasurements(userID: userID, since: since)
            let local = try context.fetch(FetchDescriptor<MeasurementEntry>(predicate: #Predicate { $0.ownerID == userID }))
            var byID = Dictionary(local.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
            for dto in remote where !pendingMeasurements.contains(dto.id) {
                if let existing = byID[dto.id] {
                    if !existing.needsSync, dto.updatedAt > existing.updatedAt { existing.apply(dto) }
                } else {
                    let entry = MeasurementEntry.make(from: dto, ownerID: userID)
                    context.insert(entry)
                    byID[dto.id] = entry
                }
            }
            try context.save()
            for entry in local where entry.needsSync { uploadMeasurement(entry) }
        } catch {
            // Çevrimdışı olabilir.
        }
    }

    // MARK: - Yardımcılar
    private func commit() throws {
        guard let context else { throw AppError.notAuthenticated }
        do {
            try context.save()
        } catch {
            throw AppError.unknown(error.localizedDescription)
        }
    }

    private func uploadWeight(_ entry: WeightEntry) {
        guard let userID else { return }
        let dto = entry.dto
        let id = entry.id
        let updatedAt = entry.updatedAt
        Task {
            do {
                try await sync.uploadWeight(dto, userID: userID)
                markWeightSynced(id: id, updatedAt: updatedAt)
            } catch {}
        }
    }

    private func uploadMeasurement(_ entry: MeasurementEntry) {
        guard let userID else { return }
        let dto = entry.dto
        let id = entry.id
        let updatedAt = entry.updatedAt
        Task {
            do {
                try await sync.uploadMeasurement(dto, userID: userID)
                markMeasurementSynced(id: id, updatedAt: updatedAt)
            } catch {}
        }
    }

    private func markWeightSynced(id: UUID, updatedAt: Date) {
        guard let context else { return }
        let descriptor = FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.id == id })
        if let entry = try? context.fetch(descriptor).first, entry.updatedAt == updatedAt {
            entry.needsSync = false
            try? context.save()
        }
    }

    private func markMeasurementSynced(id: UUID, updatedAt: Date) {
        guard let context else { return }
        let descriptor = FetchDescriptor<MeasurementEntry>(predicate: #Predicate { $0.id == id })
        if let entry = try? context.fetch(descriptor).first, entry.updatedAt == updatedAt {
            entry.needsSync = false
            try? context.save()
        }
    }

    private func deleteRemoteWeight(id: String, userID: String) {
        let store = weightDeletions
        Task {
            do {
                try await sync.deleteWeight(id: id, userID: userID)
                store?.remove(id)
            } catch {}
        }
    }

    private func deleteRemoteMeasurement(id: String, userID: String) {
        let store = measurementDeletions
        Task {
            do {
                try await sync.deleteMeasurement(id: id, userID: userID)
                store?.remove(id)
            } catch {}
        }
    }

    private func present(_ error: Error) {
        errorMessage = AppError.map(error).errorDescription
        Haptics.error()
    }
}
