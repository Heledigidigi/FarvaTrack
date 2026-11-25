import Foundation
import Observation
import SwiftData
import UIKit

/// Diyet programları, öğün kayıtları, notlar, fotoğraflar, yorumlar, öneriler ve sohbet teklifleri.
/// SwiftData (`DietRecord`) ana kaynaktır; değişiklikler arka planda `dietPrograms` koleksiyonuna yüklenir.
@MainActor
@Observable
final class DietStore {
    private(set) var programs: [DietProgram] = []
    private(set) var logsByProgram: [String: [DietMealLog]] = [:]
    private(set) var notesByProgram: [String: [DietDayNote]] = [:]
    private(set) var commentsByProgram: [String: [DietComment]] = [:]
    private(set) var suggestionsByProgram: [String: [DietSuggestion]] = [:]
    /// Takibini benimle paylaşanların programları (yalnızca bellekte).
    private(set) var sharedPrograms: [DietProgram] = []
    private(set) var isSyncing = false
    var errorMessage: String?
    var toast: String?

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private(set) var user: AppUser?
    @ObservationIgnored private let sync: DietSyncing
    @ObservationIgnored private let media: ChatMediaStoring
    @ObservationIgnored private let chat: ChatSyncing
    @ObservationIgnored private let notifier: ChatNotifying?
    @ObservationIgnored private let files: DietPhotoFiles
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// Yüklemeler sırayla gider: aynı kaydın eski hali yenisinin üzerine yazılmasın.
    @ObservationIgnored private var uploadChain: Task<Void, Never>?

    init(sync: DietSyncing = DietSyncService(), media: ChatMediaStoring = MediaServerClient(),
         chat: ChatSyncing = ChatService(), notifier: ChatNotifying? = MediaServerClient(),
         files: DietPhotoFiles = .live, defaults: UserDefaults = .standard) {
        self.sync = sync
        self.media = media
        self.chat = chat
        self.notifier = notifier
        self.files = files
        self.defaults = defaults
    }

    var userID: String? { user?.id }

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func configure(context: ModelContext, user: AppUser) {
        let changed = self.user?.id != user.id
        self.context = context
        self.user = user
        if changed { reload() }
    }

    // MARK: - Okuma

    /// Bugün (ya da verilen gün) süren program; yoksa yakında başlayacak olan.
    func activeProgram(on date: Date = .now) -> DietProgram? {
        let candidates = programs.filter { !$0.isArchived }
        if let running = candidates.filter({ $0.programDay(on: date) != nil }).max(by: { $0.startDate < $1.startDate }) {
            return running
        }
        return candidates.filter { $0.dayOffset(of: date) < 0 }.min(by: { $0.startDate < $1.startDate })
    }

    func program(id: String) -> DietProgram? {
        programs.first { $0.id == id } ?? sharedPrograms.first { $0.id == id }
    }

    func logs(for programID: String) -> [DietMealLog] { logsByProgram[programID] ?? [] }
    func notes(for programID: String) -> [DietDayNote] { notesByProgram[programID] ?? [] }
    func comments(for programID: String) -> [DietComment] { commentsByProgram[programID] ?? [] }
    func suggestions(for programID: String) -> [DietSuggestion] { suggestionsByProgram[programID] ?? [] }

    func log(programID: String, dayKey: String, mealID: String) -> DietMealLog? {
        let id = DietMealLog.makeID(dayKey: dayKey, mealID: mealID)
        return logs(for: programID).first { $0.id == id }
    }

    func note(programID: String, dayKey: String) -> DietDayNote? {
        notes(for: programID).first { $0.dayKey == dayKey }
    }

    func comments(programID: String, targetID: String) -> [DietComment] {
        comments(for: programID).filter { $0.targetID == targetID }
    }

    /// Serbest kayıtlar (program dışı yenenler) tarih aralığında.
    func extras(from start: Date, to end: Date) -> [DietExtra] {
        guard let context, let ownerID = userID else { return [] }
        let lower = Calendar.current.startOfDay(for: start)
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
        let entries = (try? context.fetch(FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.ownerID == ownerID && $0.date >= lower && $0.date < upper },
            sortBy: [SortDescriptor(\.date)]))) ?? []
        return entries.map {
            DietExtra(id: $0.id.uuidString, date: $0.date, name: $0.name,
                      amountText: "\(DietFormat.number($0.quantity, maxFraction: 2)) × \($0.servingLabel)",
                      nutrition: DietNutrition(calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat))
        }
    }

    func summary(for program: DietProgram, from start: Date, to end: Date, now: Date = .now) -> DietRangeSummary {
        DietAnalysis.summarize(program: program, from: start, to: end, logs: logs(for: program.id),
                               notes: notes(for: program.id), extras: program.ownerID == userID ? extras(from: start, to: end) : [],
                               now: now)
    }

    /// Kütüphanedeki tüm yiyecekler (hazır + özel).
    func foodLibrary() -> [FoodTemplate] {
        guard let context, let ownerID = userID else { return FoodLibrary.all }
        let custom = (try? context.fetch(FetchDescriptor<CustomFood>(predicate: #Predicate { $0.ownerID == ownerID }))) ?? []
        return custom.map(\.template) + FoodLibrary.all
    }

    /// İçe aktarmada kütüphanede olmayan yiyecek için özel yiyecek.
    func createCustomFood(name: String, servingLabel: String, nutrition: DietNutrition) throws -> FoodTemplate {
        guard let context, let ownerID = userID else { throw AppError.notAuthenticated }
        let clean = name.trimmed
        guard (2...60).contains(clean.count) else { throw AppError.invalidInput("Yiyecek adı 2–60 karakter olmalı.") }
        guard (0...5_000).contains(nutrition.calories), (0...1_000).contains(nutrition.protein),
              (0...1_000).contains(nutrition.carbs), (0...1_000).contains(nutrition.fat) else {
            throw AppError.invalidInput("Besin değerleri makul bir aralıkta olmalı.")
        }
        if let existing = foodLibrary().first(where: { $0.name.compare(clean, options: .caseInsensitive, locale: DietFormat.locale) == .orderedSame }) {
            return existing
        }
        let food = CustomFood(ownerID: ownerID, name: clean, servingLabel: servingLabel.trimmed.isEmpty ? "1 porsiyon" : servingLabel.trimmed,
                              calories: nutrition.calories, protein: nutrition.protein, carbs: nutrition.carbs, fat: nutrition.fat)
        context.insert(food)
        try context.save()
        return food.template
    }

    func reload() {
        guard let context, let ownerID = userID else {
            programs = []; logsByProgram = [:]; notesByProgram = [:]
            return
        }
        let records = (try? context.fetch(FetchDescriptor<DietRecord>(predicate: #Predicate { $0.ownerID == ownerID }))) ?? []
        var programs: [DietProgram] = []
        var logs: [String: [DietMealLog]] = [:]
        var notes: [String: [DietDayNote]] = [:]
        for record in records {
            switch record.kind {
            case .program: if let program = record.program { programs.append(program) }
            case .log: if let log = record.log { logs[record.programID, default: []].append(log) }
            case .note: if let note = record.note { notes[record.programID, default: []].append(note) }
            }
        }
        self.programs = programs.sorted { $0.startDate > $1.startDate }
        logsByProgram = logs
        notesByProgram = notes
    }

    // MARK: - Program

    @discardableResult
    func createProgram(name: String, plan: DietPlan, startDate: Date, endBehavior: DietEndBehavior,
                       note: String, sharedBy: (id: String, name: String)? = nil, allowViewer: Bool = false) throws -> DietProgram {
        guard let user else { throw AppError.notAuthenticated }
        let cleanName = name.trimmed.isEmpty ? "Diyet programı" : String(name.trimmed.prefix(60))
        guard plan.dayCount > 0 else { throw AppError.invalidInput("Programda en az bir gün olmalı.") }
        guard plan.dayCount <= 366 else { throw AppError.invalidInput("Program en fazla 366 gün olabilir.") }
        let viewers = allowViewer ? [sharedBy?.id].compactMap { $0 } : []
        let program = DietProgram(ownerID: user.id, ownerName: user.displayName, viewerIDs: viewers, name: cleanName,
                                  startDate: startDate, endBehavior: endBehavior, plan: plan, note: note,
                                  authorName: user.displayName, sharedByID: sharedBy?.id, sharedByName: sharedBy?.name)
        try save(program)
        Haptics.success()
        return program
    }

    /// Program bilgisini kaydeder ve yükler.
    func save(_ program: DietProgram) throws {
        guard let context, let ownerID = userID else { throw AppError.notAuthenticated }
        var copy = program
        copy.updatedAt = .now
        try upsert(kind: .program, programID: copy.id, docID: copy.id, value: copy, context: context, ownerID: ownerID)
        reload()
        scheduleUpload(programID: copy.id)
    }

    /// Plan değişikliği: program başladıysa yeni sürüm (geçmiş günler eski sürümle kalır).
    func savePlan(_ plan: DietPlan, for programID: String, effectiveFrom: Date, note: String,
                  author: (id: String, name: String?)? = nil) throws {
        guard var program = program(id: programID), let user else { throw AppError.notAuthenticated }
        program.apply(plan: plan, effectiveFrom: effectiveFrom, authorID: author?.id ?? user.id,
                      authorName: author?.name ?? user.displayName, note: note)
        try save(program)
    }

    func rename(_ programID: String, to name: String) throws {
        guard var program = program(id: programID) else { return }
        let clean = name.trimmed
        guard !clean.isEmpty else { throw AppError.invalidInput("Program adı boş olamaz.") }
        program.name = String(clean.prefix(60))
        try save(program)
    }

    func setStart(_ programID: String, date: Date, endBehavior: DietEndBehavior) throws {
        guard var program = program(id: programID) else { return }
        program.startDate = Calendar.current.startOfDay(for: date)
        if program.versions.count == 1 { program.versions[0].effectiveFrom = program.startDate }
        program.endBehavior = endBehavior
        try save(program)
    }

    func setViewer(_ programID: String, viewerID: String, allowed: Bool) throws {
        guard var program = program(id: programID) else { return }
        program.viewerIDs.removeAll { $0 == viewerID }
        if allowed { program.viewerIDs.append(viewerID) }
        try save(program)
        Haptics.selection()
    }

    func archive(_ programID: String, archived: Bool = true) throws {
        guard var program = program(id: programID) else { return }
        program.isArchived = archived
        try save(program)
    }

    func deleteProgram(_ programID: String) {
        guard let context, let ownerID = userID else { return }
        let records = (try? context.fetch(FetchDescriptor<DietRecord>(predicate: #Predicate { $0.ownerID == ownerID && $0.programID == programID }))) ?? []
        for record in records {
            if let path = record.log?.photoPath { files.remove(path) }
            context.delete(record)
        }
        try? context.save()
        DietShoppingStore(defaults: defaults, programID: programID).save([:])
        reload()
        Haptics.impact(.medium)
        let pending = PendingDeletionStore(userID: ownerID, scope: "DietProgram")
        pending.add(programID)
        let media = self.media
        let sync = self.sync
        Task {
            do {
                try await sync.deleteProgram(id: programID)
                try? await media.deletePrefix("diet/\(programID)/")
                pending.remove(programID)
            } catch {
                // Bir sonraki eşitlemede yeniden denenir.
            }
        }
    }

    // MARK: - Öğün işaretleme

    func mark(program: DietProgram, date: Date, meal: DietMeal, status: DietMealStatus,
              eaten: [DietPortion]? = nil, swaps: [String] = [], note: String? = nil) throws {
        guard let number = program.programDay(on: date) else { throw AppError.invalidInput("Bu gün programın dışında.") }
        let key = DietDayKey.make(date)
        var log = self.log(programID: program.id, dayKey: key, mealID: meal.id)
            ?? DietMealLog(programID: program.id, dayKey: key, programDay: number, meal: meal, status: status, eaten: [])
        log.status = status
        log.planned = meal.portions
        log.mealName = meal.name
        log.mealMinutes = meal.minutes
        switch status {
        case .eaten:
            log.eaten = meal.portions
            log.swaps = []
        case .changed:
            log.eaten = eaten ?? meal.portions
            log.swaps = swaps
        case .skipped, .pending:
            log.eaten = []
            log.swaps = []
        }
        if let note { log.note = String(note.prefix(500)) }
        if status.isMarked, log.loggedAt < Calendar.current.startOfDay(for: .now) || log.status == .pending {
            log.loggedAt = .now
        }
        log.updatedAt = .now
        try saveLog(log)
        status == .skipped ? Haptics.impact(.light) : Haptics.success()
    }

    /// İşareti kaldırır (fotoğraf ve not kalır).
    func unmark(program: DietProgram, date: Date, meal: DietMeal) throws {
        let key = DietDayKey.make(date)
        guard var log = log(programID: program.id, dayKey: key, mealID: meal.id) else { return }
        if log.photoPath == nil, log.note.isEmpty {
            deleteLog(log)
            return
        }
        log.status = .pending
        log.eaten = []
        log.swaps = []
        log.updatedAt = .now
        try saveLog(log)
    }

    func setMealNote(program: DietProgram, date: Date, meal: DietMeal, note: String) throws {
        guard let number = program.programDay(on: date) else { return }
        let key = DietDayKey.make(date)
        var log = self.log(programID: program.id, dayKey: key, mealID: meal.id)
            ?? DietMealLog(programID: program.id, dayKey: key, programDay: number, meal: meal, status: .pending, eaten: [])
        log.note = String(note.trimmed.prefix(500))
        log.updatedAt = .now
        if log.status == .pending, log.note.isEmpty, log.photoPath == nil { deleteLog(log); return }
        try saveLog(log)
    }

    /// Fotoğrafı öğüne ekler (öğün işaretlenmeden de). Eski fotoğraf silinir.
    func attachPhoto(_ image: UIImage, program: DietProgram, date: Date, meal: DietMeal) throws {
        guard let number = program.programDay(on: date), let ownerID = userID else { return }
        let key = DietDayKey.make(date)
        var log = self.log(programID: program.id, dayKey: key, mealID: meal.id)
            ?? DietMealLog(programID: program.id, dayKey: key, programDay: number, meal: meal, status: .pending, eaten: [])
        let path = DietPhotoFiles.path(programID: program.id)
        _ = try files.save(image, path: path)
        if let old = log.photoPath { removeRemotePhoto(old) }
        log.photoPath = path
        log.photoTakenAt = .now
        log.updatedAt = .now
        try saveLog(log)
        var pending = pendingPhotos(ownerID)
        pending.insert(path)
        savePendingPhotos(pending, ownerID)
        uploadPhoto(path)
        Haptics.success()
    }

    func removePhoto(program: DietProgram, date: Date, meal: DietMeal) throws {
        let key = DietDayKey.make(date)
        guard var log = log(programID: program.id, dayKey: key, mealID: meal.id), let path = log.photoPath else { return }
        removeRemotePhoto(path)
        log.photoPath = nil
        log.photoTakenAt = nil
        log.updatedAt = .now
        if log.status == .pending, log.note.isEmpty { deleteLog(log); return }
        try saveLog(log)
    }

    func saveDayNote(programID: String, date: Date, text: String, tags: [String]) throws {
        guard let context, let ownerID = userID else { throw AppError.notAuthenticated }
        let key = DietDayKey.make(date)
        let note = DietDayNote(dayKey: key, programID: programID, text: String(text.trimmed.prefix(1000)), tags: tags, updatedAt: .now)
        try upsert(kind: .note, programID: programID, docID: key, dayKey: key, value: note, context: context, ownerID: ownerID)
        reload()
        let sync = self.sync
        enqueue { [weak self] in
            do {
                try await sync.uploadNote(note)
                self?.markSynced(kind: .note, programID: programID, docID: key, updatedAt: note.updatedAt)
            } catch {}
        }
    }

    private func saveLog(_ log: DietMealLog) throws {
        guard let context, let ownerID = userID else { throw AppError.notAuthenticated }
        try upsert(kind: .log, programID: log.programID, docID: log.id, dayKey: log.dayKey, value: log, context: context, ownerID: ownerID)
        reload()
        let sync = self.sync
        enqueue { [weak self] in
            do {
                try await sync.uploadLog(log)
                self?.markSynced(kind: .log, programID: log.programID, docID: log.id, updatedAt: log.updatedAt)
            } catch {}
        }
    }

    private func deleteLog(_ log: DietMealLog) {
        guard let context, let ownerID = userID else { return }
        let key = DietRecord.makeKey(ownerID: ownerID, kind: .log, programID: log.programID, docID: log.id)
        if let record = try? context.fetch(FetchDescriptor<DietRecord>(predicate: #Predicate { $0.key == key })).first {
            context.delete(record)
            try? context.save()
        }
        reload()
        let pending = PendingDeletionStore(userID: ownerID, scope: "DietLog")
        pending.add("\(log.programID)/\(log.id)")
        let sync = self.sync
        Task {
            do {
                try await sync.deleteLog(id: log.id, programID: log.programID)
                pending.remove("\(log.programID)/\(log.id)")
            } catch {}
        }
    }

    // MARK: - Fotoğraflar

    func photoURL(_ path: String) -> URL? { files.localURL(for: path) }

    /// Yerelde yoksa sunucudan indirir.
    func loadPhoto(_ path: String) async -> URL? {
        if let local = files.localURL(for: path) { return local }
        let destination = files.cacheURL(for: path)
        try? FileManager.default.createDirectory(at: files.cache, withIntermediateDirectories: true)
        do {
            try await media.download(path: path, to: destination, progress: { _ in })
            return destination
        } catch {
            return nil
        }
    }

    private func uploadPhoto(_ path: String) {
        guard let ownerID = userID else { return }
        let url = files.ownURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            var pending = pendingPhotos(ownerID); pending.remove(path); savePendingPhotos(pending, ownerID)
            return
        }
        let media = self.media
        Task { [weak self] in
            do {
                try await media.upload(fileURL: url, to: path, contentType: "image/jpeg", senderID: ownerID, progress: { _ in })
                guard let self else { return }
                var pending = self.pendingPhotos(ownerID)
                pending.remove(path)
                self.savePendingPhotos(pending, ownerID)
            } catch {}
        }
    }

    private func removeRemotePhoto(_ path: String) {
        files.remove(path)
        guard let ownerID = userID else { return }
        var pending = pendingPhotos(ownerID)
        pending.remove(path)
        savePendingPhotos(pending, ownerID)
        let media = self.media
        Task { await media.delete(paths: [path]) }
    }

    private func pendingPhotos(_ ownerID: String) -> Set<String> {
        Set(defaults.stringArray(forKey: "diet.pendingPhotos.\(ownerID)") ?? [])
    }

    private func savePendingPhotos(_ paths: Set<String>, _ ownerID: String) {
        defaults.set(Array(paths), forKey: "diet.pendingPhotos.\(ownerID)")
    }

    // MARK: - Eşitleme

    func syncAll() async {
        guard let context, let ownerID = userID, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Bekleyen silmeler.
        let programDeletes = PendingDeletionStore(userID: ownerID, scope: "DietProgram")
        for id in programDeletes.ids {
            if (try? await sync.deleteProgram(id: id)) != nil {
                try? await media.deletePrefix("diet/\(id)/")
                programDeletes.remove(id)
            }
        }
        let logDeletes = PendingDeletionStore(userID: ownerID, scope: "DietLog")
        for id in logDeletes.ids {
            let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { logDeletes.remove(id); continue }
            if (try? await sync.deleteLog(id: parts[1], programID: parts[0])) != nil { logDeletes.remove(id) }
        }

        do {
            let remote = try await sync.fetchMyPrograms(userID: ownerID)
            for program in remote where !programDeletes.ids.contains(program.id) {
                try merge(kind: .program, programID: program.id, docID: program.id, value: program,
                          updatedAt: program.updatedAt, context: context, ownerID: ownerID)
            }
            reload()
            for program in programs where program.isCurrentOrUpcoming() || program.dayOffset(of: .now) < program.dayCount + 60 {
                let logs = try await sync.fetchLogs(programID: program.id)
                for log in logs where !logDeletes.ids.contains("\(program.id)/\(log.id)") {
                    try merge(kind: .log, programID: program.id, docID: log.id, dayKey: log.dayKey, value: log,
                              updatedAt: log.updatedAt, context: context, ownerID: ownerID)
                }
                for note in try await sync.fetchNotes(programID: program.id) {
                    try merge(kind: .note, programID: program.id, docID: note.dayKey, dayKey: note.dayKey, value: note,
                              updatedAt: note.updatedAt, context: context, ownerID: ownerID)
                }
            }
            try context.save()
        } catch {
            // Çevrimdışı olabilir; yerel kayıtlar korunur.
        }
        reload()
        refreshMetrics()

        // Bekleyen yüklemeler.
        let pending = (try? context.fetch(FetchDescriptor<DietRecord>(predicate: #Predicate { $0.ownerID == ownerID && $0.needsSync }))) ?? []
        for record in pending {
            switch record.kind {
            case .program:
                if let program = record.program, (try? await sync.uploadProgram(program)) != nil {
                    markSynced(kind: .program, programID: program.id, docID: program.id, updatedAt: record.updatedAt)
                }
            case .log:
                if let log = record.log, (try? await sync.uploadLog(log)) != nil {
                    markSynced(kind: .log, programID: log.programID, docID: log.id, updatedAt: record.updatedAt)
                }
            case .note:
                if let note = record.note, (try? await sync.uploadNote(note)) != nil {
                    markSynced(kind: .note, programID: note.programID, docID: note.dayKey, updatedAt: record.updatedAt)
                }
            }
        }
        for path in pendingPhotos(ownerID) { uploadPhoto(path) }
        await refreshSocial()
    }

    /// Yorumlar, öneriler ve benimle paylaşılan programlar.
    func refreshSocial() async {
        guard let ownerID = userID else { return }
        for program in programs where program.isCurrentOrUpcoming() && !program.viewerIDs.isEmpty {
            if let comments = try? await sync.fetchComments(programID: program.id) { commentsByProgram[program.id] = comments }
            if let suggestions = try? await sync.fetchSuggestions(programID: program.id) { suggestionsByProgram[program.id] = suggestions }
        }
        if let shared = try? await sync.fetchSharedPrograms(viewerID: ownerID) {
            sharedPrograms = shared.filter { !$0.isArchived }.sorted { $0.startDate > $1.startDate }
        }
    }

    /// İnceleyen kişi: başkasının programının kayıtlarını, notlarını ve yorumlarını getirir.
    func loadShared(programID: String) async {
        do {
            if let program = try await sync.fetchProgram(id: programID) {
                sharedPrograms.removeAll { $0.id == programID }
                sharedPrograms.append(program)
            }
            logsByProgram[programID] = try await sync.fetchLogs(programID: programID)
            notesByProgram[programID] = try await sync.fetchNotes(programID: programID)
            commentsByProgram[programID] = try await sync.fetchComments(programID: programID)
            suggestionsByProgram[programID] = try await sync.fetchSuggestions(programID: programID)
        } catch {
            present(error)
        }
    }

    func loadComments(programID: String) async {
        if let comments = try? await sync.fetchComments(programID: programID) { commentsByProgram[programID] = comments }
    }

    /// Program süresindeki kilo ve ölçüler programa yazılır (inceleyen kişi görebilsin).
    private func refreshMetrics() {
        guard let context, let ownerID = userID else { return }
        for program in programs where program.isCurrentOrUpcoming() && !program.viewerIDs.isEmpty {
            let start = Calendar.current.date(byAdding: .day, value: -7, to: program.startDate) ?? program.startDate
            let end = program.endDate.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) } ?? .distantFuture
            let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(
                predicate: #Predicate { $0.ownerID == ownerID && $0.date >= start && $0.date < end },
                sortBy: [SortDescriptor(\.date)]))) ?? []
            let measures = (try? context.fetch(FetchDescriptor<MeasurementEntry>(
                predicate: #Predicate { $0.ownerID == ownerID && $0.date >= start && $0.date < end },
                sortBy: [SortDescriptor(\.date)]))) ?? []
            var summary = DietMetricsSummary()
            summary.weights = weights.map { DietMetricsSummary.Point(date: $0.date, value: $0.weightKg) }
            let fields: [(String, (MeasurementEntry) -> Double?)] = [
                ("Bel", { $0.waistCm }), ("Göğüs", { $0.chestCm }), ("Kol", { $0.armCm }),
                ("Ön kol", { $0.forearmCm }), ("Bilek", { $0.wristCm }), ("Bacak", { $0.thighCm }), ("Boyun", { $0.neckCm })
            ]
            for (name, value) in fields {
                let points = measures.compactMap { entry in value(entry).map { DietMetricsSummary.Point(date: entry.date, value: $0) } }
                if let first = points.first, let last = points.last { summary.measurements[name] = first == last ? [first] : [first, last] }
            }
            if summary.weights != program.metrics?.weights || summary.measurements != program.metrics?.measurements {
                var copy = program
                copy.metrics = summary
                try? save(copy)
            }
        }
    }

    // MARK: - Yorum ve öneri

    func addComment(programID: String, targetID: String, text: String, reaction: String?) async {
        guard let user else { return }
        let clean = String(text.trimmed.prefix(1000))
        guard !clean.isEmpty || reaction != nil else { return }
        let comment = DietComment(id: UUID().uuidString, programID: programID, targetID: targetID, authorID: user.id,
                                  authorName: user.displayName, text: clean, reaction: reaction, createdAt: .now)
        commentsByProgram[programID, default: []].append(comment)
        Haptics.success()
        do {
            try await sync.addComment(comment)
        } catch {
            commentsByProgram[programID]?.removeAll { $0.id == comment.id }
            present(error)
        }
    }

    func deleteComment(_ comment: DietComment) async {
        commentsByProgram[comment.programID]?.removeAll { $0.id == comment.id }
        try? await sync.deleteComment(id: comment.id, programID: comment.programID)
    }

    /// İnceleyen kişi programda değişiklik önerir; sahibi kabul edene kadar programa girmez.
    func suggest(programID: String, plan: DietPlan, note: String) async throws {
        guard let user, let program = program(id: programID) else { throw AppError.notAuthenticated }
        let suggestion = DietSuggestion(id: UUID().uuidString, programID: programID, authorID: user.id, authorName: user.displayName,
                                        note: String(note.trimmed.prefix(1000)), basedOnVersion: program.latest.number, plan: plan,
                                        status: .pending, createdAt: .now, decidedAt: nil)
        try await sync.createSuggestion(suggestion)
        suggestionsByProgram[programID, default: []].insert(suggestion, at: 0)
        Haptics.success()
        showToast("Öneri gönderildi")
    }

    func decide(_ suggestion: DietSuggestion, accept: Bool, effectiveFrom: Date) async {
        do {
            if accept {
                let note = suggestion.note.isEmpty ? "\(suggestion.authorName) önerdi" : "\(suggestion.authorName): \(suggestion.note)"
                try savePlan(suggestion.plan, for: suggestion.programID, effectiveFrom: effectiveFrom, note: note,
                             author: (suggestion.authorID, suggestion.authorName))
            }
            try await sync.decideSuggestion(id: suggestion.id, programID: suggestion.programID,
                                            status: accept ? .accepted : .rejected, at: .now)
            if let index = suggestionsByProgram[suggestion.programID]?.firstIndex(where: { $0.id == suggestion.id }) {
                suggestionsByProgram[suggestion.programID]?[index].status = accept ? .accepted : .rejected
                suggestionsByProgram[suggestion.programID]?[index].decidedAt = .now
            }
            showToast(accept ? "Yeni sürüm uygulandı" : "Öneri reddedildi")
        } catch {
            present(error)
        }
    }

    // MARK: - Sohbette paylaşım

    /// Programı bir arkadaşa gönderir: teklif belgesi + sohbet kartı.
    func share(_ programID: String, with room: ChatRoomDTO) async {
        guard let user, let program = program(id: programID),
              let friend = room.members.first(where: { $0 != user.id }) else { return }
        let offer = DietOffer(id: UUID().uuidString, fromID: user.id, fromName: user.displayName, toID: friend,
                              name: program.name, plan: program.version(on: .now).plan, status: .pending,
                              acceptedProgramID: nil, createdAt: .now, decidedAt: nil)
        do {
            try await sync.createOffer(offer)
            let message = ChatMessageDTO(id: "diet-\(offer.id)", senderID: user.id, type: .diet, text: "",
                                         createdAt: .now, diet: ChatDietInfo(offer: offer))
            try await chat.sendMessage(message, chatID: room.id)
            try? await notifier?.notify(chatID: room.id, messageID: message.id)
            Haptics.success()
            showToast("Program \(room.names[friend] ?? "arkadaşına") gönderildi")
        } catch {
            present(error)
        }
    }

    func fetchOffer(_ id: String) async -> DietOffer? {
        try? await sync.fetchOffer(id: id)
    }

    /// Teklifi kabul eder: programın kopyası bana ait yeni bir program olur.
    @discardableResult
    func accept(_ offer: DietOffer, startDate: Date, endBehavior: DietEndBehavior, allowViewer: Bool) async throws -> DietProgram {
        let program = try createProgram(name: offer.name, plan: offer.plan, startDate: startDate, endBehavior: endBehavior,
                                        note: "\(offer.fromName) gönderdi", sharedBy: (offer.fromID, offer.fromName),
                                        allowViewer: allowViewer)
        try? await sync.decideOffer(id: offer.id, status: .accepted, programID: program.id, at: .now)
        showToast("\(offer.name) programlarına eklendi")
        return program
    }

    func decline(_ offer: DietOffer) async {
        try? await sync.decideOffer(id: offer.id, status: .declined, programID: nil, at: .now)
    }

    // MARK: - Yardımcılar

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func present(_ error: Error) {
        errorMessage = AppError.map(error).errorDescription
        Haptics.error()
    }

    private func upsert<T: Encodable>(kind: DietRecordKind, programID: String, docID: String, dayKey: String = "",
                                      value: T, context: ModelContext, ownerID: String) throws {
        let data = try DietJSON.encoder.encode(value)
        let key = DietRecord.makeKey(ownerID: ownerID, kind: kind, programID: programID, docID: docID)
        let now = Date.now
        if let record = try context.fetch(FetchDescriptor<DietRecord>(predicate: #Predicate { $0.key == key })).first {
            record.json = data
            record.dayKey = dayKey
            record.needsSync = true
            record.updatedAt = now
        } else {
            context.insert(DietRecord(ownerID: ownerID, kind: kind, programID: programID, docID: docID, dayKey: dayKey,
                                      json: data, needsSync: true, updatedAt: now))
        }
        do { try context.save() } catch { throw AppError.unknown(error.localizedDescription) }
    }

    /// Sunucudan gelen: bekleyen yerel değişiklik varsa yerel kazanır, yoksa daha yeni olan.
    private func merge<T: Encodable>(kind: DietRecordKind, programID: String, docID: String, dayKey: String = "",
                                     value: T, updatedAt: Date, context: ModelContext, ownerID: String) throws {
        let key = DietRecord.makeKey(ownerID: ownerID, kind: kind, programID: programID, docID: docID)
        let data = try DietJSON.encoder.encode(value)
        if let record = try context.fetch(FetchDescriptor<DietRecord>(predicate: #Predicate { $0.key == key })).first {
            guard !record.needsSync, updatedAt > record.updatedAt else { return }
            record.json = data
            record.updatedAt = updatedAt
        } else {
            context.insert(DietRecord(ownerID: ownerID, kind: kind, programID: programID, docID: docID, dayKey: dayKey,
                                      json: data, needsSync: false, updatedAt: updatedAt))
        }
    }

    private func markSynced(kind: DietRecordKind, programID: String, docID: String, updatedAt: Date) {
        guard let context, let ownerID = userID else { return }
        let key = DietRecord.makeKey(ownerID: ownerID, kind: kind, programID: programID, docID: docID)
        guard let record = try? context.fetch(FetchDescriptor<DietRecord>(predicate: #Predicate { $0.key == key })).first else { return }
        // Yükleme sırasında yeni bir değişiklik olduysa işaret kalır.
        if abs(record.updatedAt.timeIntervalSince(updatedAt)) < 1 || record.updatedAt <= updatedAt {
            record.needsSync = false
            try? context.save()
        }
    }

    private func scheduleUpload(programID: String) {
        guard let context, let ownerID = userID else { return }
        let key = DietRecord.makeKey(ownerID: ownerID, kind: .program, programID: programID, docID: programID)
        guard let record = try? context.fetch(FetchDescriptor<DietRecord>(predicate: #Predicate { $0.key == key })).first,
              let program = record.program else { return }
        let updatedAt = record.updatedAt
        let sync = self.sync
        enqueue { [weak self] in
            do {
                try await sync.uploadProgram(program)
                self?.markSynced(kind: .program, programID: programID, docID: programID, updatedAt: updatedAt)
            } catch {}
        }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = uploadChain
        uploadChain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}
