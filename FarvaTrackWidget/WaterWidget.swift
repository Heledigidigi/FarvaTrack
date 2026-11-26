import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Zaman çizelgesi

struct WaterEntryModel: TimelineEntry {
    let date: Date
    let snapshot: WaterSnapshot
    let amount: Int
    let theme: WaterThemeOption
    var showUndo = false
}

struct WaterProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WaterEntryModel {
        WaterEntryModel(date: .now, snapshot: WaterSnapshot(totalMl: 1_400, goalMl: 2_500, updatedAt: .now), amount: 250, theme: .krem)
    }

    func snapshot(for configuration: WaterWidgetConfig, in context: Context) async -> WaterEntryModel {
        context.isPreview
            ? WaterEntryModel(date: .now, snapshot: WaterSnapshot(totalMl: 1_400, goalMl: 2_500, updatedAt: .now), amount: configuration.amount.rawValue, theme: configuration.theme)
            : currentEntry(configuration)
    }

    func timeline(for configuration: WaterWidgetConfig, in context: Context) async -> Timeline<WaterEntryModel> {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        var entry = currentEntry(configuration)
        // Widget'tan son ekleme yeniyse "Geri al" görünür; süresi bitince ikinci kayıtla gizlenir.
        if entry.snapshot.lastWidgetAddID != nil, let at = entry.snapshot.lastWidgetAddAt {
            let ends = at.addingTimeInterval(SharedStore.wasteUndoWindow)
            if ends > .now {
                entry.showUndo = true
                var later = currentEntry(configuration)
                later = WaterEntryModel(date: ends, snapshot: later.snapshot, amount: later.amount, theme: later.theme, showUndo: false)
                return Timeline(entries: [entry, later], policy: .after(max(next, ends)))
            }
        }
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func currentEntry(_ configuration: WaterWidgetConfig) -> WaterEntryModel {
        var snapshot = SharedStore.loadWater() ?? .empty
        // Dünden kalan toplamı bugünmüş gibi göstermeyelim.
        if !Calendar.current.isDateInToday(snapshot.updatedAt) { snapshot.totalMl = 0 }
        return WaterEntryModel(date: .now, snapshot: snapshot, amount: configuration.amount.rawValue, theme: configuration.theme)
    }
}

// MARK: - Widget görünümü

struct WaterWidgetView: View {
    let entry: WaterEntryModel
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var snapshot: WaterSnapshot { entry.snapshot }
    private var theme: DropTheme {
        let base = DropTheme.make(entry.theme)
        return renderingMode == .fullColor ? base : base.glassVersion()
    }
    private var litersText: String {
        (Double(snapshot.totalMl) / 1000).formatted(.number.precision(.fractionLength(1))) + " L"
    }
    private var percent: Int {
        snapshot.goalMl > 0 ? min(100, Int((Double(snapshot.totalMl) / Double(snapshot.goalMl) * 100).rounded())) : 0
    }
    private var numberFont: Font {
        theme.serif ? .system(size: 18, weight: .bold, design: .serif) : .system(size: 18, weight: .heavy, design: .rounded)
    }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 12) {
                dropButton
                    .frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bugün")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.text.opacity(0.75))
                    Text(litersText)
                        .font(theme.serif ? .system(size: 30, weight: .bold, design: .serif) : .system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.text)
                        .contentTransition(.numericText(value: Double(snapshot.totalMl)))
                    Text("/ \((Double(snapshot.goalMl) / 1000).formatted(.number.precision(.fractionLength(1)))) L hedef · %\(percent)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.text.opacity(0.75))
                    Text("Damlaya dokun: +\(entry.amount) ml")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.pill, in: Capsule())
                        .padding(.top, 4)
                    if entry.showUndo {
                        Button(intent: UndoWaterIntent()) { UndoCapsule(dark: Color(hex: 0x1E4E73, opacity: 0.85)) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Son eklenen suyu geri al")
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            ZStack(alignment: .topLeading) {
                dropButton
                if entry.showUndo {
                    VStack {
                        Spacer(minLength: 0)
                        Button(intent: UndoWaterIntent()) { UndoCapsule(dark: Color(hex: 0x1E4E73, opacity: 0.85)) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Son eklenen suyu geri al")
                    }
                    .transition(.opacity)
                }
                HStack(alignment: .top) {
                    Text(litersText)
                        .font(numberFont)
                        .foregroundStyle(theme.text)
                        .contentTransition(.numericText(value: Double(snapshot.totalMl)))
                    Spacer(minLength: 0)
                    Text("%\(percent)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(theme.pill, in: Capsule())
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// Sadece damlanın (ya da kedi silüetinin) kendisi dokunulabilir; köşelerden uzun basmak kayıt eklemez.
    private var dropButton: some View {
        ZStack {
            DropArt(total: snapshot.totalMl, goal: snapshot.goalMl, theme: theme)
            ArtHotspot(rect: theme.isCat ? CGRect(x: 44, y: 32, width: 82, height: 118) : CGRect(x: 48, y: 36, width: 74, height: 107)) {
                Button(intent: AddWaterIntent(amountMl: entry.amount)) {
                    Color.clear.contentShape(Ellipse())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Damla, \(DropMood(total: snapshot.totalMl, goal: snapshot.goalMl).label). Bugün \(snapshot.totalMl) mililitre, hedef \(snapshot.goalMl).")
                .accessibilityHint("\(entry.amount) mililitre ekler")
            }
        }
    }
}

/// Tema arka planı (Nostalji'de eski etiket gibi ince çerçeve).
struct WaterBackground: View {
    let option: WaterThemeOption

    var body: some View {
        let theme = DropTheme.make(option)
        ZStack {
            theme.fill.view
            if theme.vintageFrame {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color(hex: 0x8C6C42, opacity: 0.55), lineWidth: 1)
                    .padding(5)
            }
        }
    }
}

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SharedStore.waterWidgetKind, intent: WaterWidgetConfig.self, provider: WaterProvider()) { entry in
            WaterWidgetView(entry: entry)
                .containerBackground(for: .widget) { WaterBackground(option: entry.theme) }
                .widgetURL(URL(string: "farvatrack://water"))
        }
        .configurationDisplayName("Damla")
        .description("Damlaya dokun, su eklensin. Miktarı ve temayı widget ayarlarından seç.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
