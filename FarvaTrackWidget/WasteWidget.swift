import WidgetKit
import SwiftUI
import AppIntents

struct WasteEntryModel: TimelineEntry {
    let date: Date
    let count: Int
}

struct WasteProvider: TimelineProvider {
    func placeholder(in context: Context) -> WasteEntryModel {
        WasteEntryModel(date: .now, count: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (WasteEntryModel) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WasteEntryModel>) -> Void) {
        // Gece yarısı sayaç sıfırlansın diye ertesi günün başında yenile.
        let tomorrow = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        completion(Timeline(entries: [currentEntry()], policy: .after(tomorrow)))
    }

    private func currentEntry() -> WasteEntryModel {
        let snapshot = SharedStore.loadWaste() ?? .empty
        let count = Calendar.current.isDateInToday(snapshot.updatedAt) ? snapshot.count : 0
        return WasteEntryModel(date: .now, count: count)
    }
}

struct WasteWidgetView: View {
    let entry: WasteEntryModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.clipboard.fill")
                    .foregroundStyle(Palette.waste)
                Text("Bugün")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
            }
            Text("\(entry.count)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Bugün \(entry.count) kayıt")

            Button(intent: AddWasteIntent()) {
                Label("Ekle", systemImage: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Palette.waste, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bir kayıt ekle")
        }
    }
}

struct WasteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.wasteWidgetKind, provider: WasteProvider()) { entry in
            WasteWidgetView(entry: entry)
                .containerBackground(Palette.background, for: .widget)
                .widgetURL(URL(string: "farvatrack://waste"))
        }
        .configurationDisplayName("Biyolojik Atık")
        .description("Tek dokunuşla günlük sayaca ekle.")
        .supportedFamilies([.systemSmall])
    }
}
