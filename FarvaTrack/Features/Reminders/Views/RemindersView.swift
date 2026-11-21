import SwiftUI
import UserNotifications

/// Tüm hatırlatıcıları tek yerden yönetir. Ayarlar ilgili modüllerin ViewModel'leriyle aynı depoyu kullanır.
struct RemindersView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(WaterViewModel.self) private var water
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var sleep = SleepViewModel()
    @State private var metrics = BodyMetricsViewModel()
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var showDenied = false

    private static let weekdays: [(name: String, value: Int)] = [
        ("Pazartesi", 2), ("Salı", 3), ("Çarşamba", 4), ("Perşembe", 5),
        ("Cuma", 6), ("Cumartesi", 7), ("Pazar", 1)
    ]

    var body: some View {
        List {
            if status == .denied {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Bildirim izni kapalı", systemImage: "bell.slash.fill")
                            .font(.headline)
                            .foregroundStyle(Color.ftWarning)
                        Text("Hatırlatıcıların çalışması için iPhone ayarlarından FarvaTrack bildirimlerini açman gerekiyor.")
                            .font(.subheadline)
                            .foregroundStyle(Color.ftTextSecondary)
                        Button("Ayarları Aç") { openSettings() }
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.ftCard)
                }
            }

            waterSection
            sleepSection
            weighInSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Hatırlatıcılar")
        .alert("Bildirim izni gerekli", isPresented: $showDenied) {
            Button("Ayarları Aç") { openSettings() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Hatırlatıcıyı açmak için bildirimlere izin vermelisin.")
        }
        .task(id: auth.currentUser?.id) {
            if let user = auth.currentUser {
                sleep.configure(context: modelContext, user: user)
                metrics.configure(context: modelContext, user: user)
            }
            water.reloadReminderSettings()
            await refreshStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
        }
    }

    // MARK: - Su
    private var waterSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { water.reminderSettings.isEnabled },
                set: { enabled in update(water: { $0.isEnabled = enabled }) }
            )) {
                Label("Su hatırlatıcısı", systemImage: "drop.fill").foregroundStyle(Color.ftWater)
            }

            if water.reminderSettings.isEnabled {
                Picker("Sıklık", selection: Binding(
                    get: { water.reminderSettings.intervalMinutes },
                    set: { value in update(water: { $0.intervalMinutes = value }) }
                )) {
                    Text("Saatte bir").tag(60)
                    Text("1,5 saatte bir").tag(90)
                    Text("2 saatte bir").tag(120)
                    Text("3 saatte bir").tag(180)
                }
                Stepper(value: Binding(
                    get: { water.reminderSettings.startHour },
                    set: { value in update(water: { $0.startHour = min(value, $0.endHour - 1) }) }
                ), in: 5...20) {
                    row("Başlangıç", String(format: "%02d:00", water.reminderSettings.startHour))
                }
                Stepper(value: Binding(
                    get: { water.reminderSettings.endHour },
                    set: { value in update(water: { $0.endHour = max(value, $0.startHour + 1) }) }
                ), in: 9...23) {
                    row("Bitiş", String(format: "%02d:00", water.reminderSettings.endHour))
                }
            }
        } header: {
            Text("Su")
        }
        .listRowBackground(Color.ftCard)
    }

    // MARK: - Uyku
    private var sleepSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { sleep.settings.reminderEnabled },
                set: { enabled in update(sleep: { $0.reminderEnabled = enabled }) }
            )) {
                Label("Yatma hatırlatıcısı", systemImage: "moon.stars.fill").foregroundStyle(Color.ftSleep)
            }

            if sleep.settings.reminderEnabled {
                Picker("Ne kadar önce", selection: Binding(
                    get: { sleep.settings.reminderLeadMinutes },
                    set: { value in update(sleep: { $0.reminderLeadMinutes = value }) }
                )) {
                    Text("Tam saatinde").tag(0)
                    Text("15 dk önce").tag(15)
                    Text("30 dk önce").tag(30)
                    Text("1 saat önce").tag(60)
                }
            }
            NavigationLink {
                SleepView()
            } label: {
                row("Önerilen yatış", SleepAnalyzer.timeText(minutes: sleep.recommendedBedtimeMinutes))
            }
        } header: {
            Text("Uyku")
        } footer: {
            Text("Uyanış saatini ve uyku hedefini Uyku ekranındaki ayarlardan değiştirebilirsin.")
        }
        .listRowBackground(Color.ftCard)
    }

    // MARK: - Tartı
    private var weighInSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { metrics.reminderSettings.isEnabled },
                set: { enabled in update(weighIn: { $0.isEnabled = enabled }) }
            )) {
                Label("Haftalık tartı", systemImage: "scalemass.fill").foregroundStyle(Color.ftWeight)
            }

            if metrics.reminderSettings.isEnabled {
                Picker("Gün", selection: Binding(
                    get: { metrics.reminderSettings.weekday },
                    set: { value in update(weighIn: { $0.weekday = value }) }
                )) {
                    ForEach(Self.weekdays, id: \.value) { Text($0.name).tag($0.value) }
                }
                DatePicker("Saat", selection: Binding(
                    get: {
                        Calendar.current.date(
                            bySettingHour: metrics.reminderSettings.hour,
                            minute: metrics.reminderSettings.minute, second: 0, of: .now
                        ) ?? .now
                    },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        update(weighIn: {
                            $0.hour = parts.hour ?? 8
                            $0.minute = parts.minute ?? 0
                        })
                    }
                ), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Kilo")
        }
        .listRowBackground(Color.ftCard)
    }

    // MARK: - Yardımcılar
    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(Color.ftTextSecondary)
        }
    }

    private func update(water change: (inout WaterReminderSettings) -> Void) {
        var settings = water.reminderSettings
        change(&settings)
        Task { await finish(await water.applyReminders(settings), enabled: settings.isEnabled) }
    }

    private func update(sleep change: (inout SleepSettings) -> Void) {
        var settings = sleep.settings
        change(&settings)
        Task { await finish(await sleep.applySettings(settings), enabled: settings.reminderEnabled) }
    }

    private func update(weighIn change: (inout WeighInReminderSettings) -> Void) {
        var settings = metrics.reminderSettings
        change(&settings)
        Task { await finish(await metrics.applyReminder(settings), enabled: settings.isEnabled) }
    }

    private func finish(_ ok: Bool, enabled: Bool) async {
        await refreshStatus()
        if ok {
            Haptics.selection()
        } else if enabled {
            showDenied = true
        }
    }

    private func refreshStatus() async {
        status = await NotificationManager.shared.authorizationStatus()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
