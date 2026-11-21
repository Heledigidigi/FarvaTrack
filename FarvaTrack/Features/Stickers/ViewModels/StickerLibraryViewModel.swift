import Foundation
import SwiftData
import Observation

struct StickerItem: Identifiable, Equatable {
    var id: String
    var fileURL: URL
    var width: Int
    var height: Int
    var isSynced: Bool
}

/// Kişisel sticker kütüphanesi: cihazda SwiftData + dosya, arka planda Storage + Firestore ile iki cihaz arasında senkron.
@MainActor
@Observable
final class StickerLibraryViewModel {
    private(set) var stickers: [StickerItem] = []
    private(set) var isSyncing = false
    var errorMessage: String?

    private let sync: StickerSyncing
    private let files: StickerFiles
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let makeID: () -> String
    private var context: ModelContext?
    private var userID: String?
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    static let deletionScope = "Sticker"

    init(
        sync: StickerSyncing = StickerService(),
        files: StickerFiles = .live,
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = { .now },
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.sync = sync
        self.files = files
        self.defaults = defaults
        self.clock = clock
        self.makeID = makeID
    }

    func configure(context: ModelContext, userID: String) {
        guard self.userID != userID || self.context == nil else { return }
        self.context = context
        self.userID = userID
        reload()
    }

    private var pendingDeletes: PendingDeletionStore? {
        userID.map { PendingDeletionStore(userID: $0, scope: Self.deletionScope, defaults: defaults) }
    }

    // MARK: Okuma

    func reload() {
        guard let context, let userID else {
            stickers = []
            return
        }
        let descriptor = FetchDescriptor<StickerRecord>(
            predicate: #Predicate { $0.ownerID == userID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        stickers = records.compactMap { record in
            guard files.exists(record.id) else { return nil }
            return StickerItem(id: record.id, fileURL: files.url(for: record.id), width: record.width, height: record.height, isSynced: !record.needsSync)
        }
    }

    // MARK: Ekleme / silme

    /// Editörden gelen PNG'yi kütüphaneye ekler; yükleme arka planda.
    @discardableResult
    func add(_ result: StickerRenderResult) throws -> String {
        guard let context, let userID else { throw AppError.notAuthenticated }
        let id = makeID()
        try result.pngData.write(to: files.url(for: id), options: .atomic)
        context.insert(StickerRecord(id: id, ownerID: userID, width: result.width, height: result.height, createdAt: clock()))
        try context.save()
        reload()
        scheduleSync()
        return id
    }

    /// Sohbette gelen bir sticker'ı (PNG dosyası) kütüphaneye kopyalar.
    @discardableResult
    func addPNG(at fileURL: URL, width: Int, height: Int) throws -> String {
        guard let context, let userID else { throw AppError.notAuthenticated }
        let data = try Data(contentsOf: fileURL)
        // Yalnızca gerçek PNG kabul edilir (Storage kuralları da PNG ister).
        guard data.starts(with: [0x89, 0x50, 0x4E, 0x47]) else { throw AppError.invalidInput("Bu dosya bir sticker değil.") }
        let id = makeID()
        try data.write(to: files.url(for: id), options: .atomic)
        context.insert(StickerRecord(id: id, ownerID: userID, width: width, height: height, createdAt: clock()))
        try context.save()
        reload()
        scheduleSync()
        return id
    }

    func delete(_ id: String) {
        guard let context, let record = record(id) else { return }
        // Hiç yüklenmemişse sunucudan silinecek bir şey yok.
        if !record.needsSync { pendingDeletes?.add(id) }
        context.delete(record)
        try? context.save()
        files.remove(id)
        reload()
        scheduleSync()
    }

    // MARK: Senkron

    private func scheduleSync() {
        let previous = syncTask
        syncTask = Task { [weak self] in
            await previous?.value
            await self?.syncAll()
        }
    }

    /// Arka planda başlatılan senkronun bitmesini bekler (testler ve kapanış için).
    func waitForPendingSync() async {
        await syncTask?.value
    }

    /// Bekleyen silmeler → bekleyen yüklemeler → diğer cihazda eklenenleri indir / silinenleri kaldır.
    func syncAll() async {
        guard let context, let userID, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        for id in pendingDeletes?.ids ?? [] {
            do {
                try await sync.delete(sticker: id, storagePath: StickerPath.storage(userID: userID, stickerID: id), userID: userID)
                pendingDeletes?.remove(id)
            } catch {
                if case .network = AppError.map(error) { return }
            }
        }

        let unsynced = ((try? context.fetch(FetchDescriptor<StickerRecord>(
            predicate: #Predicate { $0.ownerID == userID && $0.needsSync }
        ))) ?? [])
        for record in unsynced {
            let dto = record.dto
            do {
                try await sync.upload(pngAt: files.url(for: dto.id), sticker: dto, userID: userID)
                self.record(dto.id)?.needsSync = false
                try? context.save()
            } catch {
                if case .network = AppError.map(error) { reload(); return }
                errorMessage = AppError.map(error).errorDescription
            }
        }

        do {
            let remote = try await sync.fetchAll(userID: userID)
            let remoteIDs = Set(remote.map(\.id))
            let deleted = pendingDeletes?.ids ?? []
            for dto in remote where record(dto.id) == nil && !deleted.contains(dto.id) {
                do {
                    try await sync.download(sticker: dto, to: files.url(for: dto.id))
                    let record = StickerRecord(id: dto.id, ownerID: userID, width: dto.width, height: dto.height, createdAt: dto.createdAt, needsSync: false)
                    context.insert(record)
                } catch {
                    continue
                }
            }
            // Diğer cihazda silinenler (yüklenmiş ama artık sunucuda olmayanlar).
            let local = (try? context.fetch(FetchDescriptor<StickerRecord>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
            for record in local where !record.needsSync && !remoteIDs.contains(record.id) {
                files.remove(record.id)
                context.delete(record)
            }
            try? context.save()
        } catch {
            // Çevrimdışı: yerel kütüphane gösterilir.
        }
        reload()
    }

    private func record(_ id: String) -> StickerRecord? {
        guard let context else { return nil }
        var descriptor = FetchDescriptor<StickerRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
