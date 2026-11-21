import XCTest
import SwiftData
@testable import FarvaTrack

// MARK: - Sahte sohbet servisi

final class MockChatSync: ChatSyncing {
    var inviteResult: Result<ChatInvite, Error> = .failure(AppError.network)
    var redeemResult: Result<ChatRoomDTO, Error> = .failure(AppError.network)
    /// Sıradaki yazım çağrılarına sırayla fırlatılacak hatalar.
    var nextErrors: [Error] = []
    /// Açıkken tüm yazımlar ağ hatası verir.
    var isOffline = false
    var olderPages: [[ChatMessageDTO]] = []

    private(set) var redeemedCodes: [String] = []
    private(set) var sendAttempts = 0
    private(set) var sent: [ChatMessageDTO] = []
    private(set) var edits: [(id: String, text: String)] = []
    private(set) var deletions: [String] = []
    private(set) var mediaUpdates: [(id: String, media: ChatMedia)] = []
    /// Gönderim anında çağrılır (sıra testleri için).
    var onSend: ((ChatMessageDTO) -> Void)?
    private(set) var reactions: [(id: String, emoji: String?)] = []
    private(set) var reads: [[String]] = []
    private(set) var typing: [Bool] = []
    private(set) var fetchBefore: [Date] = []
    private(set) var observedChats: [String] = []

    var roomHandler: (@MainActor (ChatRoomDTO?, Bool) -> Void)?
    var messagesHandler: (@MainActor ([ChatMessageDTO]) -> Void)?

    private func write() throws {
        if isOffline { throw AppError.network }
        if !nextErrors.isEmpty { throw nextErrors.removeFirst() }
    }

    func createInvite(ownerID: String, ownerName: String, now: Date) async throws -> ChatInvite { try inviteResult.get() }

    func redeemInvite(code: String, userID: String, userName: String, now: Date) async throws -> ChatRoomDTO {
        redeemedCodes.append(code)
        return try redeemResult.get()
    }

    func observeRoom(userID: String, onChange: @escaping @MainActor (ChatRoomDTO?, Bool) -> Void, onError: @escaping @MainActor (AppError) -> Void) -> ChatSubscription {
        roomHandler = onChange
        return ChatSubscription { [weak self] in self?.roomHandler = nil }
    }

    func observeRecentMessages(chatID: String, limit: Int, onChange: @escaping @MainActor ([ChatMessageDTO]) -> Void, onError: @escaping @MainActor (AppError) -> Void) -> ChatSubscription {
        observedChats.append(chatID)
        messagesHandler = onChange
        return ChatSubscription { [weak self] in self?.messagesHandler = nil }
    }

    func fetchMessages(chatID: String, before: Date, limit: Int) async throws -> [ChatMessageDTO] {
        fetchBefore.append(before)
        return olderPages.isEmpty ? [] : olderPages.removeFirst()
    }

    func sendMessage(_ message: ChatMessageDTO, chatID: String) async throws {
        sendAttempts += 1
        try write()
        onSend?(message)
        sent.append(message)
    }

    func editMessage(id: String, chatID: String, text: String, editedAt: Date) async throws {
        try write()
        edits.append((id, text))
    }

    func deleteMessageForEveryone(id: String, chatID: String) async throws {
        try write()
        deletions.append(id)
    }

    private(set) var listens: [String] = []
    func markListened(messageID: String, chatID: String, at: Date) async throws {
        try write()
        listens.append(messageID)
    }

    // MARK: Yerleştirmeler
    var placementsHandler: (@MainActor ([ChatPlacementDTO], Bool) -> Void)?
    private(set) var savedPlacements: [ChatPlacementDTO] = []
    private(set) var deletedPlacements: [String] = []

    func observePlacements(chatID: String, onChange: @escaping @MainActor ([ChatPlacementDTO], Bool) -> Void,
                           onError: @escaping @MainActor (AppError) -> Void) -> ChatSubscription {
        placementsHandler = onChange
        return ChatSubscription { [weak self] in self?.placementsHandler = nil }
    }

    func savePlacement(_ placement: ChatPlacementDTO, chatID: String) async throws {
        try write()
        savedPlacements.append(placement)
    }

    func deletePlacement(id: String, chatID: String) async throws {
        try write()
        deletedPlacements.append(id)
    }

    func updateMedia(_ media: ChatMedia, messageID: String, chatID: String) async throws {
        try write()
        mediaUpdates.append((messageID, media))
    }

    func setReaction(_ emoji: String?, messageID: String, chatID: String, userID: String) async throws {
        try write()
        reactions.append((messageID, emoji))
    }

    func markRead(messageIDs: [String], chatID: String, at: Date) async throws {
        try write()
        reads.append(messageIDs)
    }

    func setTyping(_ isTyping: Bool, chatID: String, userID: String, at: Date) async throws {
        typing.append(isTyping)
    }

    func purgeUserData(userID: String) async throws {}
}

// MARK: - Model testleri

final class ChatModelTests: XCTestCase {
    func testUnknownMessageTypeFallsBackSafely() {
        XCTAssertEqual(ChatMessageType(rawOrUnknown: "text"), .text)
        XCTAssertEqual(ChatMessageType(rawOrUnknown: "sticker"), .sticker)
        XCTAssertEqual(ChatMessageType(rawOrUnknown: "hologram"), .unknown, "ileride eklenecek türler eski sürümü çökertmez")
        XCTAssertTrue(ChatMessageType.sendable.isSuperset(of: [.text, .image, .video, .audio]))
        XCTAssertFalse(ChatMessageType.sendable.contains(.unknown))
    }

    func testChatIDIsSymmetricAndSorted() {
        XCTAssertEqual(ChatID.make("zeynep", "ali"), "ali_zeynep")
        XCTAssertEqual(ChatID.make("ali", "zeynep"), ChatID.make("zeynep", "ali"))
        XCTAssertEqual(ChatID.sortedMembers("b", "a"), ["a", "b"])
    }

    func testInviteCodeNormalizeAndValidate() {
        XCTAssertEqual(ChatInviteCode.normalize(" k7p 2-qx "), "K7P2QX")
        XCTAssertEqual(ChatInviteCode.normalize("abcdei"), "ABCDEI", "Türkçe klavyede yazılan i, I olur")
        XCTAssertTrue(ChatInviteCode.isValid("K7P2QX"))
        XCTAssertFalse(ChatInviteCode.isValid("K7P2Q"), "kısa")
        XCTAssertFalse(ChatInviteCode.isValid("K7P2Q0"), "0 karışmasın diye alfabede yok")
        XCTAssertFalse(ChatInviteCode.isValid("K7P2QXZ"), "uzun")
    }

    func testGeneratedCodesAreValid() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<100 {
            XCTAssertTrue(ChatInviteCode.isValid(ChatInviteCode.generate(using: &generator)))
        }
        XCTAssertTrue(ChatInviteCode.isValid(ChatInviteCode.generate()))
    }

    func testSearchIsCaseAndDiacriticInsensitiveInTurkish() {
        XCTAssertTrue(ChatText.matches("Yarın İstanbul'a gidiyoruz", query: "istanbul"))
        XCTAssertTrue(ChatText.matches("ISPARTA", query: "ısparta"))
        XCTAssertTrue(ChatText.matches("ISTANBUL", query: "istanbul"), "İngilizce klavyeyle yazılmış büyük I")
        XCTAssertTrue(ChatText.matches("Ağrı dağı", query: "AGRI"))
        XCTAssertTrue(ChatText.matches("Çok güzel", query: "cok guzel"))
        XCTAssertFalse(ChatText.matches("Merhaba", query: "  "))
        XCTAssertFalse(ChatText.matches("Merhaba", query: "selam"))
    }

    func testPreviewAndSanitizing() {
        XCTAssertEqual(ChatText.preview("satır1\nsatır2", limit: 50), "satır1 satır2")
        XCTAssertEqual(ChatText.preview("abcdefghij", limit: 4), "abcd…")
        XCTAssertEqual(ChatText.sanitizedOutgoing("  selam \n"), "selam")
        XCTAssertNil(ChatText.sanitizedOutgoing("   \n "))
        XCTAssertNil(ChatText.sanitizedOutgoing(String(repeating: "a", count: ChatLimits.maxTextLength + 1)))
        XCTAssertNotNil(ChatText.sanitizedOutgoing(String(repeating: "a", count: ChatLimits.maxTextLength)))
    }

    func testReplyReferenceUsesPlaceholderForDeletedAndMedia() {
        let date = Date(timeIntervalSince1970: 1_000)
        let deleted = ChatMessageDTO(id: "1", senderID: "a", text: "", createdAt: date, deleted: true)
        XCTAssertEqual(ChatReplyReference.make(from: deleted).preview, "Bu mesaj silindi")
        let photo = ChatMessageDTO(id: "2", senderID: "a", type: .image, text: "", createdAt: date)
        XCTAssertEqual(ChatReplyReference.make(from: photo).preview, "📷 Fotoğraf")
        let long = ChatMessageDTO(id: "3", senderID: "a", text: String(repeating: "x", count: 500), createdAt: date)
        XCTAssertLessThanOrEqual(ChatReplyReference.make(from: long).preview.count, ChatLimits.replyPreviewLength + 1)
    }

    func testRoomTypingAndNames() {
        let now = Date(timeIntervalSince1970: 10_000)
        let room = ChatRoomDTO(
            id: "a_b", members: ["a", "b"], names: ["a": "Ali", "b": "  "], createdAt: now,
            typing: ["b": now.addingTimeInterval(-2), "a": now.addingTimeInterval(-30)]
        )
        XCTAssertEqual(room.otherMember(of: "a"), "b")
        XCTAssertEqual(room.displayName(of: "a"), "Ali")
        XCTAssertEqual(room.displayName(of: "b"), "Sohbet arkadaşın", "boş ad yerine yedek ad")
        XCTAssertTrue(room.isTyping("b", now: now))
        XCTAssertFalse(room.isTyping("a", now: now), "eski sinyal zaman aşımına uğrar")
        XCTAssertFalse(room.isTyping("c", now: now))
    }

    func testRoomCacheRoundTripDropsTyping() {
        let defaults = makeTestDefaults()
        let cache = ChatRoomCache(defaults: defaults)
        let room = ChatRoomDTO(id: "a_b", members: ["a", "b"], names: ["a": "Ali"], createdAt: Date(timeIntervalSince1970: 5), typing: ["b": .now])
        cache.save(room, userID: "a")
        let loaded = cache.load(userID: "a")
        XCTAssertEqual(loaded?.id, "a_b")
        XCTAssertEqual(loaded?.names["a"], "Ali")
        XCTAssertEqual(loaded?.typing, [:])
        XCTAssertNil(cache.load(userID: "b"))
        cache.clear(userID: "a")
        XCTAssertNil(cache.load(userID: "a"))
    }

    func testPairingRules() {
        let now = Date(timeIntervalSince1970: 100_000)
        let invite = ChatInvite(code: "K7P2QX", ownerID: "owner", ownerName: "Ali", createdAt: now, expiresAt: now.addingTimeInterval(60))
        XCTAssertNoThrow(try ChatPairingRules.validate(invite: invite, redeemerID: "friend", now: now))
        XCTAssertThrowsError(try ChatPairingRules.validate(invite: invite, redeemerID: "owner", now: now), "kendi kodu")
        XCTAssertThrowsError(try ChatPairingRules.validate(invite: invite, redeemerID: "friend", now: now.addingTimeInterval(61)), "süresi doldu")
        var used = invite
        used.redeemedBy = "someone"
        XCTAssertThrowsError(try ChatPairingRules.validate(invite: used, redeemerID: "friend", now: now), "kullanılmış")
    }

    func testReactionSummaryGroupsAndHidesOnDeleted() {
        let date = Date(timeIntervalSince1970: 1)
        let dto = ChatMessageDTO(id: "1", senderID: "a", text: "x", createdAt: date, reactions: ["a": "❤️", "b": "❤️"])
        let item = ChatMessageItem(message: dto, isMine: true, status: .delivered, myReaction: "❤️", canEdit: true)
        XCTAssertEqual(item.reactionSummary.map(\.emoji), ["❤️"])
        XCTAssertEqual(item.reactionSummary.first?.count, 2)

        var deleted = dto
        deleted.deleted = true
        let deletedItem = ChatMessageItem(message: deleted, isMine: true, status: .delivered, myReaction: nil, canEdit: false)
        XCTAssertTrue(deletedItem.reactionSummary.isEmpty)
        XCTAssertEqual(deletedItem.displayText, "Bu mesaj silindi")
    }

    @MainActor
    func testRecordKeepsLocalStateWhenApplyingRemote() throws {
        let container = try ModelContainer(for: ChatMessageRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let date = Date(timeIntervalSince1970: 1)
        let reply = ChatReplyReference(messageID: "0", senderID: "b", preview: "önceki", type: .text)
        let record = ChatMessageRecord(
            dto: ChatMessageDTO(id: "1", senderID: "a", text: "ilk", createdAt: date, replyTo: reply, reactions: ["b": "🔥"]),
            ownerID: "a", chatID: "a_b", sendState: .sent
        )
        container.mainContext.insert(record)
        record.hiddenForMe = true

        XCTAssertEqual(record.key, "a|1")
        XCTAssertEqual(record.replyTo, reply)
        XCTAssertEqual(record.reactions, ["b": "🔥"])

        record.apply(remote: ChatMessageDTO(id: "1", senderID: "a", text: "düzeltildi", createdAt: date, readAt: date, editedAt: date))
        XCTAssertEqual(record.text, "düzeltildi")
        XCTAssertEqual(record.readAt, date)
        XCTAssertNil(record.replyTo)
        XCTAssertEqual(record.reactions, [:])
        XCTAssertTrue(record.hiddenForMe, "'benden sil' yalnızca yereldir, sunucu verisi ezmez")
        XCTAssertEqual(record.sendState, .sent)
    }
}

/// Tekrarlanabilir rastgele sayı üreteci (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - ViewModel testleri

@MainActor
final class ChatViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockChatSync!
    private var defaults: UserDefaults!
    private var sut: ChatViewModel!
    private var currentTime = Date(timeIntervalSince1970: 1_800_000_000)
    private var idCounter = 0

    private let me = AppUser.makeNew(id: "me", email: "ben@ornek.com", displayName: "Ben")
    private var room: ChatRoomDTO {
        ChatRoomDTO(
            id: ChatID.make("me", "friend"),
            members: ChatID.sortedMembers("me", "friend"),
            names: ["me": "Ben", "friend": "Elif"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: ChatMessageRecord.self, ChatPendingOperation.self, ChatPlacementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        sync = MockChatSync()
        defaults = makeTestDefaults("chat.\(name)")
        idCounter = 0
        sut = ChatViewModel(
            sync: sync,
            defaults: defaults,
            clock: { [unowned self] in self.currentTime },
            makeID: { [unowned self] in
                self.idCounter += 1
                return "local-\(self.idCounter)"
            }
        )
    }

    override func tearDown() async throws {
        // Arka plandaki gönderim / "yazıyor" görevleri bitmeden bellek içi veritabanı bırakılmaz.
        await settleTasks()
        sut.reset()
        await settleTasks()
        sut = nil
        sync = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: Yardımcılar

    private func configurePaired() async {
        sut.configure(context: container.mainContext, user: me)
        sync.roomHandler?(room, false)
        await settle()
    }

    private func settle() async {
        await settleTasks()
        await sut.flushOutbox()
    }

    private func remote(_ id: String, from sender: String = "friend", text: String = "selam", secondsAgo: TimeInterval = 0, readAt: Date? = nil) -> ChatMessageDTO {
        ChatMessageDTO(id: id, senderID: sender, text: text, createdAt: currentTime.addingTimeInterval(-secondsAgo), readAt: readAt)
    }

    private func item(_ id: String) -> ChatMessageItem? {
        sut.messages.first { $0.id == id }
    }

    // MARK: Eşleşme

    func testUnpairedWhenServerHasNoRoom() {
        sut.configure(context: container.mainContext, user: me)
        XCTAssertEqual(sut.phase, .loading)
        sync.roomHandler?(nil, true)
        XCTAssertEqual(sut.phase, .unpaired, "önbellekte de oda yoksa eşleşme ekranı")
        sync.roomHandler?(nil, false)
        XCTAssertEqual(sut.phase, .unpaired)
    }

    func testCreateInvitePublishesCode() async {
        sut.configure(context: container.mainContext, user: me)
        let invite = ChatInvite(code: "K7P2QX", ownerID: "me", ownerName: "Ben", createdAt: currentTime, expiresAt: currentTime.addingTimeInterval(ChatLimits.inviteLifetime))
        sync.inviteResult = .success(invite)
        await sut.createInvite()
        XCTAssertEqual(sut.invite, invite)

        // Karşı taraf kodu kullanınca dinleyici odayı getirir.
        sync.roomHandler?(room, false)
        XCTAssertEqual(sut.phase, .ready)
        XCTAssertNil(sut.invite)
        XCTAssertEqual(sut.partnerName, "Elif")
        XCTAssertEqual(sync.observedChats, [room.id])
    }

    func testRedeemValidatesCodeLocallyFirst() async {
        sut.configure(context: container.mainContext, user: me)
        sut.inviteCodeInput = "ab"
        let ok = await sut.redeemInvite()
        XCTAssertFalse(ok)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sync.redeemedCodes.isEmpty, "geçersiz kod sunucuya gitmez")
    }

    func testRedeemSuccessOpensChatAndCachesRoom() async {
        sut.configure(context: container.mainContext, user: me)
        sync.redeemResult = .success(room)
        sut.inviteCodeInput = "k7p 2qx"
        let ok = await sut.redeemInvite()
        XCTAssertTrue(ok)
        XCTAssertEqual(sync.redeemedCodes, ["K7P2QX"])
        XCTAssertEqual(sut.phase, .ready)
        XCTAssertEqual(sut.inviteCodeInput, "")
        XCTAssertEqual(ChatRoomCache(defaults: defaults).load(userID: "me")?.id, room.id)
    }

    func testRedeemErrorIsShown() async {
        sut.configure(context: container.mainContext, user: me)
        sync.redeemResult = .failure(AppError.invalidInput("Bu davet kodu bulunamadı."))
        sut.inviteCodeInput = "K7P2QX"
        let ok = await sut.redeemInvite()
        XCTAssertFalse(ok)
        XCTAssertEqual(sut.errorMessage, "Bu davet kodu bulunamadı.")
        XCTAssertEqual(sut.phase, .loading)
    }

    func testCachedRoomOpensOfflineWithCachedMessages() async throws {
        ChatRoomCache(defaults: defaults).save(room, userID: "me")
        let context = container.mainContext
        context.insert(ChatMessageRecord(dto: remote("old", secondsAgo: 60, readAt: currentTime), ownerID: "me", chatID: room.id, sendState: .sent))
        try context.save()

        sut.configure(context: context, user: me)
        XCTAssertEqual(sut.phase, .ready, "çevrimdışı açılışta önbellekteki oda gösterilir")
        XCTAssertEqual(sut.messages.map(\.id), ["old"])

        sync.roomHandler?(nil, true)
        XCTAssertEqual(sut.phase, .ready, "boş yerel önbellek sonucu odayı kapatmaz")
    }

    func testRoomRemovedOnServerPurgesLocalChat() async {
        await configurePaired()
        sync.messagesHandler?([remote("r1")])
        XCTAssertEqual(sut.messages.count, 1)

        sync.roomHandler?(nil, false)
        XCTAssertEqual(sut.phase, .unpaired)
        XCTAssertTrue(sut.messages.isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<ChatMessageRecord>()).isEmpty)
        XCTAssertNil(ChatRoomCache(defaults: defaults).load(userID: "me"))
    }

    // MARK: Gönderme

    func testSendShowsSendingThenDelivered() async {
        await configurePaired()
        sut.draft = "  Merhaba Elif  "
        XCTAssertTrue(sut.canSend)
        sut.send()

        XCTAssertEqual(sut.draft, "")
        XCTAssertEqual(sut.messages.map(\.message.text), ["Merhaba Elif"])
        XCTAssertEqual(sut.messages.first?.status, .sending)

        await settle()
        XCTAssertEqual(sync.sent.map(\.text), ["Merhaba Elif"])
        XCTAssertEqual(sut.messages.first?.status, .delivered)
        XCTAssertTrue(sut.pendingOperations().isEmpty)
    }

    func testEmptyOrTooLongDraftIsNotSent() async {
        await configurePaired()
        sut.draft = "   "
        XCTAssertFalse(sut.canSend)
        sut.send()
        sut.draft = String(repeating: "a", count: ChatLimits.maxTextLength + 1)
        XCTAssertTrue(sut.draftIsTooLong)
        sut.send()
        await settle()
        XCTAssertTrue(sync.sent.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
    }

    func testOfflineMessagesAreQueuedAndSentInOrderLater() async {
        await configurePaired()
        sync.isOffline = true
        sut.draft = "bir"
        sut.send()
        await settle()
        sut.draft = "iki"
        sut.send()
        await settle()

        XCTAssertTrue(sync.sent.isEmpty, "ağ yokken kuyrukta bekler")
        XCTAssertEqual(sut.messages.map(\.status), [.sending, .sending])
        XCTAssertEqual(sut.pendingOperations().filter { $0.kind == .create }.count, 2)

        sync.isOffline = false
        await sut.handleForeground()
        XCTAssertEqual(sync.sent.map(\.text), ["bir", "iki"], "sıra korunur")
        XCTAssertEqual(sut.messages.map(\.status), [.delivered, .delivered])
    }

    func testPermanentFailureMarksFailedAndRetryWorks() async {
        await configurePaired()
        sync.nextErrors = [AppError.notAuthorized, AppError.notAuthorized, AppError.notAuthorized]
        sut.draft = "olmayacak"
        sut.send()
        for _ in 0..<5 {
            await settle()
            if item("local-1")?.status == .failed { break }
        }
        XCTAssertEqual(sync.sendAttempts, 3)
        XCTAssertEqual(item("local-1")?.status, .failed)
        XCTAssertFalse(item("local-1")?.canEdit ?? true)

        sut.retry(item("local-1")!)
        XCTAssertEqual(item("local-1")?.status, .sending)
        await settle()
        XCTAssertEqual(item("local-1")?.status, .delivered)
        XCTAssertEqual(sync.sent.count, 1)
    }

    func testReplyIsAttachedToNextMessage() async {
        await configurePaired()
        sync.messagesHandler?([remote("r1", text: "Akşam spora gidiyor muyuz?")])
        sut.beginReply(to: item("r1")!)
        XCTAssertEqual(sut.replyingTo?.id, "r1")

        sut.draft = "Evet!"
        sut.send()
        await settle()
        XCTAssertNil(sut.replyingTo)
        XCTAssertEqual(sync.sent.first?.replyTo?.messageID, "r1")
        XCTAssertEqual(sync.sent.first?.replyTo?.preview, "Akşam spora gidiyor muyuz?")
        XCTAssertEqual(item("local-1")?.message.replyTo?.senderID, "friend")
    }

    // MARK: Okundu

    func testIncomingMessagesAreMarkedReadOnlyWhileVisible() async {
        await configurePaired()
        sync.messagesHandler?([remote("r1"), remote("r2", secondsAgo: 5)])
        await settle()
        XCTAssertEqual(sut.unreadCount, 2)
        XCTAssertTrue(sync.reads.isEmpty, "sohbet ekranı açık değilken okundu gönderilmez")

        sut.setVisible(true)
        await settle()
        XCTAssertEqual(sut.unreadCount, 0)
        XCTAssertEqual(sync.reads.count, 1, "tek toplu yazım")
        XCTAssertEqual(Set(sync.reads.first ?? []), ["r1", "r2"])

        // Yeni mesaj ekran açıkken gelirse hemen okunur.
        sync.messagesHandler?([remote("r3"), remote("r1", readAt: currentTime), remote("r2", secondsAgo: 5, readAt: currentTime)])
        await settle()
        XCTAssertEqual(sync.reads.last, ["r3"])
    }

    func testOwnMessageShowsReadWhenPartnerReads() async {
        await configurePaired()
        sut.draft = "Görüldü mü?"
        sut.send()
        await settle()
        let sentMessage = sync.sent[0]

        var readCopy = sentMessage
        readCopy.readAt = currentTime
        sync.messagesHandler?([readCopy])
        XCTAssertEqual(item(sentMessage.id)?.status, .read)
    }

    // MARK: Düzenleme ve silme

    func testEditWithinWindowSendsEditAndMarksEdited() async {
        await configurePaired()
        sut.draft = "yanlş"
        sut.send()
        await settle()

        let sentItem = item("local-1")!
        XCTAssertTrue(sentItem.canEdit)
        sut.beginEdit(sentItem)
        XCTAssertEqual(sut.draft, "yanlş")
        sut.draft = "yanlış"
        sut.send()
        await settle()

        XCTAssertNil(sut.editing)
        XCTAssertEqual(sync.edits.map(\.text), ["yanlış"])
        XCTAssertEqual(item("local-1")?.message.text, "yanlış")
        XCTAssertNotNil(item("local-1")?.message.editedAt)
        XCTAssertEqual(sync.sent.count, 1, "düzenleme yeni mesaj değildir")
    }

    func testEditWindowExpires() async {
        await configurePaired()
        sut.draft = "eski"
        sut.send()
        await settle()
        currentTime = currentTime.addingTimeInterval(ChatLimits.editWindow + 1)
        sut.tick()
        XCTAssertFalse(item("local-1")?.canEdit ?? true)
        sut.beginEdit(item("local-1")!)
        XCTAssertNil(sut.editing)
    }

    func testEditingUnsentMessageUpdatesQueuedTextOnly() async {
        await configurePaired()
        sync.isOffline = true
        sut.draft = "ilk hali"
        sut.send()
        await settle()

        sut.beginEdit(item("local-1")!)
        sut.draft = "son hali"
        sut.send()
        await settle()
        XCTAssertNil(item("local-1")?.message.editedAt, "hiç gönderilmemiş mesaj 'düzenlendi' sayılmaz")

        sync.isOffline = false
        await sut.handleForeground()
        XCTAssertEqual(sync.sent.map(\.text), ["son hali"])
        XCTAssertTrue(sync.edits.isEmpty)
    }

    func testDeleteForEveryone() async {
        await configurePaired()
        sut.draft = "sil beni"
        sut.send()
        await settle()

        sut.deleteForEveryone(item("local-1")!)
        await settle()
        XCTAssertEqual(sync.deletions, ["local-1"])
        XCTAssertEqual(item("local-1")?.displayText, "Bu mesaj silindi")
        XCTAssertNil(sut.copyText(for: item("local-1")!))
        XCTAssertFalse(item("local-1")?.canEdit ?? true)
    }

    func testDeleteForEveryoneOnlyForOwnMessages() async {
        await configurePaired()
        sync.messagesHandler?([remote("r1")])
        sut.deleteForEveryone(item("r1")!)
        await settle()
        XCTAssertTrue(sync.deletions.isEmpty)
        XCTAssertFalse(item("r1")?.message.deleted ?? true)
    }

    func testDeletingUnsentMessageNeverSendsIt() async {
        await configurePaired()
        sync.isOffline = true
        sut.draft = "vazgeçtim"
        sut.send()
        await settle()

        sut.deleteForEveryone(item("local-1")!)
        sync.isOffline = false
        await sut.handleForeground()
        XCTAssertTrue(sync.sent.isEmpty)
        XCTAssertTrue(sync.deletions.isEmpty)
        XCTAssertNil(item("local-1"))
        XCTAssertTrue(sut.pendingOperations().isEmpty)
    }

    func testDeleteForMeHidesOnlyLocally() async {
        await configurePaired()
        sync.messagesHandler?([remote("r1"), remote("r2", secondsAgo: 1)])
        sut.deleteForMe(item("r1")!)
        XCTAssertEqual(sut.messages.map(\.id), ["r2"])

        // Sunucudan yeniden gelse de gizli kalır.
        sync.messagesHandler?([remote("r1"), remote("r2", secondsAgo: 1)])
        XCTAssertEqual(sut.messages.map(\.id), ["r2"])
        XCTAssertTrue(sync.deletions.isEmpty)
    }

    // MARK: Tepki

    func testReactionToggleAndReplace() async {
        await configurePaired()
        sync.messagesHandler?([remote("r1")])

        sut.toggleReaction("❤️", on: item("r1")!)
        XCTAssertEqual(item("r1")?.myReaction, "❤️")
        await settle()
        sut.toggleReaction("❤️", on: item("r1")!)
        XCTAssertNil(item("r1")?.myReaction, "aynı emoji tekrar: kaldırılır")
        await settle()
        sut.toggleReaction("😂", on: item("r1")!)
        await settle()

        XCTAssertEqual(sync.reactions.map(\.emoji), ["❤️", nil, "😂"])
    }

    func testPendingLocalChangeWinsOverStaleSnapshot() async {
        await configurePaired()
        sync.messagesHandler?([remote("r1")])
        sync.isOffline = true
        sut.toggleReaction("🔥", on: item("r1")!)
        await settle()

        // Sunucudan eski hal gelir: karşı tarafın okundu bilgisi alınır, bekleyen tepkim korunur.
        var stale = remote("r1")
        stale.reactions = ["friend": "👍"]
        sync.messagesHandler?([stale])
        XCTAssertEqual(item("r1")?.myReaction, "🔥")
        XCTAssertEqual(item("r1")?.message.reactions["friend"], "👍")
    }

    // MARK: Yazıyor…

    func testTypingIsThrottledAndClearedOnEmptyDraft() async {
        await configurePaired()
        sut.draft = "m"
        sut.draftChanged()
        sut.draft = "me"
        sut.draftChanged()
        await settleTasks()
        XCTAssertEqual(sync.typing, [true], "3 saniye içinde tek sinyal")

        currentTime = currentTime.addingTimeInterval(ChatLimits.typingThrottle + 0.1)
        sut.draft = "mer"
        sut.draftChanged()
        sut.draft = ""
        sut.draftChanged()
        await settleTasks()
        XCTAssertEqual(sync.typing, [true, true, false])
    }

    func testPartnerTypingIndicatorExpires() async {
        await configurePaired()
        var typingRoom = room
        typingRoom.typing = ["friend": currentTime]
        sync.roomHandler?(typingRoom, false)
        XCTAssertTrue(sut.isPartnerTyping)

        currentTime = currentTime.addingTimeInterval(ChatLimits.typingTimeout + 1)
        sut.tick()
        XCTAssertFalse(sut.isPartnerTyping)
    }

    // MARK: Arama ve sayfalama

    func testSearchFindsTurkishTextAndSkipsDeleted() async {
        await configurePaired()
        var deleted = remote("r3", text: "", secondsAgo: 1)
        deleted.deleted = true
        sync.messagesHandler?([remote("r1", text: "Yarın İstanbul'dayım", secondsAgo: 10), remote("r2", text: "tamam"), deleted])

        sut.searchQuery = "istanbul"
        XCTAssertEqual(sut.searchResults.map(\.id), ["r1"])
        sut.searchQuery = "xyz"
        XCTAssertTrue(sut.searchResults.isEmpty)
        sut.searchQuery = ""
        XCTAssertTrue(sut.searchResults.isEmpty)
        XCTAssertTrue(sut.reveal(messageID: "r1"))
    }

    func testPaginationLoadsOlderPagesUntilExhausted() async {
        await configurePaired()
        let page = (0..<ChatLimits.pageSize).map { remote("n\($0)", secondsAgo: TimeInterval($0 * 60)) }
        sync.messagesHandler?(page)
        XCTAssertEqual(sut.messages.count, ChatLimits.pageSize)
        XCTAssertEqual(sut.messages.first?.id, "n49", "eskiden yeniye sıralı")
        XCTAssertEqual(sut.messages.last?.id, "n0")
        XCTAssertTrue(sut.hasMoreOlder)

        sync.olderPages = [(50..<70).map { remote("n\($0)", secondsAgo: TimeInterval($0 * 60)) }]
        await sut.loadOlder()
        XCTAssertEqual(sync.fetchBefore.first, currentTime.addingTimeInterval(-49 * 60), "en eski görünen mesajdan öncesi istenir")
        XCTAssertEqual(sut.messages.count, 70)
        XCTAssertEqual(sut.messages.first?.id, "n69")
        XCTAssertFalse(sut.hasMoreOlder, "sayfa dolmadı: sunucuda daha eski yok")

        await sut.loadOlder()
        XCTAssertEqual(sync.fetchBefore.count, 1, "tükenince yeniden istenmez")
    }

    func testSmallHistoryHasNoOlderPages() async {
        await configurePaired()
        sync.messagesHandler?([remote("r1")])
        XCTAssertFalse(sut.hasMoreOlder)
    }

    func testResetClearsState() async {
        await configurePaired()
        sync.messagesHandler?([remote("r1")])
        sut.reset()
        XCTAssertEqual(sut.phase, .idle)
        XCTAssertTrue(sut.messages.isEmpty)
        XCTAssertNil(sut.room)
        XCTAssertNil(sync.roomHandler, "dinleyici bırakılır")
    }
}
