import Foundation
import UniformTypeIdentifiers

// MARK: - Medya bilgisi (mesajla birlikte Firestore'da)

enum ChatMediaQuality: String, Codable, CaseIterable, Identifiable {
    /// Dosya olduğu gibi gider (HEIC/HEVC korunur, yeniden sıkıştırılmaz).
    case original
    /// Fotoğraf 2048 px JPEG, video 720p MP4: daha küçük, daha hızlı.
    case fast

    var id: Self { self }

    var title: String {
        switch self {
        case .original: return "Orijinal"
        case .fast: return "Hızlı"
        }
    }

    var detail: String {
        switch self {
        case .original: return "Kalite kaybı yok, dosya olduğu gibi gider."
        case .fast: return "Daha küçük dosya, daha hızlı gönderim."
        }
    }
}

enum ChatMediaStatus: String, Codable {
    /// Küçük önizleme yüklendi, orijinal dosya hâlâ yükleniyor.
    case uploading
    /// Orijinal dosya hazır.
    case ready
}

struct ChatMedia: Codable, Equatable, Hashable {
    var originalPath: String
    var thumbnailPath: String
    var contentType: String
    var fileExtension: String
    var byteSize: Int64
    var width: Int
    var height: Int
    /// Video süresi (saniye).
    var duration: Double?
    var quality: ChatMediaQuality
    var status: ChatMediaStatus

    /// Baloncukta yer ayırmak için en-boy oranı (bilinmiyorsa kare).
    var aspectRatio: Double {
        guard width > 0, height > 0 else { return 1 }
        return Double(width) / Double(height)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    var formattedDuration: String? {
        guard let duration, duration.isFinite else { return nil }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Storage yolları

/// `chats/{chatId}/media/{messageId}/thumb.jpg` ve `.../original.<uzantı>`; Storage kuralları aynı biçimi bekler.
enum ChatMediaPath {
    static func folder(chatID: String, messageID: String) -> String {
        "\(Constants.Collection.chats)/\(chatID)/media/\(messageID)"
    }

    static func thumbnail(chatID: String, messageID: String) -> String {
        folder(chatID: chatID, messageID: messageID) + "/thumb.jpg"
    }

    static func original(chatID: String, messageID: String, fileExtension: String) -> String {
        folder(chatID: chatID, messageID: messageID) + "/original.\(sanitizedExtension(fileExtension))"
    }

    /// Kurallar 2–5 harf/rakamlık uzantı kabul eder.
    static func sanitizedExtension(_ ext: String) -> String {
        let cleaned = ext.lowercased().filter { $0.isLetter || $0.isNumber }
        guard (2...5).contains(cleaned.count) else { return "bin" }
        return cleaned
    }
}

enum ChatMediaKind: String, Codable {
    case image, video

    var messageType: ChatMessageType { self == .image ? .image : .video }

    /// Uzantıdan MIME türü (`heic` → `image/heic`, `mov` → `video/quicktime`).
    static func contentType(forExtension ext: String, kind: ChatMediaKind) -> String {
        if let type = UTType(filenameExtension: ext.lowercased()), let mime = type.preferredMIMEType {
            return mime
        }
        return kind == .image ? "image/jpeg" : "video/mp4"
    }
}

// MARK: - Firestore alanları (Firebase'e bağımlı değil; `Timestamp` içermez)

enum ChatMediaFields {
    static func encode(_ media: ChatMedia) -> [String: Any] {
        var fields: [String: Any] = [
            "originalPath": media.originalPath,
            "thumbnailPath": media.thumbnailPath,
            "contentType": media.contentType,
            "ext": media.fileExtension,
            "size": media.byteSize,
            "width": media.width,
            "height": media.height,
            "quality": media.quality.rawValue,
            "status": media.status.rawValue
        ]
        if let duration = media.duration { fields["duration"] = duration }
        return fields
    }

    static func decode(_ value: Any?) -> ChatMedia? {
        guard let map = value as? [String: Any],
              let original = map["originalPath"] as? String,
              let thumbnail = map["thumbnailPath"] as? String else { return nil }
        func int(_ key: String) -> Int { (map[key] as? NSNumber)?.intValue ?? 0 }
        return ChatMedia(
            originalPath: original,
            thumbnailPath: thumbnail,
            contentType: map["contentType"] as? String ?? "application/octet-stream",
            fileExtension: map["ext"] as? String ?? "bin",
            byteSize: (map["size"] as? NSNumber)?.int64Value ?? 0,
            width: int("width"),
            height: int("height"),
            duration: (map["duration"] as? NSNumber)?.doubleValue,
            quality: ChatMediaQuality(rawValue: map["quality"] as? String ?? "") ?? .original,
            status: ChatMediaStatus(rawValue: map["status"] as? String ?? "") ?? .ready
        )
    }
}

// MARK: - Yükleme aşaması (yalnızca gönderen cihazda)

enum ChatUploadStage: String, Codable, Comparable {
    /// Küçük önizleme henüz yüklenmedi.
    case thumbnail
    /// Önizleme ve mesaj belgesi hazır; orijinal dosya yükleniyor.
    case original
    /// Orijinal yüklendi, mesajı "hazır" işaretlemek kaldı.
    case finalize
    case done

    private var order: Int {
        switch self {
        case .thumbnail: return 0
        case .original: return 1
        case .finalize: return 2
        case .done: return 3
        }
    }

    static func < (lhs: ChatUploadStage, rhs: ChatUploadStage) -> Bool { lhs.order < rhs.order }
}

// MARK: - Cihazdaki dosyalar

/// Gönderilecek dosyalar Application Support'ta (yükleme bitene kadar silinmez),
/// indirilenler Caches'ta (sistem gerektiğinde temizleyebilir) tutulur.
struct ChatMediaFiles {
    let persistentRoot: URL
    let cacheRoot: URL

    static let live: ChatMediaFiles = {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ChatMediaFiles(
            persistentRoot: support.appendingPathComponent("ChatMedia", isDirectory: true),
            cacheRoot: caches.appendingPathComponent("ChatMedia", isDirectory: true)
        )
    }()

    var outgoingDirectory: URL { ensure(persistentRoot.appendingPathComponent("outgoing", isDirectory: true)) }
    var cacheDirectory: URL { ensure(cacheRoot) }

    /// Kayıtta göreli ad saklanır; uygulama güncellenince kapsayıcı yolu değişse de dosya bulunur.
    func outgoingURL(named name: String) -> URL { outgoingDirectory.appendingPathComponent(name) }

    func cachedThumbnailURL(messageID: String) -> URL {
        cacheDirectory.appendingPathComponent("\(messageID)-thumb.jpg")
    }

    /// İndirilen ve gönderilen orijaller kalıcı klasörde tutulur: buluttaki kopya 60 gün sonra silinebilir,
    /// iOS'un yer açmak için temizlediği önbellekte durmamalı.
    var originalsDirectory: URL { ensure(persistentRoot.appendingPathComponent("originals", isDirectory: true)) }

    /// Orijal dosyanın kalıcı konumu. Eski sürümün önbelleğe indirdiği dosya varsa buraya taşınır.
    func originalURL(messageID: String, fileExtension: String) -> URL {
        let name = "\(messageID).\(ChatMediaPath.sanitizedExtension(fileExtension))"
        let url = originalsDirectory.appendingPathComponent(name)
        let legacy = cacheRoot.appendingPathComponent(name)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: url)
        }
        return url
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func remove(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: persistentRoot)
        try? FileManager.default.removeItem(at: cacheRoot)
    }

    @discardableResult
    private func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - Seçilen / hazırlanan medya

/// Galeriden ya da kameradan gelen, uygulamanın geçici klasörüne kopyalanmış dosya.
struct PickedMedia: Identifiable, Equatable {
    let id = UUID()
    var fileURL: URL
    var kind: ChatMediaKind
}

/// Gönderime hazır dosyalar (`outgoing` klasöründe) ve bilgileri.
struct PreparedMedia: Equatable {
    var originalFileName: String
    var thumbnailFileName: String
    var contentType: String
    var fileExtension: String
    var byteSize: Int64
    var width: Int
    var height: Int
    var duration: Double?
}
