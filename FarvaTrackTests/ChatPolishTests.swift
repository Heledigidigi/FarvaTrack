import XCTest
import SwiftData
@testable import FarvaTrack

// MARK: - Profil fotoğrafı hizalama

final class AvatarCropGeometryTests: XCTestCase {
    private let landscape = AvatarCropGeometry(imageSize: CGSize(width: 4000, height: 3000), diameter: 300)

    func testBaseScaleFillsCircleWithShortSide() {
        XCTAssertEqual(landscape.baseScale, 0.1, accuracy: 1e-9)
        let size = landscape.displaySize(zoom: 1)
        XCTAssertEqual(size.height, 300, accuracy: 1e-9, "kısa kenar dairenin çapına eşit")
        XCTAssertEqual(size.width, 400, accuracy: 1e-9)
    }

    func testOffsetCannotRevealOutsideOfImage() {
        // Yatay fotoğrafta 1x'te yalnızca yatayda 50 pt kayma payı var.
        let clamped = landscape.clampedOffset(CGSize(width: 500, height: 80), zoom: 1)
        XCTAssertEqual(clamped.width, 50, accuracy: 1e-9)
        XCTAssertEqual(clamped.height, 0, accuracy: 1e-9)
        let zoomed = landscape.clampedOffset(CGSize(width: -1000, height: -1000), zoom: 2)
        XCTAssertEqual(zoomed.width, -250, accuracy: 1e-9)
        XCTAssertEqual(zoomed.height, -150, accuracy: 1e-9)
    }

    func testCropRectFollowsZoomAndOffset() {
        let centered = landscape.cropRect(zoom: 1, offset: .zero)
        XCTAssertEqual(centered.width, 3000, accuracy: 1e-6)
        XCTAssertEqual(centered.midX, 2000, accuracy: 1e-6)
        XCTAssertEqual(centered.midY, 1500, accuracy: 1e-6)

        // Fotoğraf sağa kaydırılınca daire fotoğrafın sol kısmını görür.
        let shifted = landscape.cropRect(zoom: 1, offset: CGSize(width: 50, height: 0))
        XCTAssertEqual(shifted.minX, 0, accuracy: 1e-6)

        let zoomed = landscape.cropRect(zoom: 2, offset: .zero)
        XCTAssertEqual(zoomed.width, 1500, accuracy: 1e-6, "2x'te yarı boy bölge")
        XCTAssertEqual(zoomed.midX, 2000, accuracy: 1e-6)
    }

    func testZoomClampsAndPinchKeepsAnchorStill() {
        XCTAssertEqual(AvatarCropGeometry.clampZoom(0.2), 1)
        XCTAssertEqual(AvatarCropGeometry.clampZoom(100), AvatarCropGeometry.maxZoom)
        // Merkezden büyütmede kaydırma değişmez.
        let still = landscape.offset(afterZoomingFrom: 1, to: 2, offset: .zero, anchor: .zero)
        XCTAssertEqual(still, .zero)
        // Sağdaki bir noktadan büyütünce görüntü o noktaya doğru kayar (sola itilir).
        let anchored = landscape.offset(afterZoomingFrom: 1, to: 2, offset: .zero, anchor: CGPoint(x: 100, y: 0))
        XCTAssertEqual(anchored.width, -100, accuracy: 1e-9)
    }

    func testRendererProducesSquareJPEG() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        }
        let data = try XCTUnwrap(ProfilePhotoRenderer.jpeg(from: image, crop: CGRect(x: 0, y: 0, width: 20, height: 20)))
        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(decoded.size.width * decoded.scale, ProfilePhotoRenderer.side, accuracy: 0.5)
        XCTAssertEqual(decoded.size.height * decoded.scale, ProfilePhotoRenderer.side, accuracy: 0.5)
    }
}

// MARK: - Çevrimiçi / son görülme

final class ChatPresenceTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()
    /// 2026-11-28 17:00 İstanbul.
    private let now = Date(timeIntervalSince1970: 1_795_874_400)

    func testOnlineOnlyWhileHeartbeatIsFresh() {
        XCTAssertEqual(ChatPresenceStatus.of(ChatPresence(online: true, at: now.addingTimeInterval(-30)), now: now), .online)
        let stale = ChatPresence(online: true, at: now.addingTimeInterval(-ChatPresence.staleAfter - 1))
        XCTAssertEqual(ChatPresenceStatus.of(stale, now: now), .lastSeen(stale.at), "sinyal kesildiyse son görülme")
        XCTAssertEqual(ChatPresenceStatus.of(nil, now: now), .unknown)
        XCTAssertNil(ChatPresenceStatus.unknown.text(now: now))
        XCTAssertEqual(ChatPresenceStatus.online.text(now: now), "çevrimiçi")
    }

    func testLastSeenTexts() {
        XCTAssertEqual(ChatPresenceStatus.lastSeen(now.addingTimeInterval(-20)).text(now: now, calendar: calendar), "son görülme az önce")
        let today = ChatPresenceStatus.lastSeen(now.addingTimeInterval(-2 * 3600)).text(now: now, calendar: calendar) ?? ""
        XCTAssertTrue(today.hasPrefix("son görülme bugün "), today)
        let yesterday = ChatPresenceStatus.lastSeen(now.addingTimeInterval(-20 * 3600)).text(now: now, calendar: calendar) ?? ""
        XCTAssertTrue(yesterday.hasPrefix("son görülme dün "), yesterday)
        let older = ChatPresenceStatus.lastSeen(now.addingTimeInterval(-6 * 86_400)).text(now: now, calendar: calendar) ?? ""
        XCTAssertTrue(older.hasPrefix("son görülme "), older)
        XCTAssertFalse(older.contains("dün") || older.contains("bugün"), older)
    }

    func testOldCachedRoomWithoutNewFieldsStillDecodes() throws {
        let json = #"{"id":"a_b","members":["a","b"],"names":{"a":"Ali"},"createdAt":0,"typing":{}}"#
        let room = try JSONDecoder().decode(ChatRoomDTO.self, from: Data(json.utf8))
        XCTAssertEqual(room.photos, [:])
        XCTAssertEqual(room.presence, [:])

        var updated = room
        updated.photos = ["b": "  https://ornek.com/p.jpg ", "a": "  "]
        updated.presence = ["b": ChatPresence(online: true, at: Date(timeIntervalSince1970: 10))]
        let roundTrip = try JSONDecoder().decode(ChatRoomDTO.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(roundTrip, updated)
        XCTAssertEqual(roundTrip.photoURL(of: "b"), "https://ornek.com/p.jpg")
        XCTAssertNil(roundTrip.photoURL(of: "a"), "boş adres fotoğraf sayılmaz")
    }
}

// MARK: - Mesaj bilgisi, bul, kaydırma, paneller

final class ChatMessageInfoTests: XCTestCase {
    private let sent = Date(timeIntervalSince1970: 1_800_000_000)

    func testMineShowsSentDeliveredRead() {
        var message = ChatMessageDTO(id: "m", senderID: "me", type: .audio, text: "", createdAt: sent)
        var info = ChatMessageInfo(message: message, isMine: true, isSending: false)
        XCTAssertEqual(info.rows.map(\.title), ["Gönderildi", "İletildi", "Görüldü", "Dinlendi"])
        XCTAssertEqual(info.rows[0].date, sent)
        XCTAssertNil(info.rows[1].date)

        // Eski sürümde iletildi bilgisi yoksa okunma zamanı kullanılır.
        message.readAt = sent.addingTimeInterval(60)
        info = ChatMessageInfo(message: message, isMine: true, isSending: false)
        XCTAssertEqual(info.rows[1].date, message.readAt)
        message.deliveredAt = sent.addingTimeInterval(5)
        info = ChatMessageInfo(message: message, isMine: true, isSending: false)
        XCTAssertEqual(info.rows[1].date, message.deliveredAt)

        XCTAssertNil(ChatMessageInfo(message: message, isMine: true, isSending: true).rows[0].date, "gönderilirken saat yok")
    }

    func testIncomingShowsSentAndSeenByMe() {
        let message = ChatMessageDTO(id: "m", senderID: "friend", text: "selam", createdAt: sent)
        let info = ChatMessageInfo(message: message, isMine: false, isSending: false)
        XCTAssertEqual(info.rows.map(\.title), ["Gönderildi", "Sende görüldü"])
    }
}

final class ChatFindStateTests: XCTestCase {
    func testStartsAtNewestAndMovesBothWays() {
        var state = ChatFindState()
        state.update(matches: ["a", "b", "c"])
        XCTAssertEqual(state.current, "c")
        XCTAssertEqual(state.positionText, "1/3")
        XCTAssertFalse(state.canGoNewer)
        XCTAssertEqual(state.older(), "b")
        XCTAssertEqual(state.older(), "a")
        XCTAssertNil(state.older(), "en eskiden öteye gidilmez")
        XCTAssertEqual(state.current, "a")
        XCTAssertEqual(state.positionText, "3/3")
        XCTAssertEqual(state.newer(), "b")
    }

    func testKeepsSelectionWhenResultsChange() {
        var state = ChatFindState()
        state.update(matches: ["a", "b", "c"])
        state.older()
        state.update(matches: ["a", "b", "c", "d"])
        XCTAssertEqual(state.current, "b", "yeni mesaj gelince seçim korunur")
        state.update(matches: ["x"])
        XCTAssertEqual(state.current, "x")
        state.update(matches: [])
        XCTAssertNil(state.current)
        XCTAssertEqual(state.positionText, "0/0")
    }
}

final class ChatLayoutHelperTests: XCTestCase {
    func testTimeRevealFollowsFingerThenResists() {
        XCTAssertEqual(ChatTimeReveal.offset(forTranslation: 30), 0, "sağa çekmek bir şey yapmaz")
        XCTAssertEqual(ChatTimeReveal.offset(forTranslation: -40), -40)
        XCTAssertEqual(ChatTimeReveal.offset(forTranslation: -164), -ChatTimeReveal.width - 20, accuracy: 1e-9)
        XCTAssertEqual(ChatTimeReveal.progress(0), 0)
        XCTAssertEqual(ChatTimeReveal.progress(-ChatTimeReveal.width), 1)
    }

    func testComposerLiftNeverMovesWhenSwitchingBetweenKeyboardAndPanel() {
        // Klavye açık → panele geçiş: klavye inerken (336 → 0) yazma alanı hep 336'da.
        for overlap in stride(from: CGFloat(336), through: 0, by: -48) {
            XCTAssertEqual(ChatPanelLayout.lift(panel: .stickers, keyboardHeight: 336, keyboardOverlap: overlap, homeInset: 34), 336)
        }
        // Panelden klavyeye: klavye çıkarken de aynı.
        XCTAssertEqual(ChatPanelLayout.lift(panel: .gallery, keyboardHeight: 336, keyboardOverlap: 120, homeInset: 34), 336)
        // Hiçbiri yoksa ev çubuğunun üstü; parmakla kapatırken klavyeyi izler.
        XCTAssertEqual(ChatPanelLayout.lift(panel: .none, keyboardHeight: 336, keyboardOverlap: 0, homeInset: 34), 34)
        XCTAssertEqual(ChatPanelLayout.lift(panel: .none, keyboardHeight: 336, keyboardOverlap: 200, homeInset: 34), 200)
    }

    func testSwipeReplyDirectionAndThreshold() {
        XCTAssertEqual(ChatSwipeReply.offset(forTranslation: 40, isMine: true), 0, "kendi mesajı sağa çekilmez")
        XCTAssertEqual(ChatSwipeReply.offset(forTranslation: -40, isMine: true), -40)
        XCTAssertEqual(ChatSwipeReply.offset(forTranslation: -40, isMine: false), 0, "karşı tarafınki sola çekilmez")
        XCTAssertEqual(ChatSwipeReply.offset(forTranslation: 40, isMine: false), 40)
        XCTAssertFalse(ChatSwipeReply.isTriggered(40))
        let far = ChatSwipeReply.offset(forTranslation: 400, isMine: false)
        XCTAssertEqual(far, ChatSwipeReply.maximum)
        XCTAssertTrue(ChatSwipeReply.isTriggered(far))
        XCTAssertTrue(ChatSwipeReply.isTriggered(ChatSwipeReply.offset(forTranslation: -70, isMine: true)))
    }

    func testCaptionSummary() {
        let photo = ChatMessageDTO(id: "p", senderID: "a", type: .image, text: "  deniz  ", createdAt: .now)
        XCTAssertEqual(ChatText.summary(of: photo), "📷 deniz")
        var plain = photo
        plain.text = ""
        XCTAssertEqual(ChatText.summary(of: plain), ChatMessageType.image.placeholder)
        XCTAssertEqual(ChatReplyReference.make(from: photo).preview, "📷 deniz")
    }

    func testGallerySnapping() {
        XCTAssertEqual(ChatPanelLayout.gallerySnap(height: 300, predictedHeight: 700, collapsed: 336, expanded: 780), .expanded)
        XCTAssertEqual(ChatPanelLayout.gallerySnap(height: 340, predictedHeight: 380, collapsed: 336, expanded: 780), .collapsed)
        XCTAssertEqual(ChatPanelLayout.gallerySnap(height: 200, predictedHeight: 120, collapsed: 336, expanded: 780), .closed)
    }
}

// MARK: - ViewModel: fotoğraf, çevrimiçi, iletildi, bul

@MainActor
final class ChatPolishViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockChatSync!
    private var defaults: UserDefaults!
    private var sut: ChatViewModel!
    private var currentTime = Date(timeIntervalSince1970: 1_800_000_000)
    private var idCounter = 0
    private var me: AppUser = {
        var user = AppUser.makeNew(id: "me", email: "ben@ornek.com", displayName: "Ben")
        user.photoURL = "https://medya.ornek.com/v1/public/profile_images/me/a.jpg"
        return user
    }()
    private var room: ChatRoomDTO {
        ChatRoomDTO(id: ChatID.make("me", "friend"), members: ChatID.sortedMembers("me", "friend"),
                    names: ["me": "Ben", "friend": "Elif"], createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: ChatMessageRecord.self, ChatPendingOperation.self, ChatPlacementRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sync = MockChatSync()
        defaults = makeTestDefaults("chatpolish.\(name)")
        idCounter = 0
        sut = ChatViewModel(sync: sync, defaults: defaults, clock: { [unowned self] in self.currentTime },
                            makeID: { [unowned self] in
                                self.idCounter += 1
                                return "local-\(self.idCounter)"
                            })
    }

    override func tearDown() async throws {
        await settleTasks()
        sut.reset()
        await settleTasks()
        sut = nil
        sync = nil
        container = nil
        try await super.tearDown()
    }

    private func pair(_ room: ChatRoomDTO? = nil) async {
        sut.configure(context: container.mainContext, user: me)
        sync.roomHandler?(room ?? self.room, false)
        await settleTasks()
    }

    func testMyPhotoIsWrittenToRoomOnceAndPartnerPhotoIsRead() async {
        await pair()
        XCTAssertEqual(sync.photoUpdates, [me.photoURL], "karşı taraf görebilsin diye odaya yazılır")

        // Oda güncellemesi fotoğrafla gelince bir daha yazılmaz.
        var updated = room
        updated.photos = ["me": me.photoURL!, "friend": "https://medya.ornek.com/f.jpg"]
        sync.roomHandler?(updated, false)
        await settleTasks()
        XCTAssertEqual(sync.photoUpdates.count, 1)
        XCTAssertEqual(sut.partnerPhotoURL, "https://medya.ornek.com/f.jpg")

        // Fotoğrafı kaldırınca odadan da silinir.
        me.photoURL = nil
        sut.configure(context: container.mainContext, user: me)
        await settleTasks()
        XCTAssertEqual(sync.photoUpdates.last, .some(nil))
    }

    func testPartnerPresenceAndSubtitle() async {
        var updated = room
        updated.presence = ["friend": ChatPresence(online: true, at: currentTime.addingTimeInterval(-10))]
        await pair(updated)
        XCTAssertEqual(sut.partnerPresence, .online)
        XCTAssertEqual(sut.partnerSubtitle, "çevrimiçi")

        currentTime = currentTime.addingTimeInterval(ChatPresence.staleAfter + 5)
        sut.tick()
        XCTAssertEqual(sut.partnerPresence, .lastSeen(currentTime.addingTimeInterval(-ChatPresence.staleAfter - 15)))

        let wrote = await sut.updatePresence(online: false)
        XCTAssertTrue(wrote)
        XCTAssertEqual(sync.presences.last?.online, false)
        XCTAssertEqual(sync.presences.last?.at, currentTime)
    }

    func testIncomingMessagesAreMarkedDeliveredOnce() async {
        await pair()
        let incoming = ChatMessageDTO(id: "r1", senderID: "friend", text: "selam", createdAt: currentTime)
        let alreadyRead = ChatMessageDTO(id: "r2", senderID: "friend", text: "ok", createdAt: currentTime, readAt: currentTime)
        sync.messagesHandler?([incoming, alreadyRead])
        await settleTasks()
        sync.messagesHandler?([incoming, alreadyRead])
        await settleTasks()
        XCTAssertEqual(sync.deliveries, [["r1"]], "okunmuş olan ve ikinci kez gelen yazılmaz")

        // Çevrimdışıyken başarısız olursa sonraki güncellemede yeniden denenir.
        sync.isOffline = true
        let second = ChatMessageDTO(id: "r3", senderID: "friend", text: "?", createdAt: currentTime)
        sync.messagesHandler?([second])
        await settleTasks()
        sync.isOffline = false
        sync.messagesHandler?([second])
        await settleTasks()
        XCTAssertEqual(sync.deliveries.last, ["r3"])
    }

    func testFindWalksMatchesChronologically() async {
        await pair()
        sync.messagesHandler?([
            ChatMessageDTO(id: "a", senderID: "friend", text: "Akşam spor var mı", createdAt: currentTime.addingTimeInterval(-300)),
            ChatMessageDTO(id: "b", senderID: "me", text: "Bugün yorgunum", createdAt: currentTime.addingTimeInterval(-200)),
            ChatMessageDTO(id: "c", senderID: "friend", text: "Yarın spora gidelim", createdAt: currentTime.addingTimeInterval(-100))
        ])
        await settleTasks()

        sut.beginFind()
        XCTAssertTrue(sut.isFinding)
        sut.findQuery = "spor"
        XCTAssertEqual(sut.find.count, 2)
        XCTAssertEqual(sut.find.current, "c", "en yeni eşleşmeden başlar")
        XCTAssertEqual(sut.findOlder(), "a")
        XCTAssertNil(sut.findOlder())
        XCTAssertEqual(sut.findNewer(), "c")

        // Yazım hatasına dayanıklı ölçüt aynı.
        sut.findQuery = "yorgnum"
        XCTAssertEqual(sut.find.current, "b")

        sut.endFind()
        XCTAssertFalse(sut.isFinding)
        XCTAssertEqual(sut.find.count, 0)
        XCTAssertEqual(sut.findQuery, "")
    }

    func testReplyFromViewerQuotesThePhotoWithoutTouchingDraft() async {
        await pair()
        let photo = ChatMessageDTO(id: "p1", senderID: "friend", type: .image, text: "", createdAt: currentTime)
        sync.messagesHandler?([photo])
        await settleTasks()
        sut.draft = "yarım kalan"
        guard let item = sut.messages.first(where: { $0.id == "p1" }) else { return XCTFail("fotoğraf yok") }
        XCTAssertTrue(sut.sendReply("çok güzel", to: item))
        XCTAssertFalse(sut.sendReply("   ", to: item))
        await settleTasks()
        await sut.flushOutbox()
        XCTAssertEqual(sync.sent.last?.text, "çok güzel")
        XCTAssertEqual(sync.sent.last?.replyTo?.messageID, "p1")
        XCTAssertEqual(sut.draft, "yarım kalan")
    }

    func testInfoUsesLatestMessageState() async {
        await pair()
        let mine = ChatMessageDTO(id: "m1", senderID: "me", text: "selam", createdAt: currentTime)
        sync.messagesHandler?([mine])
        await settleTasks()
        let item = try? XCTUnwrap(sut.messages.first { $0.id == "m1" })
        var read = mine
        read.readAt = currentTime.addingTimeInterval(30)
        read.deliveredAt = currentTime.addingTimeInterval(2)
        sync.messagesHandler?([read])
        await settleTasks()
        guard let item else { return }
        let info = sut.info(for: item)
        XCTAssertEqual(info.rows.first { $0.title == "Görüldü" }?.date, read.readAt)
        XCTAssertEqual(info.rows.first { $0.title == "İletildi" }?.date, read.deliveredAt)
    }
}
