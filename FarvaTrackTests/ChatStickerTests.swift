import XCTest
import SwiftData
import UIKit
@testable import FarvaTrack

// MARK: - Koordinat dönüşümü

final class PlacementGeometryTests: XCTestCase {
    /// Üç mesaj: 0–60, 80–120, 200–300 (sohbet içeriği koordinatları).
    private let frames: [String: CGRect] = [
        "a": CGRect(x: 12, y: 0, width: 200, height: 60),
        "b": CGRect(x: 150, y: 80, width: 220, height: 40),
        "c": CGRect(x: 12, y: 200, width: 260, height: 100)
    ]

    func testNearestAnchorPrefersContainingMessage() {
        XCTAssertEqual(PlacementGeometry.nearestAnchor(to: CGPoint(x: 50, y: 30), frames: frames), "a")
        XCTAssertEqual(PlacementGeometry.nearestAnchor(to: CGPoint(x: 300, y: 100), frames: frames), "b", "yatay konum önemsiz")
        XCTAssertEqual(PlacementGeometry.nearestAnchor(to: CGPoint(x: 0, y: 250), frames: frames), "c")
    }

    func testNearestAnchorBetweenAndOutsideMessages() {
        // Kenarlara eşit uzaklıkta (10 pt): dikey ortası daha yakın olan (b: 30 pt, a: 40 pt) seçilir.
        XCTAssertEqual(PlacementGeometry.nearestAnchor(to: CGPoint(x: 0, y: 70), frames: frames), "b")
        XCTAssertEqual(PlacementGeometry.nearestAnchor(to: CGPoint(x: 0, y: 130), frames: frames), "b", "b'ye 10, c'ye 70")
        XCTAssertEqual(PlacementGeometry.nearestAnchor(to: CGPoint(x: 0, y: 190), frames: frames), "c")
        XCTAssertEqual(PlacementGeometry.nearestAnchor(to: CGPoint(x: 0, y: -400), frames: frames), "a", "en üstün üstü")
        XCTAssertEqual(PlacementGeometry.nearestAnchor(to: CGPoint(x: 0, y: 900), frames: frames), "c", "en altın altı")
        XCTAssertNil(PlacementGeometry.nearestAnchor(to: .zero, frames: [:]))
    }

    func testAnchoredRoundTrip() throws {
        let width: CGFloat = 390
        let center = CGPoint(x: 312, y: 140)
        let anchored = try XCTUnwrap(PlacementGeometry.anchored(center: center, containerWidth: width, frames: frames))
        XCTAssertEqual(anchored.anchorID, "b")
        XCTAssertEqual(anchored.x, 0.8, accuracy: 0.0001)
        XCTAssertEqual(anchored.y, 40, "b'nin ortası 100, merkez 40 pt aşağıda")

        let restored = try XCTUnwrap(PlacementGeometry.center(x: anchored.x, y: anchored.y, anchorFrame: frames["b"], containerWidth: width))
        XCTAssertEqual(restored.x, center.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, center.y, accuracy: 0.001)
        XCTAssertNil(PlacementGeometry.anchored(center: center, containerWidth: 0, frames: frames))
    }

    func testPlacementFollowsMessageWhenLayoutShifts() throws {
        // Yeni mesajlar geldi / eski mesajlar yüklendi: bağlı mesaj 500 pt aşağı kaydı.
        let moved = frames["b"]!.offsetBy(dx: 0, dy: 500)
        let center = try XCTUnwrap(PlacementGeometry.center(x: 0.5, y: -30, anchorFrame: moved, containerWidth: 400))
        XCTAssertEqual(center, CGPoint(x: 200, y: moved.midY - 30), "mesajla birlikte hareket eder")
        XCTAssertNil(PlacementGeometry.center(x: 0.5, y: 0, anchorFrame: nil, containerWidth: 400), "mesaj ekranda yoksa çizilmez")
    }

    func testSamePlacementOnDifferentScreenWidths() throws {
        let small = try XCTUnwrap(PlacementGeometry.center(x: 0.25, y: 12, anchorFrame: CGRect(x: 0, y: 100, width: 300, height: 50), containerWidth: 320))
        let large = try XCTUnwrap(PlacementGeometry.center(x: 0.25, y: 12, anchorFrame: CGRect(x: 0, y: 100, width: 300, height: 50), containerWidth: 430))
        XCTAssertEqual(small.x / 320, large.x / 430, accuracy: 0.0001, "yatayda aynı oran")
        XCTAssertEqual(small.y, large.y)

        let smallSize = PlacementGeometry.displaySize(containerWidth: 320, scale: 1, aspectRatio: 2)
        let largeSize = PlacementGeometry.displaySize(containerWidth: 430, scale: 1, aspectRatio: 2)
        XCTAssertEqual(smallSize.width / 320, largeSize.width / 430, accuracy: 0.0001, "boyut da ekran genişliğine oranlı")
        XCTAssertEqual(smallSize.width, 320 * CGFloat(PlacementGeometry.baseWidthRatio), accuracy: 0.001)
        XCTAssertEqual(smallSize.height, smallSize.width / 2, accuracy: 0.001)
        XCTAssertEqual(PlacementGeometry.displaySize(containerWidth: 100, scale: 1, aspectRatio: 0).height, 32, "geçersiz oran kare sayılır")
    }

    func testClampsAndRotationNormalization() {
        XCTAssertEqual(PlacementGeometry.clampScale(10), 3)
        XCTAssertEqual(PlacementGeometry.clampScale(0.01), 0.3)
        XCTAssertEqual(PlacementGeometry.clampScale(.nan), 1)
        XCTAssertEqual(PlacementGeometry.clampX(1.7), 1)
        XCTAssertEqual(PlacementGeometry.clampX(-0.2), 0)
        XCTAssertEqual(PlacementGeometry.normalizedRotation(3 * .pi / 2), -.pi / 2, accuracy: 0.0001)
        XCTAssertEqual(PlacementGeometry.normalizedRotation(-3 * .pi / 2), .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(PlacementGeometry.normalizedRotation(4 * .pi + 0.1), 0.1, accuracy: 0.0001)
        XCTAssertEqual(PlacementGeometry.normalizedRotation(.infinity), 0)
    }

    func testTransformComposesGestures() {
        let start = PlacementTransform(center: CGPoint(x: 100, y: 100), scale: 1, rotation: 0)
        let moved = start.applying(translation: CGSize(width: 30, height: -20), magnification: 1.5, rotation: .pi / 4)
        XCTAssertEqual(moved.center, CGPoint(x: 130, y: 80))
        XCTAssertEqual(moved.scale, 1.5)
        XCTAssertEqual(moved.rotation, .pi / 4, accuracy: 0.0001)

        // Ardışık hareketler birikir ve sınırlanır.
        let huge = moved.applying(magnification: 4).applying(magnification: 4)
        XCTAssertEqual(huge.scale, 3)
        let spun = moved.applying(rotation: 2 * .pi)
        XCTAssertEqual(spun.rotation, .pi / 4, accuracy: 0.0001)
        XCTAssertEqual(start.applying(), start, "boş hareket hali değiştirmez")
    }

    func testVisibleCenterUsesScrollOffset() {
        let viewport = CGSize(width: 390, height: 600)
        XCTAssertEqual(PlacementGeometry.visibleCenter(contentMinY: 0, viewportSize: viewport), CGPoint(x: 195, y: 300))
        // 1000 pt aşağı kaydırılmış: içerik görünümün 1000 pt üstünden başlar.
        XCTAssertEqual(PlacementGeometry.visibleCenter(contentMinY: -1000, viewportSize: viewport), CGPoint(x: 195, y: 1300))
    }

    func testViewportToAnchorAndBackAfterScroll() throws {
        // Kullanıcı görünen bölgenin ortasına bırakır; başka bir kaydırma konumunda aynı mesajın yanında çizilir.
        let viewport = CGSize(width: 400, height: 700)
        let center = PlacementGeometry.visibleCenter(contentMinY: -150, viewportSize: viewport)  // (200, 500)
        let messageFrames = ["m1": CGRect(x: 0, y: 420, width: 300, height: 60), "m2": CGRect(x: 0, y: 700, width: 300, height: 60)]
        let anchored = try XCTUnwrap(PlacementGeometry.anchored(center: center, containerWidth: viewport.width, frames: messageFrames))
        XCTAssertEqual(anchored.anchorID, "m1")
        XCTAssertEqual(anchored.y, 50)
        // İçerik koordinatları kaydırmadan bağımsızdır: aynı çerçeveden aynı merkez.
        XCTAssertEqual(PlacementGeometry.center(x: anchored.x, y: anchored.y, anchorFrame: messageFrames["m1"], containerWidth: 400), center)
    }
}

// MARK: - Modeller

final class ChatStickerModelTests: XCTestCase {
    func testStickerFieldsAndPaths() {
        let sticker = ChatSticker(path: ChatStickerPath.file(chatID: "a_b", itemID: "m1"), width: 400, height: 200)
        XCTAssertEqual(sticker.path, "chats/a_b/media/m1/sticker.png")
        XCTAssertEqual(sticker.aspectRatio, 2)
        XCTAssertEqual(ChatStickerFields.decode(ChatStickerFields.encode(sticker)), sticker)
        XCTAssertNil(ChatStickerFields.decode(["width": 3]))
        XCTAssertTrue(ChatMessageType.sendable.contains(.sticker))
    }

    func testPlacementFieldsRoundTripAndSanitize() throws {
        let date = Date(timeIntervalSince1970: 5_000)
        let placement = ChatPlacementDTO(
            id: "p1", senderID: "me", anchorMessageID: "m9", x: 0.3, y: -42.5, scale: 1.4, rotation: 0.7, z: 12,
            sticker: ChatSticker(path: "chats/a_b/media/p1/sticker.png", width: 300, height: 300),
            createdAt: date, updatedAt: date
        )
        let fields = ChatPlacementFields.encode(placement)
        XCTAssertEqual(ChatPlacementFields.decode(id: "p1", data: fields, createdAt: date, updatedAt: date), placement)

        var bad = fields
        bad["x"] = NSNumber(value: 4)
        bad["scale"] = NSNumber(value: 99)
        bad["rotation"] = NSNumber(value: 7)
        bad.removeValue(forKey: "z")
        let sanitized = try XCTUnwrap(ChatPlacementFields.decode(id: "p1", data: bad, createdAt: date, updatedAt: date))
        XCTAssertEqual(sanitized.x, 1)
        XCTAssertEqual(sanitized.scale, 3)
        XCTAssertEqual(sanitized.rotation, 7 - 2 * .pi, accuracy: 0.0001)
        XCTAssertEqual(sanitized.z, 5_000, "eski kayıtta katman sırası oluşturulma zamanı")
        XCTAssertNil(ChatPlacementFields.decode(id: "p1", data: ["x": 1], createdAt: date, updatedAt: date))
    }

    func testRecentsOrderLimitAndFiltering() {
        let recents = StickerRecents(defaults: makeTestDefaults(), userID: "me")
        recents.use("a")
        recents.use("b")
        recents.use("a")
        XCTAssertEqual(recents.ids, ["a", "b"], "son kullanılan başa geçer, tekrar etmez")
        for index in 0..<30 { recents.use("s\(index)") }
        XCTAssertEqual(recents.ids.count, StickerRecents.limit)
        XCTAssertEqual(recents.ids.first, "s29")

        let library = [StickerItem(id: "s29", fileURL: URL(fileURLWithPath: "/a"), width: 1, height: 1, isSynced: true),
                       StickerItem(id: "s20", fileURL: URL(fileURLWithPath: "/b"), width: 1, height: 1, isSynced: true)]
        XCTAssertEqual(recents.items(from: library).map(\.id), ["s29", "s20"], "kütüphaneden silinenler düşer")
        recents.remove("s29")
        XCTAssertEqual(recents.items(from: library).map(\.id), ["s20"])
        recents.clear()
        XCTAssertTrue(recents.ids.isEmpty)
    }
}

// MARK: - ViewModel

@MainActor
final class ChatStickerViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockChatSync!
    private var store: MockMediaStore!
    private var files: ChatMediaFiles!
    private var root: URL!
    private var sut: ChatViewModel!
    private var counter = 0
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let me = AppUser.makeNew(id: "me", email: "ben@ornek.com", displayName: "Ben")
    private var roomID: String { ChatID.make("me", "friend") }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: ChatMessageRecord.self, ChatPendingOperation.self, ChatPlacementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        sync = MockChatSync()
        store = MockMediaStore()
        root = makeTemporaryDirectory()
        files = ChatMediaFiles(persistentRoot: root.appendingPathComponent("support"), cacheRoot: root.appendingPathComponent("caches"))
        counter = 0
        sut = ChatViewModel(
            sync: sync, mediaStore: store, processor: MockMediaProcessor(), files: files,
            defaults: makeTestDefaults("sticker.\(name)"),
            clock: { [unowned self] in self.now },
            makeID: { [unowned self] in
                self.counter += 1
                return "id-\(self.counter)"
            }
        )
        sut.configure(context: container.mainContext, user: me)
        sync.roomHandler?(ChatRoomDTO(id: roomID, members: ChatID.sortedMembers("me", "friend"), names: ["friend": "Elif"], createdAt: now), false)
        await settle()
    }

    override func tearDown() async throws {
        await settleTasks()
        sut.reset()
        await settleTasks()
        sut = nil
        container = nil
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func settle() async {
        for _ in 0..<3 {
            await settleTasks()
            await sut.flushOutbox()
            await sut.syncPlacements()
        }
    }

    private func png() throws -> URL {
        let url = root.appendingPathComponent("\(UUID().uuidString).png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 4)).pngData { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        }
        try image.write(to: url)
        return url
    }

    private func item(_ id: String) -> ChatMessageItem? { sut.messages.first { $0.id == id } }

    // MARK: Sticker mesajı

    func testStickerIsUploadedThenSentAsMessage() async throws {
        var uploadsAtSend: [String] = []
        sync.onSend = { [unowned self] _ in uploadsAtSend = self.store.uploads.map(\.path) }
        let source = try png()

        sut.sendSticker(fileURL: source, width: 512, height: 256)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "kütüphanedeki asıl dosya yerinde kalır")
        XCTAssertEqual(item("id-1")?.message.type, .sticker)
        XCTAssertEqual(item("id-1")?.status, .sending)
        XCTAssertEqual(item("id-1")?.displayText, "Sticker")

        await settle()
        let path = ChatStickerPath.file(chatID: roomID, itemID: "id-1")
        XCTAssertEqual(uploadsAtSend, [path], "dosya mesajdan önce yüklenir")
        XCTAssertEqual(store.uploads.first?.contentType, "image/png")
        XCTAssertEqual(sync.sent.first?.sticker, ChatSticker(path: path, width: 512, height: 256))
        XCTAssertEqual(item("id-1")?.status, .delivered)
        let local = try XCTUnwrap(item("id-1")?.localOriginalURL)
        XCTAssertEqual(local.pathExtension, "png")
        let loaded = try await sut.loadAttachment(for: item("id-1")!)
        XCTAssertEqual(loaded, local)
        XCTAssertTrue(store.downloads.isEmpty)
    }

    func testReceivedStickerCanBeSavedToLibrary() async throws {
        let path = ChatStickerPath.file(chatID: roomID, itemID: "r1")
        sync.messagesHandler?([ChatMessageDTO(id: "r1", senderID: "friend", type: .sticker, text: "", createdAt: now,
                                              sticker: ChatSticker(path: path, width: 300, height: 200))])
        let incoming = try XCTUnwrap(item("r1"))
        XCTAssertNil(incoming.localOriginalURL)

        let url = try await sut.loadAttachment(for: incoming)
        XCTAssertEqual(store.downloads, [path])
        // İndirilen dosyayı gerçek bir PNG ile değiştir (sahte depo düz metin yazar).
        try Data(contentsOf: try png()).write(to: url)

        let stickerContainer = try ModelContainer(for: StickerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let library = StickerLibraryViewModel(sync: MockStickerSync(), files: StickerFiles(root: root.appendingPathComponent("library")),
                                              defaults: makeTestDefaults("lib.\(name)"))
        library.configure(context: stickerContainer.mainContext, userID: "me")
        try library.addPNG(at: url, width: 300, height: 200)
        XCTAssertEqual(library.stickers.count, 1)
        XCTAssertEqual(library.stickers.first?.width, 300)

        let notPNG = root.appendingPathComponent("x.png")
        try Data("değil".utf8).write(to: notPNG)
        XCTAssertThrowsError(try library.addPNG(at: notPNG, width: 1, height: 1))
        await library.waitForPendingSync()
        await settleTasks()
        _ = stickerContainer
    }

    func testDeleteStickerForEveryoneRemovesFile() async throws {
        sut.sendSticker(fileURL: try png(), width: 10, height: 10)
        await settle()
        sut.deleteForEveryone(item("id-1")!)
        await settle()
        XCTAssertEqual(store.deletedPaths, [ChatStickerPath.file(chatID: roomID, itemID: "id-1")])
        XCTAssertNil(item("id-1")?.message.sticker)
    }

    // MARK: Yerleştirme

    func testPlaceUploadsPNGThenSavesPlacement() async throws {
        let id = try XCTUnwrap(sut.placeSticker(fileURL: try png(), width: 400, height: 200, anchorMessageID: "m1",
                                                x: 0.42, y: -18, scale: 1.6, rotation: 0.3))
        XCTAssertEqual(sut.placements.map(\.id), [id])
        XCTAssertTrue(sut.placements[0].isMine)
        XCTAssertTrue(sut.placements[0].isSyncing)
        XCTAssertNotNil(sut.placements[0].localImageURL, "yerleştiren hemen görür")

        await settle()
        XCTAssertEqual(store.uploads.map(\.path), [ChatStickerPath.file(chatID: roomID, itemID: id)])
        let saved = try XCTUnwrap(sync.savedPlacements.last)
        XCTAssertEqual(saved.anchorMessageID, "m1")
        XCTAssertEqual(saved.x, 0.42)
        XCTAssertEqual(saved.y, -18)
        XCTAssertEqual(saved.scale, 1.6)
        XCTAssertEqual(saved.rotation, 0.3)
        XCTAssertEqual(saved.senderID, "me")
        XCTAssertFalse(sut.placements[0].isSyncing)
        XCTAssertNotNil(sut.placements[0].localImageURL, "yüklemeden sonra önbellekten")
    }

    func testOfflinePlacementIsKeptAndSyncedLater() async throws {
        sync.isOffline = true
        sut.placeSticker(fileURL: try png(), width: 10, height: 10, anchorMessageID: "m1", x: 0.5, y: 0, scale: 1, rotation: 0)
        await settle()
        XCTAssertTrue(sync.savedPlacements.isEmpty)
        XCTAssertTrue(sut.placements[0].isSyncing)

        // Sunucudan boş liste gelse de bekleyen yerel yerleştirme kaybolmaz.
        sync.placementsHandler?([], false)
        XCTAssertEqual(sut.placements.count, 1)

        sync.isOffline = false
        await sut.handleForeground()
        XCTAssertEqual(sync.savedPlacements.count, 1)
        XCTAssertEqual(store.uploads.count, 1, "dosya bir kez yüklenir")
    }

    func testOnlyOwnerCanMoveReorderAndDelete() async throws {
        let theirs = ChatPlacementDTO(id: "p-friend", senderID: "friend", anchorMessageID: "m1", x: 0.2, y: 5, scale: 1, rotation: 0, z: 10,
                                      sticker: ChatSticker(path: ChatStickerPath.file(chatID: roomID, itemID: "p-friend"), width: 5, height: 5),
                                      createdAt: now, updatedAt: now)
        sync.placementsHandler?([theirs], false)
        XCTAssertFalse(sut.placements[0].isMine)

        sut.movePlacement("p-friend", anchorMessageID: "m2", x: 0.9, y: 0, scale: 2, rotation: 1)
        sut.reorderPlacement("p-friend", toFront: true)
        sut.deletePlacement("p-friend")
        await settle()
        XCTAssertEqual(sut.placements.first?.placement, theirs, "başkasının sticker'ı değişmez")
        XCTAssertTrue(sync.savedPlacements.isEmpty)
        XCTAssertTrue(sync.deletedPlacements.isEmpty)
    }

    func testOwnerMovesAndReordersPlacement() async throws {
        let first = try XCTUnwrap(sut.placeSticker(fileURL: try png(), width: 10, height: 10, anchorMessageID: "m1", x: 0.5, y: 0, scale: 1, rotation: 0))
        now = now.addingTimeInterval(5)
        let second = try XCTUnwrap(sut.placeSticker(fileURL: try png(), width: 10, height: 10, anchorMessageID: "m1", x: 0.5, y: 0, scale: 1, rotation: 0))
        await settle()
        XCTAssertEqual(sut.placements.map(\.id), [first, second], "yeni olan üstte")

        sut.reorderPlacement(first, toFront: true)
        XCTAssertEqual(sut.placements.map(\.id), [second, first])
        sut.reorderPlacement(first, toFront: false)
        XCTAssertEqual(sut.placements.map(\.id), [first, second])

        sut.movePlacement(second, anchorMessageID: "m7", x: 2, y: 33, scale: 9, rotation: 4 * .pi)
        await settle()
        let moved = try XCTUnwrap(sync.savedPlacements.last { $0.id == second })
        XCTAssertEqual(moved.anchorMessageID, "m7")
        XCTAssertEqual(moved.x, 1)
        XCTAssertEqual(moved.scale, 3)
        XCTAssertEqual(moved.rotation, 0, accuracy: 0.0001)
        XCTAssertEqual(store.uploads.count, 2, "taşımak dosyayı yeniden yüklemez")
    }

    func testOwnerDeletesPlacementOnServerAndStorage() async throws {
        let id = try XCTUnwrap(sut.placeSticker(fileURL: try png(), width: 10, height: 10, anchorMessageID: "m1", x: 0.5, y: 0, scale: 1, rotation: 0))
        await settle()
        sut.deletePlacement(id)
        XCTAssertTrue(sut.placements.isEmpty, "hemen kaybolur")
        await settle()
        XCTAssertEqual(sync.deletedPlacements, [id])
        XCTAssertEqual(store.deletedPaths, [ChatStickerPath.file(chatID: roomID, itemID: id)])
    }

    func testDeletingUnsentPlacementNeedsNoServerCall() async throws {
        sync.isOffline = true
        let id = try XCTUnwrap(sut.placeSticker(fileURL: try png(), width: 10, height: 10, anchorMessageID: "m1", x: 0.5, y: 0, scale: 1, rotation: 0))
        sut.deletePlacement(id)
        sync.isOffline = false
        await settle()
        XCTAssertTrue(sync.deletedPlacements.isEmpty)
        XCTAssertTrue(sync.savedPlacements.isEmpty)
        XCTAssertTrue(sut.placements.isEmpty)
    }

    func testRemotePlacementsAreCachedUpdatedAndRemoved() async throws {
        var placement = ChatPlacementDTO(id: "p1", senderID: "friend", anchorMessageID: "m1", x: 0.2, y: 5, scale: 1, rotation: 0, z: 1,
                                         sticker: ChatSticker(path: ChatStickerPath.file(chatID: roomID, itemID: "p1"), width: 5, height: 5),
                                         createdAt: now, updatedAt: now)
        sync.placementsHandler?([placement], false)
        XCTAssertNil(sut.placements[0].localImageURL)
        let url = await sut.loadPlacementImage(sut.placements[0])
        XCTAssertNotNil(url)
        XCTAssertNotNil(sut.placements[0].localImageURL)

        placement.x = 0.7
        sync.placementsHandler?([placement], false)
        XCTAssertEqual(sut.placements[0].placement.x, 0.7, "karşı taraf taşıyınca güncellenir")

        // Önbellekten gelen boş sonuç silme sayılmaz; sunucudan gelen sayılır.
        sync.placementsHandler?([], true)
        XCTAssertEqual(sut.placements.count, 1)
        sync.placementsHandler?([], false)
        XCTAssertTrue(sut.placements.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url?.path ?? "/yok"), "indirilen kopya silinir")
    }

    func testPendingLocalMoveWinsOverStaleSnapshot() async throws {
        let id = try XCTUnwrap(sut.placeSticker(fileURL: try png(), width: 10, height: 10, anchorMessageID: "m1", x: 0.5, y: 0, scale: 1, rotation: 0))
        await settle()
        let server = try XCTUnwrap(sync.savedPlacements.last)
        sync.isOffline = true
        sut.movePlacement(id, anchorMessageID: "m2", x: 0.1, y: 10, scale: 2, rotation: 0)
        await settle()
        sync.placementsHandler?([server], false)
        XCTAssertEqual(sut.placements[0].placement.anchorMessageID, "m2", "bekleyen yerel değişiklik kazanır")
        XCTAssertEqual(sut.placements[0].placement.x, 0.1)
    }
}
