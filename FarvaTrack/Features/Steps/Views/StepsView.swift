import SwiftUI

struct StepsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel = StepsViewModel()
    @State private var showGoalSheet = false

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
            switch viewModel.access {
            case .loading:
                ProgressView()
            case .unavailable:
                ContentUnavailableView(
                    "Sağlık verisi kullanılamıyor",
                    systemImage: "heart.slash",
                    description: Text("Bu cihazda Apple Sağlık desteklenmiyor.")
                )
            case .needsPermission:
                permissionView
            case .ready:
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Adımlar")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.start() }
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

    // MARK: - İzin ekranı
    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.ftAccentLight)
                .accessibilityHidden(true)

            Text("Adımlarını takip edelim")
                .font(.title2.bold())

            Text("FarvaTrack; adım, yürüme mesafesi ve aktif enerji verilerini Apple Sağlık'tan okur. Veriler yalnızca cihazında gösterilir. İzni istediğin zaman Sağlık uygulamasından değiştirebilirsin.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ftTextSecondary)

            Button {
                Task { await viewModel.requestAccess() }
            } label: {
                Text("Sağlık'a Bağlan")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Constants.Layout.screenPadding)
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
            .background(Color.ftBackground.ignoresSafeArea())
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
