import SwiftUI

// Widget çizimleri 170×170'lik sabit bir tuvalde tasarlandı (tasarım dosyalarındaki koordinatlar).
// `ArtCanvas` bu tuvali widget'ın gerçek boyutuna ölçekler; böylece çizim koordinatları aynen kullanılır.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// 170×170 tasarım tuvalini verilen alana sığdırır.
struct ArtCanvas<Content: View>: View {
    var size: CGFloat = 170
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / size
            ZStack(alignment: .topLeading) {
                content()
            }
            .frame(width: size, height: size, alignment: .topLeading)
            .scaleEffect(scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Basit SVG yol çözümleyici (yalnızca mutlak M, L, C, Q, Z komutları).
/// Koordinatlar 170×170 tuvale göredir ve verilen dikdörtgene ölçeklenir.
struct SVGShape: Shape {
    let d: String

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 170
        let sy = rect.height / 170
        let tokens = SVGShape.tokenize(d)
        var path = Path()
        var index = 0
        var command: Character = "M"

        func number() -> CGFloat {
            defer { index += 1 }
            guard index < tokens.count else { return 0 }
            return CGFloat(Double(tokens[index]) ?? 0)
        }
        func point() -> CGPoint {
            let x = number()
            let y = number()
            return CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        while index < tokens.count {
            let token = tokens[index]
            if token.count == 1, let c = token.first, "MLCQZ".contains(c) {
                command = c
                index += 1
                if c == "Z" {
                    path.closeSubpath()
                    continue
                }
            }
            switch command {
            case "M":
                path.move(to: point())
                command = "L"
            case "L":
                path.addLine(to: point())
            case "C":
                let c1 = point()
                let c2 = point()
                let end = point()
                path.addCurve(to: end, control1: c1, control2: c2)
            case "Q":
                let c1 = point()
                let end = point()
                path.addQuadCurve(to: end, control: c1)
            default:
                index += 1
            }
        }
        return path
    }

    static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current) }
            current = ""
        }
        for ch in s {
            if ch.isLetter {
                flush()
                tokens.append(String(ch))
            } else if ch == "-" {
                if !current.isEmpty && current.last != "e" { flush() }
                current.append(ch)
            } else if ch.isNumber || ch == "." {
                if ch == "." && current.contains(".") { flush() }
                current.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }
}

// MARK: - Tuval üzerinde konumlu temel şekiller

/// Merkezi ve yarıçaplarıyla elips (tasarım koordinatlarında).
struct Oval<S: ShapeStyle>: View {
    let cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat
    let style: S
    var rotation: Double = 0

    var body: some View {
        Ellipse()
            .fill(style)
            .frame(width: rx * 2, height: ry * 2)
            .rotationEffect(.degrees(rotation))
            .position(x: cx, y: cy)
    }
}

/// Tasarım koordinatlarında dolgu yolu.
struct FillPath<S: ShapeStyle>: View {
    let d: String
    let style: S

    var body: some View {
        SVGShape(d: d).fill(style).frame(width: 170, height: 170)
    }
}

/// Tasarım koordinatlarında çizgi yolu.
struct StrokePath<S: ShapeStyle>: View {
    let d: String
    let style: S
    var width: CGFloat = 1.5

    var body: some View {
        SVGShape(d: d)
            .stroke(style, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .frame(width: 170, height: 170)
    }
}

/// Dört köşeli parıltı.
struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let k = r * 0.28
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addCurve(to: CGPoint(x: c.x + r, y: c.y), control1: CGPoint(x: c.x + k * 0.5, y: c.y - k), control2: CGPoint(x: c.x + k, y: c.y - k * 0.5))
        p.addCurve(to: CGPoint(x: c.x, y: c.y + r), control1: CGPoint(x: c.x + k, y: c.y + k * 0.5), control2: CGPoint(x: c.x + k * 0.5, y: c.y + k))
        p.addCurve(to: CGPoint(x: c.x - r, y: c.y), control1: CGPoint(x: c.x - k * 0.5, y: c.y + k), control2: CGPoint(x: c.x - k, y: c.y + k * 0.5))
        p.addCurve(to: CGPoint(x: c.x, y: c.y - r), control1: CGPoint(x: c.x - k, y: c.y - k * 0.5), control2: CGPoint(x: c.x - k * 0.5, y: c.y - k))
        p.closeSubpath()
        return p
    }
}

/// Kalp.
struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let x = rect.minX, y = rect.minY
        var p = Path()
        p.move(to: CGPoint(x: x + w * 0.5, y: y + h))
        p.addCurve(to: CGPoint(x: x, y: y + h * 0.32), control1: CGPoint(x: x + w * 0.1, y: y + h * 0.72), control2: CGPoint(x: x, y: y + h * 0.5))
        p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.18), control1: CGPoint(x: x, y: y), control2: CGPoint(x: x + w * 0.42, y: y))
        p.addCurve(to: CGPoint(x: x + w, y: y + h * 0.32), control1: CGPoint(x: x + w * 0.58, y: y), control2: CGPoint(x: x + w, y: y))
        p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h), control1: CGPoint(x: x + w, y: y + h * 0.5), control2: CGPoint(x: x + w * 0.9, y: y + h * 0.72))
        p.closeSubpath()
        return p
    }
}

/// Konumlu küçük süs (parıltı/kalp).
struct Deco<S: Shape>: View {
    let shape: S
    let x: CGFloat, y: CGFloat, size: CGFloat
    let color: Color

    var body: some View {
        shape.fill(color).frame(width: size, height: size).position(x: x, y: y)
    }
}

/// Pati izi (ortada büyük yastık + dört parmak).
struct PawPrint: View {
    var color: Color = .white

    var body: some View {
        ZStack {
            Ellipse().fill(color).frame(width: 9.2, height: 7.6).offset(y: 2)
            Circle().fill(color).frame(width: 3.6, height: 3.6).offset(x: -4.6, y: -3.4)
            Circle().fill(color).frame(width: 3.6, height: 3.6).offset(x: -1.6, y: -5.6)
            Circle().fill(color).frame(width: 3.6, height: 3.6).offset(x: 1.6, y: -5.6)
            Circle().fill(color).frame(width: 3.6, height: 3.6).offset(x: 4.6, y: -3.4)
        }
        .frame(width: 16, height: 16)
    }
}

/// Tema arka planı: tek renk ya da hafif geçiş.
enum WidgetFill {
    case solid(Color)
    case gradient(Color, Color)

    @ViewBuilder var view: some View {
        switch self {
        case .solid(let c):
            c
        case .gradient(let a, let b):
            LinearGradient(colors: [a, b], startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1))
        }
    }
}
