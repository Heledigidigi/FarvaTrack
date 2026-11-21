import SwiftUI

struct OnboardingView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var step = 0
    @State private var gender: Gender?
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var heightCm: Double = 170
    @State private var weightKg: Double = 70
    @State private var goal: FitnessGoal = .maintain
    @State private var targetWeightKg: Double = 70
    @State private var activity: ActivityLevel = .moderate
    @State private var isSaving = false

    @Namespace private var selectionNamespace

    private let lastStep = 4

    private var birthDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let oldest = calendar.date(byAdding: .year, value: -Constants.Validation.maxAge, to: .now) ?? .distantPast
        let youngest = calendar.date(byAdding: .year, value: -Constants.Validation.minAge, to: .now) ?? .now
        return oldest...youngest
    }

    private var isMinor: Bool { birthDate.yearsSinceNow < 18 }

    /// 18 yaş altında kilo verme hedefi sunulmaz.
    private var availableGoals: [FitnessGoal] {
        FitnessGoal.allCases.filter { $0 != .loseWeight || !isMinor }
    }

    private var canContinue: Bool {
        step != 1 || gender != nil
    }

    private var recommendation: CalorieCalculator.Recommendation? {
        guard let gender else { return nil }
        return CalorieCalculator.recommendation(
            weightKg: weightKg,
            heightCm: heightCm,
            age: birthDate.yearsSinceNow,
            gender: gender,
            activity: activity,
            goal: goal
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            ZStack {
                switch step {
                case 0: welcomeStep
                case 1: bodyStep
                case 2: goalStep
                case 3: activityStep
                default: summaryStep
                }
            }
            .id(step)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .background(Color.ftBackground.ignoresSafeArea())
        .authAlerts()
        .onChange(of: isMinor) { _, minor in
            if minor, goal == .loseWeight { goal = .maintain }
        }
    }

    // MARK: - Üst ilerleme çubuğu
    private var progressHeader: some View {
        HStack(spacing: 6) {
            ForEach(0...lastStep, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.ftAccentLight : Color.ftCardElevated)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, Constants.Layout.screenPadding)
        .padding(.top, 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Adım \(step + 1) / \(lastStep + 1)")
    }

    // MARK: - Alt butonlar
    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: Constants.Layout.fieldHeight, height: Constants.Layout.fieldHeight)
                        .background(
                            Color.ftCard,
                            in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
                        )
                }
                .accessibilityLabel("Geri")
            }

            Button {
                goNext()
            } label: {
                Text(step == lastStep ? "Başla" : "Devam")
            }
            .buttonStyle(PrimaryButtonStyle(isLoading: isSaving))
            .disabled(!canContinue || isSaving)
        }
        .padding(.horizontal, Constants.Layout.screenPadding)
        .padding(.vertical, 16)
    }

    // MARK: - Adımlar
    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            AppLogo(size: 110)
            Text("Hoş geldin\(firstNameSuffix)!")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Sana özel hedefler belirlemek için birkaç soru soracağız. Bu bilgiler günlük kalori, su, adım ve uyku hedeflerini hesaplamak için kullanılır.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ftTextSecondary)
                .padding(.horizontal, Constants.Layout.screenPadding)
            Spacer()
            Spacer()
        }
    }

    private var bodyStep: some View {
        stepContainer(title: "Seni tanıyalım", subtitle: "Hesaplamalar bu bilgilere göre yapılır.") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cinsiyet").font(.headline)
                HStack(spacing: 10) {
                    ForEach(Gender.allCases) { option in
                        genderChip(option)
                    }
                }
            }

            DatePicker(
                "Doğum tarihi",
                selection: $birthDate,
                in: birthDateRange,
                displayedComponents: .date
            )
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .font(.headline)
            .cardStyle()

            valueSlider(title: "Boy", value: $heightCm, range: 120...220, step: 1, unit: "cm")
            valueSlider(title: "Kilo", value: $weightKg, range: 30...200, step: 0.5, unit: "kg")
        }
    }

    private var goalStep: some View {
        stepContainer(title: "Hedefin ne?", subtitle: "Hedefine göre kalori ve adım önerisi hazırlarız.") {
            VStack(spacing: 12) {
                ForEach(availableGoals) { option in
                    OptionCard(
                        title: option.title,
                        subtitle: option.subtitle,
                        systemImage: option.systemImage,
                        isSelected: goal == option,
                        namespace: selectionNamespace,
                        matchID: "goalSelection"
                    ) {
                        select(goal: option)
                    }
                }
            }

            if goal == .loseWeight || goal == .gainMuscle {
                valueSlider(title: "Hedef kilo", value: $targetWeightKg, range: 30...200, step: 0.5, unit: "kg")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: goal)
    }

    private var activityStep: some View {
        stepContainer(title: "Ne kadar aktifsin?", subtitle: "Haftalık ortalama hareket düzeyini seç.") {
            VStack(spacing: 12) {
                ForEach(ActivityLevel.allCases) { option in
                    OptionCard(
                        title: option.title,
                        subtitle: option.subtitle,
                        systemImage: option.systemImage,
                        isSelected: activity == option,
                        namespace: selectionNamespace,
                        matchID: "activitySelection"
                    ) {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            activity = option
                        }
                    }
                }
            }
        }
    }

    private var summaryStep: some View {
        stepContainer(title: "Hedeflerin hazır 🎯", subtitle: "Bunları daha sonra Profil bölümünden değiştirebilirsin.") {
            if let rec = recommendation {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SummaryTile(systemImage: "flame.fill", title: "Kalori", value: "\(rec.calorieGoal)", unit: "kcal/gün")
                    SummaryTile(systemImage: "drop.fill", title: "Su", value: "\(rec.waterGoalMl)", unit: "ml/gün")
                    SummaryTile(systemImage: "figure.walk", title: "Adım", value: rec.stepGoal.formatted(), unit: "adım/gün")
                    SummaryTile(systemImage: "moon.stars.fill", title: "Uyku", value: rec.sleepHours.formatted(), unit: "saat/gece")
                }

                Text("Bazal metabolizma hızın yaklaşık \(rec.bmr) kcal, günlük toplam enerji harcaman ise yaklaşık \(rec.tdee) kcal. Bu değerler genel tahminlerdir.")
                    .font(.footnote)
                    .foregroundStyle(Color.ftTextSecondary)
            }
        }
    }

    // MARK: - Yardımcı görünümler
    private func stepContainer<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                content()
            }
            .padding(.horizontal, Constants.Layout.screenPadding)
            .padding(.vertical, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func genderChip(_ option: Gender) -> some View {
        let isSelected = gender == option
        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { gender = option }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: option.systemImage).font(.title2)
                Text(option.title).font(.footnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(isSelected ? Color.white : Color.ftTextSecondary)
            .background(
                isSelected ? Color.ftAccent : Color.ftCard,
                in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func valueSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        let text = "\(format(value.wrappedValue, step: step)) \(unit)"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(text)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.ftAccentLight)
            }
            Slider(value: value, in: range, step: step)
                .tint(Color.ftAccentLight)
                .accessibilityLabel(title)
                .accessibilityValue(text)
        }
        .cardStyle()
    }

    private func format(_ value: Double, step: Double) -> String {
        value.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0)))
    }

    private var firstNameSuffix: String {
        guard let first = auth.currentUser?.displayName
            .split(separator: " ").first, !first.isEmpty else { return "" }
        return " \(first)"
    }

    // MARK: - Aksiyonlar
    private func select(goal option: FitnessGoal) {
        Haptics.selection()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            goal = option
            switch option {
            case .loseWeight: targetWeightKg = max(30, weightKg - 5)
            case .gainMuscle: targetWeightKg = min(200, weightKg + 3)
            default: targetWeightKg = weightKg
            }
        }
    }

    private func goBack() {
        Haptics.impact(.light)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            step = max(0, step - 1)
        }
    }

    private func goNext() {
        Haptics.impact(.light)
        if step < lastStep {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += 1 }
        } else {
            Task { await finish() }
        }
    }

    private func finish() async {
        if isMinor, goal == .loseWeight { goal = .maintain }
        guard let gender, var user = auth.currentUser, let rec = recommendation else { return }
        isSaving = true
        defer { isSaving = false }

        user.gender = gender
        user.birthDate = birthDate
        user.heightCm = heightCm
        user.weightKg = weightKg
        user.goal = goal
        user.targetWeightKg = (goal == .loseWeight || goal == .gainMuscle) ? targetWeightKg : weightKg
        user.startWeightKg = weightKg
        user.activityLevel = activity
        user.dailyCalorieGoal = rec.calorieGoal
        user.dailyWaterGoalMl = rec.waterGoalMl
        user.dailyStepGoal = rec.stepGoal
        user.sleepGoalHours = rec.sleepHours

        await auth.completeOnboarding(user)
    }
}

// MARK: - Seçilebilir kart (matchedGeometryEffect ile kayan seçim)
private struct OptionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let matchID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.ftAccentLight)
                    .frame(width: 42, height: 42)
                    .background(Color.ftAccent.opacity(0.25), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.ftAccentLight : Color.ftTextSecondary)
            }
            .padding(14)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
                        .fill(Color.ftCard)
                    if isSelected {
                        RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
                            .fill(Color.ftAccent.opacity(0.30))
                            .overlay(
                                RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
                                    .stroke(Color.ftAccentLight, lineWidth: 1.5)
                            )
                            .matchedGeometryEffect(id: matchID, in: namespace)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SummaryTile: View {
    let systemImage: String
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.ftAccentLight)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.ftTextSecondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
