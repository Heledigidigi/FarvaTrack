import XCTest
import SwiftData
@testable import FarvaTrack

// MARK: - Model

final class ChatRoomKindTests: XCTestCase {
    func testPersonalRoomIdentity() {
        XCTAssertEqual(ChatID.make("me", "me"), "me_me")
        XCTAssertEqual(ChatID.sortedMembers("me", "me"), ["me", "me"])
        let personal = ChatRoomDTO(id: "me_me", members: ["me", "me"], createdAt: .now)
        let partner = ChatRoomDTO(id: "friend_me", members: ["friend", "me"], createdAt: .now)
        XCTAssertEqual(ChatRoomKind.of(personal, userID: "me"), .personal)
        XCTAssertEqual(ChatRoomKind.of(partner, userID: "me"), .partner)
        XCTAssertNil(personal.otherMember(of: "me"))
        XCTAssertEqual(ChatRoomKind.of(ChatRoomDTO(id: "x", members: [], createdAt: .now), userID: "me"), .partner)
    }

    func testRoomCachesAreSeparate() {
        let defaults = makeTestDefaults("roomcache.\(UUID().uuidString)")
        let partner = ChatRoomDTO(id: "friend_me", members: ["friend", "me"], createdAt: .now)
        let personal = ChatRoomDTO(id: "me_me", members: ["me", "me"], createdAt: .now)
        ChatRoomCache(defaults: defaults).save(partner, userID: "me")
        ChatRoomCache(defaults: defaults, kind: .personal).save(personal, userID: "me")
        XCTAssertEqual(ChatRoomCache(defaults: defaults).load(userID: "me")?.id, "friend_me", "eski anahtar korunur")
        XCTAssertEqual(ChatRoomCache(defaults: defaults, kind: .personal).load(userID: "me")?.id, "me_me")
    }
}

// MARK: - İki oda birlikte

@MainActor
final class ChatPersonalRoomTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockChatSync!
    private var store: MockMediaStore!
    private var root: URL!
    private var defaults: UserDefaults!
    private var personal: ChatViewModel!
    private var friendService: MockFriendSync!
    /// Arkadaş odası `ChatHub` tarafından açılır.
    private var partner: ChatViewModel! { hub.rooms["friend_me"] }
    private var hub: ChatHub!
    private var counter = 0
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let me = AppUser.makeNew(id: "me", email: "ben@ornek.com", displayName: "Ben")
    private let partnerRoom = ChatRoomDTO(id: "friend_me", members: ["friend", "me"], names: ["friend": "Elif", "me": "Ben"],
                                          createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    private let personalRoom = ChatRoomDTO(id: "me_me", members: ["me", "me"], names: ["me": "Ben"],
                                           createdAt: Date(timeIntervalSince1970: 1_800_000_000))

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: ChatMessageRecord.self, ChatPendingOperation.self, ChatPlacementRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sync = MockChatSync()
        store = MockMediaStore()
        root = makeTemporaryDirectory()
        defaults = makeTestDefaults("personal.\(name)")
        counter = 0
        personal = makeViewModel(.personal)
        friendService = MockFriendSync()
        hub = ChatHub(sync: sync, personal: personal, friends: FriendsViewModel(service: friendService),
                      friendService: friendService, defaults: defaults) { [unowned self] in self.makeViewModel(.partner, chatID: $0) }
        hub.configure(context: container.mainContext, user: me)
    }

    override func tearDown() async throws {
        await settleTasks()
        hub.reset()
        await settleTasks()
        hub = nil
        personal = nil
        container = nil
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func makeViewModel(_ kind: ChatRoomKind, chatID: String? = nil) -> ChatViewModel {
        ChatViewModel(kind: kind, sync: sync, mediaStore: store, processor: MockMediaProcessor(),
                      files: ChatMediaFiles(persistentRoot: root.appendingPathComponent("s"), cacheRoot: root.appendingPathComponent("c")),
                      defaults: defaults, clock: { [unowned self] in self.now },
                      makeID: { [unowned self] in
                          self.counter += 1
                          return "\(kind.rawValue)-\(self.counter)"
                      }, chatID: chatID)
    }

    private func settle() async {
        for _ in 0..<3 {
            await settleTasks()
            await partner?.flushOutbox()
            await personal.flushOutbox()
        }
    }

    private func openBothRooms() async {
        sync.roomsHandler?([partnerRoom, personalRoom], false)
        sync.roomHandlers[.personal]?(personalRoom, false)
        await settle()
    }

    func testHubOpensOneModelPerFriendRoomAndNoteSeparately() async {
        XCTAssertEqual(sync.observedKinds, [.personal], "arkadaş odaları tek listeden gelir")
        let second = ChatRoomDTO(id: "me_zeynep", members: ["me", "zeynep"], names: ["zeynep": "Zeynep", "me": "Ben"], createdAt: now)
        sync.roomsHandler?([partnerRoom, personalRoom, second], false)
        await settle()
        XCTAssertEqual(Set(hub.rooms.keys), ["friend_me", "me_zeynep"], "not sohbeti arkadaş sayılmaz")
        XCTAssertEqual(hub.friendIDs, ["friend", "zeynep"])
        XCTAssertEqual(hub.rooms["me_zeynep"]?.partnerName, "Zeynep")
        XCTAssertEqual(hub.callRooms, ["friend_me": "Elif", "me_zeynep": "Zeynep"])

        // Sunucudan kalkan oda (hesap silindi) kapanır; önbellekten gelen eksik liste kapatmaz.
        sync.roomsHandler?([partnerRoom], true)
        XCTAssertEqual(hub.rooms.count, 2)
        sync.roomsHandler?([partnerRoom], false)
        XCTAssertEqual(Set(hub.rooms.keys), ["friend_me"])
    }

    func testRoomListIsRestoredFromCacheOffline() async {
        await openBothRooms()
        hub.reset()
        let friendService = MockFriendSync()
        hub = ChatHub(sync: sync, personal: makeViewModel(.personal), friends: FriendsViewModel(service: friendService),
                      friendService: friendService, defaults: defaults) { [unowned self] in self.makeViewModel(.partner, chatID: $0) }
        hub.configure(context: container.mainContext, user: me)
        XCTAssertEqual(hub.rooms["friend_me"]?.phase, .ready, "çevrimdışı açılışta liste önbellekten")
        XCTAssertFalse(hub.hasLoadedRooms)
    }

    func testPersonalRoomIsCreatedWithOneTap() async {
        sync.roomHandlers[.personal]?(nil, false)
        XCTAssertEqual(personal.phase, .unpaired)
        let ok = await hub.createPersonalRoom()
        XCTAssertTrue(ok)
        XCTAssertEqual(friendService.personalRooms, ["me"])
        XCTAssertEqual(personal.phase, .ready)
        XCTAssertEqual(personal.room?.id, "me_me")
    }

    func testPersonalChatWorksLikeAnyChatButWithoutTypingOrUnread() async {
        await openBothRooms()
        personal.draft = "Spor salonu: 3x10 squat"
        personal.draftChanged()
        personal.send()
        await settle()
        XCTAssertEqual(sync.sent.map(\.text), ["Spor salonu: 3x10 squat"])
        XCTAssertTrue(sync.typing.isEmpty, "not sohbetinde yazıyor sinyali gitmez")

        // Sunucudan dönen kendi mesajım: okunmamış sayılmaz.
        var echoed = sync.sent[0]
        echoed.hasPendingWrites = false
        sync.messageHandlers["me_me"]?([echoed])
        XCTAssertEqual(personal.unreadCount, 0)
        XCTAssertEqual(personal.messages.first?.isMine, true)
        XCTAssertTrue(partner.messages.isEmpty, "odalar karışmaz")
    }

    func testOutboxesAreSeparatePerRoom() async {
        await openBothRooms()
        sync.isOffline = true
        partner.draft = "Elif'e"
        partner.send()
        personal.draft = "Kendime"
        personal.send()
        await settle()
        XCTAssertEqual(partner.pendingOperations().map(\.chatID), ["friend_me"])
        XCTAssertEqual(personal.pendingOperations().map(\.chatID), ["me_me"])

        sync.isOffline = false
        await settle()
        XCTAssertEqual(Set(sync.sent.map(\.text)), ["Elif'e", "Kendime"])
        XCTAssertEqual(sync.sent.count, 2, "her mesaj bir kez gönderilir")
    }

    func testOnlyOpenConversationMarksMessagesRead() async {
        await openBothRooms()
        sync.messageHandlers["friend_me"]?([ChatMessageDTO(id: "r1", senderID: "friend", text: "selam", createdAt: now)])
        hub.isTabVisible = true
        hub.openConversation = .personal
        await settle()
        XCTAssertTrue(sync.reads.isEmpty, "liste ya da not açıkken karşılıklı mesaj okunmaz")
        XCTAssertEqual(hub.unreadCount, 1)

        hub.openConversation = .room("friend_me")
        await settle()
        XCTAssertEqual(sync.reads.first, ["r1"])
        XCTAssertEqual(hub.unreadCount, 0)
    }

    func testPersonalOriginalIsAcknowledgedAfterUpload() async throws {
        await openBothRooms()
        let source = root.appendingPathComponent("\(UUID().uuidString).heic")
        try Data("not".utf8).write(to: source)
        await personal.sendMedia([PickedMedia(fileURL: source, kind: .image)], quality: .original)
        await settle()
        let original = ChatMediaPath.original(chatID: "me_me", messageID: "personal-1", fileExtension: "heic")
        XCTAssertTrue(store.uploads.map(\.path).contains(original))
        for _ in 0..<3 { await settleTasks() }
        XCTAssertEqual(store.acknowledged, [original], "not sohbetinde orijal bu cihazda: bulut temizlenebilir")
    }
}
