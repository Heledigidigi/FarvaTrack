import Foundation
import SwiftData

/// Sohbet üstü sticker yerleştirmesinin cihazdaki kopyası. Bekleyen yerel değişiklik (`needsSync`) sunucudan gelene karşı kazanır.
@Model
final class ChatPlacementRecord {
    /// `ownerID|placementID`
    @Attribute(.unique) var key: String
    var placementID: String
    var ownerID: String
    var chatID: String
    var senderID: String
    var anchorMessageID: String
    var x: Double
    var y: Double
    var scale: Double
    var rotation: Double
    var z: Double
    var stickerData: Data
    var createdAt: Date
    var updatedAt: Date
    /// Sunucuya yazılmayı bekleyen değişiklik var.
    var needsSync: Bool
    /// Silinecek (sunucudan silinince kayıt da kalkar).
    var pendingDelete: Bool
    /// Belge sunucuda var.
    var isOnServer: Bool
    /// PNG Storage'a yüklendi.
    var fileUploaded: Bool
    /// Gönderen cihazda yüklenmeyi bekleyen PNG (`outgoing` klasöründe).
    var localFileName: String?

    init(dto: ChatPlacementDTO, ownerID: String, chatID: String, needsSync: Bool, isOnServer: Bool) {
        self.key = ChatPlacementRecord.key(ownerID: ownerID, placementID: dto.id)
        self.placementID = dto.id
        self.ownerID = ownerID
        self.chatID = chatID
        self.senderID = dto.senderID
        self.anchorMessageID = dto.anchorMessageID
        self.x = dto.x
        self.y = dto.y
        self.scale = dto.scale
        self.rotation = dto.rotation
        self.z = dto.z
        self.stickerData = (try? JSONEncoder().encode(dto.sticker)) ?? Data()
        self.createdAt = dto.createdAt
        self.updatedAt = dto.updatedAt
        self.needsSync = needsSync
        self.pendingDelete = false
        self.isOnServer = isOnServer
        self.fileUploaded = isOnServer
        self.localFileName = nil
    }

    static func key(ownerID: String, placementID: String) -> String { "\(ownerID)|\(placementID)" }

    var sticker: ChatSticker {
        (try? JSONDecoder().decode(ChatSticker.self, from: stickerData)) ?? ChatSticker(path: "", width: 1, height: 1)
    }

    var dto: ChatPlacementDTO {
        ChatPlacementDTO(
            id: placementID, senderID: senderID, anchorMessageID: anchorMessageID,
            x: x, y: y, scale: scale, rotation: rotation, z: z,
            sticker: sticker, createdAt: createdAt, updatedAt: updatedAt
        )
    }

    func apply(remote dto: ChatPlacementDTO) {
        senderID = dto.senderID
        anchorMessageID = dto.anchorMessageID
        x = dto.x
        y = dto.y
        scale = dto.scale
        rotation = dto.rotation
        z = dto.z
        stickerData = (try? JSONEncoder().encode(dto.sticker)) ?? stickerData
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        isOnServer = true
        fileUploaded = true
    }
}

/// Ekranda gösterilen yerleştirme.
struct ChatPlacementItem: Identifiable, Equatable {
    var placement: ChatPlacementDTO
    var isMine: Bool
    var localImageURL: URL?
    var isSyncing: Bool

    var id: String { placement.id }
}

/// Veri dışa aktarma için.
struct ChatPlacementExport: Codable, Equatable {
    var id: String
    var chatID: String
    var senderID: String
    var anchorMessageID: String
    var x: Double
    var y: Double
    var scale: Double
    var rotation: Double
    var stickerPath: String
    var createdAt: Date

    init(record: ChatPlacementRecord) {
        id = record.placementID
        chatID = record.chatID
        senderID = record.senderID
        anchorMessageID = record.anchorMessageID
        x = record.x
        y = record.y
        scale = record.scale
        rotation = record.rotation
        stickerPath = record.sticker.path
        createdAt = record.createdAt
    }
}
