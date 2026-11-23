import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Zaman çizelgesi

struct WasteEntryModel: TimelineEntry {
    let date: Date
    let count: Int
    let lastAt: Date?
    let showUndo: Bool
    let secret: Bool
}

struct WasteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WasteEntryModel {
        WasteEntryModel(date: .now, count: 1, lastAt: .now, showUndo: false, secret: false)
    }

    func snapshot(for configuration: WasteWidgetConfig, in context: Context) async -> WasteEntryModel {
        context.isPreview
            ? WasteEntryModel(date: .now, count: 1, lastAt: .now, showUndo: false, secret: configuration.secretMode)
            : entries(configuration).first ?? placeholder(in: context)
    }

    func timeline(for configuration: WasteWidgetConfig, in context: Context) async -> Timeline<WasteEntryModel> {
        // Gece yarısı sayaç sıfırlansın diye ertesi günün başında yenile.
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        return Timeline(entries: entries(configuration), policy: .after(tomorrow))
    }

    /// Şimdiki durum; son dokunuştan sonra "Geri al" süresi bitince ikinci bir kayıt.
    private func entries(_ configuration: WasteWidgetConfig) -> [WasteEntryModel] {
        let now = Date.now
        let snapshot = SharedStore.loadWaste() ?? .empty
        let isToday = Calendar.current.isDateInToday(snapshot.updatedAt)
        let count = isToday ? snapshot.count : 0
        let lastAt = isToday ? snapshot.lastAt : nil
        let secret = configuration.secretMode

        guard let lastAt, snapshot.lastWidgetTapID != nil else {
            return [WasteEntryModel(date: now, count: count, lastAt: lastAt, showUndo: false, secret: secret)]
        }
        let undoEnds = lastAt.addingTimeInterval(SharedStore.wasteUndoWindow)
        guard undoEnds > now else {
            return [WasteEntryModel(date: now, count: count, lastAt: lastAt, showUndo: false, secret: secret)]
        }
        return [
            WasteEntryModel(date: now, count: count, lastAt: lastAt, showUndo: true, secret: secret),
            WasteEntryModel(date: undoEnds, count: count, lastAt: lastAt, showUndo: false, secret: secret)
        ]
    }
}

// MARK: - Van kedisi çizimi

enum CatPose: Int {
    case waiting, clean, cheerful, busy

    init(count: Int) {
        switch count {
        case ...0: self = .waiting
        case 1: self = .clean
        case 2: self = .cheerful
        default: self = .busy
        }
    }

    var line: String {
        switch self {
        case .waiting: return "Miyav? Bekliyorum…"
        case .clean: return "Mrr, tertemiz!"
        case .cheerful: return "Pırıl pırıl, miyav!"
        case .busy: return "Bugün çok yoğunuz!"
        }
    }
}

private enum Fur {
    static let white = RadialGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xF7F2EC), Color(hex: 0xDCD2C8)],
                                      center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: 46)
    static let ginger = RadialGradient(colors: [Color(hex: 0xF8C68C), Color(hex: 0xEBA45F), Color(hex: 0xCF8243)],
                                       center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 26)
    static let earInner = LinearGradient(colors: [Color(hex: 0xF2A9B4), Color(hex: 0xFCD3D6)], startPoint: .top, endPoint: .bottom)
    static let ink = Color(hex: 0x3A2C2A)
}

/// Kum kabındaki kedi; tasarım koordinatlarında (kedi 0,8 ölçekte kabın içine oturur).
struct LitterCat: View {
    let pose: CatPose

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Kuyruk (havada)
            StrokePath(d: "M110 132 C 132 124 138 100 128 88", style: Color(hex: 0xEBA45F), width: 12)
            StrokePath(d: "M131 108 Q 126 107 122 110 M133 98 Q 128 97 124 99", style: Color(hex: 0xCF8243, opacity: 0.5), width: 2)
            // Gövde
            Oval(cx: 85, cy: 128, rx: 32, ry: 27, style: Fur.white)
            Oval(cx: 85, cy: 104, rx: 30, ry: 6, style: Color(hex: 0x8A7464, opacity: 0.22)).blur(radius: 3)
            Oval(cx: 72, cy: 150, rx: 9.5, ry: 6.5, style: Fur.white)
            Oval(cx: 98, cy: 150, rx: 9.5, ry: 6.5, style: Fur.white)
            head
        }
        .frame(width: 170, height: 170, alignment: .topLeading)
    }

    private var head: some View {
        ZStack(alignment: .topLeading) {
            FillPath(d: "M50 54 C 46 40 47 28 52 20 C 55 17 58 18 61 21 C 67 28 73 36 76 42 Z", style: Fur.ginger)
            FillPath(d: "M54 48 C 52 39 53 31 56 26 C 61 31 66 37 69 42 Z", style: Fur.earInner)
            FillPath(d: "M120 54 C 124 40 123 28 118 20 C 115 17 112 18 109 21 C 103 28 97 36 94 42 Z", style: Fur.ginger)
            FillPath(d: "M116 48 C 118 39 117 31 114 26 C 109 31 104 37 101 42 Z", style: Fur.earInner)

            Oval(cx: 85, cy: 70, rx: 40, ry: 35, style: Fur.white)
            // Van kedisinin başındaki turuncu lekeler (kafanın içine kırpılır)
            ZStack(alignment: .topLeading) {
                Oval(cx: 61, cy: 44, rx: 23, ry: 19, style: Fur.ginger, rotation: -18)
                Oval(cx: 109, cy: 44, rx: 23, ry: 19, style: Fur.ginger, rotation: 18)
            }
            .frame(width: 170, height: 170, alignment: .topLeading)
            .mask(Ellipse().frame(width: 80, height: 70).position(x: 85, y: 70))

            Oval(cx: 66, cy: 47, rx: 9, ry: 5, style: Color.white.opacity(0.45)).blur(radius: 2)
            Ellipse().stroke(Color.white.opacity(0.6), lineWidth: 1.4).frame(width: 80, height: 70).position(x: 85, y: 70)

            Oval(cx: 56, cy: 91, rx: 7.5, ry: 4.4, style: Color(hex: 0xF7A9B6, opacity: blush)).blur(radius: 2)
            Oval(cx: 114, cy: 91, rx: 7.5, ry: 4.4, style: Color(hex: 0xF7A9B6, opacity: blush)).blur(radius: 2)

            eye(cx: 68, cy: 78, iris: [Color(hex: 0xD8F2FF), Color(hex: 0x82C3E8), Color(hex: 0x3F86B8)])
            eye(cx: 102, cy: 78, iris: [Color(hex: 0xFFEDB5), Color(hex: 0xF0BD5A), Color(hex: 0xC88A2E)])

            mouth
            FillPath(d: "M82.4 84.4 L87.6 84.4 C 87.6 86.2 85.9 87.4 85 87.6 C 84.1 87.4 82.4 86.2 82.4 84.4 Z", style: Color(hex: 0xF2A0AE))
            StrokePath(d: "M60 88 L46 86 M60 91 L47 93 M110 88 L124 86 M110 91 L123 93", style: Color(hex: 0xB9ADA4, opacity: 0.7), width: 0.9)

            if pose == .busy {
                FillPath(d: "M128 46 C 128 46 124.6 51.6 124.6 53.6 C 124.6 55.5 126.1 57 128 57 C 129.9 57 131.4 55.5 131.4 53.6 C 131.4 51.6 128 46 128 46 Z",
                         style: Color(hex: 0x9FD3F2))
            }
        }
        .frame(width: 170, height: 170, alignment: .topLeading)
    }

    private var blush: Double {
        switch pose {
        case .waiting: return 0.55
        case .clean: return 0.66
        case .cheerful: return 0.77
        case .busy: return 0.5
        }
    }

    @ViewBuilder
    private func eye(cx: CGFloat, cy: CGFloat, iris: [Color]) -> some View {
        if pose == .clean {
            StrokePath(d: "M\(cx - 8) \(cy + 2.5) Q \(cx) \(cy - 6) \(cx + 8) \(cy + 2.5)", style: Fur.ink, width: 2.7)
        } else {
            let pupil: CGFloat = pose == .waiting ? 6 : 6.9
            ZStack(alignment: .topLeading) {
                Oval(cx: cx, cy: cy, rx: 8.6, ry: 9.6,
                     style: RadialGradient(colors: iris, center: UnitPoint(x: 0.5, y: 0.6), startRadius: 0, endRadius: 10))
                Oval(cx: cx, cy: cy + 0.9, rx: pupil, ry: pupil, style: Color(hex: 0x1F1A24))
                Oval(cx: cx + 3, cy: cy - 3.6, rx: 3.3, ry: 2.9, style: Color.white)
                Oval(cx: cx - 3.1, cy: cy + 3.6, rx: 1.5, ry: 1.5, style: Color.white.opacity(0.9))
                Ellipse().stroke(Fur.ink, lineWidth: 1.3).frame(width: 17.2, height: 19.2).position(x: cx, y: cy)
                if pose != .waiting {
                    Deco(shape: Sparkle(), x: cx - 3.6, y: cy - 4.6, size: 4.5, color: .white)
                }
            }
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch pose {
        case .waiting, .clean:
            StrokePath(d: "M80.6 89 Q 82.8 92.2 85 89 Q 87.2 92.2 89.4 89", style: Color(hex: 0x5A3A3A), width: 1.7)
        case .cheerful:
            FillPath(d: "M80 89 Q 85 97.5 90 89 Q 85 90.6 80 89 Z", style: Color(hex: 0x7A3A44))
            FillPath(d: "M82.2 92.6 Q 85 95.6 87.8 92.6 Q 85 93.4 82.2 92.6 Z", style: Color(hex: 0xF4A0AC))
        case .busy:
            Oval(cx: 85, cy: 91.4, rx: 2.8, ry: 3.4, style: Color(hex: 0x7A3A44))
            Oval(cx: 85, cy: 93.2, rx: 1.8, ry: 1.2, style: Color(hex: 0xF4A0AC))
        }
    }
}

/// Kum kabı sahnesi: arka kenar, kum, kedi, ön duvar ve günün pati izleri.
struct LitterBoxArt: View {
    let count: Int

    private var pose: CatPose { CatPose(count: count) }

    var body: some View {
        ArtCanvas {
            FillPath(d: "M20 121 Q 85 108 150 121 L 150 128 Q 85 115 20 128 Z", style: Color(hex: 0x8FCBB5))
            Oval(cx: 85, cy: 124, rx: 62, ry: 8.5, style: Color(hex: 0xEAD7B4))
            StrokePath(d: "M40 122 L41 122 M52 125 L53 125 M66 121 L67 121 M100 124 L101 124 M116 121 L117 121 M128 125 L129 125 M76 126 L77 126",
                       style: Color(hex: 0xC9AE80), width: 1.4)

            LitterCat(pose: pose)
                .scaleEffect(0.8, anchor: UnitPoint(x: 85.0 / 170, y: 152.0 / 170))
                .id(pose)
                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))

            FillPath(d: "M14 122 Q 85 136 156 122 L 149 158 Q 148 163 142 163 L 28 163 Q 22 163 21 158 Z",
                     style: LinearGradient(colors: [Color(hex: 0xBFE8D8), Color(hex: 0x86C6AE)], startPoint: .top, endPoint: .bottom))
            StrokePath(d: "M16 123.6 Q 85 137.4 154 123.6", style: Color.white.opacity(0.8), width: 2.2)
            StrokePath(d: "M30 156 Q 85 160 140 156", style: Color(hex: 0x6FAE98, opacity: 0.5), width: 1)

            // Her kayıt kabın önüne bir pati izi (en fazla 7 gösterilir)
            let shown = min(count, 7)
            ForEach(0..<shown, id: \.self) { i in
                PawPrint(color: .white.opacity(0.9))
                    .rotationEffect(.degrees(i % 2 == 0 ? -12 : 12))
                    .position(x: 85 - CGFloat(shown - 1) * 8 + CGFloat(i) * 16, y: 148)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.55), value: count)
    }
}

// MARK: - Widget görünümü

struct WasteWidgetView: View {
    let entry: WasteEntryModel

    private var subtitle: String {
        guard entry.count > 0, let lastAt = entry.lastAt else { return "bugün henüz yok" }
        return "bugün · son " + lastAt.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        if entry.secret {
            secretView
        } else {
            catView
        }
    }

    private var catView: some View {
        ZStack(alignment: .topLeading) {
            // Sadece kedinin kendisi dokunulabilir; köşelerden uzun basmak kayıt eklemez.
            LitterBoxArt(count: entry.count)
            ArtHotspot(rect: CGRect(x: 48, y: 40, width: 76, height: 104)) {
                Button(intent: AddWasteIntent()) {
                    Color.clear.contentShape(Ellipse())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ritim, bugün \(entry.count) kayıt")
                .accessibilityHint("Bir kayıt ekler")
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("\(entry.count)")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0x3A2418))
                    .contentTransition(.numericText(value: Double(entry.count)))
                    .privacySensitive()
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: 0x8A6A56))
                    .privacySensitive()
            }
            .allowsHitTesting(false)

            if entry.showUndo {
                HStack {
                    Spacer(minLength: 0)
                    Text(CatPose(count: entry.count).line)
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: 0x5A3420))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.white, in: RoundedRectangle(cornerRadius: 9))
                        .shadow(color: Color(hex: 0x5A3214, opacity: 0.18), radius: 3, y: 1)
                }
                .padding(.top, 42)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))

                VStack {
                    Spacer(minLength: 0)
                    Button(intent: UndoWasteIntent()) { UndoCapsule() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Son kaydı geri al")
                }
                .transition(.opacity)
            }
        }
    }

    /// Gizli mod: karakter yok, sade sayaç.
    private var secretView: some View {
        ZStack {
            secretContent
            ArtHotspot(rect: CGRect(x: 40, y: 40, width: 90, height: 90)) {
                Button(intent: AddWasteIntent()) {
                    Color.clear.contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ritim, bugün \(entry.count) kayıt")
                .accessibilityHint("Bir kayıt ekler")
            }
        }
    }

    private var secretContent: some View {
            VStack(spacing: 4) {
                Text("Ritim")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color(hex: 0x8A6A56))
                Text("\(entry.count)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0x3A2418))
                    .contentTransition(.numericText(value: Double(entry.count)))
                    .privacySensitive()
                Text(subtitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(hex: 0x8A6A56))
                    .privacySensitive()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

struct WasteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SharedStore.wasteWidgetKind, intent: WasteWidgetConfig.self, provider: WasteProvider()) { entry in
            WasteWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    entry.secret ? Color(hex: 0xF3EBE2) : Color(hex: 0xFFF6EC)
                }
                .widgetURL(URL(string: "farvatrack://waste"))
        }
        .configurationDisplayName("Ritim")
        .description("Kum kabındaki kediye dokun, kayıt eklensin. Gizli modu ayarlardan aç.")
        .supportedFamilies([.systemSmall])
    }
}
