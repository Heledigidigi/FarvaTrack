import SwiftUI

struct DashboardView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(LiveWorkoutViewModel.self) private var live
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DashboardViewModel()

    private let twoColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private let threeColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    /// Biyolojik atık ayrı bir küçük satırda, su ise halkada gösterildiği için modül kutularında yer almaz.
    private var visibleRoutes: [AppRoute] {
        AppRoute.allCases.filter { $0 != .biologicalWaste && $0 != .water }
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.dashboardPath) {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if let user = auth.currentUser {
                        DashboardTrainingRow(ownerID: user.id, isLive: live.isActive) {
                            router.selectedTab = .exercise
                        }
                    }
                    dailyRingsCard
                    statGrid
                    weeklyStepsCard
                    modulesSection
                    wasteRow
                }
                .redacted(reason: viewModel.hasLoaded ? [] : .placeholder)
                .padding(.horizontal, Constants.Layout.screenPadding)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.load() }
            .background(Color.ftBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRoute.self) { route in
                route.destination
            }
        }
        .onChange(of: auth.currentUser, initial: true) { _, user in
            guard let user else { return }
            viewModel.updateGoals(from: user)
            viewModel.configure(
                dataSource: LiveDashboardDataSource(
                    context: modelContext,
                    ownerID: user.id,
                    weightKg: user.weightKg,
                    heightCm: user.heightCm,
                    stepGoal: user.dailyStepGoal
                )
            )
            Task { await viewModel.load() }
        }
        .onChange(of: router.selectedTab) { _, tab in
            if tab == .dashboard { Task { await viewModel.load() } }
        }
        .alert("Veriler yüklenemedi", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Üst bölüm
    private var firstName: String {
        auth.currentUser?.displayName.split(separator: " ").first.map(String.init) ?? ""
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(
                    .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR"))
                ))
                .font(.subheadline)
                .foregroundStyle(Color.ftTextSecondary)

                Text(firstName.isEmpty ? viewModel.greeting : "\(viewModel.greeting), \(firstName)")
                    .font(.title.bold())
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                Haptics.impact(.light)
                router.select(.profile)
            } label: {
                AvatarView(name: auth.currentUser?.displayName ?? "", photoURL: auth.currentUser?.photoURL)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Profil")
        }
    }

    // MARK: - Günlük halkalar
    private var dailyRingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bugünün Özeti")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: 8) {
                ringMetric(
                    title: "Adım",
                    systemImage: "figure.walk",
                    value: viewModel.summary.steps.formatted(),
                    goalText: "/ \(viewModel.goals.steps.formatted())",
                    progress: viewModel.stepProgress,
                    color: Color.ftAccentLight
                ) { router.push(.steps) }

                ringMetric(
                    title: "Kalori",
                    systemImage: "flame.fill",
                    value: "\(viewModel.summary.caloriesConsumed.formatted()) kcal",
                    goalText: "/ \(viewModel.goals.calories.formatted())",
                    progress: viewModel.calorieProgress,
                    color: Color.ftCalories
                ) { router.select(.nutrition) }

                ringMetric(
                    title: "Su",
                    systemImage: "drop.fill",
                    value: "\(liters(viewModel.summary.waterMl)) L",
                    goalText: "/ \(liters(viewModel.goals.waterMl)) L",
                    progress: viewModel.waterProgress,
                    color: Color.ftWater
                ) { router.push(.water) }
            }
        }
        .cardStyle(padding: 20)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: viewModel.summary)
    }

    private func ringMetric(
        title: String,
        systemImage: String,
        value: String,
        goalText: String,
        progress: Double,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            VStack(spacing: 10) {
                ProgressRing(progress: progress, lineWidth: 10, color: color) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(color)
                }
                .frame(width: 84, height: 84)

                VStack(spacing: 2) {
                    Text(value)
                        .font(.subheadline.bold().monospacedDigit())
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(goalText)
                        .font(.caption2)
                        .foregroundStyle(Color.ftTextSecondary)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value), hedef \(goalText)")
        .accessibilityValue("yüzde \(Int(min(progress, 9.99) * 100))")
        .accessibilityHint("Ayrıntıları açmak için çift dokun")
    }

    private func liters(_ ml: Int) -> String {
        (Double(ml) / 1000).formatted(.number.precision(.fractionLength(1)))
    }

    // MARK: - İstatistik kartları
    private var weightSubtitle: String {
        var parts: [String] = []
        if let bmi = viewModel.bmi {
            parts.append("BMI \(bmi.formatted(.number.precision(.fractionLength(1))))")
        }
        if let target = viewModel.goals.targetWeightKg {
            parts.append("Hedef \(target.formatted(.number.precision(.fractionLength(0...1)))) kg")
        }
        return parts.joined(separator: " • ")
    }

    private var statGrid: some View {
        LazyVGrid(columns: twoColumns, spacing: 12) {
            NavigationLink(value: AppRoute.sleep) {
                StatCard(
                    title: "Uyku",
                    value: viewModel.summary.sleepHours
                        .map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                    unit: "saat",
                    systemImage: "moon.stars.fill",
                    tint: Color.ftSleep,
                    progress: viewModel.sleepProgress,
                    subtitle: "Hedef: \(viewModel.goals.sleepHours.formatted()) saat",
                    showsChevron: true
                )
            }

            NavigationLink(value: AppRoute.weight) {
                StatCard(
                    title: "Kilo",
                    value: viewModel.displayedWeightKg
                        .map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                    unit: "kg",
                    systemImage: "scalemass.fill",
                    tint: Color.ftWeight,
                    subtitle: weightSubtitle.isEmpty ? nil : weightSubtitle,
                    showsChevron: true
                )
            }

            Button {
                Haptics.impact(.light)
                router.select(.exercise)
            } label: {
                StatCard(
                    title: "Egzersiz",
                    value: "\(viewModel.summary.workoutMinutes)",
                    unit: "dk",
                    systemImage: "dumbbell.fill",
                    tint: Color.ftExercise,
                    subtitle: "Bugünkü antrenman süresi",
                    showsChevron: true
                )
            }

            NavigationLink(value: AppRoute.steps) {
                StatCard(
                    title: "Yakılan",
                    value: viewModel.summary.caloriesBurned.formatted(),
                    unit: "kcal",
                    systemImage: "flame.fill",
                    tint: Color.ftCalories,
                    subtitle: "\(viewModel.summary.distanceKm.formatted(.number.precision(.fractionLength(1)))) km yürüdün",
                    showsChevron: true
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Haftalık adım grafiği
    private var weeklyStepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bu Hafta · Adım")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink(value: AppRoute.statistics) {
                    Text("Tümü")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ftAccentLight)
                }
            }

            if viewModel.hasWeeklyStepData {
                ChartView(
                    data: viewModel.summary.weeklySteps,
                    goal: Double(viewModel.goals.steps),
                    tint: Color.ftAccentLight,
                    unit: "adım"
                )
                .frame(height: 170)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title)
                        .foregroundStyle(Color.ftTextSecondary.opacity(0.6))
                    Text("Henüz adım verisi yok. Adımların burada görünecek.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130)
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle(padding: 20)
    }

    // MARK: - Modüller
    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modüller")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: threeColumns, spacing: 12) {
                ForEach(visibleRoutes) { route in
                    NavigationLink(value: route) {
                        ModuleTile(route: route)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Biyolojik atık satırı
private extension DashboardView {
    var wasteRow: some View {
        NavigationLink(value: AppRoute.biologicalWaste) {
            HStack(spacing: 12) {
                Image(systemName: AppRoute.biologicalWaste.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(Color.ftWaste)
                    .frame(width: 32, height: 32)
                    .background(Color.ftWaste.opacity(0.18), in: Circle())
                Text(AppRoute.biologicalWaste.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("Bugün \(viewModel.summary.wasteCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.ftTextSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.ftTextSecondary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.ftCard, in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modül kutusu
private struct ModuleTile: View {
    let route: AppRoute

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: route.systemImage)
                .font(.title3)
                .foregroundStyle(route.tint)
                .frame(width: 44, height: 44)
                .background(route.tint.opacity(0.18), in: Circle())

            Text(route.title)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(.vertical, 8)
        .background(
            Color.ftCard,
            in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}
