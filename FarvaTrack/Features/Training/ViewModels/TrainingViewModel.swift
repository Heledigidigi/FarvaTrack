import Foundation
import Observation
import SwiftData

/// Şablonlar, programlar ve "bugün ne var" hesabı.
@MainActor
@Observable
final class TrainingViewModel {
    var errorMessage: String?
    private(set) var isSyncing = false

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private(set) var userID: String?
    @ObservationIgnored private var templateDeletions: PendingDeletionStore?
    @ObservationIgnored private var programDeletions: PendingDeletionStore?
    @ObservationIgnored private let sync: TrainingSyncing
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    static let nameLength = 2...40
    static let maxExercises = 20

    init(sync: TrainingSyncing = FirestoreTrainingSyncService(), defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.sync = sync
        self.defaults = defaults
        self.calendar = calendar
    }

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func configure(context: ModelContext, user: AppUser) {
        self.context = context
        guard userID != user.id else { return }
        userID = user.id
        templateDeletions = PendingDeletionStore(userID: user.id, scope: "Template", defaults: defaults)
        programDeletions = PendingDeletionStore(userID: user.id, scope: "Program", defaults: defaults)
    }

    // MARK: - Okuma
    func templates() -> [WorkoutTemplate] {
        guard let context, let userID else { return [] }
        return (try? context.fetch(FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.ownerID == userID },
            sortBy: [SortDescriptor(\.name)]
        ))) ?? []
    }

    func template(id: UUID) -> WorkoutTemplate? {
        guard let context else { return nil }
        return try? context.fetch(FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == id })).first
    }

    func activeProgram() -> TrainingProgram? {
        guard let context, let userID else { return nil }
        return try? context.fetch(FetchDescriptor<TrainingProgram>(
            predicate: #Predicate { $0.ownerID == userID && $0.isActive }
        )).first
    }

    /// Bugünkü plan: aktif program, mevcut şablonlar ve tamamlanan antrenmanlardan hesaplanır.
    func todayPlan(on date: Date = .now) -> TodayPlan {
        guard let context, let userID, let program = activeProgram() else { return .none }
        let since = calendar.date(byAdding: .day, value: -120, to: calendar.startOfDay(for: date)) ?? .distantPast
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.ownerID == userID && $0.date >= since }
        ))) ?? []
        let completed = workouts.map { CompletedSession(date: $0.date, templateID: $0.templateID.flatMap(UUID.init(uuidString:))) }
        return ProgramPlanner.plan(
            for: program.snapshot,
            completed: completed,
            on: date,
            existingTemplates: Set(templates().map(\.id)),
            calendar: calendar
        )
    }

    // MARK: - Şablonlar
    @discardableResult
    func saveTemplate(name: String, exercises: [TemplateExercise], editing: WorkoutTemplate? = nil) throws -> WorkoutTemplate {
        guard let context, let userID else { throw AppError.notAuthenticated }
        let cleanName = name.trimmed
        guard Self.nameLength.contains(cleanName.count) else {
            throw AppError.invalidInput("Şablon adı \(Self.nameLength.lowerBound)–\(Self.nameLength.upperBound) karakter olmalı.")
        }
        guard !exercises.isEmpty else { throw AppError.invalidInput("Şablona en az bir egzersiz ekle.") }
        guard exercises.count <= Self.maxExercises else {
            throw AppError.invalidInput("Bir şablonda en fazla \(Self.maxExercises) egzersiz olabilir.")
        }
        guard exercises.allSatisfy(\.isValid) else {
            throw AppError.invalidInput("Set, tekrar ve süre değerlerini kontrol et.")
        }
        let taken = templates().contains {
            $0.id != editing?.id && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame
        }
        guard !taken else { throw AppError.invalidInput("Bu isimde bir şablon zaten var.") }

        let template: WorkoutTemplate
        if let editing {
            template = editing
            template.name = cleanName
            template.exercises = exercises
        } else {
            template = WorkoutTemplate(ownerID: userID, name: cleanName, exercises: exercises)
            context.insert(template)
        }
        template.updatedAt = .now
        template.needsSync = true
        try commit()
        Haptics.success()
        uploadTemplate(template)
        return template
    }

    /// Geçmiş bir antrenmandan şablon üretir; setlerdeki en yaygın tekrar ve son ağırlık hedef olur.
    @discardableResult
    func saveTemplate(from workout: Workout, name: String) throws -> WorkoutTemplate {
        try saveTemplate(name: name, exercises: Self.templateExercises(from: workout))
    }

    static func templateExercises(from workout: Workout) -> [TemplateExercise] {
        workout.sortedEntries.map { entry in
            let template = ExerciseTemplate(key: entry.exerciseKey, name: entry.name, category: entry.category, mode: entry.mode, met: entry.met)
            switch entry.mode {
            case .duration:
                return TemplateExercise(template: template, durationMinutes: max(entry.durationMinutes, 1), restSeconds: 60)
            case .sets:
                let reps = entry.sets.map(\.reps)
                let common = Dictionary(grouping: reps, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? 10
                let weight = entry.sets.last.map(\.weightKg).flatMap { $0 > 0 ? $0 : nil }
                return TemplateExercise(
                    template: template,
                    sets: min(max(entry.sets.count, 1), TemplateExercise.setRange.upperBound),
                    reps: min(max(common, 1), TemplateExercise.repRange.upperBound),
                    weightKg: weight
                )
            }
        }
    }

    /// Şablonu siler ve onu kullanan programlardan çıkarır.
    func deleteTemplate(_ template: WorkoutTemplate) {
        guard let context, let userID else { return }
        let id = template.id.uuidString
        for program in programs() where program.templateIDs.contains(id) {
            program.weekdayTemplateIDs = program.weekdayTemplateIDs.map { $0 == id ? "" : $0 }
            program.rotationTemplateIDs.removeAll { $0 == id }
            program.updatedAt = .now
            program.needsSync = true
            uploadProgram(program)
        }
        context.delete(template)
        do { try commit() } catch { present(error); return }
        Haptics.impact(.medium)
        templateDeletions?.add(id)
        deleteRemoteTemplate(id: id, userID: userID)
    }

    // MARK: - Programlar
    func programs() -> [TrainingProgram] {
        guard let context, let userID else { return [] }
        return (try? context.fetch(FetchDescriptor<TrainingProgram>(
            predicate: #Predicate { $0.ownerID == userID },
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []
    }

    @discardableResult
    func saveProgram(
        name: String,
        kind: ProgramKind,
        weekly: [String],
        rotation: [String],
        editing: TrainingProgram? = nil,
        activate: Bool = false
    ) throws -> TrainingProgram {
        guard let context, let userID else { throw AppError.notAuthenticated }
        let cleanName = name.trimmed
        guard Self.nameLength.contains(cleanName.count) else {
            throw AppError.invalidInput("Program adı \(Self.nameLength.lowerBound)–\(Self.nameLength.upperBound) karakter olmalı.")
        }
        let existing = Set(templates().map(\.id.uuidString))
        let week = TrainingProgram.normalizedWeek(weekly).map { existing.contains($0) ? $0 : "" }
        let cycle = rotation.filter { existing.contains($0) }
        switch kind {
        case .weekly:
            guard week.contains(where: { !$0.isEmpty }) else { throw AppError.invalidInput("En az bir güne şablon ata.") }
        case .rotation:
            guard !cycle.isEmpty else { throw AppError.invalidInput("Döngüye en az bir şablon ekle.") }
        }

        let program: TrainingProgram
        if let editing {
            program = editing
            // Döngünün sırası değiştiyse sayım baştan başlar.
            if editing.kind != kind || editing.rotationTemplateIDs != cycle { program.activatedAt = .now }
        } else {
            program = TrainingProgram(ownerID: userID, name: cleanName, kind: kind)
            context.insert(program)
        }
        program.name = cleanName
        program.kind = kind
        program.weekdayTemplateIDs = week
        program.rotationTemplateIDs = cycle
        program.updatedAt = .now
        program.needsSync = true
        try commit()

        if activate || programs().filter(\.isActive).isEmpty {
            setActive(program)
        } else {
            uploadProgram(program)
        }
        Haptics.success()
        return program
    }

    /// Tek aktif program olur; `nil` tüm programları pasifleştirir.
    func setActive(_ program: TrainingProgram?) {
        for other in programs() {
            let shouldBeActive = other.id == program?.id
            guard other.isActive != shouldBeActive else { continue }
            other.isActive = shouldBeActive
            if shouldBeActive { other.activatedAt = .now }
            other.updatedAt = .now
            other.needsSync = true
            uploadProgram(other)
        }
        try? commit()
        Haptics.selection()
    }

    func deleteProgram(_ program: TrainingProgram) {
        guard let context, let userID else { return }
        let id = program.id.uuidString
        context.delete(program)
        do { try commit() } catch { present(error); return }
        Haptics.impact(.medium)
        programDeletions?.add(id)
        deleteRemoteProgram(id: id, userID: userID)
    }

    /// Hazır programı kullanıcının hesabına kopyalar ve etkinleştirir. Aynı adlı şablon varsa ad sonuna sayı eklenir.
    @discardableResult
    func adopt(_ preset: PresetProgram) throws -> TrainingProgram {
        guard context != nil, userID != nil else { throw AppError.notAuthenticated }
        var takenNames = Set(templates().map { $0.name.lowercased() })
        var ids: [String] = []
        for day in preset.days {
            var name = day.name
            var counter = 2
            while takenNames.contains(name.lowercased()) {
                name = "\(day.name) \(counter)"
                counter += 1
            }
            takenNames.insert(name.lowercased())
            let template = try saveTemplate(name: name, exercises: day.exercises)
            ids.append(template.id.uuidString)
        }

        let weekly = preset.weeklyLayout.map { index in index.map { ids[$0] } ?? "" }
        var programName = preset.name
        var counter = 2
        let programNames = Set(programs().map { $0.name.lowercased() })
        while programNames.contains(programName.lowercased()) {
            programName = "\(preset.name) \(counter)"
            counter += 1
        }
        return try saveProgram(
            name: programName,
            kind: preset.kind,
            weekly: preset.kind == .weekly ? weekly : [],
            rotation: preset.kind == .rotation ? ids : [],
            activate: true
        )
    }

    // MARK: - Senkronizasyon
    func syncAll() async {
        guard let context, let userID, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let pendingTemplates = templateDeletions?.ids ?? []
        let pendingPrograms = programDeletions?.ids ?? []
        for id in pendingTemplates { deleteRemoteTemplate(id: id, userID: userID) }
        for id in pendingPrograms { deleteRemoteProgram(id: id, userID: userID) }

        if let remote = try? await sync.fetchTemplates(userID: userID) {
            let local = (try? context.fetch(FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
            var byID = Dictionary(local.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
            for dto in remote where !pendingTemplates.contains(dto.id) {
                if let existing = byID[dto.id] {
                    if !existing.needsSync, dto.updatedAt > existing.updatedAt { existing.apply(dto) }
                } else {
                    let template = WorkoutTemplate.make(from: dto, ownerID: userID)
                    context.insert(template)
                    byID[dto.id] = template
                }
            }
            try? context.save()
            for template in local where template.needsSync { uploadTemplate(template) }
        }

        if let remote = try? await sync.fetchPrograms(userID: userID) {
            let local = (try? context.fetch(FetchDescriptor<TrainingProgram>(predicate: #Predicate { $0.ownerID == userID }))) ?? []
            var byID = Dictionary(local.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
            for dto in remote where !pendingPrograms.contains(dto.id) {
                if let existing = byID[dto.id] {
                    if !existing.needsSync, dto.updatedAt > existing.updatedAt { existing.apply(dto) }
                } else {
                    let program = TrainingProgram.make(from: dto, ownerID: userID)
                    context.insert(program)
                    byID[dto.id] = program
                }
            }
            // İki cihazda farklı program aktifleştirildiyse en son aktifleştirilen kalır.
            let active = byID.values.filter(\.isActive).sorted { $0.activatedAt > $1.activatedAt }
            for extra in active.dropFirst() {
                extra.isActive = false
                extra.updatedAt = .now
                extra.needsSync = true
            }
            try? context.save()
            for program in byID.values where program.needsSync { uploadProgram(program) }
        }
    }

    // MARK: - Yardımcılar
    private func commit() throws {
        guard let context else { throw AppError.notAuthenticated }
        do {
            try context.save()
        } catch {
            throw AppError.unknown(error.localizedDescription)
        }
    }

    private func uploadTemplate(_ template: WorkoutTemplate) {
        guard let userID else { return }
        let dto = template.dto
        let id = template.id
        let updatedAt = template.updatedAt
        Task {
            do {
                try await sync.uploadTemplate(dto, userID: userID)
                if let context, let item = try? context.fetch(FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == id })).first,
                   item.updatedAt == updatedAt {
                    item.needsSync = false
                    try? context.save()
                }
            } catch {}
        }
    }

    private func uploadProgram(_ program: TrainingProgram) {
        guard let userID else { return }
        let dto = program.dto
        let id = program.id
        let updatedAt = program.updatedAt
        Task {
            do {
                try await sync.uploadProgram(dto, userID: userID)
                if let context, let item = try? context.fetch(FetchDescriptor<TrainingProgram>(predicate: #Predicate { $0.id == id })).first,
                   item.updatedAt == updatedAt {
                    item.needsSync = false
                    try? context.save()
                }
            } catch {}
        }
    }

    private func deleteRemoteTemplate(id: String, userID: String) {
        let store = templateDeletions
        Task {
            do {
                try await sync.deleteTemplate(id: id, userID: userID)
                store?.remove(id)
            } catch {}
        }
    }

    private func deleteRemoteProgram(id: String, userID: String) {
        let store = programDeletions
        Task {
            do {
                try await sync.deleteProgram(id: id, userID: userID)
                store?.remove(id)
            } catch {}
        }
    }

    private func present(_ error: Error) {
        errorMessage = AppError.map(error).errorDescription
        Haptics.error()
    }
}
