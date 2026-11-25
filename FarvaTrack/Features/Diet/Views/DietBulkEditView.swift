import SwiftUI

/// Toplu düzenleme: günü kopyala, yiyeceği değiştir, porsiyonu ayarla. Uygulamadan önce önizleme gösterilir.
struct DietBulkEditView: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let programID: String
    /// Düzenleyiciden açıldıysa değişiklik oradaki taslağa uygulanır; yoksa programa yeni sürüm olarak kaydedilir.
    var workingPlan: Binding<DietPlan>?

    enum Operation: String, CaseIterable, Identifiable {
        case copy, replace, portion
        var id: String { rawValue }
        var title: String {
            switch self {
            case .copy: return "Günü kopyala"
            case .replace: return "Yiyeceği değiştir"
            case .portion: return "Porsiyonu ayarla"
            }
        }
    }

    enum AmountMode: String, CaseIterable, Identifiable {
        case equal, same, manual
        var id: String { rawValue }
    }

    enum ScopeMode: String, CaseIterable, Identifiable {
        case all, future, selected
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Tüm günler"
            case .future: return "Bugünden sonra"
            case .selected: return "Takvimden seç"
            }
        }
    }

    @State private var operation: Operation = .replace
    @State private var findKey: String?
    @State private var replacement: DietFood?
    @State private var amountMode: AmountMode = .equal
    @State private var manualAmount: Double = 1
    @State private var manualUnit: DietUnit = .serving
    @State private var scopeMode: ScopeMode = .future
    @State private var selectedDays: Set<Int> = []
    @State private var mealFilter: Set<String> = []
    @State private var sourceDay = 0
    @State private var delta: Double = -1
    @State private var pickingReplacement = false
    @State private var undoPlan: DietPlan?

    private var program: DietProgram? { store.program(id: programID) }
    private var basePlan: DietPlan { workingPlan?.wrappedValue ?? program?.latestPlan ?? DietPlan() }
    private var todayIndex: Int { max(0, (program?.programDay(on: .now) ?? 1) - 1) }

    private var scope: DietBulkScope {
        var scope = DietBulkScope()
        switch scopeMode {
        case .all: scope.days = .all
        case .future: scope.days = .from(program?.dayOffset(of: .now) ?? 0 < 0 ? 0 : todayIndex + 1)
        case .selected: scope.days = .selected(selectedDays)
        }
        scope.mealNames = Set(mealFilter.map(DietText.fold))
        return scope
    }

    private var usage: [(food: DietFood, count: Int)] { DietBulkEdit.foodUsage(in: basePlan) }

    private var result: DietBulkResult? {
        switch operation {
        case .copy:
            guard !selectedDays.isEmpty else { return nil }
            return DietBulkEdit.copyDay(sourceDay, to: selectedDays, in: basePlan)
        case .replace:
            guard let findKey, let replacement else { return nil }
            let amount: DietReplaceAmount
            switch amountMode {
            case .equal: amount = .equalCalories
            case .same: amount = .same
            case .manual: amount = .manual(manualAmount, manualUnit)
            }
            return DietBulkEdit.replaceFood(in: basePlan, key: findKey, with: replacement, amount: amount, scope: scope)
        case .portion:
            guard let findKey, delta != 0 else { return nil }
            return DietBulkEdit.adjustPortion(in: basePlan, key: findKey, delta: delta, scope: scope)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("İşlem", selection: $operation) {
                        ForEach(Operation.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                switch operation {
                case .copy: copySection
                case .replace: replaceSection
                case .portion: portionSection
                }
                if operation != .copy { scopeSection }
                previewSection
            }
            .navigationTitle("Toplu düzenleme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { applyBar }
        }
    }

    // MARK: Bölümler

    private var foodPicker: some View {
        Picker("Bul", selection: $findKey) {
            Text("Seç").tag(String?.none)
            ForEach(usage, id: \.food.key) { entry in
                Text("\(entry.food.name) · \(entry.count) yerde").tag(String?.some(entry.food.key))
            }
        }
    }

    private var replaceSection: some View {
        Group {
            Section("Bul") { foodPicker }
            Section("Yerine") {
                Button(replacement?.name ?? "Kütüphaneden seç") { pickingReplacement = true }
                    .sheet(isPresented: $pickingReplacement) {
                        DietFoodPicker(foods: store.foodLibrary(), title: "Yerine") { food in
                            replacement = food
                            manualUnit = food.suggestedUnits.first ?? .serving
                        }
                    }
            }
            Section("Miktar") {
                Picker("Miktar", selection: $amountMode) {
                    Text(equalLabel).tag(AmountMode.equal)
                    Text("Aynı ölçü").tag(AmountMode.same)
                    Text("Elle gir").tag(AmountMode.manual)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if amountMode == .manual {
                    HStack {
                        TextField("Miktar", value: $manualAmount, format: .number.precision(.fractionLength(0...2)).locale(DietFormat.locale))
                            .keyboardType(.decimalPad)
                        Picker("Ölçü", selection: $manualUnit) {
                            ForEach(DietUnit.allCases) { Text($0.title).tag($0) }
                        }
                    }
                }
            }
        }
    }

    private var equalLabel: String {
        guard let findKey, let replacement,
              let sample = basePlan.days.flatMap(\.meals).flatMap(\.items).first(where: { $0.portion.food.key == findKey }) else {
            return "Kalorisi eşit"
        }
        let target = DietUnitTable.equalCalorieAmount(for: sample.portion.nutrition.calories, food: replacement)
        let portion = DietPortion(food: replacement, amount: target.amount, unit: target.unit)
        return "Kalorisi eşit ≈ \(portion.shortAmountText)\(portion.gramsHint.map { " (\($0))" } ?? "")"
    }

    private var portionSection: some View {
        Section {
            foodPicker
            Stepper(value: $delta, in: -5...5, step: 0.5) {
                Text(delta == 0 ? "Değişiklik yok" : "\(delta > 0 ? "+" : "")\(DietFormat.number(delta)) (kendi ölçüsünde)")
            }
        } header: {
            Text("Porsiyon")
        } footer: {
            Text("Örn. ekmek −1: her öğünde 1 dilim azalır. Sıfıra inen yiyecek öğünden çıkar.")
        }
    }

    private var copySection: some View {
        Group {
            Section("Kaynak gün") {
                Picker("Kaynak", selection: $sourceDay) {
                    ForEach(basePlan.days.indices, id: \.self) { Text("Gün \($0 + 1)").tag($0) }
                }
            }
            Section("Hedef günler") { dayGrid }
        }
    }

    private var scopeSection: some View {
        Section("Kapsam") {
            Picker("Günler", selection: $scopeMode) {
                ForEach(ScopeMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if scopeMode == .selected { dayGrid }
            let names = DietBulkEdit.mealNames(in: basePlan)
            DietTagRow(tags: ["Tüm öğünler"] + names, selected: mealFilter.isEmpty ? ["Tüm öğünler"] : mealFilter) { tag in
                Haptics.selection()
                if tag == "Tüm öğünler" { mealFilter = [] }
                else if mealFilter.contains(tag) { mealFilter.remove(tag) } else { mealFilter.insert(tag) }
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(basePlan.days.indices, id: \.self) { index in
                let on = selectedDays.contains(index)
                Button("\(index + 1)") {
                    Haptics.selection()
                    if on { selectedDays.remove(index) } else { selectedDays.insert(index) }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(on ? Color.white : (operation == .copy && index == sourceDay ? Color.ftTextSecondary : Color.ftText))
                .background(on ? Color.ftAccent : Color.ftSubtle(0.1), in: RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.plain)
                .disabled(operation == .copy && index == sourceDay)
                .accessibilityLabel("Gün \(index + 1)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var previewSection: some View {
        Section("Önizleme") {
            if let result, result.mealCount > 0 {
                Text("\(result.mealCount) öğün değişecek · \(daysText(result.days))").font(.subheadline)
                HStack {
                    deltaColumn(DietFormat.number(result.averageDelta.calories.rounded()), "kcal/gün", Color.ftText)
                    deltaColumn(signed(result.averageDelta.protein) + " g", "protein", MacroKind.protein.color)
                    deltaColumn(signed(result.averageDelta.carbs) + " g", "karb.", MacroKind.carbs.color)
                    deltaColumn(signed(result.averageDelta.fat) + " g", "yağ", MacroKind.fat.color)
                }
                if workingPlan == nil, let program, program.dayOffset(of: .now) >= 0 {
                    Text("Geçmiş günler (1–\(todayIndex + 1)) ve kayıtların değişmez; yeni sürüm yarından itibaren geçerli olur.")
                        .font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
            } else {
                Text("Seçimleri tamamla; kaç öğünün değişeceği burada görünür.").font(.subheadline).foregroundStyle(Color.ftTextSecondary)
            }
        }
    }

    private var applyBar: some View {
        VStack(spacing: 6) {
            if let undoPlan {
                Button {
                    apply(undoPlan, note: "Toplu düzenleme geri alındı")
                    self.undoPlan = nil
                } label: { Label("Geri al", systemImage: "arrow.uturn.backward") }
                    .tint(Color.ftAccentLight)
            }
            Button {
                guard let result else { return }
                undoPlan = basePlan
                apply(result.plan, note: noteText)
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    undoPlan = nil
                }
            } label: {
                Text(result.map { "\($0.mealCount) öğüne uygula" } ?? "Uygula").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ftAccent)
            .controlSize(.large)
            .disabled((result?.mealCount ?? 0) == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var noteText: String {
        switch operation {
        case .copy: return "Toplu düzenleme: Gün \(sourceDay + 1) kopyalandı"
        case .replace:
            let from = usage.first { $0.food.key == findKey }?.food.name ?? ""
            return "Toplu düzenleme: \(from) → \(replacement?.name ?? "")"
        case .portion:
            let name = usage.first { $0.food.key == findKey }?.food.name ?? ""
            return "Toplu düzenleme: \(name) \(delta > 0 ? "+" : "")\(DietFormat.number(delta))"
        }
    }

    private func apply(_ plan: DietPlan, note: String) {
        if let workingPlan {
            workingPlan.wrappedValue = plan
            Haptics.success()
            return
        }
        guard let program else { return }
        let effective = program.dayOffset(of: .now) < 0 ? program.startDate : (Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        do {
            try store.savePlan(plan, for: programID, effectiveFrom: effective, note: note)
            Haptics.success()
            store.showToast("Uygulandı · 10 sn içinde geri alabilirsin")
        } catch {
            store.present(error)
        }
    }

    private func daysText(_ days: [Int]) -> String {
        if days.count <= 6 { return "Gün " + days.map(String.init).joined(separator: ", ") }
        return "\(days.count) gün"
    }

    private func signed(_ value: Double) -> String {
        let rounded = value.rounded()
        return (rounded > 0 ? "+" : "") + DietFormat.number(rounded)
    }

    private func deltaColumn(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
