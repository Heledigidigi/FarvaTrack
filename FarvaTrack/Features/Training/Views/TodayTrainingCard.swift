import SwiftUI
import SwiftData

/// "Bugün ne var?" kartı. Veriler @Query ile izlendiği için antrenman kaydedilince kendiliğinden güncellenir.
struct TodayTrainingCard: View {
    @Query private var programs: [TrainingProgram]
    @Query private var templates: [WorkoutTemplate]
    @Query private var recentWorkouts: [Workout]

    let liveTitle: String?
    let onStart: (WorkoutTemplate, String?) -> Void
    let onQuickComplete: (WorkoutTemplate, String?) -> Void
    let onResume: () -> Void
    let onOpenPrograms: () -> Void

    init(
        ownerID: String,
        liveTitle: String?,
        onStart: @escaping (WorkoutTemplate, String?) -> Void,
        onQuickComplete: @escaping (WorkoutTemplate, String?) -> Void,
        onResume: @escaping () -> Void,
        onOpenPrograms: @escaping () -> Void
    ) {
        let since = Calendar.current.date(byAdding: .day, value: -120, to: Date.now.startOfDay) ?? .distantPast
        _programs = Query(filter: #Predicate<TrainingProgram> { $0.ownerID == ownerID && $0.isActive })
        _templates = Query(filter: #Predicate<WorkoutTemplate> { $0.ownerID == ownerID })
        _recentWorkouts = Query(filter: #Predicate<Workout> { $0.ownerID == ownerID && $0.date >= since })
        self.liveTitle = liveTitle
        self.onStart = onStart
        self.onQuickComplete = onQuickComplete
        self.onResume = onResume
        self.onOpenPrograms = onOpenPrograms
    }

    private var program: TrainingProgram? { programs.first }
    private var templatesByID: [UUID: WorkoutTemplate] {
        Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var plan: TodayPlan {
        ProgramPlanner.plan(
            for: program?.snapshot,
            completed: recentWorkouts.map { CompletedSession(date: $0.date, templateID: $0.templateID.flatMap(UUID.init(uuidString:))) },
            on: .now,
            existingTemplates: Set(templatesByID.keys)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let liveTitle {
                resumeRow(liveTitle)
            } else {
                planContent
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ftCard, in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous))
    }

    private func resumeRow(_ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title2)
                .foregroundStyle(Color.ftExercise)
            VStack(alignment: .leading, spacing: 2) {
                Text("Devam eden antrenman").font(.caption.weight(.semibold)).foregroundStyle(Color.ftTextSecondary)
                Text(title).font(.headline)
            }
            Spacer()
            Button("Devam Et", action: onResume)
                .buttonStyle(.borderedProminent)
                .tint(Color.ftAccent)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var planContent: some View {
        switch plan {
        case .none:
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.ftExercise)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Düzenli mi çalışıyorsun?").font(.headline)
                    Text("Şablon ve haftalık program oluştur, her seferinde baştan girme.")
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                Spacer(minLength: 0)
            }
            Button("Programlar ve Şablonlar", action: onOpenPrograms)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ftAccentLight)

        case .rest(let next):
            HStack(spacing: 12) {
                Image(systemName: "bed.double.fill")
                    .font(.title2)
                    .foregroundStyle(Color.ftSleep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bugün dinlenme günü").font(.headline)
                    if let next, let template = templatesByID[next.templateID] {
                        Text("Sıradaki: \(ProgramPlanner.weekdayNames[ProgramPlanner.weekdayIndex(of: next.date)]) • \(template.name)")
                            .font(.caption)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

        case .workout(let id, let isDone):
            if let template = templatesByID[id] {
                HStack(spacing: 12) {
                    Image(systemName: isDone ? "checkmark.seal.fill" : "dumbbell.fill")
                        .font(.title2)
                        .foregroundStyle(isDone ? Color.ftSuccess : Color.ftExercise)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isDone ? "Bugünkü antrenman tamam" : "Bugün").font(.caption.weight(.semibold)).foregroundStyle(Color.ftTextSecondary)
                        Text(template.name).font(.headline)
                        Text(template.summaryText).font(.caption).foregroundStyle(Color.ftTextSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if !isDone {
                    HStack(spacing: 10) {
                        Button {
                            onStart(template, program?.id.uuidString)
                        } label: {
                            Label("Başla", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ftAccent)

                        Button {
                            onQuickComplete(template, program?.id.uuidString)
                        } label: {
                            Label("Plandaki gibi yaptım", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.ftAccentLight)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}

/// Özet ekranındaki tek satırlık antrenman durumu; dokununca Egzersiz sekmesine geçer.
struct DashboardTrainingRow: View {
    @Query private var programs: [TrainingProgram]
    @Query private var templates: [WorkoutTemplate]
    @Query private var recentWorkouts: [Workout]
    let isLive: Bool
    let onOpen: () -> Void

    init(ownerID: String, isLive: Bool, onOpen: @escaping () -> Void) {
        let since = Calendar.current.date(byAdding: .day, value: -120, to: Date.now.startOfDay) ?? .distantPast
        _programs = Query(filter: #Predicate<TrainingProgram> { $0.ownerID == ownerID && $0.isActive })
        _templates = Query(filter: #Predicate<WorkoutTemplate> { $0.ownerID == ownerID })
        _recentWorkouts = Query(filter: #Predicate<Workout> { $0.ownerID == ownerID && $0.date >= since })
        self.isLive = isLive
        self.onOpen = onOpen
    }

    private var status: (icon: String, title: String, detail: String)? {
        if isLive { return ("figure.strengthtraining.traditional", "Devam eden antrenman", "Kaldığın yerden devam et") }
        let names = Dictionary(templates.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let plan = ProgramPlanner.plan(
            for: programs.first?.snapshot,
            completed: recentWorkouts.map { CompletedSession(date: $0.date, templateID: $0.templateID.flatMap(UUID.init(uuidString:))) },
            on: .now,
            existingTemplates: Set(names.keys)
        )
        switch plan {
        case .none:
            return nil
        case .rest:
            return ("bed.double.fill", "Bugün dinlenme günü", programs.first?.name ?? "")
        case .workout(let id, let isDone):
            return (isDone ? "checkmark.seal.fill" : "dumbbell.fill",
                    isDone ? "Bugünkü antrenman tamam" : "Bugün: \(names[id] ?? "")",
                    programs.first?.name ?? "")
        }
    }

    var body: some View {
        if let status {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Image(systemName: status.icon)
                        .font(.subheadline)
                        .foregroundStyle(Color.ftExercise)
                        .frame(width: 32, height: 32)
                        .background(Color.ftExercise.opacity(0.18), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.title).font(.subheadline.weight(.medium))
                        if !status.detail.isEmpty {
                            Text(status.detail).font(.caption).foregroundStyle(Color.ftTextSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.ftTextSecondary.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.ftCard, in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
        }
    }
}
