import Foundation
import SwiftData
import UserNotifications

/// Bu cihazdaki bir kullanıcıya ait yerel verileri temizler (buluttaki veriye dokunmaz).
enum LocalDataCleaner {
    private static let pendingScopes = ["Workout", "Meal", "Water", "Sleep", "Weight", "Measurement", "Waste"]

    @MainActor
    static func wipe(
        userID: String,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        clearNotifications: Bool = true
    ) {
        try? context.delete(model: LocalUserProfile.self, where: #Predicate { $0.uid == userID })
        try? context.delete(model: Workout.self, where: #Predicate { $0.ownerID == userID })
        // Toplu silme ilişki kurallarını uygulamayabilir; sahipsiz kalan egzersiz satırlarını da temizle.
        try? context.delete(model: WorkoutEntry.self, where: #Predicate { $0.workout == nil })
        try? context.delete(model: Exercise.self, where: #Predicate { $0.ownerID == userID })
        try? context.delete(model: MealEntry.self, where: #Predicate { $0.ownerID == userID })
        try? context.delete(model: CustomFood.self, where: #Predicate { $0.ownerID == userID })
        try? context.delete(model: FavoriteFood.self, where: #Predicate { $0.ownerID == userID })
        try? context.delete(model: WaterEntry.self, where: #Predicate { $0.ownerID == userID })
        try? context.delete(model: SleepEntry.self, where: #Predicate { $0.ownerID == userID })
        try? context.delete(model: WeightEntry.self, where: #Predicate { $0.ownerID == userID })
        try? context.delete(model: MeasurementEntry.self, where: #Predicate { $0.ownerID == userID })
        try? context.delete(model: WasteEntry.self, where: #Predicate { $0.ownerID == userID })
        try? context.delete(model: BadgeUnlock.self, where: #Predicate { $0.ownerID == userID })
        try? context.save()

        for scope in pendingScopes {
            defaults.removeObject(forKey: "pending\(scope)Deletes.\(userID)")
        }
        for key in [
            "bodyMetricsLastPull.\(userID)", "badgesSeeded.\(userID)",
            "librarySync.dirty.\(userID)", "librarySync.localStamp.\(userID)", "librarySync.appliedRemote.\(userID)",
            "waterReminderSettings", "sleepSettings", "weighInReminderSettings"
        ] {
            defaults.removeObject(forKey: key)
        }

        SharedStore.clearAll()
        if clearNotifications {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
    }

    /// Henüz buluta yüklenmemiş kayıt sayısı (cihaz verilerini silmeden önce uyarı için).
    @MainActor
    static func unsyncedCount(userID: String, context: ModelContext) -> Int {
        let workouts = (try? context.fetchCount(FetchDescriptor<Workout>(predicate: #Predicate { $0.ownerID == userID && $0.needsSync }))) ?? 0
        let meals = (try? context.fetchCount(FetchDescriptor<MealEntry>(predicate: #Predicate { $0.ownerID == userID && $0.needsSync }))) ?? 0
        let water = (try? context.fetchCount(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.ownerID == userID && $0.needsSync }))) ?? 0
        let sleep = (try? context.fetchCount(FetchDescriptor<SleepEntry>(predicate: #Predicate { $0.ownerID == userID && $0.needsSync }))) ?? 0
        let weights = (try? context.fetchCount(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.ownerID == userID && $0.needsSync }))) ?? 0
        let measurements = (try? context.fetchCount(FetchDescriptor<MeasurementEntry>(predicate: #Predicate { $0.ownerID == userID && $0.needsSync }))) ?? 0
        let waste = (try? context.fetchCount(FetchDescriptor<WasteEntry>(predicate: #Predicate { $0.ownerID == userID && $0.needsSync }))) ?? 0
        return workouts + meals + water + sleep + weights + measurements + waste
    }
}