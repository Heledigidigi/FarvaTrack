import Foundation
import Observation
import SwiftData

/// Widget deposuna erişim (testte taklit edilir).
protocol WasteWidgetStoring {
    func pendingTaps() -> [PendingWasteTap]
    func removePending(ids: [UUID])
    func publish(_ snapshot: WasteSnapshot)
}

struct SharedStoreWasteBridge: WasteWidgetStoring {
    func pendingTaps() -> [PendingWasteTap] { SharedStore.pendingWasteTaps() }
    func removePending(ids: [UUID]) { SharedStore.removePendingWaste(ids: ids) }
    func publish(_ snapshot: WasteSnapshot) { SharedStore.saveWaste(snapshot) }
}

@MainActor
@Observable
final class WasteViewModel {
    var errorMessage: String?
    private(set) var lastAddedID: UUID?
    private(set) var isSyncing = false

    // Yönetici görünümü
    private(set) var adminUsers: [WasteUserSummary] = []
    private(set) var isLoadingAdmin = false
    var adminError: String?

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var deletions: PendingDeletionStore?
    /// Günlük toplamı sunucuya henüz yazılamamış günler (`yyyy-MM-dd`).
    @ObservationIgnored private var dirtyDays: PendingDeletionStore?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private let sync: WasteSyncing
    @ObservationIgnored private let widget: WasteWidgetStoring
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let defaults: UserDefaults

    init(
        sync: WasteSyncing = FirestoreWasteSyncService(),
        widget: WasteWidgetStoring = SharedStoreWasteBridge(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        self.sync = sync
        self.widget = widget
        self.calendar = calendar
        self.defaults = defaults
    }

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func configure(context: ModelContext, user: AppUser) {
        self.context = context
        guard userID != user.id else { return }
        userID = user.id
        deletions = PendingDeletionStore(userID: user.id, scope: "Waste", defaults: defaults)
        dirtyDays = PendingDeletionStore(userID: user.id, scope: "WasteDaily", defaults: defaults)
        adminUsers = []
    }

    // MARK: - Sayaç
    @discardableResult
    func add(at date: Date = .now) throws -> WasteEntry {
        guard let context, let userID else { throw AppError.notAuthenticated }
        guard count(on: date) < SharedStore.maxDailyWasteCount else {
            throw AppError.invalidInput("Bir günde en fazla \(SharedStore.maxDailyWasteCount) kayıt girilebilir. Yanlış girdiysen son kaydı silebilirsin.")
        }
        let entry = WasteEntry(ownerID: userID, date: date)
        context.insert(entry)
        try commit()

        Haptics.impact(.medium)
        showUndo(entry.id)
        publishWidgetSnapshot()
        upload(entry)
        markDirty(date)
        return entry
    }

    func delete(_ entry: WasteEntry) {
        guard let context, let userID else { return }
        let id = entry.id.uuidString
        let date = entry.date
        context.delete(entry)
        do {
            try commit()
        } catch {
            present(error)
            return
        }
        Haptics.impact(.light)
        deletions?.add(id)
        deleteRemote(id: id, userID: userID)
        markDirty(date)
        publishWidgetSnapshot()
    }

    func undo() {
        guard let context, let id = lastAddedID else { return }
        lastAddedID = nil
        undoTask?.cancel()
        let descriptor = FetchDescriptor<WasteEntry>(predicate: #Predicate { $0.id == id })
        if let entry = try? context.fetch(descriptor).first { delete(entry) }
    }

    private func showUndo(_ id: UUID) {
        undoTask?.cancel()
        lastAddedID = id
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.lastAddedID = nil
        }
    }

    // MARK: - Uygulama öne gelince
    func handleForeground() async {
        importWidgetTaps()
        publishWidgetSnapshot()
        await syncAll()
        publishWidgetSnapshot()
    }

    /// Widget dokunuşlarını SwiftData'ya aktarır (UUID sayesinde tekrar çalışması güvenli).
    func importWidgetTaps() {
        guard let context, let userID else { return }
        let pending = widget.pendingTaps()
        guard !pending.isEmpty else { return }

        let ids = pending.map(\.id)
        let existing = (try? context.fetch(FetchDescriptor<WasteEntry>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let known = Set(existing.map(\.id))

        var inserted: [WasteEntry] = []
        for tap in pending where !known.contains(tap.id) {
            let entry = WasteEntry(id: tap.id, ownerID: userID, date: tap.date)
            context.insert(entry)
            inserted.append(entry)
        }
        guard (try? context.save()) != nil else { return }
        widget.removePending(ids: ids)
        for entry in inserted {
            upload(entry)
            markDirty(entry.date)
        }
    }

    // MARK: - Senkronizasyon
    func syncAll() async {
        guard let context, let userID, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let pending = deletions?.ids ?? []
        for id in pending { deleteRemote(id: id, userID: userID) }

        do {
            let since = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: .now)) ?? .distantPast
            let remote = try await sync.fetchEntries(userID: userID, since: since)
            let local = try context.fetch(FetchDescriptor<WasteEntry>(predicate: #Predicate { $0.ownerID == userID }))
            let localIDs = Set(local.map(\.id))
            for dto in remote where !pending.contains(dto.id) {
                guard let uuid = UUID(uuidString: dto.id), !localIDs.contains(uuid) else { continue }
                context.insert(WasteEntry.make(from: dto, ownerID: userID))
            }
            try context.save()
            for entry in local where entry.needsSync { upload(entry) }
        } catch {
            // Çevrimdışı olabilir.
        }

        await flushDirtyDays()
    }

    /// Bekleyen günlerin toplamını yerel kayıtlardan hesaplayıp yazar.
    func flushDirtyDays() async {
        guard let userID, let store = dirtyDays else { return }
        for key in store.ids {
            guard let day = WasteAnalyzer.day(fromKey: key, calendar: calendar) else {
                store.remove(key)
                continue
            }
            let dto = WasteDailyDTO(id: key, day: day, count: count(on: day), updatedAt: .now)
            do {
                try await sync.uploadDaily(dto, userID: userID)
                store.remove(key)
            } catch {
                // Sonraki açılışta yeniden denenir.
            }
        }
    }

    // MARK: - Yönetici
    func loadAdminOverview(days: Int = 90) async {
        guard !isLoadingAdmin else { return }
        isLoadingAdmin = true
        defer { isLoadingAdmin = false }
        let since = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now)) ?? .distantPast
        do {
            adminUsers = try await sync.fetchAllUsersDaily(since: since)
            adminError = nil
        } catch {
            adminError = AppError.map(error).errorDescription
        }
    }

    // MARK: - Yardımcılar
    func count(on date: Date) -> Int {
        guard let context, let userID else { return 0 }
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        let descriptor = FetchDescriptor<WasteEntry>(
            predicate: #Predicate { $0.ownerID == userID && $0.date >= start && $0.date < end }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    private func markDirty(_ date: Date) {
        dirtyDays?.add(WasteAnalyzer.dayKey(date, calendar: calendar))
        Task { await flushDirtyDays() }
    }

    private func publishWidgetSnapshot() {
        guard userID != nil else { return }
        widget.publish(WasteSnapshot(count: count(on: .now), updatedAt: .now))
    }

    private func commit() throws {
        guard let context else { throw AppError.notAuthenticated }
        do {
            try context.save()
        } catch {
            throw AppError.unknown(error.localizedDescription)
        }
    }

    private func upload(_ entry: WasteEntry) {
        guard let userID else { return }
        let dto = entry.dto
        let id = entry.id
        Task {
            do {
                try await sync.uploadEntry(dto, userID: userID)
                markSynced(id: id)
            } catch {}
        }
    }

    private func markSynced(id: UUID) {
        guard let context else { return }
        let descriptor = FetchDescriptor<WasteEntry>(predicate: #Predicate { $0.id == id })
        if let entry = try? context.fetch(descriptor).first {
            entry.needsSync = false
            try? context.save()
        }
    }

    private func deleteRemote(id: String, userID: String) {
        let store = deletions
        Task {
            do {
                try await sync.deleteEntry(id: id, userID: userID)
                store?.remove(id)
            } catch {}
        }
    }

    private func present(_ error: Error) {
        errorMessage = AppError.map(error).errorDescription
        Haptics.error()
    }
}
