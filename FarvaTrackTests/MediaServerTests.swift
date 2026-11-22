import XCTest
import SwiftData
@testable import FarvaTrack

// MARK: - Ağ taklidi

/// Medya sunucusuna giden istekleri yakalar; yanıtı testin verdiği işleyici üretir.
final class StubURLProtocol: URLProtocol {
    struct Captured {
        var method: String
        var url: URL
        var headers: [String: String]
        var body: Data?

        var query: [String: String] {
            Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _requests: [Captured] = []
    nonisolated(unsafe) private static var _handler: ((Captured) -> (Int, Data))?

    static var requests: [Captured] { lock.withLock { _requests } }

    static func reset(_ handler: @escaping (Captured) -> (Int, Data)) {
        lock.withLock {
            _requests = []
            _handler = handler
        }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            body = data
        }
        let captured = Captured(method: request.httpMethod ?? "GET", url: request.url!,
                                headers: request.allHTTPHeaderFields ?? [:], body: body)
        let handler = Self.lock.withLock {
            Self._requests.append(captured)
            return Self._handler
        }
        let (status, data) = handler?(captured) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - İstemci

@MainActor
final class MediaServerClientTests: XCTestCase {
    private var root: URL!
    private let base = URL(string: "https://media.example.workers.dev")!

    override func setUp() async throws {
        try await super.setUp()
        root = makeTemporaryDirectory()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func client(single: Int64 = 1_000, part: Int64 = 400) -> MediaServerClient {
        MediaServerClient(baseURL: base, session: StubURLProtocol.session(), token: { "belirtec" },
                          singleUploadLimit: single, partSize: part)
    }

    private func file(bytes: Int) throws -> URL {
        let url = root.appendingPathComponent("\(UUID().uuidString).bin")
        try Data(repeating: 9, count: bytes).write(to: url)
        return url
    }

    func testConfigParsing() {
        XCTAssertEqual(MediaServerConfig.parse(" https://a.workers.dev/ ")?.absoluteString, "https://a.workers.dev")
        XCTAssertNil(MediaServerConfig.parse("http://a.workers.dev"), "yalnızca https")
        XCTAssertNil(MediaServerConfig.parse(""))
        XCTAssertNil(MediaServerConfig.parse("çöp"))
        XCTAssertNil(MediaServerConfig.load(from: Bundle(for: Self.self)), "test paketinde ayar dosyası yok")
    }

    func testSmallFileIsSentInOneRequestWithToken() async throws {
        StubURLProtocol.reset { _ in (200, Data(#"{"ok":true}"#.utf8)) }
        var last = 0.0
        try await client().upload(fileURL: try file(bytes: 500), to: "chats/a_b/media/m1/thumb.jpg", contentType: "image/jpeg",
                                  senderID: "a", progress: { last = $0 })
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].method, "PUT")
        XCTAssertEqual(requests[0].url.path, "/v1/o")
        XCTAssertEqual(requests[0].query["p"], "chats/a_b/media/m1/thumb.jpg")
        XCTAssertEqual(requests[0].headers["Authorization"], "Bearer belirtec")
        XCTAssertEqual(requests[0].headers["Content-Type"], "image/jpeg")
        XCTAssertEqual(last, 1)
    }

    func testLargeFileIsUploadedInParts() async throws {
        StubURLProtocol.reset { request in
            switch (request.method, request.url.path) {
            case ("POST", "/v1/mpu"): return (200, Data(#"{"uploadId":"u1"}"#.utf8))
            case ("PUT", "/v1/mpu"): return (200, Data(#"{"partNumber":\#(request.query["part"]!),"etag":"e\#(request.query["part"]!)"}"#.utf8))
            case ("POST", "/v1/mpu/complete"): return (200, Data(#"{"ok":true}"#.utf8))
            default: return (500, Data())
            }
        }
        try await client().upload(fileURL: try file(bytes: 1_100), to: "chats/a_b/media/m1/original.mov",
                                  contentType: "video/quicktime", senderID: "a", progress: { _ in })
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.map(\.method), ["POST", "PUT", "PUT", "PUT", "POST"])
        XCTAssertEqual(requests[0].headers["X-Total-Size"], "1100")
        XCTAssertEqual(requests[1...3].map { $0.query["part"] }, ["1", "2", "3"])
        XCTAssertTrue(requests[1...3].allSatisfy { $0.query["uploadId"] == "u1" })
        // Gövde, URLProtocol'e her zaman ulaşmayabilir; ulaştıysa parça boyları denetlenir.
        let sizes = requests[1...3].compactMap { $0.body?.count }
        if sizes.count == 3, sizes.allSatisfy({ $0 > 0 }) {
            XCTAssertEqual(sizes, [400, 400, 300])
        }
        XCTAssertEqual(requests[4].url.path, "/v1/mpu/complete")
    }

    func testFailedPartAbortsUpload() async throws {
        StubURLProtocol.reset { request in
            switch (request.method, request.url.path) {
            case ("POST", "/v1/mpu"): return (200, Data(#"{"uploadId":"u9"}"#.utf8))
            case ("PUT", "/v1/mpu"): return (403, Data(#"{"error":"İzin yok"}"#.utf8))
            default: return (200, Data(#"{"ok":true}"#.utf8))
            }
        }
        do {
            try await client().upload(fileURL: try file(bytes: 2_000), to: "chats/a_b/media/m1/original.mov",
                                      contentType: "video/quicktime", senderID: "a", progress: { _ in })
            XCTFail("hata bekleniyordu")
        } catch {
            XCTAssertEqual(error as? AppError, .notAuthorized)
        }
        XCTAssertEqual(StubURLProtocol.requests.last?.method, "DELETE", "yarım yükleme iptal edilir")
        XCTAssertEqual(StubURLProtocol.requests.last?.query["uploadId"], "u9")
    }

    func testDownloadAndErrors() async throws {
        StubURLProtocol.reset { request in
            request.query["p"] == "var.jpg" ? (200, Data("resim".utf8)) : (404, Data(#"{"error":"yok"}"#.utf8))
        }
        let destination = root.appendingPathComponent("alt/klasor/x.jpg")
        try await client().download(path: "var.jpg", to: destination, progress: { _ in })
        XCTAssertEqual(try Data(contentsOf: destination), Data("resim".utf8))

        let missing = root.appendingPathComponent("yok.jpg")
        do {
            try await client().download(path: "yok.jpg", to: missing, progress: { _ in })
            XCTFail("hata bekleniyordu")
        } catch {
            XCTAssertEqual(error as? AppError, .mediaRemoved)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path), "hata gövdesi dosya sanılmaz")
    }

    func testStatusMapping() {
        func status(_ code: Int) -> AppError? {
            let response = HTTPURLResponse(url: base, statusCode: code, httpVersion: nil, headerFields: nil)!
            do {
                try MediaServerClient.check(response)
                return nil
            } catch {
                return error as? AppError
            }
        }
        XCTAssertNil(status(204))
        XCTAssertEqual(status(401), .notAuthenticated)
        XCTAssertEqual(status(403), .notAuthorized)
        XCTAssertEqual(status(404), .mediaRemoved)
        XCTAssertEqual(status(503), .network, "sunucu hatası yeniden denenir")
        XCTAssertTrue(MediaServerClient.mapTransport(URLError(.cancelled)) is CancellationError)
        XCTAssertEqual(MediaServerClient.mapTransport(URLError(.notConnectedToInternet)) as? AppError, .network)
    }

    func testAdminCallsAndPublicURL() async throws {
        StubURLProtocol.reset { request in
            switch request.url.path {
            case "/v1/usage":
                return (200, Data(#"{"usedBytes":5000000000,"originalBytes":4000000000,"limitBytes":10000000000,"highWaterBytes":9000000000,"retentionDays":60}"#.utf8))
            case "/v1/cleanup":
                return (200, Data(#"{"deleted":2,"totalBytes":10,"afterBytes":5,"waitingBytes":0}"#.utf8))
            default:
                return (200, Data(#"{"ok":true}"#.utf8))
            }
        }
        let sut = client()
        let usage = try await sut.usage()
        XCTAssertEqual(usage.fraction, 0.5, accuracy: 0.0001)
        let cleaned = try await sut.cleanup()
        XCTAssertEqual(cleaned.deleted, 2)
        try await sut.acknowledge(path: "chats/a_b/media/m/original.jpg")
        try await sut.deletePrefix("users/a/stickers/")
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests[2].method, "POST")
        XCTAssertEqual(requests[2].url.path, "/v1/ack")
        XCTAssertEqual(requests[3].method, "DELETE")
        XCTAssertEqual(requests[3].query["p"], "users/a/stickers/")
        XCTAssertEqual(sut.publicURL(for: "profile_images/a/x.jpg")?.absoluteString,
                       "https://media.example.workers.dev/v1/public/profile_images/a/x.jpg")
    }

    func testNotConfigured() async {
        let sut = MediaServerClient(baseURL: nil, session: StubURLProtocol.session(), token: { "t" })
        do {
            try await sut.acknowledge(path: "x")
            XCTFail("hata bekleniyordu")
        } catch {
            XCTAssertEqual(error as? AppError, .mediaServerNotConfigured)
        }
        XCTAssertNil(sut.publicURL(for: "profile_images/a/x.jpg"))
    }
}

// MARK: - Dosya konumları

final class ChatMediaFilesTests: XCTestCase {
    func testOriginalsArePersistentAndLegacyCacheIsMigrated() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ChatMediaFiles(persistentRoot: root.appendingPathComponent("support"), cacheRoot: root.appendingPathComponent("caches"))
        try FileManager.default.createDirectory(at: files.cacheRoot, withIntermediateDirectories: true)
        let legacy = files.cacheRoot.appendingPathComponent("m1.heic")
        try Data("eski".utf8).write(to: legacy)

        let url = files.originalURL(messageID: "m1", fileExtension: "HEIC")
        XCTAssertTrue(url.path.hasPrefix(files.persistentRoot.path), "orijaller önbellekte değil")
        XCTAssertEqual(try Data(contentsOf: url), Data("eski".utf8), "eski indirilen taşınır")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }
}

// MARK: - Gelen orijallerin cihaza alınması

final class MockPhotoSaver: PhotoLibrarySaving {
    private(set) var saved: [(name: String, isVideo: Bool)] = []
    var error: Error?

    func save(fileURL: URL, isVideo: Bool) async throws {
        if let error { throw error }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        saved.append((fileURL.lastPathComponent, isVideo))
    }
}

@MainActor
final class ChatOriginalRetentionTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockChatSync!
    private var store: MockMediaStore!
    private var photos: MockPhotoSaver!
    private var root: URL!
    private var files: ChatMediaFiles!
    private var defaults: UserDefaults!
    private var sut: ChatViewModel!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var roomID: String { ChatID.make("me", "friend") }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: ChatMessageRecord.self, ChatPendingOperation.self, ChatPlacementRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sync = MockChatSync()
        store = MockMediaStore()
        photos = MockPhotoSaver()
        root = makeTemporaryDirectory()
        files = ChatMediaFiles(persistentRoot: root.appendingPathComponent("support"), cacheRoot: root.appendingPathComponent("caches"))
        defaults = makeTestDefaults("retention.\(name)")
        sut = makeViewModel(autoFetch: false)
        sut.configure(context: container.mainContext, user: AppUser.makeNew(id: "me", email: "ben@ornek.com", displayName: "Ben"))
        sync.roomHandler?(ChatRoomDTO(id: roomID, members: ChatID.sortedMembers("me", "friend"), createdAt: now), false)
        await settleTasks()
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

    private func makeViewModel(autoFetch: Bool) -> ChatViewModel {
        ChatViewModel(sync: sync, mediaStore: store, processor: MockMediaProcessor(), files: files,
                      defaults: defaults, photoSaver: photos, autoFetchOriginals: autoFetch,
                      clock: { [unowned self] in self.now }, makeID: { UUID().uuidString })
    }

    private func media(_ id: String, ext: String = "heic", status: ChatMediaStatus = .ready) -> ChatMedia {
        ChatMedia(originalPath: ChatMediaPath.original(chatID: roomID, messageID: id, fileExtension: ext),
                  thumbnailPath: ChatMediaPath.thumbnail(chatID: roomID, messageID: id),
                  contentType: ext == "mov" ? "video/quicktime" : "image/heic", fileExtension: ext, byteSize: 10,
                  width: 10, height: 10, duration: nil, quality: .original, status: status)
    }

    private func incoming(_ id: String, ext: String = "heic", status: ChatMediaStatus = .ready, from sender: String = "friend") -> ChatMessageDTO {
        ChatMessageDTO(id: id, senderID: sender, type: ext == "mov" ? .video : .image, text: "", createdAt: now,
                       media: media(id, ext: ext, status: status))
    }

    func testIncomingOriginalsAreDownloadedSavedAndAcknowledgedOnce() async throws {
        sync.messagesHandler?([incoming("p1"), incoming("v1", ext: "mov"), incoming("u1", status: .uploading), incoming("mine", from: "me")])
        XCTAssertEqual(Set(sut.pendingIncomingOriginals().map(\.messageID)), ["p1", "v1"], "yüklenmekte olan ve kendi mesajım hariç")

        await sut.fetchPendingOriginals()
        XCTAssertEqual(Set(store.downloads), [media("p1").originalPath, media("v1", ext: "mov").originalPath])
        XCTAssertEqual(Set(store.acknowledged), Set(store.downloads))
        XCTAssertEqual(photos.saved.map(\.isVideo).sorted { !$0 && $1 }, [false, true])
        let local = files.originalURL(messageID: "p1", fileExtension: "heic")
        XCTAssertTrue(local.path.hasPrefix(files.persistentRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.path))

        await sut.fetchPendingOriginals()
        XCTAssertEqual(store.downloads.count, 2, "tekrar indirilmez")
        XCTAssertEqual(photos.saved.count, 2, "tekrar kaydedilmez")
        XCTAssertTrue(sut.pendingIncomingOriginals().isEmpty)
    }

    func testAutoSaveSettingIsRespected() async {
        defaults.set(false, forKey: ChatMediaPreferences.autoSaveKey)
        sync.messagesHandler?([incoming("p1")])
        await sut.fetchPendingOriginals()
        XCTAssertTrue(photos.saved.isEmpty)
        XCTAssertEqual(store.acknowledged.count, 1, "kaydetme kapalı olsa da cihaza alınır")
    }

    func testAlreadyDownloadedOriginalIsAcknowledgedButNotSavedAgain() async throws {
        sync.messagesHandler?([incoming("p1")])
        let local = files.originalURL(messageID: "p1", fileExtension: "heic")
        try Data("önceden".utf8).write(to: local)
        await sut.fetchPendingOriginals()
        XCTAssertTrue(store.downloads.isEmpty)
        XCTAssertTrue(photos.saved.isEmpty, "eski indirilmişler Fotoğraflar'ı doldurmaz")
        XCTAssertEqual(store.acknowledged, [media("p1").originalPath])
    }

    func testOfflineAckIsRetriedWithoutRedownloadOrResave() async {
        sync.messagesHandler?([incoming("p1")])
        store.ackFailure = AppError.network
        await sut.fetchPendingOriginals()
        XCTAssertTrue(store.acknowledged.isEmpty)
        XCTAssertEqual(sut.pendingIncomingOriginals().count, 1)

        await sut.fetchPendingOriginals()
        XCTAssertEqual(store.acknowledged.count, 1)
        XCTAssertEqual(store.downloads.count, 1)
        XCTAssertEqual(photos.saved.count, 1)
    }

    func testRemovedOriginalIsMarkedAndNotRetried() async throws {
        sync.messagesHandler?([incoming("old"), incoming("p2")])
        store.failures[media("old").originalPath] = AppError.mediaRemoved
        await sut.fetchPendingOriginals()
        XCTAssertEqual(store.acknowledged, [media("p2").originalPath], "biri silinmiş olsa da diğeri alınır")
        XCTAssertTrue(sut.pendingIncomingOriginals().isEmpty)

        let item = try XCTUnwrap(sut.messages.first { $0.id == "old" })
        do {
            _ = try await sut.loadOriginal(for: item)
            XCTFail("buluttan silinen orijal açılamaz")
        } catch {
            XCTAssertEqual(error as? AppError, .mediaRemoved)
        }
        XCTAssertEqual(store.downloads.filter { $0.contains("/old/") }.count, 0, "yeniden indirilmeye çalışılmaz")
    }

    func testViewerAndAutoFetchShareOneDownload() async throws {
        sync.messagesHandler?([incoming("p1")])
        store.holdOriginals = false
        let item = try XCTUnwrap(sut.messages.first { $0.id == "p1" })
        async let viewer = sut.loadOriginal(for: item)
        await sut.fetchPendingOriginals()
        _ = try await viewer
        XCTAssertEqual(store.downloads.count, 1)
    }

    func testAutoFetchRunsWhenMessagesArrive() async throws {
        sut.reset()
        sut = makeViewModel(autoFetch: true)
        sut.configure(context: container.mainContext, user: AppUser.makeNew(id: "me", email: "ben@ornek.com", displayName: "Ben"))
        sync.roomHandler?(ChatRoomDTO(id: roomID, members: ChatID.sortedMembers("me", "friend"), createdAt: now), false)
        await settleTasks()
        sync.messagesHandler?([incoming("p9")])
        for _ in 0..<5 { await settleTasks() }
        XCTAssertEqual(store.acknowledged, [media("p9").originalPath])
    }
}

// MARK: - Depolama ekranı

final class MockUsageStore: ChatMediaStoring {
    var usageResult: Result<MediaUsage, Error> = .success(MediaUsage(usedBytes: 2_500_000_000, originalBytes: 2_000_000_000,
                                                                       limitBytes: 10_000_000_000, highWaterBytes: 9_000_000_000, retentionDays: 60))
    var cleanupResult = MediaCleanupResult(deleted: 0, totalBytes: 0, afterBytes: 0, waitingBytes: 0)
    private(set) var cleanups = 0

    func upload(fileURL: URL, to path: String, contentType: String, senderID: String, progress: @escaping @MainActor (Double) -> Void) async throws {}
    func download(path: String, to destination: URL, progress: @escaping @MainActor (Double) -> Void) async throws {}
    func delete(paths: [String]) async {}
    func usage() async throws -> MediaUsage { try usageResult.get() }
    func cleanup() async throws -> MediaCleanupResult {
        cleanups += 1
        return cleanupResult
    }
}

@MainActor
final class ChatStorageViewModelTests: XCTestCase {
    func testUsageAndCleanupMessages() async {
        let store = MockUsageStore()
        let sut = ChatStorageViewModel(media: store)
        XCTAssertEqual(sut.usageText, "—")
        await sut.load()
        XCTAssertEqual(sut.usage?.fraction ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertTrue(sut.usageText.contains("/"))
        XCTAssertNotNil(sut.originalsText)

        await sut.cleanNow()
        XCTAssertEqual(store.cleanups, 1)
        XCTAssertTrue(sut.resultMessage?.hasPrefix("Silinecek orijal yok") == true)

        store.cleanupResult = MediaCleanupResult(deleted: 3, totalBytes: 9, afterBytes: 5, waitingBytes: 1_000_000)
        await sut.cleanNow()
        XCTAssertTrue(sut.resultMessage?.hasPrefix("3 orijal") == true)
        XCTAssertTrue(sut.resultMessage?.contains("bekliyor") == true)

        store.usageResult = .failure(AppError.mediaServerNotConfigured)
        await sut.load()
        XCTAssertEqual(sut.errorMessage, AppError.mediaServerNotConfigured.errorDescription)
    }
}
