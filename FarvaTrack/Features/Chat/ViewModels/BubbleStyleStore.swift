import Foundation
import SwiftData
import Observation
import UIKit

/// Baloncuk stilleri: hazırlar, kullanıcının kendi tasarladıkları (SwiftData + sunucu) ve karşı taraftan
/// indirilenler (sürümüyle önbellekte). Seçilen stil giden mesajlara `bubble {id, version}` olarak eklenir.
@MainActor
@Observable
final class BubbleStyleStore {
    private(set) var myStyles: [BubbleStyle] = []
    private(set) var selectedID: String?
    /// Önbellek değişince artar; baloncuklar yeniden çözümlensin.
    private(set) var revision = 0
    private(set) var isSyncing = false
    var errorMessage: String?

    private let sync: BubbleSyncing
    let files: BubbleFiles
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let makeID: () -> String
    private var context: ModelContext?
    private(set) var userID: String?
    @ObservationIgnored private var inflight: Set<String> = []
    @ObservationIgnored private var cachedOthers: [String: BubbleStyle] = [:]
    @ObservationIgnored private var drawingImages: [String: CGImage] = [:]
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    static let deletionScope = "Bubble"

    init(
        sync: BubbleSyncing = BubbleService(),
        files: BubbleFiles = .live,
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = { .now },
        makeID: @escaping () -> String = { UUID().uuidString.lowercased() }
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
        cachedOthers = [:]
        drawingImages = [:]
        selectedID = defaults.string(forKey: selectionKey(userID))
        reload()
        if let selectedID, style(id: selectedID) == nil { select(nil) }
    }

    private func selectionKey(_ userID: String) -> String { "chat.bubble.selected.\(userID)" }

    private var pendingDeletes: PendingDeletionStore? {
        userID.map { PendingDeletionStore(userID: $0, scope: Self.deletionScope, defaults: defaults) }
    }

    // MARK: Seçim

    var presets: [BubbleStyle] { BubblePresets.all }

    /// Hazır ya da kendi stillerimizden biri.
    func style(id: String) -> BubbleStyle? {
        BubblePresets.style(id: id) ?? myStyles.first { $0.id == id }
    }

    var selectedStyle: BubbleStyle? { selectedID.flatMap(style(id:)) }

    /// Giden mesaja eklenecek başvuru (`nil` = varsayılan baloncuk).
    var selectedRef: ChatBubbleRef? { selectedStyle?.ref }

    func select(_ id: String?) {
        guard let userID else { return }
        if let id, style(id: id) == nil { return }
        selectedID = id
        if let id { defaults.set(id, forKey: selectionKey(userID)) } else { defaults.removeObject(forKey: selectionKey(userID)) }
    }

    // MARK: Çözümleme

    /// Mesajdaki başvurudan stil: hazır → kendi → önbellek (daha yeni sürüm gelene kadar eldeki gösterilir).
    func style(for ref: ChatBubbleRef?, ownerID: String) -> BubbleStyle? {
        guard let ref else { return nil }
        if let preset = BubblePresets.style(id: ref.id) { return preset }
        if ownerID == userID { return myStyles.first { $0.id == ref.id } }
        let key = "\(ownerID)|\(ref.id)"
        if let cached = cachedOthers[key] { return cached }
        guard let record = record(styleOwnerID: ownerID, styleID: ref.id), let style = record.style else { return nil }
        cachedOthers[key] = style
        return style
    }

    /// Önbellekte yoksa ya da mesajdaki sürüm daha yeniyse indirilmeli mi.
    func needsFetch(_ ref: ChatBubbleRef?, ownerID: String) -> Bool {
        guard let ref, !ref.id.hasPrefix(BubblePresets.prefix), ownerID != userID else { return false }
        guard let record = record(styleOwnerID: ownerID, styleID: ref.id) else { return true }
        return record.version < ref.version
    }

    /// Karşı tarafın stilini (ve dosyalarını) bir kez indirip önbelleğe alır.
    func ensure(_ ref: ChatBubbleRef?, ownerID: String) async {
        guard let ref, needsFetch(ref, ownerID: ownerID), let userID else { return }
        let key = "\(ownerID)|\(ref.id)"
        guard !inflight.contains(key) else { return }
        inflight.insert(key)
        defer { inflight.remove(key) }
        do {
            guard let style = try await sync.fetch(styleID: ref.id, ownerID: ownerID) else { return }
            for asset in style.assetIDs {
                let destination = files.url(ownerID: ownerID, styleID: style.id, assetID: asset, isMine: false)
                try? await sync.downloadAsset(styleID: style.id, assetID: asset, ownerID: ownerID, to: destination)
            }
            guard let context, self.userID == userID else { return }
            let json = try style.jsonData()
            if let record = record(styleOwnerID: ownerID, styleID: style.id) {
                guard style.version >= record.version else { return }
                record.version = style.version
                record.json = json
                record.updatedAt = clock()
            } else {
                context.insert(BubbleStyleRecord(cacheOwnerID: userID, styleOwnerID: ownerID, style: style, json: json, needsSync: false, updatedAt: clock()))
            }
            try? context.save()
            cachedOthers[key] = style
            drawingImages = drawingImages.filter { !$0.key.contains("/\(style.id)/") }
            revision += 1
        } catch {
            // Çevrimdışı ya da izin yok: varsayılan baloncuk gösterilir.
        }
    }

    /// Stilin dosyaları (çizim görseli bellekte tutulur).
    func assets(for style: BubbleStyle, ownerID: String) -> BubbleAssets {
        let isMine = ownerID == userID
        var assets = BubbleAssets(drawing: nil)
        for decoration in style.decorations where decoration.kind == .sticker {
            guard let asset = decoration.assetID else { continue }
            let url = files.url(ownerID: ownerID, styleID: style.id, assetID: asset, isMine: isMine)
            if files.exists(url) { assets.stickerURLs[asset] = url }
        }
        if let drawingID = style.drawingAssetID {
            let url = files.url(ownerID: ownerID, styleID: style.id, assetID: drawingID, isMine: isMine)
            if let cached = drawingImages[url.path] {
                assets.drawing = cached
            } else if let image = UIImage(contentsOfFile: url.path)?.cgImage {
                drawingImages[url.path] = image
                assets.drawing = image
            }
            assets.drawingToken = assets.drawing == nil ? "" : drawingID
        }
        return assets
    }

    // MARK: Kendi stillerim

    func reload() {
        guard let context, let userID else {
            myStyles = []
            return
        }
        let descriptor = FetchDescriptor<BubbleStyleRecord>(
            predicate: #Predicate { $0.cacheOwnerID == userID && $0.styleOwnerID == userID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        myStyles = ((try? context.fetch(descriptor)) ?? []).compactMap(\.style)
        revision += 1
    }

    /// Editörden kaydet: yeniyse kimlik alır, varsa sürümü artar. Dosyalar önce cihaza yazılır, sonra arka planda yüklenir.
    /// - Parameters:
    ///   - drawingPNG: Çizimin referans boyuttaki görseli (`nil` = çizim yok).
    ///   - stickerFiles: Yeni eklenen sticker süslemelerinin kaynak PNG'leri (assetID → dosya).
    @discardableResult
    func save(_ draft: BubbleStyle, drawingPNG: Data?, drawingData: Data?, stickerFiles: [String: URL] = [:]) throws -> BubbleStyle {
        guard let context, let userID else { throw AppError.notAuthenticated }
        var style = draft
        let existing = style.isPreset || style.id.isEmpty ? nil : record(styleOwnerID: userID, styleID: style.id)
        if let existing {
            style.version = existing.version + 1
        } else {
            style.id = makeID()
            style.version = 1
        }

        if let drawingPNG {
            let assetID = BubbleAssetID.make()
            try drawingPNG.write(to: files.url(ownerID: userID, styleID: style.id, assetID: assetID, isMine: true), options: .atomic)
            style.drawingAssetID = assetID
        } else {
            style.drawingAssetID = nil
        }
        for (assetID, source) in stickerFiles where BubbleAssetID.isValid(assetID) {
            let destination = files.url(ownerID: userID, styleID: style.id, assetID: assetID, isMine: true)
            if destination != source {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }
        style = style.sanitized()
        let json = try style.jsonData()

        if let existing {
            existing.version = style.version
            existing.json = json
            existing.drawingData = drawingData
            existing.needsSync = true
            existing.updatedAt = clock()
        } else {
            let record = BubbleStyleRecord(cacheOwnerID: userID, styleOwnerID: userID, style: style, json: json, needsSync: true, updatedAt: clock())
            record.drawingData = drawingData
            context.insert(record)
        }
        try context.save()
        drawingImages = [:]
        reload()
        select(style.id)
        scheduleSync()
        return style
    }

    /// Yeniden düzenlemek için PencilKit verisi.
    func drawingData(for styleID: String) -> Data? {
        guard let userID else { return nil }
        return record(styleOwnerID: userID, styleID: styleID)?.drawingData
    }

    /// Kendi stilin düzenleme kaynağı (sticker süslemelerinin cihazdaki dosyaları).
    func stickerFiles(for style: BubbleStyle) -> [String: URL] {
        guard let userID else { return [:] }
        return assets(for: style, ownerID: userID).stickerURLs
    }

    func delete(_ id: String) {
        guard let context, let userID, let record = record(styleOwnerID: userID, styleID: id) else { return }
        // Daha önce yüklendiyse sunucudan da silinir (bağlantı yoksa sonra).
        if !(record.needsSync && record.version == 1) { pendingDeletes?.add(id) }
        context.delete(record)
        try? context.save()
        files.removeStyle(ownerID: userID, styleID: id, isMine: true)
        if selectedID == id { select(nil) }
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

    func waitForPendingSync() async {
        await syncTask?.value
    }

    /// Bekleyen silmeler → yüklemeler (önce dosyalar, sonra belge) → diğer cihazdaki stiller.
    func syncAll() async {
        guard let userID, context != nil, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        for id in pendingDeletes?.ids ?? [] {
            do {
                try await sync.delete(styleID: id, userID: userID)
                pendingDeletes?.remove(id)
            } catch {
                if case .network = AppError.map(error) { return }
            }
        }

        let unsynced = myRecords().filter(\.needsSync).map(\.styleID)
        for id in unsynced {
            guard let record = record(styleOwnerID: userID, styleID: id), let style = record.style else { continue }
            let version = record.version
            do {
                for asset in style.assetIDs {
                    let url = files.url(ownerID: userID, styleID: style.id, assetID: asset, isMine: true)
                    guard files.exists(url) else { continue }
                    try await sync.uploadAsset(url, styleID: style.id, assetID: asset, userID: userID)
                }
                try await sync.save(style, userID: userID)
                if let current = self.record(styleOwnerID: userID, styleID: id), current.version == version {
                    current.needsSync = false
                }
                try? context?.save()
            } catch {
                if case .network = AppError.map(error) { reload(); return }
                errorMessage = AppError.map(error).errorDescription
            }
        }

        // Diğer cihazda eklenen ya da güncellenen kendi stillerim.
        if let remote = try? await sync.fetchAll(userID: userID), let context {
            let deleted = Set(pendingDeletes?.ids ?? [])
            for style in remote where !deleted.contains(style.id) {
                let local = record(styleOwnerID: userID, styleID: style.id)
                if let local, local.needsSync || local.version >= style.version { continue }
                for asset in style.assetIDs {
                    let destination = files.url(ownerID: userID, styleID: style.id, assetID: asset, isMine: true)
                    if !files.exists(destination) {
                        try? await sync.downloadAsset(styleID: style.id, assetID: asset, ownerID: userID, to: destination)
                    }
                }
                guard let json = try? style.jsonData() else { continue }
                if let local {
                    local.version = style.version
                    local.json = json
                    local.updatedAt = clock()
                } else {
                    context.insert(BubbleStyleRecord(cacheOwnerID: userID, styleOwnerID: userID, style: style, json: json, needsSync: false, updatedAt: clock()))
                }
            }
            // Diğer cihazda silinenler.
            let remoteIDs = Set(remote.map(\.id))
            for record in myRecords() where !record.needsSync && !remoteIDs.contains(record.styleID) {
                files.removeStyle(ownerID: userID, styleID: record.styleID, isMine: true)
                context.delete(record)
            }
            try? context.save()
            drawingImages = [:]
        }
        reload()
        if let selectedID, style(id: selectedID) == nil { select(nil) }
    }

    // MARK: Yardımcılar

    private func myRecords() -> [BubbleStyleRecord] {
        guard let context, let userID else { return [] }
        let descriptor = FetchDescriptor<BubbleStyleRecord>(predicate: #Predicate { $0.cacheOwnerID == userID && $0.styleOwnerID == userID })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func record(styleOwnerID: String, styleID: String) -> BubbleStyleRecord? {
        guard let context, let userID else { return nil }
        let key = BubbleStyleRecord.key(cacheOwnerID: userID, styleOwnerID: styleOwnerID, styleID: styleID)
        var descriptor = FetchDescriptor<BubbleStyleRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
