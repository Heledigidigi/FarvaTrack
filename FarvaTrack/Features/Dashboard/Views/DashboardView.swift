import SwiftUI

struct DashboardView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(LiveWorkoutViewModel.self) private var live
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DashboardViewModel()

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    /// Su halkada gösterildiği için modül kutularında yer almaz.
    private var visibleRoutes: [AppRoute] {
        AppRoute.allCases.filter { $0 != .water }
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.dashboardPath) {
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if let user = auth.currentUser {
                            DashboardTrainingRow(ownerID: user.id, isLive: live.isActive) {
                                router.selectedTab = .exercise
                            }
                            .padding(.top, 4)
                        }
                        dailyRingsCard
                            .padding(.top, 26)
                        statGrid
                            .padding(.top, 12)
                        weeklyStepsCard
                            .padding(.top, -14)
                        modulesSection
                            .padding(.top, 6)
                    }
                    .redacted(reason: viewModel.hasLoaded ? [] : .placeholder)
                    .padding(.horizontal, Constants.Layout.screenPadding)
                    .padding(.top, geo.safeAreaInsets.top + 8)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 34)
                }
                .scrollIndicators(.hidden)
                .refreshable { await viewModel.load() }
                .mask(kenarErimesi(ust: geo.safeAreaInsets.top, alt: geo.safeAreaInsets.bottom))
                .ignoresSafeArea(edges: .vertical)
            }
            .ftScreenBackground()
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

    // MARK: - Kaydırma kenarları
    /// Kaydırırken içerik üstte saat bölgesinde, altta sekme çubuğunun hemen üstünde yumuşakça erir;
    /// zemin olduğu gibi kalır.
    private func kenarErimesi(ust: CGFloat, alt: CGFloat) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: max(0, (ust - 3) / (ust + 23))),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: ust + 23)
            Color.black
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .clear, location: 22 / (alt + 21)),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: alt + 21)
        }
        .ignoresSafeArea()
    }

    // MARK: - Üst bölüm
    private var firstName: String {
        auth.currentUser?.displayName.split(separator: " ").first.map(String.init) ?? ""
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(
                    .dateTime.day().month(.wide).weekday(.wide).locale(Locale(identifier: "tr_TR"))
                ))
                .font(.system(size: 15))
                .foregroundStyle(Color.ftTextSecondary)

                Text(firstName.isEmpty ? viewModel.greeting : "\(viewModel.greeting), \(firstName)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.ftText)
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
                madalyon
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profil")
        }
    }

    /// Profil fotoğrafı için oval madalyon çerçeve.
    private var madalyon: some View {
        ZStack {
            Ellipse().fill(Color(hex: "#EADBBB"))
                .frame(width: 50, height: 62)
            AvatarView(name: auth.currentUser?.displayName ?? "", photoURL: auth.currentUser?.photoURL)
                .frame(width: 40, height: 52)
                .clipShape(Ellipse())
            Ellipse().stroke(Color(hex: "#7A5C3C"), lineWidth: 0.9)
                .frame(width: 50, height: 62)
            Ellipse().stroke(Color(hex: "#7A5C3C"), lineWidth: 0.5)
                .frame(width: 41, height: 53)
        }
        .murekkepGolgesi()
    }

    // MARK: - Günlük halkalar (fırça halkası)
    private var dailyRingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bugünün Özeti")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ftText)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: 0) {
                ringMetric(title: "Adım", value: viewModel.summary.steps.formatted(),
                           goalText: "/ \(viewModel.goals.steps.formatted())",
                           progress: viewModel.stepProgress, color: OzetRenk.adim, seed: 1) { router.push(.steps) }
                ringMetric(title: "Kalori", value: viewModel.summary.caloriesConsumed.formatted(),
                           goalText: "/ \(viewModel.goals.calories.formatted()) kcal",
                           progress: viewModel.calorieProgress, color: OzetRenk.kalori, seed: 4) { router.select(.nutrition) }
                ringMetric(title: "Su", value: "\(liters(viewModel.summary.waterMl)) L",
                           goalText: "/ \(liters(viewModel.goals.waterMl)) L",
                           progress: viewModel.waterProgress, color: OzetRenk.su, seed: 7) { router.push(.water) }
            }
        }
        .animation(.spring(response: 0.8, dampingFraction: 0.85), value: viewModel.summary)
    }

    private func ringMetric(
        title: String,
        value: String,
        goalText: String,
        progress: Double,
        color: Color,
        seed: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(OzetRenk.soluk.opacity(0.22), lineWidth: 0.5)
                        .padding(4)
                    FircaHalka(ilerleme: progress, tohum: seed)
                        .fill(color.opacity(0.8))
                        .blur(radius: 0.3)
                        .murekkepGolgesi(hafif: true)
                    VStack(spacing: 1) {
                        Text(value)
                            .font(.system(size: 17, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.ftText)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(goalText)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.ftTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 8)
                }
                .frame(width: 80, height: 80)

                Text(title.uppercased(with: Locale(identifier: "tr_TR")))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
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

    // MARK: - Uyku ve Kilo
    private var weightSubtitle: String {
        var parts: [String] = []
        if let bmi = viewModel.bmi {
            parts.append("BMI \(bmi.formatted(.number.precision(.fractionLength(1))))")
        }
        if let target = viewModel.goals.targetWeightKg {
            parts.append("Hedef \(target.formatted(.number.precision(.fractionLength(0...1))))")
        }
        return parts.joined(separator: " · ")
    }

    private var statGrid: some View {
        HStack(spacing: 12) {
            NavigationLink(value: AppRoute.sleep) {
                ZStack(alignment: .topLeading) {
                    BulutluHilal().murekkepGolgesi()
                    uykuMetni.offset(x: 11.8, y: 80.6)
                }
                .frame(width: 136, height: 155, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            NavigationLink(value: AppRoute.weight) {
                ZStack(alignment: .topLeading) {
                    SuzulenTuy().murekkepGolgesi()
                    kiloMetni.offset(x: 11.8, y: 80.6)
                }
                .frame(width: 136, height: 155, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    private func buyukDeger(_ sayi: String, _ birim: String) -> Text {
        Text(sayi).font(.system(size: 14.5, weight: .bold)) + Text(birim).font(.system(size: 8.5))
    }

    private var uykuMetni: some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text("Uyku")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(OzetRenk.uykuBaslik)
            Group {
                if let uyku = OzetBicim.uykuParcalari(viewModel.summary.sleepHours) {
                    buyukDeger("\(uyku.saat)", " sa ") + buyukDeger("\(uyku.dakika)", " dk")
                } else {
                    Text("—").font(.system(size: 14.5, weight: .bold))
                }
            }
            .foregroundStyle(Color.ftText)
            Text("hedef \(viewModel.goals.sleepHours.formatted()) saat")
                .font(.system(size: 9))
                .foregroundStyle(Color.ftTextSecondary)
        }
        .fixedSize()
    }

    private var kiloMetni: some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text("Kilo")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(OzetRenk.kiloBaslik)
            Group {
                if let kg = viewModel.displayedWeightKg {
                    buyukDeger(kg.formatted(.number.precision(.fractionLength(1))), " kg")
                } else {
                    Text("—").font(.system(size: 14.5, weight: .bold))
                }
            }
            .foregroundStyle(Color.ftText)
            if !weightSubtitle.isEmpty {
                Text(weightSubtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.ftTextSecondary)
            }
        }
        .fixedSize()
    }

    // MARK: - Haftalık adım: büyüyen çiçekler
    private var weeklyStepsCard: some View {
        ZStack(alignment: .top) {
            BuyuyenCicekler(gunler: viewModel.summary.weeklySteps, hedef: Double(viewModel.goals.steps))
                .padding(.horizontal, -1)
            HStack(alignment: .firstTextBaseline) {
                Text("Bu Hafta · Adım")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ftText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink(value: AppRoute.statistics) {
                    Text("Tümü")
                        .font(.system(size: 13))
                        .foregroundStyle(OzetRenk.tumu)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Modüller (tek sıra şerit)
    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Modüller")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ftText)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                ForEach(Array(visibleRoutes.enumerated()), id: \.element) { index, route in
                    if index > 0 { Spacer(minLength: 0) }
                    NavigationLink(value: route) {
                        OzetModulOgesi(route: route)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
