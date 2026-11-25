import XCTest
@testable import FarvaTrack

/// Bellek içi arkadaş servisi.
final class MockFriendSync: FriendSyncing {
    var usernames: [String: FriendProfile] = [:]
    var sentRequests: [FriendRequest] = []
    var accepted: [(FriendRequest, Bool)] = []
    var removed: [String] = []
    var personalRooms: [String] = []
    var nextError: AppError?
    private(set) var requestsHandler: (@MainActor ([FriendRequest], [FriendRequest]) -> Void)?

    private func fail() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    func username(of userID: String) async throws -> String? {
        try fail()
        return mockLock.withLock { usernames.first { $0.value.userID == userID }?.key }
    }

    func claimUsername(_ name: String, userID: String, displayName: String, photoURL: String?, previous: String?) async throws {
        try fail()
        try mockLock.withLock {
            if let owner = usernames[name], owner.userID != userID { throw AppError.invalidInput("alınmış") }
            if let previous { usernames[previous] = nil }
            usernames[name] = FriendProfile(userID: userID, username: name, displayName: displayName, photoURL: photoURL)
        }
    }

    func search(prefix: String) async throws -> [FriendProfile] {
        try fail()
        return mockLock.withLock { usernames.filter { $0.key.hasPrefix(prefix) }.map(\.value).sorted { $0.username < $1.username } }
    }

    func sendRequest(from: FriendProfile, to: FriendProfile, now: Date) async throws {
        try fail()
        mockLock.withLock { sentRequests.append(FriendRequest(from: from, to: to, createdAt: now)) }
    }

    func observeRequests(userID: String, onChange: @escaping @MainActor ([FriendRequest], [FriendRequest]) -> Void,
                         onError: @escaping @MainActor (AppError) -> Void) -> ChatSubscription {
        requestsHandler = onChange
        return ChatSubscription { [weak self] in self?.requestsHandler = nil }
    }

    func accept(_ request: FriendRequest, roomExists: Bool, now: Date) async throws -> ChatRoomDTO {
        try fail()
        mockLock.withLock { accepted.append((request, roomExists)) }
        return ChatRoomDTO(id: ChatID.make(request.from.userID, request.to.userID),
                           members: ChatID.sortedMembers(request.from.userID, request.to.userID),
                           names: [request.from.userID: request.from.displayName, request.to.userID: request.to.displayName],
                           createdAt: now)
    }

    func remove(_ request: FriendRequest) async throws {
        try fail()
        mockLock.withLock { removed.append(request.id) }
    }

    func createPersonalRoom(userID: String, userName: String, now: Date) async throws -> ChatRoomDTO {
        try fail()
        mockLock.withLock { personalRooms.append(userID) }
        return ChatRoomDTO(id: ChatID.make(userID, userID), members: [userID, userID], names: [userID: userName], createdAt: now)
    }

    func purge(userID: String) async throws {}
}

final class ChatUsernameTests: XCTestCase {
    func testNormalizeFoldsTurkishAndStripsSymbols() {
        XCTAssertEqual(ChatUsername.normalize(" @Özgür.Bozkurt "), "ozgur.bozkurt")
        XCTAssertEqual(ChatUsername.normalize("Şule Çağ!"), "sule_cag")
        XCTAssertEqual(ChatUsername.suggestion(from: "Özgür Bozkurt"), "ozgur.bozkurt")
    }

    func testValidation() {
        XCTAssertTrue(ChatUsername.isValid("elif_92"))
        XCTAssertNotNil(ChatUsername.problem("ab"))
        XCTAssertNotNil(ChatUsername.problem(".elif"))
        XCTAssertNotNil(ChatUsername.problem("el..if"))
        XCTAssertNotNil(ChatUsername.problem(String(repeating: "a", count: 21)))
        XCTAssertNotNil(ChatUsername.problem("Elif"), "büyük harf normalize edilmeden geçmez")
    }

    func testRelation() {
        let me = FriendProfile(userID: "me", username: "ben", displayName: "Ben")
        let elif = FriendProfile(userID: "elif", username: "elif", displayName: "Elif")
        let zeynep = FriendProfile(userID: "zeynep", username: "zeynep", displayName: "Zeynep")
        let out = [FriendRequest(from: me, to: elif, createdAt: .now)]
        let inc = [FriendRequest(from: zeynep, to: me, createdAt: .now)]
        XCTAssertEqual(FriendRelation.of("me", me: "me", friends: [], incoming: inc, outgoing: out), .me)
        XCTAssertEqual(FriendRelation.of("elif", me: "me", friends: [], incoming: inc, outgoing: out), .requestSent)
        XCTAssertEqual(FriendRelation.of("zeynep", me: "me", friends: [], incoming: inc, outgoing: out), .requestReceived)
        XCTAssertEqual(FriendRelation.of("elif", me: "me", friends: ["elif"], incoming: inc, outgoing: out), .friend)
        XCTAssertEqual(FriendRelation.of("x", me: "me", friends: [], incoming: [], outgoing: []), .none)
        XCTAssertEqual(FriendRequest(from: me, to: elif, createdAt: .now).id, "me_elif")
    }
}

@MainActor
final class FriendsViewModelTests: XCTestCase {
    private var service: MockFriendSync!
    private var sut: FriendsViewModel!
    private let user = AppUser.makeNew(id: "me", email: "ben@ornek.com", displayName: "Özgür Bozkurt")

    override func setUp() async throws {
        try await super.setUp()
        service = MockFriendSync()
        sut = FriendsViewModel(service: service, clock: { Date(timeIntervalSince1970: 1_800_000_000) }, debounce: .zero)
    }

    private func configure() async {
        sut.configure(user: user)
        for _ in 0..<3 { await settleTasks() }
    }

    func testUsernameIsSuggestedThenClaimed() async {
        await configure()
        XCTAssertEqual(sut.myUsername, "")
        XCTAssertFalse(sut.hasUsername)
        XCTAssertEqual(sut.usernameInput, "ozgur.bozkurt")

        service.usernames["ozgur.bozkurt"] = FriendProfile(userID: "other", username: "ozgur.bozkurt", displayName: "Başkası")
        let taken = await sut.saveUsername()
        XCTAssertFalse(taken)
        XCTAssertNotNil(sut.errorMessage)

        sut.usernameInput = "@Ozgur_B"
        let saved = await sut.saveUsername()
        XCTAssertTrue(saved)
        XCTAssertEqual(sut.myUsername, "ozgur_b")
        XCTAssertEqual(sut.me?.username, "ozgur_b")
    }

    func testSearchAndSendRequest() async {
        service.usernames["ben"] = FriendProfile(userID: "me", username: "ben", displayName: "Özgür Bozkurt")
        service.usernames["elif"] = FriendProfile(userID: "elif", username: "elif", displayName: "Elif")
        await configure()
        sut.query = "@El"
        for _ in 0..<3 { await settleTasks() }
        await sut.search("el")
        XCTAssertEqual(sut.results.map(\.userID), ["elif"])
        XCTAssertEqual(sut.relation(to: "elif"), .none)

        await sut.add(sut.results[0])
        XCTAssertEqual(service.sentRequests.map(\.id), ["me_elif"])
        XCTAssertEqual(sut.relation(to: "elif"), .requestSent, "dinleyici gelmeden arayüz güncellenir")
    }

    func testAddingSomeoneWhoAlreadyAskedAcceptsInstead() async {
        service.usernames["ben"] = FriendProfile(userID: "me", username: "ben", displayName: "Özgür Bozkurt")
        await configure()
        var created: [String] = []
        sut.onRoomCreated = { created.append($0.id) }
        let zeynep = FriendProfile(userID: "zeynep", username: "zeynep", displayName: "Zeynep")
        let request = FriendRequest(from: zeynep, to: sut.me!, createdAt: .now)
        service.requestsHandler?([request], [])
        XCTAssertEqual(sut.incoming.count, 1)

        await sut.add(zeynep)
        XCTAssertTrue(service.sentRequests.isEmpty)
        XCTAssertEqual(service.accepted.map(\.0.id), ["zeynep_me"])
        XCTAssertEqual(created, ["me_zeynep"])
        XCTAssertTrue(sut.incoming.isEmpty)
    }

    func testAcceptKnowsWhenRoomExistsAndDeclineRemoves() async {
        service.usernames["ben"] = FriendProfile(userID: "me", username: "ben", displayName: "Özgür Bozkurt")
        await configure()
        sut.friendIDs = { ["elif"] }
        let elif = FriendProfile(userID: "elif", username: "elif", displayName: "Elif")
        let ali = FriendProfile(userID: "ali", username: "ali", displayName: "Ali")
        let fromElif = FriendRequest(from: elif, to: sut.me!, createdAt: .now)
        let fromAli = FriendRequest(from: ali, to: sut.me!, createdAt: .now)
        service.requestsHandler?([fromElif, fromAli], [])

        let ok = await sut.accept(fromElif)
        XCTAssertTrue(ok)
        XCTAssertEqual(service.accepted.first?.1, true, "eski davetle açılmış oda yeniden oluşturulmaz")

        await sut.remove(fromAli)
        XCTAssertEqual(service.removed, ["ali_me"])
        XCTAssertTrue(sut.incoming.isEmpty)

        service.nextError = .network
        let failed = await sut.accept(FriendRequest(from: ali, to: sut.me!, createdAt: .now))
        XCTAssertFalse(failed)
    }
}

final class MeasureTrendStateTests: XCTestCase {
    func testRoundTripAndSanitizing() {
        let state = MeasureTrendState(range: .year, mode: .percent, compared: [.weight, .measure(.arm)])
        let decoded = MeasureTrendState(encoded: state.encoded, primary: .waist)
        XCTAssertEqual(decoded, state)

        // Bozuk parçalar atlanır, ana ölçü ve tekrarlar karşılaştırmadan çıkar.
        let messy = MeasureTrendState(encoded: "x|percent|waist,weight,weight,bilinmeyen", primary: .waist)
        XCTAssertEqual(messy.range, .sixMonths)
        XCTAssertEqual(messy.mode, .percent)
        XCTAssertEqual(messy.compared, [.weight])
        XCTAssertEqual(MeasureTrendState(encoded: nil, primary: .arm), MeasureTrendState())
    }

    func testSavedPerMeasure() {
        let defaults = makeTestDefaults("trend.\(UUID().uuidString)")
        MeasureTrendState(range: .all, compared: [.weight]).save(.arm, defaults: defaults)
        XCTAssertEqual(MeasureTrendState.load(.arm, defaults: defaults).range, .all)
        XCTAssertEqual(MeasureTrendState.load(.waist, defaults: defaults), MeasureTrendState(), "diğer ölçü etkilenmez")
    }
}
