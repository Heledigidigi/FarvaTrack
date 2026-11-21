import SwiftUI
import SwiftData

struct AddMealView: View {
    let viewModel: NutritionViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var mealType: MealType
    @State private var searchText = ""

    init(viewModel: NutritionViewModel, initialMealType: MealType) {
        self.viewModel = viewModel
        _mealType = State(initialValue: initialMealType)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Öğün", selection: $mealType) {
                    ForEach(MealType.allCases) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Constants.Layout.screenPadding)
                .padding(.vertical, 8)

                if let ownerID = viewModel.currentUserID {
                    FoodPickerList(
                        ownerID: ownerID,
                        searchText: searchText,
                        mealType: mealType,
                        viewModel: viewModel,
                        onAdded: { dismiss() }
                    )
                } else {
                    ProgressView().frame(maxHeight: .infinity)
                }
            }
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle("Yiyecek Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Yiyecek ara")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Liste
private struct FoodPickerList: View {
    @Query private var favorites: [FavoriteFood]
    @Query private var customFoods: [CustomFood]
    @Query private var recentEntries: [MealEntry]

    let searchText: String
    let mealType: MealType
    let viewModel: NutritionViewModel
    let onAdded: () -> Void

    init(
        ownerID: String,
        searchText: String,
        mealType: MealType,
        viewModel: NutritionViewModel,
        onAdded: @escaping () -> Void
    ) {
        _favorites = Query(filter: #Predicate<FavoriteFood> { $0.ownerID == ownerID }, sort: \.name)
        _customFoods = Query(filter: #Predicate<CustomFood> { $0.ownerID == ownerID }, sort: \.name)

        var descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        _recentEntries = Query(descriptor)

        self.searchText = searchText
        self.mealType = mealType
        self.viewModel = viewModel
        self.onAdded = onAdded
    }

    private var recentTemplates: [FoodTemplate] {
        var seen = Set<String>()
        let unique = recentEntries.compactMap { seen.insert($0.foodKey).inserted ? $0.template : nil }
        return Array(unique.prefix(8))
    }

    var body: some View {
        let query = searchText.trimmed

        List {
            if query.isEmpty {
                if !favorites.isEmpty {
                    Section("Favoriler") { rows(favorites.map(\.template)) }
                }
                if !recentTemplates.isEmpty {
                    Section("Son Kullanılanlar") { rows(recentTemplates) }
                }
                Section {
                    NavigationLink {
                        CreateFoodView(viewModel: viewModel)
                    } label: {
                        Label("Kendi yiyeceğini oluştur", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.ftAccentLight)
                    }
                    .listRowBackground(Color.ftCard)
                }
                if !customFoods.isEmpty {
                    Section("Özel Yiyeceklerim") {
                        ForEach(customFoods) { food in
                            row(food.template)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        viewModel.deleteCustomFood(food)
                                    } label: {
                                        Label("Sil", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                Section("Tüm Yiyecekler") { rows(FoodLibrary.all) }
            } else {
                let results = (customFoods.map(\.template) + FoodLibrary.all)
                    .filter { $0.name.localizedCaseInsensitiveContains(query) }
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                } else {
                    Section { rows(results) }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func rows(_ templates: [FoodTemplate]) -> some View {
        ForEach(templates) { template in
            row(template)
        }
    }

    private func row(_ template: FoodTemplate) -> some View {
        NavigationLink {
            FoodDetailView(
                template: template,
                viewModel: viewModel,
                quantity: 1,
                mealType: mealType,
                submitTitle: "Ekle",
                showsMealPicker: false,
                onDelete: nil,
                onSubmit: { quantity, type in
                    try viewModel.addMeal(
                        template: template, quantity: quantity, mealType: type, day: viewModel.selectedDate
                    )
                    onAdded()
                }
            )
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name).font(.body)
                    Text(template.servingLabel)
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                Spacer()
                Text("\(Int(template.calories.rounded())) kcal")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.ftTextSecondary)
            }
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.ftCard)
    }
}

// MARK: - Yiyecek detayı (ekleme ve düzenleme için ortak)
struct FoodDetailView: View {
    let template: FoodTemplate
    let viewModel: NutritionViewModel
    let submitTitle: String
    let showsMealPicker: Bool
    var onDelete: (() -> Void)?
    let onSubmit: (Double, MealType) throws -> Void

    @State private var quantity: Double
    @State private var mealType: MealType
    @State private var errorMessage: String?

    private static let quickAmounts: [Double] = [0.5, 1, 1.5, 2]

    init(
        template: FoodTemplate,
        viewModel: NutritionViewModel,
        quantity: Double,
        mealType: MealType,
        submitTitle: String,
        showsMealPicker: Bool,
        onDelete: (() -> Void)?,
        onSubmit: @escaping (Double, MealType) throws -> Void
    ) {
        self.template = template
        self.viewModel = viewModel
        self.submitTitle = submitTitle
        self.showsMealPicker = showsMealPicker
        self.onDelete = onDelete
        self.onSubmit = onSubmit
        _quantity = State(initialValue: quantity)
        _mealType = State(initialValue: mealType)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var quantityText: String {
        quantity.formatted(.number.precision(.fractionLength(0...2)))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name).font(.title2.bold())
                    Text("1 porsiyon = \(template.servingLabel)")
                        .font(.subheadline)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                quantityCard
                nutritionCard

                if showsMealPicker {
                    HStack {
                        Text("Öğün").font(.headline)
                        Spacer()
                        Picker("Öğün", selection: $mealType) {
                            ForEach(MealType.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    .cardStyle()
                }

                Button {
                    submit()
                } label: {
                    Text("\(submitTitle) · \(Int((template.calories * quantity).rounded())) kcal")
                }
                .buttonStyle(PrimaryButtonStyle())

                if let onDelete {
                    Button("Kaydı Sil", role: .destructive, action: onDelete)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(Constants.Layout.screenPadding)
        }
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let ownerID = viewModel.currentUserID {
                    FavoriteButton(template: template, ownerID: ownerID, viewModel: viewModel)
                }
            }
        }
        .alert("Kaydedilemedi", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var quantityCard: some View {
        VStack(spacing: 12) {
            Stepper(value: $quantity, in: 0.25...20, step: 0.25) {
                HStack {
                    Text("Miktar").font(.headline)
                    Spacer()
                    Text("\(quantityText) porsiyon")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.ftAccentLight)
                }
            }
            .accessibilityValue("\(quantityText) porsiyon")

            HStack(spacing: 8) {
                ForEach(Self.quickAmounts, id: \.self) { value in
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { quantity = value }
                    } label: {
                        Text(value.formatted(.number.precision(.fractionLength(0...1))))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                quantity == value ? Color.ftAccent : Color.ftCardElevated,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
    }

    private var nutritionCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Int((template.calories * quantity).rounded()).formatted())
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("kcal").foregroundStyle(Color.ftTextSecondary)
            }
            HStack {
                ForEach(MacroKind.allCases) { kind in
                    VStack(spacing: 4) {
                        Text("\((template.grams(of: kind) * quantity).formatted(.number.precision(.fractionLength(0...1)))) g")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(kind.color)
                        Text(kind.title).font(.caption).foregroundStyle(Color.ftTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 18)
        .animation(.easeInOut(duration: 0.2), value: quantity)
    }

    private func submit() {
        do {
            try onSubmit(quantity, mealType)
        } catch {
            errorMessage = AppError.map(error).errorDescription
            Haptics.error()
        }
    }
}

private struct FavoriteButton: View {
    @Query private var matches: [FavoriteFood]
    let template: FoodTemplate
    let viewModel: NutritionViewModel

    init(template: FoodTemplate, ownerID: String, viewModel: NutritionViewModel) {
        let key = "\(ownerID)|\(template.key)"
        _matches = Query(filter: #Predicate<FavoriteFood> { $0.compositeKey == key })
        self.template = template
        self.viewModel = viewModel
    }

    var body: some View {
        Button {
            viewModel.toggleFavorite(template)
        } label: {
            Image(systemName: matches.isEmpty ? "star" : "star.fill")
                .foregroundStyle(Color.ftStats)
        }
        .accessibilityLabel(matches.isEmpty ? "Favorilere ekle" : "Favorilerden çıkar")
    }
}

// MARK: - Kendi yiyeceğini oluştur
struct CreateFoodView: View {
    let viewModel: NutritionViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var servingLabel = "1 porsiyon"
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var errorMessage: String?

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var canSave: Bool {
        name.trimmed.count >= 2 && (calories != nil || protein != nil || carbs != nil || fat != nil)
    }

    var body: some View {
        Form {
            Section("Yiyecek") {
                TextField("Ad", text: $name)
                    .textInputAutocapitalization(.sentences)
                TextField("Porsiyon (örn. 1 dilim, 100 g)", text: $servingLabel)
            }

            Section {
                numberRow("Kalori (kcal)", value: $calories)
                numberRow("Protein (g)", value: $protein)
                numberRow("Karbonhidrat (g)", value: $carbs)
                numberRow("Yağ (g)", value: $fat)
            } header: {
                Text("1 porsiyondaki değerler")
            } footer: {
                Text("Kalori boş bırakılırsa makrolardan hesaplanır (protein ve karbonhidrat 4, yağ 9 kcal/g). Değerleri paket etiketindeki porsiyona göre gir.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Yeni Yiyecek")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Bitti") { hideKeyboard() }
            }
        }
        .alert("Kaydedilemedi", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func numberRow(_ title: String, value: Binding<Double?>) -> some View {
        LabeledContent(title) {
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        let p = protein ?? 0, c = carbs ?? 0, f = fat ?? 0
        let kcal = calories ?? (p * 4 + c * 4 + f * 9)
        do {
            try viewModel.createCustomFood(
                name: name, servingLabel: servingLabel,
                calories: kcal, protein: p, carbs: c, fat: f
            )
            dismiss()
        } catch {
            errorMessage = AppError.map(error).errorDescription
            Haptics.error()
        }
    }
}
