import SwiftUI
import UniformTypeIdentifiers

/// Excel (ya da CSV) dosyasından program: eşleşme özeti, takvimli önizleme, düzeltilecekler.
struct DietImportView: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onCreated: (DietProgram) -> Void

    @State private var showPicker = true
    @State private var fileName = ""
    @State private var draft: DietImportDraft?
    @State private var name = ""
    @State private var start = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var end: DietEndBehavior = .stop
    @State private var selectingStart = false
    @State private var previewDay = 1
    @State private var month = Calendar.current.startOfDay(for: .now)
    @State private var resolvingFood: DietImportIssue?
    @State private var creatingFood: DietImportIssue?
    @State private var errorText: String?

    private static let types: [UTType] = [
        UTType(filenameExtension: "xlsx") ?? .data, .commaSeparatedText, .plainText, .spreadsheet
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    content(draft)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "tablecells").font(.system(size: 48)).foregroundStyle(Color.ftAccentLight)
                        Text("Excel ya da CSV dosyası seç").font(.headline)
                        if let errorText { Text(errorText).font(.subheadline).foregroundStyle(Color.ftDanger).multilineTextAlignment(.center) }
                        Button("Dosya seç") { showPicker = true }.buttonStyle(.borderedProminent).tint(Color.ftAccent)
                    }
                    .padding(30)
                }
            }
            .ftScreenBackground()
            .navigationTitle("İçe aktar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: Self.types) { result in
                load(result)
            }
            .sheet(item: $resolvingFood) { issue in
                DietFoodPicker(foods: store.foodLibrary(), title: "Şununla eşleştir") { food in
                    draft?.resolutions[issue.id] = .matched(food)
                }
            }
            .sheet(item: $creatingFood) { issue in
                DietNewFoodSheet(initialName: { if case .unknownFood(let name) = issue.kind { return name }; return "" }()) { template in
                    draft?.resolutions[issue.id] = .matched(DietFood(template: template))
                }
            }
        }
    }

    // MARK: Yükleme

    private func load(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorText = error.localizedDescription
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let rows = try DietImport.rows(from: data, fileName: url.lastPathComponent)
                let parsed = DietImport.draft(from: rows, foods: store.foodLibrary())
                guard parsed.dayCount > 0 else {
                    errorText = "Başlık satırı bulunamadı. Sütunlar: Gün, Öğün, Saat, Yiyecek, Miktar, Birim, Değişim (şablonu indirip kullanabilirsin)."
                    return
                }
                fileName = url.lastPathComponent
                name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ").capitalized(with: DietFormat.locale)
                draft = parsed
                month = start
                Haptics.success()
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? "Dosya okunamadı."
            }
        }
    }

    // MARK: İçerik

    private func content(_ draft: DietImportDraft) -> some View {
        let plan = draft.makePlan()
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("XLSX").font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 42, height: 48).background(Color.ftSuccess, in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileName).font(.headline).lineLimit(1)
                        Text("\(draft.dayCount) gün · \(draft.mealCount) öğün · \(draft.rows.count) malzeme satırı")
                            .font(.caption).foregroundStyle(Color.ftTextSecondary)
                    }
                }
                .cardStyle(padding: 12)
                HStack(spacing: 8) {
                    counter("\(draft.matchedRowCount)", "eşleşti", Color.ftSuccess)
                    counter("\(draft.unknownFoodIssues.filter { draft.resolutions[$0.id] == nil }.count)", "kütüphanede yok", Color.ftWarning)
                    counter("\(draft.rowIssues.filter { draft.resolutions[$0.id] == nil }.count)", "hatalı satır", Color.ftDanger)
                }
                TextField("Program adı", text: $name).textFieldStyle(.roundedBorder)

                calendar(draft, plan: plan)
                dayPreview(draft, plan: plan)

                if !draft.issues.isEmpty {
                    DietSectionTitle(text: "Düzeltilecekler")
                    ForEach(draft.issues) { issue in issueCard(issue, draft: draft) }
                }
                Text("Şablon sütunları: Gün · Öğün · Saat · Yiyecek · Miktar · Birim · Değişim")
                    .font(.caption).foregroundStyle(Color.ftTextSecondary)
                Button {
                    save(plan)
                } label: {
                    Text("Programı kaydet").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ftAccent)
                .controlSize(.large)
                .disabled(plan.isEmpty)
                Text("Atlananlar programa eklenmez, sonra düzenleyiciden eklenebilir.")
                    .font(.caption).foregroundStyle(Color.ftTextSecondary).frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }

    private func counter(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.45)))
    }

    // MARK: Takvim

    private func calendar(_ draft: DietImportDraft, plan: DietPlan) -> some View {
        let calendar = Calendar.current
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let days = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        let offset = (calendar.component(.weekday, from: firstOfMonth) + 5) % 7
        let count = max(1, plan.dayCount)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Takvimde program").font(.headline)
                Spacer()
                Text(rangeText(count)).font(.caption).foregroundStyle(Color.ftTextSecondary)
            }
            Picker("Kip", selection: $selectingStart) {
                Text("Başlangıcı seç").tag(true)
                Text("Günlere bak").tag(false)
            }
            .pickerStyle(.segmented)
            Text(selectingStart ? "Programın başlayacağı güne dokun" : "Bir program gününe dokun, öğünleri aşağıda gör")
                .font(.caption).foregroundStyle(Color.ftTextSecondary).frame(maxWidth: .infinity)
            HStack {
                Button { month = calendar.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Önceki ay")
                Spacer()
                Text(firstOfMonth.formatted(.dateTime.month(.wide).year().locale(DietFormat.locale))).font(.headline)
                Spacer()
                Button { month = calendar.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Sonraki ay")
            }
            .tint(Color.ftAccentLight)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"], id: \.self) {
                    Text($0).font(.caption2.weight(.semibold)).foregroundStyle(Color.ftTextSecondary)
                }
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(1...days, id: \.self) { dayNumber in
                    let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: firstOfMonth) ?? firstOfMonth
                    dayCell(date, draft: draft, count: count)
                }
            }
            HStack(spacing: 12) {
                legend(Color.ftAccent, "Başlangıç")
                legend(Color.ftAccent.opacity(0.25), "Program günleri")
                legend(Color.ftWarning, "Düzeltme bekliyor", dot: true)
            }
            .font(.caption2).foregroundStyle(Color.ftTextSecondary)
            HStack {
                Text("Bitince").font(.subheadline.weight(.semibold))
                Picker("Bitince", selection: $end) {
                    ForEach(DietEndBehavior.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .cardStyle(padding: 14)
    }

    private func dayCell(_ date: Date, draft: DietImportDraft, count: Int) -> some View {
        let calendar = Calendar.current
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? -1
        let inRange = offset >= 0 && (offset < count || end == .loop)
        let programDay = inRange ? offset % count + 1 : nil
        let isStart = offset == 0
        let isCycle = offset >= count
        let selected = !selectingStart && programDay == previewDay && !isCycle
        let issue = programDay.map { draft.hasOpenIssue(day: $0) } ?? false
        return Button {
            Haptics.selection()
            if selectingStart {
                start = calendar.startOfDay(for: date)
                previewDay = 1
                selectingStart = false
            } else if let programDay {
                previewDay = programDay
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))").font(.subheadline.weight(isStart || selected ? .bold : .regular))
                Circle().fill(issue ? (isStart ? Color.white : Color.ftWarning) : Color.clear).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(isStart ? Color.white : (inRange ? Color.ftText : Color.ftTextSecondary))
            .background(isStart ? Color.ftAccent : (inRange ? Color.ftAccent.opacity(isCycle ? 0.08 : 0.2) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.ftText : .clear, lineWidth: 2))
            .overlay(alignment: .bottom) {
                if calendar.isDateInToday(date) { Rectangle().fill(Color.ftText).frame(width: 12, height: 1).offset(y: -4) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(DietFormat.longDate(date))\(programDay.map { ", program günü \($0)" } ?? "")\(issue ? ", düzeltme bekliyor" : "")")
    }

    private func legend(_ color: Color, _ text: String, dot: Bool = false) -> some View {
        HStack(spacing: 4) {
            if dot { Circle().fill(color).frame(width: 6, height: 6) } else { RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10) }
            Text(text)
        }
    }

    private func rangeText(_ count: Int) -> String {
        let endDate = Calendar.current.date(byAdding: .day, value: count - 1, to: start) ?? start
        return "\(DietFormat.shortDate(start)) – \(DietFormat.shortDate(endDate))\(end == .loop ? " · tekrar" : "")"
    }

    private func dayPreview(_ draft: DietImportDraft, plan: DietPlan) -> some View {
        let date = Calendar.current.date(byAdding: .day, value: previewDay - 1, to: start) ?? start
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Gün \(previewDay)").font(.headline)
                Spacer()
                Text("~\(plan.day(previewDay - 1).map { DietFormat.kcal($0.nutrition.calories) } ?? "0") kcal").font(.subheadline.bold()).foregroundStyle(Color.ftCalories)
            }
            Text(DietFormat.longDate(date)).font(.caption).foregroundStyle(Color.ftTextSecondary)
            if let text = draft.openIssueText(day: previewDay) {
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ftWarning.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
            }
            ForEach(plan.day(previewDay - 1)?.sortedMeals ?? []) { meal in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(meal.name).font(.subheadline.weight(.semibold))
                        Text(meal.timeText).font(.caption2).foregroundStyle(Color.ftTextSecondary)
                    }
                    .frame(width: 86, alignment: .leading)
                    Text(meal.summaryText).font(.caption)
                    Spacer(minLength: 0)
                }
                Divider()
            }
        }
        .cardStyle(padding: 14)
    }

    // MARK: Sorunlar

    private func issueCard(_ issue: DietImportIssue, draft: DietImportDraft) -> some View {
        let resolution = draft.resolutions[issue.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title).font(.subheadline.bold())
                    Text(issue.detail).font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
                Spacer()
                if let resolution {
                    Text(resolutionText(resolution)).font(.caption.weight(.semibold)).foregroundStyle(Color.ftSuccess)
                }
            }
            switch issue.kind {
            case .unknownFood(let name):
                let suggestion = FoodIndex(foods: store.foodLibrary()).search(name, limit: 1).first
                HStack(spacing: 6) {
                    if let suggestion {
                        chip("\(suggestion.name) ile eşleştir", prominent: true) {
                            self.draft?.resolutions[issue.id] = .matched(DietFood(template: suggestion))
                        }
                    }
                    chip("Benzerini seç…", prominent: suggestion == nil) { resolvingFood = issue }
                    chip("Yeni yiyecek") { creatingFood = issue }
                    chip("Atla") { self.draft?.resolutions[issue.id] = .skip }
                }
            case .missingAmount, .unknownUnit:
                DietAmountFixRow { amount, unit in self.draft?.resolutions[issue.id] = .amount(amount, unit) }
                chip("Atla") { self.draft?.resolutions[issue.id] = .skip }
            }
        }
        .padding(12)
        .background(resolution == nil ? Color.ftWarning.opacity(0.14) : Color.ftCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(resolution == nil ? Color.ftWarning.opacity(0.6) : Color.ftCardBorder))
    }

    private func resolutionText(_ resolution: DietImportResolution) -> String {
        switch resolution {
        case .matched(let food): return "→ \(food.name)"
        case .skip: return "Atlanacak"
        case .amount(let amount, let unit): return "\(DietFormat.number(amount)) \(unit.shortTitle)"
        }
    }

    private func chip(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(prominent ? Color.white : Color.ftText)
                .background(prominent ? Color.ftAccent : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(prominent ? Color.clear : Color.ftCardBorder))
        }
        .buttonStyle(.plain)
    }

    private func save(_ plan: DietPlan) {
        do {
            let program = try store.createProgram(name: name, plan: plan, startDate: start, endBehavior: end,
                                                  note: "Excel'den aktarıldı (\(fileName))")
            dismiss()
            onCreated(program)
        } catch {
            store.present(error)
        }
    }
}

struct DietAmountFixRow: View {
    let onSet: (Double, DietUnit) -> Void
    @State private var amount: Double = 1
    @State private var unit: DietUnit = .serving

    var body: some View {
        HStack {
            TextField("Miktar", value: $amount, format: .number.precision(.fractionLength(0...2)).locale(DietFormat.locale))
                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width: 80)
            Picker("Ölçü", selection: $unit) {
                ForEach(DietUnit.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            Button("Düzelt") { onSet(amount, unit) }.buttonStyle(.bordered).tint(Color.ftAccentLight)
        }
    }
}

/// Kütüphanede olmayan yiyecek için değer girişi.
struct DietNewFoodSheet: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var serving = "1 porsiyon (100 g)"
    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0
    let onCreate: (FoodTemplate) -> Void

    init(initialName: String, onCreate: @escaping (FoodTemplate) -> Void) {
        _name = State(initialValue: initialName)
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad", text: $name)
                    TextField("Porsiyon (örn. 1 adet (30 g))", text: $serving)
                }
                Section("1 porsiyon için") {
                    number("Kalori (kcal)", $calories)
                    number("Protein (g)", $protein)
                    number("Karbonhidrat (g)", $carbs)
                    number("Yağ (g)", $fat)
                }
            }
            .navigationTitle("Yeni yiyecek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        do {
                            let template = try store.createCustomFood(name: name, servingLabel: serving,
                                                                      nutrition: DietNutrition(calories: calories, protein: protein, carbs: carbs, fat: fat))
                            onCreate(template)
                            dismiss()
                        } catch { store.present(error) }
                    }
                    .bold()
                }
            }
        }
    }

    private func number(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)).locale(DietFormat.locale))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
}
