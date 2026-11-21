import Foundation
import CoreGraphics

// MARK: - Maske

/// Tek kanallı (0…255) saydamlık maskesi. 0 = tamamen silinmiş, 255 = tamamen görünür.
/// Satır satır, sol üstten başlar (görüntü koordinatları).
struct StickerMask: Equatable {
    let width: Int
    let height: Int
    var alpha: [UInt8]

    init(width: Int, height: Int, fill: UInt8 = 255) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.alpha = Array(repeating: fill, count: self.width * self.height)
    }

    init(width: Int, height: Int, alpha: [UInt8]) {
        precondition(alpha.count == width * height, "maske boyutu uyuşmuyor")
        self.width = width
        self.height = height
        self.alpha = alpha
    }

    subscript(x: Int, y: Int) -> UInt8 {
        get { alpha[y * width + x] }
        set { alpha[y * width + x] = newValue }
    }

    var isEmpty: Bool { !alpha.contains { $0 > 0 } }

    /// Eşiğin üstündeki piksellerin sınır kutusu (yoksa `nil`).
    func boundingBox(threshold: UInt8 = 8) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where alpha[row + x] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Görünür piksel oranı (0…1); testler ve "boş sticker" denetimi için.
    var coverage: Double {
        guard !alpha.isEmpty else { return 0 }
        return Double(alpha.reduce(0) { $0 + Int($1) }) / Double(alpha.count * 255)
    }
}

// MARK: - Fırça

enum StickerBrushMode: String, CaseIterable, Identifiable {
    /// Arka planı siler.
    case erase
    /// Yanlışlıkla silineni geri getirir (orijinal fotoğraftan).
    case restore

    var id: Self { self }

    var title: String {
        switch self {
        case .erase: return "Silgi"
        case .restore: return "Onar"
        }
    }

    var systemImage: String {
        switch self {
        case .erase: return "eraser"
        case .restore: return "paintbrush.pointed"
        }
    }
}

struct StickerBrush: Equatable {
    var mode: StickerBrushMode
    /// Görüntü pikseli cinsinden yarıçap.
    var radius: Double
    /// 0 = sert kenar, 1 = tamamen yumuşak (merkezden kenara doğru azalan).
    var softness: Double

    /// Merkezden `distance` uzaklıktaki etkinin gücü (0…1).
    static func weight(distance: Double, radius: Double, softness: Double) -> Double {
        guard radius > 0, distance < radius else { return 0 }
        let soft = min(max(softness, 0), 1)
        let core = radius * (1 - soft)
        if distance <= core { return 1 }
        // Sert çekirdekten kenara yumuşak geçiş (smoothstep).
        let t = (distance - core) / max(radius - core, .ulpOfOne)
        let s = 1 - t
        return s * s * (3 - 2 * s)
    }
}

extension StickerMask {
    /// Tek bir fırça damgası.
    mutating func stamp(at center: CGPoint, brush: StickerBrush) {
        let radius = brush.radius
        guard radius > 0 else { return }
        let minX = max(0, Int((center.x - radius).rounded(.down)))
        let maxX = min(width - 1, Int((center.x + radius).rounded(.up)))
        let minY = max(0, Int((center.y - radius).rounded(.down)))
        let maxY = min(height - 1, Int((center.y + radius).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }

        for y in minY...maxY {
            let dy = Double(y) + 0.5 - center.y
            let row = y * width
            for x in minX...maxX {
                let dx = Double(x) + 0.5 - center.x
                let w = StickerBrush.weight(distance: (dx * dx + dy * dy).squareRoot(), radius: radius, softness: brush.softness)
                guard w > 0 else { continue }
                let current = Double(alpha[row + x])
                let updated: Double
                switch brush.mode {
                case .erase: updated = current * (1 - w)
                case .restore: updated = current + (255 - current) * w
                }
                alpha[row + x] = UInt8(clamping: Int(updated.rounded()))
            }
        }
    }

    /// İki nokta arasını boşluksuz boyar (hızlı parmak hareketinde çizgi kopmaz).
    mutating func stroke(from start: CGPoint, to end: CGPoint, brush: StickerBrush) {
        let spacing = max(1, brush.radius * 0.25)
        let distance = hypot(end.x - start.x, end.y - start.y)
        let steps = max(1, Int((distance / spacing).rounded(.up)))
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            stamp(at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), brush: brush)
        }
    }
}

// MARK: - Kontur için mesafe alanı

extension StickerMask {
    /// Eşiğin üstündeki piksele olan yaklaşık Öklid uzaklığı (piksel), iki geçişli 3-4 chamfer dönüşümü.
    /// Görünür piksellerde 0. O(n): 512×512'de anında.
    func distanceField(threshold: UInt8 = 127) -> [Float] {
        let infinity: Float = .greatestFiniteMagnitude / 4
        var distance = [Float](repeating: infinity, count: width * height)
        for index in 0..<alpha.count where alpha[index] > threshold { distance[index] = 0 }
        let straight: Float = 1
        let diagonal: Float = 1.4142135

        // İleri geçiş (sol üstten)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                var value = distance[index]
                if value == 0 { continue }
                if x > 0 { value = min(value, distance[index - 1] + straight) }
                if y > 0 {
                    value = min(value, distance[index - width] + straight)
                    if x > 0 { value = min(value, distance[index - width - 1] + diagonal) }
                    if x < width - 1 { value = min(value, distance[index - width + 1] + diagonal) }
                }
                distance[index] = value
            }
        }
        // Geri geçiş (sağ alttan)
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let index = y * width + x
                var value = distance[index]
                if value == 0 { continue }
                if x < width - 1 { value = min(value, distance[index + 1] + straight) }
                if y < height - 1 {
                    value = min(value, distance[index + width] + straight)
                    if x < width - 1 { value = min(value, distance[index + width + 1] + diagonal) }
                    if x > 0 { value = min(value, distance[index + width - 1] + diagonal) }
                }
                distance[index] = value
            }
        }
        return distance
    }

    /// Şeklin etrafında `width` piksel kalınlığında kontur maskesi (kenarı 1 piksel yumuşak).
    func outline(width outlineWidth: Double, threshold: UInt8 = 127) -> StickerMask {
        guard outlineWidth > 0 else { return StickerMask(width: width, height: height, fill: 0) }
        let distance = distanceField(threshold: threshold)
        let limit = Float(outlineWidth)
        let values = distance.map { value -> UInt8 in
            if value <= limit - 0.5 { return 255 }
            if value >= limit + 0.5 { return 0 }
            return UInt8(clamping: Int(((limit + 0.5 - value) * 255).rounded()))
        }
        return StickerMask(width: width, height: height, alpha: values)
    }
}

// MARK: - Geometri

enum StickerGeometry {
    /// Fırça noktası parmağın bu kadar üstünde (pt): parmak boyanan yeri kapatmasın.
    static let brushOffset: CGFloat = 70

    static func brushPoint(forTouch touch: CGPoint, offset: CGFloat = brushOffset) -> CGPoint {
        CGPoint(x: touch.x, y: touch.y - offset)
    }

    /// Ekrandaki noktayı görüntü pikseline çevirir. `imageFrame`: görüntünün ekrandaki (yakınlaştırılmış) çerçevesi.
    static func imagePoint(fromView point: CGPoint, imageFrame: CGRect, pixelSize: CGSize) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        return CGPoint(
            x: (point.x - imageFrame.minX) / imageFrame.width * pixelSize.width,
            y: (point.y - imageFrame.minY) / imageFrame.height * pixelSize.height
        )
    }

    /// Ekrandaki fırça çapı (pt) → görüntü pikseli cinsinden yarıçap; yakınlaştırınca fırça ekranda aynı boyda kalır.
    static func pixelRadius(forDiameter diameter: CGFloat, imageFrame: CGRect, pixelSize: CGSize) -> Double {
        guard imageFrame.width > 0 else { return 0 }
        return Double(diameter / 2 * pixelSize.width / imageFrame.width)
    }

    /// Görüntüyü kutuya sığdırır (en-boy korunur, ortalanır).
    static func aspectFit(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }

    /// Çıktı yerleşimi: içerik `maxSide` içine sığar, etrafında kontur + kenar boşluğu kalır.
    static func outputLayout(contentSize: CGSize, maxSide: Int, inset: Int) -> (canvas: CGSize, scale: Double) {
        let available = Double(max(1, maxSide - 2 * inset))
        let longest = Double(max(contentSize.width, contentSize.height))
        guard longest > 0 else { return (.zero, 1) }
        let scale = min(1, available / longest)
        let width = min(maxSide, Int((Double(contentSize.width) * scale).rounded(.up)) + 2 * inset)
        let height = min(maxSide, Int((Double(contentSize.height) * scale).rounded(.up)) + 2 * inset)
        return (CGSize(width: width, height: height), scale)
    }
}

// MARK: - Geri al / ileri al

struct UndoStack<State: Equatable> {
    private(set) var past: [State] = []
    private(set) var future: [State] = []
    let limit: Int

    init(limit: Int = 30) { self.limit = max(1, limit) }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// Değişiklikten ÖNCEKİ hal kaydedilir; yeni değişiklik ileri al geçmişini siler.
    mutating func record(_ state: State) {
        if past.last == state { return }
        past.append(state)
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    mutating func undo(current: State) -> State? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    mutating func redo(current: State) -> State? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }

    /// Son kaydı ileri al geçmişine eklemeden geri verir (yarım kalan işlemi iptal etmek için).
    mutating func discardLast() -> State? {
        past.popLast()
    }

    mutating func clear() {
        past.removeAll()
        future.removeAll()
    }
}
