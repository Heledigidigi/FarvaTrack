import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Zaman çizelgesi

struct StepsEntry: TimelineEntry {
    let date: Date
    let snapshot: StepsSnapshot
    let metric: Int
    let theme: StepsThemeOption
}

struct StepsProvider: AppIntentTimelineProvider {
    private static let sample = StepsSnapshot(steps: 6_842, goal: 10_000, distanceKm: 4.9, updatedAt: .now)

    func placeholder(in context: Context) -> StepsEntry {
        StepsEntry(date: .now, snapshot: Self.sample, metric: 0, theme: .gece)
    }

    func snapshot(for configuration: StepsWidgetConfig, in context: Context) async -> StepsEntry {
        context.isPreview
            ? StepsEntry(date: .now, snapshot: Self.sample, metric: 0, theme: configuration.theme)
            : currentEntry(configuration)
    }

    func timeline(for configuration: StepsWidgetConfig, in context: Context) async -> Timeline<StepsEntry> {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        return Timeline(entries: [currentEntry(configuration)], policy: .after(next))
    }

    private func currentEntry(_ configuration: StepsWidgetConfig) -> StepsEntry {
        var snapshot = SharedStore.loadSteps() ?? .empty
        // Dünden kalan veriyi bugünmüş gibi göstermeyelim.
        if !Calendar.current.isDateInToday(snapshot.updatedAt) {
            snapshot.steps = 0
            snapshot.distanceKm = 0
        }
        return StepsEntry(date: .now, snapshot: snapshot, metric: SharedStore.stepsMetric, theme: configuration.theme)
    }
}

// MARK: - Tema

struct RingTheme {
    var fill: WidgetFill
    var track: Color = Color(hex: 0x2A2C32)
    var g1: Color = Color(hex: 0xFF8FA3)
    var g2: Color = Color(hex: 0xC2185B)
    var text: Color = .white
    var sub: Color = Color(hex: 0xA9A7AE)
    var lineWidth: CGFloat = 11
    var roundCap = true
    var capFill: Color = .white
    var isVintage = false
    var isCat = false

    static func make(_ option: StepsThemeOption) -> RingTheme {
        switch option {
        case .gece:
            return RingTheme(fill: .solid(Color(hex: 0x16171B)))
        case .beyaz:
            return RingTheme(fill: .solid(.white), track: Color(hex: 0xF1E8EA), g1: Color(hex: 0xD1435E), g2: Color(hex: 0x800020), text: Color(hex: 0x1C1B1D), sub: Color(hex: 0x8A8387))
        case .bordo:
            return RingTheme(fill: .solid(Color(hex: 0x800020)), track: .white.opacity(0.22), g1: .white, g2: Color(hex: 0xFFD6DE), text: .white, sub: .white.opacity(0.75), capFill: Color(hex: 0x800020))
        case .krem:
            return RingTheme(fill: .solid(Color(hex: 0xFFF7F2)), track: Color(hex: 0xF3E3DA), g1: Color(hex: 0xF2A38A), g2: Color(hex: 0xC9604E), text: Color(hex: 0x5A2E24), sub: Color(hex: 0x9A6F62))
        case .lavanta:
            return RingTheme(fill: .solid(Color(hex: 0xEEE9FB)), track: Color(hex: 0xDDD5F3), g1: Color(hex: 0xA994F0), g2: Color(hex: 0x5B45B8), text: Color(hex: 0x2F2566), sub: Color(hex: 0x6E64A0))
        case .grafit:
            return RingTheme(fill: .solid(Color(hex: 0x2B2D31)), track: Color(hex: 0x3A3D43), g1: Color(hex: 0x9BEAC9), g2: Color(hex: 0x2FAE84), text: .white, sub: Color(hex: 0xA9ADB4))
        case .safak:
            return RingTheme(fill: .gradient(Color(hex: 0xFFE9D9), Color(hex: 0xFBD3DF)), track: .white.opacity(0.7), g1: Color(hex: 0xF59A7A), g2: Color(hex: 0xD1435E), text: Color(hex: 0x6B2436), sub: Color(hex: 0x9A5868))
        case .okyanus:
            return RingTheme(fill: .gradient(Color(hex: 0xE6F6FB), Color(hex: 0xC8DCF7)), track: .white.opacity(0.75), g1: Color(hex: 0x5CC6E0), g2: Color(hex: 0x2F6FC4), text: Color(hex: 0x173E66), sub: Color(hex: 0x4E6E8E))
        case .gunBatimi:
            return RingTheme(fill: .gradient(Color(hex: 0x2A2142), Color(hex: 0x6E3653)), track: .white.opacity(0.16), g1: Color(hex: 0xFFC27A), g2: Color(hex: 0xFF6F91), text: .white, sub: Color(hex: 0xE9C9D6))
        case .aurora:
            return RingTheme(fill: .gradient(Color(hex: 0x0F2A33), Color(hex: 0x2B1F4D)), track: .white.opacity(0.14), g1: Color(hex: 0x7CF2C9), g2: Color(hex: 0x8E7BFF), text: .white, sub: Color(hex: 0xB9C4D6))
        case .nostalji:
            return RingTheme(fill: .gradient(Color(hex: 0xF8EEDA), Color(hex: 0xE6D1A9)), track: Color(hex: 0x5A3E28, opacity: 0.22), g1: Color(hex: 0xD49C98), g2: Color(hex: 0xA8605E),
                             text: Color(hex: 0x4A3020), sub: Color(hex: 0x7A5A40), lineWidth: 8, capFill: Color(hex: 0x5A3E28), isVintage: true)
        case .kedi:
            return RingTheme(fill: .gradient(Color(hex: 0xFFF2E4), Color(hex: 0xF9D8CF)), track: Color(hex: 0xF1C9B5), g1: Color(hex: 0xF7A97E), g2: Color(hex: 0xE06A5E),
                             text: Color(hex: 0x7A4536), sub: Color(hex: 0xA06A5A), lineWidth: 12, isCat: true)
        }
    }

    /// Şeffaf / renk tonlu ana ekran için tek renkli sürüm.
    func glassVersion() -> RingTheme {
        var t = self
        t.fill = .solid(.clear)
        t.track = .white.opacity(0.2)
        t.g1 = .white
        t.g2 = .white
        t.text = .white
        t.sub = .white.opacity(0.75)
        t.capFill = .white
        return t
    }
}

// MARK: - Halka çizimi

private func ringPoint(radius: CGFloat, degrees: Double) -> CGPoint {
    let a = degrees * .pi / 180
    return CGPoint(x: 85 + radius * CGFloat(cos(a)), y: 85 + radius * CGFloat(sin(a)))
}

struct RingArt: View {
    let progress: CGFloat
    let theme: RingTheme

    private var capAngle: Double { -90 + 360 * Double(progress) }

    var body: some View {
        ArtCanvas {
            if theme.isVintage { VintagePageBackground() }
            if theme.isCat { CatRingEars(track: theme.track, whisker: theme.sub) }

            Circle()
                .stroke(theme.track, lineWidth: theme.lineWidth)
                .frame(width: 120, height: 120)
                .position(x: 85, y: 85)

            if theme.isVintage {
                // Suluboya taşması
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color(hex: 0xD9A5A0, opacity: 0.35), style: StrokeStyle(lineWidth: 15, lineCap: .round))
                    .rotationEffect(.degrees(-91.5))
                    .frame(width: 121, height: 121)
                    .position(x: 85, y: 85)
            }

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [theme.g1, theme.g2], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: theme.lineWidth, lineCap: theme.roundCap ? .round : .butt)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 120, height: 120)
                .position(x: 85, y: 85)

            if progress > 0.001 {
                let cap = ringPoint(radius: 60, degrees: capAngle)
                if theme.isCat {
                    PawPrint(color: .white)
                        .rotationEffect(.degrees(360 * Double(progress)))
                        .position(cap)
                } else if theme.isVintage {
                    Blossom(scale: 1.15, color: Color(hex: 0xB9716E))
                        .position(cap)
                } else {
                    Circle().fill(theme.capFill).frame(width: 6, height: 6).position(cap)
                }
            }

            if theme.isVintage { VintagePageForeground() }
        }
        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: progress)
    }
}

/// Kedi teması: halkanın tepesinde kulaklar, iki yanda bıyıklar.
struct CatRingEars: View {
    let track: Color
    let whisker: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach([-128.0, -52.0], id: \.self) { center in
                earPath(center: center, outer: true)
                    .fill(track)
                    .overlay(earPath(center: center, outer: true).stroke(track, style: StrokeStyle(lineWidth: 5, lineJoin: .round)))
                earPath(center: center, outer: false)
                    .fill(Color(hex: 0xF7B6C0))
            }
            StrokePath(d: "M24 80 L8 76 M24 86 L7 87 M24 92 L9 98 M146 80 L162 76 M146 86 L163 87 M146 92 L161 98", style: whisker.opacity(0.7), width: 1.4)
        }
        .frame(width: 170, height: 170, alignment: .topLeading)
    }

    private func earPath(center: Double, outer: Bool) -> Path {
        let spread: Double = outer ? 16 : 9
        let base: CGFloat = outer ? 64 : 67
        let tipR: CGFloat = outer ? 86 : 80
        var p = Path()
        p.move(to: ringPoint(radius: base, degrees: center - spread))
        p.addLine(to: ringPoint(radius: tipR, degrees: center))
        p.addLine(to: ringPoint(radius: base, degrees: center + spread))
        p.closeSubpath()
        return p
    }
}

/// Beş yapraklı küçük kurutulmuş çiçek.
struct Blossom: View {
    var scale: CGFloat = 1
    var color: Color

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { k in
                let a = Double(k) * 72 - 90
                Circle()
                    .fill(color.opacity(0.85))
                    .frame(width: 4.8 * scale, height: 4.8 * scale)
                    .offset(x: 3.2 * scale * CGFloat(cos(a * .pi / 180)), y: 3.2 * scale * CGFloat(sin(a * .pi / 180)))
            }
            Circle().fill(Color(hex: 0xC9A15A)).frame(width: 2.8 * scale, height: 2.8 * scale)
        }
        .frame(width: 14 * scale, height: 14 * scale)
    }
}

/// Nostalji: hurda defter sayfası (defter çizgileri, çay lekesi, pul, posta damgası).
struct VintagePageBackground: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            StrokePath(d: stride(from: 22, to: 162, by: 11).map { "M14 \($0) L160 \($0)" }.joined(separator: " "),
                       style: Color(hex: 0xB8A07A, opacity: 0.35), width: 0.6)
            StrokePath(d: "M24 0 L24 170", style: Color(hex: 0xC98B8B, opacity: 0.4), width: 0.7)
            Oval(cx: 132, cy: 138, rx: 30, ry: 22, style: Color(hex: 0xA6784A, opacity: 0.14)).blur(radius: 6)
            Oval(cx: 36, cy: 40, rx: 18, ry: 12, style: Color(hex: 0xA6784A, opacity: 0.10)).blur(radius: 6)

            // Pul: içinde soluk tonlarda şişe vazo ve gözlü gül
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(hex: 0xFBF4E6)).frame(width: 30, height: 37).position(x: 140, y: 32.5)
                Rectangle().strokeBorder(Color(hex: 0xE2D2B4), style: StrokeStyle(lineWidth: 3.2, dash: [2.2, 1.6]))
                    .frame(width: 33, height: 40).position(x: 140, y: 32.5)
                Rectangle().fill(Color(hex: 0xDCC6C2)).frame(width: 23, height: 30).position(x: 140, y: 32.5)
                StampVaseRose().opacity(0.78)
            }
            .frame(width: 170, height: 170, alignment: .topLeading)
            .rotationEffect(.degrees(8), anchor: UnitPoint(x: 140.0 / 170, y: 33.0 / 170))

            // Posta damgası
            ZStack(alignment: .topLeading) {
                Circle().stroke(Color(hex: 0x5A3E28), lineWidth: 0.8).frame(width: 22, height: 22).position(x: 124, y: 48)
                Circle().stroke(Color(hex: 0x5A3E28), style: StrokeStyle(lineWidth: 0.8, dash: [1, 1.4])).frame(width: 16.8, height: 16.8).position(x: 124, y: 48)
                StrokePath(d: "M96 43 Q 100 41 104 43 Q 108 45 112 43 M94 48 Q 98 46 102 48 Q 106 50 110 48 M96 53 Q 100 51 104 53 Q 108 55 112 53",
                           style: Color(hex: 0x5A3E28), width: 0.8)
            }
            .opacity(0.45)
        }
        .frame(width: 170, height: 170, alignment: .topLeading)
    }
}

/// Puldaki soluk şişe vazo ve gözlü gül.
struct StampVaseRose: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            StrokePath(d: "M140 26 C 139.6 29 140.4 32 140 36", style: Color(hex: 0x6F7A55), width: 0.8)
            Oval(cx: 137, cy: 29.5, rx: 2.6, ry: 1.1, style: Color(hex: 0x8A9A6A), rotation: 25)
            Oval(cx: 143, cy: 28.5, rx: 2.6, ry: 1.1, style: Color(hex: 0x95A472), rotation: -25)
            FillPath(d: "M138.3 31.5 L141.7 31.5 L141.7 33.6 C 144.6 35 145 37 145 39.5 L145 44.6 Q 145 45.6 144 45.6 L136 45.6 Q 135 45.6 135 44.6 L135 39.5 C 135 37 135.4 35 138.3 33.6 Z",
                     style: Color(hex: 0xEFE7DD, opacity: 0.7))
            StrokePath(d: "M138.3 31.5 L141.7 31.5 L141.7 33.6 C 144.6 35 145 37 145 39.5 L145 44.6 Q 145 45.6 144 45.6 L136 45.6 Q 135 45.6 135 44.6 L135 39.5 C 135 37 135.4 35 138.3 33.6 Z",
                       style: Color(hex: 0x8A7568), width: 0.6)
            FillPath(d: "M135.2 42.4 L144.8 42.4 L144.8 44.6 Q 144.8 45.4 144 45.4 L136 45.4 Q 135.2 45.4 135.2 44.6 Z", style: Color(hex: 0xAE9BB6, opacity: 0.8))
            Rectangle().fill(Color(hex: 0xF3EADB)).frame(width: 6.8, height: 5.2).position(x: 140, y: 39.8)
            Oval(cx: 140, cy: 39.2, rx: 1.05, ry: 1.05, style: Color(hex: 0x7A6A60))
            StrokePath(d: "M138.6 41.4 L141.4 40.4 M138.6 40.4 L141.4 41.4", style: Color(hex: 0x7A6A60), width: 0.4)
            // Gözlü gül
            ForEach(0..<5, id: \.self) { k in
                let a = Double(k) * 72 - 90
                Oval(cx: 140 + 3 * CGFloat(cos(a * .pi / 180)), cy: 22.5 + 3 * CGFloat(sin(a * .pi / 180)), rx: 3.3, ry: 2.7,
                     style: Color(hex: 0x8C5357), rotation: Double(k) * 72)
            }
            Oval(cx: 140, cy: 22.5, rx: 3.7, ry: 3.7, style: Color(hex: 0x9E6266))
            Oval(cx: 140, cy: 22.5, rx: 2.5, ry: 2.5, style: Color(hex: 0xAE7476))
            FillPath(d: "M137.9 22.5 Q 140 20.8 142.1 22.5 Q 140 24.1 137.9 22.5 Z", style: Color(hex: 0xEDE3D6))
            Oval(cx: 140, cy: 22.5, rx: 0.95, ry: 0.95, style: Color(hex: 0x8AA3B8))
            Oval(cx: 140, cy: 22.5, rx: 0.45, ry: 0.45, style: Color(hex: 0x3E3434))
        }
        .frame(width: 170, height: 170, alignment: .topLeading)
    }
}

/// Nostalji: washi bant ve kurutulmuş çiçek demeti (halkanın üstünde).
struct VintagePageForeground: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(hex: 0xE3B7B1, opacity: 0.78)).frame(width: 62, height: 14).position(x: 23, y: 21)
                ForEach([4.0, 16.0, 28.0, 40.0], id: \.self) { x in
                    Oval(cx: x, cy: 21, rx: 1, ry: 1, style: Color.white.opacity(0.7))
                }
            }
            .frame(width: 170, height: 170, alignment: .topLeading)
            .rotationEffect(.degrees(-36), anchor: UnitPoint(x: 22.0 / 170, y: 22.0 / 170))

            StrokePath(d: "M160 168 C 150 150 142 136 128 122 M146 146 C 152 140 158 140 162 136 M138 134 C 132 130 130 124 132 118",
                       style: Color(hex: 0x7A5A40), width: 0.9)
            Oval(cx: 152, cy: 150, rx: 5, ry: 2.2, style: Color(hex: 0x9DAF8E), rotation: -40)
            Oval(cx: 140, cy: 142, rx: 5, ry: 2.2, style: Color(hex: 0xA9BB98), rotation: 30)
            Oval(cx: 146, cy: 134, rx: 4.4, ry: 2, style: Color(hex: 0x9DAF8E), rotation: -55)
            Oval(cx: 156, cy: 160, rx: 4.4, ry: 2, style: Color(hex: 0xA9BB98), rotation: 25)
            Blossom(scale: 1, color: Color(hex: 0xD49C98)).position(x: 128, y: 121)
            Blossom(scale: 0.8, color: Color(hex: 0xE2B4A8)).position(x: 162, y: 135)
            Blossom(scale: 0.6, color: Color(hex: 0xC98B8B)).position(x: 131, y: 117)
        }
        .frame(width: 170, height: 170, alignment: .topLeading)
    }
}

// MARK: - Widget görünümü

struct StepsWidgetView: View {
    let entry: StepsEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var snapshot: StepsSnapshot { entry.snapshot }
    private var theme: RingTheme {
        let base = RingTheme.make(entry.theme)
        return renderingMode == .fullColor ? base : base.glassVersion()
    }
    private var progress: CGFloat {
        snapshot.goal > 0 ? min(CGFloat(snapshot.steps) / CGFloat(snapshot.goal), 1) : 0
    }
    /// Tahmini kalori (adım başına ~0,04 kcal); yalnızca bilgi amaçlı.
    private var kcal: Int { Int((Double(snapshot.steps) * 0.04).rounded()) }

    private var value: (number: Double, text: String, unit: String) {
        switch entry.metric {
        case 1:
            return (snapshot.distanceKm, snapshot.distanceKm.formatted(.number.precision(.fractionLength(1))), "kilometre")
        case 2:
            return (Double(kcal), kcal.formatted(), "kcal (tahmini)")
        default:
            return (Double(snapshot.steps), snapshot.steps.formatted(), "/ \(snapshot.goal.formatted()) adım")
        }
    }

    private var numberFont: Font {
        theme.isVintage ? .system(size: 30, weight: .regular, design: .serif) : .system(size: 28, weight: .bold, design: .rounded)
    }
    private var unitFont: Font {
        theme.isVintage ? .custom("Noteworthy-Bold", size: 14) : .system(size: 11, weight: .medium)
    }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 14) {
                ringButton.frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 6) {
                    row("Adım", snapshot.steps.formatted())
                    row("Mesafe", snapshot.distanceKm.formatted(.number.precision(.fractionLength(1))) + " km")
                    row("Kalori", "~\(kcal.formatted()) kcal")
                    row("Hedef", snapshot.goal.formatted())
                }
                Spacer(minLength: 0)
            }
        default:
            ringButton
        }
    }

    private func row(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(theme.sub)
            Text(text).font(.subheadline.weight(.bold)).foregroundStyle(theme.text)
        }
    }

    /// Sadece halkanın içi dokunulabilir; köşelerden uzun basmak gösterimi değiştirmez.
    private var ringButton: some View {
        ZStack {
            ringFace
            ArtHotspot(rect: CGRect(x: 30, y: 30, width: 110, height: 110)) {
                Button(intent: CycleStepsMetricIntent()) {
                    Color.clear.contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bugünkü adım: \(snapshot.steps), hedef \(snapshot.goal), \(snapshot.distanceKm.formatted(.number.precision(.fractionLength(1)))) kilometre")
                .accessibilityHint("Adım, kilometre ve kalori arasında geçiş yapar")
            }
        }
    }

    private var ringFace: some View {
            ZStack {
                RingArt(progress: progress, theme: theme)
                VStack(spacing: 1) {
                    Text(value.text)
                        .font(numberFont)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(theme.text)
                        .contentTransition(.numericText(value: value.number))
                    Text(value.unit)
                        .font(unitFont)
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                }
                .padding(.horizontal, 28)
            }
            .accessibilityHidden(true)
    }
}

struct StepsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SharedStore.stepsWidgetKind, intent: StepsWidgetConfig.self, provider: StepsProvider()) { entry in
            StepsWidgetView(entry: entry)
                .containerBackground(for: .widget) { RingTheme.make(entry.theme).fill.view }
                .widgetURL(URL(string: "farvatrack://steps"))
        }
        .configurationDisplayName("Adım Halkası")
        .description("Bugünkü adımların. Halkaya dokununca km ve kaloriye geçer.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
