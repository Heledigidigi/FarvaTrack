import Foundation
import Observation
import SwiftData
import UserNotifications

/// Widget deposuna erişim (testte taklit edilebilsin diye protokol).
protocol WaterWidgetStoring {
    func pendingAdds() -> [PendingWaterAdd]
    func removePending(ids: [UUID])
    func publish(_ snapshot: WaterSnapshot)
    /// Widget'taki "Geri al" ile silinmesi istenen, uygulamaya çoktan aktarılmış kayıtlar.
    func pendingUndos() -> [UUID]
    func removeUndos(ids: [UUID])
}

extension WaterWidgetStoring {
    func pendingUndos() -> [UUID] { [] }
    func removeUndos(ids: [UUID]) {}
}

struct SharedStoreWaterBridge: WaterWidgetStoring {
    func pendingAdds() -> [PendingWaterAdd] { SharedStore.pendingWaterAdds() }
    func removePending(ids: [UUID]) { SharedStore.removePendingWater(ids: ids) }
    func publish(_ snapshot: WaterSnapshot) { SharedStore.saveWater(snapshot) }
    func pendingUndos() -> [UUID] { SharedStore.pendingWaterUndos() }
    func removeUndos(ids: [UUID]) { SharedStore.removePendingWaterUndos(ids: ids) }
}

struct WaterUndoToken: Equatable {
    let entryID: UUID
    let amountMl: Int
}

@MainActor
@Observable
final class WaterViewModel {
    static let presets = [150, 200, 330, 500]
    static let customRange = 50...SharedStore.maxSingleWaterMl
    static let goalRange = 500...6_000

    var errorMessage: String?
    private(set) var goalMl = Constants.Defaults.waterGoalMl
    private(set) var undoToken: WaterUndoToken?
    private(set) var reminderSettings: WaterReminderSettings
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var isSyncing = false

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var deletions: PendingDeletionStore?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private let sync: WaterSyncing
    @ObservationIgnored private let widget: WaterWidgetStoring
    @ObservationIgnored private let scheduler: NotificationScheduling
    @ObservationIgnored private let defaults: UserDefaults

    init(
        sync: WaterSyncing = FirestoreWaterSyncService(),
        widget: WaterWidgetStoring = SharedStoreWaterBridge(),
        scheduler: NotificationScheduling = NotificationManager.shared,
        defaults: UserDefaults = .standard
    ) {
        self.sync = sync
        self.widget = widget
        self.scheduler = scheduler
        self.defaults = defaults
        self.reminderSettings = WaterReminderSettings.load(defaults: defaults)
    }

    var currentUserID: String? { userID }

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func configure(context: ModelContext, user: AppUser) {
        self.context = context
        if userID != user.id {
            userID = user.id
            deletions = PendingDeletionStore(userID: user.id, scope: "Water")
        }
        let newGoal = min(max(user.dailyWaterGoalMl, Self.goalRange.lowerBound), Self.goalRange.upperBound)
        let changed = newGoal != goalMl
        goalMl = newGoal
        if changed { publishWidgetSnapshot() }
    }

    func reloadReminderSettings() {
        reminderSettings = WaterReminderSettings.load(defaults: defaults)
    }

    // MARK: - Ekleme, silme, geri alma
    @discardableResult
    func add(amountMl: Int, date: Date = .now) throws -> WaterEntry {
        guard let context, let userID else { throw AppError.notAuthenticated }
        guard Self.customRange.contains(amountMl) else {
            throw AppError.invalidInput("Miktar \(Self.customRange.lowerBound)–\(Self.customRange.upperBound) ml arasında olmalı.")
        }
        guard todayTotal() + amountMl <= SharedStore.maxDailyWaterMl else {
            throw AppError.invalidInput("Günlük en fazla \(SharedStore.maxDailyWaterMl.formatted()) ml girebilirsin. Yanlış girdiysen son kaydı silebilirsin.")
        }

        let entry = WaterEntry(ownerID: userID, date: date, amountMl: amountMl)
        context.insert(entry)
        try commit()

        Haptics.impact(.light)
        showUndo(WaterUndoToken(entryID: entry.id, amountMl: amountMl))
        publishWidgetSnapshot()
        scheduleUpload(entry)
        return entry
    }

    func delete(_ entry: WaterEntry) {
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
        publishWidgetSnapshot()
    }

    func undo() {
        guard let context, let token = undoToken else { return }
        let id = token.entryID
        let descriptor = FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.id == id })
        undoToken = nil
        undoTask?.cancel()
        if let entry = try? context.fetch(descriptor).first {
            delete(entry)
        }
    }

    private func showUndo(_ token: WaterUndoToken) {
        undoTask?.cancel()
        undoToken = token
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.undoToken = nil
        }
    }

    // MARK: - Uygulama öne gelince
    func handleForeground() async {
        importWidgetAdds()
        publishWidgetSnapshot()
        notificationStatus = await scheduler.authorizationStatus()
        if reminderSettings.isEnabled, notificationStatus == .denied {
            reminderSettings.isEnabled = false      // bildirim izni sistemden kapatılmış
            reminderSettings.save(defaults: defaults)
        }
        await syncAll()
        publishWidgetSnapshot()
    }

    /// Widget'tan eklenen kayıtları SwiftData'ya aktarır. Her kayıt kendi UUID'siyle geldiği için tekrar çalışması güvenlidir.
    func importWidgetAdds() {
        guard let context, let userID else { return }
        applyWidgetUndos()
        let pending = widget.pendingAdds()
        guard !pending.isEmpty else { return }

        let ids = pending.map(\.id)
        let existing = (try? context.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let known = Set(existing.map(\.id))

        var inserted: [WaterEntry] = []
        for add in pending where !known.contains(add.id) {
            let entry = WaterEntry(id: add.id, ownerID: userID, date: add.date, amountMl: add.amountMl)
            context.insert(entry)
            inserted.append(entry)
        }
        guard (try? context.save()) != nil else { return }

        widget.removePending(ids: ids)
        inserted.forEach(scheduleUpload)
        // Widget'tan gelen eklemeler aktarılınca widget toplamı uygulamanın kayıtlarıyla eşitlenir.
        publishWidgetSnapshot()
    }

    /// Widget'tan geri alınan ama uygulamaya çoktan aktarılmış kayıtları siler.
    private func applyWidgetUndos() {
        guard let context else { return }
        let ids = widget.pendingUndos()
        guard !ids.isEmpty else { return }
        let entries = (try? context.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        for entry in entries { delete(entry) }
        widget.removeUndos(ids: ids)
    }

    // MARK: - Hatırlatıcılar
    /// Ayarları uygular. Bildirim izni yoksa ister; verilmezse hatırlatıcı kapalı kalır ve `false` döner.
    @discardableResult
    func applyReminders(_ settings: WaterReminderSettings) async -> Bool {
        var updated = settings
        defer {
            reminderSettings = updated
            updated.save(defaults: defaults)
        }

        guard settings.isEnabled else {
            await scheduler.cancelWaterReminders()
            return true
        }

        var status = await scheduler.authorizationStatus()
        if status == .notDetermined {
            _ = try? await scheduler.requestAuthorization()
            status = await scheduler.authorizationStatus()
        }
        notificationStatus = status

        guard status.allowsNotifications else {
            updated.isEnabled = false
            await scheduler.cancelWaterReminders()
            return false
        }

        do {
            try await scheduler.scheduleWaterReminders(settings: settings)
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

        let pending = deletions?.ids ?? []
        for id in pending { scheduleDelete(id: id, userID: userID) }

        do {
            let since = Calendar.current.date(byAdding: .day, value: -30, to: Date.now.startOfDay) ?? .distantPast
            let remote = try await sync.fetchEntries(userID: userID, since: since)
            let local = try context.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.ownerID == userID }))
            let localIDs = Set(local.map(\.id))

            // Su kayıtları düzenlenmez; yalnızca eksik olanları ekleriz.
            for dto in remote where !pending.contains(dto.id) {
                guard let uuid = UUID(uuidString: dto.id), !localIDs.contains(uuid) else { continue }
                context.insert(WaterEntry.make(from: dto, ownerID: userID))
            }
            try context.save()
            for entry in local where entry.needsSync { scheduleUpload(entry) }
        } catch {
            // Çevrimdışı olabilir; sonraki açılışta tekrar denenir.
        }
    }

    // MARK: - Hesaplamalar
    /// Son `days` günün (bugün dahil) günlük toplamları, eskiden yeniye.
    nonisolated static func dailyTotals(entries: [WaterEntry], endingOn end: Date = .now, days: Int = 7, calendar: Calendar = .current) -> [DailyValue] {
        let today = calendar.startOfDay(for: end)
        let dates = (0..<days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        var totals: [Date: Int] = [:]
        for entry in entries {
            totals[calendar.startOfDay(for: entry.date), default: 0] += entry.amountMl
        }
        return dates.map { DailyValue(date: $0, value: Double(totals[$0] ?? 0)) }
    }

    private func todayTotal() -> Int {
        guard let context, let userID else { return 0 }
        let start = Date.now.startOfDay
        let end = Date.now.endOfDay
        let entries = (try? context.fetch(FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.ownerID == userID && $0.date >= start && $0.date <= end }
        ))) ?? []
        return entries.reduce(0) { $0 + $1.amountMl }
    }

    private func publishWidgetSnapshot() {
        guard userID != nil else { return }
        widget.publish(WaterSnapshot(totalMl: todayTotal(), goalMl: goalMl, updatedAt: .now))
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

    private func scheduleUpload(_ entry: WaterEntry) {
        guard let userID else { return }
        let dto = entry.dto
        let id = entry.id
        let updatedAt = entry.updatedAt

        Task {
            do {
                try await sync.upload(dto, userID: userID)
                markSynced(id: id, updatedAt: updatedAt)
            } catch {
                // needsSync true kalır; sonraki syncAll'da yeniden denenir.
            }
        }
    }

    private func markSynced(id: UUID, updatedAt: Date) {
        guard let context else { return }
        let descriptor = FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.id == id })
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
                // "bekleyen silme" olarak kalır.
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = AppError.map(error).errorDescription
        Haptics.error()
    }
}
