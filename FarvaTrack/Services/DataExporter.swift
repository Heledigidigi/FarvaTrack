import Foundation
import SwiftData

/// Kullanıcının cihazdaki tüm kayıtlarını tek bir JSON dosyasına yazar (veri taşınabilirliği).
struct DataExport: Codable {
    struct Profile: Codable {
        var displayName: String
        var email: String
        var birthDate: Date?
        var heightCm: Double?
        var weightKg: Double?
        var dailyCalorieGoal: Int
        var dailyWaterGoalMl: Int
        var dailyStepGoal: Int
        var sleepGoalHours: Double
    }

    var exportedAt: Date
    var profile: Profile
    var workouts: [WorkoutDTO]
    var meals: [MealDTO]
    var water: [WaterDTO]
    var sleep: [SleepDTO]
    var weight: [WeightDTO]
    var measurements: [MeasurementDTO]
    var biologicalWaste: [WasteDTO]
    var workoutTemplates: [WorkoutTemplateDTO]
    var trainingPrograms: [TrainingProgramDTO]
    var manualSteps: [ManualStepDTO]
    /// Cihazda önbelleğe alınmış sohbet mesajları (iki tarafın mesajları; "benden sil" ile gizlenenler hariç).
    var chatMessages: [ChatMessageExport]
    /// Sticker kütüphanesi (bilgiler; PNG dosyaları Storage'da).
    var stickers: [StickerDTO]
    /// Sohbet üstüne yerleştirilen sticker'lar (konum bilgileri).
    var chatPlacements: [ChatPlacementExport]
    /// Kendi tasarladığım baloncuk stilleri (JSON).
    var bubbleStyles: [BubbleStyleExport]
}

@MainActor
enum DataExporter {
    static func makeExport(user: AppUser, context: ModelContext, now: Date = .now) throws -> DataExport {
        let owner = user.id
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] { try context.fetch(descriptor) }

        return DataExport(
            exportedAt: now,
            profile: .init(
                displayName: user.displayName, email: user.email, birthDate: user.birthDate,
                heightCm: user.heightCm, weightKg: user.weightKg,
                dailyCalorieGoal: user.dailyCalorieGoal, dailyWaterGoalMl: user.dailyWaterGoalMl,
                dailyStepGoal: user.dailyStepGoal, sleepGoalHours: user.sleepGoalHours
            ),
            workouts: try fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.date)])).map(\.dto),
            meals: try fetch(FetchDescriptor<MealEntry>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.date)])).map(\.dto),
            water: try fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.date)])).map(\.dto),
            sleep: try fetch(FetchDescriptor<SleepEntry>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.day)])).map(\.dto),
            weight: try fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.date)])).map(\.dto),
            measurements: try fetch(FetchDescriptor<MeasurementEntry>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.date)])).map(\.dto),
            biologicalWaste: try fetch(FetchDescriptor<WasteEntry>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.date)])).map(\.dto),
            workoutTemplates: try fetch(FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.name)])).map(\.dto),
            trainingPrograms: try fetch(FetchDescriptor<TrainingProgram>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.createdAt)])).map(\.dto),
            manualSteps: try fetch(FetchDescriptor<ManualStepEntry>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.day)])).map(\.dto),
            chatMessages: try fetch(FetchDescriptor<ChatMessageRecord>(predicate: #Predicate { $0.ownerID == owner && !$0.hiddenForMe }, sortBy: [SortDescriptor(\.createdAt)])).map(ChatMessageExport.init(record:)),
            stickers: try fetch(FetchDescriptor<StickerRecord>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.createdAt)])).map(\.dto),
            chatPlacements: try fetch(FetchDescriptor<ChatPlacementRecord>(predicate: #Predicate { $0.ownerID == owner }, sortBy: [SortDescriptor(\.createdAt)])).map(ChatPlacementExport.init(record:)),
            bubbleStyles: try fetch(FetchDescriptor<BubbleStyleRecord>(predicate: #Predicate { $0.cacheOwnerID == owner && $0.styleOwnerID == owner }, sortBy: [SortDescriptor(\.updatedAt)])).map(BubbleStyleExport.init(record:))
        )
    }

    /// Paylaşılabilir geçici dosya: `FarvaTrack-veriler-2026-11-21.json`
    static func writeFile(user: AppUser, context: ModelContext, now: Date = .now) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(makeExport(user: user, context: context, now: now))

        let name = "FarvaTrack-veriler-\(WasteAnalyzer.dayKey(now)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
