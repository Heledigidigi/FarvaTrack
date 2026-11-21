import Foundation
import Observation
import SwiftData
import UserNotifications

typealias SleepNotificationScheduling = NotificationScheduling & SleepReminderScheduling

@MainActor
@Observable
final class SleepViewModel {
    static let goalRange = 5.0...11.0

    var errorMessage: String?
    private(set) var goalHours = Constants.Defaults.sleepGoalHours
    private(set) var settings: SleepSettings
    private(set) var isSyncing = false

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var deletions: PendingDeletionStore?
    @ObservationIgnored private let sync: SleepSyncing
    @ObservationIgnored private let scheduler: SleepNotificationScheduling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    init(
        sync: SleepSyncing = FirestoreSleepSyncService(),
        scheduler: SleepNotificationScheduling = NotificationManager.shared,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.sync = sync
        self.scheduler = scheduler
        self.defaults = defaults
        self.calendar = calendar
        self.settings = SleepSettings.load(defaults: defaults)
    }

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func configure(context: ModelContext, user: AppUser) {
        self.context = context
        if userID != user.id {
            userID = user.id
            deletions = PendingDeletionStore(userID: user.id, scope: "Sleep")
        }
        goalHours = min(max(user.sleepGoalHours, Self.goalRange.lowerBound), Self.goalRange.upperBound)
    }

    // MARK: - Öneriler
    var suggestions: [BedtimeSuggestion] {
        SleepPlanner.suggestions(wakeMinutes: settings.targetWakeMinutes, goalHours: goalHours)
    }

    var recommendedBedtimeMinutes: Int {
        SleepPlanner.recommendedBedtimeMinutes(wakeMinutes: settings.targetWakeMinutes, goalHours: goalHours)
    }

    /// Saat seçicilerden gelen dakikaları gerçek tarihlere çevirir. Yatış saati uyanıştan sonraysa önceki güne aittir.
    static func resolve(
        bedtimeMinutes: Int,
        wakeMinutes: Int,
        wakeDay: Date,
        calendar: Calendar = .current
    ) -> (bedtime: Date, wakeTime: Date) {
        let day = calendar.startOfDay(for: wakeDay)
        let wake = calendar.date(byAdding: .minute, value: wakeMinutes, to: day) ?? day
        var bed = calendar.date(byAdding: .minute, value: bedtimeMinutes, to: day) ?? day
        if bed >= wake {
            bed = calendar.date(byAdding: .day, value: -1, to: bed) ?? bed
        }
        return (bed, wake)
    }

    // MARK: - Kaydet / sil
    /// Aynı uyanış gününe ait kayıt varsa günceller (günde tek kayıt).
    @discardableResult
    func save(bedtime: Date, wakeTime: Date, quality: Int, editing: SleepEntry? = nil) throws -> SleepEntry {
        guard let context, let userID else { throw AppError.notAuthenticated }

        let hours = wakeTime.timeIntervalSince(bedtime) / 3600
        guard SleepAnalyzer.isValidDuration(hours) else {
            throw AppError.invalidInput("Uyku süresi 30 dakika ile 20 saat arasında olmalı.")
        }
        guard wakeTime <= Date.now.addingTimeInterval(15 * 60) else {
            throw AppError.invalidInput("Uyanış saati gelecekte olamaz.")
        }
        let clampedQuality = min(max(quality, 1), 5)
        let day = calendar.startOfDay(for: wakeTime)

        let target: SleepEntry
        if let editing {
            target = editing
        } else if let existing = try? context.fetch(FetchDescriptor<SleepEntry>(
            predicate: #Predicate { $0.ownerID == userID && $0.day == day }
        )).first {
            target = existing
        } else {
            target = SleepEntry(ownerID: userID, bedtime: bedtime, wakeTime: wakeTime, quality: clampedQuality, calendar: calendar)
            context.insert(target)
        }

        target.bedtime = bedtime
        target.wakeTime = wakeTime
        target.day = day
        target.quality = clampedQuality
        target.updatedAt = .now
        target.needsSync = true

        try commit()
        Haptics.success()
        scheduleUpload(target)
        return target
    }

    func delete(_ entry: SleepEntry) {
        guard let context, let userID else { return }
        let id = entry.id.uuidString
        context.delete(entry)
        do {
            try commit()
        } catch {
            present(error)
            return
        }
        Haptics.impact(.medium)
        deletions?.add(id)
        scheduleDelete(id: id, userID: userID)
    }

    // MARK: - Ayarlar ve hatırlatıcı
    /// Ayarları kaydeder ve hatırlatıcıyı yeniden kurar. İzin verilmezse hatırlatıcı kapanır, `false` döner.
    @discardableResult
    func applySettings(_ newSettings: SleepSettings) async -> Bool {
        var updated = newSettings
        updated.targetWakeMinutes = ((newSettings.targetWakeMinutes % 1_440) + 1_440) % 1_440
        updated.reminderLeadMinutes = min(max(newSettings.reminderLeadMinutes, 0), 120)
        defer {
            settings = updated
            updated.save(defaults: defaults)
        }

        guard updated.reminderEnabled else {
            await scheduler.cancelSleepReminder()
            return true
        }

        var status = await scheduler.authorizationStatus()
        if status == .notDetermined {
            _ = try? await scheduler.requestAuthorization()
            status = await scheduler.authorizationStatus()
        }
        guard status.allowsNotifications else {
            updated.reminderEnabled = false
            await scheduler.cancelSleepReminder()
            return false
        }

        let bedtime = SleepPlanner.recommendedBedtimeMinutes(wakeMinutes: updated.targetWakeMinutes, goalHours: goalHours)
        let fire = ((bedtime - updated.reminderLeadMinutes) % 1_440 + 1_440) % 1_440
        do {
            try await scheduler.scheduleSleepReminder(
                hour: fire / 60,
                minute: fire % 60,
                bedtimeText: SleepAnalyzer.timeText(minutes: bedtime)
            )
            return true
        } catch {
            updated.reminderEnabled = false
            present(error)
            return false
        }
    }

    // MARK: - Senkronizasyon
    func syncAll() async {
        guard let context, let userID, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let pending = deletions?.ids ?? []
        for id in pending { scheduleDelete(id: id, userID: userID) }

        do {
            let since = calendar.date(byAdding: .day, value: -60, to: calendar.startOfDay(for: .now)) ?? .distantPast
            let remote = try await sync.fetchEntries(userID: userID, since: since)
            let local = try context.fetch(FetchDescriptor<SleepEntry>(predicate: #Predicate { $0.ownerID == userID }))
            var byID = Dictionary(local.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })

            for dto in remote where !pending.contains(dto.id) {
                if let existing = byID[dto.id] {
                    // Bekleyen yerel değişiklik kazanır; yoksa daha yeni olan.
                    if !existing.needsSync, dto.updatedAt > existing.updatedAt {
                        existing.apply(dto)
                    }
                } else {
                    let entry = SleepEntry.make(from: dto, ownerID: userID)
                    context.insert(entry)
                    byID[dto.id] = entry
                }
            }
            try context.save()
            for entry in local where entry.needsSync { scheduleUpload(entry) }
        } catch {
            // Çevrimdışı olabilir; sonra yeniden denenir.
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

    private func scheduleUpload(_ entry: SleepEntry) {
        guard let userID else { return }
        let dto = entry.dto
        let id = entry.id
        let updatedAt = entry.updatedAt
        Task {
            do {
                try await sync.upload(dto, userID: userID)
                markSynced(id: id, updatedAt: updatedAt)
            } catch {
                // needsSync true kalır.
            }
        }
    }

    private func markSynced(id: UUID, updatedAt: Date) {
        guard let context else { return }
        let descriptor = FetchDescriptor<SleepEntry>(predicate: #Predicate { $0.id == id })
        if let entry = try? context.fetch(descriptor).first, entry.updatedAt == updatedAt {
            entry.needsSync = false
            try? context.save()
        }
    }

    private func scheduleDelete(id: String, userID: String) {
        let store = deletions
        Task {
            do {
                try await sync.deleteEntry(id: id, userID: userID)
                store?.remove(id)
            } catch {
                // bekleyen silme olarak kalır.
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = AppError.map(error).errorDescription
        Haptics.error()
    }
}
