import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    let viewModel: ExerciseViewModel
    let onSelect: (ExerciseTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var category: ExerciseCategory?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CategoryChips(selected: $category)
                    .padding(.vertical, 8)

                if let ownerID = viewModel.currentUserID {
                    PickerList(
                        ownerID: ownerID,
                        searchText: searchText,
                        category: category,
                        viewModel: viewModel,
                        onSelect: { template in
                            onSelect(template)
                            dismiss()
                        }
                    )
                } else {
                    ProgressView().frame(maxHeight: .infinity)
                }
            }
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle("Egzersiz Seç")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Egzersiz ara")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

private struct PickerList: View {
    @Query private var custom: [Exercise]

    let searchText: String
    let category: ExerciseCategory?
    let viewModel: ExerciseViewModel
    let onSelect: (ExerciseTemplate) -> Void

    init(
        ownerID: String,
        searchText: String,
        category: ExerciseCategory?,
        viewModel: ExerciseViewModel,
        onSelect: @escaping (ExerciseTemplate) -> Void
    ) {
        _custom = Query(filter: #Predicate<Exercise> { $0.ownerID == ownerID }, sort: \.name)
        self.searchText = searchText
        self.category = category
        self.viewModel = viewModel
        self.onSelect = onSelect
    }

    private func matches(_ template: ExerciseTemplate) -> Bool {
        let query = searchText.trimmed
        let matchesCategory = category.map { $0 == template.category } ?? true
        let matchesSearch = query.isEmpty || template.name.localizedCaseInsensitiveContains(query)
        return matchesCategory && matchesSearch
    }

    var body: some View {
        let mine = custom.filter { matches($0.template) }
        let library = ExerciseLibrary.presets.filter(matches)

        List {
            Section {
                NavigationLink {
                    CreateExerciseView(viewModel: viewModel, onCreated: onSelect)
                } label: {
                    Label("Yeni egzersiz oluştur", systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.ftAccentLight)
                }
                .listRowBackground(Color.ftCard)
            }

            if !mine.isEmpty {
                Section("Özel Egzersizlerim") {
                    ForEach(mine) { exercise in
                        row(for: exercise.template)
                            .swipeActions {
                                Button(role: .destructive) {
                                    viewModel.deleteCustomExercise(exercise)
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            if !library.isEmpty {
                Section("Kütüphane") {
                    ForEach(library) { template in
                        row(for: template)
                    }
                }
            }

            if mine.isEmpty && library.isEmpty {
                ContentUnavailableView.search(text: searchText.trimmed)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(for template: ExerciseTemplate) -> some View {
        Button {
            Haptics.selection()
            onSelect(template)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: template.category.systemImage)
                    .foregroundStyle(template.category.tint)
                    .frame(width: 36, height: 36)
                    .background(template.category.tint.opacity(0.18), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                    Text("\(template.category.title) • \(template.mode.title)")
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.ftAccentLight)
            }
        }
        .listRowBackground(Color.ftCard)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Antrenmana ekler")
    }
}

// MARK: - Özel egzersiz oluşturma
struct CreateExerciseView: View {
    let viewModel: ExerciseViewModel
    let onCreated: (ExerciseTemplate) -> Void

    @State private var name = ""
    @State private var category: ExerciseCategory = .strength
    @State private var mode: TrackingMode = .sets
    @State private var intensity: ExerciseIntensity = .moderate
    @State private var errorMessage: String?

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        Form {
            Section("Egzersiz") {
                TextField("Ad", text: $name)
                    .textInputAutocapitalization(.sentences)

                Picker("Kategori", selection: $category) {
                    ForEach(ExerciseCategory.allCases) { item in
                        Label(item.title, systemImage: item.systemImage).tag(item)
                    }
                }
            }

            Section {
                Picker("Takip şekli", selection: $mode) {
                    ForEach(TrackingMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Nasıl takip edilsin?")
            } footer: {
                Text(mode == .sets
                     ? "Her set için tekrar sayısı ve ağırlık girersin."
                     : "Yalnızca süreyi girersin.")
            }

            Section {
                Picker("Yoğunluk", selection: $intensity) {
                    ForEach(ExerciseIntensity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Yoğunluk")
            } footer: {
                Text("Yakılan kalori tahmininde kullanılır.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Yeni Egzersiz")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") { save() }
                    .fontWeight(.semibold)
                    .disabled(name.trimmed.count < 2)
            }
        }
        .alert("Kaydedilemedi", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        do {
            let template = try viewModel.createCustomExercise(
                name: name,
                category: category,
                mode: mode,
                intensity: intensity
            )
            onCreated(template)
        } catch {
            errorMessage = AppError.map(error).errorDescription
            Haptics.error()
        }
    }
}
