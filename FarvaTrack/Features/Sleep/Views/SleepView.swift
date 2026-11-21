import SwiftUI
import SwiftData

struct SleepView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = SleepViewModel()
    @State private var editor: SleepEditorTarget?
    @State private var showSettings = false

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    var body: some View {
        Group {
            if let user = auth.currentUser {
                SleepContent(ownerID: user.id, viewModel: viewModel, onEdit: { editor = $0 })
            } else {
                ProgressView()
            }
        }
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Uyku")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: viewModel.settings.reminderEnabled ? "bell.badge.fill" : "bell")
                }
                .accessibilityLabel("Uyku ayarları ve hatırlatıcı")

                Button {
                    Haptics.impact(.light)
                    editor = SleepEditorTarget(entry: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Uyku kaydı ekle")
            }
        }
        .sheet(item: $editor) { target in
            SleepEditorSheet(viewModel: viewModel, entry: target.entry)
        }
        .sheet(isPresented: $showSettings) {
            SleepSettingsSheet(viewModel: viewModel) { newGoal in
                guard var user = auth.currentUser else { return }
                user.sleepGoalHours = newGoal
                Task { await auth.updateUser(user) }
            }
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
        }
    }
}

struct SleepEditorTarget: Identifiable {
    let entry: SleepEntry?
    let id = UUID()
}

// MARK: - İçerik
private struct SleepContent: View {
    @Query private var entries: [SleepEntry]
    let viewModel: SleepViewModel
    let onEdit: (SleepEditorTarget) -> Void

    init(ownerID: String, viewModel: SleepViewModel, onEdit: @escaping (SleepEditorTarget) -> Void) {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date.now.startOfDay) ?? .distantPast
        _entries = Query(
            filter: #Predicate<SleepEntry> { $0.ownerID == ownerID && $0.day >= since },
            sort: \.day,
            order: .reverse
        )
        self.viewModel = viewModel
        self.onEdit = onEdit
    }

    var body: some View {
        let records = entries.map(\.record)
        let goal = viewModel.goalHours
        let report = SleepAnalyzer.report(records: records, endingOn: .now, goalHours: goal)
        let regularity = SleepAnalyzer.regularity(records: records)
        let lastNight = entries.first { Calendar.current.isDateInToday($0.day) }

        List {
            Section {
                lastNightCard(lastNight, goal: goal)
                    .listRowBackground(Color.ftCard)
            }

            Section {
                Text(SleepAnalyzer.summary(report: report, goalHours: goal))
                    .font(.subheadline)
                    .listRowBackground(Color.ftCard)

                HStack(spacing: 12) {
                    metric("Ortalama", report.averageHours.map { SleepAnalyzer.durationText(hours: $0) } ?? "—")
                    metric("Kalite", report.averageQuality.map { $0.formatted(.number.precision(.fractionLength(1))) + " ★" } ?? "—")
                    metric("Uyku borcu", report.debtHours > 0 ? SleepAnalyzer.durationText(hours: report.debtHours) : "Yok")
                }
                .listRowBackground(Color.ftCard)
            } header: {
                Text("Bu Hafta")
            }

            if !report.recorded.isEmpty {
                Section("Süre (saat)") {
                    ChartView(data: report.durationChart, goal: goal, tint: Color.ftSleep, unit: "sa", fractionDigits: 1)
                        .frame(height: 170)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.ftCard)
                }
                Section("Kalite (yıldız)") {
                    ChartView(data: report.qualityChart, tint: Color.ftStats, unit: "★")
                        .frame(height: 140)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.ftCard)
                }
            }

            if let regularity {
                Section("Uyku Düzeni") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(regularity.label).font(.headline)
                            Text("Ortalama yatış \(SleepAnalyzer.timeText(minutes: regularity.averageBedtimeMinutes)), uyanış \(SleepAnalyzer.timeText(minutes: regularity.averageWakeMinutes))")
                                .font(.caption)
                                .foregroundStyle(Color.ftTextSecondary)
                        }
                        Spacer()
                        Text("\(regularity.score)")
                            .font(.title.bold().monospacedDigit())
                            .foregroundStyle(Color.ftSleep)
                    }
                    .accessibilityElement(children: .combine)
                    .listRowBackground(Color.ftCard)
                }
            }

            Section {
                ForEach(viewModel.suggestions) { suggestion in
                    HStack {
                        Image(systemName: suggestion.isRecommended ? "moon.stars.fill" : "moon")
                            .foregroundStyle(Color.ftSleep)
                        Text(SleepAnalyzer.timeText(minutes: suggestion.bedtimeMinutes))
                            .font(.body.monospacedDigit().weight(suggestion.isRecommended ? .bold : .regular))
                        Spacer()
                        Text("\(suggestion.cycles) döngü • \(SleepAnalyzer.durationText(hours: suggestion.sleepHours))")
                            .font(.caption)
                            .foregroundStyle(Color.ftTextSecondary)
                        if suggestion.isRecommended {
                            Text("Önerilen")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.ftSleep.opacity(0.25), in: Capsule())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .listRowBackground(Color.ftCard)
                }
            } header: {
                Text("\(SleepAnalyzer.timeText(minutes: viewModel.settings.targetWakeMinutes)) uyanış için yatış saatleri")
            } footer: {
                Text("90 dakikalık uyku döngüleri ve ~15 dakikalık uykuya dalma süresiyle hesaplanır.")
            }

            Section("Kayıtlar") {
                if entries.isEmpty {
                    Text("Henüz uyku kaydın yok. Sağ üstteki + ile ekleyebilirsin.")
                        .foregroundStyle(Color.ftTextSecondary)
                        .listRowBackground(Color.ftCard)
                }
                ForEach(entries) { entry in
                    Button {
                        onEdit(SleepEditorTarget(entry: entry))
                    } label: {
                        row(entry)
                    }
                    .listRowBackground(Color.ftCard)
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.delete(entry)
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
    private func lastNightCard(_ entry: SleepEntry?, goal: Double) -> some View {
        if let entry {
            HStack(spacing: 16) {
                ProgressRing(progress: entry.durationHours / goal, lineWidth: 10, color: Color.ftSleep) {
                    Image(systemName: "moon.zzz.fill").font(.title2).foregroundStyle(Color.ftSleep)
                }
                .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dün gece").font(.caption.weight(.semibold)).foregroundStyle(Color.ftTextSecondary)
                    Text(SleepAnalyzer.durationText(hours: entry.durationHours))
                        .font(.title.bold())
                    Text("\(entry.bedtime.formatted(date: .omitted, time: .shortened)) – \(entry.wakeTime.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                    StarRatingView(value: entry.quality)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        } else {
            Button {
                onEdit(SleepEditorTarget(entry: nil))
            } label: {
                Label("Dün geceki uykunu kaydet", systemImage: "moon.zzz.fill")
                    .font(.headline)
                    .foregroundStyle(Color.ftSleep)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func row(_ entry: SleepEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR"))))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text("\(entry.bedtime.formatted(date: .omitted, time: .shortened)) – \(entry.wakeTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Color.ftTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(SleepAnalyzer.durationText(hours: entry.durationHours))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white)
                StarRatingView(value: entry.quality, size: 10)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Kayıt düzenleyici
private struct SleepEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: SleepViewModel
    let entry: SleepEntry?

    @State private var wakeDay: Date
    @State private var bedtime: Date
    @State private var wakeTime: Date
    @State private var quality: Int
    @State private var saveError: String?

    init(viewModel: SleepViewModel, entry: SleepEntry?) {
        self.viewModel = viewModel
        self.entry = entry
        let calendar = Calendar.current
        if let entry {
            _wakeDay = State(initialValue: entry.day)
            _bedtime = State(initialValue: entry.bedtime)
            _wakeTime = State(initialValue: entry.wakeTime)
            _quality = State(initialValue: entry.quality)
        } else {
            let today = calendar.startOfDay(for: .now)
            let wakeMinutes = viewModel.settings.targetWakeMinutes
            let bedMinutes = viewModel.recommendedBedtimeMinutes
            _wakeDay = State(initialValue: today)
            _bedtime = State(initialValue: calendar.date(byAdding: .minute, value: bedMinutes, to: today) ?? .now)
            _wakeTime = State(initialValue: calendar.date(byAdding: .minute, value: wakeMinutes, to: today) ?? .now)
            _quality = State(initialValue: 3)
        }
    }

    private var resolved: (bedtime: Date, wakeTime: Date) {
        SleepViewModel.resolve(
            bedtimeMinutes: SleepAnalyzer.minutesOfDay(bedtime),
            wakeMinutes: SleepAnalyzer.minutesOfDay(wakeTime),
            wakeDay: wakeDay
        )
    }

    var body: some View {
        let times = resolved
        let hours = times.wakeTime.timeIntervalSince(times.bedtime) / 3600

        NavigationStack {
            Form {
                Section {
                    DatePicker("Uyanış günü", selection: $wakeDay, in: ...Date.now, displayedComponents: .date)
                    DatePicker("Yatış", selection: $bedtime, displayedComponents: .hourAndMinute)
                    DatePicker("Uyanış", selection: $wakeTime, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("Yatış saati uyanıştan sonraysa önceki geceye sayılır.")
                }

                Section("Süre") {
                    HStack {
                        Text(SleepAnalyzer.durationText(hours: hours))
                            .font(.title2.bold().monospacedDigit())
                        Spacer()
                        if !SleepAnalyzer.isValidDuration(hours) {
                            Label("Geçersiz", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.ftWarning)
                        }
                    }
                }

                Section("Uyku kalitesi") {
                    StarRatingView(rating: $quality)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }

                if let entry {
                    Section {
                        Button("Kaydı sil", role: .destructive) {
                            viewModel.delete(entry)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBackground)
            .navigationTitle(entry == nil ? "Uyku Ekle" : "Uykuyu Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        do {
                            try viewModel.save(bedtime: times.bedtime, wakeTime: times.wakeTime, quality: quality, editing: entry)
                            dismiss()
                        } catch {
                            saveError = AppError.map(error).errorDescription
                            Haptics.error()
                        }
                    }
                    .disabled(!SleepAnalyzer.isValidDuration(hours))
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
}

// MARK: - Ayarlar
private struct SleepSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: SleepViewModel
    let onGoalChange: (Double) -> Void

    @State private var draft: SleepSettings
    @State private var goal: Double
    @State private var wakeTime: Date
    @State private var permissionDenied = false
    @State private var isSaving = false

    init(viewModel: SleepViewModel, onGoalChange: @escaping (Double) -> Void) {
        self.viewModel = viewModel
        self.onGoalChange = onGoalChange
        _draft = State(initialValue: viewModel.settings)
        _goal = State(initialValue: viewModel.goalHours)
        let today = Calendar.current.startOfDay(for: .now)
        _wakeTime = State(initialValue: Calendar.current.date(byAdding: .minute, value: viewModel.settings.targetWakeMinutes, to: today) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hedef") {
                    Stepper(value: $goal, in: SleepViewModel.goalRange, step: 0.5) {
                        HStack {
                            Text("Günlük uyku")
                            Spacer()
                            Text(SleepAnalyzer.durationText(hours: goal)).monospacedDigit()
                        }
                    }
                    DatePicker("Hedef uyanış", selection: $wakeTime, displayedComponents: .hourAndMinute)
                }

                Section {
                    Toggle("Yatma hatırlatıcısı", isOn: $draft.reminderEnabled)
                    if draft.reminderEnabled {
                        Picker("Ne kadar önce", selection: $draft.reminderLeadMinutes) {
                            Text("Tam saatinde").tag(0)
                            Text("15 dk önce").tag(15)
                            Text("30 dk önce").tag(30)
                            Text("1 saat önce").tag(60)
                        }
                    }
                } footer: {
                    if permissionDenied {
                        Text("Bildirim izni kapalı. Ayarlar > FarvaTrack > Bildirimler'den açabilirsin.")
                            .foregroundStyle(Color.ftWarning)
                    } else {
                        Text("Önerilen yatış saatine göre her akşam hatırlatılır.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBackground)
            .navigationTitle("Uyku Ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        var settings = draft
        settings.targetWakeMinutes = SleepAnalyzer.minutesOfDay(wakeTime)
        if goal != viewModel.goalHours { onGoalChange(goal) }
        Task {
            let ok = await viewModel.applySettings(settings)
            isSaving = false
            if ok {
                Haptics.success()
                dismiss()
            } else {
                draft.reminderEnabled = false
                permissionDenied = true
            }
        }
    }
}
