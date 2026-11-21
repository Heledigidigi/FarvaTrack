import SwiftUI
import SwiftData

/// Programlar, şablonlar ve hazır programlar.
struct ProgramsView: View {
    @Environment(AuthViewModel.self) private var auth
    let training: TrainingViewModel
    let exerciseViewModel: ExerciseViewModel

    var body: some View {
        Group {
            if let user = auth.currentUser {
                ProgramsContent(ownerID: user.id, training: training, exerciseViewModel: exerciseViewModel)
            } else {
                ProgressView()
            }
        }
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Programlar")
        .alert("Bir sorun oluştu", isPresented: Binding(get: { training.hasError }, set: { training.hasError = $0 })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(training.errorMessage ?? "")
        }
    }
}

struct TemplateEditorTarget: Identifiable {
    let template: WorkoutTemplate?
    let id = UUID()
}

struct ProgramEditorTarget: Identifiable {
    let program: TrainingProgram?
    let id = UUID()
}

private struct ProgramsContent: View {
    @Query private var programs: [TrainingProgram]
    @Query private var templates: [WorkoutTemplate]
    let training: TrainingViewModel
    let exerciseViewModel: ExerciseViewModel

    @State private var templateEditor: TemplateEditorTarget?
    @State private var programEditor: ProgramEditorTarget?
    @State private var presetToAdopt: PresetProgram?
    @State private var programToDelete: TrainingProgram?
    @State private var templateToDelete: WorkoutTemplate?

    init(ownerID: String, training: TrainingViewModel, exerciseViewModel: ExerciseViewModel) {
        _programs = Query(filter: #Predicate<TrainingProgram> { $0.ownerID == ownerID }, sort: \.createdAt)
        _templates = Query(filter: #Predicate<WorkoutTemplate> { $0.ownerID == ownerID }, sort: \.name)
        self.training = training
        self.exerciseViewModel = exerciseViewModel
    }

    private var templateNames: [String: String] {
        Dictionary(templates.map { ($0.id.uuidString, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        List {
            Section {
                if programs.isEmpty {
                    Text("Henüz programın yok. Aşağıdaki hazır programlardan birini kullanabilir ya da kendi programını oluşturabilirsin.")
                        .font(.subheadline)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                ForEach(programs) { program in
                    ProgramRow(program: program, templateNames: templateNames) {
                        training.setActive(program.isActive ? nil : program)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { programEditor = ProgramEditorTarget(program: program) }
                    .swipeActions {
                        Button(role: .destructive) { programToDelete = program } label: { Label("Sil", systemImage: "trash") }
                    }
                }
                Button {
                    programEditor = ProgramEditorTarget(program: nil)
                } label: {
                    Label("Yeni program", systemImage: "plus")
                }
                .disabled(templates.isEmpty)
            } header: {
                Text("Programlarım")
            } footer: {
                Text(templates.isEmpty ? "Program oluşturmak için önce bir şablon ekle." : "Aynı anda bir program aktif olur. Program olmadan da istediğin zaman serbest antrenman ekleyebilirsin.")
            }
            .listRowBackground(Color.ftCard)

            Section {
                ForEach(templates) { template in
                    Button {
                        templateEditor = TemplateEditorTarget(template: template)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                            Text(template.summaryText).font(.caption).foregroundStyle(Color.ftTextSecondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { templateToDelete = template } label: { Label("Sil", systemImage: "trash") }
                    }
                }
                Button {
                    templateEditor = TemplateEditorTarget(template: nil)
                } label: {
                    Label("Yeni şablon", systemImage: "plus")
                }
            } header: {
                Text("Şablonlarım")
            } footer: {
                Text("Geçmiş bir antrenmanı da detay ekranındaki menüden şablon olarak kaydedebilirsin.")
            }
            .listRowBackground(Color.ftCard)

            Section("Hazır Programlar") {
                ForEach(PresetPrograms.all) { preset in
                    Button {
                        presetToAdopt = preset
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(preset.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Spacer()
                                Text(preset.level)
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.ftExercise.opacity(0.2), in: Capsule())
                                    .foregroundStyle(Color.ftExercise)
                            }
                            Text(preset.summary).font(.caption).foregroundStyle(Color.ftTextSecondary)
                            Text(preset.days.map(\.name).joined(separator: " • "))
                                .font(.caption2)
                                .foregroundStyle(Color.ftTextSecondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .listRowBackground(Color.ftCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .sheet(item: $templateEditor) { target in
            TemplateEditorView(training: training, exerciseViewModel: exerciseViewModel, template: target.template)
        }
        .sheet(item: $programEditor) { target in
            ProgramEditorView(training: training, templates: templates, program: target.program)
        }
        .confirmationDialog(
            presetToAdopt.map { "\($0.name) hesabına eklensin mi?" } ?? "",
            isPresented: Binding(get: { presetToAdopt != nil }, set: { if !$0 { presetToAdopt = nil } }),
            titleVisibility: .visible,
            presenting: presetToAdopt
        ) { preset in
            Button("Ekle ve aktif yap") {
                do { try training.adopt(preset) } catch { training.errorMessage = AppError.map(error).errorDescription }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { preset in
            Text("\(preset.days.count) şablon oluşturulur; ağırlıkları ve egzersizleri sonra düzenleyebilirsin.")
        }
        .confirmationDialog(
            "Program silinsin mi?",
            isPresented: Binding(get: { programToDelete != nil }, set: { if !$0 { programToDelete = nil } }),
            titleVisibility: .visible,
            presenting: programToDelete
        ) { program in
            Button("Sil", role: .destructive) { training.deleteProgram(program) }
        } message: { _ in
            Text("Şablonların ve geçmiş antrenmanların silinmez.")
        }
        .confirmationDialog(
            "Şablon silinsin mi?",
            isPresented: Binding(get: { templateToDelete != nil }, set: { if !$0 { templateToDelete = nil } }),
            titleVisibility: .visible,
            presenting: templateToDelete
        ) { template in
            Button("Sil", role: .destructive) { training.deleteTemplate(template) }
        } message: { _ in
            Text("Bu şablonu kullanan programlardan da çıkarılır. Geçmiş antrenmanların silinmez.")
        }
    }
}

private struct ProgramRow: View {
    let program: TrainingProgram
    let templateNames: [String: String]
    let onToggleActive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.name).font(.subheadline.weight(.semibold))
                    Text(program.kind.title).font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
                Spacer()
                Button(action: onToggleActive) {
                    Text(program.isActive ? "Aktif" : "Aktif yap")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(program.isActive ? Color.ftSuccess.opacity(0.2) : Color.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(program.isActive ? Color.ftSuccess : Color.ftTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(program.isActive ? "Aktif program, pasif yapmak için dokun" : "Aktif yap")
            }

            switch program.kind {
            case .weekly:
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { index in
                        let id = TrainingProgram.normalizedWeek(program.weekdayTemplateIDs)[index]
                        VStack(spacing: 2) {
                            Text(ProgramPlanner.weekdayShortNames[index]).font(.caption2.weight(.semibold))
                            Circle()
                                .fill(id.isEmpty ? Color.white.opacity(0.1) : Color.ftExercise)
                                .frame(width: 8, height: 8)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(ProgramPlanner.weekdayNames[index]): \(templateNames[id] ?? "dinlenme")")
                    }
                }
            case .rotation:
                Text(program.rotationTemplateIDs.compactMap { templateNames[$0] }.joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(Color.ftTextSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Şablon düzenleyici
struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let training: TrainingViewModel
    let exerciseViewModel: ExerciseViewModel
    let template: WorkoutTemplate?

    @State private var name: String
    @State private var exercises: [TemplateExercise]
    @State private var showPicker = false
    @State private var error: String?

    init(training: TrainingViewModel, exerciseViewModel: ExerciseViewModel, template: WorkoutTemplate?, initialName: String = "", initialExercises: [TemplateExercise] = []) {
        self.training = training
        self.exerciseViewModel = exerciseViewModel
        self.template = template
        _name = State(initialValue: template?.name ?? initialName)
        _exercises = State(initialValue: template?.exercises ?? initialExercises)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Şablon adı (ör. İtiş Günü)", text: $name)
                }

                Section {
                    ForEach($exercises) { $item in
                        TemplateExerciseRow(item: $item)
                    }
                    .onDelete { exercises.remove(atOffsets: $0) }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        showPicker = true
                    } label: {
                        Label("Egzersiz ekle", systemImage: "plus.circle.fill")
                    }
                    .disabled(exercises.count >= TrainingViewModel.maxExercises)
                } header: {
                    Text("Egzersizler")
                } footer: {
                    Text("Sıralamak için sağ üstteki Düzenle'ye bas. Ağırlığı boş bırakırsan canlı modda geçen seferki ağırlık kullanılır.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle(template == nil ? "Yeni Şablon" : "Şablonu Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(exercises.isEmpty || name.trimmed.isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView(viewModel: exerciseViewModel) { picked in
                    exercises.append(TemplateExercise(template: picked))
                }
            }
            .alert("Kaydedilemedi", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func save() {
        do {
            try training.saveTemplate(name: name, exercises: exercises, editing: template)
            dismiss()
        } catch {
            self.error = AppError.map(error).errorDescription
            Haptics.error()
        }
    }
}

private struct TemplateExerciseRow: View {
    @Binding var item: TemplateExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(item.name, systemImage: item.category.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.category.tint)

            if item.mode == .sets {
                Stepper(value: $item.targetSets, in: TemplateExercise.setRange) {
                    Text("\(item.targetSets) set").monospacedDigit()
                }
                Stepper(value: $item.targetReps, in: TemplateExercise.repRange) {
                    Text("\(item.targetReps) tekrar").monospacedDigit()
                }
                HStack {
                    Text("Hedef ağırlık")
                    Spacer()
                    TextField("geçen sefer", value: $item.targetWeightKg, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("kg").foregroundStyle(Color.ftTextSecondary)
                }
                Picker("Dinlenme", selection: $item.restSeconds) {
                    ForEach(TemplateExercise.restOptions, id: \.self) { seconds in
                        Text(seconds < 60 ? "\(seconds) sn" : (seconds % 60 == 0 ? "\(seconds / 60) dk" : "\(seconds / 60) dk \(seconds % 60) sn")).tag(seconds)
                    }
                }
            } else {
                Stepper(value: $item.durationMinutes, in: 1...300, step: 1) {
                    Text("\(Int(item.durationMinutes)) dk").monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Program düzenleyici
struct ProgramEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let training: TrainingViewModel
    let templates: [WorkoutTemplate]
    let program: TrainingProgram?

    @State private var name: String
    @State private var kind: ProgramKind
    @State private var weekly: [String]
    @State private var rotation: [String]
    @State private var activate: Bool
    @State private var error: String?

    init(training: TrainingViewModel, templates: [WorkoutTemplate], program: TrainingProgram?) {
        self.training = training
        self.templates = templates
        self.program = program
        _name = State(initialValue: program?.name ?? "")
        _kind = State(initialValue: program?.kind ?? .weekly)
        _weekly = State(initialValue: TrainingProgram.normalizedWeek(program?.weekdayTemplateIDs ?? []))
        _rotation = State(initialValue: program?.rotationTemplateIDs ?? [])
        _activate = State(initialValue: program?.isActive ?? true)
    }

    private func templateName(_ id: String) -> String {
        templates.first { $0.id.uuidString == id }?.name ?? "Silinmiş şablon"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Program adı", text: $name)
                    Picker("Tür", selection: $kind) {
                        ForEach(ProgramKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(kind.detail)
                }

                switch kind {
                case .weekly:
                    Section("Haftanın günleri") {
                        ForEach(0..<7, id: \.self) { index in
                            Picker(ProgramPlanner.weekdayNames[index], selection: $weekly[index]) {
                                Text("Dinlenme").tag("")
                                ForEach(templates) { Text($0.name).tag($0.id.uuidString) }
                            }
                        }
                    }
                case .rotation:
                    Section {
                        ForEach(Array(rotation.enumerated()), id: \.offset) { index, id in
                            HStack {
                                Text("\(index + 1).").monospacedDigit().foregroundStyle(Color.ftTextSecondary)
                                Text(templateName(id))
                            }
                        }
                        .onDelete { rotation.remove(atOffsets: $0) }
                        .onMove { rotation.move(fromOffsets: $0, toOffset: $1) }

                        Menu {
                            ForEach(templates) { template in
                                Button(template.name) { rotation.append(template.id.uuidString) }
                            }
                        } label: {
                            Label("Döngüye şablon ekle", systemImage: "plus.circle.fill")
                        }
                    } header: {
                        Text("Sıra")
                    } footer: {
                        Text("Her antrenmandan sonra sıradaki şablon önerilir; son şablondan sonra başa döner.")
                    }
                }

                Section {
                    Toggle("Aktif program yap", isOn: $activate)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle(program == nil ? "Yeni Program" : "Programı Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                }
                if kind == .rotation {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            .alert("Kaydedilemedi", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func save() {
        do {
            let saved = try training.saveProgram(
                name: name, kind: kind, weekly: weekly, rotation: rotation,
                editing: program, activate: activate
            )
            if !activate && saved.isActive { training.setActive(nil) }
            dismiss()
        } catch {
            self.error = AppError.map(error).errorDescription
            Haptics.error()
        }
    }
}
