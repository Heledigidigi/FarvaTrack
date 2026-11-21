import XCTest
import SwiftData
@testable import FarvaTrack

final class ProfileDraftTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)   // Kasım 2026

    private func user(age: Int?) -> AppUser {
        var user = AppUser.makeNew(id: "u1", email: "a@b.com", displayName: "Deniz Yılmaz")
        user.birthDate = age.flatMap { Calendar.current.date(byAdding: .year, value: -$0, to: now) }
        user.heightCm = 175
        user.weightKg = 70
        user.gender = .male
        return user
    }

    func testValidDraftPasses() {
        XCTAssertNil(ProfileDraft(user: user(age: 30)).validationError(now: now))
    }

    func testValidationErrors() {
        var draft = ProfileDraft(user: user(age: 30))
        draft.displayName = " A "
        XCTAssertNotNil(draft.validationError(now: now))

        draft = ProfileDraft(user: user(age: 30))
        draft.heightCm = 80
        XCTAssertNotNil(draft.validationError(now: now))

        draft = ProfileDraft(user: user(age: 30))
        draft.dailyCalorieGoal = 900
        XCTAssertNotNil(draft.validationError(now: now))

        draft = ProfileDraft(user: user(age: 5))
        XCTAssertNotNil(draft.validationError(now: now))
    }

    func testMinorCannotChooseWeightLoss() {
        var draft = ProfileDraft(user: user(age: 16))
        draft.goal = .loseWeight
        XCTAssertTrue(draft.isMinor(now: now))
        XCTAssertNotNil(draft.validationError(now: now))

        // Öneri hesabı da kalori açığı vermez.
        let recommendation = draft.recommendation(weightKg: 70, now: now)!
        var maintain = draft
        maintain.goal = .maintain
        XCTAssertEqual(recommendation.calorieGoal, maintain.recommendation(weightKg: 70, now: now)!.calorieGoal)
    }

    func testRecommendationNeedsCompleteProfile() {
        var draft = ProfileDraft(user: user(age: 30))
        XCTAssertNil(draft.recommendation(weightKg: nil, now: now))
        draft.gender = nil
        XCTAssertNil(draft.recommendation(weightKg: 70, now: now))
    }

    func testApplyRecommendationAndAppliedUser() {
        var draft = ProfileDraft(user: user(age: 30))
        let recommendation = draft.recommendation(weightKg: 70, now: now)!
        draft.applyRecommendation(recommendation)
        draft.displayName = "  Deniz  "
        let updated = draft.applied(to: user(age: 30))
        XCTAssertEqual(updated.displayName, "Deniz")
        XCTAssertEqual(updated.dailyCalorieGoal, recommendation.calorieGoal)
        XCTAssertEqual(updated.dailyStepGoal, recommendation.stepGoal)
        XCTAssertEqual(updated.weightKg, 70, "kilo profil düzenlemede değişmez")
        XCTAssertNil(draft.validationError(now: now))
    }
}

final class UserDocumentEncoderTests: XCTestCase {
    func testNilFieldsAreDeletedAndRoleIsNeverWritten() throws {
        var user = AppUser.makeNew(id: "u1", email: "a@b.com", displayName: "Test")
        user.role = "admin"
        user.heightCm = 180
        let fields = try UserDocumentEncoder.fields(for: user, deleteMarker: "SİL")

        XCTAssertNil(fields["role"])
        XCTAssertEqual(fields["heightCm"] as? Double, 180)
        XCTAssertEqual(fields["targetWeightKg"] as? String, "SİL")
        XCTAssertEqual(fields["photoURL"] as? String, "SİL")
        XCTAssertEqual(fields["displayName"] as? String, "Test")
    }
}

@MainActor
final class AccountManagementTests: XCTestCase {
    private var service: MockFirebaseService!
    private var container: ModelContainer!
    private var sut: AuthViewModel!

    override func setUp() async throws {
        try await super.setUp()
        service = MockFirebaseService()
        container = try ModelContainer(
            for: LocalUserProfile.self, Workout.self, WorkoutEntry.self, Exercise.self,
            MealEntry.self, CustomFood.self, FavoriteFood.self, WaterEntry.self,
            SleepEntry.self, WeightEntry.self, MeasurementEntry.self, WasteEntry.self,
            WorkoutTemplate.self, TrainingProgram.self, ManualStepEntry.self,
            ChatMessageRecord.self, ChatPendingOperation.self, StickerRecord.self, ChatPlacementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        sut = AuthViewModel(service: service, modelContext: container.mainContext)

        var user = AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test")
        user.hasCompletedOnboarding = true
        service.storedUser = user
        sut.email = "a@b.com"
        sut.password = "Sifre1234!"
        await sut.signIn()
        XCTAssertEqual(sut.authState, .authenticated)
    }

    /// Arka plan görevleri bitmeden bellek içi veritabanı bırakılmaz (sonraki testlerde çökmeyi önler).
    override func tearDown() async throws {
        await settleTasks()
        try await super.tearDown()
    }

    func testDeleteAccountRequiresPassword() async {
        let ok = await sut.deleteAccount(password: "")
        XCTAssertFalse(ok)
        XCTAssertTrue(service.deletedAccounts.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
    }

    func testDeleteAccountPurgesLocalDataOfThatUserOnly() async throws {
        let context = container.mainContext
        context.insert(WaterEntry(ownerID: "uid-1", amountMl: 200))
        context.insert(WaterEntry(ownerID: "someone-else", amountMl: 300))
        context.insert(WasteEntry(ownerID: "uid-1"))
        context.insert(WeightEntry(ownerID: "uid-1", date: .now, weightKg: 70))
        let chatMessage = ChatMessageDTO(id: "m1", senderID: "uid-1", text: "selam", createdAt: .now)
        context.insert(ChatMessageRecord(dto: chatMessage, ownerID: "uid-1", chatID: "c", sendState: .sent))
        context.insert(ChatMessageRecord(dto: chatMessage, ownerID: "someone-else", chatID: "c", sendState: .sent))
        context.insert(ChatPendingOperation(ownerID: "uid-1", chatID: "c", messageID: "m1", kind: .markRead, createdAt: .now))
        try context.save()
        UserDefaults.standard.set(["x"], forKey: "pendingWaterDeletes.uid-1")
        ChatRoomCache(defaults: .standard).save(ChatRoomDTO(id: "c", members: ["a", "uid-1"], createdAt: .now), userID: "uid-1")

        let ok = await sut.deleteAccount(password: "Sifre1234!")
        XCTAssertTrue(ok)
        XCTAssertTrue(service.reauthenticated)
        XCTAssertEqual(service.deletedAccounts, ["uid-1"])
        XCTAssertEqual(sut.authState, .unauthenticated)
        XCTAssertNil(sut.currentUser)

        XCTAssertEqual(try context.fetch(FetchDescriptor<WaterEntry>()).map(\.ownerID), ["someone-else"])
        XCTAssertTrue(try context.fetch(FetchDescriptor<WasteEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WeightEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LocalUserProfile>()).isEmpty)
        XCTAssertNil(UserDefaults.standard.array(forKey: "pendingWaterDeletes.uid-1"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessageRecord>()).map(\.ownerID), ["someone-else"])
        XCTAssertTrue(try context.fetch(FetchDescriptor<ChatPendingOperation>()).isEmpty)
        XCTAssertNil(ChatRoomCache(defaults: .standard).load(userID: "uid-1"))
    }

    func testDeleteAccountRecentLoginMessage() async {
        service.deleteError = AppError.requiresRecentLogin
        let ok = await sut.deleteAccount(password: "Sifre1234!")
        XCTAssertFalse(ok)
        XCTAssertEqual(sut.authState, .authenticated)
        XCTAssertTrue(sut.errorMessage?.contains("tekrar giriş") ?? false)
    }

    func testPhotoUploadSetsURLAndFailureShowsError() async {
        let ok = await sut.updateProfilePhoto(Data([1, 2, 3]))
        XCTAssertTrue(ok)
        XCTAssertEqual(sut.currentUser?.photoURL, "https://example.com/uid-1.jpg")

        await sut.removeProfilePhoto()
        XCTAssertNil(sut.currentUser?.photoURL)

        service.uploadError = AppError.storage("yok")
        let failed = await sut.updateProfilePhoto(Data([1]))
        XCTAssertFalse(failed)
        XCTAssertNotNil(sut.errorMessage)
    }

    func testDataExportContainsOnlyOwnRecords() throws {
        let context = container.mainContext
        context.insert(WaterEntry(ownerID: "uid-1", amountMl: 250))
        context.insert(WaterEntry(ownerID: "other", amountMl: 300))
        context.insert(SleepEntry(ownerID: "uid-1", bedtime: .now.addingTimeInterval(-8 * 3_600), wakeTime: .now, quality: 4))
        let visible = ChatMessageRecord(dto: ChatMessageDTO(id: "m1", senderID: "uid-1", text: "merhaba", createdAt: .now), ownerID: "uid-1", chatID: "c", sendState: .sent)
        let hidden = ChatMessageRecord(dto: ChatMessageDTO(id: "m2", senderID: "x", text: "gizli", createdAt: .now), ownerID: "uid-1", chatID: "c", sendState: .sent)
        hidden.hiddenForMe = true
        context.insert(visible)
        context.insert(hidden)
        context.insert(ChatMessageRecord(dto: ChatMessageDTO(id: "m3", senderID: "x", text: "başkası", createdAt: .now), ownerID: "other", chatID: "c", sendState: .sent))
        try context.save()

        let export = try DataExporter.makeExport(user: sut.currentUser!, context: context)
        XCTAssertEqual(export.water.map(\.amountMl), [250])
        XCTAssertEqual(export.sleep.count, 1)
        XCTAssertEqual(export.profile.email, "a@b.com")
        XCTAssertEqual(export.chatMessages.map(\.text), ["merhaba"], "yalnızca kendi önbelleği, 'benden sil' ile gizlenenler hariç")

        let url = try DataExporter.writeFile(user: sut.currentUser!, context: context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.pathExtension, "json")
    }
}

// MARK: - Kütüphane eşitleme
final class MockLibrarySync: LibrarySyncing {
    var remote: [LibraryItemDTO] = []
    private(set) var uploaded: [LibraryItemDTO] = []
    private(set) var deleted: [String] = []

    func upload(_ item: LibraryItemDTO, userID: String) async throws { uploaded.append(item) }
    func delete(id: String, userID: String) async throws {
        deleted.append(id)
        remote.removeAll { $0.id == id }
    }
    func fetchAll(userID: String) async throws -> [LibraryItemDTO] { remote }
}

@MainActor
final class LibrarySyncTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var sync: MockLibrarySync!
    private var defaults: UserDefaults!
    private var sut: LibrarySynchronizer!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: CustomFood.self, FavoriteFood.self, Exercise.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        sync = MockLibrarySync()
        defaults = makeTestDefaults("library")
        sut = LibrarySynchronizer(sync: sync, defaults: defaults)
    }

    /// Arka plan görevleri bitmeden bellek içi veritabanı bırakılmaz (sonraki testlerde çökmeyi önler).
    override func tearDown() async throws {
        await settleTasks()
        try await super.tearDown()
    }

    func testUploadsLocalAndDownloadsRemote() async throws {
        let food = CustomFood(ownerID: "u1", name: "Kek", servingLabel: "1 dilim", calories: 300, protein: 4, carbs: 40, fat: 12)
        context.insert(food)
        let rowing = Exercise(ownerID: "u1", name: "Kürek", category: .cardio, mode: .duration, met: 7)
        context.insert(rowing)
        try context.save()

        let remoteExerciseID = UUID()
        sync.remote = [
            LibraryItemDTO(id: LibraryID.customExercise(remoteExerciseID), kind: .customExercise, name: "Tırmanış",
                           updatedAt: .now, category: "sports", mode: "duration", met: 8),
            LibraryItemDTO(id: LibraryID.favorite("preset.menemen"), kind: .favorite, name: "Menemen", updatedAt: .now,
                           foodKey: "preset.menemen", servingLabel: "1 porsiyon", calories: 240, protein: 11, carbs: 9, fat: 18),
            LibraryItemDTO(id: "food-bozuk", kind: .customFood, name: "Bozuk", updatedAt: .now)
        ]

        await sut.syncAll(context: context, userID: "u1")

        XCTAssertEqual(Set(sync.uploaded.map(\.id)), [LibraryID.customFood(food.id), LibraryID.customExercise(rowing.id)])
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.count, 2)
        XCTAssertTrue(exercises.contains { $0.id == remoteExerciseID && $0.categoryRaw == "sports" })
        XCTAssertEqual(try context.fetch(FetchDescriptor<FavoriteFood>()).first?.foodKey, "preset.menemen")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CustomFood>()).count, 1, "eksik alanlı uzak öğe atlanır")
    }

    func testPendingDeletionIsSentAndNotRestored() async throws {
        let id = LibraryID.favorite("preset.menemen")
        sync.remote = [LibraryItemDTO(id: id, kind: .favorite, name: "Menemen", updatedAt: .now,
                                      foodKey: "preset.menemen", calories: 240)]
        LibrarySynchronizer.recordDeletion(id, userID: "u1", defaults: defaults)

        await sut.syncAll(context: context, userID: "u1")
        XCTAssertEqual(sync.deleted, [id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<FavoriteFood>()).isEmpty)
    }

    func testReAddedItemCancelsPendingDeletion() async throws {
        let template = FoodLibrary.template(forKey: "preset.menemen")!
        context.insert(FavoriteFood(ownerID: "u1", template: template))
        try context.save()
        LibrarySynchronizer.recordDeletion(LibraryID.favorite(template.key), userID: "u1", defaults: defaults)

        await sut.syncAll(context: context, userID: "u1")
        XCTAssertTrue(sync.deleted.isEmpty)
        XCTAssertEqual(sync.uploaded.map(\.id), [LibraryID.favorite(template.key)])
    }
}
