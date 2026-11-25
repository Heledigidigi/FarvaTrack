import SwiftUI
import UniformTypeIdentifiers

// MARK: - Program bölümü

struct DietProgramOverview: View {
    @Environment(DietStore.self) private var store
    let program: DietProgram

    @State private var editorDay: DietEditorTarget?
    @State private var showBulk = false
    @State private var showVersions = false
    @State private var showShopping = false
    @State private var showShare = false
    @State private var showReport = false
    @State private var showSettings = false
    @State private var exportURL: DietSharedFile?
    @State private var confirmDelete = false

    private var plan: DietPlan { program.version(on: .now).plan }
    private var todayNumber: Int? { program.programDay(on: .now) }
    private var pendingSuggestions: Int { store.suggestions(for: program.id).filter { $0.status == .pending }.count }

    var body: some View {
        VStack(spacing: 12) {
            infoCard
            actions
            DietSectionTitle(text: "Günler")
            ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                Button { editorDay = DietEditorTarget(day: index) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .frame(width: 34, height: 34)
                            .foregroundStyle(todayNumber == index + 1 ? Color.white : Color.ftText)
                            .background(todayNumber == index + 1 ? Color.ftAccent : Color.ftSubtle(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.sortedMeals.map(\.name).joined(separator: " · "))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ftText).lineLimit(1)
                            Text(day.sortedMeals.flatMap(\.items).prefix(4).map(\.portion.food.name).joined(separator: ", "))
                                .font(.caption).foregroundStyle(Color.ftTextSecondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(day.nutrition.kcal) kcal").font(.caption.weight(.semibold)).foregroundStyle(Color.ftCalories)
                            Text(day.nutrition.shareText).font(.caption2).foregroundStyle(Color.ftTextSecondary)
                        }
                    }
                    .padding(12)
                    .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gün \(index + 1), \(day.nutrition.kcal) kilokalori")
                .accessibilityHint("Düzenlemek için çift dokun")
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Programı sil", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
        }
        .sheet(item: $editorDay) { target in
            DietEditorView(programID: program.id, startDay: target.day)
        }
        .sheet(isPresented: $showBulk) { DietBulkEditView(programID: program.id) }
        .sheet(isPresented: $showVersions) { DietVersionsView(programID: program.id) }
        .sheet(isPresented: $showShopping) { DietShoppingView(program: program) }
        .sheet(isPresented: $showShare) { DietShareSheet(programID: program.id) }
        .sheet(isPresented: $showSettings) { DietProgramSettingsView(program: program) }
        .fullScreenCover(isPresented: $showReport) { DietReportView(program: program) }
        .sheet(item: $exportURL) { file in DietShareFileSheet(url: file.url) }
        .confirmationDialog("\(program.name) silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Programı ve kayıtlarını sil", role: .destructive) { store.deleteProgram(program.id) }
            Button("Arşivle (kayıtlar kalsın)") { try? store.archive(program.id) }
        } message: {
            Text("Öğün kayıtları, fotoğraflar ve notlar da silinir. Bu işlem geri alınamaz.")
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(program.name).font(.title3.bold()).foregroundStyle(Color.ftText)
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .tint(Color.ftAccentLight)
                    .accessibilityLabel("Program ayarları")
            }
            Text(dateLine).font(.caption).foregroundStyle(Color.ftTextSecondary)
            HStack(spacing: 14) {
                stat("\(plan.dayCount)", "gün")
                stat(DietFormat.number(plan.averageMealsPerDay), "öğün/gün")
                stat(DietFormat.kcal(plan.averageNutrition.calories), "ort. kcal")
                stat("\(program.versions.count)", "sürüm")
            }
            DietMacroBar(nutrition: plan.averageNutrition)
            Text(plan.averageNutrition.shareText).font(.caption).foregroundStyle(Color.ftTextSecondary)
            if let shared = program.sharedByName {
                Label(program.viewerIDs.isEmpty ? "\(shared) gönderdi" : "\(shared) gönderdi · takibini görebiliyor",
                      systemImage: program.viewerIDs.isEmpty ? "person" : "eye")
                    .font(.caption).foregroundStyle(Color.ftTextSecondary)
            }
        }
        .cardStyle(padding: 14)
    }

    private var dateLine: String {
        let start = "Başlangıç \(DietFormat.shortDate(program.startDate))"
        if let end = program.endDate { return "\(start) · bitiş \(DietFormat.shortDate(end))" }
        return "\(start) · bitince başa döner"
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(Color.ftText)
            Text(label).font(.caption2).foregroundStyle(Color.ftTextSecondary)
        }
    }

    private var actions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            action("Düzenle", "pencil") { editorDay = DietEditorTarget(day: max(0, (todayNumber ?? 1) - 1)) }
            action("Toplu düzenle", "wand.and.stars") { showBulk = true }
            action(pendingSuggestions > 0 ? "Sürümler (\(pendingSuggestions))" : "Sürümler", "clock.arrow.circlepath") { showVersions = true }
            action("Alışveriş", "cart") { showShopping = true }
            action("Rapor", "doc.text.magnifyingglass") { showReport = true }
            action("Paylaş", "paperplane") { showShare = true }
            action("Excel'e aktar", "tablecells") { exportExcel() }
        }
    }

    private func action(_ title: String, _ icon: String, perform: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            perform()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(Color.ftAccentLight)
            .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ftCardBorder))
        }
        .buttonStyle(.plain)
    }

    private func exportExcel() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(program.name.replacingOccurrences(of: "/", with: "-")).xlsx")
        do {
            try DietImport.exportData(plan: program.latestPlan).write(to: url, options: .atomic)
            exportURL = DietSharedFile(url: url)
        } catch {
            store.present(error)
        }
    }
}

struct DietEditorTarget: Identifiable {
    var day: Int
    var id: Int { day }
}

/// Paylaşılacak dosya (sayfa açmak için kimlikli sarmalayıcı).
struct DietSharedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Dosya paylaşım sayfası (Excel, PDF).
struct DietShareFileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: url.pathExtension == "pdf" ? "doc.richtext" : "tablecells")
                    .font(.system(size: 46)).foregroundStyle(Color.ftAccentLight)
                Text(url.lastPathComponent).font(.headline).multilineTextAlignment(.center)
                ShareLink(item: url) {
                    Label("Paylaş ya da Dosyalar'a kaydet", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ftAccent)
            }
            .padding(24)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Program ayarları

struct DietProgramSettingsView: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let program: DietProgram
    @State private var name: String
    @State private var start: Date
    @State private var end: DietEndBehavior
    @State private var viewerAllowed: Bool

    init(program: DietProgram) {
        self.program = program
        _name = State(initialValue: program.name)
        _start = State(initialValue: program.startDate)
        _end = State(initialValue: program.endBehavior)
        _viewerAllowed = State(initialValue: program.sharedByID.map { program.viewerIDs.contains($0) } ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Program") {
                    TextField("Program adı", text: $name)
                    DatePicker("Başlangıç", selection: $start, displayedComponents: .date)
                        .environment(\.locale, DietFormat.locale)
                    Picker("Bitince", selection: $end) {
                        ForEach(DietEndBehavior.allCases) { Text($0.title).tag($0) }
                    }
                }
                if let sharedBy = program.sharedByID {
                    Section {
                        Toggle("\(program.sharedByName ?? "Gönderen") takibimi görebilsin", isOn: $viewerAllowed)
                    } footer: {
                        Text("Açıkken öğünlerin, fotoğrafların, notların, makro analizin, ekstraların, kilon ve ölçülerin bu kişiye görünür; yorum yapabilir ve programda değişiklik önerebilir. Kapatınca hiçbirini göremez.")
                    }
                    .onChange(of: viewerAllowed) { _, allowed in
                        do { try store.setViewer(program.id, viewerID: sharedBy, allowed: allowed) } catch { store.present(error) }
                    }
                }
                Section {
                    Button(program.isArchived ? "Arşivden çıkar" : "Arşivle") {
                        try? store.archive(program.id, archived: !program.isArchived)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Program ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        do {
                            if name != program.name { try store.rename(program.id, to: name) }
                            if start != program.startDate || end != program.endBehavior {
                                try store.setStart(program.id, date: start, endBehavior: end)
                            }
                            dismiss()
                        } catch { store.present(error) }
                    }
                    .bold()
                }
            }
        }
    }
}

// MARK: - Yeni program

struct DietNewProgramView: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Diyet programım"
    @State private var days = 7
    @State private var start = Date.now
    @State private var end: DietEndBehavior = .loop
    @State private var showImport = false
    @State private var templateURL: DietSharedFile?
    let onCreated: (DietProgram) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showImport = true } label: {
                        Label("Excel'den içe aktar", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FarvaTrack-diyet-sablonu.xlsx")
                        do {
                            try DietImport.templateData(foods: store.foodLibrary()).write(to: url, options: .atomic)
                            templateURL = DietSharedFile(url: url)
                        } catch { store.present(error) }
                    } label: {
                        Label("Excel şablonunu indir", systemImage: "tablecells")
                    }
                } footer: {
                    Text("Şablonu doldurup Dosyalar'dan seçebilirsin. Sütunlar: Gün, Öğün, Saat, Yiyecek, Miktar, Birim, Değişim.")
                }
                Section("Ya da elle oluştur") {
                    TextField("Program adı", text: $name)
                    Stepper("\(days) gün", value: $days, in: 1...120)
                    DatePicker("Başlangıç", selection: $start, displayedComponents: .date)
                        .environment(\.locale, DietFormat.locale)
                    Picker("Bitince", selection: $end) {
                        ForEach(DietEndBehavior.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .navigationTitle("Yeni program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Oluştur") {
                        do {
                            let program = try store.createProgram(name: name, plan: .empty(days: days), startDate: start,
                                                                  endBehavior: end, note: "Elle oluşturuldu")
                            dismiss()
                            onCreated(program)
                        } catch { store.present(error) }
                    }
                    .bold()
                }
            }
            .sheet(isPresented: $showImport) {
                DietImportView { program in
                    dismiss()
                    onCreated(program)
                }
            }
            .sheet(item: $templateURL) { file in DietShareFileSheet(url: file.url) }
        }
    }
}

// MARK: - Düzenleyici

struct DietEditorView: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let programID: String
    /// Öneri kipinde (programı inceleyen kişi) kaydetmek öneri gönderir.
    var suggestionMode = false

    @State private var plan = DietPlan()
    @State private var original = DietPlan()
    @State private var day: Int
    @State private var loaded = false
    @State private var editing: DietItemTarget?
    @State private var addingTo: String?
    @State private var showSave = false
    @State private var showBulk = false
    @State private var effectiveFrom = Date.now
    @State private var note = ""

    init(programID: String, startDay: Int, suggestionMode: Bool = false) {
        self.programID = programID
        self.suggestionMode = suggestionMode
        _day = State(initialValue: startDay)
    }

    private var program: DietProgram? { store.program(id: programID) }
    private var hasChanges: Bool { plan != original }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    dayChips
                    if let current = plan.day(day) {
                        ForEach(current.sortedMeals) { meal in mealCard(meal) }
                        Button { addMeal() } label: { Label("Öğün ekle", systemImage: "plus") }
                            .tint(Color.ftAccentLight)
                        dayBalance(current)
                    }
                }
                .padding(16)
            }
            .ftScreenBackground()
            .navigationTitle(suggestionMode ? "Değişiklik öner" : "Programı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showBulk = true } label: { Label("Toplu düzenleme", systemImage: "wand.and.stars") }
                        Button { copyDayToNext() } label: { Label("Bu günü sonraki güne kopyala", systemImage: "doc.on.doc") }
                        Button { plan.days.append(DietDay(meals: DietMeal.defaultSlots())); day = plan.days.count - 1 } label: {
                            Label("Gün ekle", systemImage: "calendar.badge.plus")
                        }
                        if plan.days.count > 1 {
                            Button(role: .destructive) { removeDay() } label: { Label("Bu günü sil", systemImage: "calendar.badge.minus") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(suggestionMode ? "Gönder" : "Kaydet") { showSave = true }.bold().disabled(!hasChanges)
                }
            }
            .sheet(item: $editing) { target in
                DietItemEditor(item: binding(for: target), foods: store.foodLibrary()) {
                    deleteItem(target)
                }
            }
            .sheet(item: Binding(get: { addingTo.map { DietMealTarget(id: $0) } }, set: { addingTo = $0?.id })) { target in
                DietFoodPicker(foods: store.foodLibrary(), title: "Malzeme ekle") { food in
                    addItem(food, to: target.id)
                }
            }
            .sheet(isPresented: $showBulk) {
                DietBulkEditView(programID: programID, workingPlan: $plan)
            }
            .sheet(isPresented: $showSave) { saveSheet }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded, let program else { return }
        loaded = true
        // Yeni sürümler en son plan üzerinden düzenlenir.
        plan = program.latestPlan
        original = plan
        day = min(day, max(0, plan.dayCount - 1))
        effectiveFrom = program.dayOffset(of: .now) < 0 ? program.startDate : (Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
    }

    private var dayChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(plan.days.indices, id: \.self) { index in
                        Button("Gün \(index + 1)") {
                            Haptics.selection()
                            day = index
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(day == index ? Color.white : Color.ftText)
                        .background(day == index ? Color.ftAccent : Color.ftSubtle(0.12), in: Capsule())
                        .id(index)
                        .accessibilityAddTraits(day == index ? .isSelected : [])
                    }
                }
            }
            .onAppear { proxy.scrollTo(day, anchor: .center) }
        }
    }

    private func mealCard(_ meal: DietMeal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Öğün", text: mealName(meal.id))
                    .font(.headline)
                DatePicker("Saat", selection: mealTime(meal.id), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Menu {
                    Button(role: .destructive) { removeMeal(meal.id) } label: { Label("Öğünü sil", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }
                .accessibilityLabel("\(meal.name) seçenekleri")
            }
            ForEach(meal.items) { item in
                Button { editing = DietItemTarget(mealID: meal.id, itemID: item.id) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.portion.food.name).font(.subheadline).foregroundStyle(Color.ftText)
                            HStack(spacing: 4) {
                                Text(item.portion.amountText)
                                if let hint = item.portion.gramsHint { Text(hint) }
                            }
                            .font(.caption).foregroundStyle(Color.ftTextSecondary)
                            if !item.alternatives.isEmpty {
                                Text("↺ " + item.alternatives.map(\.label).joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(Color.ftWarning).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("\(item.portion.nutrition.kcal)").font(.caption.monospacedDigit()).foregroundStyle(Color.ftTextSecondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                Divider()
            }
            Button { addingTo = meal.id } label: { Label("Malzeme ekle", systemImage: "plus") }
                .font(.subheadline.weight(.semibold))
                .tint(Color.ftAccentLight)
            mealEstimate(meal)
        }
        .cardStyle(padding: 14)
    }

    private func mealEstimate(_ meal: DietMeal) -> some View {
        let n = meal.nutrition
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tahmini öğün: \(n.kcal) kcal").font(.caption.bold()).foregroundStyle(Color.ftText)
                Spacer()
                Text("canlı hesap").font(.caption2).foregroundStyle(Color.ftTextSecondary)
            }
            DietMacroBar(nutrition: n)
            DietMacroColumns(nutrition: n)
        }
        .padding(10)
        .background(Color.ftCalories.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
    }

    private func dayBalance(_ current: DietDay) -> some View {
        let n = current.nutrition
        let heaviest = current.meals.max { $0.nutrition.calories < $1.nutrition.calories }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Gün \(day + 1) dengesi (tahmini)").font(.headline).foregroundStyle(Color.ftText)
                Spacer()
                Text("\(DietFormat.kcal(n.calories)) kcal").font(.headline).foregroundStyle(Color.ftCalories)
            }
            DietMacroBar(nutrition: n, height: 10)
            DietMacroColumns(nutrition: n)
            if let heaviest, n.calories > 0 {
                Text("\(current.meals.count) öğün · en ağır öğün \(heaviest.name.lowercased(with: DietFormat.locale)) (%\(Int((heaviest.nutrition.calories / n.calories * 100).rounded())))")
                    .font(.caption).foregroundStyle(Color.ftTextSecondary)
            }
        }
        .cardStyle(padding: 14)
    }

    private var saveSheet: some View {
        NavigationStack {
            Form {
                let changes = DietPlanDiff.changes(from: original, to: plan)
                Section("Değişiklikler") {
                    if changes.isEmpty { Text("Değişiklik yok").foregroundStyle(Color.ftTextSecondary) }
                    ForEach(changes.prefix(12)) { change in
                        HStack(alignment: .top) {
                            Text(change.symbol).bold().foregroundStyle(change.kind == .removed ? Color.ftDanger : (change.kind == .added ? Color.ftSuccess : Color.ftWarning))
                            Text("\(change.mealName): \(change.text)").font(.subheadline)
                            Spacer()
                            Text(change.daysText).font(.caption).foregroundStyle(Color.ftTextSecondary)
                        }
                    }
                }
                if !suggestionMode, let program, program.dayOffset(of: .now) >= 0 {
                    Section {
                        DatePicker("Geçerli olacağı gün", selection: $effectiveFrom, in: program.startDate..., displayedComponents: .date)
                            .environment(\.locale, DietFormat.locale)
                    } footer: {
                        Text("Bu günden önceki kayıtlar ve analizler eski sürümle kalır.")
                    }
                }
                Section(suggestionMode ? "Not (programın sahibine)" : "Not (sürüm geçmişinde görünür)") {
                    TextField(suggestionMode ? "Örn. akşamları acıktığını yazmışsın…" : "Örn. ekmeği azalttım", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(suggestionMode ? "Öneriyi gönder" : "Kaydet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Geri") { showSave = false } }
                ToolbarItem(placement: .confirmationAction) { Button(suggestionMode ? "Gönder" : "Kaydet", action: commit).bold() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func commit() {
        if suggestionMode {
            Task {
                do {
                    try await store.suggest(programID: programID, plan: plan, note: note)
                    showSave = false
                    dismiss()
                } catch { store.present(error) }
            }
            return
        }
        do {
            try store.savePlan(plan, for: programID, effectiveFrom: effectiveFrom, note: note)
            Haptics.success()
            showSave = false
            dismiss()
        } catch {
            store.present(error)
        }
    }

    // MARK: Bağlamalar

    private func mealIndex(_ mealID: String) -> Int? { plan.days[day].meals.firstIndex { $0.id == mealID } }

    private func mealName(_ mealID: String) -> Binding<String> {
        Binding(get: { mealIndex(mealID).map { plan.days[day].meals[$0].name } ?? "" },
                set: { value in if let i = mealIndex(mealID) { plan.days[day].meals[i].name = String(value.prefix(30)) } })
    }

    private func mealTime(_ mealID: String) -> Binding<Date> {
        Binding(get: {
            let minutes = mealIndex(mealID).map { plan.days[day].meals[$0].minutes } ?? 0
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        }, set: { value in
            guard let i = mealIndex(mealID) else { return }
            let c = Calendar.current.dateComponents([.hour, .minute], from: value)
            plan.days[day].meals[i].minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }

    private func binding(for target: DietItemTarget) -> Binding<DietItem> {
        Binding(get: {
            guard let m = mealIndex(target.mealID), let i = plan.days[day].meals[m].items.firstIndex(where: { $0.id == target.itemID }) else {
                return DietItem(portion: DietPortion(food: .placeholder(name: "—"), amount: 1, unit: .serving))
            }
            return plan.days[day].meals[m].items[i]
        }, set: { value in
            guard let m = mealIndex(target.mealID), let i = plan.days[day].meals[m].items.firstIndex(where: { $0.id == target.itemID }) else { return }
            plan.days[day].meals[m].items[i] = value
        })
    }

    private func addItem(_ food: DietFood, to mealID: String) {
        guard let m = mealIndex(mealID) else { return }
        let item = DietItem(portion: DietPortion(food: food))
        plan.days[day].meals[m].items.append(item)
        editing = DietItemTarget(mealID: mealID, itemID: item.id)
    }

    private func deleteItem(_ target: DietItemTarget) {
        guard let m = mealIndex(target.mealID) else { return }
        plan.days[day].meals[m].items.removeAll { $0.id == target.itemID }
    }

    private func addMeal() {
        let used = Set(plan.days[day].meals.map { DietText.fold($0.name) })
        let next = DietMeal.defaultSlots().first { !used.contains(DietText.fold($0.name)) } ?? DietMeal(name: "Gece", minutes: 22 * 60)
        // Aynı adlı öğünün kimliği başka günlerde varsa onu kullan (kayıtlar ve analiz öğünleri eşleştirir).
        let existingID = plan.days.flatMap(\.meals).first { DietText.fold($0.name) == DietText.fold(next.name) }?.id
        plan.days[day].meals.append(DietMeal(id: existingID ?? next.id, name: next.name, minutes: next.minutes))
    }

    private func removeMeal(_ mealID: String) {
        plan.days[day].meals.removeAll { $0.id == mealID }
    }

    private func copyDayToNext() {
        guard day + 1 < plan.days.count else { return }
        plan = DietBulkEdit.copyDay(day, to: [day + 1], in: plan).plan
        day += 1
        Haptics.success()
    }

    private func removeDay() {
        plan.days.remove(at: day)
        day = max(0, day - 1)
    }
}

struct DietItemTarget: Identifiable, Hashable {
    var mealID: String
    var itemID: String
    var id: String { "\(mealID)|\(itemID)" }
}

struct DietMealTarget: Identifiable { var id: String }

/// Malzeme ve değişimleri.
struct DietItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var item: DietItem
    let foods: [FoodTemplate]
    let onDelete: () -> Void
    @State private var pickingAlternative = false
    @State private var replacingFood = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DietPortionEditor(portion: $item.portion)
                    Button("Yiyeceği değiştir") { replacingFood = true }
                }
                Section {
                    ForEach(item.alternatives.indices, id: \.self) { index in
                        DietPortionEditor(portion: $item.alternatives[index])
                    }
                    .onDelete { item.alternatives.remove(atOffsets: $0) }
                    Button { pickingAlternative = true } label: { Label("Değişim ekle", systemImage: "plus") }
                } header: {
                    Text("Değişimler (\"ya da\")")
                } footer: {
                    Text("\"Değiştirerek yedim\" derken bunlar ilk sırada önerilir.")
                }
                Section {
                    Button("Malzemeyi sil", role: .destructive) { onDelete(); dismiss() }
                }
            }
            .navigationTitle(item.portion.food.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() }.bold() } }
            .sheet(isPresented: $pickingAlternative) {
                DietFoodPicker(foods: foods, title: "Değişim ekle") { food in
                    let target = DietUnitTable.equalCalorieAmount(for: item.portion.nutrition.calories, food: food)
                    item.alternatives.append(DietPortion(food: food, amount: target.amount, unit: target.unit))
                }
            }
            .sheet(isPresented: $replacingFood) {
                DietFoodPicker(foods: foods, title: "Yiyeceği değiştir") { food in
                    let target = DietUnitTable.equalCalorieAmount(for: item.portion.nutrition.calories, food: food)
                    item.portion = DietPortion(food: food, amount: target.amount, unit: target.unit)
                }
            }
        }
    }
}

// MARK: - Programlarım

struct DietProgramListView: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false

    private var active: DietProgram? { store.activeProgram() }

    var body: some View {
        NavigationStack {
            List {
                if store.programs.isEmpty {
                    ContentUnavailableView("Henüz program yok", systemImage: "list.clipboard",
                                           description: Text("Excel'den aktarabilir ya da elle oluşturabilirsin."))
                }
                let current = store.programs.filter { !$0.isArchived }
                if !current.isEmpty {
                    Section("Programlar") {
                        ForEach(current) { program in row(program) }
                    }
                }
                let archived = store.programs.filter(\.isArchived)
                if !archived.isEmpty {
                    Section("Arşiv") {
                        ForEach(archived) { program in row(program) }
                    }
                }
            }
            .navigationTitle("Diyet programlarım")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Yeni program")
                }
            }
            .sheet(isPresented: $showNew) { DietNewProgramView { _ in } }
        }
    }

    private func row(_ program: DietProgram) -> some View {
        NavigationLink {
            ScrollView {
                DietProgramOverview(program: program).padding(16)
            }
            .ftScreenBackground()
            .navigationTitle(program.name)
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(program.name).font(.headline)
                    if program.id == active?.id {
                        Text("takipte").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.ftSuccess.opacity(0.2), in: Capsule()).foregroundStyle(Color.ftSuccess)
                    }
                }
                Text(status(program)).font(.caption).foregroundStyle(Color.ftTextSecondary)
            }
        }
        .swipeActions {
            Button(program.isArchived ? "Geri al" : "Arşivle") { try? store.archive(program.id, archived: !program.isArchived) }
                .tint(Color.ftWarning)
        }
    }

    private func status(_ program: DietProgram) -> String {
        if let day = program.programDay(on: .now) { return "Gün \(day) / \(program.dayCount) · \(DietFormat.shortDate(program.startDate)) başladı" }
        if program.dayOffset(of: .now) < 0 { return "\(DietFormat.shortDate(program.startDate)) tarihinde başlıyor · \(program.dayCount) gün" }
        return "Bitti · \(program.dayCount) gün"
    }
}
