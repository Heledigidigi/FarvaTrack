import XCTest
import SwiftData
@testable import FarvaTrack

final class MockAccountService: AccountDeleting {
    var providerIDs: [String] = ["password"]
    var online = true
    var reauthError: Error?
    var remoteDeleteError: Error?
    var revokeError: Error?
    private(set) var calls: [String] = []
    private(set) var includedAdminCollections: Bool?

    func isOnline() async -> Bool { calls.append("online"); return online }

    func reauthenticate(password: String) async throws {
        calls.append("reauth")
        if let reauthError { throw reauthError }
    }

    func reauthenticateWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        calls.append("reauthApple")
        if let reauthError { throw reauthError }
    }

    func deleteRemoteData(userID: String, includeAdminCollections: Bool) async throws {
        calls.append("remote")
        includedAdminCollections = includeAdminCollections
        if let remoteDeleteError { throw remoteDeleteError }
    }

    func deleteProfilePhoto(userID: String) async { calls.append("photo") }

    func revokeAppleToken(authorizationCode: String) async throws {
        calls.append("revoke")
        if let revokeError { throw revokeError }
    }

    func deleteAuthUser() async throws { calls.append("authDelete") }
}

private let allModels: [any PersistentModel.Type] = [
    LocalUserProfile.self, Workout.self, WorkoutEntry.self, Exercise.self, MealEntry.self, CustomFood.self,
    FavoriteFood.self, WaterEntry.self, SleepEntry.self, WeightEntry.self, MeasurementEntry.self,
    WasteEntry.self, BadgeUnlock.self
]

@MainActor
final class AccountDeletionViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: MockAccountService!
    private var defaults: UserDefaults!
    private var sut: AccountDeletionViewModel!
    private var user: AppUser!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: Schema(allModels),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        defaults = UserDefaults(suiteName: "deletion-tests")
        defaults.removePersistentDomain(forName: "deletion-tests")
        service = MockAccountService()
        user = AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test")

        sut = AccountDeletionViewModel(service: service, defaults: defaults)
        sut.configure(user: user, context: context)
        sut.confirmed = true
        sut.password = "sifre123"

        context.insert(WaterEntry(ownerID: "uid-1", amountMl: 200))
        try context.save()
    }

    func testSuccessfulDeletionRunsStepsInOrderAndWipesLocalData() async throws {
        await sut.deleteWithPassword()

        XCTAssertEqual(sut.phase, .finished)
        XCTAssertEqual(service.calls, ["online", "reauth", "remote", "photo", "authDelete"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WaterEntry>()), 0)
    }

    func testOfflineStopsBeforeAnyDeletion() async throws {
        service.online = false
        await sut.deleteWithPassword()

        XCTAssertNotNil(sut.failureMessage)
        XCTAssertEqual(service.calls, ["online"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WaterEntry>()), 1)
    }

    func testWrongPasswordDeletesNothing() async throws {
        service.reauthError = AppError.wrongCredentials
        await sut.deleteWithPassword()

        XCTAssertEqual(service.calls, ["online", "reauth"])
        XCTAssertNotNil(sut.failureMessage)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WaterEntry>()), 1)
    }

    func testRemoteFailureKeepsAccountAndLocalData() async throws {
        service.remoteDeleteError = AppError.network
        await sut.deleteWithPassword()

        XCTAssertFalse(service.calls.contains("authDelete"))
        XCTAssertNotNil(sut.failureMessage)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WaterEntry>()), 1)
    }

    func testButtonRequiresConfirmationAndPassword() {
        sut.confirmed = false
        XCTAssertFalse(sut.canSubmitPassword)
        sut.confirmed = true
        sut.password = ""
        XCTAssertFalse(sut.canSubmitPassword)
    }

    func testAdminAccountsIncludeAdminCollections() async {
        var admin = user!
        admin.role = "admin"
        sut.configure(user: admin, context: context)

        await sut.deleteWithPassword()
        XCTAssertEqual(service.includedAdminCollections, true)
    }

    func testProviderDetection() {
        service.providerIDs = ["apple.com"]
        sut.configure(user: user, context: context)
        XCTAssertTrue(sut.usesApple)
        XCTAssertFalse(sut.usesPassword)
    }
}

@MainActor
final class LocalDataCleanerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: Schema(allModels),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        defaults = UserDefaults(suiteName: "cleaner-tests")
        defaults.removePersistentDomain(forName: "cleaner-tests")
    }

    func testWipeRemovesOnlyTheGivenUsersData() throws {
        context.insert(WaterEntry(ownerID: "A", amountMl: 200))
        context.insert(WaterEntry(ownerID: "B", amountMl: 300))
        context.insert(WeightEntry(ownerID: "A", date: .now, weightKg: 70))
        context.insert(BadgeUnlock(ownerID: "A", badge: .firstWorkout))
        try context.save()

        LocalDataCleaner.wipe(userID: "A", context: context, defaults: defaults, clearNotifications: false)

        let remainingWater = try context.fetch(FetchDescriptor<WaterEntry>())
        XCTAssertEqual(remainingWater.count, 1)
        XCTAssertEqual(remainingWater.first?.ownerID, "B")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WeightEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BadgeUnlock>()), 0)
    }

    func testWipeRemovesWorkoutsWithTheirEntries() throws {
        let workout = Workout(ownerID: "A", title: "Test", date: .now)
        context.insert(workout)
        let template = ExerciseLibrary.template(forKey: "preset.bench-press")!
        let entry = WorkoutEntry(order: 0, template: template, durationMinutes: 0, sets: [WorkoutSet(reps: 10, weightKg: 50)])
        context.insert(entry)
        workout.entries.append(entry)
        try context.save()

        LocalDataCleaner.wipe(userID: "A", context: context, defaults: defaults, clearNotifications: false)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutEntry>()), 0)
    }

    func testWipeClearsPerUserDefaultsKeys() {
        defaults.set(["x"], forKey: "pendingWorkoutDeletes.A")
        defaults.set(Date.now, forKey: "bodyMetricsLastPull.A")
        defaults.set(true, forKey: "badgesSeeded.A")
        defaults.set(["y"], forKey: "pendingWorkoutDeletes.B")

        LocalDataCleaner.wipe(userID: "A", context: context, defaults: defaults, clearNotifications: false)

        XCTAssertNil(defaults.object(forKey: "pendingWorkoutDeletes.A"))
        XCTAssertNil(defaults.object(forKey: "bodyMetricsLastPull.A"))
        XCTAssertFalse(defaults.bool(forKey: "badgesSeeded.A"))
        XCTAssertNotNil(defaults.object(forKey: "pendingWorkoutDeletes.B"))        // başka kullanıcıya dokunulmadı
    }

    func testUnsyncedCountCountsOnlyPendingRecordsOfTheUser() throws {
        let pending = WaterEntry(ownerID: "A", amountMl: 200)             // needsSync = true
        let synced = WaterEntry(ownerID: "A", amountMl: 300)
        synced.needsSync = false
        let other = WeightEntry(ownerID: "B", date: .now, weightKg: 70)
        context.insert(pending)
        context.insert(synced)
        context.insert(other)
        try context.save()

        XCTAssertEqual(LocalDataCleaner.unsyncedCount(userID: "A", context: context), 1)
    }
}