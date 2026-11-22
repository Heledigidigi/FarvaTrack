import CoreGraphics
import Foundation

// MARK: - Kameradan çekilen fotoğrafın düzenleme belgesi (saf, testli)

/// Tüm konumlar ORİJİNAL fotoğrafa göre 0…1 oranlarıdır; kırpma tahribatsızdır (yalnızca görünen bölge).
/// Böylece kırpma sonradan değişse de çizimler ve katmanlar yerinde kalır.
struct PhotoEditStroke: Identifiable, Equatable {
    var id = UUID()
    /// Noktalar (x: genişliğe, y: yüksekliğe oran).
    var points: [CGPoint]
    var colorIndex: Int
    /// Çizgi kalınlığı, orijinal genişliğe oran.
    var width: CGFloat
}

struct PhotoEditLayer: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String, colorIndex: Int)
        case sticker(id: String, aspect: CGFloat)
    }

    var id = UUID()
    var content: Content
    /// Merkez (orijinale oran).
    var center: CGPoint
    var scale: CGFloat = 1
    /// Radyan.
    var rotation: Double = 0

    /// Yazı boyutu: orijinal genişliğin %7'si × ölçek.
    static let textSizeFraction: CGFloat = 0.07
    /// Sticker genişliği: orijinal genişliğin %35'i × ölçek.
    static let stickerWidthFraction: CGFloat = 0.35
    static let scaleRange: ClosedRange<CGFloat> = 0.25...6
}

struct PhotoEditDocument: Equatable {
    /// Görünen bölge (orijinale oran). Varsayılan: tamamı.
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var strokes: [PhotoEditStroke] = []
    var layers: [PhotoEditLayer] = []

    static let fullCrop = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Hiç değişiklik yoksa orijinal dosya bayt bayt gönderilir.
    var isEdited: Bool {
        !PhotoEditGeometry.isFull(crop) || !strokes.isEmpty || !layers.isEmpty
    }
}

enum PhotoEditGeometry {
    /// Kırpmada en küçük kenar (orijinale oran).
    static let minimumCropSide: CGFloat = 0.12

    static func isFull(_ rect: CGRect) -> Bool {
        abs(rect.minX) < 0.0005 && abs(rect.minY) < 0.0005 && abs(rect.width - 1) < 0.0005 && abs(rect.height - 1) < 0.0005
    }

    /// `bounds` içine en-boy oranını koruyarak sığan boyut.
    static func fitted(aspect: CGFloat, in bounds: CGSize) -> CGSize {
        guard aspect > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        if bounds.width / bounds.height > aspect {
            return CGSize(width: bounds.height * aspect, height: bounds.height)
        }
        return CGSize(width: bounds.width, height: bounds.width / aspect)
    }

    /// Kırpılmış bölgenin en-boy oranı (genişlik / yükseklik).
    static func aspect(of crop: CGRect, imageSize: CGSize) -> CGFloat {
        guard imageSize.height > 0, crop.height > 0 else { return 1 }
        return (crop.width * imageSize.width) / (crop.height * imageSize.height)
    }

    /// Ekrandaki nokta (görünen bölgenin `displaySize` boyutundaki çizimi) → orijinale oran.
    static func toImage(_ point: CGPoint, displaySize: CGSize, crop: CGRect) -> CGPoint {
        guard displaySize.width > 0, displaySize.height > 0 else { return .zero }
        return CGPoint(x: crop.minX + point.x / displaySize.width * crop.width,
                       y: crop.minY + point.y / displaySize.height * crop.height)
    }

    /// Orijinale oran → ekrandaki nokta.
    static func toDisplay(_ point: CGPoint, displaySize: CGSize, crop: CGRect) -> CGPoint {
        guard crop.width > 0, crop.height > 0 else { return .zero }
        return CGPoint(x: (point.x - crop.minX) / crop.width * displaySize.width,
                       y: (point.y - crop.minY) / crop.height * displaySize.height)
    }

    /// Görünen bölge `displaySize` iken orijinalin tamamının ekrandaki boyutu.
    static func fullDisplaySize(displaySize: CGSize, crop: CGRect) -> CGSize {
        guard crop.width > 0, crop.height > 0 else { return displaySize }
        return CGSize(width: displaySize.width / crop.width, height: displaySize.height / crop.height)
    }

    /// Kırpma bölgesinin piksel karşılığı (tam sayıya yuvarlanmış, resmin içinde).
    static func pixelRect(crop: CGRect, pixelSize: CGSize) -> CGRect {
        let rect = CGRect(x: crop.minX * pixelSize.width, y: crop.minY * pixelSize.height,
                          width: crop.width * pixelSize.width, height: crop.height * pixelSize.height).integral
        return rect.intersection(CGRect(origin: .zero, size: pixelSize))
    }

    enum CropHandle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight, move
    }

    /// Kırpma çerçevesini köşeden çekme ya da taşıma (öteleme orijinale oran). Sonuç resmin içinde kalır.
    static func adjust(_ start: CGRect, handle: CropHandle, translation: CGSize) -> CGRect {
        let minSide = minimumCropSide
        var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
        switch handle {
        case .move:
            let dx = min(max(translation.width, -start.minX), 1 - start.maxX)
            let dy = min(max(translation.height, -start.minY), 1 - start.maxY)
            return start.offsetBy(dx: dx, dy: dy)
        case .topLeft:
            minX = min(max(0, start.minX + translation.width), maxX - minSide)
            minY = min(max(0, start.minY + translation.height), maxY - minSide)
        case .topRight:
            maxX = max(min(1, start.maxX + translation.width), minX + minSide)
            minY = min(max(0, start.minY + translation.height), maxY - minSide)
        case .bottomLeft:
            minX = min(max(0, start.minX + translation.width), maxX - minSide)
            maxY = max(min(1, start.maxY + translation.height), minY + minSide)
        case .bottomRight:
            maxX = max(min(1, start.maxX + translation.width), minX + minSide)
            maxY = max(min(1, start.maxY + translation.height), minY + minSide)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Silgi: `point` çevresindeki `radius` (orijinal genişliğe oran) içinden geçen çizgilerin kimlikleri.
    /// `aspect` = yükseklik / genişlik; y ekseni genişlik birimine çevrilerek gerçek uzaklık ölçülür.
    static func strokesHit(_ strokes: [PhotoEditStroke], at point: CGPoint, radius: CGFloat, heightOverWidth aspect: CGFloat) -> Set<UUID> {
        func scaled(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y * aspect) }
        let target = scaled(point)
        var hit = Set<UUID>()
        for stroke in strokes {
            let limit = radius + stroke.width / 2
            let points = stroke.points.map(scaled)
            if points.count == 1 {
                if distance(target, points[0]) <= limit { hit.insert(stroke.id) }
                continue
            }
            for index in points.indices.dropFirst() where segmentDistance(target, points[index - 1], points[index]) <= limit {
                hit.insert(stroke.id)
                break
            }
        }
        return hit
    }

    /// Katmanın yaklaşık yarıçapı (orijinal genişlik biriminde; dönüşten bağımsız olsun diye çevreleyen daire).
    static func approximateRadius(of layer: PhotoEditLayer) -> CGFloat {
        switch layer.content {
        case .sticker(_, let aspect):
            let halfWidth = PhotoEditLayer.stickerWidthFraction * layer.scale / 2
            return max(halfWidth, halfWidth / max(aspect, 0.05))
        case .text(let text, _):
            let size = PhotoEditLayer.textSizeFraction * layer.scale
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            let longest = CGFloat(lines.map(\.count).max() ?? 1)
            return max(longest * size * 0.6, CGFloat(lines.count) * size * 1.2) / 2
        }
    }

    /// Dokunulan noktadaki en üstteki katman (yoksa nil). `aspect` = yükseklik / genişlik.
    static func layerHit(_ layers: [PhotoEditLayer], at point: CGPoint, heightOverWidth aspect: CGFloat, slop: CGFloat = 0.03) -> UUID? {
        for layer in layers.reversed() {
            let dx = point.x - layer.center.x
            let dy = (point.y - layer.center.y) * aspect
            if hypot(dx, dy) <= approximateRadius(of: layer) + slop { return layer.id }
        }
        return nil
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Noktanın doğru parçasına en kısa uzaklığı.
    static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(p, a) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
        return distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}
