import WidgetKit
import SwiftUI

/// Widget renkleri (uygulamanın paletiyle uyumlu; widget hedefi uygulama dosyalarını derlemez).
enum Palette {
    static let accent = Color(red: 0.50, green: 0.0, blue: 0.125)        // #800020
    static let accentLight = Color(red: 0.88, green: 0.38, blue: 0.50)   // #E0607F
    static let background = Color(red: 0.055, green: 0.055, blue: 0.07)  // #0E0E12
    static let track = Color.white.opacity(0.1)
    static let secondary = Color.white.opacity(0.65)
    static let water = Color(red: 0.30, green: 0.64, blue: 1.0)          // #4DA3FF
}

// MARK: - Adım widget'ı
struct StepsEntry: TimelineEntry {
    let date: Date
    let snapshot: StepsSnapshot
}

struct StepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepsEntry {
        StepsEntry(date: .now, snapshot: StepsSnapshot(steps: 6_240, goal: 8_000, distanceKm: 4.6, updatedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (StepsEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }

    private func currentEntry() -> StepsEntry {
        var snapshot = SharedStore.loadSteps() ?? .empty
        // Dünden kalan veriyi bugünmüş gibi göstermeyelim.
        if !Calendar.current.isDateInToday(snapshot.updatedAt) {
            snapshot.steps = 0
            snapshot.distanceKm = 0
        }
        return StepsEntry(date: .now, snapshot: snapshot)
    }
}

struct StepsWidgetView: View {
    let entry: StepsEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: StepsSnapshot { entry.snapshot }
    private var progress: Double {
        snapshot.goal > 0 ? min(Double(snapshot.steps) / Double(snapshot.goal), 1) : 0
    }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 20) {
                ring.frame(width: 100, height: 100)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bugün")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.secondary)
                    Text(snapshot.steps.formatted())
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("/ \(snapshot.goal.formatted()) adım • \(snapshot.distanceKm.formatted(.number.precision(.fractionLength(1)))) km")
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            ring
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [Palette.accent, Palette.accentLight], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Image(systemName: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(Palette.accentLight)
                Text(snapshot.steps.formatted())
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
        }
        .padding(4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bugünkü adım: \(snapshot.steps), hedef \(snapshot.goal)")
    }
}

struct StepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.stepsWidgetKind, provider: StepsProvider()) { entry in
            StepsWidgetView(entry: entry)
                .containerBackground(Palette.background, for: .widget)
                .widgetURL(URL(string: "farvatrack://steps"))
        }
        .configurationDisplayName("Adım Sayacı")
        .description("Bugünkü adımların ve hedefine ilerlemen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct FarvaTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        StepsWidget()
        WaterWidget()
    }
}
