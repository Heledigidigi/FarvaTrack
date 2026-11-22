import Foundation
import FirebaseAuth

// MARK: - Sözleşme

/// Medya dosyalarının (sohbet fotoğraf/video, ses, sticker, baloncuk, profil fotoğrafı) depolama işlemleri.
/// Canlı uygulama Cloudflare R2 üzerindeki medya sunucusunu (`cloudflare/media-worker`) kullanır;
/// testlerde sahte uygulamayla değiştirilir.
protocol ChatMediaStoring: AnyObject {
    /// Dosyayı yükler. İlerleme 0…1 arası bildirilir. `Task` iptal edilirse yükleme de iptal olur.
    func upload(fileURL: URL, to path: String, contentType: String, senderID: String,
                progress: @escaping @MainActor (Double) -> Void) async throws
    /// Dosyayı `destination` konumuna indirir.
    func download(path: String, to destination: URL,
                  progress: @escaping @MainActor (Double) -> Void) async throws
    /// En iyi çabayla siler (dosya yoksa hata sayılmaz).
    func delete(paths: [String]) async
    /// Alıcı orijali cihazına aldı: sunucu bundan sonra buluttaki kopyayı temizleyebilir.
    func acknowledge(path: String) async throws
    /// Bir klasördeki tüm dosyaları siler (hesap silme, stil silme).
    func deletePrefix(_ prefix: String) async throws
    func usage() async throws -> MediaUsage
    func cleanup() async throws -> MediaCleanupResult
    /// Herkese açık okunabilen dosyanın (profil fotoğrafı) adresi.
    func publicURL(for path: String) -> URL?
}

extension ChatMediaStoring {
    func acknowledge(path: String) async throws {}
    func deletePrefix(_ prefix: String) async throws {}
    func usage() async throws -> MediaUsage { throw AppError.mediaServerNotConfigured }
    func cleanup() async throws -> MediaCleanupResult { throw AppError.mediaServerNotConfigured }
    func publicURL(for path: String) -> URL? { nil }
}

/// Yeni mesaj için karşı tarafa push bildirimi isteği (8G). Gönderim medya sunucusundan yapılır.
protocol ChatNotifying: AnyObject {
    func notify(chatID: String, messageID: String) async throws
}

/// Sesli arama (8H): TURN/STUN sunucuları ve karşı tarafı çaldırma (VoIP push ya da bildirim).
protocol CallServerProviding: AnyObject {
    func iceServers() async throws -> [IceServer]
    func ring(chatID: String, callID: String) async throws
}

/// Bulut depolama özeti.
struct MediaUsage: Codable, Equatable {
    var usedBytes: Int64
    var originalBytes: Int64
    var limitBytes: Int64
    var highWaterBytes: Int64
    var retentionDays: Int

    var fraction: Double {
        guard limitBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(limitBytes)))
    }
}

struct MediaCleanupResult: Codable, Equatable {
    var deleted: Int
    var totalBytes: Int64
    var afterBytes: Int64
    /// Alıcının henüz indirmediği orijaller (silinmez).
    var waitingBytes: Int64
}

// MARK: - Yapılandırma

/// Sunucu adresi `MediaServer.plist` (`URL` anahtarı) dosyasından okunur. Dosya repoda değildir;
/// CI, GitHub değişkeni `MEDIA_SERVER_URL`'den yazar.
enum MediaServerConfig {
    static let resourceName = "MediaServer"

    static let baseURL: URL? = load(from: .main)

    static func load(from bundle: Bundle) -> URL? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = plist["URL"] as? String else { return nil }
        return parse(raw)
    }

    /// Yalnızca https adresleri kabul edilir; sondaki `/` atılır.
    static func parse(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}

// MARK: - İstemci

final class MediaServerClient: ChatMediaStoring {
    /// Worker'ın istek gövdesi sınırı 100 MB: bundan büyükler parça parça yüklenir.
    static let defaultSingleUploadLimit: Int64 = 90 * 1024 * 1024
    static let defaultPartSize: Int64 = 50 * 1024 * 1024
    static let partRetries = 3

    private let baseURL: URL?
    private let session: URLSession
    private let token: () async throws -> String
    private let singleUploadLimit: Int64
    private let partSize: Int64

    init(baseURL: URL? = MediaServerConfig.baseURL,
         session: URLSession = .shared,
         token: @escaping () async throws -> String = MediaServerClient.firebaseToken,
         singleUploadLimit: Int64 = MediaServerClient.defaultSingleUploadLimit,
         partSize: Int64 = MediaServerClient.defaultPartSize) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
        self.singleUploadLimit = singleUploadLimit
        self.partSize = partSize
    }

    static func firebaseToken() async throws -> String {
        guard FirebaseBootstrap.isConfigured, let user = Auth.auth().currentUser else { throw AppError.notAuthenticated }
        do {
            return try await user.getIDToken()
        } catch {
            throw AppError.map(error)
        }
    }

    // MARK: İstek yardımcıları

    func endpoint(_ route: String, query: [String: String] = [:]) throws -> URL {
        guard let baseURL else { throw AppError.mediaServerNotConfigured }
        var components = URLComponents(url: baseURL.appendingPathComponent(route), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw AppError.mediaServerNotConfigured }
        return url
    }

    private func makeRequest(_ method: String, _ route: String, query: [String: String] = [:],
                         headers: [String: String] = [:]) async throws -> URLRequest {
        var request = URLRequest(url: try endpoint(route, query: query))
        request.httpMethod = method
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    /// HTTP durum kodunu uygulama hatasına çevirir.
    static func check(_ response: URLResponse, body: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { throw AppError.network }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw AppError.notAuthenticated
        case 403: throw AppError.notAuthorized
        case 404: throw AppError.mediaRemoved
        case 413: throw AppError.storage("Dosya çok büyük.")
        case 415: throw AppError.storage("Bu dosya türü desteklenmiyor.")
        case 408, 429, 500..<600: throw AppError.network
        default:
            let message = body.flatMap { try? JSONDecoder().decode([String: String].self, from: $0)["error"] }
            throw AppError.storage(message ?? "Sunucu isteği reddetti (\(http.statusCode)).")
        }
    }

    static func mapTransport(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? CancellationError() : AppError.network
        }
        return AppError.map(error)
    }

    private func send(_ request: URLRequest, body: Data? = nil) async throws -> Data {
        do {
            let (data, response): (Data, URLResponse)
            if let body {
                (data, response) = try await session.upload(for: request, from: body)
            } else {
                (data, response) = try await session.data(for: request)
            }
            try Self.check(response, body: data)
            return data
        } catch {
            throw Self.mapTransport(error)
        }
    }

    // MARK: Yükleme

    func upload(fileURL: URL, to path: String, contentType: String, senderID: String,
                progress: @escaping @MainActor (Double) -> Void) async throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        try Task.checkCancellation()
        if size <= singleUploadLimit {
            let request = try await makeRequest("PUT", "v1/o", query: ["p": path], headers: ["Content-Type": contentType])
            let tracker = TransferProgress { value in progress(value) }
            do {
                let (data, response) = try await session.upload(for: request, fromFile: fileURL, delegate: tracker)
                try Self.check(response, body: data)
            } catch {
                throw Self.mapTransport(error)
            }
            await progress(1)
        } else {
            try await uploadInParts(fileURL: fileURL, size: size, path: path, contentType: contentType, progress: progress)
        }
    }

    private struct UploadedPart: Codable {
        var partNumber: Int
        var etag: String
    }

    /// Büyük dosya: 50 MB'lık parçalar; her parça ağ hatasında birkaç kez yeniden denenir.
    private func uploadInParts(fileURL: URL, size: Int64, path: String, contentType: String,
                               progress: @escaping @MainActor (Double) -> Void) async throws {
        let create = try await makeRequest("POST", "v1/mpu", query: ["p": path],
                                       headers: ["Content-Type": contentType, "X-Total-Size": String(size)])
        let created = try await send(create)
        guard let uploadID = (try? JSONDecoder().decode([String: String].self, from: created))?["uploadId"] else {
            throw AppError.storage("Yükleme başlatılamadı.")
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var parts: [UploadedPart] = []
        var sent: Int64 = 0
        do {
            var number = 1
            while sent < size {
                try Task.checkCancellation()
                let length = min(partSize, size - sent)
                try handle.seek(toOffset: UInt64(sent))
                guard let chunk = try handle.read(upToCount: Int(length)), !chunk.isEmpty else { break }
                let base = Double(sent)
                let chunkSize = Double(chunk.count)
                let part = try await uploadPart(chunk, number: number, path: path, uploadID: uploadID) { fraction in
                    progress((base + fraction * chunkSize) / Double(size))
                }
                parts.append(part)
                sent += Int64(chunk.count)
                number += 1
            }
            let body = try JSONEncoder().encode(["parts": parts])
            let complete = try await makeRequest("POST", "v1/mpu/complete", query: ["p": path, "uploadId": uploadID],
                                             headers: ["Content-Type": "application/json"])
            _ = try await send(complete, body: body)
            await progress(1)
        } catch {
            // Yarım yükleme sunucuda yer kaplamasın.
            if let abort = try? await makeRequest("DELETE", "v1/mpu", query: ["p": path, "uploadId": uploadID]) {
                _ = try? await session.data(for: abort)
            }
            throw error
        }
    }

    private func uploadPart(_ chunk: Data, number: Int, path: String, uploadID: String,
                            progress: @escaping @MainActor (Double) -> Void) async throws -> UploadedPart {
        var attempt = 0
        while true {
            attempt += 1
            do {
                let request = try await makeRequest("PUT", "v1/mpu", query: ["p": path, "uploadId": uploadID, "part": String(number)],
                                                headers: ["Content-Type": "application/octet-stream"])
                let tracker = TransferProgress { value in progress(value) }
                let (data, response) = try await session.upload(for: request, from: chunk, delegate: tracker)
                try Self.check(response, body: data)
                return try JSONDecoder().decode(UploadedPart.self, from: data)
            } catch {
                let mapped = Self.mapTransport(error)
                guard attempt < Self.partRetries, (mapped as? AppError) == .network else { throw mapped }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
            }
        }
    }

    // MARK: İndirme

    func download(path: String, to destination: URL,
                  progress: @escaping @MainActor (Double) -> Void) async throws {
        let request = try await makeRequest("GET", "v1/o", query: ["p": path])
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tracker = TransferProgress { value in progress(value) }
        let temporary: URL
        do {
            let (location, response) = try await session.download(for: request, delegate: tracker)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = try? Data(contentsOf: location)
                try? FileManager.default.removeItem(at: location)
                try Self.check(response, body: body)
            }
            temporary = location
        } catch {
            throw Self.mapTransport(error)
        }
        // Önce aynı klasöre geçici adla; yarım dosya "tam" sanılmasın.
        let partial = destination.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partial)
        try FileManager.default.moveItem(at: temporary, to: partial)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        await progress(1)
    }

    // MARK: Diğer

    func delete(paths: [String]) async {
        for path in paths {
            guard let request = try? await makeRequest("DELETE", "v1/o", query: ["p": path]) else { return }
            _ = try? await session.data(for: request)
        }
    }

    func acknowledge(path: String) async throws {
        _ = try await send(makeRequest("POST", "v1/ack", query: ["p": path]))
    }

    func deletePrefix(_ prefix: String) async throws {
        _ = try await send(makeRequest("DELETE", "v1/prefix", query: ["p": prefix]))
    }

    func usage() async throws -> MediaUsage {
        try await JSONDecoder().decode(MediaUsage.self, from: send(makeRequest("GET", "v1/usage")))
    }

    func cleanup() async throws -> MediaCleanupResult {
        try await JSONDecoder().decode(MediaCleanupResult.self, from: send(makeRequest("POST", "v1/cleanup")))
    }

    func publicURL(for path: String) -> URL? {
        baseURL?.appendingPathComponent("v1/public").appendingPathComponent(path)
    }
}

extension MediaServerClient: CallServerProviding {
    private struct IceResponse: Decodable { var iceServers: [IceServer] }

    /// TURN kimlik bilgileri sunucuda üretilir (kısa ömürlü); uygulamaya gömülmez.
    func iceServers() async throws -> [IceServer] {
        let data = try await send(makeRequest("GET", "v1/turn"))
        let servers = try JSONDecoder().decode(IceResponse.self, from: data).iceServers.filter { !$0.urls.isEmpty }
        return servers.isEmpty ? IceServer.fallback : servers
    }

    func ring(chatID: String, callID: String) async throws {
        let body = try JSONEncoder().encode(["chatId": chatID, "callId": callID])
        _ = try await send(makeRequest("POST", "v1/call", headers: ["Content-Type": "application/json"]), body: body)
    }
}

extension MediaServerClient: ChatNotifying {
    func notify(chatID: String, messageID: String) async throws {
        let body = try JSONEncoder().encode(["chatId": chatID, "messageId": messageID])
        _ = try await send(makeRequest("POST", "v1/notify", headers: ["Content-Type": "application/json"]), body: body)
    }
}

/// Görevin `Progress` nesnesini izler; değer %1'den fazla değişince ana iş parçacığında bildirir.
private final class TransferProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let handler: @MainActor (Double) -> Void
    private let lock = NSLock()
    private var observation: NSKeyValueObservation?
    private var last: Double = -1

    init(_ handler: @escaping @MainActor (Double) -> Void) {
        self.handler = handler
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let observation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            self?.report(progress.fractionCompleted)
        }
        lock.withLock { self.observation = observation }
    }

    private func report(_ value: Double) {
        let shouldReport: Bool = lock.withLock {
            guard value - last >= 0.01 || value >= 1 else { return false }
            last = value
            return true
        }
        guard shouldReport else { return }
        let handler = handler
        Task { @MainActor in handler(min(value, 0.99)) }
    }
}
