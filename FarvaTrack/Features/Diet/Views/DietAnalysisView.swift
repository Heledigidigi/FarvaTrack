import SwiftUI

/// Öğün / gün / hafta / program bazında plan ve yenen; yiyeceklerin makrolara katkısı.
struct DietAnalysisView: View {
    @Environment(DietStore.self) private var store
    let program: DietProgram

    enum Scope: String, CaseIterable, Identifiable {
        case meal, day, week, program
        var id: String { rawValue }
        var title: String {
            switch self {
            case .meal: return "Öğün"
            case .day: return "Gün"
            case .week: return "Hafta"
            case .program: return "Program"
            }
        }
    }

    @State private var scope: Scope = .day
    @State private var date = Date.now
    @State private var macro: MacroKind = .protein
    @State private var mealID: String?

    private var range: (Date, Date) {
        let today = Calendar.current.startOfDay(for: date)
        switch scope {
        case .meal, .day: return (today, today)
        case .week: return (Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today, today)
        case .program:
            let end = min(Calendar.current.startOfDay(for: .now), program.endDate ?? .now)
            return (program.startDate, max(program.startDate, end))
        }
    }

    private var summary: DietRangeSummary { store.summary(for: program, from: range.0, to: range.1) }

    var body: some View {
        let summary = self.summary
        VStack(spacing: 12) {
            Picker("Kapsam", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if scope != .program {
                DietDayNavigator(date: date, subtitle: scope == .week ? "\(DietFormat.shortDate(range.0)) – \(DietFormat.shortDate(range.1))" : program.programDay(on: date).map { "Gün \($0)" },
                                 canGoForward: !Calendar.current.isDateInToday(date)) { offset in
                    date = Calendar.current.date(byAdding: .day, value: scope == .week ? offset * 7 : offset, to: date) ?? date
                }
            }

            if scope == .meal {
                mealAnalysis(summary)
            } else {
                planVsEaten(summary)
                if scope == .day, let day = summary.days.first { mealShares(day) }
                if scope != .day { adherence(summary) }
                contributions(summary)
                if scope != .day { highlights(summary) }
            }
        }
    }

    // MARK: Plan ve yenen

    private func planVsEaten(_ summary: DietRangeSummary) -> some View {
        let eaten = scope == .day ? (summary.days.first?.eaten ?? .zero) : summary.averageEaten
        let planned = scope == .day ? (summary.days.first?.planned ?? .zero) : summary.averagePlanned
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(scope == .day ? "Plan ve yenen" : "Günlük ortalama").font(.headline).foregroundStyle(Color.ftText)
                Spacer()
                Text("\(DietFormat.kcal(eaten.calories)) / \(DietFormat.kcal(planned.calories)) kcal").font(.subheadline.bold()).foregroundStyle(Color.ftCalories)
            }
            ForEach(MacroKind.allCases) { kind in
                let value = eaten.grams(of: kind)
                let target = planned.grams(of: kind)
                HStack {
                    Text(kind.title).font(.caption.weight(.semibold)).foregroundStyle(kind.color).frame(width: 92, alignment: .leading)
                    ProgressView(value: target > 0 ? min(1, value / target) : 0).tint(kind.color)
                    Text("\(Int(value.rounded())) / \(Int(target.rounded())) g").font(.caption.monospacedDigit()).frame(width: 82, alignment: .trailing)
                }
            }
            Text("Dağılım: \(eaten.shareText) (plan \(planned.shareText))").font(.caption).foregroundStyle(Color.ftTextSecondary)
        }
        .cardStyle(padding: 14)
    }

    private func mealShares(_ day: DietDaySummary) -> some View {
        let total = max(1, day.eaten.calories)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Öğünlere göre").font(.headline).foregroundStyle(Color.ftText)
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(Array(day.meals.enumerated()), id: \.offset) { index, snapshot in
                        Rectangle()
                            .fill(Color.ftCalories.opacity(0.35 + 0.65 * Double(index % 3) / 2))
                            .frame(width: geometry.size.width * snapshot.eatenNutrition.calories / total)
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                ForEach(day.meals) { snapshot in
                    Text("\(snapshot.meal.name) \(snapshot.eatenNutrition.kcal) kcal · %\(Int((snapshot.eatenNutrition.calories / total * 100).rounded()))")
                        .font(.caption).foregroundStyle(Color.ftText)
                }
                if !day.extras.isEmpty {
                    Text("Ekstra \(DietFormat.kcal(day.extras.reduce(0) { $0 + $1.nutrition.calories })) kcal").font(.caption).foregroundStyle(Color.ftExercise)
                }
            }
        }
        .cardStyle(padding: 14)
    }

    // MARK: Öğün

    @ViewBuilder
    private func mealAnalysis(_ summary: DietRangeSummary) -> some View {
        if let day = summary.days.first, !day.meals.isEmpty {
            let selected = day.meals.first { $0.meal.id == mealID } ?? day.meals.first!
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(day.meals) { snapshot in
                        Button(snapshot.meal.name) { mealID = snapshot.meal.id }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(selected.id == snapshot.id ? Color.white : Color.ftText)
                            .background(selected.id == snapshot.id ? Color.ftAccent : Color.ftSubtle(0.12), in: Capsule())
                    }
                }
            }
            let eaten = selected.eatenNutrition
            let planned = selected.plannedNutrition
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(selected.meal.name) · \(selected.meal.timeText)").font(.headline)
                    Spacer()
                    DietStatusChip(status: selected.status, missed: selected.isMissed)
                }
                Text("Yenen \(eaten.kcal) kcal · \(eaten.macroText)").font(.subheadline)
                Text("Plan \(planned.kcal) kcal · \(planned.macroText)").font(.caption).foregroundStyle(Color.ftTextSecondary)
                let difference = eaten.calories - planned.calories
                if selected.status != nil {
                    Text("Fark: \(difference >= 0 ? "+" : "")\(Int(difference.rounded())) kcal").font(.caption.weight(.semibold))
                        .foregroundStyle(abs(difference) < 50 ? Color.ftSuccess : Color.ftWarning)
                }
                Divider()
                ForEach(Array((selected.log?.eaten ?? selected.meal.portions).enumerated()), id: \.offset) { _, portion in
                    HStack {
                        Text(portion.label).font(.caption)
                        Spacer()
                        Text("\(portion.nutrition.kcal) kcal · P \(Int(portion.nutrition.protein.rounded())) K \(Int(portion.nutrition.carbs.rounded())) Y \(Int(portion.nutrition.fat.rounded()))")
                            .font(.caption2.monospacedDigit()).foregroundStyle(Color.ftTextSecondary)
                    }
                }
            }
            .cardStyle(padding: 14)
        } else {
            Text("Bu gün programın dışında.").foregroundStyle(Color.ftTextSecondary)
        }
    }

    // MARK: Katkılar

    private func contributions(_ summary: DietRangeSummary) -> some View {
        let days = summary.pastDays
        let items = DietAnalysis.contributions(of: macro, in: days)
        let total = items.reduce(0) { $0 + $1.grams }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(macro.title) nereden geldi?").font(.headline).foregroundStyle(Color.ftText)
                Spacer()
                Picker("Makro", selection: $macro) {
                    ForEach(MacroKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Color.ftAccentLight)
            }
            if items.isEmpty {
                Text("Henüz yenen öğün yok.").font(.caption).foregroundStyle(Color.ftTextSecondary)
            }
            ForEach(items.prefix(8)) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.name).font(.subheadline)
                        if !item.mealName.isEmpty { Text("· \(item.mealName)").font(.caption).foregroundStyle(Color.ftTextSecondary) }
                        Spacer()
                        Text("\(DietFormat.number(item.grams)) g").font(.caption.monospacedDigit())
                        Text("%\(Int((item.share * 100).rounded()))").font(.caption.bold().monospacedDigit()).frame(width: 40, alignment: .trailing)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(macro.color).frame(width: geometry.size.width * item.share)
                    }
                    .frame(height: 5)
                    .background(macro.color.opacity(0.15), in: Capsule())
                }
                .accessibilityElement(children: .combine)
            }
            if items.count > 8 {
                Text("+ \(items.count - 8) yiyecek daha · toplam \(DietFormat.number(total)) g").font(.caption).foregroundStyle(Color.ftTextSecondary)
            }
        }
        .cardStyle(padding: 14)
    }

    // MARK: Uyum

    private func adherence(_ summary: DietRangeSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uyum").font(.headline).foregroundStyle(Color.ftText)
                    Text("\(summary.followed) / \(summary.judged) öğün · \(summary.changed) değişim · \(summary.skipped) atlanan · \(summary.missed) işaretlenmedi")
                        .font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
                Spacer()
                Text(summary.adherencePercent.map { "%\($0)" } ?? "—").font(.title.bold()).foregroundStyle(Color.ftSuccess)
            }
            ForEach(summary.mealStats) { stats in
                HStack {
                    Text(stats.name).font(.caption).frame(width: 80, alignment: .leading)
                    Text("✓ \(stats.eaten)").foregroundStyle(Color.ftSuccess)
                    Text("↺ \(stats.changed)").foregroundStyle(Color.ftWarning)
                    Text("✕ \(stats.skipped)").foregroundStyle(Color.ftDanger)
                    if stats.missed > 0 { Text("? \(stats.missed)").foregroundStyle(Color.ftTextSecondary) }
                    Spacer()
                }
                .font(.caption.monospacedDigit())
            }
        }
        .cardStyle(padding: 14)
    }

    private func highlights(_ summary: DietRangeSummary) -> some View {
        let swaps = summary.frequentSwaps.prefix(3)
        let extras = summary.frequentExtras.prefix(3)
        let tags = summary.tagCounts.prefix(4)
        let weight = DietAnalysis.weightChange(program.metrics)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Öne çıkanlar").font(.headline).foregroundStyle(Color.ftText)
            if !swaps.isEmpty {
                Text("Sık değişimler: " + swaps.map { "\($0.text) \($0.count)×" }.joined(separator: ", ")).font(.caption)
            }
            if !extras.isEmpty {
                Text("Ekstralar: " + extras.map { "\($0.text) \($0.count)×" }.joined(separator: ", ")).font(.caption)
            }
            if !tags.isEmpty {
                Text("Notlarda: " + tags.map { "\($0.tag) \($0.count)" }.joined(separator: " · ")).font(.caption)
            }
            if let weight {
                Text("Kilo: \(DietFormat.number(weight.first)) → \(DietFormat.number(weight.last)) kg").font(.caption)
            }
            if swaps.isEmpty && extras.isEmpty && tags.isEmpty && weight == nil {
                Text("Kayıt arttıkça burada özetlenecek.").font(.caption).foregroundStyle(Color.ftTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
    }
}
