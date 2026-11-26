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
        let secret = configuration.secretMode || SharedStore.wasteSecret

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
