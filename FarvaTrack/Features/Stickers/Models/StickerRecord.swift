import Foundation
import SwiftData

/// Kişisel sticker kütüphanesindeki bir sticker. PNG dosyası cihazda (`StickerFiles`), kopyası Storage'da.
@Model
final class StickerRecord {
    @Attribute(.unique) var id: String
    var ownerID: String
    var storagePath: String
    var width: Int
    var height: Int
    var createdAt: Date
    var updatedAt: Date
    /// Henüz sunucuya yüklenmedi.
    var needsSync: Bool

    init(id: String, ownerID: String, width: Int, height: Int, createdAt: Date, needsSync: Bool = true) {
        self.id = id
        self.ownerID = ownerID
        self.storagePath = StickerPath.storage(userID: ownerID, stickerID: id)
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.needsSync = needsSync
    }

    var dto: StickerDTO {
        StickerDTO(id: id, storagePath: storagePath, width: width, height: height, createdAt: createdAt, updatedAt: updatedAt)
    }
}

/// Sticker PNG'leri Application Support'ta tutulur (önbellek değil, kütüphanenin kendisi).
struct StickerFiles {
    let root: URL

    static let live = StickerFiles(
        root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stickers", isDirectory: true)
    )

    func url(for id: String) -> URL {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(id).png")
    }

    func exists(_ id: String) -> Bool { FileManager.default.fileExists(atPath: url(for: id).path) }

    func remove(_ id: String) { try? FileManager.default.removeItem(at: url(for: id)) }

    func removeAll() { try? FileManager.default.removeItem(at: root) }
}
