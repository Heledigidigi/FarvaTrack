import Foundation
import SwiftData
import UIKit

// MARK: - Yerel önbellek

enum DietRecordKind: String, Codable {
    case program, log, note
}

/// Diyet verisinin çevrimdışı kopyası: program, öğün kaydı ve gün notu JSON olarak saklanır.
/// Kaynak Firestore'daki `dietPrograms/{id}` belgesi ve alt koleksiyonlarıdır.
@Model
final class DietRecord {
    /// "<ownerID>|<tür>|<programID>|<belge>"
    @Attribute(.unique) var key: String
    var ownerID: String
    var kindRaw: String
    var programID: String
    var docID: String
    /// Kayıt ve notlarda gün anahtarı (yyyy-MM-dd); programda boş.
    var dayKey: String
    var json: Data
    var needsSync: Bool
    var updatedAt: Date

    init(ownerID: String, kind: DietRecordKind, programID: String, docID: String, dayKey: String = "",
         json: Data, needsSync: Bool, updatedAt: Date) {
        self.key = DietRecord.makeKey(ownerID: ownerID, kind: kind, programID: programID, docID: docID)
        self.ownerID = ownerID
        self.kindRaw = kind.rawValue
        self.programID = programID
        self.docID = docID
        self.dayKey = dayKey
        self.json = json
        self.needsSync = needsSync
        self.updatedAt = updatedAt
    }

    static func makeKey(ownerID: String, kind: DietRecordKind, programID: String, docID: String) -> String {
        "\(ownerID)|\(kind.rawValue)|\(programID)|\(docID)"
    }

    var kind: DietRecordKind { DietRecordKind(rawValue: kindRaw) ?? .program }

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? DietJSON.decoder.decode(type, from: json)
    }

    var program: DietProgram? { kind == .program ? decode(DietProgram.self) : nil }
    var log: DietMealLog? { kind == .log ? decode(DietMealLog.self) : nil }
    var note: DietDayNote? { kind == .note ? decode(DietDayNote.self) : nil }
}

enum DietJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

// MARK: - Öğün fotoğrafları (cihazda)

/// Kendi fotoğraflarım Application Support'ta (yüklenene kadar ve sonrasında), indirilenler Caches'ta.
struct DietPhotoFiles {
    let root: URL
    let cache: URL

    static let live: DietPhotoFiles = {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let caches = (try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return DietPhotoFiles(root: support.appendingPathComponent("DietPhotos", isDirectory: true),
                              cache: caches.appendingPathComponent("DietPhotos", isDirectory: true))
    }()

    /// Sunucu yolu (`diet/{program}/{ad}.jpg`) → yerel dosya. Önce kendi kopyam, yoksa önbellek.
    func localURL(for path: String) -> URL? {
        let own = root.appendingPathComponent(Self.fileName(path))
        if FileManager.default.fileExists(atPath: own.path) { return own }
        let cached = cache.appendingPathComponent(Self.fileName(path))
        return FileManager.default.fileExists(atPath: cached.path) ? cached : nil
    }

    func ownURL(for path: String) -> URL { root.appendingPathComponent(Self.fileName(path)) }
    func cacheURL(for path: String) -> URL { cache.appendingPathComponent(Self.fileName(path)) }

    static func fileName(_ path: String) -> String { path.replacingOccurrences(of: "/", with: "_") }

    static func path(programID: String) -> String { "diet/\(programID)/\(UUID().uuidString.lowercased()).jpg" }

    /// Fotoğrafı 1600 px genişliğe küçültüp JPEG olarak kaydeder.
    func save(_ image: UIImage, path: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = ownURL(for: path)
        guard let data = Self.jpeg(image) else { throw AppError.invalidInput("Fotoğraf kaydedilemedi.") }
        try data.write(to: url, options: .atomic)
        return url
    }

    func remove(_ path: String) {
        try? FileManager.default.removeItem(at: ownURL(for: path))
        try? FileManager.default.removeItem(at: cacheURL(for: path))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: cache)
    }

    static func jpeg(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.82) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
