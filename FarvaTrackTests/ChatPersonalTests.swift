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
    private var partner: ChatViewModel!
    private var personal: ChatViewModel!
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
        partner = makeViewModel(.partner)
        personal = makeViewModel(.personal)
        hub = ChatHub(partner: partner, personal: personal)
        hub.configure(context: container.mainContext, user: me)
    }

    override func tearDown() async throws {
        await settleTasks()
        hub.reset()
        await settleTasks()
        hub = nil
        partner = nil
        personal = nil
        container = nil
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func makeViewModel(_ kind: ChatRoomKind) -> ChatViewModel {
        ChatViewModel(kind: kind, sync: sync, mediaStore: store, processor: MockMediaProcessor(),
                      files: ChatMediaFiles(persistentRoot: root.appendingPathComponent("s"), cacheRoot: root.appendingPathComponent("c")),
                      defaults: defaults, clock: { [unowned self] in self.now },
                      makeID: { [unowned self] in
                          self.counter += 1
                          return "\(kind.rawValue)-\(self.counter)"
                      })
    }

    private func settle() async {
        for _ in 0..<3 {
            await settleTasks()
            await partner.flushOutbox()
            await personal.flushOutbox()
        }
    }

    private func openBothRooms() async {
        sync.roomHandlers[.partner]?(partnerRoom, false)
        sync.roomHandlers[.personal]?(personalRoom, false)
        await settle()
    }

    func testEachModelObservesItsOwnKind() {
        XCTAssertEqual(Set(sync.observedKinds), [.partner, .personal])
        // Sunucu dinleyicisi yanlış türü getirse bile model almaz.
        sync.roomHandlers[.partner]?(personalRoom, false)
        XCTAssertNotEqual(partner.phase, .ready)
        sync.roomHandlers[.personal]?(personalRoom, false)
        XCTAssertEqual(personal.phase, .ready)
        XCTAssertEqual(personal.partnerName, "Ben (Sen)")
        XCTAssertTrue(hub.showsRoomList, "not sohbeti varsa liste gösterilir")
    }

    func testPastingOwnCodeOpensPersonalChatWithoutTouchingPartner() async {
        sync.roomHandlers[.partner]?(nil, false)
        sync.roomHandlers[.personal]?(nil, false)
        XCTAssertEqual(partner.phase, .unpaired)
        XCTAssertFalse(hub.showsRoomList, "not sohbeti yokken eski akış")

        let invite = ChatInvite(code: "K7P2QX", ownerID: "me", ownerName: "Ben", createdAt: now, expiresAt: now.addingTimeInterval(ChatLimits.inviteLifetime))
        sync.inviteResult = .success(invite)
        await partner.createInvite()
        sync.redeemResult = .success(personalRoom)
        partner.inviteCodeInput = "K7P2QX"
        let ok = await partner.redeemInvite()
        XCTAssertTrue(ok)
        XCTAssertEqual(partner.phase, .unpaired, "karşılıklı sohbet bekler")
        XCTAssertNil(partner.invite, "kullanılan kod gösterilmez")

        // Not modelinin dinleyicisi odayı getirir.
        sync.roomHandlers[.personal]?(personalRoom, false)
        XCTAssertEqual(personal.phase, .ready)
        XCTAssertTrue(hub.showsRoomList)
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

        hub.openConversation = .partner
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
