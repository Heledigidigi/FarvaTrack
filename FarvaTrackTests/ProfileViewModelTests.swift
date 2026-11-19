import XCTest
import UIKit
@testable import FarvaTrack

final class MockPhotoStore: ProfilePhotoStoring {
    private(set) var uploadedSizes: [Int] = []
    private(set) var deletedUIDs: [String] = []
    var shouldFail = false

    func uploadPhoto(_ data: Data, uid: String) async throws -> URL {
        if shouldFail { throw AppError.storage("hata") }
        uploadedSizes.append(data.count)
        return URL(string: "https://example.com/\(uid).jpg")!
    }

    func deletePhoto(uid: String) async { deletedUIDs.append(uid) }
}

@MainActor
final class ProfileViewModelTests: XCTestCase {

    private var calendar: Calendar!
    private var now: Date!
    private var photos: MockPhotoStore!
    private var sut: ProfileViewModel!
    private var user: AppUser!
    private var updates: [AppUser] = []

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar = cal
        now = cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))
        photos = MockPhotoStore()
        updates = []

        var u = AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test Kullanıcı")
        u.birthDate = cal.date(byAdding: .year, value: -30, to: now)
        u.heightCm = 175
        u.weightKg = 70
        u.gender = .male
        u.activityLevel = .moderate
        u.goal = .maintain
        user = u

        let fixedNow = now!
        sut = ProfileViewModel(photos: photos, calendar: cal, now: { fixedNow })
        sut.configure(user: u) { [unowned self] updated in self.updates.append(updated) }
    }

    private func draft() -> ProfileDraft { ProfileDraft(user: user, now: now) }

    // MARK: - Doğrulama
    func testValidDraftPasses() {
        XCTAssertNoThrow(try sut.validate(draft()))
    }

    func testRejectsInvalidFields() {
        var d = draft(); d.displayName = "   "
        XCTAssertThrowsError(try sut.validate(d))

        d = draft(); d.heightCm = 90
        XCTAssertThrowsError(try sut.validate(d))

        d = draft(); d.heightCm = 260
        XCTAssertThrowsError(try sut.validate(d))

        d = draft(); d.birthDate = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertThrowsError(try sut.validate(d))

        d = draft(); d.birthDate = calendar.date(byAdding: .year, value: -10, to: now)!     // 13 yaş altı
        XCTAssertThrowsError(try sut.validate(d))
    }

    func testMinorCannotChooseWeightLossGoal() {
        var d = draft()
        d.birthDate = calendar.date(byAdding: .year, value: -15, to: now)!
        d.goal = .loseWeight
        XCTAssertThrowsError(try sut.validate(d))

        d.goal = .improveFitness
        XCTAssertNoThrow(try sut.validate(d))
    }

    // MARK: - Kaydetme
    func testSavingOnlyNameDoesNotOfferRecalculation() async throws {
        var d = draft()
        d.displayName = "  Yeni Ad  "
        let saved = try await sut.save(d)

        XCTAssertEqual(saved.displayName, "Yeni Ad")
        XCTAssertNil(sut.recalcOffer)
        XCTAssertEqual(updates.last?.displayName, "Yeni Ad")
    }

    func testChangingHeightOffersRecalculationWithoutSteps() async throws {
        var d = draft()
        d.heightCm = 182
        try await sut.save(d)
        XCTAssertEqual(sut.recalcOffer, RecalcOffer(includesSteps: false))
    }

    func testChangingGoalOrActivityOffersRecalculationWithSteps() async throws {
        var d = draft()
        d.activityLevel = .active
        try await sut.save(d)
        XCTAssertEqual(sut.recalcOffer, RecalcOffer(includesSteps: true))
    }

    func testAcceptRecalculationUpdatesGoalsAndKeepsCustomStepGoal() async throws {
        user.dailyStepGoal = 12_345                       // kullanıcının kendi hedefi
        sut.configure(user: user) { [unowned self] in self.updates.append($0) }

        var d = draft()
        d.heightCm = 185
        try await sut.save(d)
        await sut.acceptRecalculation()

        let updated = updates.last
        XCTAssertEqual(updated?.dailyStepGoal, 12_345)    // adım hedefi korundu
        // BMR = 700 + 1156,25 − 150 + 5 = 1711,25 ; ×1,55 = 2652,4 → 2650
        XCTAssertEqual(updated?.dailyCalorieGoal, 2_650)
        XCTAssertNil(sut.recalcOffer)
    }

    func testRecalculatedGoalsIncludeStepsWhenRequested() {
        let updated = ProfileViewModel.recalculatedGoals(for: user, includeSteps: true, now: now, calendar: calendar)
        XCTAssertEqual(updated?.dailyStepGoal, 8_000)     // koruma + orta aktif
    }

    func testRecalculationIsSkippedWhenProfileIsIncomplete() {
        var incomplete = user!
        incomplete.gender = nil
        XCTAssertNil(ProfileViewModel.recalculatedGoals(for: incomplete, includeSteps: false, now: now, calendar: calendar))
    }

    // MARK: - Fotoğraf
    private func sampleImageData(size: CGSize) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.pngData()!
    }

    func testUploadPhotoProcessesImageAndSetsURL() async {
        await sut.uploadPhoto(sampleImageData(size: CGSize(width: 2_000, height: 1_000)))

        XCTAssertEqual(photos.uploadedSizes.count, 1)
        XCTAssertLessThan(photos.uploadedSizes[0], 200_000)
        XCTAssertEqual(updates.last?.photoURL, "https://example.com/uid-1.jpg")
    }

    func testUploadRejectsNonImageData() async {
        await sut.uploadPhoto(Data([0, 1, 2, 3]))
        XCTAssertTrue(photos.uploadedSizes.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
    }

    func testUploadFailureShowsError() async {
        photos.shouldFail = true
        await sut.uploadPhoto(sampleImageData(size: CGSize(width: 100, height: 100)))
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertNil(updates.last?.photoURL)
    }

    func testRemovePhotoClearsURLAndDeletesFile() async {
        user.photoURL = "https://example.com/uid-1.jpg"
        sut.configure(user: user) { [unowned self] in self.updates.append($0) }

        await sut.removePhoto()

        XCTAssertEqual(photos.deletedUIDs, ["uid-1"])
        XCTAssertNil(updates.last?.photoURL)
    }
}

final class ProfileImageProcessorTests: XCTestCase {

    private func imageData(width: CGFloat, height: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.pngData()!
    }

    func testLargeLandscapeImageBecomesSquareAtMaxSize() throws {
        let output = try XCTUnwrap(ProfileImageProcessor.process(imageData(width: 2_000, height: 1_000)))
        let image = try XCTUnwrap(UIImage(data: output))
        XCTAssertEqual(image.size.width, 512, accuracy: 1)
        XCTAssertEqual(image.size.height, 512, accuracy: 1)
    }

    func testSmallImageIsNotUpscaled() throws {
        let output = try XCTUnwrap(ProfileImageProcessor.process(imageData(width: 200, height: 300)))
        let image = try XCTUnwrap(UIImage(data: output))
        XCTAssertEqual(image.size.width, 200, accuracy: 1)
        XCTAssertEqual(image.size.height, 200, accuracy: 1)
    }

    func testInvalidDataReturnsNil() {
        XCTAssertNil(ProfileImageProcessor.process(Data([1, 2, 3])))
    }
}