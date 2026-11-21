import SwiftUI

/// Salonda canlı mod: setleri işaretle, dinlenme sayacı otomatik başlar.
struct LiveWorkoutView: View {
    @Environment(LiveWorkoutViewModel.self) private var live
    @Environment(\.dismiss) private var dismiss
    let exerciseViewModel: ExerciseViewModel

    @State private var showFinishOptions = false
    @State private var showDiscard = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let session = live.session {
                    content(session)
                } else {
                    ContentUnavailableView("Antrenman yok", systemImage: "dumbbell")
                }
            }
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle(live.session?.title ?? "Antrenman")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Küçült") { dismiss() }
                        .accessibilityHint("Antrenman arka planda devam eder")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitir") { showFinishOptions = true }
                        .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let session = live.session, session.restEndsAt != nil {
                    RestTimerBar(session: session)
                }
            }
            .confirmationDialog("Antrenmanı bitir", isPresented: $showFinishOptions, titleVisibility: .visible) {
                Button("İşaretlediğim setleri kaydet") { finish(asPlanned: false) }
                Button("Plandaki gibi tamamladım") { finish(asPlanned: true) }
                Button("Antrenmanı iptal et", role: .destructive) { showDiscard = true }
                Button("Devam et", role: .cancel) {}
            }
            .alert("Antrenman iptal edilsin mi?", isPresented: $showDiscard) {
                Button("İptal et", role: .destructive) {
                    live.discard()
                    dismiss()
                }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("İşaretlediğin setler kaydedilmeyecek.")
            }
            .alert("Kaydedilemedi", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(localError ?? "")
            }
        }
    }

    // MARK: - İçerik
    private func content(_ session: LiveSession) -> some View {
        let progress = session.progress
        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(progress.done)/\(progress.total) tamamlandı")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(session.startedAt, style: .timer)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.ftTextSecondary)
                            .accessibilityLabel("Geçen süre")
                    }
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .tint(Color.ftExercise)
                }
                .listRowBackground(Color.ftCard)
            }

            ForEach(session.exercises) { item in
                Section {
                    if item.exercise.mode == .sets {
                        ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
                            SetRow(index: index, set: set, previous: item.previousText(at: index), exerciseID: item.id)
                                .listRowBackground(set.isDone ? Color.ftExercise.opacity(0.12) : Color.ftCard)
                                .swipeActions {
                                    if item.sets.count > 1 {
                                        Button(role: .destructive) {
                                            live.removeSet(exerciseID: item.id, setID: set.id)
                                        } label: {
                                            Label("Sil", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                        Button {
                            live.addSet(exerciseID: item.id)
                        } label: {
                            Label("Set ekle", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                        .listRowBackground(Color.ftCard)
                    } else {
                        DurationRow(item: item)
                            .listRowBackground(item.isDurationDone ? Color.ftExercise.opacity(0.12) : Color.ftCard)
                    }
                } header: {
                    HStack {
                        Label(item.exercise.name, systemImage: item.exercise.category.systemImage)
                            .foregroundStyle(item.isComplete ? Color.ftSuccess : Color.ftTextSecondary)
                        ExerciseGuideButton(key: item.exercise.exerciseKey, name: item.exercise.name, category: item.exercise.category)
                        Spacer()
                        if item.exercise.mode == .sets {
                            Text("Dinlenme \(item.exercise.restSeconds) sn")
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func finish(asPlanned: Bool) {
        do {
            let draft = try live.finishDraft(asPlanned: asPlanned)
            try exerciseViewModel.save(draft)
            live.end()
            dismiss()
        } catch {
            localError = AppError.map(error).errorDescription
            Haptics.error()
        }
    }
}

// MARK: - Set satırı
private struct SetRow: View {
    @Environment(LiveWorkoutViewModel.self) private var live
    let index: Int
    let set: LiveSet
    let previous: String?
    let exerciseID: UUID

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.headline.monospacedDigit())
                .frame(width: 22)
                .foregroundStyle(Color.ftTextSecondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TextField("kg", value: Binding(
                        get: { set.weightKg },
                        set: { live.updateSet(exerciseID: exerciseID, setID: set.id, weightKg: $0) }
                    ), format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .accessibilityLabel("Set \(index + 1) ağırlık, kilogram")
                    Text("kg ×").foregroundStyle(Color.ftTextSecondary)
                    TextField("tekrar", value: Binding(
                        get: { set.reps },
                        set: { live.updateSet(exerciseID: exerciseID, setID: set.id, reps: $0) }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 44)
                    .accessibilityLabel("Set \(index + 1) tekrar")
                }
                .font(.body.monospacedDigit())
                if let previous {
                    Text("Geçen sefer: \(previous)")
                        .font(.caption2)
                        .foregroundStyle(Color.ftTextSecondary)
                }
            }

            Spacer()

            Button {
                live.toggleSet(exerciseID: exerciseID, setID: set.id)
            } label: {
                Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(set.isDone ? Color.ftSuccess : Color.ftTextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isDone ? "Set \(index + 1) tamamlandı" : "Set \(index + 1) tamamla")
        }
        .padding(.vertical, 2)
    }
}

private struct DurationRow: View {
    @Environment(LiveWorkoutViewModel.self) private var live
    let item: LiveExercise

    var body: some View {
        HStack {
            Stepper(value: Binding(
                get: { item.durationMinutes },
                set: { live.updateDuration(exerciseID: item.id, minutes: $0) }
            ), in: 1...300, step: 1) {
                Text("\(Int(item.durationMinutes)) dk").font(.body.monospacedDigit())
            }
            Button {
                live.toggleDuration(exerciseID: item.id)
            } label: {
                Image(systemName: item.isDurationDone ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(item.isDurationDone ? Color.ftSuccess : Color.ftTextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDurationDone ? "Tamamlandı" : "Tamamla")
        }
    }
}

// MARK: - Dinlenme çubuğu
private struct RestTimerBar: View {
    @Environment(LiveWorkoutViewModel.self) private var live
    let session: LiveSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let end = session.restEndsAt ?? context.date
            let remaining = max(Int(end.timeIntervalSince(context.date).rounded(.up)), 0)
            let total = max(session.restTotalSeconds, 1)

            VStack(spacing: 10) {
                HStack {
                    Label("Dinlenme", systemImage: "timer")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(.title2.bold().monospacedDigit())
                        .contentTransition(.numericText())
                }
                ProgressView(value: Double(total - remaining), total: Double(total))
                    .tint(Color.ftExercise)
                HStack(spacing: 10) {
                    Button("−\(LiveWorkoutViewModel.restAdjustment) sn") { live.adjustRest(by: -LiveWorkoutViewModel.restAdjustment) }
                    Button("+\(LiveWorkoutViewModel.restAdjustment) sn") { live.adjustRest(by: LiveWorkoutViewModel.restAdjustment) }
                    Spacer()
                    Button("Geç") { live.skipRest() }
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dinlenme, \(remaining) saniye kaldı")
        }
    }
}
