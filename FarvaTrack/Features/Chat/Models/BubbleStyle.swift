import Foundation
import CoreGraphics

// MARK: - Baloncuk stili (Codable JSON)

/// Sohbet baloncuğunun tasarımı. JSON olarak saklanır (`users/{uid}/bubbles/{id}`), mesajda yalnızca
/// `bubble {id, version}` gider; karşı cihaz stili bir kez indirip önbelleğe alır.
struct BubbleStyle: Codable, Equatable, Identifiable {
    var id: String
    /// Her kayıtta artar; karşı cihaz eski sürümü önbellekten atıp yenisini indirir.
    var version: Int
    var name: String
    var shape: BubbleShapeStyle
    var fill: BubbleFill
    var border: BubbleBorder?
    var textColorHex: String
    /// Yazı, emoji, sticker: sabitlendikleri bölgeye göre konumlanır, esnemez.
    var decorations: [BubbleDecoration]
    /// El çizimi (PNG); arka planın parçası olarak 9-dilimle esner.
    var drawingAssetID: String?
    var effect: BubbleEffect
    /// `nil` = otomatik (şekilden hesaplanır). Editörde elle ayarlanabilir.
    var manualInsets: BubbleInsets?
    /// Hazır çizimli baloncuk (ör. Kutu Kedi): şekil/dolgu yerine kendi çizimiyle gösterilir. Eski kayıtlarda yok → `nil`.
    var art: BubbleArtKind? = nil

    static let schemaVersion = 1
    static let maxDecorations = 12
    static let maxTextLength = 24
    static let nameLength = 30

    var isPreset: Bool { id.hasPrefix(BubblePresets.prefix) }
}

/// Kendi çizimi ve uzama kuralı olan baloncuklar.
enum BubbleArtKind: String, Codable {
    /// Nakış kafa ve patiler sabit, kumaş dokulu gövde kutusu mesajla büyür (`CatBoxGeometry`).
    case catBox
}

struct BubbleShapeStyle: Codable, Equatable {
    var cornerRadius: Double
    var tail: BubbleTail

    static let radiusRange: ClosedRange<Double> = 4...28
}

enum BubbleTail: String, Codable, CaseIterable, Identifiable {
    case none
    /// Alt köşede küçük sivri kuyruk.
    case classic
    /// Kıvrık (iMessage benzeri) kuyruk.
    case curl
    /// Düşünce balonu gibi iki küçük daire.
    case dots

    var id: Self { self }

    var title: String {
        switch self {
        case .none: return "Yok"
        case .classic: return "Sivri"
        case .curl: return "Kıvrık"
        case .dots: return "Düşünce"
        }
    }

    /// Kuyruğun gövdeden dışarı taşan alanı (pt).
    var extent: CGSize {
        switch self {
        case .none: return .zero
        case .classic: return CGSize(width: 8, height: 10)
        case .curl: return CGSize(width: 9, height: 14)
        case .dots: return CGSize(width: 12, height: 12)
        }
    }
}

struct BubbleFill: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case solid, linear, radial
        var id: Self { self }
        var title: String {
            switch self {
            case .solid: return "Düz"
            case .linear: return "Geçişli"
            case .radial: return "Işınsal"
            }
        }
    }

    var kind: Kind
    /// 1 (düz) ya da 2–3 renk.
    var colors: [String]
    /// Geçiş açısı (derece; 0 = soldan sağa, 90 = yukarıdan aşağı).
    var angle: Double
}

struct BubbleBorder: Codable, Equatable {
    var colorHex: String
    var width: Double

    static let widthRange: ClosedRange<Double> = 0.5...4
}

/// Süslemenin sabitlendiği bölge: 4 köşe, 4 kenar ortası. Baloncuk büyüse de bu noktaya göre yerinde kalır.
enum BubbleAnchor: String, Codable, CaseIterable, Identifiable {
    case topLeading, top, topTrailing, leading, trailing, bottomLeading, bottom, bottomTrailing

    var id: Self { self }

    var title: String {
        switch self {
        case .topLeading: return "Sol üst köşe"
        case .top: return "Üst kenar"
        case .topTrailing: return "Sağ üst köşe"
        case .leading: return "Sol kenar"
        case .trailing: return "Sağ kenar"
        case .bottomLeading: return "Sol alt köşe"
        case .bottom: return "Alt kenar"
        case .bottomTrailing: return "Sağ alt köşe"
        }
    }

    /// Birim kare içindeki konum (0…1).
    var unitPoint: CGPoint {
        switch self {
        case .topLeading: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: 0.5, y: 0)
        case .topTrailing: return CGPoint(x: 1, y: 0)
        case .leading: return CGPoint(x: 0, y: 0.5)
        case .trailing: return CGPoint(x: 1, y: 0.5)
        case .bottomLeading: return CGPoint(x: 0, y: 1)
        case .bottom: return CGPoint(x: 0.5, y: 1)
        case .bottomTrailing: return CGPoint(x: 1, y: 1)
        }
    }

    /// Gelen mesajlarda baloncuk aynalanır; sağ/sol yer değiştirir.
    var mirrored: BubbleAnchor {
        switch self {
        case .topLeading: return .topTrailing
        case .topTrailing: return .topLeading
        case .leading: return .trailing
        case .trailing: return .leading
        case .bottomLeading: return .bottomTrailing
        case .bottomTrailing: return .bottomLeading
        case .top, .bottom: return self
        }
    }
}

struct BubbleDecoration: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case emoji, text, sticker }

    var id: String
    var kind: Kind
    /// Emoji ya da yazı.
    var text: String?
    /// Sticker PNG'si (`users/{uid}/bubbles/{styleId}/{assetID}.png`).
    var assetID: String?
    var colorHex: String?
    var anchor: BubbleAnchor
    /// Sabitlendiği noktaya göre kaydırma (pt; aynalamada x işareti değişir).
    var offset: CGSize
    /// Yükseklik (pt).
    var size: Double
    /// Derece.
    var rotation: Double

    static let sizeRange: ClosedRange<Double> = 10...48
    static let offsetLimit: Double = 40
}

struct BubbleEffect: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case none
        /// Üzerinden geçen ışık bandı.
        case shimmer
        /// Kenarlarda nabız gibi atan ışıma.
        case glow
        /// Yanıp sönen küçük parıltılar.
        case particles

        var id: Self { self }

        var title: String {
            switch self {
            case .none: return "Yok"
            case .shimmer: return "Parıltı"
            case .glow: return "Işıma"
            case .particles: return "Parçacık"
            }
        }
    }

    var kind: Kind
    var colorHex: String
    /// 0…1
    var intensity: Double

    static let none = BubbleEffect(kind: .none, colorHex: "#FFFFFF", intensity: 0.6)
}

struct BubbleInsets: Codable, Equatable {
    var top: Double
    var leading: Double
    var bottom: Double
    var trailing: Double

    var horizontal: Double { leading + trailing }
    var vertical: Double { top + bottom }

    /// Aynalanınca sol ve sağ yer değiştirir.
    var mirrored: BubbleInsets { BubbleInsets(top: top, leading: trailing, bottom: bottom, trailing: leading) }
}

// MARK: - Mesajdaki başvuru

/// Mesajın hangi baloncukla (ve hangi sürümüyle) gönderildiği; stilin sahibi mesajı gönderendir.
struct ChatBubbleRef: Codable, Equatable, Hashable {
    var id: String
    var version: Int
}

enum ChatBubbleRefFields {
    static func encode(_ ref: ChatBubbleRef) -> [String: Any] { ["id": ref.id, "version": ref.version] }

    static func decode(_ value: Any?) -> ChatBubbleRef? {
        guard let map = value as? [String: Any], let id = map["id"] as? String, !id.isEmpty else { return nil }
        return ChatBubbleRef(id: id, version: max(1, (map["version"] as? NSNumber)?.intValue ?? 1))
    }
}

// MARK: - Doğrulama

extension BubbleStyle {
    /// Sınırlar içine çeker (editör, ağdan gelen ya da elle bozulmuş JSON için).
    func sanitized() -> BubbleStyle {
        var style = self
        style.version = max(1, version)
        style.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.nameLength))
        if style.name.isEmpty { style.name = "Baloncuğum" }
        style.shape.cornerRadius = min(max(shape.cornerRadius, BubbleShapeStyle.radiusRange.lowerBound), BubbleShapeStyle.radiusRange.upperBound)
        style.fill.colors = Array(fill.colors.filter(BubbleColor.isValidHex).prefix(3))
        if style.fill.colors.isEmpty { style.fill.colors = [BubblePalette.bordo] }
        if style.fill.kind != .solid, style.fill.colors.count == 1 { style.fill.colors.append(style.fill.colors[0]) }
        style.fill.angle = fill.angle.isFinite ? fill.angle.truncatingRemainder(dividingBy: 360) : 0
        if var border = border {
            border.width = min(max(border.width, BubbleBorder.widthRange.lowerBound), BubbleBorder.widthRange.upperBound)
            if !BubbleColor.isValidHex(border.colorHex) { border.colorHex = "#FFFFFF" }
            style.border = border
        }
        if !BubbleColor.isValidHex(textColorHex) { style.textColorHex = "#FFFFFF" }
        style.decorations = decorations.prefix(Self.maxDecorations).compactMap { decoration in
            var item = decoration
            item.size = min(max(decoration.size, BubbleDecoration.sizeRange.lowerBound), BubbleDecoration.sizeRange.upperBound)
            let limit = BubbleDecoration.offsetLimit
            item.offset = CGSize(width: min(max(decoration.offset.width, -limit), limit),
                                 height: min(max(decoration.offset.height, -limit), limit))
            item.rotation = decoration.rotation.isFinite ? decoration.rotation.truncatingRemainder(dividingBy: 360) : 0
            switch decoration.kind {
            case .emoji, .text:
                let text = String((decoration.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTextLength))
                guard !text.isEmpty else { return nil }
                item.text = text
            case .sticker:
                guard let asset = decoration.assetID, BubbleAssetID.isValid(asset) else { return nil }
            }
            return item
        }
        if let drawing = drawingAssetID, !BubbleAssetID.isValid(drawing) { style.drawingAssetID = nil }
        style.effect.intensity = min(max(effect.intensity.isFinite ? effect.intensity : 0.6, 0), 1)
        if !BubbleColor.isValidHex(effect.colorHex) { style.effect.colorHex = "#FFFFFF" }
        if let manual = manualInsets {
            func clamp(_ value: Double) -> Double { min(max(value.isFinite ? value : 0, 0), 60) }
            style.manualInsets = BubbleInsets(top: clamp(manual.top), leading: clamp(manual.leading),
                                              bottom: clamp(manual.bottom), trailing: clamp(manual.trailing))
        }
        return style
    }

    /// Düzenleme kaydedilirken: yeni sürüm.
    func bumpedVersion() -> BubbleStyle {
        var copy = self
        copy.version = version + 1
        return copy
    }

    /// Stilin kullandığı dosyalar (çizim + sticker'lar).
    var assetIDs: [String] {
        var ids = decorations.compactMap { $0.kind == .sticker ? $0.assetID : nil }
        if let drawingAssetID { ids.append(drawingAssetID) }
        return Array(Set(ids)).sorted()
    }

    var ref: ChatBubbleRef { ChatBubbleRef(id: id, version: version) }

    // JSON

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(json data: Data) throws -> BubbleStyle {
        try JSONDecoder().decode(BubbleStyle.self, from: data).sanitized()
    }
}

enum BubbleAssetID {
    /// Storage kuralları ile aynı: harf, rakam, tire.
    static func isValid(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } && id.allSatisfy(\.isASCII)
    }

    static func make() -> String { UUID().uuidString.lowercased() }
}

enum BubbleColor {
    static func isValidHex(_ hex: String) -> Bool {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        return (value.count == 6 || value.count == 8) && value.allSatisfy(\.isHexDigit)
    }
}

enum BubblePalette {
    static let bordo = "#800020"
    static let bordoLight = "#A3243F"
    static let gold = "#D4AF6A"
    static let night = "#1C1C24"
    static let ink = "#14141A"
    static let rose = "#C98A94"
    static let cream = "#F3E6D8"

    /// Editördeki hazır renkler.
    static let swatches = [bordo, bordoLight, "#4A0012", night, ink, "#2C2C38", rose, gold, cream, "#FFFFFF", "#6E5BFF", "#2E8B7A"]
}
