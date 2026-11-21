import Foundation
import UserNotifications

// MARK: - Ayar modelleri
struct WaterReminderSettings: Codable, Equatable {
    var isEnabled = false
    var intervalMinutes = 120
    var startHour = 8
    var endHour = 22

    private static let key = "waterReminderSettings"

    static func load(defaults: UserDefaults = .standard) -> WaterReminderSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(WaterReminderSettings.self, from: data) else {
            return WaterReminderSettings()
        }
        return settings
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}

struct WeighInReminderSettings: Codable, Equatable {
    var isEnabled = false
    /// Calendar.weekday: 1 = Pazar … 7 = Cumartesi. Varsayılan Pazartesi.
    var weekday = 2
    var hour = 8
    var minute = 0

    private static let key = "weighInReminderSettings"

    static func load(defaults: UserDefaults = .standard) -> WeighInReminderSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(WeighInReminderSettings.self, from: data) else {
            return WeighInReminderSettings()
        }
        return settings
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}

// MARK: - Protokoller (testte taklit edilir)
protocol NotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func scheduleWaterReminders(settings: WaterReminderSettings) async throws
    func cancelWaterReminders() async
}

protocol SleepReminderScheduling {
    func scheduleSleepReminder(hour: Int, minute: Int, bedtimeText: String) async throws
    func cancelSleepReminder() async
}

protocol WeighInReminderScheduling {
    func scheduleWeighInReminder(weekday: Int, hour: Int, minute: Int) async throws
    func cancelWeighInReminder() async
}

/// Program günlerinde antrenman hatırlatıcısı (cihaza özel ayar).
struct WorkoutReminderSettings: Codable, Equatable {
    var isEnabled = false
    var hour = 18
    var minute = 0

    private static let key = "workoutReminderSettings"

    static func load(defaults: UserDefaults = .standard) -> WorkoutReminderSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(WorkoutReminderSettings.self, from: data) else {
            return WorkoutReminderSettings()
        }
        return settings
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}

/// Haftanın bir günü için hatırlatıcı içeriği. `weekday`: Calendar biçimi (1 = Pazar … 7 = Cumartesi).
struct WorkoutReminderSlot: Equatable {
    let weekday: Int
    let body: String
}

protocol WorkoutReminderScheduling {
    func scheduleWorkoutReminders(_ slots: [WorkoutReminderSlot], hour: Int, minute: Int) async throws
    func cancelWorkoutReminders() async
}

/// Canlı antrenmanda dinlenme bitince (uygulama arka plandayken de) haber verir.
protocol RestTimerScheduling {
    func scheduleRestEnd(after seconds: TimeInterval, exerciseName: String) async
    func cancelRestEnd() async
}

extension UNAuthorizationStatus {
    var allowsNotifications: Bool {
        self == .authorized || self == .provisional || self == .ephemeral
    }
}

// MARK: - Yerel bildirimler
final class NotificationManager: NotificationScheduling, SleepReminderScheduling, WeighInReminderScheduling, RestTimerScheduling, WorkoutReminderScheduling {
    static let shared = NotificationManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    private static let waterPrefix = "water.reminder."
    private static let sleepReminderID = "sleep.reminder"
    private static let weighInReminderID = "weighin.reminder"
    private static let restTimerID = "workout.rest"
    private static let workoutPrefix = "workout.reminder."

    private static let waterMessages = [
        "Bir bardak su içmeye ne dersin?",
        "Vücudun suya ihtiyaç duyuyor olabilir.",
        "Hedefine yaklaşmak için bir yudum al.",
        "Kısa bir su molası zamanı."
    ]

    /// Başlangıçtan bitişe kadar aralıkla hatırlatma saatleri (iOS'un 64 bekleyen bildirim sınırı nedeniyle en fazla 30).
    static func reminderTimes(for settings: WaterReminderSettings) -> [DateComponents] {
        guard settings.intervalMinutes >= 30, settings.endHour > settings.startHour else { return [] }
        var minutes = settings.startHour * 60
        let end = settings.endHour * 60
        var result: [DateComponents] = []
        while minutes <= end, result.count < 30 {
            result.append(DateComponents(hour: minutes / 60, minute: minutes % 60))
            minutes += settings.intervalMinutes
        }
        return result
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    // MARK: Su
    func scheduleWaterReminders(settings: WaterReminderSettings) async throws {
        await cancelWaterReminders()

        for (index, time) in Self.reminderTimes(for: settings).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Su Molası"
            content.body = Self.waterMessages[index % Self.waterMessages.count]
            content.sound = .default
            content.userInfo = ["url": "farvatrack://water"]

            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
            let id = "\(Self.waterPrefix)\(String(format: "%02d%02d", time.hour ?? 0, time.minute ?? 0))"
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    func cancelWaterReminders() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.waterPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: Uyku
    func scheduleSleepReminder(hour: Int, minute: Int, bedtimeText: String) async throws {
        await cancelSleepReminder()

        let content = UNMutableNotificationContent()
        content.title = "Yatma Vakti Yaklaşıyor"
        content.body = "Hedef uykuna ulaşmak için \(bedtimeText) civarında yatmayı düşün."
        content.sound = .default
        content.userInfo = ["url": "farvatrack://sleep"]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour, minute: minute),
            repeats: true
        )
        try await center.add(UNNotificationRequest(identifier: Self.sleepReminderID, content: content, trigger: trigger))
    }

    func cancelSleepReminder() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.sleepReminderID])
    }

    // MARK: Tartı
    func scheduleWeighInReminder(weekday: Int, hour: Int, minute: Int) async throws {
        await cancelWeighInReminder()

        let content = UNMutableNotificationContent()
        content.title = "Haftalık Tartı Zamanı"
        content.body = "Aynı saatte ve benzer koşullarda tartılmak, karşılaştırmayı kolaylaştırır."
        content.sound = .default
        content.userInfo = ["url": "farvatrack://weight"]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour, minute: minute, weekday: weekday),
            repeats: true
        )
        try await center.add(UNNotificationRequest(identifier: Self.weighInReminderID, content: content, trigger: trigger))
    }

    func cancelWeighInReminder() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.weighInReminderID])
    }

    // MARK: Dinlenme sayacı
    /// İzin yoksa sessizce atlanır; uygulama öndeyse titreşim zaten ViewModel'den gelir.
    func scheduleRestEnd(after seconds: TimeInterval, exerciseName: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.restTimerID])
        guard seconds >= 1, await authorizationStatus().allowsNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "Dinlenme bitti"
        content.body = "Sıradaki set: \(exerciseName)"
        content.sound = .default
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.restTimerID, content: content, trigger: trigger))
    }

    func cancelRestEnd() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.restTimerID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.restTimerID])
    }

    // MARK: Antrenman hatırlatıcısı
    func scheduleWorkoutReminders(_ slots: [WorkoutReminderSlot], hour: Int, minute: Int) async throws {
        await cancelWorkoutReminders()
        for slot in slots {
            let content = UNMutableNotificationContent()
            content.title = "Antrenman günü 💪"
            content.body = slot.body
            content.sound = .default
            content.userInfo = ["url": "farvatrack://exercise"]

            var components = DateComponents()
            components.weekday = slot.weekday
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await center.add(UNNotificationRequest(identifier: "\(Self.workoutPrefix)\(slot.weekday)", content: content, trigger: trigger))
        }
    }

    func cancelWorkoutReminders() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.workoutPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
