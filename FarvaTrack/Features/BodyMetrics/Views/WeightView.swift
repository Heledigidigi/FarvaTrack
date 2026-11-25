import SwiftUI
import SwiftData

enum WeightRange: String, CaseIterable, Identifiable {
    case month = "1A", quarter = "3A", year = "1Y"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        }
    }
}

struct WeightView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = BodyMetricsViewModel()
    @State private var editor: WeightEditorTarget?
    @State private var showGoal = false
    @State private var showReminder = false

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    var body: some View {
        Group {
            if let user = auth.currentUser {
                WeightContent(
                    ownerID: user.id,
                    viewModel: viewModel,
                    onEdit: { editor = $0 },
                    onGoal: { showGoal = true }
                )
            } else {
                ProgressView()
            }
        }
        .ftScreenBackground()
        .navigationTitle("Kilo")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showReminder = true
                } label: {
                    Image(systemName: viewModel.reminderSettings.isEnabled ? "bell.badge.fill" : "bell")
                }
                .accessibilityLabel("Tartı hatırlatıcısı")

                Button {
                    Haptics.impact(.light)
                    editor = WeightEditorTarget(entry: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Tartı ekle")
            }
        }
        .sheet(item: $editor) { target in
            WeightEditorSheet(viewModel: viewModel, entry: target.entry, onSaved: syncProfileWeight)
        }
        .sheet(isPresented: $showGoal) {
            WeightGoalSheet(viewModel: viewModel, currentKg: viewModel.latestWeight() ?? auth.currentUser?.weightKg) { target in
                guard var user = auth.currentUser else { return }
                user.targetWeightKg = target
                if user.startWeightKg == nil || target == nil {
                    user.startWeightKg = target == nil ? nil : (viewModel.latestWeight() ?? user.weightKg)
                }
                Task { await auth.updateUser(user) }
            }
        }
        .sheet(isPresented: $showReminder) {
            WeighInReminderSheet(viewModel: viewModel)
        }
        .alert("Bir sorun oluştu", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: auth.currentUser, initial: true) { _, user in
            if let user { viewModel.configure(context: modelContext, user: user) }
        }
        .task(id: auth.currentUser?.id) {
            if let user = auth.currentUser { viewModel.configure(context: modelContext, user: user) }
            await viewModel.syncAll()
            syncProfileWeight()
        }
    }

    /// Profildeki kiloyu en son tartıyla eşitler (kalori ve su hedefleri buna göre hesaplanır).
    private func syncProfileWeight() {
        guard var user = auth.currentUser, let latest = viewModel.latestWeight() else { return }
        guard abs((user.weightKg ?? 0) - latest) >= 0.05 else { return }
        user.weightKg = latest
        Task { await auth.updateUser(user) }
    }
}

struct WeightEditorTarget: Identifiable {
    let entry: WeightEntry?
    let id = UUID()
}

// MARK: - İçerik
private struct WeightContent: View {
    @Query private var entries: [WeightEntry]
    let viewModel: BodyMetricsViewModel
    let onEdit: (WeightEditorTarget) -> Void
    let onGoal: () -> Void

    @State private var range: WeightRange = .quarter

    init(ownerID: String, viewModel: BodyMetricsViewModel, onEdit: @escaping (WeightEditorTarget) -> Void, onGoal: @escaping () -> Void) {
        _entries = Query(filter: #Predicate<WeightEntry> { $0.ownerID == ownerID }, sort: \.date, order: .reverse)
        self.viewModel = viewModel
        self.onEdit = onEdit
        self.onGoal = onGoal
    }

    var body: some View {
        let points = entries.map(\.point)
        let start = Date.now.addingTimeInterval(-Double(range.days) * 86_400)
        let visible = points.filter { $0.date >= start }.sorted { $0.date < $1.date }
        let latest = entries.first

        List {
            Section {
                header(latest: latest, points: points)
                    .listRowBackground(Color.ftCard)
            }

            if visible.count >= 2 {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Aralık", selection: $range) {
                            ForEach(WeightRange.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        TrendChartView(points: visible, target: viewModel.targetWeightKg)
                            .frame(height: 200)
                        Text("Noktalar tartıları, çizgi 7 günlük ortalamayı gösterir.")
                            .font(.caption2)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.ftCard)
                }
            }

            Section {
                goalCard(latest: latest?.weightKg, points: points)
                    .listRowBackground(Color.ftCard)
            }

            if let latest, let bmi = viewModel.bmi(for: latest.weightKg) {
                Section {
                    BMIGaugeView(bmi: bmi)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.ftCard)
                }
            } else if viewModel.heightCm == nil {
                Section {
                    Label("BMI için profiline boyunu ekle.", systemImage: "ruler")
                        .foregroundStyle(Color.ftTextSecondary)
                        .listRowBackground(Color.ftCard)
                }
            }

            Section {
                NavigationLink {
                    MeasurementsView(viewModel: viewModel)
                } label: {
                    Label("Vücut Ölçüleri", systemImage: "ruler.fill")
                        .foregroundStyle(Color.ftWeight)
                }
                .listRowBackground(Color.ftCard)
            }

            Section("Tartılar") {
                if entries.isEmpty {
                    Text("Henüz tartı kaydın yok. Sağ üstteki + ile ekleyebilirsin.")
                        .foregroundStyle(Color.ftTextSecondary)
                        .listRowBackground(Color.ftCard)
                }
                ForEach(Array(entries.prefix(60).enumerated()), id: \.element.id) { index, entry in
                    Button {
                        onEdit(WeightEditorTarget(entry: entry))
                    } label: {
                        row(entry, previous: index + 1 < entries.count ? entries[index + 1] : nil)
                    }
                    .listRowBackground(Color.ftCard)
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.deleteWeight(entry)
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func header(latest: WeightEntry?, points: [WeightPoint]) -> some View {
        if let latest {
            VStack(alignment: .leading, spacing: 8) {
                Text("Son tartı • \(latest.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "tr_TR"))))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ftTextSecondary)
                Text(WeightAnalyzer.kgText(latest.weightKg))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 16) {
                    change("7 gün", WeightAnalyzer.change(points, days: 7))
                    change("30 gün", WeightAnalyzer.change(points, days: 30))
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        } else {
            Button {
                onEdit(WeightEditorTarget(entry: nil))
            } label: {
                Label("İlk tartını ekle", systemImage: "scalemass.fill")
                    .font(.headline)
                    .foregroundStyle(Color.ftWeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    private func change(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { WeightAnalyzer.kgText($0, signed: true) } ?? "—")
                .font(.subheadline.bold().monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(Color.ftTextSecondary)
        }
    }

    @ViewBuilder
    private func goalCard(latest: Double?, points: [WeightPoint]) -> some View {
        if let target = viewModel.targetWeightKg, let latest {
            let start = viewModel.startWeightKg ?? points.last?.weightKg ?? latest
            let progress = WeightAnalyzer.goalProgress(start: start, current: latest, target: target)
            let weeks = WeightAnalyzer.weeksToGoal(current: latest, target: target, weeklyRate: WeightAnalyzer.weeklyRate(points))

            Button(action: onGoal) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Hedef: \(WeightAnalyzer.kgText(target))").font(.headline).foregroundStyle(Color.ftText)
                        Spacer()
                        Text("%\(Int(progress * 100))").font(.headline.monospacedDigit()).foregroundStyle(Color.ftWeight)
                    }
                    ProgressView(value: progress).tint(Color.ftWeight)
                    HStack {
                        Text("Başlangıç \(WeightAnalyzer.kgText(start))")
                        Spacer()
                        Text(abs(target - latest) < 0.1 ? "Hedefe ulaştın 🎉" : "Kalan \(WeightAnalyzer.kgText(abs(target - latest)))")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.ftTextSecondary)
                    if let weeks {
                        Text("Bu hızla yaklaşık \(weeks) hafta.")
                            .font(.caption)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Hedefi düzenle")
        } else {
            Button(action: onGoal) {
                Label("Hedef kilo belirle", systemImage: "target")
                    .foregroundStyle(Color.ftWeight)
            }
        }
    }

    private func row(_ entry: WeightEntry, previous: WeightEntry?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "tr_TR"))))
                    .font(.subheadline)
                    .foregroundStyle(Color.ftText)
                if let note = entry.note {
                    Text(note).font(.caption).foregroundStyle(Color.ftTextSecondary).lineLimit(1)
                }
            }
            Spacer()
            if let previous {
                let diff = entry.weightKg - previous.weightKg
                Text(WeightAnalyzer.kgText(diff, signed: true))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.ftTextSecondary)
            }
            Text(WeightAnalyzer.kgText(entry.weightKg))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.ftText)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tartı ekle / düzenle
private struct WeightEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: BodyMetricsViewModel
    let entry: WeightEntry?
    let onSaved: () -> Void

    @State private var kg: Double
    @State private var date: Date
    @State private var note: String
    @State private var saveError: String?

    init(viewModel: BodyMetricsViewModel, entry: WeightEntry?, onSaved: @escaping () -> Void) {
        self.viewModel = viewModel
        self.entry = entry
        self.onSaved = onSaved
        _kg = State(initialValue: entry?.weightKg ?? viewModel.latestWeight() ?? Constants.Training.fallbackWeightKg)
        _date = State(initialValue: entry?.date ?? .now)
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Button { adjust(-0.1) } label: { Image(systemName: "minus.circle.fill").font(.largeTitle) }
                            .accessibilityLabel("100 gram azalt")
                        Spacer()
                        TextField("Kilo", value: $kg, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .accessibilityLabel("Kilo, kilogram")
                        Text("kg").foregroundStyle(Color.ftTextSecondary)
                        Spacer()
                        Button { adjust(0.1) } label: { Image(systemName: "plus.circle.fill").font(.largeTitle) }
                            .accessibilityLabel("100 gram artır")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.ftWeight)
                }

                Section {
                    DatePicker("Tarih", selection: $date, in: ...Date.now)
                    TextField("Not (isteğe bağlı)", text: $note)
                }

                if let entry {
                    Section {
                        Button("Tartıyı sil", role: .destructive) {
                            viewModel.deleteWeight(entry)
                            onSaved()
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .ftScreenBackground()
            .navigationTitle(entry == nil ? "Tartı Ekle" : "Tartıyı Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        do {
                            try viewModel.saveWeight(kg, date: date, note: note, editing: entry)
                            onSaved()
                            dismiss()
                        } catch {
                            saveError = AppError.map(error).errorDescription
                            Haptics.error()
                        }
                    }
                }
            }
        }
        .alert("Kaydedilemedi", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .presentationDetents([.medium, .large])
    }

    private func adjust(_ delta: Double) {
        Haptics.selection()
        kg = min(max(((kg + delta) * 10).rounded() / 10, WeightAnalyzer.validRange.lowerBound), WeightAnalyzer.validRange.upperBound)
    }
}

// MARK: - Hedef
private struct WeightGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: BodyMetricsViewModel
    let currentKg: Double?
    let onSave: (Double?) -> Void

    @State private var target: Double

    init(viewModel: BodyMetricsViewModel, currentKg: Double?, onSave: @escaping (Double?) -> Void) {
        self.viewModel = viewModel
        self.currentKg = currentKg
        self.onSave = onSave
        _target = State(initialValue: viewModel.targetWeightKg ?? currentKg ?? Constants.Training.fallbackWeightKg)
    }

    private var validation: WeightGoalValidation {
        viewModel.validateGoal(target, currentKg: currentKg)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $target, in: WeightAnalyzer.validRange, step: 0.5) {
                        HStack {
                            Text("Hedef kilo")
                            Spacer()
                            Text(WeightAnalyzer.kgText(target)).monospacedDigit()
                        }
                    }
                    if let height = viewModel.heightCm, let healthy = WeightAnalyzer.healthyRange(heightCm: height) {
                        Text("Boyuna göre sağlıklı aralık: \(WeightAnalyzer.kgText(healthy.lowerBound)) – \(WeightAnalyzer.kgText(healthy.upperBound))")
                            .font(.caption)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                } footer: {
                    if let message = validation.message {
                        Text(message).foregroundStyle(Color.ftWarning)
                    } else {
                        Text("Haftada 0,25–1 kg arası değişim çoğu kişi için sürdürülebilir kabul edilir.")
                    }
                }

                if viewModel.targetWeightKg != nil {
                    Section {
                        Button("Hedefi kaldır", role: .destructive) {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .ftScreenBackground()
            .navigationTitle("Kilo Hedefi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        Haptics.success()
                        onSave(target)
                        dismiss()
                    }
                    .disabled(validation != .ok)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Tartı hatırlatıcısı
private struct WeighInReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: BodyMetricsViewModel

    @State private var draft: WeighInReminderSettings
    @State private var time: Date
    @State private var permissionDenied = false

    init(viewModel: BodyMetricsViewModel) {
        self.viewModel = viewModel
        let settings = viewModel.reminderSettings
        _draft = State(initialValue: settings)
        _time = State(initialValue: Calendar.current.date(
            bySettingHour: settings.hour, minute: settings.minute, second: 0, of: .now
        ) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Haftalık tartı hatırlatıcısı", isOn: $draft.isEnabled)
                    if draft.isEnabled {
                        Picker("Gün", selection: $draft.weekday) {
                            ForEach(Self.weekdays, id: \.value) { day in
                                Text(day.name).tag(day.value)
                            }
                        }
                        DatePicker("Saat", selection: $time, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    if permissionDenied {
                        Text("Bildirim izni kapalı. Ayarlar > FarvaTrack > Bildirimler'den açabilirsin.")
                            .foregroundStyle(Color.ftWarning)
                    } else {
                        Text("Sabah, kahvaltıdan önce tartılmak daha tutarlı sonuç verir.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .ftScreenBackground()
            .navigationTitle("Hatırlatıcı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private static let weekdays: [(name: String, value: Int)] = [
        ("Pazartesi", 2), ("Salı", 3), ("Çarşamba", 4), ("Perşembe", 5),
        ("Cuma", 6), ("Cumartesi", 7), ("Pazar", 1)
    ]

    private func save() {
        var settings = draft
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        settings.hour = components.hour ?? 8
        settings.minute = components.minute ?? 0
        Task {
            if await viewModel.applyReminder(settings) {
                Haptics.success()
                dismiss()
            } else {
                draft.isEnabled = false
                permissionDenied = true
            }
        }
    }
}
