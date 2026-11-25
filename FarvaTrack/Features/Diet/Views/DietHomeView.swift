import SwiftUI

/// Beslenme sekmesi, takip edilen bir program varken: Bugün / Program / Analiz.
struct DietHomeView: View {
    @Environment(DietStore.self) private var store
    let program: DietProgram
    let nutrition: NutritionViewModel
    let onAddExtra: () -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case today, program, analysis
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: return "Bugün"
            case .program: return "Program"
            case .analysis: return "Analiz"
            }
        }
    }

    @State private var tab: Tab = .today
    @State private var date = Date.now

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Picker("Bölüm", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .today:
                    DietTodayContent(program: program, date: $date, onAddExtra: onAddExtra)
                case .program:
                    DietProgramOverview(program: program)
                case .analysis:
                    DietAnalysisView(program: program)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await store.syncAll() }
    }
}

// MARK: - Bugün

struct DietTodayContent: View {
    @Environment(DietStore.self) private var store
    let program: DietProgram
    @Binding var date: Date
    let onAddExtra: () -> Void

    @State private var showDayNote = false

    private var summary: DietDaySummary? {
        store.summary(for: program, from: date, to: date).days.first
    }

    private var currentMealID: String? {
        guard Calendar.current.isDateInToday(date), let summary else { return nil }
        let minutes = Calendar.current.component(.hour, from: .now) * 60 + Calendar.current.component(.minute, from: .now)
        let open = summary.meals.filter { $0.status == nil }
        return (open.last(where: { $0.meal.minutes <= minutes + 45 }) ?? open.first)?.meal.id
    }

    private var subtitle: String? {
        if let number = program.programDay(on: date) {
            let cycle = program.cycle(on: date)
            return "Gün \(number) / \(program.version(on: date).plan.dayCount)" + (cycle > 0 ? " · \(cycle + 1). tur" : "")
        }
        if program.dayOffset(of: date) < 0 { return "Program \(DietFormat.shortDate(program.startDate)) tarihinde başlıyor" }
        return "Program bitti"
    }

    var body: some View {
        VStack(spacing: 12) {
            DietDayNavigator(date: date, subtitle: subtitle,
                             canGoForward: date < (Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)) { offset in
                Haptics.selection()
                date = Calendar.current.date(byAdding: .day, value: offset, to: date) ?? date
            }

            if let summary, summary.programDay != nil {
                DietDayRingCard(summary: summary)
                ForEach(summary.meals) { snapshot in
                    DietMealCard(program: program, date: date, snapshot: snapshot, isCurrent: snapshot.meal.id == currentMealID)
                }
                extras(summary)
                dayNote(summary)
            } else {
                ContentUnavailableView {
                    Label(subtitle ?? "Bu gün programın dışında", systemImage: "calendar")
                } description: {
                    Text("Programın günlerini görmek için Program bölümüne geç ya da başka bir güne git.")
                }
                .padding(.vertical, 30)
            }
        }
        .sheet(isPresented: $showDayNote) {
            DietDayNoteSheet(programID: program.id, date: date, note: store.note(programID: program.id, dayKey: DietDayKey.make(date)))
        }
    }

    private func extras(_ summary: DietDaySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !summary.extras.isEmpty {
                DietSectionTitle(text: "Program dışı (Ekstra)")
                ForEach(summary.extras) { extra in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(extra.name).font(.subheadline).foregroundStyle(Color.ftText)
                            Text("\(extra.amountText) · \(extra.date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(Color.ftTextSecondary)
                        }
                        Spacer()
                        Text("\(extra.nutrition.kcal) kcal").font(.caption.weight(.semibold)).foregroundStyle(Color.ftExercise)
                    }
                    .padding(12)
                    .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if Calendar.current.isDateInToday(date) {
                Button(action: onAddExtra) {
                    Label("Program dışı ekle (Ekstra)", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Color.ftAccentLight)
                .padding(.top, 2)
            }
        }
    }

    private func dayNote(_ summary: DietDaySummary) -> some View {
        Button { showDayNote = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Günün notu").font(.headline).foregroundStyle(Color.ftText)
                    Spacer()
                    Text(summary.note?.isEmpty == false ? "Düzenle" : "Ekle").font(.caption.weight(.semibold)).foregroundStyle(Color.ftAccentLight)
                }
                if let note = summary.note, !note.isEmpty {
                    if !note.text.isEmpty {
                        Text(note.text).font(.subheadline).foregroundStyle(Color.ftText).multilineTextAlignment(.leading)
                    }
                    if !note.tags.isEmpty {
                        DietTagRow(tags: note.tags, selected: Set(note.tags))
                    }
                } else {
                    Text("Bugün nasıl geçti? Açlık, enerji, antrenman…").font(.subheadline).foregroundStyle(Color.ftTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 14)
        }
        .buttonStyle(.plain)
    }
}

/// Günün kalori halkası ve makrolar (plan karşısında).
struct DietDayRingCard: View {
    let summary: DietDaySummary

    var body: some View {
        let eaten = summary.eaten
        let planned = summary.planned
        let progress = planned.calories > 0 ? min(1, eaten.calories / planned.calories) : 0
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.ftSubtle(0.15), lineWidth: 9)
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.ftCalories, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(DietFormat.kcal(eaten.calories)).font(.headline.monospacedDigit()).foregroundStyle(Color.ftText)
                    Text("/ \(DietFormat.kcal(planned.calories))").font(.caption2).foregroundStyle(Color.ftTextSecondary)
                }
            }
            .frame(width: 82, height: 82)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Plan \(planned.kcal), yenen \(eaten.kcal) kilokalori")

            VStack(alignment: .leading, spacing: 6) {
                DietMacroColumns(nutrition: eaten, target: planned)
                Text(statusLine).font(.caption).foregroundStyle(Color.ftTextSecondary)
            }
        }
        .cardStyle(padding: 14)
    }

    private var statusLine: String {
        var parts: [String] = []
        let eaten = summary.count(.eaten)
        if eaten > 0 { parts.append("\(eaten) öğün ✓") }
        let changed = summary.count(.changed)
        if changed > 0 { parts.append("\(changed) değişim") }
        let skipped = summary.count(.skipped)
        if skipped > 0 { parts.append("\(skipped) atlandı") }
        if summary.pendingCount > 0 { parts.append("\(summary.pendingCount) bekliyor") }
        if !summary.extras.isEmpty { parts.append("+\(summary.extras.count) ekstra") }
        return parts.isEmpty ? "Henüz işaretlenen öğün yok" : parts.joined(separator: " · ")
    }
}

// MARK: - Günün notu

struct DietTagRow: View {
    let tags: [String]
    let selected: Set<String>
    var onTap: ((String) -> Void)?

    var body: some View {
        DietFlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                let isOn = selected.contains(tag)
                Group {
                    if let onTap {
                        Button(tag) { onTap(tag) }.buttonStyle(.plain)
                    } else {
                        Text(tag)
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isOn ? Color.white : Color.ftText)
                .background(isOn ? Color.ftAccent : Color.ftSubtle(0.12), in: Capsule())
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

struct DietDayNoteSheet: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let programID: String
    let date: Date
    @State private var text: String
    @State private var tags: [String]
    @State private var newTag = ""

    init(programID: String, date: Date, note: DietDayNote?) {
        self.programID = programID
        self.date = date
        _text = State(initialValue: note?.text ?? "")
        _tags = State(initialValue: note?.tags ?? [])
    }

    private var allTags: [String] {
        DietDayNote.suggestedTags + tags.filter { !DietDayNote.suggestedTags.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Not") {
                    TextField("Bugün nasıl geçti?", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Etiketler") {
                    DietTagRow(tags: allTags, selected: Set(tags)) { tag in
                        Haptics.selection()
                        if let index = tags.firstIndex(of: tag) { tags.remove(at: index) } else { tags.append(tag) }
                    }
                    HStack {
                        TextField("Yeni etiket", text: $newTag)
                            .onSubmit(addTag)
                        Button("Ekle", action: addTag).disabled(newTag.trimmed.isEmpty)
                    }
                }
            }
            .navigationTitle(DietFormat.dayTitle(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        do {
                            try store.saveDayNote(programID: programID, date: date, text: text, tags: tags)
                            Haptics.success()
                            dismiss()
                        } catch { store.present(error) }
                    }
                    .bold()
                }
            }
        }
    }

    private func addTag() {
        let tag = String(newTag.trimmed.prefix(24))
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        newTag = ""
    }
}

/// Satır sığmazsa alta geçen yerleşim (etiketler için).
struct DietFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
