import XCTest
import SwiftData
@testable import FarvaTrack

// MARK: - Sahteler

final class MockPushSystem: PushSystem {
    var granted = true
    var token: String?
    private(set) var registrations = 0
    private(set) var deletedTokens = 0
    private(set) var badges: [Int] = []

    func requestAuthorization() async -> Bool { granted }
    func registerForRemoteNotifications() { registrations += 1 }
    func fcmToken() async -> String? { token }
    func deleteFCMToken() async { deletedTokens += 1 }
    func setBadge(_ count: Int) { mockLock.withLock { badges.append(count) } }
}

final class MockDeviceStore: PushDeviceStoring {
    private(set) var saved: [(device: PushDevice, userID: String)] = []
    private(set) var deleted: [(deviceID: String, userID: String)] = []

    func save(_ device: PushDevice, userID: String) async throws { mockLock.withLock { saved.append((device, userID)) } }
    func delete(deviceID: String, userID: String) async throws { mockLock.withLock { deleted.append((deviceID, userID)) } }
}

final class MockNotifier: ChatNotifying {
    private(set) var calls: [String] = []
    var error: Error?

    func notify(chatID: String, messageID: String) async throws {
        if let error { throw error }
        mockLock.withLock { calls.append("\(chatID)/\(messageID)") }
    }
}

// MARK: - Push kaydı

@MainActor
final class PushManagerTests: XCTestCase {
    private var system: MockPushSystem!
    private var store: MockDeviceStore!
    private var defaults: UserDefaults!
    private var sut: PushManager!

    override func setUp() async throws {
        try await super.setUp()
        system = MockPushSystem()
        store = MockDeviceStore()
        defaults = makeTestDefaults("push.\(name)")
        sut = PushManager(system: system, devices: store, defaults: defaults, appVersion: "1.2")
    }

    func testRegistersAndSavesTokenWithStableDeviceID() async {
        system.token = "fcm-1"
        await sut.start(userID: "me")
        XCTAssertEqual(system.registrations, 1)
        XCTAssertEqual(sut.availability, .enabled)
        let first = try? XCTUnwrap(store.saved.last)
        XCTAssertEqual(first?.userID, "me")
        XCTAssertEqual(first?.device.token, "fcm-1")
        XCTAssertEqual(first?.device.appVersion, "1.2")
        XCTAssertFalse(first?.device.muted ?? true)

        await sut.tokenReceived("fcm-2")
        XCTAssertEqual(store.saved.last?.device.token, "fcm-2", "yenilenen belirteç yazılır")
        XCTAssertEqual(store.saved.last?.device.id, first?.device.id, "cihaz kimliği aynı kalır")
        XCTAssertEqual(PushManager(system: system, devices: store, defaults: defaults).deviceID, first?.device.id)

        await sut.start(userID: "me")
        XCTAssertEqual(system.registrations, 1, "aynı kullanıcı için yeniden izin istenmez")
    }

    func testWithoutAPNsFallsBackGracefully() async {
        system.token = nil
        await sut.start(userID: "me")
        sut.apnsFailed()
        XCTAssertEqual(sut.availability, .unavailable)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertTrue(sut.statusText.contains("Uygulama açıkken"))
    }

    func testDeniedPermission() async {
        system.granted = false
        await sut.start(userID: "me")
        XCTAssertEqual(sut.availability, .denied)
        XCTAssertEqual(system.registrations, 0)
    }

    func testMuteIsSavedAndRemembered() async {
        system.token = "fcm-1"
        await sut.start(userID: "me")
        sut.muted = true
        for _ in 0..<3 { await settleTasks() }
        XCTAssertEqual(store.saved.last?.device.muted, true)
        XCTAssertTrue(PushManager(system: system, devices: store, defaults: defaults).muted)
    }

    func testStopRemovesDeviceAndToken() async {
        system.token = "fcm-1"
        await sut.start(userID: "me")
        await sut.stop()
        XCTAssertEqual(store.deleted.first?.userID, "me")
        XCTAssertEqual(system.deletedTokens, 1)
        XCTAssertEqual(sut.availability, .unknown)
        XCTAssertEqual(system.badges.last, 0)
    }
}

// MARK: - Bildirimden yanıt / okundu

@MainActor
final class ChatQuickActionsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testReplySendsMessageMarksReadAndNotifies() async throws {
        let sync = MockChatSync()
        sync.olderPages = [[
            ChatMessageDTO(id: "r1", senderID: "friend", text: "selam", createdAt: now),
            ChatMessageDTO(id: "r0", senderID: "friend", text: "eski", createdAt: now, readAt: now),
            ChatMessageDTO(id: "m0", senderID: "me", text: "benim", createdAt: now)
        ]]
        let notifier = MockNotifier()
        let sut = ChatQuickActions(sync: sync, notifier: notifier, currentUserID: { "me" }, clock: { self.now }, makeID: { "q1" })
        try await sut.reply("  Geliyorum  ", chatID: "friend_me")
        XCTAssertEqual(sync.sent.map(\.text), ["Geliyorum"])
        XCTAssertEqual(sync.sent.first?.senderID, "me")
        XCTAssertEqual(sync.reads, [["r1"]], "yalnızca karşı tarafın okunmamışları")
        XCTAssertEqual(notifier.calls, ["friend_me/q1"])

        try await sut.reply("   ", chatID: "friend_me")
        XCTAssertEqual(sync.sent.count, 1, "boş yanıt gönderilmez")
    }

    func testRejectsForeignChatOrSignedOut() async {
        let sync = MockChatSync()
        let foreign = ChatQuickActions(sync: sync, notifier: nil, currentUserID: { "me" })
        do {
            try await foreign.reply("x", chatID: "a_b")
            XCTFail("başka odaya yazılmaz")
        } catch {
            XCTAssertEqual(error as? AppError, .notAuthorized)
        }
        let signedOut = ChatQuickActions(sync: sync, notifier: nil, currentUserID: { nil })
        do {
            _ = try await signedOut.markRead(chatID: "friend_me")
            XCTFail("oturum gerekir")
        } catch {
            XCTAssertEqual(error as? AppError, .notAuthenticated)
        }
        XCTAssertTrue(sync.sent.isEmpty)
    }
}

// MARK: - Sohbette bildirim isteği ve uygulama içi şerit

@MainActor
final class ChatPushFlowTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockChatSync!
    private var notifier: MockNotifier!
    private var hub: ChatHub!
    private var counter = 0
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let me = AppUser.makeNew(id: "me", email: "ben@ornek.com", displayName: "Ben")
    private let partnerRoom = ChatRoomDTO(id: "friend_me", members: ["friend", "me"], names: ["friend": "Elif", "me": "Ben"],
                                          createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    private let personalRoom = ChatRoomDTO(id: "me_me", members: ["me", "me"], createdAt: Date(timeIntervalSince1970: 1_800_000_000))

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: ChatMessageRecord.self, ChatPendingOperation.self, ChatPlacementRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sync = MockChatSync()
        notifier = MockNotifier()
        counter = 0
        let defaults = makeTestDefaults("pushflow.\(name)")
        let root = makeTemporaryDirectory()
        func make(_ kind: ChatRoomKind) -> ChatViewModel {
            ChatViewModel(kind: kind, sync: sync, mediaStore: MockMediaStore(), processor: MockMediaProcessor(),
                          files: ChatMediaFiles(persistentRoot: root.appendingPathComponent("s"), cacheRoot: root.appendingPathComponent("c")),
                          defaults: defaults, notifier: notifier, clock: { [unowned self] in self.now },
                          makeID: { [unowned self] in
                              self.counter += 1
                              return "\(kind.rawValue)-\(self.counter)"
                          })
        }
        hub = ChatHub(partner: make(.partner), personal: make(.personal))
        hub.configure(context: container.mainContext, user: me)
        sync.roomHandlers[.partner]?(partnerRoom, false)
        sync.roomHandlers[.personal]?(personalRoom, false)
        await settle()
    }

    override func tearDown() async throws {
        await settleTasks()
        hub.reset()
        await settleTasks()
        hub = nil
        container = nil
        try await super.tearDown()
    }

    private func settle() async {
        for _ in 0..<3 {
            await settleTasks()
            await hub.partner.flushOutbox()
            await hub.personal.flushOutbox()
        }
    }

    func testRecipientIsNotifiedAfterMessageIsWritten() async {
        sync.isOffline = true
        hub.partner.draft = "Akşam spor?"
        hub.partner.send()
        await settle()
        XCTAssertTrue(notifier.calls.isEmpty, "mesaj sunucuya yazılmadan bildirim istenmez")

        sync.isOffline = false
        await settle()
        XCTAssertEqual(notifier.calls, ["friend_me/partner-1"])

        hub.personal.draft = "not"
        hub.personal.send()
        await settle()
        XCTAssertEqual(notifier.calls.count, 1, "not sohbetinde bildirim yok")
    }

    func testBannerForNewIncomingMessageOnlyWhenConversationNotOpen() {
        hub.isTabVisible = false
        sync.messageHandlers["friend_me"]?([ChatMessageDTO(id: "r1", senderID: "friend", text: "Neredesin?", createdAt: now)])
        XCTAssertEqual(hub.banner, ChatBanner(id: "r1", kind: .partner, title: "Elif", body: "Neredesin?"))

        hub.open(.partner)
        XCTAssertNil(hub.banner)
        XCTAssertEqual(hub.pendingOpen, .partner)
        XCTAssertEqual(hub.kind(forChatID: "friend_me"), .partner)
        XCTAssertEqual(hub.kind(forChatID: "me_me"), .personal)
        XCTAssertNil(hub.kind(forChatID: "x_y"))

        // Aynı mesaj tekrar gelirse (dinleyici güncellemesi) şerit yeniden çıkmaz; eski mesajlar da çıkarmaz.
        sync.messageHandlers["friend_me"]?([
            ChatMessageDTO(id: "r1", senderID: "friend", text: "Neredesin?", createdAt: now),
            ChatMessageDTO(id: "old", senderID: "friend", text: "dün", createdAt: now.addingTimeInterval(-86_400))
        ])
        XCTAssertNil(hub.banner)

        // Konuşma açıkken şerit yok.
        hub.isTabVisible = true
        hub.openConversation = .partner
        sync.messageHandlers["friend_me"]?([ChatMessageDTO(id: "r2", senderID: "friend", text: "?", createdAt: now)])
        XCTAssertNil(hub.banner)

        // Uygulama arka plandayken sistem bildirimi gelir, şerit değil.
        hub.openConversation = nil
        hub.isAppActive = false
        sync.messageHandlers["friend_me"]?([ChatMessageDTO(id: "r3", senderID: "friend", text: "!", createdAt: now)])
        XCTAssertNil(hub.banner)
    }
}

// MARK: - Sunucu isteği

@MainActor
final class MediaServerNotifyTests: XCTestCase {
    func testNotifyPostsChatAndMessage() async throws {
        StubURLProtocol.reset { _ in (200, Data(#"{"sent":1}"#.utf8)) }
        let client = MediaServerClient(baseURL: URL(string: "https://media.example.workers.dev")!,
                                       session: StubURLProtocol.session(), token: { "belirtec" })
        try await client.notify(chatID: "friend_me", messageID: "m1")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/v1/notify")
        XCTAssertEqual(request.headers["Authorization"], "Bearer belirtec")
        if let body = request.body, !body.isEmpty {
            XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: body), ["chatId": "friend_me", "messageId": "m1"])
        }
    }
}
