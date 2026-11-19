import XCTest
import SwiftData
@testable import FarvaTrack

final class MockLibraryRemote: LibraryRemoting {
    var stored: LibraryDTO?
    private(set) var uploads: [LibraryDTO] = []

    func fetch(userID: String) async throws -> LibraryDTO? { stored }

    func upload(_ library: LibraryDTO, userID: String) async throws {
        uploads.append(library)
        stored = library
    }
}

@MainActor
final class LibrarySyncTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var remote: MockLibraryRemote!
    private var sut: LibrarySyncService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: Exercise.self, CustomFood.self, FavoriteFood.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        defaults = UserDefaults(suiteName: "library-tests")
        defaults.removePersistentDomain(forName: "library-tests")
        remote = MockLibraryRemote()
        sut = LibrarySyncService(remote: remote, defaults: defaults)
    }

    private func addExercise(_ name: String) {
        context.insert(Exercise(ownerID: "uid-1", name: name, category: .strength, mode: .sets, met: 5))
        try? context.save()
    }

    private func localExerciseNames() throws -> [String] {
        try context.fetch(FetchDescriptor<Exercise>()).map(\.name).sorted()
    }

    func testFirstSyncUploadsExistingLocalItems() async {
        addExercise("Kettlebell Swing")
        await sut.sync(context: context, userID: "uid-1")
        XCTAssertEqual(remote.uploads.count, 1)
        XCTAssertEqual(remote.stored?.exercises.first?.name, "Kettlebell Swing")
    }

    func testLocalChangeIsUploadedAndClearsDirtyFlag() async throws {
        addExercise("Bir")
        await sut.sync(context: context, userID: "uid-1")          // ilk yükleme

        addExercise("İki")
        defaults.set(true, forKey: "librarySync.dirty.uid-1")
        defaults.set(Date.now.addingTimeInterval(10), forKey: "librarySync.localStamp.uid-1")
        await sut.sync(context: context, userID: "uid-1")

        XCTAssertEqual(remote.stored?.exercises.count, 2)
        XCTAssertFalse(defaults.bool(forKey: "librarySync.dirty.uid-1"))
    }

    func testNewDeviceAdoptsRemoteLibrary() async throws {
        remote.stored = LibraryDTO(
            exercises: [.init(id: UUID().uuidString, name: "Uzak Egzersiz", category: "cardio", mode: "duration", met: 7, createdAt: .now)],
            foods: [.init(id: UUID().uuidString, name: "Granola", servingLabel: "1 kase", calories: 210, protein: 6, carbs: 28, fat: 8, createdAt: .now)],
            favorites: [.init(foodKey: "preset.menemen", name: "Menemen", servingLabel: "1 porsiyon", calories: 240, protein: 11, carbs: 9, fat: 18, addedAt: .now)],
            updatedAt: Date.now
        )

        await sut.sync(context: context, userID: "uid-1")

        XCTAssertEqual(try localExerciseNames(), ["Uzak Egzersiz"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CustomFood>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FavoriteFood>()), 1)
        XCTAssertTrue(remote.uploads.isEmpty)                       // yerelde değişiklik yoktu
    }

    func testRemoteDeletionPropagatesWhenLocalIsNotDirty() async throws {
        addExercise("Silinecek")
        await sut.sync(context: context, userID: "uid-1")          // yüklendi, kirli değil

        // Başka cihaz her şeyi silip daha yeni bir sürüm yükledi.
        remote.stored = LibraryDTO(exercises: [], foods: [], favorites: [], updatedAt: Date.now.addingTimeInterval(60))
        await sut.sync(context: context, userID: "uid-1")

        XCTAssertEqual(try localExerciseNames(), [])
    }

    func testLocalChangesWinOverNewerRemoteWhenDirty() async throws {
        addExercise("Yerel")
        await sut.sync(context: context, userID: "uid-1")

        remote.stored = LibraryDTO(exercises: [], foods: [], favorites: [], updatedAt: Date.now.addingTimeInterval(60))
        defaults.set(true, forKey: "librarySync.dirty.uid-1")
        defaults.set(Date.now, forKey: "librarySync.localStamp.uid-1")

        await sut.sync(context: context, userID: "uid-1")

        XCTAssertEqual(try localExerciseNames(), ["Yerel"])
        XCTAssertEqual(remote.stored?.exercises.count, 1)
    }

    func testEmptyLocalAndEmptyRemoteDoesNothing() async {
        await sut.sync(context: context, userID: "uid-1")
        XCTAssertTrue(remote.uploads.isEmpty)
    }
}