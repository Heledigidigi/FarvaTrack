import Foundation
import SwiftData

/// Baloncuk stili önbelleği: hem kullanıcının kendi stilleri hem karşı taraftan indirilenler.
@Model
final class BubbleStyleRecord {
    /// `cacheOwnerID|styleOwnerID|styleID`
    @Attribute(.unique) var key: String
    /// Cihazdaki oturum sahibi.
    var cacheOwnerID: String
    /// Stili tasarlayan (mesajı gönderen).
    var styleOwnerID: String
    var styleID: String
    var version: Int
    /// `BubbleStyle` JSON'u.
    var json: Data
    /// PencilKit çizim verisi (yalnızca kendi stillerimizde, yeniden düzenlemek için).
    var drawingData: Data?
    var needsSync: Bool
    var updatedAt: Date

    init(cacheOwnerID: String, styleOwnerID: String, style: BubbleStyle, json: Data, needsSync: Bool, updatedAt: Date) {
        self.key = BubbleStyleRecord.key(cacheOwnerID: cacheOwnerID, styleOwnerID: styleOwnerID, styleID: style.id)
        self.cacheOwnerID = cacheOwnerID
        self.styleOwnerID = styleOwnerID
        self.styleID = style.id
        self.version = style.version
        self.json = json
        self.drawingData = nil
        self.needsSync = needsSync
        self.updatedAt = updatedAt
    }

    static func key(cacheOwnerID: String, styleOwnerID: String, styleID: String) -> String {
        "\(cacheOwnerID)|\(styleOwnerID)|\(styleID)"
    }

    var style: BubbleStyle? { try? BubbleStyle.decode(json: json) }
}

/// Stil dosyaları: kendi stillerimiz Application Support'ta, indirilenler Caches'ta.
struct BubbleFiles {
    let persistentRoot: URL
    let cacheRoot: URL

    static let live: BubbleFiles = {
        let fm = FileManager.default
        return BubbleFiles(
            persistentRoot: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bubbles", isDirectory: true),
            cacheRoot: fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Bubbles", isDirectory: true)
        )
    }()

    func url(ownerID: String, styleID: String, assetID: String, isMine: Bool) -> URL {
        let folder = (isMine ? persistentRoot : cacheRoot)
            .appendingPathComponent(ownerID, isDirectory: true)
            .appendingPathComponent(styleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(assetID).png")
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func removeStyle(ownerID: String, styleID: String, isMine: Bool) {
        let folder = (isMine ? persistentRoot : cacheRoot).appendingPathComponent(ownerID).appendingPathComponent(styleID)
        try? FileManager.default.removeItem(at: folder)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: persistentRoot)
        try? FileManager.default.removeItem(at: cacheRoot)
    }
}

/// Veri dışa aktarma için.
struct BubbleStyleExport: Codable, Equatable {
    var id: String
    var version: Int
    var json: String

    init(record: BubbleStyleRecord) {
        id = record.styleID
        version = record.version
        json = String(data: record.json, encoding: .utf8) ?? ""
    }
}
