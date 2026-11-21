import Foundation
import CoreGraphics

// MARK: - Sticker mesajı

/// `type: sticker` mesajının dosyası: gönderenin kütüphanesindeki PNG, sohbet klasörüne kopyalanır
/// (kişisel kütüphane yalnızca sahibine açık olduğundan karşı taraf oradan okuyamaz).
struct ChatSticker: Codable, Equatable, Hashable {
    var path: String
    var width: Int
    var height: Int

    var aspectRatio: Double {
        guard width > 0, height > 0 else { return 1 }
        return Double(width) / Double(height)
    }
}

enum ChatStickerPath {
    static let fileName = "sticker.png"
    static let fileExtension = "png"
    static let contentType = "image/png"

    /// `chats/{chatId}/media/{messageId|placementId}/sticker.png`
    static func file(chatID: String, itemID: String) -> String {
        ChatMediaPath.folder(chatID: chatID, messageID: itemID) + "/" + fileName
    }
}

enum ChatStickerFields {
    static func encode(_ sticker: ChatSticker) -> [String: Any] {
        ["path": sticker.path, "width": sticker.width, "height": sticker.height]
    }

    static func decode(_ value: Any?) -> ChatSticker? {
        guard let map = value as? [String: Any], let path = map["path"] as? String else { return nil }
        return ChatSticker(
            path: path,
            width: (map["width"] as? NSNumber)?.intValue ?? 0,
            height: (map["height"] as? NSNumber)?.intValue ?? 0
        )
    }
}

// MARK: - Serbest yerleştirme

/// `chats/{chatId}/placements/{id}`: sohbetin üstüne bırakılan sticker.
/// Konum en yakın mesaja bağlıdır; ekran boyu farklı iki cihazda da aynı mesajın yanında görünür.
struct ChatPlacementDTO: Equatable, Identifiable {
    var id: String
    var senderID: String
    var anchorMessageID: String
    /// Merkezin yatay konumu, sohbet genişliğine oranla (0…1).
    var x: Double
    /// Merkezin, bağlı mesajın dikey ortasına göre uzaklığı (pt; aşağı pozitif).
    var y: Double
    var scale: Double
    /// Radyan.
    var rotation: Double
    /// Katman sırası: büyük olan üstte ("öne al / arkaya al").
    var z: Double
    var sticker: ChatSticker
    var createdAt: Date
    var updatedAt: Date
}

enum ChatPlacementFields {
    static func encode(_ placement: ChatPlacementDTO) -> [String: Any] {
        [
            "senderId": placement.senderID,
            "anchorMessageId": placement.anchorMessageID,
            "x": placement.x,
            "y": placement.y,
            "scale": placement.scale,
            "rotation": placement.rotation,
            "z": placement.z,
            "sticker": ChatStickerFields.encode(placement.sticker)
        ]
    }

    /// `createdAt` / `updatedAt` Firestore zaman damgası olduğundan çağıran taraf çözer.
    static func decode(id: String, data: [String: Any], createdAt: Date, updatedAt: Date) -> ChatPlacementDTO? {
        guard let sender = data["senderId"] as? String,
              let anchor = data["anchorMessageId"] as? String,
              let sticker = ChatStickerFields.decode(data["sticker"]) else { return nil }
        func number(_ key: String, _ fallback: Double) -> Double { (data[key] as? NSNumber)?.doubleValue ?? fallback }
        return ChatPlacementDTO(
            id: id, senderID: sender, anchorMessageID: anchor,
            x: PlacementGeometry.clampX(number("x", 0.5)),
            y: number("y", 0),
            scale: PlacementGeometry.clampScale(number("scale", 1)),
            rotation: PlacementGeometry.normalizedRotation(number("rotation", 0)),
            z: number("z", createdAt.timeIntervalSince1970),
            sticker: sticker, createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

// MARK: - Koordinat dönüşümü

/// Sürükle / büyüt / döndür sırasında sticker'ın sohbet içeriğindeki hali.
struct PlacementTransform: Equatable {
    /// Sohbet içeriği koordinatlarında merkez (kaydırma içeriği; mesajlarla birlikte kayar).
    var center: CGPoint
    var scale: Double
    var rotation: Double

    /// Hareketler başladığındaki hale göre: sürükleme ötelemesi, iki parmak büyütme oranı ve dönüş açısı.
    func applying(translation: CGSize = .zero, magnification: Double = 1, rotation delta: Double = 0) -> PlacementTransform {
        PlacementTransform(
            center: CGPoint(x: center.x + translation.width, y: center.y + translation.height),
            scale: PlacementGeometry.clampScale(scale * magnification),
            rotation: PlacementGeometry.normalizedRotation(rotation + delta)
        )
    }
}

enum PlacementGeometry {
    /// Ölçek 1'de sticker genişliği = sohbet genişliğinin bu oranı (her ekranda aynı oranda görünür).
    static let baseWidthRatio: Double = 0.32
    static let scaleRange: ClosedRange<Double> = 0.3...3

    static func clampScale(_ scale: Double) -> Double {
        guard scale.isFinite else { return 1 }
        return min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
    }

    static func clampX(_ x: Double) -> Double {
        guard x.isFinite else { return 0.5 }
        return min(max(x, 0), 1)
    }

    /// -π…π aralığına getirir.
    static func normalizedRotation(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi { value -= 2 * .pi }
        if value < -.pi { value += 2 * .pi }
        return value
    }

    /// Ekranda çizilecek boyut (döndürmeden önce).
    static func displaySize(containerWidth: CGFloat, scale: Double, aspectRatio: Double) -> CGSize {
        let width = containerWidth * CGFloat(baseWidthRatio * clampScale(scale))
        let ratio = aspectRatio > 0 && aspectRatio.isFinite ? aspectRatio : 1
        return CGSize(width: width, height: width / CGFloat(ratio))
    }

    /// Merkeze en yakın mesaj: merkez mesajın içindeyse uzaklık 0, değilse üst/alt kenara dikey uzaklık.
    /// Eşitlikte dikey ortası daha yakın olan seçilir.
    static func nearestAnchor(to center: CGPoint, frames: [String: CGRect]) -> String? {
        frames.min { lhs, rhs in
            let left = verticalDistance(center.y, lhs.value)
            let right = verticalDistance(center.y, rhs.value)
            if left != right { return left < right }
            let leftMid = abs(center.y - lhs.value.midY)
            let rightMid = abs(center.y - rhs.value.midY)
            if leftMid != rightMid { return leftMid < rightMid }
            return lhs.key < rhs.key
        }?.key
    }

    static func verticalDistance(_ y: CGFloat, _ frame: CGRect) -> CGFloat {
        if y < frame.minY { return frame.minY - y }
        if y > frame.maxY { return y - frame.maxY }
        return 0
    }

    /// İçerik koordinatındaki merkez → kaydedilecek bağlı konum.
    static func anchored(center: CGPoint, containerWidth: CGFloat, frames: [String: CGRect]) -> (anchorID: String, x: Double, y: Double)? {
        guard containerWidth > 0, let id = nearestAnchor(to: center, frames: frames), let frame = frames[id] else { return nil }
        return (id, clampX(Double(center.x / containerWidth)), Double(center.y - frame.midY))
    }

    /// Kaydedilmiş bağlı konum → içerik koordinatındaki merkez (bağlı mesaj ekranda yoksa `nil`).
    static func center(x: Double, y: Double, anchorFrame: CGRect?, containerWidth: CGFloat) -> CGPoint? {
        guard let anchorFrame else { return nil }
        return CGPoint(x: CGFloat(clampX(x)) * containerWidth, y: anchorFrame.midY + CGFloat(y))
    }

    /// Görünen bölgenin ortası (yeni yerleştirmenin başlangıcı). `contentMinY`: içeriğin görünüm içindeki üst kenarı (kaydırınca negatif).
    static func visibleCenter(contentMinY: CGFloat, viewportSize: CGSize) -> CGPoint {
        CGPoint(x: viewportSize.width / 2, y: -contentMinY + viewportSize.height / 2)
    }
}

// MARK: - Son kullanılan sticker'lar

/// Kütüphanedeki sticker kimlikleri, en son kullanılan başta (kullanıcı başına, cihazda).
struct StickerRecents {
    static let limit = 16
    let defaults: UserDefaults
    let userID: String

    private var key: String { "chat.recentStickers.\(userID)" }

    var ids: [String] { defaults.stringArray(forKey: key) ?? [] }

    func use(_ id: String) {
        var list = ids.filter { $0 != id }
        list.insert(id, at: 0)
        defaults.set(Array(list.prefix(Self.limit)), forKey: key)
    }

    func remove(_ id: String) {
        defaults.set(ids.filter { $0 != id }, forKey: key)
    }

    /// Kütüphanede hâlâ olanlar, kullanım sırasıyla.
    func items(from library: [StickerItem]) -> [StickerItem] {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    func clear() { defaults.removeObject(forKey: key) }
}
