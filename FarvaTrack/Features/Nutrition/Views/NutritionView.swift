import SwiftUI
import SwiftData
import Charts

struct AddMealTarget: Identifiable {
    let mealType: MealType
    var id: String { mealType.rawValue }
}

struct NutritionView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = NutritionViewModel()
    @State private var addTarget: AddMealTarget?
    @State private var editingEntry: MealEntry?

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayNavigator(
                    date: viewModel.selectedDate,
                    canGoForward: viewModel.canGoForward,
                    onShift: { viewModel.shiftDay(by: $0) }
                )

                if let user = auth.currentUser {
                    NutritionDayContent(
                        ownerID: user.id,
                        day: viewModel.selectedDate,
                        viewModel: viewModel,
                        onAdd: { addTarget = AddMealTarget(mealType: $0) },
                        onEdit: { editingEntry = $0 }
                    )
                } else {
                    ProgressView().frame(maxHeight: .infinity)
                }
            }
            .ftScreenBackground()
            .navigationTitle("Beslenme")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.impact(.light)
                        addTarget = AddMealTarget(mealType: .suggested())
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Yiyecek ekle")
                }
            }
            .sheet(item: $addTarget) { target in
                AddMealView(viewModel: viewModel, initialMealType: target.mealType)
            }
            .sheet(item: $editingEntry) { entry in
                EditMealSheet(entry: entry, viewModel: viewModel)
            }
            .alert("Bir sorun oluştu", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
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

// MARK: - Gün gezgini
private struct DayNavigator: View {
    let date: Date
    let canGoForward: Bool
    let onShift: (Int) -> Void

    private var title: String {
        if Calendar.current.isDateInToday(date) { return "Bugün" }
        if Calendar.current.isDateInYesterday(date) { return "Dün" }
        return date.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(Locale(identifier: "tr_TR")))
    }

    var body: some View {
        HStack {
            Button { onShift(-1) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Önceki gün")

            Spacer()
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()

            Button { onShift(1) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Sonraki gün")
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Seçili günün içeriği (@Query burada)
private struct NutritionDayContent: View {
    @Query private var entries: [MealEntry]

    let viewModel: NutritionViewModel
    let onAdd: (MealType) -> Void
    let onEdit: (MealEntry) -> Void

    init(
        ownerID: String,
        day: Date,
        viewModel: NutritionViewModel,
        onAdd: @escaping (MealType) -> Void,
        onEdit: @escaping (MealEntry) -> Void
    ) {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(
            filter: #Predicate<MealEntry> { $0.ownerID == ownerID && $0.date >= start && $0.date < end },
            sort: \.date
        )
        self.viewModel = viewModel
        self.onAdd = onAdd
        self.onEdit = onEdit
    }

    var body: some View {
        let totals = NutritionTotals(entries: entries)

        List {
            Section {
                SummaryCard(totals: totals, goal: viewModel.calorieGoal, targets: viewModel.macroTargets)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                MacroPieCard(totals: totals)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(MealType.allCases) { type in
                mealSection(type)
            }

            Section {
                Text("Besin değerleri yaklaşık ortalamalardır; marka ve tarife göre değişebilir. Hedefler genel önerilerdir, kişisel beslenme planı yerine geçmez.")
                    .font(.caption)
                    .foregroundStyle(Color.ftTextSecondary)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func mealSection(_ type: MealType) -> some View {
        let items = entries.filter { $0.mealType == type }
        let kcal = Int(items.reduce(0) { $0 + $1.calories }.rounded())

        Section {
            if items.isEmpty {
                Button { onAdd(type) } label: {
                    Label("Yiyecek ekle", systemImage: "plus")
                        .foregroundStyle(Color.ftTextSecondary)
                }
                .listRowBackground(Color.ftCard)
            }
            ForEach(items) { entry in
                Button { onEdit(entry) } label: {
                    MealRow(entry: entry)
                }
                .listRowBackground(Color.ftCard)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.delete(entry)
                    } label: {
                        Label("Sil", systemImage: "trash")
                    }
                }
            }
        } header: {
            HStack {
                Label(type.title, systemImage: type.systemImage)
                    .foregroundStyle(type.tint)
                Spacer()
                Text("\(kcal) kcal")
                    .foregroundStyle(Color.ftTextSecondary)
                    .monospacedDigit()
                Button { onAdd(type) } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(type.tint)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(type.title) için yiyecek ekle")
            }
            .font(.headline)
            .textCase(nil)
        }
    }
}

// MARK: - Satır
private struct MealRow: View {
    let entry: MealEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text("\(entry.quantity.formatted(.number.precision(.fractionLength(0...2)))) × \(entry.servingLabel)")
                    .font(.caption)
                    .foregroundStyle(Color.ftTextSecondary)
                    .lineLimit(1)
                Text("P \(Int(entry.protein.rounded())) g · K \(Int(entry.carbs.rounded())) g · Y \(Int(entry.fat.rounded())) g")
                    .font(.caption2)
                    .foregroundStyle(Color.ftTextSecondary)
            }
            Spacer()
            Text("\(Int(entry.calories.rounded())) kcal")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Düzenlemek için çift dokun")
    }
}

// MARK: - Özet kartı
private struct SummaryCard: View {
    let totals: NutritionTotals
    let goal: Int
    let targets: CalorieCalculator.MacroTargets

    private var remaining: Int { goal - Int(totals.calories.rounded()) }

    private func target(for kind: MacroKind) -> Int {
        switch kind {
        case .protein: return targets.proteinG
        case .carbs: return targets.carbsG
        case .fat: return targets.fatG
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            ProgressRing(progress: totals.calories / Double(max(goal, 1)), lineWidth: 14, color: Color.ftCalories) {
                VStack(spacing: 0) {
                    Text(Int(totals.calories.rounded()).formatted())
                        .font(.title2.bold().monospacedDigit())
                        .contentTransition(.numericText())
                    Text("/ \(goal.formatted())")
                        .font(.caption2)
                        .foregroundStyle(Color.ftTextSecondary)
                }
            }
            .frame(width: 124, height: 124)

            VStack(alignment: .leading, spacing: 10) {
                Text(remaining >= 0 ? "\(remaining.formatted()) kcal kaldı" : "\(abs(remaining).formatted()) kcal hedefin üzerinde")
                    .font(.subheadline.weight(.semibold))

                ForEach(MacroKind.allCases) { kind in
                    macroBar(kind)
                }
            }
        }
        .cardStyle(padding: 18)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: totals)
        .accessibilityElement(children: .combine)
    }

    private func macroBar(_ kind: MacroKind) -> some View {
        let grams = totals.grams(of: kind)
        let goalGrams = max(target(for: kind), 1)
        let progress = min(grams / Double(goalGrams), 1)

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(kind.title).font(.caption)
                Spacer()
                Text("\(Int(grams.rounded())) / \(goalGrams) g")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.ftTextSecondary)
            }
            Capsule()
                .fill(Color.ftSubtle(0.08))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule().fill(kind.color).frame(width: geometry.size.width * progress)
                    }
                }
        }
    }
}

// MARK: - Pasta grafik
private struct MacroPieCard: View {
    let totals: NutritionTotals

    private struct Slice: Identifiable {
        let kind: MacroKind
        let energy: Double
        var id: MacroKind { kind }
    }

    private var slices: [Slice] {
        MacroKind.allCases.map { Slice(kind: $0, energy: totals.grams(of: $0) * $0.kcalPerGram) }
    }

    private func percent(_ slice: Slice) -> Int {
        guard totals.macroEnergy > 0 else { return 0 }
        return Int((slice.energy / totals.macroEnergy * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Makro Dağılımı")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if totals.macroEnergy > 0 {
                HStack(spacing: 20) {
                    ZStack {
                        Chart(slices) { slice in
                            SectorMark(
                                angle: .value("Enerji", slice.energy),
                                innerRadius: .ratio(0.62),
                                angularInset: 2
                            )
                            .cornerRadius(5)
                            .foregroundStyle(slice.kind.color)
                        }
                        .chartLegend(.hidden)

                        VStack(spacing: 0) {
                            Text(Int(totals.calories.rounded()).formatted())
                                .font(.headline.monospacedDigit())
                            Text("kcal").font(.caption2).foregroundStyle(Color.ftTextSecondary)
                        }
                    }
                    .frame(width: 130, height: 130)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(slices) { slice in
                            HStack(spacing: 8) {
                                Circle().fill(slice.kind.color).frame(width: 10, height: 10)
                                Text(slice.kind.title).font(.subheadline)
                                Spacer()
                                Text("\(Int(totals.grams(of: slice.kind).rounded())) g • %\(percent(slice))")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(Color.ftTextSecondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } else {
                HStack(spacing: 16) {
                    Circle()
                        .stroke(Color.ftSubtle(0.08), lineWidth: 16)
                        .frame(width: 80, height: 80)
                    Text("Henüz kayıt yok. Yiyecek ekledikçe protein, karbonhidrat ve yağ dağılımın burada görünür.")
                        .font(.footnote)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle(padding: 18)
        .animation(.easeInOut(duration: 0.4), value: totals)
    }
}

// MARK: - Düzenleme sayfası
private struct EditMealSheet: View {
    let entry: MealEntry
    let viewModel: NutritionViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FoodDetailView(
                template: entry.template,
                viewModel: viewModel,
                quantity: entry.quantity,
                mealType: entry.mealType,
                submitTitle: "Kaydet",
                showsMealPicker: true,
                onDelete: deleteAndClose,
                onSubmit: { quantity, mealType in
                    try viewModel.updateMeal(entry, quantity: quantity, mealType: mealType)
                    dismiss()
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    /// Önce sayfayı kapatır, silmeyi kapanış animasyonundan sonra yapar (silinmiş SwiftData nesnesine erişim çökertebilir).
    private func deleteAndClose() {
        let target = entry
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            viewModel.delete(target)
        }
    }
}
