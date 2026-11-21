import SwiftUI
import SwiftData

struct WaterTrackingView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(WaterViewModel.self) private var viewModel

    @State private var showCustomSheet = false
    @State private var showSettings = false

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let user = auth.currentUser {
                    WaterContent(
                        ownerID: user.id,
                        viewModel: viewModel,
                        onCustom: { showCustomSheet = true }
                    )
                } else {
                    ProgressView()
                }
            }
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle("Su")
            .onAppear { viewModel.reloadReminderSettings() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: viewModel.reminderSettings.isEnabled ? "bell.badge.fill" : "bell")
                    }
                    .accessibilityLabel("Su ayarları ve hatırlatıcılar")
                }
            }
            .sheet(isPresented: $showCustomSheet) {
                CustomAmountSheet { amount in
                    do {
                        try viewModel.add(amountMl: amount)
                        return true
                    } catch {
                        viewModel.errorMessage = AppError.map(error).errorDescription
                        return false
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                WaterSettingsSheet(viewModel: viewModel) { newGoal in
                    guard var user = auth.currentUser else { return }
                    user.dailyWaterGoalMl = newGoal
                    Task { await auth.updateUser(user) }
                }
            }
            .alert("Bir sorun oluştu", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

// MARK: - İçerik (@Query burada: son 7 gün)
private struct WaterContent: View {
    @Query private var entries: [WaterEntry]

    let viewModel: WaterViewModel
    let onCustom: () -> Void

    init(ownerID: String, viewModel: WaterViewModel, onCustom: @escaping () -> Void) {
        let since = Calendar.current.date(byAdding: .day, value: -6, to: Date.now.startOfDay) ?? .distantPast
        _entries = Query(
            filter: #Predicate<WaterEntry> { $0.ownerID == ownerID && $0.date >= since },
            sort: \.date,
            order: .reverse
        )
        self.viewModel = viewModel
        self.onCustom = onCustom
    }

    private var todayEntries: [WaterEntry] {
        entries.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        let total = todayEntries.reduce(0) { $0 + $1.amountMl }
        let goal = viewModel.goalMl
        let weekData = WaterViewModel.dailyTotals(entries: entries)

        List {
            Section {
                hero(total: total, goal: goal)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                quickAdd
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if total >= 4_000 && Double(total) >= Double(goal) * 1.5 {
                    Label("Bugün hedefinin çok üzerindesin. Susuzluk hissetmiyorsan ara verebilirsin.", systemImage: "info.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.ftWarning)
                        .listRowBackground(Color.ftCard)
                }
            }

            if weekData.contains(where: { $0.value > 0 }) {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Son 7 Gün").font(.headline)
                        ChartView(data: weekData, goal: Double(goal), tint: Color.ftWater, unit: "ml")
                            .frame(height: 170)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.ftCard)
                }
            }

            Section("Bugünkü Kayıtlar") {
                if todayEntries.isEmpty {
                    Text("Henüz su eklemedin.")
                        .foregroundStyle(Color.ftTextSecondary)
                        .listRowBackground(Color.ftCard)
                }
                ForEach(todayEntries) { entry in
                    HStack {
                        Label(entry.date.formatted(date: .omitted, time: .shortened), systemImage: "drop.fill")
                            .foregroundStyle(Color.ftWater)
                        Spacer()
                        Text("\(entry.amountMl) ml")
                            .font(.body.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
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
        .overlay(alignment: .bottom) { undoToast }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.undoToken)
        .sensoryFeedback(.success, trigger: total >= goal) { old, new in !old && new }
    }

    // MARK: Üst gösterge
    private func hero(total: Int, goal: Int) -> some View {
        let progress = goal > 0 ? Double(total) / Double(goal) : 0
        let percent = Int(min(progress, 9.99) * 100)

        return ZStack {
            Circle().fill(Color.ftCard)

            WaterWaveView(progress: progress)
                .clipShape(Circle())

            Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)

            VStack(spacing: 2) {
                Text(total.formatted())
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/ \(goal.formatted()) ml")
                    .font(.subheadline.weight(.medium))
                Text("%\(percent)")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 3)
        }
        .frame(width: 250, height: 250)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bugünkü su: \(total) mililitre, hedef \(goal) mililitre")
        .accessibilityValue("yüzde \(percent)")
    }

    // MARK: Hızlı ekleme
    private var quickAdd: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            quickButton(150, "Fincan", "cup.and.saucer.fill")
            quickButton(200, "Bardak", "drop.fill")
            quickButton(330, "Kutu", "takeoutbag.and.cup.and.straw.fill")
            quickButton(500, "Şişe", "waterbottle.fill")

            Button(action: onCustom) {
                VStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.title3)
                    Text("Özel").font(.subheadline.weight(.semibold))
                    Text("ml gir").font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 84)
                .background(Color.ftCard, in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func quickButton(_ ml: Int, _ title: String, _ systemImage: String) -> some View {
        Button {
            do {
                try viewModel.add(amountMl: ml)
            } catch {
                viewModel.errorMessage = AppError.map(error).errorDescription
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.ftWater)
                Text("+\(ml) ml").font(.subheadline.weight(.semibold).monospacedDigit())
                Text(title).font(.caption).foregroundStyle(Color.ftTextSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Color.ftCard, in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(ml) mililitre ekle")
    }

    // MARK: Geri al
    @ViewBuilder
    private var undoToast: some View {
        if let token = viewModel.undoToken {
            HStack(spacing: 14) {
                Text("+\(token.amountMl) ml eklendi")
                    .font(.subheadline.weight(.medium))
                Button("Geri al") { viewModel.undo() }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.ftAccentLight)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.ftCardElevated, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Özel miktar
private struct CustomAmountSheet: View {
    /// Başarılıysa `true` döner ve sayfa kapanır.
    let onAdd: (Int) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var amount = 250

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $amount, in: WaterViewModel.customRange, step: 50) {
                        Text("\(amount) ml")
                            .font(.title2.bold().monospacedDigit())
                    }
                } footer: {
                    Text("Tek seferde en fazla \(WaterViewModel.customRange.upperBound.formatted()) ml eklenebilir.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle("Özel Miktar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        if onAdd(amount) { dismiss() }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Ayarlar ve hatırlatıcılar
private struct WaterSettingsSheet: View {
    let viewModel: WaterViewModel
    let onGoalSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: WaterReminderSettings
    @State private var goal: Int
    @State private var showDeniedNote = false

    init(viewModel: WaterViewModel, onGoalSave: @escaping (Int) -> Void) {
        self.viewModel = viewModel
        self.onGoalSave = onGoalSave
        _draft = State(initialValue: viewModel.reminderSettings)
        _goal = State(initialValue: viewModel.goalMl)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goal, in: WaterViewModel.goalRange, step: 100) {
                        Text("\(goal.formatted()) ml")
                            .font(.title3.bold().monospacedDigit())
                    }
                } header: {
                    Text("Günlük hedef")
                } footer: {
                    Text("Başlangıç hedefin kilona ve aktivite düzeyine göre hesaplandı. Doktorun özel bir sıvı miktarı önerdiyse ona uy.")
                }

                Section {
                    Toggle("Hatırlatıcılar", isOn: $draft.isEnabled)

                    if draft.isEnabled {
                        Picker("Sıklık", selection: $draft.intervalMinutes) {
                            Text("1 saatte bir").tag(60)
                            Text("1,5 saatte bir").tag(90)
                            Text("2 saatte bir").tag(120)
                            Text("3 saatte bir").tag(180)
                        }
                        Picker("Başlangıç", selection: $draft.startHour) {
                            ForEach(5...12, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                        Picker("Bitiş", selection: $draft.endHour) {
                            ForEach(18...23, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                    }
                } header: {
                    Text("Hatırlatıcılar")
                } footer: {
                    Text("Bildirimler yalnızca seçtiğin saatler arasında gelir; uyku saatlerinde sessiz kalır.")
                }

                if showDeniedNote {
                    Section {
                        Text("Bildirim izni kapalı. Hatırlatıcı için iPhone Ayarları → FarvaTrack → Bildirimler bölümünden izin ver.")
                            .font(.footnote)
                            .foregroundStyle(Color.ftWarning)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Ayarları Aç", destination: url)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle("Su Ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") {
                        if goal != viewModel.goalMl { onGoalSave(goal) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: draft) { _, new in
                Task {
                    let ok = await viewModel.applyReminders(new)
                    if !ok {
                        draft.isEnabled = false
                        showDeniedNote = new.isEnabled
                    } else {
                        showDeniedNote = false
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
