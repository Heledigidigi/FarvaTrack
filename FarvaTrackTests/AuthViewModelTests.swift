import XCTest
@testable import FarvaTrack

// MARK: - Sahte servis
final class MockFirebaseService: FirebaseServicing {
    var currentUserID: String?
    var signInResult: Result<String, Error> = .success("uid-1")
    var registerResult: Result<String, Error> = .success("uid-1")
    var storedUser: AppUser?
    private(set) var savedUsers: [AppUser] = []
    private(set) var signOutCalled = false

    func observeAuthState(_ handler: @escaping (String?) -> Void) -> Any { NSObject() }
    func stopObserving(_ token: Any) {}

    func signIn(email: String, password: String) async throws -> String {
        try signInResult.get()
    }

    func register(email: String, password: String) async throws -> String {
        try registerResult.get()
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AppleSignInResult {
        AppleSignInResult(uid: "apple-uid", email: nil, isNewUser: true)
    }

    func signOut() throws { signOutCalled = true }
    func sendPasswordReset(email: String) async throws {}

    func fetchUser(uid: String) async throws -> AppUser? { storedUser }

    func saveUser(_ user: AppUser) async throws {
        savedUsers.append(user)
        storedUser = user
    }

    func uploadProfileImage(_ data: Data, uid: String) async throws -> URL {
        URL(string: "https://example.com/\(uid).jpg")!
    }
}

// MARK: - Testler
@MainActor
final class AuthViewModelTests: XCTestCase {

    private var service: MockFirebaseService!
    private var sut: AuthViewModel!

    override func setUp() async throws {
        try await super.setUp()
        service = MockFirebaseService()
        sut = AuthViewModel(service: service)
    }

    func testSignInWithInvalidEmailShowsError() async {
        sut.email = "gecersiz"
        sut.password = "123456789"
        await sut.signIn()
        XCTAssertEqual(sut.errorMessage, AppError.invalidEmail.errorDescription)
    }

    func testSignInExistingUserWithCompletedOnboardingIsAuthenticated() async {
        var user = AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test")
        user.hasCompletedOnboarding = true
        service.storedUser = user

        sut.email = "a@b.com"
        sut.password = "Sifre1234!"
        await sut.signIn()

        XCTAssertEqual(sut.authState, .authenticated)
        XCTAssertEqual(sut.currentUser?.id, "uid-1")
    }

    func testRegisterWithValidInputGoesToOnboarding() async {
        sut.displayName = "Test Kullanıcı"
        sut.email = "test@example.com"
        sut.password = "Sifre1234!"
        sut.confirmPassword = "Sifre1234!"

        await sut.register()

        XCTAssertEqual(sut.authState, .onboarding)
        XCTAssertEqual(service.savedUsers.first?.displayName, "Test Kullanıcı")
    }

    func testRegisterWithMismatchedPasswordsShowsError() async {
        sut.displayName = "Test"
        sut.email = "test@example.com"
        sut.password = "Sifre1234!"
        sut.confirmPassword = "Baska1234!"

        await sut.register()

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(service.savedUsers.isEmpty)
    }

    func testSignInFailureMapsToErrorMessage() async {
        service.signInResult = .failure(AppError.wrongCredentials)
        sut.email = "a@b.com"
        sut.password = "yanlis"
        await sut.signIn()
        XCTAssertEqual(sut.errorMessage, AppError.wrongCredentials.errorDescription)
    }

    func testCompleteOnboardingMarksUserAuthenticated() async {
        let user = AppUser.makeNew(id: "uid-1", email: "a@b.com", displayName: "Test")
        await sut.completeOnboarding(user)
        XCTAssertEqual(sut.authState, .authenticated)
        XCTAssertEqual(service.savedUsers.last?.hasCompletedOnboarding, true)
    }

    func testSignOutResetsState() {
        sut.email = "a@b.com"
        sut.signOut()
        XCTAssertTrue(service.signOutCalled)
        XCTAssertEqual(sut.authState, .unauthenticated)
        XCTAssertTrue(sut.email.isEmpty)
    }

    func testAdminRoleIsRecognized() {
        var user = AppUser.makeNew(id: "u", email: "a@b.com", displayName: "T")
        XCTAssertFalse(user.isAdmin)
        user.role = "admin"
        XCTAssertTrue(user.isAdmin)
    }
}
