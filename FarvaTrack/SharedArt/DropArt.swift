import SwiftUI

// Damla (su widget'ı) çizimi; uygulama ve widget hedefinde ortak derlenir.

// MARK: - Ruh hâli

enum DropMood: Equatable {
    case dead, sad, ok, happy, full

    init(total: Int, goal: Int) {
        guard total > 0 else { self = .dead; return }
        let r = goal > 0 ? Double(total) / Double(goal) : 0
        switch r {
        case ..<0.34: self = .sad
        case ..<0.67: self = .ok
        case ..<1: self = .happy
        default: self = .full
        }
    }

    var label: String {
        switch self {
        case .dead: return "bitkin"
        case .sad: return "üzgün"
        case .ok: return "keyifli"
        case .happy: return "mutlu"
        case .full: return "çok mutlu"
        }
    }
}

// MARK: - Tema

struct DropTheme {
    var fill: WidgetFill
    var text: Color
    var pill: Color
    var base: Color
    var stroke: Color
    var ink = Color(hex: 0x23394B)
    var cheek = Color(hex: 0xF7A9BC)
    var water1 = Color(hex: 0x8FCBF2)
    var water2 = Color(hex: 0x3F8FD2)
    var back1 = Color(hex: 0xC4E3F8)
    var back2 = Color(hex: 0x82BCE8)
    var serif = false
    var vintageFrame = false
    var isCat = false
    var glass = false

    static func make(_ option: WaterThemeOption) -> DropTheme {
        switch option {
        case .krem: return DropTheme(fill: .solid(Color(hex: 0xFFF7F2)), text: Color(hex: 0x1E4E73), pill: Color(hex: 0xEAF4FB), base: Color(hex: 0xEAF4FB), stroke: Color(hex: 0xCFE4F2))
        case .pamukPembe: return DropTheme(fill: .solid(Color(hex: 0xFFE9EF)), text: Color(hex: 0x7A2E45), pill: .white, base: Color(hex: 0xF3F8FC), stroke: Color(hex: 0xF3C9D5))
        case .nane: return DropTheme(fill: .solid(Color(hex: 0xE4F5EE)), text: Color(hex: 0x1F5B4A), pill: .white, base: Color(hex: 0xF1FAFD), stroke: Color(hex: 0xBFE3D6))
        case .lavanta: return DropTheme(fill: .solid(Color(hex: 0xEEE9FB)), text: Color(hex: 0x4A3D86), pill: .white, base: Color(hex: 0xF2F6FD), stroke: Color(hex: 0xD3CBF0))
        case .gece: return DropTheme(fill: .solid(Color(hex: 0x1B2433)), text: Color(hex: 0xE6F1FA), pill: .white.opacity(0.14), base: Color(hex: 0xDCEAF6), stroke: Color(hex: 0x9FC3E3))
        case .bordo: return DropTheme(fill: .solid(Color(hex: 0x800020)), text: Color(hex: 0xFFF1F4), pill: .white.opacity(0.18), base: Color(hex: 0xFBEFF2), stroke: Color(hex: 0xF3C2CF))
        case .safak: return DropTheme(fill: .gradient(Color(hex: 0xFFE9D9), Color(hex: 0xFBD3DF)), text: Color(hex: 0x7A2E45), pill: .white.opacity(0.75), base: Color(hex: 0xF5F9FC), stroke: Color(hex: 0xF2C6D3))
        case .okyanus: return DropTheme(fill: .gradient(Color(hex: 0xE6F6FB), Color(hex: 0xC8DCF7)), text: Color(hex: 0x1E4E73), pill: .white.opacity(0.75), base: Color(hex: 0xF4F9FD), stroke: Color(hex: 0xB7D4EE))
        case .lavantaSisi: return DropTheme(fill: .gradient(Color(hex: 0xF3EAFB), Color(hex: 0xDCE5FA)), text: Color(hex: 0x4A3D86), pill: .white.opacity(0.75), base: Color(hex: 0xF5F7FD), stroke: Color(hex: 0xCFC6EE))
        case .gunBatimi: return DropTheme(fill: .gradient(Color(hex: 0x2A2142), Color(hex: 0x6E3653)), text: Color(hex: 0xFFEFF4), pill: .white.opacity(0.16), base: Color(hex: 0xF5EDF4), stroke: Color(hex: 0xE6C3D6))
        case .nostalji:
            return DropTheme(fill: .gradient(Color(hex: 0xF4E7CF), Color(hex: 0xE5CFA9)), text: Color(hex: 0x5A3E28), pill: Color(hex: 0xFFF8EB, opacity: 0.85),
                             base: Color(hex: 0xF7EEDD), stroke: Color(hex: 0xB79B70), ink: Color(hex: 0x4A3424), cheek: Color(hex: 0xD9A29C),
                             water1: Color(hex: 0x9DBDB5), water2: Color(hex: 0x5F8A8E), back1: Color(hex: 0xC7D8CF), back2: Color(hex: 0x8FAEA9),
                             serif: true, vintageFrame: true)
        case .kedi:
            return DropTheme(fill: .gradient(Color(hex: 0xFFF2E4), Color(hex: 0xF9D8CF)), text: Color(hex: 0x7A4536), pill: .white.opacity(0.8),
                             base: Color(hex: 0xF7FBFD), stroke: Color(hex: 0xEDC4B4), ink: Color(hex: 0x3B2A2A), cheek: Color(hex: 0xF4A7B0),
                             water1: Color(hex: 0xA6DAEC), water2: Color(hex: 0x5DA9D1), back1: Color(hex: 0xCFEAF4), back2: Color(hex: 0x93C7E2), isCat: true)
        }
    }

    /// Şeffaf / renk tonlu ana ekran: sistem içeriği tek renge boyar, çizimi sadeleştiriyoruz.
    func glassVersion() -> DropTheme {
        var t = self
        t.fill = .solid(.clear)
        t.text = .white
        t.pill = .white.opacity(0.18)
        t.base = .white.opacity(0.08)
        t.stroke = .white
        t.ink = .white
        t.cheek = .white.opacity(0.55)
        t.water1 = .white.opacity(0.35)
        t.water2 = .white.opacity(0.25)
        t.back1 = .white.opacity(0.18)
        t.back2 = .white.opacity(0.12)
        t.glass = true
        return t
    }
}

// MARK: - Şekiller

enum DropPaths {
    static let drop = "M85 30 C 85 30 46 78 46 106 C 46 127.54 63.46 145 85 145 C 106.54 145 124 127.54 124 106 C 124 78 85 30 85 30 Z"
    static let cat = "M58 62 C 56 50 57 38 60 30 C 63 31 72 38 76 44 Q 85 41 94 44 C 98 38 107 31 110 30 C 113 38 114 50 112 62 C 116 72 114 86 104 94 C 120 104 128 122 128 136 C 128 146 120 150 108 150 L 62 150 C 50 150 42 146 42 136 C 42 122 50 104 66 94 C 56 86 54 72 58 62 Z"
}

/// Su yüzeyi: seviye değişince yay animasyonuyla yükselir.
struct WaveFill: Shape {
    var levelY: CGFloat
    var phase: CGFloat
    var amplitude: CGFloat = 1.6

    var animatableData: CGFloat {
        get { levelY }
        set { levelY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 170
        var p = Path()
        var x: CGFloat = 30
        p.move(to: CGPoint(x: x * s, y: (levelY + amplitude * sin(x * 0.09 + phase)) * s))
        while x <= 140 {
            x += 4
            p.addLine(to: CGPoint(x: x * s, y: (levelY + amplitude * sin(x * 0.09 + phase)) * s))
        }
        p.addLine(to: CGPoint(x: 144 * s, y: 172 * s))
        p.addLine(to: CGPoint(x: 26 * s, y: 172 * s))
        p.closeSubpath()
        return p
    }
}

// MARK: - Damla çizimi

struct DropArt: View {
    let total: Int
    let goal: Int
    let theme: DropTheme

    private var mood: DropMood { DropMood(total: total, goal: goal) }
    private var progress: CGFloat { goal > 0 ? min(CGFloat(total) / CGFloat(goal), 1) : 0 }
    private var shapePath: String { theme.isCat ? DropPaths.cat : DropPaths.drop }
    private var levelY: CGFloat {
        let bottom: CGFloat = theme.isCat ? 150 : 145
        let top: CGFloat = theme.isCat ? 34 : 30
        return bottom - progress * (bottom - top)
    }
    private var isDead: Bool { mood == .dead }
    private var baseColor: Color { isDead && !theme.glass ? Color(hex: 0xEEF1F4) : theme.base }
    private var strokeColor: Color { isDead && !theme.glass ? Color(hex: 0xD5DCE2) : theme.stroke }

    var body: some View {
        ArtCanvas {
            if theme.isCat {
                StrokePath(d: "M122 146 C 142 148 151 134 147 120 C 145 112 151 105 157 108", style: strokeColor, width: 9)
            }
            FillPath(d: shapePath, style: baseColor)

            // Su (arkadaki açık katman + öndeki koyu katman), şeklin içine kırpılır
            ZStack {
                WaveFill(levelY: levelY - 2.5, phase: 1.7)
                    .fill(LinearGradient(colors: [theme.back1, theme.back2], startPoint: .top, endPoint: .bottom))
                WaveFill(levelY: levelY, phase: 0)
                    .fill(LinearGradient(colors: [theme.water1, theme.water2], startPoint: .top, endPoint: .bottom))
            }
            .frame(width: 170, height: 170)
            .opacity(total > 0 ? 1 : 0)
            .mask(SVGShape(d: shapePath).frame(width: 170, height: 170))
            .animation(.spring(response: 0.7, dampingFraction: 0.55), value: total)

            StrokePath(d: shapePath, style: strokeColor, width: theme.glass ? 2 : 1.5)

            if theme.isCat {
                StrokePath(d: "M76 150 L76 141 M94 150 L94 141", style: strokeColor, width: 1.8)
                Oval(cx: 64, cy: 112, rx: 4.5, ry: 9, style: Color.white.opacity(0.8), rotation: 25)
            } else {
                Oval(cx: 66, cy: 76, rx: 4.5, ry: 9, style: Color.white.opacity(0.8), rotation: 25)
                Oval(cx: 71, cy: 92, rx: 1.8, ry: 1.8, style: Color.white.opacity(0.7))
            }

            DropFace(mood: mood, theme: theme)
                .offset(y: theme.isCat ? -42 : 0)
                .id(mood)
                .transition(.scale(scale: 0.6).combined(with: .opacity))

            DropDecorations(mood: mood, isCat: theme.isCat)
                .id("deco-\(mood.label)")
                .transition(.scale(scale: 0.3).combined(with: .opacity))
        }
    }
}

/// Damlanın yüzü (tasarım koordinatlarında, merkez ≈ 85,116).
struct DropFace: View {
    let mood: DropMood
    let theme: DropTheme

    private var ink: Color { theme.ink }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch mood {
            case .dead:
                StrokePath(d: "M71.5 107.5 L78.5 114.5 M78.5 107.5 L71.5 114.5 M91.5 107.5 L98.5 114.5 M98.5 107.5 L91.5 114.5",
                           style: theme.glass ? Color.white : Color(hex: 0x6E7B86), width: 2.4)
                StrokePath(d: "M79.5 122.5 L90.5 122.5", style: theme.glass ? Color.white : Color(hex: 0x6E7B86), width: 2.2)
                FillPath(d: "M85.5 122.5 Q 85.5 127.8 88 127.8 Q 90.5 127.8 90.5 122.5 Z", style: theme.glass ? Color.white.opacity(0.5) : Color(hex: 0xF2A3B3))
            case .sad:
                StrokePath(d: "M69 105 L79 102 M91 102 L101 105", style: ink, width: 1.8)
                eyes(scale: 0.9)
                StrokePath(d: "M71.5 116 Q 75 117.6 78.5 116 M91.5 116 Q 95 117.6 98.5 116", style: theme.glass ? Color.white.opacity(0.6) : Color(hex: 0x8FCBF2), width: 1.6)
                StrokePath(d: "M80.5 124.8 Q 85 120.6 89.5 124.8", style: ink, width: 2.1)
                FillPath(d: "M102 115 C 102 115 99.6 118.8 99.6 120.3 C 99.6 121.6 100.7 122.7 102 122.7 C 103.3 122.7 104.4 121.6 104.4 120.3 C 104.4 118.8 102 115 102 115 Z",
                         style: theme.glass ? Color.white.opacity(0.6) : Color(hex: 0x8FCBF2))
                cheeks(rx: 5, ry: 2.6)
            case .ok:
                eyes(scale: 1)
                StrokePath(d: "M80.5 120 Q 82.75 123.6 85 120 Q 87.75 123.6 89.5 120", style: ink, width: 2)
                cheeks(rx: 6, ry: 3.3)
            case .happy:
                StrokePath(d: "M71 112.5 Q 75 107 79 112.5 M91 112.5 Q 95 107 99 112.5", style: ink, width: 2.6)
                openMouth(fill: "M79 119 Q 85 127.5 91 119 Z", tongue: "M82.2 123.4 Q 85 121.8 87.8 123.4 Q 86.6 125.4 85 125.4 Q 83.4 125.4 82.2 123.4 Z")
                cheeks(rx: 6.5, ry: 3.5)
            case .full:
                if theme.isCat {
                    // Kediye özgü: mırlayan kapalı gözler, kalp burun, "ω" ağız ve dil ucu
                    StrokePath(d: "M70.5 110 Q 75 105.5 79.5 110 M90.5 110 Q 95 105.5 99.5 110", style: ink, width: 2.6)
                    FillPath(d: "M85 119 C 82 117 82.3 114.6 85 115.8 C 87.7 114.6 88 117 85 119 Z", style: theme.glass ? Color.white : Color(hex: 0xE98A9F))
                    FillPath(d: "M86 122.6 Q 86 127 88.2 127 Q 90.3 127 89.6 122.2 Z", style: theme.glass ? Color.white.opacity(0.6) : Color(hex: 0xF28FA5))
                    StrokePath(d: "M80.5 120.5 Q 82.75 123.8 85 120.5 Q 87.25 123.8 89.5 120.5", style: ink, width: 1.9)
                } else {
                    Deco(shape: Sparkle(), x: 75, y: 111, size: 11, color: ink)
                    Deco(shape: Sparkle(), x: 95, y: 111, size: 11, color: ink)
                    openMouth(fill: "M77.5 118 Q 85 131 92.5 118 Z", tongue: "M81.5 124 Q 85 121.8 88.5 124 Q 87 127.2 85 127.2 Q 83 127.2 81.5 124 Z")
                }
                cheeks(rx: 6.5, ry: 3.5)
            }

            if theme.isCat {
                catWhiskers
            }
        }
        .frame(width: 170, height: 170, alignment: .topLeading)
    }

    private func eyes(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([75.0, 95.0], id: \.self) { x in
                Oval(cx: x, cy: 111, rx: 3.8 * scale, ry: 4.6 * scale, style: ink)
                if !theme.glass {
                    Oval(cx: x + 1.3, cy: 109.2, rx: 1.5, ry: 1.5, style: Color.white)
                    Oval(cx: x - 1.1, cy: 112.8, rx: 0.7, ry: 0.7, style: Color.white)
                }
            }
        }
    }

    private func cheeks(rx: CGFloat, ry: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Oval(cx: 65, cy: 120, rx: rx, ry: ry, style: theme.cheek.opacity(0.9))
            Oval(cx: 105, cy: 120, rx: rx, ry: ry, style: theme.cheek.opacity(0.9))
        }
    }

    private func openMouth(fill: String, tongue: String) -> some View {
        ZStack(alignment: .topLeading) {
            FillPath(d: fill, style: ink)
            FillPath(d: tongue, style: theme.glass ? Color.black.opacity(0.25) : Color(hex: 0xF28FA5))
        }
    }

    /// Bıyıklar ruh hâline göre iner/kalkar; burun (çok mutluda kalp burun ayrı çizilir).
    private var catWhiskers: some View {
        let angle: Double = {
            switch mood {
            case .dead, .sad: return -14
            case .ok: return 0
            case .happy, .full: return 9
            }
        }()
        return ZStack(alignment: .topLeading) {
            StrokePath(d: "M61 118.5 L46 116 M61 121.5 L45 122 M61 124.5 L47 128", style: ink.opacity(0.7), width: 1.3)
                .rotationEffect(.degrees(angle), anchor: UnitPoint(x: 61.0 / 170, y: 121.0 / 170))
            StrokePath(d: "M109 118.5 L124 116 M109 121.5 L125 122 M109 124.5 L123 128", style: ink.opacity(0.7), width: 1.3)
                .rotationEffect(.degrees(-angle), anchor: UnitPoint(x: 109.0 / 170, y: 121.0 / 170))
            if mood != .full {
                FillPath(d: "M82.6 115.2 L87.4 115.2 L85 118.2 Z", style: theme.glass ? Color.white : Color(hex: 0xE98A9F))
            }
        }
    }
}

/// Mutlu hâlde kalpler, hedefte parıltılar (kedide mırlama çizgileri ve balık).
struct DropDecorations: View {
    let mood: DropMood
    let isCat: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch mood {
            case .happy:
                Deco(shape: HeartShape(), x: 136, y: 50, size: 17, color: Color(hex: 0xF28FA5))
                Deco(shape: HeartShape(), x: 34, y: 64, size: 12.5, color: Color(hex: 0xF7A9BC))
                Deco(shape: HeartShape(), x: 134, y: 98, size: 10, color: Color(hex: 0xF7C2CF))
            case .full where isCat:
                StrokePath(d: "M48 68 Q 44 74 48 80 M42 65 Q 36 74 42 83 M122 68 Q 126 74 122 80 M128 65 Q 134 74 128 83", style: Color(hex: 0xE7A98F), width: 2)
                Oval(cx: 140, cy: 44, rx: 8, ry: 4.6, style: Color(hex: 0x8FCBF2))
                FillPath(d: "M147 44 L153 39.5 L153 48.5 Z", style: Color(hex: 0x8FCBF2))
                Oval(cx: 136, cy: 43, rx: 1, ry: 1, style: Color(hex: 0x3B2A2A))
                Deco(shape: HeartShape(), x: 30, y: 48, size: 12, color: Color(hex: 0xF4A7B0))
                Deco(shape: HeartShape(), x: 138, y: 104, size: 9, color: Color(hex: 0xF7C2CF))
            case .full:
                Deco(shape: Sparkle(), x: 136, y: 46, size: 14, color: Color(hex: 0xFFC861))
                Deco(shape: Sparkle(), x: 34, y: 62, size: 9, color: Color(hex: 0x8FCBF2))
                Deco(shape: Sparkle(), x: 134, y: 98, size: 7, color: Color(hex: 0xF7A9BC))
                Oval(cx: 30, cy: 100, rx: 2.5, ry: 1.2, style: Color(hex: 0xFFC861), rotation: 30)
                Oval(cx: 146, cy: 76, rx: 2.5, ry: 1.2, style: Color(hex: 0x8FCBF2), rotation: -25)
            default:
                EmptyView()
            }
        }
        .frame(width: 170, height: 170, alignment: .topLeading)
    }
}
