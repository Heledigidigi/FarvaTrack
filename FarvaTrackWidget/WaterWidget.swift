import WidgetKit
import SwiftUI
import AppIntents

struct WaterEntryModel: TimelineEntry {
    let date: Date
    let snapshot: WaterSnapshot
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntryModel {
        WaterEntryModel(date: .now, snapshot: WaterSnapshot(totalMl: 1_500, goalMl: 2_600, updatedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (WaterEntryModel) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterEntryModel>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }

    private func currentEntry() -> WaterEntryModel {
        var snapshot = SharedStore.loadWater() ?? .empty
        // Dünden kalan toplamı bugünmüş gibi göstermeyelim.
        if !Calendar.current.isDateInToday(snapshot.updatedAt) { snapshot.totalMl = 0 }
        return WaterEntryModel(date: .now, snapshot: snapshot)
    }
}

struct WaterWidgetView: View {
    let entry: WaterEntryModel
    @Environment(\.widgetFamily) private var family

    private var snapshot: WaterSnapshot { entry.snapshot }
    private var progress: Double {
        snapshot.goalMl > 0 ? min(Double(snapshot.totalMl) / Double(snapshot.goalMl), 1) : 0
    }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 16) {
                gauge.frame(width: 100, height: 100)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bugün")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.secondary)
                    Text("/ \(snapshot.goalMl.formatted()) ml hedef")
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                    HStack(spacing: 8) {
                        addButton(200)
                        addButton(330)
                        addButton(500)
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(spacing: 8) {
                gauge
                addButton(200)
            }
        }
    }

    private var gauge: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: 9)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Palette.water, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Image(systemName: "drop.fill")
                    .font(.caption2)
                    .foregroundStyle(Palette.water)
                Text(snapshot.totalMl.formatted())
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
        }
        .padding(3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bugünkü su: \(snapshot.totalMl) mililitre, hedef \(snapshot.goalMl)")
    }

    private func addButton(_ ml: Int) -> some View {
        Button(intent: AddWaterIntent(amountMl: ml)) {
            Text("+\(ml)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.water.opacity(0.3), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ml) mililitre ekle")
    }
}

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.waterWidgetKind, provider: WaterProvider()) { entry in
            WaterWidgetView(entry: entry)
                .containerBackground(Palette.background, for: .widget)
                .widgetURL(URL(string: "farvatrack://water"))
        }
        .configurationDisplayName("Su Takibi")
        .description("Widget'tan tek dokunuşla su ekle.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
