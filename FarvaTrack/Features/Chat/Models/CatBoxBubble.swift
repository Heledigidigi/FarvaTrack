import CoreGraphics
import Foundation

// MARK: - SVG yol ayrıştırıcı (yalnızca mutlak M, L, Q, C, Z)

/// Nakış çizgileri SVG yolu olarak saklanır; bu ayrıştırıcı onları `CGPath`'e çevirir (saf, testli).
enum SVGPathParser {
    static func parse(_ string: String) -> CGPath {
        let path = CGMutablePath()
        var numbers: [CGFloat] = []
        var command: Character?

        func flush() {
            guard let command else { return }
            var index = 0
            func next(_ count: Int) -> [CGFloat]? {
                guard index + count <= numbers.count else { return nil }
                defer { index += count }
                return Array(numbers[index..<index + count])
            }
            switch command {
            case "M":
                if let p = next(2) { path.move(to: CGPoint(x: p[0], y: p[1])) }
                // M'den sonraki ek çiftler çizgi sayılır.
                while let p = next(2) { path.addLine(to: CGPoint(x: p[0], y: p[1])) }
            case "L":
                while let p = next(2) { path.addLine(to: CGPoint(x: p[0], y: p[1])) }
            case "Q":
                while let p = next(4) {
                    path.addQuadCurve(to: CGPoint(x: p[2], y: p[3]), control: CGPoint(x: p[0], y: p[1]))
                }
            case "C":
                while let p = next(6) {
                    path.addCurve(to: CGPoint(x: p[4], y: p[5]),
                                  control1: CGPoint(x: p[0], y: p[1]), control2: CGPoint(x: p[2], y: p[3]))
                }
            case "Z", "z":
                if !path.isEmpty { path.closeSubpath() }
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }

        var token = ""
        func endToken() {
            if !token.isEmpty, let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }
        for character in string {
            if character.isLetter, character != "e", character != "E" {
                endToken()
                flush()
                command = character
                if character == "Z" || character == "z" { flush(); command = nil }
            } else if character == "," || character.isWhitespace {
                endToken()
            } else if character == "-", !token.isEmpty, token.last != "e", token.last != "E" {
                endToken()
                token = "-"
            } else {
                token.append(character)
            }
        }
        endToken()
        flush()
        return path
    }
}

// MARK: - Kutu Kedi geometrisi

/// Kafa ve patiler sabit; gövde kutusu içerik büyüdükçe sağa ve yukarı uzar.
/// Tüm çizim fotoğraf pikseli uzayında yapılır, `scale` ile noktaya çevrilir.
enum CatBoxGeometry {
    static let scale: CGFloat = 0.14
    /// Karın çizgisi (fotoğraf pikseli, y).
    static let belly: CGFloat = 456
    /// Kutunun en kısa halindeki üst kenar ve sağ kenar.
    static let baseTop: CGFloat = 110
    static let baseRight: CGFloat = 1480
    /// Daraltılmış ön patinin en sol noktası.
    static let left: CGFloat = 134.8
    /// Çene altındaki patinin sağ kenarı (buraya kadar fotoğraftan, sonrası çizilir).
    static let pawRight: CGFloat = 1048.2
    static let lineWidth: CGFloat = 22
    static let cornerRadius: CGFloat = 95
    /// Kenardan taşma payı (nokta).
    static let margin: CGFloat = 6

    /// İçeriğin kutunun üst kenarından ve karın çizgisinden uzaklığı (eşit: metin dikeyde ortada kalır).
    static let verticalInset: CGFloat = 55

    /// Mesaj içeriğinin baloncuk kenarlarına uzaklığı (nokta). Gövde büyüse de sabit kalır.
    static var contentPadding: (top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        (top: verticalInset * scale + margin,
         leading: (840 - left) * scale + margin,
         bottom: (70 + verticalInset) * scale,
         trailing: 140 * scale)
    }

    /// Kutunun en küçük hali için içerik alanı (nokta).
    static var minimumContentSize: CGSize {
        CGSize(width: (baseRight - 50 - 840) * scale,
               height: ((belly - verticalInset) - (baseTop + verticalInset)) * scale)
    }

    /// Durum tikinin merkezi, baloncuğun sağ alt köşesinden (nokta): arka bacak ile karın çizgisinin
    /// birleştiği köşe, karın çizgisinin üstünde (yarısı kedinin içinde, yarısı dışında).
    static var statusMarkOffset: CGSize {
        CGSize(width: 160 * scale, height: 70 * scale - 1)
    }

    struct Layout: Equatable {
        /// Kutunun üst kenarı ve sağ kenarı (fotoğraf pikseli).
        var top: CGFloat
        var right: CGFloat
        /// Fotoğraf pikselini noktaya çeviren dönüşüm: (p - origin) × scale.
        var origin: CGPoint

        var transform: CGAffineTransform {
            CGAffineTransform(scaleX: CatBoxGeometry.scale, y: CatBoxGeometry.scale)
                .translatedBy(x: -origin.x, y: -origin.y)
        }
    }

    /// Baloncuğun toplam boyutundan kutunun konumu. İçerik en küçük boyuttan küçükse kutu taban halinde kalır.
    static func layout(for size: CGSize) -> Layout {
        let right = max(baseRight, (size.width - margin) / scale + left - 90)
        let top = min(baseTop, belly + 70 - (size.height - margin) / scale)
        return Layout(top: top, right: right, origin: CGPoint(x: left - margin / scale, y: top - margin / scale))
    }

    /// İçerik boyutundan baloncuğun toplam boyutu (testler ve önizleme için).
    static func bubbleSize(content: CGSize) -> CGSize {
        let padding = contentPadding
        let minimum = minimumContentSize
        return CGSize(width: max(content.width, minimum.width) + padding.leading + padding.trailing,
                      height: max(content.height, minimum.height) + padding.top + padding.bottom)
    }

    // MARK: Yollar (fotoğraf pikseli)

    static func bodyFill(_ l: Layout) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 520, y: 214))
        addBackCurve(to: path, from: 214, top: l.top)
        path.addLine(to: CGPoint(x: l.right - cornerRadius, y: l.top))
        path.addQuadCurve(to: CGPoint(x: l.right, y: l.top + cornerRadius), control: CGPoint(x: l.right, y: l.top))
        path.addLine(to: CGPoint(x: l.right, y: belly))
        path.addLine(to: CGPoint(x: 700, y: belly))
        path.addLine(to: CGPoint(x: 700, y: 214))
        path.closeSubpath()
        return path
    }

    /// Kafadan yükselen sırt + düz üst kenar + yuvarlak köşe + sağ kenar.
    static func back(_ l: Layout) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 528, y: 206))
        addBackCurve(to: path, from: 206, top: l.top)
        path.addLine(to: CGPoint(x: l.right - cornerRadius, y: l.top))
        path.addQuadCurve(to: CGPoint(x: l.right, y: l.top + cornerRadius), control: CGPoint(x: l.right, y: l.top))
        path.addLine(to: CGPoint(x: l.right, y: belly - 100))
        return path
    }

    /// Eğim ilk yarıda yumuşak başlar, sonra dik yükselir.
    private static func addBackCurve(to path: CGMutablePath, from startY: CGFloat, top: CGFloat) {
        path.addCurve(to: CGPoint(x: 790, y: top),
                      control1: CGPoint(x: 585, y: (startY + top) / 2 + 10),
                      control2: CGPoint(x: 615, y: top + 6))
    }

    static func belly(_ l: Layout) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: pawRight - 14, y: belly))
        path.addLine(to: CGPoint(x: l.right - 50, y: belly))
        return path
    }

    /// Sağ alttaki arka ayak (kısaltılmış).
    static func foot(_ l: Layout, closed: Bool) -> CGPath {
        let x = l.right, b = belly
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: b - 100))
        path.addCurve(to: CGPoint(x: x + 66, y: b - 12), control1: CGPoint(x: x + 2, y: b - 56), control2: CGPoint(x: x + 46, y: b - 42))
        path.addQuadCurve(to: CGPoint(x: x + 64, y: b + 30), control: CGPoint(x: x + 82, y: b + 14))
        path.addQuadCurve(to: CGPoint(x: x + 36, y: b + 34), control: CGPoint(x: x + 54, y: b + 38))
        path.addLine(to: CGPoint(x: x - 10, y: b + 26))
        path.addQuadCurve(to: CGPoint(x: x - 46, y: b), control: CGPoint(x: x - 36, y: b + 20))
        if closed { path.closeSubpath() }
        return path
    }

    static func toes(_ l: Layout) -> CGPath {
        let x = l.right, b = belly
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x + 56, y: b + 8)); path.addLine(to: CGPoint(x: x + 64, y: b + 25))
        path.move(to: CGPoint(x: x + 40, y: b + 13)); path.addLine(to: CGPoint(x: x + 45, y: b + 31))
        return path
    }

    /// Fotoğraftan gelen kafa/pati çizimlerinin kullanılan bölgesi (eski sırt çizgisi dışarıda kalır).
    static let headClip: CGPath = {
        let path = CGMutablePath()
        path.addLines(between: [
            CGPoint(x: 0, y: 0), CGPoint(x: 470, y: 0), CGPoint(x: 470, y: 197), CGPoint(x: 565, y: 197),
            CGPoint(x: 650, y: 203), CGPoint(x: 790, y: 150), CGPoint(x: 820, y: 150), CGPoint(x: 820, y: 380),
            CGPoint(x: pawRight, y: 380), CGPoint(x: pawRight, y: belly + 90), CGPoint(x: 0, y: belly + 90)
        ])
        path.closeSubpath()
        return path
    }()

    static let ink: CGPath = SVGPathParser.parse(CatBoxArtData.ink)
    static let silhouette: CGPath = SVGPathParser.parse(CatBoxArtData.silhouette)
}
