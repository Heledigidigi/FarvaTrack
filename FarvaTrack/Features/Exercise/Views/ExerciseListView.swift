import SwiftUI
import SwiftData

struct WorkoutComposerTarget: Identifiable {
    let workout: Workout?
    var id: String { workout?.id.uuidString ?? "new" }
}

struct ExerciseListView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = ExerciseViewModel()
    @State private var searchText = ""
    @State private var selectedCategory: ExerciseCategory?
    @State private var composerTarget: WorkoutComposerTarget?
    @State private var workoutToDelete: Workout?

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { workoutToDelete != nil }, set: { if !$0 { workoutToDelete = nil } })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let user = auth.currentUser {
                    VStack(spacing: 0) {
                        CategoryChips(selected: $selectedCategory)
                            .padding(.vertical, 8)

                        WorkoutListContent(
                            ownerID: user.id,
                            searchText: searchText,
                            category: selectedCategory,
                            onCreate: { composerTarget = WorkoutComposerTarget(workout: nil) },
                            onEdit: { composerTarget = WorkoutComposerTarget(workout: $0) },
                            onDuplicate: { viewModel.duplicate($0) },
                            onDelete: { workoutToDelete = $0 }
                        )
                    }
                } else {
                    ProgressView()
                }
            }
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle("Egzersiz")
            .searchable(text: $searchText, prompt: "Antrenman veya egzersiz ara")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.impact(.light)
                        composerTarget = WorkoutComposerTarget(workout: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Yeni antrenman")
                }
            }
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(workout: workout, viewModel: viewModel)
            }
            .sheet(item: $composerTarget) { target in
                CreateWorkoutView(viewModel: viewModel, workout: target.workout)
            }
            .confirmationDialog(
                "Bu antrenman silinsin mi?",
                isPresented: deleteBinding,
                titleVisibility: .visible,
                presenting: workoutToDelete
            ) { workout in
                Button("Sil", role: .destructive) { viewModel.delete(workout) }
                Button("Vazgeç", role: .cancel) {}
            } message: { _ in
                Text("Bu işlem geri alınamaz.")
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

// MARK: - Liste içeriği (@Query burada, kullanıcıya göre süzülür)
private struct WorkoutListContent: View {
    @Query private var workouts: [Workout]

    let searchText: String
    let category: ExerciseCategory?
    let onCreate: () -> Void
    let onEdit: (Workout) -> Void
    let onDuplicate: (Workout) -> Void
    let onDelete: (Workout) -> Void

    init(
        ownerID: String,
        searchText: String,
        category: ExerciseCategory?,
        onCreate: @escaping () -> Void,
        onEdit: @escaping (Workout) -> Void,
        onDuplicate: @escaping (Workout) -> Void,
        onDelete: @escaping (Workout) -> Void
    ) {
        _workouts = Query(
            filter: #Predicate<Workout> { $0.ownerID == ownerID },
            sort: \.date,
            order: .reverse
        )
        self.searchText = searchText
        self.category = category
        self.onCreate = onCreate
        self.onEdit = onEdit
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
    }

    private struct DaySection: Identifiable {
        let day: Date
        let workouts: [Workout]
        var id: Date { day }
    }

    private var filtered: [Workout] {
        let query = searchText.trimmed
        return workouts.filter { workout in
            let matchesCategory = category.map { selected in
                workout.entries.contains { $0.categoryRaw == selected.rawValue }
            } ?? true
            let matchesSearch = query.isEmpty
                || workout.title.localizedCaseInsensitiveContains(query)
                || workout.entries.contains { $0.name.localizedCaseInsensitiveContains(query) }
            return matchesCategory && matchesSearch
        }
    }

    private var sections: [DaySection] {
        Dictionary(grouping: filtered) { $0.date.startOfDay }
            .map { DaySection(day: $0.key, workouts: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private var weekStats: WorkoutStats {
        let since = Calendar.current.date(byAdding: .day, value: -6, to: Date.now.startOfDay) ?? .distantPast
        return WorkoutStats(workouts: workouts.filter { $0.date >= since })
    }

    var body: some View {
        if workouts.isEmpty {
            ContentUnavailableView {
                Label("Henüz antrenman yok", systemImage: "dumbbell.fill")
            } description: {
                Text("İlk antrenmanını ekleyerek takibe başla.")
            } actions: {
                Button("Antrenman Ekle", action: onCreate)
                    .buttonStyle(.borderedProminent)
            }
        } else if filtered.isEmpty {
            if searchText.trimmed.isEmpty {
                ContentUnavailableView(
                    "Sonuç yok",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Bu filtreye uygun antrenman bulunamadı.")
                )
            } else {
                ContentUnavailableView.search(text: searchText.trimmed)
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                WeeklySummaryCard(stats: weekStats)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(sections) { section in
                Section {
                    ForEach(section.workouts) { workout in
                        NavigationLink(value: workout) {
                            WorkoutRow(workout: workout)
                        }
                        .listRowBackground(Color.ftCard)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete(workout)
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                            Button {
                                onEdit(workout)
                            } label: {
                                Label("Düzenle", systemImage: "pencil")
                            }
                            .tint(Color.ftWater)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                onDuplicate(workout)
                            } label: {
                                Label("Tekrarla", systemImage: "doc.on.doc")
                            }
                            .tint(Color.ftSuccess)
                        }
                        .contextMenu {
                            Button { onEdit(workout) } label: { Label("Düzenle", systemImage: "pencil") }
                            Button { onDuplicate(workout) } label: { Label("Bugüne tekrarla", systemImage: "doc.on.doc") }
                            Button(role: .destructive) { onDelete(workout) } label: { Label("Sil", systemImage: "trash") }
                        }
                    }
                } header: {
                    Text(dayTitle(section.day))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Bugün" }
        if Calendar.current.isDateInYesterday(day) { return "Dün" }
        return day.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(Locale(identifier: "tr_TR")))
    }
}

// MARK: - Haftalık özet
private struct WeeklySummaryCard: View {
    let stats: WorkoutStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Son 7 Gün")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack {
                metric("\(stats.count)", "antrenman", "dumbbell.fill", Color.ftExercise)
                metric(Int(stats.minutes.rounded()).formatted(), "dakika", "clock.fill", Color.ftSleep)
                metric(Int(stats.calories.rounded()).formatted(), "kcal", "flame.fill", Color.ftCalories)
            }
        }
        .cardStyle(padding: 18)
    }

    private func metric(_ value: String, _ label: String, _ systemImage: String, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Satır
private struct WorkoutRow: View {
    let workout: Workout

    private var primaryCategory: ExerciseCategory {
        workout.categories.first ?? .other
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: primaryCategory.systemImage)
                .font(.title3)
                .foregroundStyle(primaryCategory.tint)
                .frame(width: 44, height: 44)
                .background(primaryCategory.tint.opacity(0.18), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(workout.date.formatted(date: .omitted, time: .shortened)) • \(Int(workout.durationMinutes.rounded())) dk • \(Int(workout.caloriesBurned.rounded())) kcal")
                    .font(.caption)
                    .foregroundStyle(Color.ftTextSecondary)
                Text("\(workout.entries.count) egzersiz")
                    .font(.caption2)
                    .foregroundStyle(Color.ftTextSecondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
