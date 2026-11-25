import SwiftUI

struct StepsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = StepsViewModel()
    @State private var showGoalSheet = false
    @State private var showManualSheet = false

    private var periodBinding: Binding<StepPeriod> {
        Binding(
            get: { viewModel.period },
            set: { newValue in
                Haptics.selection()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    viewModel.period = newValue
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    var body: some View {
        Group {
            if viewModel.access == .loading {
                ProgressView()
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ftScreenBackground()
        .navigationTitle("Adımlar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showManualSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Adımı elle gir")
            }
        }
        .sheet(isPresented: $showManualSheet) {
            ManualStepSheet(viewModel: viewModel)
        }
        .task {
            if let user = auth.currentUser { viewModel.attach(context: modelContext, userID: user.id) }
            await viewModel.start()
            await viewModel.syncManual()
        }
        .onChange(of: auth.currentUser, initial: true) { _, user in
            if let user { viewModel.configure(user: user) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await viewModel.start() }   // gün değişimi veya izin sonrası dönüş
            case .background: viewModel.stop()
            default: break
            }
        }
        .onDisappear { viewModel.stop() }
        .sensoryFeedback(.success, trigger: viewModel.isTodayGoalReached) { old, new in !old && new }
        .sheet(isPresented: $showGoalSheet) {
            StepGoalSheet(current: viewModel.dailyGoal) { newGoal in
                guard var user = auth.currentUser else { return }
                user.dailyStepGoal = newGoal
                Task { await auth.updateUser(user) }
            }
        }
        .alert("Bir sorun oluştu", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Sağlık durumu kartı
    @ViewBuilder
    private var healthBanner: some View {
        switch viewModel.access {
        case .needsPermission:
            banner(
                icon: "heart.text.square.fill",
                title: "Adımlarını otomatik takip edelim",
                text: "FarvaTrack; adım, yürüme mesafesi ve aktif enerji verilerini Apple Sağlık'tan okur. Veriler yalnızca cihazında gösterilir. İstersen adımlarını elle de girebilirsin."
            ) {
                Button("Sağlık'a Bağlan") { Task { await viewModel.requestAccess() } }
                    .buttonStyle(PrimaryButtonStyle())
            }
        case .unavailable:
            banner(icon: "heart.slash", title: "Apple Sağlık kullanılamıyor", text: "Bu cihazda Apple Sağlık desteklenmiyor. Adımlarını sağ üstteki kalem simgesiyle elle girebilirsin.") {
                EmptyView()
            }
        case .ready, .loading:
            if let issue = viewModel.healthIssue {
                banner(icon: "exclamationmark.triangle.fill", title: "Sağlık verisi okunamadı", text: issue) {
                    Button("Bugünün adımını gir") { showManualSheet = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ftAccentLight)
                }
            }
        }
    }

    private func banner<Actions: View>(icon: String, title: String, text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Color.ftAccentLight)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.ftTextSecondary)
            actions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 20)
    }

    // MARK: - Ana içerik
    private var content: some View {
        let stats = viewModel.stats(for: viewModel.period)

        return ScrollView {
            VStack(spacing: 20) {
                Picker("Dönem", selection: periodBinding) {
                    ForEach(StepPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                healthBanner
                hero(stats)
                metrics(stats)
                chartCard

                if viewModel.showsNoDataHint { noDataHint }

                goalCard

                if let last = viewModel.lastUpdated {
                    Text("Son güncelleme: \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                }
            }
            .padding(Constants.Layout.screenPadding)
        }
        .scrollIndicators(.hidden)
    }

    private func hero(_ stats: StepPeriodStats) -> some View {
        let reached = stats.progress >= 1

        return VStack(spacing: 16) {
            ProgressRing(progress: stats.progress, lineWidth: 18, color: Color.ftAccentLight) {
                VStack(spacing: 4) {
                    Image(systemName: reached ? "checkmark.seal.fill" : "figure.walk")
                        .font(.title2)
                        .foregroundStyle(reached ? Color.ftSuccess : Color.ftAccentLight)
                    Text(stats.steps.formatted())
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("/ \(stats.goal.formatted()) adım")
                        .font(.footnote)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                .padding(.horizontal, 28)
            }
            .frame(width: 230, height: 230)

            Text(reached ? "Hedefe ulaştın, harika iş!" : "Hedefe \(stats.remaining.formatted()) adım kaldı")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(reached ? Color.ftSuccess : Color.ftTextSecondary)

            if viewModel.period == .day && viewModel.isTodayManual {
                Label("Elle girildi", systemImage: "square.and.pencil")
                    .font(.caption)
                    .foregroundStyle(Color.ftTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(viewModel.period.scopeTitle) adım: \(stats.steps), hedef \(stats.goal)")
        .accessibilityValue("yüzde \(Int(min(stats.progress, 9.99) * 100))")
    }

    private func metrics(_ stats: StepPeriodStats) -> some View {
        HStack(spacing: 12) {
            MetricTile(
                title: "Mesafe",
                value: stats.distanceKm.formatted(.number.precision(.fractionLength(1))),
                unit: "km",
                systemImage: "map.fill",
                tint: Color.ftWater
            )
            MetricTile(
                title: "Kalori",
                value: stats.calories.formatted(),
                unit: stats.caloriesAreEstimated ? "kcal • tahmini" : "kcal",
                systemImage: "flame.fill",
                tint: Color.ftCalories
            )
            if viewModel.period == .day {
                MetricTile(
                    title: "Kalan",
                    value: stats.remaining.formatted(),
                    unit: "adım",
                    systemImage: "flag.fill",
                    tint: Color.ftSuccess
                )
            } else {
                MetricTile(
                    title: "Ortalama",
                    value: stats.dailyAverage.formatted(),
                    unit: "adım/gün",
                    systemImage: "chart.bar.fill",
                    tint: Color.ftSleep
                )
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.period.chartTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ChartView(
                data: viewModel.chartData(for: viewModel.period),
                goal: Double(viewModel.dailyGoal),
                tint: Color.ftAccentLight,
                unit: "adım",
                xAxisStyle: viewModel.period == .month ? .dayOfMonth : .weekday
            )
            .frame(height: 200)
        }
        .cardStyle(padding: 20)
    }

    private var noDataHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Veri görünmüyor mu?", systemImage: "info.circle.fill")
                .font(.headline)
            Text("İzin verdiysen ve hâlâ sıfır görüyorsan Sağlık uygulamasında Paylaşım → Uygulamalar → FarvaTrack bölümünden adım iznini kontrol et. Telefonun yanında taşınmadığı günlerde de veri olmayabilir.")
                .font(.footnote)
                .foregroundStyle(Color.ftTextSecondary)
            if let url = URL(string: "x-apple-health://") {
                Link("Sağlık Uygulamasını Aç", destination: url)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ftAccentLight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 20)
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hedeflerin").font(.headline)
                Spacer()
                Button("Düzenle") { showGoalSheet = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ftAccentLight)
            }
            goalRow("Günlük", viewModel.goal(for: .day))
            goalRow("Haftalık", viewModel.goal(for: .week))
            goalRow("Aylık", viewModel.goal(for: .month))
        }
        .cardStyle(padding: 20)
    }

    private func goalRow(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.ftTextSecondary)
            Spacer()
            Text("\(value.formatted()) adım").font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Küçük bileşenler
private struct MetricTile: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Color.ftTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

private struct StepGoalSheet: View {
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var goal: Int

    init(current: Int, onSave: @escaping (Int) -> Void) {
        _goal = State(initialValue: current)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goal, in: 1_000...50_000, step: 500) {
                        Text("\(goal.formatted()) adım")
                            .font(.title3.bold().monospacedDigit())
                    }
                } header: {
                    Text("Günlük hedef")
                } footer: {
                    Text("Haftalık hedef: \((goal * 7).formatted()) adım. Aylık hedef, ayın gün sayısına göre hesaplanır.")
                }
            }
            .scrollContentBackground(.hidden)
            .ftScreenBackground()
            .navigationTitle("Adım Hedefi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        onSave(goal)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Elle adım girişi
private struct ManualStepSheet: View {
    let viewModel: StepsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var day = Date.now
    @State private var steps: Int?
    @State private var error: String?

    private var existing: Int? { viewModel.manualValue(for: day) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Gün", selection: $day, in: ...Date.now, displayedComponents: .date)
                    HStack {
                        TextField("Adım sayısı", value: $steps, format: .number)
                            .keyboardType(.numberPad)
                            .font(.title2.bold().monospacedDigit())
                            .accessibilityLabel("Adım sayısı")
                        Text("adım").foregroundStyle(Color.ftTextSecondary)
                    }
                } footer: {
                    Text("Telefonundaki Sağlık uygulamasında veya saatinde gördüğün sayıyı yazabilirsin. Elle girilen değer o günün Sağlık verisinin yerine geçer.")
                }

                if existing != nil {
                    Section {
                        Button("Elle girilen değeri sil", role: .destructive) {
                            viewModel.deleteManual(for: day)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .ftScreenBackground()
            .navigationTitle("Adımı Elle Gir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        do {
                            try viewModel.saveManual(steps: steps ?? 0, for: day)
                            dismiss()
                        } catch {
                            self.error = AppError.map(error).errorDescription
                            Haptics.error()
                        }
                    }
                    .disabled(steps == nil)
                }
            }
            .alert("Kaydedilemedi", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .onAppear { steps = existing }
            .onChange(of: day) { _, _ in steps = existing }
        }
        .presentationDetents([.medium])
    }
}
