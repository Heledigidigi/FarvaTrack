import XCTest
import SwiftData
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import FarvaTrack

// MARK: - Sahte Storage ve işlemci

final class MockMediaStore: ChatMediaStoring {
    struct Upload: Equatable {
        var path: String
        var contentType: String
        var senderID: String
    }

    private(set) var uploads: [Upload] = []
    private(set) var downloads: [String] = []
    private(set) var deletedPaths: [String] = []
    /// Yol → bir kez fırlatılacak hata.
    var failures: [String: Error] = [:]
    /// Bu yol için sürekli hata (kalıcı başarısızlık testleri).
    var alwaysFail: [String: Error] = [:]
    /// Açıkken orijinal yüklemesi `releaseHeld()` çağrılana kadar bekler.
    var holdOriginals = false
    private var held: [CheckedContinuation<Void, Error>] = []

    func upload(fileURL: URL, to path: String, contentType: String, senderID: String,
                progress: @escaping @MainActor (Double) -> Void) async throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "yüklenecek dosya cihazda olmalı")
        if let error = alwaysFail[path] { throw error }
        if let error = failures.removeValue(forKey: path) { throw error }
        await progress(0.5)
        if holdOriginals, path.contains("/original.") {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { held.append($0) }
            } onCancel: { [weak self] in
                Task { @MainActor in self?.cancelHeld() }
            }
        }
        try Task.checkCancellation()
        await progress(1)
        uploads.append(Upload(path: path, contentType: contentType, senderID: senderID))
    }

    @MainActor func releaseHeld() {
        let pending = held
        held = []
        pending.forEach { $0.resume() }
    }

    @MainActor private func cancelHeld() {
        let pending = held
        held = []
        pending.forEach { $0.resume(throwing: CancellationError()) }
    }

    var hasHeldUpload: Bool { !held.isEmpty }

    func download(path: String, to destination: URL, progress: @escaping @MainActor (Double) -> Void) async throws {
        if let error = failures.removeValue(forKey: path) { throw error }
        downloads.append(path)
        await progress(0.5)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("indirildi".utf8).write(to: destination)
        await progress(1)
    }

    func delete(paths: [String]) async {
        deletedPaths.append(contentsOf: paths)
    }

    private(set) var acknowledged: [String] = []
    /// "Aldım" bildirimine bir kez fırlatılacak hata.
    var ackFailure: Error?

    func acknowledge(path: String) async throws {
        if let error = ackFailure {
            ackFailure = nil
            throw error
        }
        acknowledged.append(path)
    }
}

final class MockMediaProcessor: ChatMediaProcessing {
    private(set) var qualities: [ChatMediaQuality] = []
    var error: Error?

    func prepare(_ media: PickedMedia, quality: ChatMediaQuality, messageID: String, directory: URL) async throws -> PreparedMedia {
        if let error { throw error }
        qualities.append(quality)
        let ext = media.kind == .image ? (quality == .original ? "heic" : "jpg") : (quality == .original ? "mov" : "mp4")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = directory.appendingPathComponent("\(messageID).\(ext)")
        let thumb = directory.appendingPathComponent("\(messageID)-thumb.jpg")
        try Data(repeating: 1, count: 1_000).write(to: original)
        try Data(repeating: 2, count: 100).write(to: thumb)
        return PreparedMedia(
            originalFileName: original.lastPathComponent,
            thumbnailFileName: thumb.lastPathComponent,
            contentType: ChatMediaKind.contentType(forExtension: ext, kind: media.kind),
            fileExtension: ext,
            byteSize: 1_000,
            width: 4032,
            height: 3024,
            duration: media.kind == .video ? 12.4 : nil
        )
    }
}

func makeTemporaryDirectory(_ name: String = UUID().uuidString) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("farva-tests-\(name)", isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Model testleri

final class ChatMediaModelTests: XCTestCase {
    func testStoragePathsMatchRules() {
        XCTAssertEqual(ChatMediaPath.thumbnail(chatID: "a_b", messageID: "m1"), "chats/a_b/media/m1/thumb.jpg")
        XCTAssertEqual(ChatMediaPath.original(chatID: "a_b", messageID: "m1", fileExtension: "HEIC"), "chats/a_b/media/m1/original.heic")
        XCTAssertEqual(ChatMediaPath.sanitizedExtension("m.o.v"), "mov")
        XCTAssertEqual(ChatMediaPath.sanitizedExtension("x"), "bin", "kurallar 2–5 karakter ister")
        XCTAssertEqual(ChatMediaPath.sanitizedExtension("toolongext"), "bin")
    }

    func testContentTypesKeepOriginalFormats() {
        XCTAssertEqual(ChatMediaKind.contentType(forExtension: "heic", kind: .image), "image/heic")
        XCTAssertEqual(ChatMediaKind.contentType(forExtension: "JPG", kind: .image), "image/jpeg")
        XCTAssertEqual(ChatMediaKind.contentType(forExtension: "mov", kind: .video), "video/quicktime")
        XCTAssertEqual(ChatMediaKind.contentType(forExtension: "mp4", kind: .video), "video/mp4")
        XCTAssertEqual(ChatMediaKind.image.messageType, .image)
        XCTAssertTrue(ChatMessageType.video.isMedia)
        XCTAssertTrue(ChatMessageType.sendable.isSuperset(of: [.text, .image, .video]))
    }

    func testFirestoreFieldsRoundTrip() {
        let media = ChatMedia(
            originalPath: "chats/a_b/media/m1/original.mov", thumbnailPath: "chats/a_b/media/m1/thumb.jpg",
            contentType: "video/quicktime", fileExtension: "mov", byteSize: 123_456_789,
            width: 1920, height: 1080, duration: 12.5, quality: .original, status: .uploading
        )
        let fields = ChatMediaFields.encode(media)
        XCTAssertEqual(fields["size"] as? Int64, 123_456_789)
        XCTAssertEqual(ChatMediaFields.decode(fields), media)

        // Firestore sayıları NSNumber olarak döner.
        let fromServer: [String: Any] = [
            "originalPath": "p", "thumbnailPath": "t", "size": NSNumber(value: 5), "width": NSNumber(value: 3), "height": NSNumber(value: 4)
        ]
        let decoded = ChatMediaFields.decode(fromServer)
        XCTAssertEqual(decoded?.byteSize, 5)
        XCTAssertEqual(decoded?.status, .ready, "eksik durum hazır sayılır")
        XCTAssertNil(decoded?.duration)
        XCTAssertNil(ChatMediaFields.decode(["originalPath": "p"]), "önizleme yolu zorunlu")
        XCTAssertNil(ChatMediaFields.decode(nil))
    }

    func testMediaFormattingAndStages() {
        var media = ChatMedia(originalPath: "", thumbnailPath: "", contentType: "", fileExtension: "jpg", byteSize: 0,
                              width: 3000, height: 1500, duration: 75.4, quality: .fast, status: .ready)
        XCTAssertEqual(media.aspectRatio, 2)
        XCTAssertEqual(media.formattedDuration, "1:15")
        media.width = 0
        XCTAssertEqual(media.aspectRatio, 1)
        XCTAssertTrue(ChatUploadStage.thumbnail < .original)
        XCTAssertTrue(ChatUploadStage.finalize < .done)
        XCTAssertEqual(ChatMediaQuality.allCases.first, .original, "varsayılan seçenek Orijinal")
    }

    @MainActor
    func testRecordStoresMedia() throws {
        let container = try ModelContainer(for: ChatMessageRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let media = ChatMedia(originalPath: "o", thumbnailPath: "t", contentType: "image/heic", fileExtension: "heic",
                              byteSize: 10, width: 1, height: 2, duration: nil, quality: .original, status: .uploading)
        let record = ChatMessageRecord(
            dto: ChatMessageDTO(id: "1", senderID: "a", type: .image, text: "", createdAt: .now, media: media),
            ownerID: "a", chatID: "c", sendState: .pending
        )
        container.mainContext.insert(record)
        XCTAssertEqual(record.dto.media, media)
        XCTAssertNil(record.uploadStage)
        record.uploadStage = .original
        XCTAssertEqual(record.uploadStageRaw, "original")
        XCTAssertEqual(ChatMessageExport(record: record).media, media)
    }
}

// MARK: - Gerçek işlemci (fotoğraf)

final class ChatMediaProcessorTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = makeTemporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        }
    }

    private func pixelSize(_ url: URL) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return .zero }
        return ChatMediaProcessor.orientedPixelSize(of: source)
    }

    func testOriginalImageIsCopiedByteForByte() async throws {
        let source = directory.appendingPathComponent("kaynak.jpg")
        try XCTUnwrap(makeImage(width: 1200, height: 800).jpegData(compressionQuality: 0.9)).write(to: source)
        let out = directory.appendingPathComponent("out")

        let prepared = try await ChatMediaProcessor().prepare(PickedMedia(fileURL: source, kind: .image), quality: .original, messageID: "m1", directory: out)

        let original = out.appendingPathComponent(prepared.originalFileName)
        XCTAssertEqual(try Data(contentsOf: original), try Data(contentsOf: source), "yeniden sıkıştırılmaz")
        XCTAssertEqual(prepared.fileExtension, "jpg")
        XCTAssertEqual(prepared.contentType, "image/jpeg")
        XCTAssertEqual(prepared.width, 1200)
        XCTAssertEqual(prepared.height, 800)
        XCTAssertEqual(prepared.byteSize, Int64(try Data(contentsOf: source).count))

        let thumb = pixelSize(out.appendingPathComponent(prepared.thumbnailFileName))
        XCTAssertLessThanOrEqual(max(thumb.width, thumb.height), ChatMediaProcessor.thumbnailMaxPixel)
        XCTAssertGreaterThan(thumb.width, 0)
    }

    func testOriginalHEICKeepsFormat() async throws {
        let source = directory.appendingPathComponent("kaynak.heic")
        guard let cgImage = makeImage(width: 800, height: 600).cgImage,
              let destination = CGImageDestinationCreateWithURL(source as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw XCTSkip("Bu simülatörde HEIC kodlayıcı yok")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw XCTSkip("Bu simülatörde HEIC kodlayıcı yok") }

        let prepared = try await ChatMediaProcessor().prepare(PickedMedia(fileURL: source, kind: .image), quality: .original, messageID: "h1", directory: directory)
        XCTAssertEqual(prepared.fileExtension, "heic")
        XCTAssertEqual(prepared.contentType, "image/heic")
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(prepared.originalFileName)), try Data(contentsOf: source))
    }

    func testFastModeDownscalesToJPEG() async throws {
        let source = directory.appendingPathComponent("buyuk.png")
        try XCTUnwrap(makeImage(width: 4000, height: 1000).pngData()).write(to: source)

        let prepared = try await ChatMediaProcessor().prepare(PickedMedia(fileURL: source, kind: .image), quality: .fast, messageID: "f1", directory: directory)
        XCTAssertEqual(prepared.fileExtension, "jpg")
        XCTAssertEqual(prepared.width, Int(ChatMediaProcessor.fastImageMaxPixel))
        XCTAssertEqual(prepared.height, 512)
        XCTAssertLessThan(prepared.byteSize, ChatMediaProcessor.fileSize(source))
    }

    func testUnreadableImageThrows() async {
        let source = directory.appendingPathComponent("bozuk.jpg")
        try? Data("resim değil".utf8).write(to: source)
        do {
            _ = try await ChatMediaProcessor().prepare(PickedMedia(fileURL: source, kind: .image), quality: .fast, messageID: "x", directory: directory)
            XCTFail("hata bekleniyordu")
        } catch {}
    }
}

// MARK: - ViewModel medya akışı

@MainActor
final class ChatMediaViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockChatSync!
    private var store: MockMediaStore!
    private var processor: MockMediaProcessor!
    private var files: ChatMediaFiles!
    private var root: URL!
    private var sut: ChatViewModel!
    private var idCounter = 0
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private let me = AppUser.makeNew(id: "me", email: "ben@ornek.com", displayName: "Ben")
    private var room: ChatRoomDTO {
        ChatRoomDTO(id: ChatID.make("me", "friend"), members: ChatID.sortedMembers("me", "friend"),
                    names: ["me": "Ben", "friend": "Elif"], createdAt: now)
    }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: ChatMessageRecord.self, ChatPendingOperation.self, ChatPlacementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        sync = MockChatSync()
        store = MockMediaStore()
        processor = MockMediaProcessor()
        root = makeTemporaryDirectory()
        files = ChatMediaFiles(persistentRoot: root.appendingPathComponent("support"), cacheRoot: root.appendingPathComponent("caches"))
        idCounter = 0
        sut = ChatViewModel(
            sync: sync, mediaStore: store, processor: processor, files: files,
            defaults: makeTestDefaults("media.\(name)"),
            clock: { [unowned self] in self.now },
            makeID: { [unowned self] in
                self.idCounter += 1
                return "media-\(self.idCounter)"
            }
        )
        sut.configure(context: container.mainContext, user: me)
        sync.roomHandler?(room, false)
        await settle()
    }

    override func tearDown() async throws {
        store.releaseHeld()
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
        }
        await settleTasks()
    }

    private func picked(_ kind: ChatMediaKind = .image) throws -> PickedMedia {
        let url = root.appendingPathComponent("\(UUID().uuidString).\(kind == .image ? "heic" : "mov")")
        try Data("seçilen".utf8).write(to: url)
        return PickedMedia(fileURL: url, kind: kind)
    }

    private func item(_ id: String) -> ChatMessageItem? { sut.messages.first { $0.id == id } }

    private var thumbPath: String { ChatMediaPath.thumbnail(chatID: room.id, messageID: "media-1") }
    private var originalPath: String { ChatMediaPath.original(chatID: room.id, messageID: "media-1", fileExtension: "heic") }

    // MARK: Gönderme

    func testThumbnailFirstThenMessageThenOriginalThenReady() async throws {
        var uploadsAtSend: [String] = []
        sync.onSend = { [unowned self] _ in uploadsAtSend = self.store.uploads.map(\.path) }
        let source = try picked()

        await sut.sendMedia([source], quality: .original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.fileURL.path), "geçici kopya temizlenir")
        XCTAssertEqual(item("media-1")?.status, .sending)
        XCTAssertNotNil(item("media-1")?.localThumbnailURL, "gönderen kendi önizlemesini hemen görür")

        await settle()

        XCTAssertEqual(uploadsAtSend, [thumbPath], "mesaj belgesinden önce yalnızca önizleme yüklenir")
        XCTAssertEqual(store.uploads.map(\.path), [thumbPath, originalPath])
        XCTAssertEqual(store.uploads.map(\.contentType), ["image/jpeg", "image/heic"])
        XCTAssertEqual(store.uploads.map(\.senderID), ["me", "me"])

        let sentMessage = try XCTUnwrap(sync.sent.first)
        XCTAssertEqual(sentMessage.type, .image)
        XCTAssertEqual(sentMessage.media?.status, .uploading)
        XCTAssertEqual(sentMessage.media?.quality, .original)
        XCTAssertEqual(sentMessage.media?.width, 4032)

        XCTAssertEqual(sync.mediaUpdates.map(\.media.status), [.ready])
        XCTAssertEqual(item("media-1")?.status, .delivered)
        XCTAssertEqual(item("media-1")?.message.media?.status, .ready)
        XCTAssertTrue(sut.pendingOperations().isEmpty)

        // Yükleme bitince orijal kalıcı klasöre taşınır; görüntüleyici indirmeden açılır.
        let local = try XCTUnwrap(item("media-1")?.localOriginalURL)
        XCTAssertTrue(local.path.hasPrefix(files.originalsDirectory.path), "orijaller kalıcı klasörde (bulut kopyası silinebilir)")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: files.outgoingDirectory.path), [])
        let opened = try await sut.loadOriginal(for: item("media-1")!)
        XCTAssertEqual(opened, local)
        XCTAssertTrue(store.downloads.isEmpty)
    }

    func testFastQualityIsPassedToProcessorAndStored() async throws {
        await sut.sendMedia([try picked(.video)], quality: .fast)
        await settle()
        XCTAssertEqual(processor.qualities, [.fast])
        XCTAssertEqual(sync.sent.first?.type, .video)
        XCTAssertEqual(sync.sent.first?.media?.quality, .fast)
        XCTAssertEqual(sync.sent.first?.media?.fileExtension, "mp4")
        XCTAssertEqual(sync.sent.first?.media?.duration, 12.4)
    }

    func testEachFileBecomesOwnMessageAndReplyGoesToFirst() async throws {
        sync.messagesHandler?([ChatMessageDTO(id: "r1", senderID: "friend", text: "foto at", createdAt: now)])
        sut.beginReply(to: item("r1")!)
        await sut.sendMedia([try picked(), try picked(.video)], quality: .original)
        await settle()
        XCTAssertEqual(sync.sent.map(\.id), ["media-1", "media-2"])
        XCTAssertEqual(sync.sent.first?.replyTo?.messageID, "r1")
        XCTAssertNil(sync.sent.last?.replyTo)
        XCTAssertNil(sut.replyingTo)
    }

    func testProgressIsShownWhileOriginalUploads() async throws {
        store.holdOriginals = true
        await sut.sendMedia([try picked()], quality: .original)
        await settle()

        XCTAssertTrue(store.hasHeldUpload)
        XCTAssertEqual(item("media-1")?.uploadProgress, 0.5)
        XCTAssertTrue(item("media-1")?.isUploading ?? false)
        XCTAssertEqual(sync.sent.count, 1, "önizlemeli mesaj karşı tarafa çoktan gitti")

        store.releaseHeld()
        await settle()
        XCTAssertNil(item("media-1")?.uploadProgress)
        XCTAssertEqual(item("media-1")?.status, .delivered)
    }

    func testCancelDuringOriginalUploadDeletesMessageAndFiles() async throws {
        store.holdOriginals = true
        await sut.sendMedia([try picked()], quality: .original)
        await settle()

        sut.cancelUpload(item("media-1")!)
        await settle()

        XCTAssertEqual(sync.deletions, ["media-1"])
        XCTAssertEqual(Set(store.deletedPaths), [thumbPath, originalPath])
        XCTAssertTrue(sync.mediaUpdates.isEmpty, "iptal edilen yükleme hazır işaretlenmez")
        XCTAssertEqual(item("media-1")?.displayText, "Bu mesaj silindi")
        XCTAssertNil(item("media-1")?.message.media)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: files.outgoingDirectory.path), [])
    }

    func testCancelBeforeMessageCreatedRemovesEverything() async throws {
        sync.isOffline = true
        await sut.sendMedia([try picked()], quality: .original)
        await settle()
        XCTAssertEqual(store.uploads.map(\.path), [thumbPath], "önizleme yüklendi, belge çevrimdışı bekliyor")

        sut.cancelUpload(item("media-1")!)
        sync.isOffline = false
        await settle()

        XCTAssertNil(item("media-1"))
        XCTAssertTrue(sync.sent.isEmpty)
        XCTAssertTrue(sync.deletions.isEmpty)
        XCTAssertEqual(store.deletedPaths, [thumbPath])
        XCTAssertTrue(sut.pendingOperations().isEmpty)
    }

    func testNetworkDropResumesOnForeground() async throws {
        store.failures[ChatMediaPath.original(chatID: room.id, messageID: "media-1", fileExtension: "heic")] = AppError.network
        await sut.sendMedia([try picked()], quality: .original)
        await settle()

        XCTAssertEqual(item("media-1")?.status, .sending, "bağlantı gelince devam edecek")
        XCTAssertTrue(sut.pendingOperations().contains { $0.kind == .uploadOriginal })
        XCTAssertEqual(sync.sent.count, 1)

        await sut.handleForeground()
        await settle()
        XCTAssertEqual(store.uploads.map(\.path), [thumbPath, originalPath], "önizleme yeniden yüklenmez")
        XCTAssertEqual(item("media-1")?.status, .delivered)
        XCTAssertEqual(sync.sent.count, 1, "mesaj yeniden oluşturulmaz")
    }

    func testPermanentUploadFailureCanBeRetried() async throws {
        store.alwaysFail[originalPath] = AppError.notAuthorized
        await sut.sendMedia([try picked()], quality: .original)
        for _ in 0..<4 { await settle(); await sut.handleForeground() }
        await settle()
        XCTAssertEqual(item("media-1")?.status, .failed)

        store.alwaysFail = [:]
        sut.retry(item("media-1")!)
        await settle()
        XCTAssertEqual(item("media-1")?.status, .delivered)
        XCTAssertEqual(sync.sent.count, 1)
        XCTAssertEqual(sync.mediaUpdates.count, 1)
    }

    func testProcessingErrorIsShown() async throws {
        processor.error = AppError.invalidInput("Fotoğraf okunamadı.")
        await sut.sendMedia([try picked()], quality: .original)
        XCTAssertEqual(sut.errorMessage, "Fotoğraf okunamadı.")
        XCTAssertTrue(sut.messages.isEmpty)
        XCTAssertFalse(sut.isPreparingMedia)
    }

    func testDeleteForEveryoneRemovesStorageFiles() async throws {
        await sut.sendMedia([try picked()], quality: .original)
        await settle()
        sut.deleteForEveryone(item("media-1")!)
        await settle()
        XCTAssertEqual(sync.deletions, ["media-1"])
        XCTAssertEqual(Set(store.deletedPaths), [thumbPath, originalPath])
        XCTAssertNil(item("media-1")?.localOriginalURL)
    }

    // MARK: Alıcı

    private func remoteMedia(status: ChatMediaStatus, deleted: Bool = false) -> ChatMessageDTO {
        let media = ChatMedia(
            originalPath: ChatMediaPath.original(chatID: room.id, messageID: "r-media", fileExtension: "mov"),
            thumbnailPath: ChatMediaPath.thumbnail(chatID: room.id, messageID: "r-media"),
            contentType: "video/quicktime", fileExtension: "mov", byteSize: 50_000_000,
            width: 1080, height: 1920, duration: 30, quality: .original, status: status
        )
        return ChatMessageDTO(id: "r-media", senderID: "friend", type: .video, text: "", createdAt: now,
                              deleted: deleted, media: deleted ? nil : media)
    }

    func testRecipientDownloadsThumbnailOnceAndOriginalWhenReady() async throws {
        sync.messagesHandler?([remoteMedia(status: .uploading)])
        let incoming = try XCTUnwrap(item("r-media"))
        XCTAssertNil(incoming.status)
        XCTAssertNil(incoming.localThumbnailURL)
        XCTAssertFalse(incoming.isUploading, "iptal düğmesi yalnızca gönderende")

        let thumb = await sut.loadThumbnail(for: incoming)
        XCTAssertNotNil(thumb)
        XCTAssertNotNil(item("r-media")?.localThumbnailURL)
        await sut.loadThumbnail(for: item("r-media")!)
        XCTAssertEqual(store.downloads.count, 1, "önizleme önbellekten gelir")

        do {
            _ = try await sut.loadOriginal(for: item("r-media")!)
            XCTFail("yüklenmekte olan orijinal açılmamalı")
        } catch {}

        sync.messagesHandler?([remoteMedia(status: .ready)])
        let url = try await sut.loadOriginal(for: item("r-media")!)
        XCTAssertEqual(url.pathExtension, "mov")
        XCTAssertNil(sut.downloadProgress["r-media"], "indirme bitince ilerleme kalkar")
        _ = try await sut.loadOriginal(for: item("r-media")!)
        XCTAssertEqual(store.downloads.filter { $0.hasSuffix("original.mov") }.count, 1)
    }

    func testRemoteDeleteRemovesCachedFiles() async throws {
        sync.messagesHandler?([remoteMedia(status: .ready)])
        await sut.loadThumbnail(for: item("r-media")!)
        let original = try await sut.loadOriginal(for: item("r-media")!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))

        sync.messagesHandler?([remoteMedia(status: .ready, deleted: true)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.cachedThumbnailURL(messageID: "r-media").path))
        XCTAssertEqual(item("r-media")?.displayText, "Bu mesaj silindi")
    }
}
