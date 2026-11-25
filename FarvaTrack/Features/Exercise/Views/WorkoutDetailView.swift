import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout
    let viewModel: ExerciseViewModel
    var onSaveAsTemplate: ((Workout) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    @State private var showDeleteConfirmation = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                LazyVGrid(columns: columns, spacing: 12) {
                    StatCard(
                        title: "Süre",
                        value: Int(workout.durationMinutes.rounded()).formatted(),
                        unit: "dk",
                        systemImage: "clock.fill",
                        tint: Color.ftSleep
                    )
                    StatCard(
                        title: "Kalori",
                        value: Int(workout.caloriesBurned.rounded()).formatted(),
                        unit: "kcal",
                        systemImage: "flame.fill",
                        tint: Color.ftCalories,
                        subtitle: "Tahmini değer"
                    )
                    StatCard(
                        title: "Egzersiz",
                        value: "\(workout.entries.count)",
                        systemImage: "list.bullet",
                        tint: Color.ftExercise
                    )
                    StatCard(
                        title: "Hacim",
                        value: workout.totalVolumeKg > 0 ? Int(workout.totalVolumeKg.rounded()).formatted() : "—",
                        unit: workout.totalVolumeKg > 0 ? "kg" : "",
                        systemImage: "scalemass.fill",
                        tint: Color.ftWeight,
                        subtitle: "Toplam kaldırılan"
                    )
                }

                VStack(spacing: 12) {
                    ForEach(workout.sortedEntries) { entry in
                        EntryCard(entry: entry)
                    }
                }

                if !workout.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notlar").font(.headline)
                        Text(workout.notes)
                            .font(.body)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
            }
            .padding(Constants.Layout.screenPadding)
        }
        .ftScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showEditor = true } label: { Label("Düzenle", systemImage: "pencil") }
                    Button { viewModel.duplicate(workout) } label: { Label("Bugüne tekrarla", systemImage: "doc.on.doc") }
                    if let onSaveAsTemplate {
                        Button { onSaveAsTemplate(workout) } label: { Label("Şablon olarak kaydet", systemImage: "square.on.square") }
                    }
                    Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("Sil", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Seçenekler")
            }
        }
        .sheet(isPresented: $showEditor) {
            CreateWorkoutView(viewModel: viewModel, workout: workout)
        }
        .confirmationDialog("Bu antrenman silinsin mi?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { deleteAndClose() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bu işlem geri alınamaz.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(workout.title)
                .font(.title.bold())
            Text(workout.date.formatted(
                .dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "tr_TR"))
            ))
            .font(.subheadline)
            .foregroundStyle(Color.ftTextSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Önce ekranı kapatır, silmeyi geçiş animasyonundan sonra yapar.
    /// Silinmiş bir SwiftData nesnesine ekran görünürken erişmek çökmeye yol açabilir.
    private func deleteAndClose() {
        let target = workout
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            viewModel.delete(target)
        }
    }
}

private struct EntryCard: View {
    let entry: WorkoutEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: entry.category.systemImage)
                    .foregroundStyle(entry.category.tint)
                    .frame(width: 34, height: 34)
                    .background(entry.category.tint.opacity(0.18), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.headline)
                    Text(entry.category.title)
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                Spacer()
                Text(entry.summaryText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.ftTextSecondary)
            }

            if entry.mode == .sets {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("Set")
                        Text("Tekrar")
                        Text("Ağırlık")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.ftTextSecondary)

                    ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, item in
                        GridRow {
                            Text("\(index + 1)")
                            Text("\(item.reps)")
                            Text(item.weightKg > 0
                                 ? "\(item.weightKg.formatted(.number.precision(.fractionLength(0...1)))) kg"
                                 : "Vücut ağırlığı")
                        }
                        .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
