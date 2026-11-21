import Foundation
import UserNotifications
@testable import FarvaTrack

/// Tüm hatırlatıcı protokollerini taklit eder.
final class MockNotificationScheduler: NotificationScheduling, SleepReminderScheduling, WeighInReminderScheduling, WorkoutReminderScheduling {
    var status: UNAuthorizationStatus = .authorized
    var grantOnRequest = true
    private(set) var requestedAuthorization = false
    private(set) var waterScheduled: WaterReminderSettings?
    private(set) var waterCancelled = false
    private(set) var sleepScheduled: (hour: Int, minute: Int, bedtimeText: String)?
    private(set) var sleepCancelled = false
    private(set) var weighInScheduled: (weekday: Int, hour: Int, minute: Int)?
    private(set) var weighInCancelled = false

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        requestedAuthorization = true
        status = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }

    func scheduleWaterReminders(settings: WaterReminderSettings) async throws { waterScheduled = settings }
    func cancelWaterReminders() async { waterCancelled = true }

    func scheduleSleepReminder(hour: Int, minute: Int, bedtimeText: String) async throws {
        sleepScheduled = (hour, minute, bedtimeText)
    }
    func cancelSleepReminder() async { sleepCancelled = true }

    func scheduleWeighInReminder(weekday: Int, hour: Int, minute: Int) async throws {
        weighInScheduled = (weekday, hour, minute)
    }
    func cancelWeighInReminder() async { weighInCancelled = true }

    private(set) var workoutSlots: [WorkoutReminderSlot]?
    private(set) var workoutTime: (hour: Int, minute: Int)?
    private(set) var workoutCancelled = 0
    func scheduleWorkoutReminders(_ slots: [WorkoutReminderSlot], hour: Int, minute: Int) async throws {
        workoutSlots = slots
        workoutTime = (hour, minute)
    }
    func cancelWorkoutReminders() async { workoutCancelled += 1 }
}

/// Her test için boş, izole bir UserDefaults.
func makeTestDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "test.\(name)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// Arka plan `Task`'larının (yükleme/silme) bitmesine fırsat tanır.
func settleTasks() async {
    for _ in 0..<5 { await Task.yield() }
    try? await Task.sleep(nanoseconds: 50_000_000)
}

func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}
