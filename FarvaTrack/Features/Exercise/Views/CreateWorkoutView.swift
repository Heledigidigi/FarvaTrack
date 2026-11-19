import SwiftUI

struct CreateWorkoutView: View {
    let viewModel: ExerciseViewModel
    let workout: Workout?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutDraft
    @State private var initialDraft: WorkoutDraft
    @State private var showPicker = false
    @State private var showDiscardConfirmation = false
    @State private var errorMessage: String?

    init(viewModel: ExerciseViewModel, workout: Workout?) {
        self.viewModel = viewModel
        self.workout = workout
        let start = workout.map(WorkoutDraft.init(workout:)) ?? WorkoutDraft()
        _draft = State(initialValue: start)
        _initialDraft = State(initialValue: start)
    }

    private var hasChanges: Bool { draft != initialDraft }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Genel") {
                    TextField("Antrenman adı (isteğe bağlı)", text: $draft.title)
                    DatePicker(
                        "Tarih",
                        selection: $draft.date,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                }

                Section {
                    ForEach($draft.entries) { $entry in
                        EntryEditor(entry: $entry)
                    }
                    .onDelete { draft.entries.remove(atOffsets: $0) }
                    .onMove { draft.entries.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        showPicker = true
                    } label: {
                        Label("Egzersiz ekle", systemImage: "plus.circle.fill")
                    }
                } header: {
                    HStack {
                        Text("Egzersizler")
                        Spacer()
                        if draft.entries.count > 1 { EditButton() }
                    }
                } footer: {
                    if !draft.entries.isEmpty {
                        let minutes = Int(draft.estimatedMinutes.rounded())
                        let calories = Int(draft.estimatedCalories(weightKg: viewModel.weightKg).rounded())
                        Text("Tahmini: \(minutes) dk • \(calories) kcal. Kalori; egzersizin MET değeri ve profilindeki kilo (\(viewModel.weightKg.formatted(.number.precision(.fractionLength(0...1)))) kg) ile hesaplanır, gerçek değerden farklı olabilir.")
                    }
                }

                Section("Not") {
                    TextField("Notlar (isteğe bağlı)", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle(workout == nil ? "Yeni Antrenman" : "Antrenmanı Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .fontWeight(.semibold)
                        .disabled(!draft.isValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Bitti") { hideKeyboard() }
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView(viewModel: viewModel) { template in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        draft.entries.append(DraftEntry(template: template))
                    }
                }
            }
            .confirmationDialog("Değişiklikler silinsin mi?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Değişiklikleri Sil", role: .destructive) { dismiss() }
                Button("Düzenlemeye Devam Et", role: .cancel) {}
            }
            .alert("Kaydedilemedi", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    private func cancel() {
        if hasChanges {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func save() {
        do {
            try viewModel.save(draft, editing: workout)
            dismiss()
        } catch {
            errorMessage = AppError.map(error).errorDescription
            Haptics.error()
        }
    }
}

// MARK: - Egzersiz satırı düzenleyici
private struct EntryEditor: View {
    @Binding var entry: DraftEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: entry.template.category.systemImage)
                    .foregroundStyle(entry.template.category.tint)
                    .frame(width: 30, height: 30)
                    .background(entry.template.category.tint.opacity(0.18), in: Circle())
                    .accessibilityHidden(true)
                Text(entry.template.name)
                    .font(.headline)
                Spacer()
            }

            switch entry.template.mode {
            case .sets: setsEditor
            case .duration: durationEditor
            }
        }
        .padding(.vertical, 6)
    }

    private var durationEditor: some View {
        Stepper(value: $entry.durationMinutes, in: 1...300, step: 5) {
            Text("\(Int(entry.durationMinutes)) dakika")
                .monospacedDigit()
        }
    }

    private var setsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($entry.sets) { $set in
                HStack(spacing: 8) {
                    Text("Set \(index(of: set))")
                        .font(.subheadline)
                        .foregroundStyle(Color.ftTextSecondary)
                        .frame(width: 48, alignment: .leading)

                    numberField("Tekrar", value: $set.reps)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Set \(index(of: set)) tekrar sayısı")

                    Text("×").foregroundStyle(Color.ftTextSecondary)

                    numberField("0", value: $set.weightKg)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Set \(index(of: set)) ağırlık, kilogram")

                    Text("kg").font(.subheadline).foregroundStyle(Color.ftTextSecondary)

                    Spacer(minLength: 0)

                    if entry.sets.count > 1 {
                        Button(role: .destructive) {
                            withAnimation { entry.sets.removeAll { $0.id == set.id } }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Seti sil")
                    }
                }
            }

            Button {
                Haptics.selection()
                withAnimation {
                    let last = entry.sets.last ?? WorkoutSet(reps: 10, weightKg: 0)
                    entry.sets.append(WorkoutSet(reps: last.reps, weightKg: last.weightKg))
                }
            } label: {
                Label("Set ekle", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
    }

    private func index(of set: WorkoutSet) -> Int {
        (entry.sets.firstIndex { $0.id == set.id } ?? 0) + 1
    }

    private func numberField<T>(_ placeholder: String, value: Binding<T>) -> some View
    where T: Numeric, T: Comparable, T.Magnitude: Comparable {
        // Int ve Double için ayrı formatlama aşağıdaki overload'larla yapılır.
        EmptyView()
    }

    private func numberField(_ placeholder: String, value: Binding<Int>) -> some View {
        TextField(placeholder, value: value, format: .number)
            .multilineTextAlignment(.center)
            .frame(width: 64)
            .padding(.vertical, 6)
            .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func numberField(_ placeholder: String, value: Binding<Double>) -> some View {
        TextField(placeholder, value: value, format: .number)
            .multilineTextAlignment(.center)
            .frame(width: 72)
            .padding(.vertical, 6)
            .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
Not: EntryEditor içindeki jenerik numberField<T> taslağı gereksiz kalmış. Derleme sırasında overload belirsizliği çıkarabilir. O jenerik fonksiyonu (private func numberField<T>... { EmptyView() } bloğunu) silin, yalnızca Int ve Double için olan iki fonksiyon kalsın.