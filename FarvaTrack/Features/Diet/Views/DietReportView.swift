import SwiftUI
import UIKit

/// Kontrol raporu: takvim, seçilen günün öğün fotoğrafları ve notları, ortalamalar. PDF olarak paylaşılır.
struct DietReportView: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let program: DietProgram

    enum Period: String, CaseIterable, Identifiable {
        case all, twoWeeks, week
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Tüm program"
            case .twoWeeks: return "Son 14 gün"
            case .week: return "Son 7 gün"
            }
        }
    }

    @State private var period: Period = .all
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var inspecting: DietInspectTarget?
    @State private var pdf: DietSharedFile?
    @State private var exporting = false

    private var range: (Date, Date) {
        let today = Calendar.current.startOfDay(for: .now)
        let end = min(today, program.endDate ?? today)
        switch period {
        case .all: return (program.startDate, max(program.startDate, end))
        case .twoWeeks: return (max(program.startDate, Calendar.current.date(byAdding: .day, value: -13, to: end) ?? end), end)
        case .week: return (max(program.startDate, Calendar.current.date(byAdding: .day, value: -6, to: end) ?? end), end)
        }
    }

    private var isOwner: Bool { program.ownerID == store.userID }

    var body: some View {
        let summary = store.summary(for: program, from: range.0, to: range.1)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DietReportHeader(program: program, range: range, summary: summary)
                    Picker("Dönem", selection: $period) {
                        ForEach(Period.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DietReportCalendar(program: program, range: range, summary: summary, selected: selected, interactive: true) { date in
                        Haptics.selection()
                        selected = date
                    }
                    if let day = summary.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }), day.programDay != nil {
                        DietReportDayDetail(program: program, day: day, interactive: true) { snapshot in
                            inspecting = DietInspectTarget(dayKey: day.dayKey, mealID: snapshot.meal.id)
                        }
                    } else {
                        Text("Takvimden bir program günü seç.").font(.subheadline).foregroundStyle(Color.ftTextSecondary)
                    }
                    DietReportAverages(program: program, summary: summary)
                    Text("Değerler kütüphane ortalamalarıyla hesaplanmış tahminlerdir. PDF'te her günün ayrıntısı ek sayfalarda.")
                        .font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
                .padding(16)
            }
            .ftScreenBackground()
            .navigationTitle("Kontrol raporu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        exporting = true
                        Task {
                            do { pdf = DietSharedFile(url: try await DietReportPDF.make(program: program, summary: summary, store: store)) }
                            catch { store.present(error) }
                            exporting = false
                        }
                    } label: {
                        if exporting { ProgressView() } else { Label("PDF", systemImage: "square.and.arrow.up") }
                    }
                    .disabled(exporting)
                }
            }
            .sheet(item: $pdf) { file in DietShareFileSheet(url: file.url) }
            .sheet(item: $inspecting) { target in
                DietMealInspectView(program: program, summary: summary, dayKey: target.dayKey, mealID: target.mealID)
            }
            .onAppear {
                if selected > range.1 || selected < range.0 { selected = range.1 }
            }
            .task { if !isOwner { await store.loadComments(programID: program.id) } }
        }
    }
}

struct DietInspectTarget: Identifiable {
    var dayKey: String
    var mealID: String
    var id: String { "\(dayKey)|\(mealID)" }
}

// MARK: - Başlık ve özet

struct DietReportHeader: View {
    let program: DietProgram
    let range: (Date, Date)
    let summary: DietRangeSummary

    var body: some View {
        let weight = DietAnalysis.weightChange(program.metrics)
        let planned = program.version(on: range.1).plan.averageNutrition
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kontrol Raporu").font(.title2.bold()).foregroundStyle(Color.ftText)
                    Text("\(program.name) · Sürüm \(program.version(on: range.1).number)").font(.subheadline).foregroundStyle(Color.ftText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(DietFormat.shortDate(range.0)) – \(DietFormat.shortDate(range.1))").font(.caption.bold())
                    Text(dayRangeText + (program.ownerName.map { " · \($0)" } ?? "")).font(.caption2).foregroundStyle(Color.ftTextSecondary)
                }
            }
            Rectangle().fill(Color.ftAccent).frame(height: 2)
            HStack(spacing: 8) {
                kpi(summary.adherencePercent.map { "%\($0)" } ?? "—", "öğün uyumu (\(summary.followed)/\(summary.judged))", Color.ftSuccess)
                kpi(DietFormat.kcal(summary.averageEaten.calories), "ort. kcal · plan \(DietFormat.kcal(planned.calories))", Color.ftText)
                kpi(weightValue(weight), weightLabel(weight), Color.ftText)
                kpi("\(summary.skipped) · \(summary.extraCount)", "atlanan · ekstra", Color.ftText)
            }
        }
    }

    private func weightValue(_ weight: (first: Double, last: Double)?) -> String {
        guard let weight else { return "—" }
        let change = weight.last - weight.first
        let sign = change >= 0 ? "+" : "−"
        return sign + DietFormat.number(abs(change)) + " kg"
    }

    private func weightLabel(_ weight: (first: Double, last: Double)?) -> String {
        guard let weight else { return "kilo girilmedi" }
        return "\(DietFormat.number(weight.first)) → \(DietFormat.number(weight.last)) kg"
    }

    private var dayRangeText: String {
        let numbers = summary.days.compactMap(\.programDay)
        guard let first = numbers.first, let last = numbers.last else { return "" }
        return "Gün \(first)–\(last)"
    }

    private func kpi(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(Color.ftTextSecondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ftCardBorder))
    }
}

// MARK: - Takvim

struct DietReportCalendar: View {
    let program: DietProgram
    let range: (Date, Date)
    let summary: DietRangeSummary
    let selected: Date?
    var interactive: Bool
    let onSelect: (Date) -> Void

    private static let weekdays = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]

    private var cells: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: range.0)
        let end = calendar.startOfDay(for: range.1)
        let startWeekday = (calendar.component(.weekday, from: start) + 5) % 7
        let endWeekday = (calendar.component(.weekday, from: end) + 5) % 7
        let first = calendar.date(byAdding: .day, value: -startWeekday, to: start) ?? start
        let last = calendar.date(byAdding: .day, value: 6 - endWeekday, to: end) ?? end
        var dates: [Date] = []
        var cursor = first
        while cursor <= last {
            dates.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? last.addingTimeInterval(86_400)
        }
        return dates
    }

    var body: some View {
        let byKey = Dictionary(summary.days.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TAKVİM").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(Color.ftAccentLight)
                Spacer()
                if interactive { Text("Bir güne dokun, ayrıntısı aşağıda").font(.caption2).foregroundStyle(Color.ftTextSecondary) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(Self.weekdays, id: \.self) { Text($0).font(.caption2.weight(.semibold)).foregroundStyle(Color.ftTextSecondary) }
                ForEach(cells, id: \.self) { date in
                    cell(date, day: byKey[DietDayKey.make(date)])
                }
            }
            legend
        }
    }

    @ViewBuilder
    private func cell(_ date: Date, day: DietDaySummary?) -> some View {
        let isSelected = selected.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
        let inRange = day != nil && day?.programDay != nil
        let future = date > Calendar.current.startOfDay(for: .now)
        let number = program.programDay(on: date)
        let content = VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Calendar.current.component(.day, from: date))").font(.caption.bold())
                Spacer(minLength: 0)
                if let number { Text("G\(number)").font(.system(size: 8)).foregroundStyle(Color.ftTextSecondary) }
            }
            if let day, inRange {
                Text(DietFormat.kcal(day.eaten.calories)).font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(kcalColor(day))
                HStack(spacing: 2) {
                    ForEach(day.meals) { snapshot in
                        Circle()
                            .fill(snapshot.status == nil ? Color.clear : DietStatusChip.color(snapshot.status))
                            .overlay(Circle().strokeBorder(dotStroke(snapshot), lineWidth: 1))
                            .frame(width: 6, height: 6)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    if day.photoCount > 0 { Text("\(day.photoCount) foto").foregroundStyle(Color.ftTextSecondary) }
                    if !day.extras.isEmpty { Text("+\(day.extras.count) ekstra").foregroundStyle(Color.ftDanger) }
                    if let tag = day.note?.tags.first { Text(tag).foregroundStyle(Color.ftText) }
                }
                .font(.system(size: 8))
                .lineLimit(1)
            } else if future, number != nil {
                Text("plan").font(.system(size: 9)).foregroundStyle(Color.ftTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(background(day: day, inRange: inRange), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(borderColor(isSelected: isSelected, future: future, planned: number != nil),
                                                                 style: borderStyle(isSelected: isSelected, future: future)))
        if interactive && inRange {
            Button { onSelect(date) } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel("\(DietFormat.longDate(date)), program günü \(number ?? 0)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            content
        }
    }

    private func borderColor(isSelected: Bool, future: Bool, planned: Bool) -> Color {
        if isSelected { return Color.ftText }
        return future && planned ? Color.ftCardBorder : .clear
    }

    private func borderStyle(isSelected: Bool, future: Bool) -> StrokeStyle {
        let dash: [CGFloat] = future && !isSelected ? [3] : []
        return StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: dash)
    }

    private func dotStroke(_ snapshot: DietMealSnapshot) -> Color {
        guard snapshot.status == nil else { return .clear }
        return snapshot.isMissed ? Color.ftDanger : Color.ftTextSecondary.opacity(0.5)
    }

    private func kcalColor(_ day: DietDaySummary) -> Color {
        let eaten = day.eaten.calories
        let planned = day.planned.calories
        if eaten > planned * 1.1 { return Color.ftDanger }
        if !day.isToday, eaten < planned * 0.85 { return Color.ftWarning }
        return Color.ftText
    }

    private func background(day: DietDaySummary?, inRange: Bool) -> Color {
        guard let day, inRange, let adherence = day.adherence else { return Color.ftSubtle(inRange ? 0.06 : 0.03) }
        if adherence >= 0.8 { return Color.ftSuccess.opacity(0.18) }
        if adherence >= 0.6 { return Color.ftWarning.opacity(0.2) }
        return Color.ftDanger.opacity(0.15)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendDot(Color.ftSuccess, "uydu")
            legendDot(Color.ftWarning, "değiştirdi")
            legendDot(Color.ftDanger, "atladı")
            legendDot(.clear, "işaretlenmedi", stroke: true)
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(Color.ftTextSecondary)
    }

    private func legendDot(_ color: Color, _ text: String, stroke: Bool = false) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).overlay(Circle().strokeBorder(stroke ? Color.ftTextSecondary : .clear)).frame(width: 7, height: 7)
            Text(text)
        }
    }
}

// MARK: - Seçilen gün

struct DietReportDayDetail: View {
    let program: DietProgram
    let day: DietDaySummary
    var interactive: Bool
    /// PDF'te fotoğraflar önceden yüklenir.
    var images: [String: UIImage] = [:]
    var onOpen: ((DietMealSnapshot) -> Void)?

    @Environment(DietStore.self) private var store

    private var subtitle: String {
        var parts = ["\(day.count(.eaten)) uydu"]
        if day.count(.changed) > 0 { parts.append("\(day.count(.changed)) değişim") }
        if day.count(.skipped) > 0 { parts.append("\(day.count(.skipped)) atlandı") }
        if day.missedCount > 0 { parts.append("\(day.missedCount) işaretlenmedi") }
        if day.pendingCount > 0 { parts.append("\(day.pendingCount) bekliyor") }
        if !day.extras.isEmpty { parts.append("+\(day.extras.count) ekstra") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gün \(day.programDay ?? 0) · \(DietFormat.longDate(day.date))").font(.headline).foregroundStyle(Color.ftText)
                    Text(subtitle).font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(DietFormat.kcal(day.eaten.calories)) kcal").font(.subheadline.bold())
                    if interactive, day.photoCount > 0 {
                        Button { saveAll() } label: {
                            Label("\(day.photoCount) fotoğraf", systemImage: "arrow.down.to.line").font(.caption2.weight(.semibold))
                        }
                        .tint(Color.ftAccentLight)
                        .accessibilityLabel("Günün fotoğraflarını indir")
                    }
                }
            }
            Group {
                if let note = day.note, !note.isEmpty {
                    (Text("Günün notu: ").bold() + Text(note.text.isEmpty ? note.tags.joined(separator: ", ") : note.text))
                        .font(.caption)
                } else {
                    Text("Günün notu: bu güne not yazılmamış.").font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ftAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))

            let paired = day.meals.count % 2 == 1 ? Array(day.meals.dropLast()) : day.meals
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(paired) { snapshot in card(snapshot, wide: false) }
            }
            // Tek kalan son öğün tam genişlikte, fotoğrafı daha büyük.
            if day.meals.count % 2 == 1, let last = day.meals.last {
                card(last, wide: true)
            }
            if !day.extras.isEmpty {
                Text("Ekstra: " + day.extras.map { "\($0.name) (\($0.nutrition.kcal) kcal)" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(Color.ftExercise)
            }
        }
        .padding(12)
        .background(Color.ftCard.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.ftAccent.opacity(0.4), lineWidth: 1.2))
    }

    @ViewBuilder
    private func card(_ snapshot: DietMealSnapshot, wide: Bool) -> some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                photo(snapshot)
                    .frame(height: wide ? 190 : 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                HStack {
                    DietStatusChip(status: snapshot.status, missed: snapshot.isMissed, thirdPerson: program.ownerID != store.userID, filled: true)
                    Spacer()
                    if let taken = snapshot.log?.photoTakenAt ?? snapshot.log?.loggedAt {
                        Text(taken.formatted(date: .omitted, time: .shortened)).font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.black.opacity(0.5), in: Capsule()).foregroundStyle(.white)
                    }
                }
                .padding(7)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(snapshot.meal.name).font(.subheadline.bold()).foregroundStyle(Color.ftText)
                    Spacer()
                    Text(snapshot.status == .eaten || snapshot.status == .changed ? "\(snapshot.eatenNutrition.kcal) kcal" : "—")
                        .font(.caption.bold()).foregroundStyle(Color.ftText)
                }
                Text(foodsText(snapshot)).font(.caption).foregroundStyle(Color.ftText).lineLimit(3)
                if let note = snapshot.log?.note, !note.isEmpty {
                    Text("“\(note)”").font(.caption2.italic()).foregroundStyle(Color.ftTextSecondary).lineLimit(2)
                }
                if interactive {
                    Text("İncele ›").font(.caption2.weight(.semibold)).foregroundStyle(Color.ftAccentLight)
                }
            }
            .padding(9)
        }
        .background(Color.ftCardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ftCardBorder, style: StrokeStyle(lineWidth: 1, dash: snapshot.log?.photoPath == nil ? [4] : [])))
        if interactive, let onOpen {
            Button { onOpen(snapshot) } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel("\(snapshot.meal.name), \(snapshot.status?.thirdPersonTitle ?? "işaretlenmedi"), incele")
        } else {
            content
        }
    }

    @ViewBuilder
    private func photo(_ snapshot: DietMealSnapshot) -> some View {
        if let path = snapshot.log?.photoPath {
            if let image = images[path] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                DietPhotoView(path: path)
            }
        } else {
            ZStack {
                Color.ftSubtle(0.06)
                Text("fotoğraf yok").font(.caption2).foregroundStyle(Color.ftTextSecondary)
            }
        }
    }

    private func foodsText(_ snapshot: DietMealSnapshot) -> String {
        switch snapshot.status {
        case .eaten, .changed:
            let eaten = snapshot.log?.eatenSummary ?? ""
            if snapshot.status == .changed, let swaps = snapshot.log?.swaps, !swaps.isEmpty { return swaps.joined(separator: " · ") }
            return eaten
        default:
            return "Plan: " + snapshot.meal.summaryText
        }
    }

    private func saveAll() {
        let paths = day.meals.compactMap { $0.log?.photoPath }
        Task {
            let saver = PhotoLibrarySaver()
            var saved = 0
            for path in paths {
                if let url = await store.loadPhoto(path), (try? await saver.save(fileURL: url, isVideo: false)) != nil { saved += 1 }
            }
            if saved > 0 {
                store.showToast("\(saved) fotoğraf Fotoğraflar'a kaydedildi")
                Haptics.success()
            } else {
                store.present(AppError.notAuthorized)
            }
        }
    }
}

// MARK: - Ortalamalar ve öne çıkanlar

struct DietReportAverages: View {
    let program: DietProgram
    let summary: DietRangeSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("GÜNLÜK ORTALAMA").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(Color.ftAccentLight)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                    GridRow {
                        Text("").font(.caption2)
                        Text("Plan").font(.caption2).foregroundStyle(Color.ftTextSecondary)
                        Text("Yenen").font(.caption2).foregroundStyle(Color.ftTextSecondary)
                        Text("Fark").font(.caption2).foregroundStyle(Color.ftTextSecondary)
                    }
                    ForEach(MacroKind.allCases) { kind in
                        let planned = summary.averagePlanned.grams(of: kind)
                        let eaten = summary.averageEaten.grams(of: kind)
                        let diff = Int((eaten - planned).rounded())
                        GridRow {
                            Text(kind.title).font(.caption)
                            Text("\(Int(planned.rounded())) g").font(.caption)
                            Text("\(Int(eaten.rounded())) g").font(.caption)
                            Text("\(diff >= 0 ? "+" : "")\(diff)").font(.caption).foregroundStyle(diff < -5 ? Color.ftDanger : Color.ftText)
                        }
                    }
                }
                Text("Dağılım \(summary.averageEaten.shareText)").font(.caption2).foregroundStyle(Color.ftTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("ÖNE ÇIKANLAR").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(Color.ftAccentLight)
                let stats = summary.mealStats
                if let mostChanged = stats.max(by: { $0.changed < $1.changed }), mostChanged.changed > 0 {
                    Text("En çok değişen: \(mostChanged.name) (\(mostChanged.changed)×)").font(.caption)
                }
                if let mostSkipped = stats.max(by: { $0.skipped < $1.skipped }), mostSkipped.skipped > 0 {
                    Text("En çok atlanan: \(mostSkipped.name) (\(mostSkipped.skipped)×)").font(.caption)
                }
                if let swap = summary.frequentSwaps.first { Text("Sık değişim: \(swap.text) \(swap.count)×").font(.caption) }
                if !summary.frequentExtras.isEmpty {
                    Text("Ekstralar: " + summary.frequentExtras.prefix(3).map { "\($0.text) \($0.count)×" }.joined(separator: ", ")).font(.caption)
                }
                if !summary.tagCounts.isEmpty {
                    Text("Notlarda: " + summary.tagCounts.prefix(3).map { "\($0.tag) \($0.count)" }.joined(separator: " · ")).font(.caption)
                }
                if let waist = program.metrics?.measurements["Bel"], let first = waist.first, let last = waist.last, waist.count > 1 {
                    Text("Bel \(DietFormat.number(first.value)) → \(DietFormat.number(last.value)) cm").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.ftText)
    }
}

// MARK: - Öğün inceleme

struct DietMealInspectView: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let program: DietProgram
    let summary: DietRangeSummary
    let dayKey: String
    @State var mealID: String
    @State private var fullScreen = false

    init(program: DietProgram, summary: DietRangeSummary, dayKey: String, mealID: String) {
        self.program = program
        self.summary = summary
        self.dayKey = dayKey
        _mealID = State(initialValue: mealID)
    }

    private var day: DietDaySummary? { summary.days.first { $0.dayKey == dayKey } }
    private var index: Int { day?.meals.firstIndex { $0.meal.id == mealID } ?? 0 }
    private var snapshot: DietMealSnapshot? { day.flatMap { $0.meals.indices.contains(index) ? $0.meals[index] : nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let snapshot, let day {
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack(alignment: .topLeading) {
                            Button { if snapshot.log?.photoPath != nil { fullScreen = true } } label: {
                                Group {
                                    if let path = snapshot.log?.photoPath {
                                        DietPhotoView(path: path)
                                    } else {
                                        ZStack {
                                            Color.black.opacity(0.85)
                                            Text("Bu öğün için fotoğraf yok").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                                        }
                                    }
                                }
                                .frame(height: 320)
                                .frame(maxWidth: .infinity)
                                .clipped()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Fotoğrafı tam ekran aç")
                            DietStatusChip(status: snapshot.status, missed: snapshot.isMissed, thirdPerson: program.ownerID != store.userID, filled: true)
                                .padding(10)
                            if let path = snapshot.log?.photoPath {
                                HStack { Spacer(); DietPhotoActions(path: path) }.padding(10)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        if let note = snapshot.log?.note, !note.isEmpty {
                            Text("“\(note)”").font(.subheadline.italic()).padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.ftAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        if snapshot.status == .changed, let swaps = snapshot.log?.swaps, !swaps.isEmpty {
                            ForEach(swaps, id: \.self) { Text("↺ \($0)").font(.caption.weight(.semibold)).foregroundStyle(Color.ftWarning) }
                        }
                        foodTable(snapshot)
                        if let log = snapshot.log {
                            DietCommentList(programID: program.id, targetID: log.id)
                        }
                        Text("Gün \(day.programDay ?? 0) · \(DietFormat.longDate(day.date)) · \(index + 1) / \(day.meals.count)")
                            .font(.caption).foregroundStyle(Color.ftTextSecondary)
                    }
                    .padding(16)
                }
            }
            .ftScreenBackground()
            .navigationTitle(snapshot.map { "\($0.meal.name) · \($0.log?.photoTakenAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? $0.meal.timeText)" } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Kapat") }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Önceki öğün")
                    Button { move(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Sonraki öğün")
                }
            }
            .fullScreenCover(isPresented: $fullScreen) {
                if let path = snapshot?.log?.photoPath {
                    DietPhotoFullScreen(path: path, title: snapshot?.meal.name ?? "")
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = store.toast { DietToastView(text: toast).padding(.bottom, 24) }
            }
        }
    }

    private func move(_ offset: Int) {
        guard let day, !day.meals.isEmpty else { return }
        Haptics.selection()
        mealID = day.meals[(index + offset + day.meals.count) % day.meals.count].meal.id
    }

    private func foodTable(_ snapshot: DietMealSnapshot) -> some View {
        let marked = snapshot.status == .eaten || snapshot.status == .changed
        let list = marked ? (snapshot.log?.eaten ?? []) : snapshot.meal.portions
        let total = DietNutrition.sum(list.map(\.nutrition))
        let planned = snapshot.meal.nutrition
        return VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    Text(marked ? "Yenen" : "Plandaki").bold()
                    Text("Miktar").foregroundStyle(Color.ftTextSecondary)
                    Text("kcal").foregroundStyle(Color.ftTextSecondary)
                    Text("P / K / Y").foregroundStyle(Color.ftTextSecondary)
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(list.enumerated()), id: \.offset) { _, portion in
                    GridRow {
                        Text(portion.food.name)
                        Text(portion.shortAmountText)
                        Text("\(portion.nutrition.kcal)")
                        Text("\(Int(portion.nutrition.protein.rounded())) / \(Int(portion.nutrition.carbs.rounded())) / \(Int(portion.nutrition.fat.rounded())) g")
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("Toplam").bold()
                    Text("")
                    Text("\(total.kcal)").bold()
                    Text("\(Int(total.protein.rounded())) / \(Int(total.carbs.rounded())) / \(Int(total.fat.rounded())) g").bold()
                }
            }
            .font(.caption)
            Text(marked ? "Plan \(planned.kcal) kcal → yenen \(total.kcal) kcal (\(total.kcal - planned.kcal >= 0 ? "+" : "")\(total.kcal - planned.kcal))"
                 : (snapshot.status == .skipped ? "Bu öğün atlandı; değerler plandakilerdir." : "Bu öğün henüz işaretlenmedi."))
                .font(.caption).foregroundStyle(Color.ftTextSecondary)
        }
        .cardStyle(padding: 12)
    }
}

/// Fotoğrafın sağ üst köşesindeki küçük paylaş / indir simgeleri.
struct DietPhotoActions: View {
    @Environment(DietStore.self) private var store
    let path: String
    @State private var url: URL?

    var body: some View {
        HStack(spacing: 8) {
            if let url {
                ShareLink(item: url) { icon("square.and.arrow.up") }.accessibilityLabel("Paylaş")
            }
            Button {
                Task {
                    guard let url = await store.loadPhoto(path) else { return }
                    do {
                        try await PhotoLibrarySaver().save(fileURL: url, isVideo: false)
                        store.showToast("Fotoğraflar'a kaydedildi")
                        Haptics.success()
                    } catch { store.present(error) }
                }
            } label: { icon("arrow.down.to.line") }
            .accessibilityLabel("Fotoğrafı indir")
        }
        .task(id: path) { url = await store.loadPhoto(path) }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.subheadline.weight(.semibold))
            .frame(width: 34, height: 34)
            .foregroundStyle(.white)
            .background(Color.black.opacity(0.5), in: Circle())
    }
}

// MARK: - PDF

@MainActor
enum DietReportPDF {
    static let pageSize = CGSize(width: 595, height: 842)

    /// İlk sayfa takvim ve özet; sonra her program günü için bir sayfa (fotoğraflarıyla).
    static func make(program: DietProgram, summary: DietRangeSummary, store: DietStore) async throws -> URL {
        var images: [String: UIImage] = [:]
        for day in summary.days {
            for snapshot in day.meals {
                guard let path = snapshot.log?.photoPath, images[path] == nil,
                      let url = await store.loadPhoto(path), let image = UIImage(contentsOfFile: url.path) else { continue }
                images[path] = image.preparingThumbnail(of: CGSize(width: 700, height: 700)) ?? image
            }
        }
        let range = (summary.days.first?.date ?? program.startDate, summary.days.last?.date ?? .now)
        var pages: [AnyView] = [
            AnyView(DietPDFPage {
                DietReportHeader(program: program, range: range, summary: summary)
                DietReportCalendar(program: program, range: range, summary: summary, selected: nil, interactive: false) { _ in }
                DietReportAverages(program: program, summary: summary)
            })
        ]
        for day in summary.days where day.programDay != nil && !day.isFuture && (day.markedCount > 0 || day.note != nil || day.isToday == false) {
            pages.append(AnyView(DietPDFPage {
                DietReportDayDetail(program: program, day: day, interactive: false, images: images)
            }))
        }

        let name = "\(program.name.replacingOccurrences(of: "/", with: "-"))-kontrol-raporu.pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw AppError.unknown("PDF oluşturulamadı.")
        }
        for page in pages {
            let renderer = ImageRenderer(content: page.environment(store).environment(\.colorScheme, .light).frame(width: pageSize.width, height: pageSize.height))
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, render in
                context.beginPDFPage(nil)
                render(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return url
    }
}

/// A4 sayfa: krem kâğıt, kenar boşlukları, alt bilgi.
struct DietPDFPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
            Spacer(minLength: 0)
            HStack {
                Text("Değerler kütüphane ortalamalarıyla hesaplanmış tahminlerdir.")
                Spacer()
                Text("FarvaTrack · \(Date.now.formatted(date: .numeric, time: .omitted))")
            }
            .font(.system(size: 8))
            .foregroundStyle(Color(red: 0.48, green: 0.36, blue: 0.27))
        }
        .padding(32)
        .frame(width: DietReportPDF.pageSize.width, height: DietReportPDF.pageSize.height, alignment: .topLeading)
        .background(Color(red: 0.984, green: 0.957, blue: 0.886))
    }
}
