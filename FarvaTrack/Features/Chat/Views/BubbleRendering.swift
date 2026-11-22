import SwiftUI
import UIKit

// MARK: - Baloncuk sanatı (referans boyutta bir kez çizilir)

/// Stilin kullandığı dosyalar: çizim görseli ve sticker PNG'leri.
struct BubbleAssets {
    var drawing: CGImage?
    var stickerURLs: [String: URL] = [:]
    /// Önbellek anahtarına girer: çizim değişince sanat yeniden üretilir.
    var drawingToken: String = ""

    static let empty = BubbleAssets(drawing: nil)
}

enum BubbleArtRenderer {
    static let scale: CGFloat = 3

    /// Gövde (yuvarlatılmış dikdörtgen) + kuyruk.
    static func path(size: CGSize, style: BubbleStyle, mirrored: Bool) -> CGPath {
        let tail = style.shape.tail
        let body = BubbleLayout.bodyRect(in: size, tail: tail, mirrored: false)
        let radius = min(CGFloat(style.shape.cornerRadius), body.height / 2, body.width / 2)
        let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
        // Kuyruk ayrı çizilip gövdeyle birleştirilir: yönleri ters düşse de üst üste binen yerde delik kalmaz.
        let path = CGMutablePath()

        let extent = tail.extent
        switch tail {
        case .none:
            break
        case .classic:
            path.move(to: CGPoint(x: body.maxX - radius * 0.9, y: body.maxY))
            path.addLine(to: CGPoint(x: body.maxX - 1, y: body.maxY - extent.height - 2))
            path.addLine(to: CGPoint(x: size.width, y: body.maxY))
            path.closeSubpath()
        case .curl:
            path.move(to: CGPoint(x: body.maxX - radius, y: body.maxY))
            path.addLine(to: CGPoint(x: body.maxX - 1, y: body.maxY - extent.height))
            path.addQuadCurve(to: CGPoint(x: size.width, y: body.maxY),
                              control: CGPoint(x: body.maxX + 1, y: body.maxY - 2))
            path.addQuadCurve(to: CGPoint(x: body.maxX - radius, y: body.maxY),
                              control: CGPoint(x: body.maxX - 2, y: body.maxY + 2))
            path.closeSubpath()
        case .dots:
            path.addEllipse(in: CGRect(x: body.maxX - 4, y: body.maxY + 1, width: 7, height: 7))
            path.addEllipse(in: CGRect(x: size.width - 5, y: size.height - 5, width: 4.5, height: 4.5))
        }

        let shape = path.isEmpty ? bodyPath : bodyPath.union(path)
        guard mirrored else { return shape }
        var flip = CGAffineTransform(translationX: size.width, y: 0).scaledBy(x: -1, y: 1)
        return shape.copy(using: &flip) ?? shape
    }

    /// Şekil + dolgu + çizim + iç kenarlık. Gelen mesaj için şekil aynalanır, çizim gövdeyle birlikte kayar (yazı ters dönmez).
    static func render(style: BubbleStyle, assets: BubbleAssets, mirrored: Bool) -> CGImage? {
        let size = BubbleLayout.referenceSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let shape = path(size: size, style: style, mirrored: mirrored)

            cg.saveGState()
            cg.addPath(shape)
            cg.clip()
            drawFill(style.fill, in: CGRect(origin: .zero, size: size), context: cg)
            if let drawing = assets.drawing {
                let body = BubbleLayout.bodyRect(in: size, tail: style.shape.tail, mirrored: mirrored)
                // Çizim gövdeye göre konumlanır (aynalamada kuyruk payı kadar kayar).
                UIImage(cgImage: drawing).draw(in: CGRect(origin: body.origin, size: size))
            }
            if let border = style.border {
                // Yolun içine çizilir: kalınlığın yarısı kırpılır, kenar baloncuğun dışına taşmaz.
                cg.addPath(shape)
                cg.setStrokeColor(UIColor(Color(hex: border.colorHex)).cgColor)
                cg.setLineWidth(CGFloat(border.width) * 2)
                cg.strokePath()
            }
            cg.restoreGState()
        }
        return image.cgImage
    }

    private static func drawFill(_ fill: BubbleFill, in rect: CGRect, context: CGContext) {
        let colors = fill.colors.map { UIColor(Color(hex: $0)).cgColor }
        guard let first = colors.first else { return }
        switch fill.kind {
        case .solid:
            context.setFillColor(first)
            context.fill(rect)
        case .linear, .radial:
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let stops = colors.count > 1 ? colors : [first, first]
            guard let gradient = CGGradient(colorsSpace: space, colors: stops as CFArray, locations: nil) else { return }
            if fill.kind == .radial {
                let center = CGPoint(x: rect.midX * 0.8, y: rect.midY * 0.6)
                context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                           endRadius: max(rect.width, rect.height) * 0.8, options: [.drawsAfterEndLocation])
            } else {
                let radians = fill.angle * .pi / 180
                let half = CGSize(width: cos(radians) * rect.width / 2, height: sin(radians) * rect.height / 2)
                let start = CGPoint(x: rect.midX - half.width, y: rect.midY - half.height)
                let end = CGPoint(x: rect.midX + half.width, y: rect.midY + half.height)
                context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        }
    }
}

// MARK: - Önbellek

/// Sanat + dokuz parçası. Kaydırma sırasında her karede yeniden çizilmez.
final class BubbleArt {
    let image: CGImage
    /// Satır satır 9 parça (boş parçalar `nil`).
    let pieces: [CGImage?]
    let insets: BubbleInsets

    init(image: CGImage, insets: BubbleInsets) {
        self.image = image
        self.insets = insets
        let size = BubbleLayout.referenceSize
        // Parçalar yalnızca kaynak dikdörtgene bağlıdır; hedef boyut sadece yerleşimi değiştirir.
        let slices = NineSlice.slices(imageSize: size, insets: insets, target: size)
        var pieces = [CGImage?](repeating: nil, count: 9)
        for slice in slices {
            let pixel = CGRect(x: slice.source.minX * BubbleArtRenderer.scale, y: slice.source.minY * BubbleArtRenderer.scale,
                               width: slice.source.width * BubbleArtRenderer.scale, height: slice.source.height * BubbleArtRenderer.scale).integral
            pieces[slice.index] = image.cropping(to: pixel)
        }
        self.pieces = pieces
    }
}

@MainActor
enum BubbleArtCache {
    private static var storage: [String: BubbleArt] = [:]
    private static var order: [String] = []
    private static let limit = 64

    static func art(for style: BubbleStyle, assets: BubbleAssets, mirrored: Bool, keyPrefix: String) -> BubbleArt? {
        let key = "\(keyPrefix)|\(style.id)|\(style.version)|\(mirrored)|\(assets.drawingToken)"
        if let cached = storage[key] { return cached }
        guard let image = BubbleArtRenderer.render(style: style, assets: assets, mirrored: mirrored) else { return nil }
        let insets = BubbleLayout.insets(for: style)
        let art = BubbleArt(image: image, insets: mirrored ? insets.mirrored : insets)
        storage[key] = art
        order.append(key)
        if order.count > limit {
            storage.removeValue(forKey: order.removeFirst())
        }
        return art
    }

    /// Editör önizlemesi: her değişiklikte yeni sanat (önbelleğe alınmaz).
    static func uncachedArt(for style: BubbleStyle, assets: BubbleAssets, mirrored: Bool) -> BubbleArt? {
        guard let image = BubbleArtRenderer.render(style: style, assets: assets, mirrored: mirrored) else { return nil }
        let insets = BubbleLayout.insets(for: style)
        return BubbleArt(image: image, insets: mirrored ? insets.mirrored : insets)
    }

    static func removeAll() {
        storage.removeAll()
        order.removeAll()
    }
}

// MARK: - 9-dilim arka plan

/// Sanatın 9 parçasını hedef boyuta yerleştirir: köşeler sabit, kenarlar tek yönde, orta iki yönde esner.
struct NineSliceArtView: View {
    let art: BubbleArt

    var body: some View {
        Canvas { context, size in
            let slices = NineSlice.slices(imageSize: BubbleLayout.referenceSize, insets: art.insets, target: size)
            for slice in slices {
                guard let piece = art.pieces[slice.index] else { continue }
                // Parça kenarlarında ince boşluk kalmasın diye hedef yarım nokta taşırılır.
                let rect = slice.destination.insetBy(dx: -0.25, dy: -0.25)
                context.draw(Image(decorative: piece, scale: BubbleArtRenderer.scale), in: rect)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Mesaj baloncuğunun arkası: 9-dilim sanat + efekt + süslemeler.
struct BubbleBackgroundView: View {
    let style: BubbleStyle
    let assets: BubbleAssets
    let mirrored: Bool
    /// Önbellek anahtarı (stilin sahibi); editörde `nil` → her seferinde yeniden çizilir.
    var cacheOwner: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var art: BubbleArt? {
        if let cacheOwner {
            return BubbleArtCache.art(for: style, assets: assets, mirrored: mirrored, keyPrefix: cacheOwner)
        }
        return BubbleArtCache.uncachedArt(for: style, assets: assets, mirrored: mirrored)
    }

    var body: some View {
        ZStack {
            if let art {
                NineSliceArtView(art: art)
                    .bubbleEffect(style.effect, enabled: BubbleEffectPolicy.isEnabled(style.effect, reduceMotion: reduceMotion))
            }
        }
        .overlay {
            BubbleDecorationsView(style: style, assets: assets, mirrored: mirrored)
        }
    }
}

/// Yazı, emoji, sticker süslemeleri: sabitlendikleri köşe/kenara göre yerleşir, baloncukla esnemez.
struct BubbleDecorationsView: View {
    let style: BubbleStyle
    let assets: BubbleAssets
    let mirrored: Bool

    var body: some View {
        GeometryReader { proxy in
            ForEach(style.decorations) { decoration in
                decorationView(decoration)
                    .rotationEffect(.degrees(mirrored ? -decoration.rotation : decoration.rotation))
                    .position(BubbleLayout.position(of: decoration, in: proxy.size, tail: style.shape.tail, mirrored: mirrored))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func decorationView(_ decoration: BubbleDecoration) -> some View {
        switch decoration.kind {
        case .emoji:
            Text(decoration.text ?? "")
                .font(.system(size: decoration.size * 0.85))
                .fixedSize()
        case .text:
            Text(decoration.text ?? "")
                .font(.system(size: decoration.size * 0.6, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: decoration.colorHex ?? "#FFFFFF"))
                .shadow(color: .black.opacity(0.4), radius: 1)
                .fixedSize()
        case .sticker:
            StickerImage(url: decoration.assetID.flatMap { assets.stickerURLs[$0] })
                .frame(width: decoration.size, height: decoration.size)
        }
    }
}
