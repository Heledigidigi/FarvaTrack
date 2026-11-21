import Foundation
import SwiftData

/// Hesap silindiğinde cihazdaki tüm kullanıcı verilerini temizler.
@MainActor
enum LocalDataCleaner {
    /// Bekleyen silme / gün kuyruklarının kapsamları (`pending<Scope>Deletes.<uid>`).
    static let pendingScopes = ["Workout", "Meal", "Water", "Sleep", "Weight", "Measurement", "Waste", "WasteDaily", "Library", "Template", "Program", "ManualStep"]

    static func purge(ownerID: String, context: ModelContext, defaults: UserDefaults = .standard) throws {
        try delete(Workout.self, context: context) { $0.ownerID == ownerID }
        try delete(Exercise.self, context: context) { $0.ownerID == ownerID }
        try delete(MealEntry.self, context: context) { $0.ownerID == ownerID }
        try delete(CustomFood.self, context: context) { $0.ownerID == ownerID }
        try delete(FavoriteFood.self, context: context) { $0.ownerID == ownerID }
        try delete(WaterEntry.self, context: context) { $0.ownerID == ownerID }
        try delete(SleepEntry.self, context: context) { $0.ownerID == ownerID }
        try delete(WeightEntry.self, context: context) { $0.ownerID == ownerID }
        try delete(MeasurementEntry.self, context: context) { $0.ownerID == ownerID }
        try delete(WasteEntry.self, context: context) { $0.ownerID == ownerID }
        try delete(WorkoutTemplate.self, context: context) { $0.ownerID == ownerID }
        try delete(TrainingProgram.self, context: context) { $0.ownerID == ownerID }
        try delete(ManualStepEntry.self, context: context) { $0.ownerID == ownerID }
        try delete(ChatMessageRecord.self, context: context) { $0.ownerID == ownerID }
        try delete(ChatPendingOperation.self, context: context) { $0.ownerID == ownerID }
        try delete(LocalUserProfile.self, context: context) { $0.uid == ownerID }
        try context.save()

        for scope in pendingScopes {
            defaults.removeObject(forKey: "pending\(scope)Deletes.\(ownerID)")
        }
        UserDefaultsLiveSessionStore(defaults: defaults).clear(userID: ownerID)
        ChatRoomCache(defaults: defaults).clear(userID: ownerID)
        // Sohbet fotoğraf/videoları (gönderilmeyi bekleyenler ve indirilenler).
        ChatMediaFiles.live.removeAll()
    }

    /// Nesneleri tek tek siler; böylece ilişkilerdeki `cascade` kuralı (antrenman → egzersizler) uygulanır.
    private static func delete<T: PersistentModel>(
        _ type: T.Type,
        context: ModelContext,
        where predicate: (T) -> Bool
    ) throws {
        for object in try context.fetch(FetchDescriptor<T>()) where predicate(object) {
            context.delete(object)
        }
    }
}
