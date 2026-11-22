import Foundation
import CoreGraphics

// MARK: - 9-dilim (cap insets)

/// Baloncuk görseli 9 parçaya bölünür: köşeler sabit, üst/alt kenar yalnız yatayda, sol/sağ kenar yalnız
/// dikeyde, orta iki yönde esner. Böylece mesaj uzayıp kısaldıkça köşe yarıçapı, kuyruk ve köşedeki
/// çizimler bozulmaz.
enum NineSlice {
    enum Region: Equatable {
        case corner
        /// Üst ya da alt kenar: yalnız yatayda esner.
        case horizontalEdge
        /// Sol ya da sağ kenar: yalnız dikeyde esner.
        case verticalEdge
        case center
    }

    struct Slice: Equatable {
        var source: CGRect
        var destination: CGRect
        var region: Region
        /// 0…2 (üst, orta, alt) ve 0…2 (sol, orta, sağ).
        var row: Int
        var column: Int

        var index: Int { row * 3 + column }
    }

    /// `imageSize` ve `insets` görselin kendi biriminde (pt). Hedef paylardan küçükse köşeler orantılı küçülür.
    static func slices(imageSize: CGSize, insets: BubbleInsets, target: CGSize) -> [Slice] {
        guard imageSize.width > 0, imageSize.height > 0, target.width > 0, target.height > 0 else { return [] }
        let source = clamped(insets, to: imageSize)

        // Hedef küçükse payları aynı oranda daralt (köşeler ezilmez, birlikte küçülür).
        let horizontalScale = min(1, Double(target.width) / max(source.horizontal, .ulpOfOne))
        let verticalScale = min(1, Double(target.height) / max(source.vertical, .ulpOfOne))
        let destination = BubbleInsets(
            top: source.top * verticalScale, leading: source.leading * horizontalScale,
            bottom: source.bottom * verticalScale, trailing: source.trailing * horizontalScale
        )

        let sourceColumns = spans(total: Double(imageSize.width), start: source.leading, end: source.trailing)
        let sourceRows = spans(total: Double(imageSize.height), start: source.top, end: source.bottom)
        let destColumns = spans(total: Double(target.width), start: destination.leading, end: destination.trailing)
        let destRows = spans(total: Double(target.height), start: destination.top, end: destination.bottom)

        var result: [Slice] = []
        for row in 0..<3 {
            for column in 0..<3 {
                let src = CGRect(x: sourceColumns[column].0, y: sourceRows[row].0,
                                 width: sourceColumns[column].1, height: sourceRows[row].1)
                let dst = CGRect(x: destColumns[column].0, y: destRows[row].0,
                                 width: destColumns[column].1, height: destRows[row].1)
                guard src.width > 0.0001, src.height > 0.0001, dst.width > 0.0001, dst.height > 0.0001 else { continue }
                let region: Region
                switch (row, column) {
                case (1, 1): region = .center
                case (0, 1), (2, 1): region = .horizontalEdge
                case (1, 0), (1, 2): region = .verticalEdge
                default: region = .corner
                }
                result.append(Slice(source: src, destination: dst, region: region, row: row, column: column))
            }
        }
        return result
    }

    /// Paylar görselin içine sığsın; ortada en az 1 pt esneyen alan kalsın.
    static func clamped(_ insets: BubbleInsets, to size: CGSize) -> BubbleInsets {
        func fit(_ a: Double, _ b: Double, total: Double) -> (Double, Double) {
            let a = max(0, a), b = max(0, b)
            let available = max(0, total - 1)
            guard a + b > available, a + b > 0 else { return (a, b) }
            let scale = available / (a + b)
            return (a * scale, b * scale)
        }
        let (leading, trailing) = fit(insets.leading, insets.trailing, total: Double(size.width))
        let (top, bottom) = fit(insets.top, insets.bottom, total: Double(size.height))
        return BubbleInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    private static func spans(total: Double, start: Double, end: Double) -> [(Double, Double)] {
        [(0, start), (start, max(0, total - start - end)), (total - end, end)]
    }
}

// MARK: - Baloncuk ölçüleri

enum BubbleLayout {
    /// Görselin (sanat) çizildiği referans boyut: gövde + kuyruk payı.
    static let referenceSize = CGSize(width: 180, height: 110)
    /// Yazının gövde kenarına uzaklığı.
    static let textPadding = CGSize(width: 12, height: 8)

    /// Kuyruk sağ altta (giden mesaj); gelen mesajda görsel aynalanır.
    static func bodyRect(in size: CGSize, tail: BubbleTail, mirrored: Bool = false) -> CGRect {
        let extent = tail.extent
        let bottomExtra: CGFloat = tail == .dots ? extent.height : 0
        let width = max(0, size.width - extent.width)
        let height = max(0, size.height - bottomExtra)
        return CGRect(x: mirrored ? extent.width : 0, y: 0, width: width, height: height)
    }

    /// Şekilden otomatik dilim payları: köşe yarıçapı + kenarlık + kuyruk alanı.
    static func automaticInsets(for style: BubbleStyle) -> BubbleInsets {
        let radius = style.shape.cornerRadius
        let border = style.border?.width ?? 0
        let extent = style.shape.tail.extent
        let margin = 2.0
        let side = radius + border + margin
        let bottom: Double
        switch style.shape.tail {
        case .dots: bottom = side + Double(extent.height)
        case .classic, .curl: bottom = max(radius, Double(extent.height)) + border + margin
        case .none: bottom = side
        }
        return NineSlice.clamped(
            BubbleInsets(top: side, leading: side, bottom: bottom, trailing: side + Double(extent.width)),
            to: referenceSize
        )
    }

    /// Elle ayarlanmışsa o, yoksa otomatik.
    static func insets(for style: BubbleStyle) -> BubbleInsets {
        NineSlice.clamped(style.manualInsets ?? automaticInsets(for: style), to: referenceSize)
    }

    /// Yazının baloncuk içindeki iç boşluğu (kuyruk tarafı daha geniş).
    static func contentPadding(for style: BubbleStyle, mirrored: Bool) -> BubbleInsets {
        let extent = style.shape.tail.extent
        let border = style.border?.width ?? 0
        let horizontal = Double(textPadding.width) + border
        let vertical = Double(textPadding.height) + border
        let tailSide = horizontal + Double(extent.width)
        let bottom = vertical + (style.shape.tail == .dots ? Double(extent.height) : 0)
        return BubbleInsets(top: vertical, leading: mirrored ? tailSide : horizontal,
                            bottom: bottom, trailing: mirrored ? horizontal : tailSide)
    }

    /// Süslemenin baloncuk içindeki merkezi: sabitlendiği noktası + kaydırma. Aynalamada sağ/sol değişir.
    static func position(of decoration: BubbleDecoration, in size: CGSize, tail: BubbleTail, mirrored: Bool) -> CGPoint {
        let body = bodyRect(in: size, tail: tail, mirrored: mirrored)
        let anchor = mirrored ? decoration.anchor.mirrored : decoration.anchor
        let unit = anchor.unitPoint
        let dx = mirrored ? -decoration.offset.width : decoration.offset.width
        return CGPoint(x: body.minX + unit.x * body.width + dx, y: body.minY + unit.y * body.height + decoration.offset.height)
    }
}

// MARK: - Efekt kuralı

enum BubbleEffectPolicy {
    /// "Hareketi azalt" açıksa efektler hiç çalışmaz (statik baloncuk gösterilir).
    static func isEnabled(_ effect: BubbleEffect, reduceMotion: Bool) -> Bool {
        !reduceMotion && effect.kind != .none && effect.intensity > 0.01
    }
}

// MARK: - Hazır baloncuklar

enum BubblePresets {
    static let prefix = "preset."

    static let all: [BubbleStyle] = [
        preset("bordo", "Bordo Klasik",
               shape: BubbleShapeStyle(cornerRadius: 18, tail: .classic),
               fill: BubbleFill(kind: .linear, colors: [BubblePalette.bordo, BubblePalette.bordoLight], angle: 120)),
        preset("gece", "Gece",
               shape: BubbleShapeStyle(cornerRadius: 16, tail: .curl),
               fill: BubbleFill(kind: .solid, colors: [BubblePalette.night], angle: 0),
               border: BubbleBorder(colorHex: BubblePalette.bordo, width: 1.5), text: BubblePalette.cream),
        preset("gul", "Gül Kurusu",
               shape: BubbleShapeStyle(cornerRadius: 20, tail: .curl),
               fill: BubbleFill(kind: .linear, colors: [BubblePalette.rose, "#8E4A58"], angle: 90),
               decorations: [decoration("gul-1", emoji: "🌸", .topTrailing, offset: CGSize(width: -4, height: -2), size: 18, rotation: 12)]),
        preset("altin", "Altın Çerçeve",
               shape: BubbleShapeStyle(cornerRadius: 14, tail: .classic),
               fill: BubbleFill(kind: .linear, colors: ["#2A1A10", BubblePalette.ink], angle: 135),
               border: BubbleBorder(colorHex: BubblePalette.gold, width: 1.5), text: BubblePalette.cream,
               effect: BubbleEffect(kind: .shimmer, colorHex: BubblePalette.gold, intensity: 0.45)),
        preset("neon", "Neon Bordo",
               shape: BubbleShapeStyle(cornerRadius: 22, tail: .none),
               fill: BubbleFill(kind: .solid, colors: [BubblePalette.ink], angle: 0),
               border: BubbleBorder(colorHex: BubblePalette.bordoLight, width: 2),
               effect: BubbleEffect(kind: .glow, colorHex: "#E0607F", intensity: 0.7)),
        preset("yildiz", "Yıldızlı Gece",
               shape: BubbleShapeStyle(cornerRadius: 18, tail: .dots),
               fill: BubbleFill(kind: .radial, colors: ["#2C2C38", "#0B0B12"], angle: 0),
               decorations: [decoration("yildiz-1", emoji: "✨", .topLeading, offset: CGSize(width: 2, height: 0), size: 16, rotation: 0)],
               effect: BubbleEffect(kind: .particles, colorHex: BubblePalette.cream, intensity: 0.6)),
        preset("pati", "Pati",
               shape: BubbleShapeStyle(cornerRadius: 24, tail: .classic),
               fill: BubbleFill(kind: .solid, colors: ["#4A0012"], angle: 0),
               decorations: [decoration("pati-1", emoji: "🐾", .bottomLeading, offset: CGSize(width: 4, height: -2), size: 16, rotation: -15)]),
        preset("minimal", "Minimal",
               shape: BubbleShapeStyle(cornerRadius: 12, tail: .none),
               fill: BubbleFill(kind: .solid, colors: ["#2C2C38"], angle: 0))
    ]

    static func style(id: String) -> BubbleStyle? { all.first { $0.id == id } }

    private static func preset(_ key: String, _ name: String, shape: BubbleShapeStyle, fill: BubbleFill,
                               border: BubbleBorder? = nil, text: String = "#FFFFFF",
                               decorations: [BubbleDecoration] = [], effect: BubbleEffect = .none) -> BubbleStyle {
        BubbleStyle(id: prefix + key, version: 1, name: name, shape: shape, fill: fill, border: border,
                    textColorHex: text, decorations: decorations, drawingAssetID: nil, effect: effect, manualInsets: nil)
    }

    private static func decoration(_ id: String, emoji: String, _ anchor: BubbleAnchor, offset: CGSize, size: Double, rotation: Double) -> BubbleDecoration {
        BubbleDecoration(id: id, kind: .emoji, text: emoji, assetID: nil, colorHex: nil, anchor: anchor, offset: offset, size: size, rotation: rotation)
    }
}
