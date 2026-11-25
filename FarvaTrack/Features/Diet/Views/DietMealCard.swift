import SwiftUI

// MARK: - Öğün kartı (Bugün ekranı)

struct DietMealCard: View {
    @Environment(DietStore.self) private var store
    let program: DietProgram
    let date: Date
    let snapshot: DietMealSnapshot
    /// Şu anki ya da sıradaki öğün: açık gösterilir.
    let isCurrent: Bool

    @State private var expanded = false
    @State private var showSwap = false
    @State private var showCamera = false
    @State private var showNote = false
    @State private var showPhoto = false

    private var meal: DietMeal { snapshot.meal }
    private var log: DietMealLog? { snapshot.log }
    private var isOpen: Bool { expanded || (snapshot.status == nil && (isCurrent || !snapshot.isMissed)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isOpen {
                openContent
            } else {
                compactContent
            }
            if let log, store.program(id: program.id)?.viewerIDs.isEmpty == false || !store.comments(programID: program.id, targetID: log.id).isEmpty {
                DietCommentList(programID: program.id, targetID: log.id)
            }
        }
        .padding(14)
        .background(Color.ftCard, in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
                .strokeBorder(isCurrent && snapshot.status == nil ? Color.ftAccent.opacity(0.55) : Color.ftCardBorder,
                              lineWidth: isCurrent && snapshot.status == nil ? 1.5 : 1)
        )
        .sheet(isPresented: $showSwap) {
            DietSwapSheet(program: program, date: date, meal: meal, existing: log)
        }
        .fullScreenCover(isPresented: $showCamera) {
            DietCameraPicker { image in
                do { try store.attachPhoto(image, program: program, date: date, meal: meal) } catch { store.present(error) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showNote) {
            DietTextSheet(title: "\(meal.name) notu", text: log?.note ?? "", placeholder: "Örn. peyniri yarım dilim yedim") { text in
                do { try store.setMealNote(program: program, date: date, meal: meal, note: text) } catch { store.present(error) }
            }
        }
        .fullScreenCover(isPresented: $showPhoto) {
            if let path = log?.photoPath {
                DietPhotoFullScreen(path: path, title: "\(meal.name) · \(log?.photoTakenAt.map { DietFormat.time(minutes: Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0)) } ?? meal.timeText)")
            }
        }
    }

    // MARK: Başlık

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(meal.name) · \(meal.timeText)").font(.headline).foregroundStyle(Color.ftText)
                Text(snapshot.status == .changed || snapshot.status == .eaten
                     ? "\(snapshot.eatenNutrition.kcal) kcal · plan \(meal.nutrition.kcal)"
                     : "plan \(meal.nutrition.kcal) kcal")
                    .font(.caption).foregroundStyle(Color.ftTextSecondary)
            }
            Spacer()
            if snapshot.status != nil || snapshot.isMissed {
                DietStatusChip(status: snapshot.status, missed: snapshot.isMissed)
            }
            Button {
                Haptics.impact(.light)
                showCamera = true
            } label: {
                Image(systemName: "camera.fill").font(.subheadline)
                    .frame(width: 34, height: 34)
                    .background(Color.ftAccent.opacity(0.1), in: Circle())
                    .foregroundStyle(Color.ftAccentLight)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(log?.photoPath == nil ? "Tabağın fotoğrafını çek" : "Fotoğrafı yeniden çek")
            menu
        }
    }

    private var menu: some View {
        Menu {
            if snapshot.status != nil {
                Button { showSwap = true } label: { Label("Değiştirerek yedim", systemImage: "arrow.triangle.2.circlepath") }
                Button { mark(.eaten) } label: { Label("Planındaki gibi yedim", systemImage: "checkmark") }
                Button { mark(.skipped) } label: { Label("Atladım", systemImage: "xmark") }
                Button(role: .destructive) {
                    do { try store.unmark(program: program, date: date, meal: meal) } catch { store.present(error) }
                } label: { Label("İşareti kaldır", systemImage: "arrow.uturn.backward") }
            }
            Button { showNote = true } label: { Label(log?.note.isEmpty == false ? "Notu düzenle" : "Not ekle", systemImage: "square.and.pencil") }
            if log?.photoPath != nil {
                Button(role: .destructive) {
                    do { try store.removePhoto(program: program, date: date, meal: meal) } catch { store.present(error) }
                } label: { Label("Fotoğrafı kaldır", systemImage: "trash") }
            }
            if snapshot.status != nil {
                Button { withAnimation { expanded.toggle() } } label: {
                    Label(expanded ? "Küçült" : "Planı göster", systemImage: expanded ? "chevron.up" : "chevron.down")
                }
            }
        } label: {
            Image(systemName: "ellipsis").font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .accessibilityLabel("\(meal.name) seçenekleri")
    }

    // MARK: İçerik

    @ViewBuilder
    private var openContent: some View {
        if let path = log?.photoPath {
            photoRow(path)
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(meal.items) { item in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.portion.food.name).font(.subheadline).foregroundStyle(Color.ftText)
                        HStack(spacing: 4) {
                            Text(item.portion.amountText)
                            if let hint = item.portion.gramsHint { Text(hint) }
                            if !item.alternatives.isEmpty { Text("· \(item.alternatives.count) değişim") }
                        }
                        .font(.caption).foregroundStyle(Color.ftTextSecondary)
                    }
                    Spacer()
                    Text("\(item.portion.nutrition.kcal)").font(.caption.monospacedDigit()).foregroundStyle(Color.ftTextSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        if let note = log?.note, !note.isEmpty, log?.photoPath == nil {
            Text("“\(note)”").font(.caption.italic()).foregroundStyle(Color.ftText)
        }
        if snapshot.status == nil {
            HStack(spacing: 8) {
                Button { mark(.eaten) } label: {
                    Text("Yedim").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ftAccent)
                Button { showSwap = true } label: {
                    Text("Değiştirerek yedim").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.ftAccentLight)
                .layoutPriority(1)
                Button { mark(.skipped) } label: {
                    Text("Atladım").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.ftTextSecondary)
            }
            .font(.subheadline.weight(.semibold))
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private var compactContent: some View {
        HStack(alignment: .top, spacing: 10) {
            if let path = log?.photoPath {
                Button { showPhoto = true } label: {
                    DietPhotoView(path: path)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(meal.name) fotoğrafını aç")
            }
            VStack(alignment: .leading, spacing: 3) {
                if snapshot.status == .changed, let log, !log.swaps.isEmpty {
                    Text(log.swaps.joined(separator: " · ")).font(.caption.weight(.semibold)).foregroundStyle(Color.ftWarning)
                }
                if snapshot.status == .skipped {
                    Text("Plan: " + meal.summaryText).font(.caption).foregroundStyle(Color.ftTextSecondary).lineLimit(2)
                } else if snapshot.status != nil {
                    Text(log?.eatenSummary ?? meal.summaryText).font(.caption).foregroundStyle(Color.ftText).lineLimit(2)
                } else {
                    Text(meal.summaryText).font(.caption).foregroundStyle(Color.ftTextSecondary).lineLimit(2)
                }
                if let note = log?.note, !note.isEmpty {
                    Text("“\(note)”").font(.caption.italic()).foregroundStyle(Color.ftText).lineLimit(2)
                }
                if snapshot.isMissed {
                    HStack {
                        Button("Yedim") { mark(.eaten) }
                        Button("Değiştirerek") { showSwap = true }
                        Button("Atladım") { mark(.skipped) }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(Color.ftAccentLight)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func photoRow(_ path: String) -> some View {
        HStack(spacing: 10) {
            Button { showPhoto = true } label: {
                DietPhotoView(path: path)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fotoğrafı tam ekran aç")
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.status == nil ? "Fotoğraf hazır" : "Tabak fotoğrafı").font(.caption.weight(.bold)).foregroundStyle(Color.ftText)
                Text(snapshot.status == nil ? "Öğünü işaretleyince bu kayda eklenir." : (log?.note.isEmpty == false ? "“\(log?.note ?? "")”" : ""))
                    .font(.caption).foregroundStyle(Color.ftTextSecondary).lineLimit(2)
                if log?.note.isEmpty != false {
                    Button("+ Not ekle") { showNote = true }.font(.caption.weight(.semibold)).tint(Color.ftAccentLight)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.ftAccent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func mark(_ status: DietMealStatus) {
        do {
            try store.mark(program: program, date: date, meal: meal, status: status)
            expanded = false
        } catch {
            store.present(error)
        }
    }
}

// MARK: - Değiştirerek yedim

struct DietSwapSheet: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let program: DietProgram
    let date: Date
    let meal: DietMeal
    let existing: DietMealLog?

    private enum Choice: Hashable { case same, swapped(DietPortion), skipped }

    @State private var choices: [String: Choice] = [:]
    @State private var selectedItem: String?
    @State private var extras: [DietPortion] = []
    @State private var showSearch = false
    @State private var searchForItem: String?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Neyi değiştirdin? Dokun, yerine yediğini seç.").font(.subheadline).foregroundStyle(Color.ftTextSecondary)
                    VStack(spacing: 0) {
                        ForEach(meal.items) { item in itemRow(item) }
                    }
                    .padding(.horizontal, 12)
                    .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 14))

                    if let id = selectedItem, let item = meal.items.first(where: { $0.id == id }) {
                        suggestions(for: item)
                    }

                    if !extras.isEmpty {
                        DietSectionTitle(text: "Ayrıca yediklerin")
                        ForEach(Array(extras.enumerated()), id: \.offset) { index, _ in
                            HStack(alignment: .top) {
                                DietPortionEditor(portion: $extras[index])
                                Button { extras.remove(at: index) } label: { Image(systemName: "minus.circle.fill") }
                                    .tint(Color.ftDanger)
                                    .accessibilityLabel("Kaldır")
                            }
                            .padding(12)
                            .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    Button {
                        searchForItem = nil
                        showSearch = true
                    } label: {
                        Label("Başka bir şey de yedim", systemImage: "plus.circle")
                    }
                    .tint(Color.ftAccentLight)

                    TextField("Not (isteğe bağlı)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)

                    summary
                }
                .padding(16)
            }
            .ftScreenBackground()
            .navigationTitle("Değiştirerek yedim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet", action: save).bold() }
            }
            .sheet(isPresented: $showSearch) {
                DietFoodPicker(foods: store.foodLibrary(), title: searchForItem == nil ? "Ne yedin?" : "Yerine ne yedin?") { food in
                    let portion = DietPortion(food: food)
                    if let id = searchForItem, let item = meal.items.first(where: { $0.id == id }) {
                        let target = DietUnitTable.equalCalorieAmount(for: item.portion.nutrition.calories, food: food)
                        choices[id] = .swapped(DietPortion(food: food, amount: target.amount, unit: target.unit))
                    } else {
                        extras.append(portion)
                    }
                }
            }
            .onAppear(perform: restore)
        }
    }

    private func choice(for item: DietItem) -> Choice { choices[item.id] ?? .same }

    private func itemRow(_ item: DietItem) -> some View {
        let current = choice(for: item)
        let isSelected = selectedItem == item.id
        return Button {
            Haptics.selection()
            withAnimation(.snappy) { selectedItem = isSelected ? nil : item.id }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.portion.food.name)
                        .font(.subheadline.weight(isSelected ? .bold : .regular))
                        .strikethrough(current == .skipped)
                        .foregroundStyle(current == .skipped ? Color.ftTextSecondary : Color.ftText)
                    if case .swapped(let portion) = current {
                        Text("→ \(portion.label)").font(.caption.weight(.semibold)).foregroundStyle(Color.ftWarning)
                    } else {
                        Text(item.portion.amountText).font(.caption).foregroundStyle(Color.ftTextSecondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Aynen yedim") { choices[item.id] = .same }
                    Button("Değiştirdim") { selectedItem = item.id }
                    Button("Yemedim") { choices[item.id] = .skipped }
                } label: {
                    chip(current)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().opacity(item.id == meal.items.last?.id ? 0 : 1) }
    }

    @ViewBuilder
    private func chip(_ choice: Choice) -> some View {
        switch choice {
        case .same: DietStatusChip(status: .eaten)
        case .swapped: DietStatusChip(status: .changed, filled: true)
        case .skipped: Text("Yemedim").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.ftSubtle(0.12), in: Capsule()).foregroundStyle(Color.ftTextSecondary)
        }
    }

    private func suggestions(for item: DietItem) -> some View {
        let options = alternatives(for: item)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Bunu mu yedin?").font(.title3.bold()).foregroundStyle(Color.ftText)
            Text("\(item.portion.food.name) yerine · \(item.portion.nutrition.kcal) kcal · K \(Int(item.portion.nutrition.carbs.rounded())) g")
                .font(.caption).foregroundStyle(Color.ftTextSecondary)
            if !item.alternatives.isEmpty {
                DietSectionTitle(text: "Programdaki değişimler")
                ForEach(item.alternatives, id: \.self) { portion in option(portion, for: item, badge: "≈ eşdeğer") }
            }
            if !options.isEmpty {
                DietSectionTitle(text: "Benzer değerde")
                ForEach(options, id: \.self) { portion in option(portion, for: item, badge: "yakın") }
            }
            Button {
                searchForItem = item.id
                showSearch = true
            } label: {
                Label("Başka bir şey yedim… ara", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.ftSubtle(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .tint(Color.ftTextSecondary)
        }
    }

    private func option(_ portion: DietPortion, for item: DietItem, badge: String) -> some View {
        let selected = choice(for: item) == .swapped(portion)
        return Button {
            Haptics.selection()
            choices[item.id] = selected ? .same : .swapped(portion)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(portion.food.name) · \(portion.amountText)").font(.subheadline.weight(.semibold)).foregroundStyle(Color.ftText)
                    Text("\(portion.nutrition.kcal) kcal · \(portion.nutrition.macroText)").font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ftAccent).font(.title3)
                } else {
                    Text(badge).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.ftSuccess.opacity(0.15), in: Capsule()).foregroundStyle(Color.ftSuccess)
                }
            }
            .padding(12)
            .background(selected ? Color.ftAccent.opacity(0.08) : Color.ftCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.ftAccent : Color.ftCardBorder, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Aynı reyondan, makro dağılımı en yakın 3 yiyecek (kalorisi eşit miktarda).
    private func alternatives(for item: DietItem) -> [DietPortion] {
        let original = item.portion
        let category = DietShoppingCategory.of(original.food.name)
        let excluded = Set([original.food.key] + item.alternatives.map(\.food.key))
        let profile = original.nutrition
        func distance(_ food: FoodTemplate) -> Double {
            let n = DietNutrition(template: food)
            return MacroKind.allCases.reduce(0) { $0 + abs(n.energyShare(of: $1) - profile.energyShare(of: $1)) }
        }
        return store.foodLibrary()
            .filter { !excluded.contains($0.key) && DietShoppingCategory.of($0.name) == category && $0.calories > 0 }
            .sorted { distance($0) < distance($1) }
            .prefix(3)
            .map { template in
                let food = DietFood(template: template)
                let target = DietUnitTable.equalCalorieAmount(for: profile.calories, food: food)
                return DietPortion(food: food, amount: target.amount, unit: target.unit)
            }
    }

    private var eaten: [DietPortion] {
        meal.items.compactMap { item -> DietPortion? in
            switch choice(for: item) {
            case .same: return item.portion
            case .swapped(let portion): return portion
            case .skipped: return nil
            }
        } + extras
    }

    private var swaps: [String] {
        meal.items.compactMap { item -> String? in
            switch choice(for: item) {
            case .same: return nil
            case .swapped(let portion): return "\(item.portion.food.name) → \(portion.label)"
            case .skipped: return "\(item.portion.food.name) yenmedi"
            }
        } + extras.map { "+ \($0.label)" }
    }

    private var summary: some View {
        let total = DietNutrition.sum(eaten.map(\.nutrition))
        let planned = meal.nutrition
        let ratio = planned.calories > 0 ? 1 - abs(total.calories - planned.calories) / planned.calories : 1
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Öğün: \(planned.kcal) → \(total.kcal) kcal").font(.subheadline.bold()).foregroundStyle(Color.ftText)
                Text(total.macroText).font(.caption).foregroundStyle(Color.ftTextSecondary)
            }
            Spacer()
            Text("plana %\(max(0, Int((ratio * 100).rounded()))) yakın")
                .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.ftSuccess.opacity(0.15), in: Capsule()).foregroundStyle(Color.ftSuccess)
        }
        .padding(12)
        .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 14))
    }

    private func restore() {
        guard choices.isEmpty, let existing, existing.status == .changed else { return }
        note = existing.note
        var remaining = existing.eaten
        for item in meal.items {
            if let index = remaining.firstIndex(where: { $0.food.key == item.portion.food.key }) {
                let portion = remaining.remove(at: index)
                choices[item.id] = portion == item.portion ? .same : .swapped(portion)
            } else if existing.swaps.contains(where: { $0.hasPrefix(item.portion.food.name + " → ") }),
                      let index = remaining.indices.first {
                choices[item.id] = .swapped(remaining.remove(at: index))
            } else {
                choices[item.id] = .skipped
            }
        }
        extras = remaining
    }

    private func save() {
        do {
            let changed = !swaps.isEmpty
            try store.mark(program: program, date: date, meal: meal, status: changed ? .changed : .eaten,
                           eaten: eaten, swaps: swaps, note: note.trimmed.isEmpty ? existing?.note : note)
            dismiss()
        } catch {
            store.present(error)
        }
    }
}

// MARK: - Metin düzenleme

struct DietTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State var text: String
    let placeholder: String
    let onSave: (String) -> Void

    init(title: String, text: String, placeholder: String, onSave: @escaping (String) -> Void) {
        self.title = title
        _text = State(initialValue: text)
        self.placeholder = placeholder
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { onSave(text); dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
