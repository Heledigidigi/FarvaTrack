import Foundation
import FirebaseFirestore

/// Baloncuk stillerinin sunucu işlemleri. Belge: `users/{uid}/bubbles/{styleId}` (`json`, `version`, `updatedAt`);
/// dosyalar: `users/{uid}/bubbles/{styleId}/{assetId}.png`. Sohbet arkadaşı okuyabilir, yalnızca sahibi yazar.
protocol BubbleSyncing: AnyObject {
    func save(_ style: BubbleStyle, userID: String) async throws
    func uploadAsset(_ fileURL: URL, styleID: String, assetID: String, userID: String) async throws
    /// Başka bir kullanıcının (sohbet arkadaşının) stili.
    func fetch(styleID: String, ownerID: String) async throws -> BubbleStyle?
    /// Kendi stillerimiz (diğer cihazda eklenenler için).
    func fetchAll(userID: String) async throws -> [BubbleStyle]
    func downloadAsset(styleID: String, assetID: String, ownerID: String, to destination: URL) async throws
    func delete(styleID: String, userID: String) async throws
    func purge(userID: String) async throws
}

enum BubblePath {
    static func document(userID: String, styleID: String) -> String {
        "\(Constants.Collection.users)/\(userID)/\(Constants.Collection.bubbles)/\(styleID)"
    }

    static func asset(userID: String, styleID: String, assetID: String) -> String {
        "\(document(userID: userID, styleID: styleID))/\(assetID).png"
    }

    static func folder(userID: String) -> String {
        "\(Constants.Collection.users)/\(userID)/\(Constants.Collection.bubbles)"
    }
}

final class BubbleService: BubbleSyncing {
    private let media: ChatMediaStoring

    init(media: ChatMediaStoring = MediaServerClient()) {
        self.media = media
    }

    private var db: Firestore {
        get throws {
            guard FirebaseBootstrap.isConfigured else { throw AppError.firebaseNotConfigured }
            return Firestore.firestore()
        }
    }

    private func collection(_ userID: String) throws -> CollectionReference {
        try db.collection(Constants.Collection.users).document(userID).collection(Constants.Collection.bubbles)
    }

    func save(_ style: BubbleStyle, userID: String) async throws {
        do {
            let json = String(data: try style.jsonData(), encoding: .utf8) ?? "{}"
            try await collection(userID).document(style.id).setData([
                "json": json,
                "version": style.version,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        } catch {
            throw AppError.map(error)
        }
    }

    func uploadAsset(_ fileURL: URL, styleID: String, assetID: String, userID: String) async throws {
        try await media.upload(fileURL: fileURL, to: BubblePath.asset(userID: userID, styleID: styleID, assetID: assetID),
                               contentType: "image/png", senderID: userID, progress: { _ in })
    }

    func fetch(styleID: String, ownerID: String) async throws -> BubbleStyle? {
        do {
            let snapshot = try await collection(ownerID).document(styleID).getDocument()
            return Self.decode(id: snapshot.documentID, data: snapshot.data())
        } catch {
            throw AppError.map(error)
        }
    }

    func fetchAll(userID: String) async throws -> [BubbleStyle] {
        do {
            let snapshot = try await collection(userID).getDocuments()
            return snapshot.documents.compactMap { Self.decode(id: $0.documentID, data: $0.data()) }
        } catch {
            throw AppError.map(error)
        }
    }

    func downloadAsset(styleID: String, assetID: String, ownerID: String, to destination: URL) async throws {
        try await media.download(path: BubblePath.asset(userID: ownerID, styleID: styleID, assetID: assetID), to: destination, progress: { _ in })
    }

    func delete(styleID: String, userID: String) async throws {
        do {
            try await collection(userID).document(styleID).delete()
            try? await media.deletePrefix(BubblePath.document(userID: userID, styleID: styleID) + "/")
        } catch {
            throw AppError.map(error)
        }
    }

    func purge(userID: String) async throws {
        try await media.deletePrefix(BubblePath.folder(userID: userID) + "/")
    }

    /// Belge → stil; JSON'daki kimlik belge kimliğiyle, sürüm belge alanıyla eşitlenir.
    static func decode(id: String, data: [String: Any]?) -> BubbleStyle? {
        guard let data, let json = data["json"] as? String, let bytes = json.data(using: .utf8),
              var style = try? BubbleStyle.decode(json: bytes) else { return nil }
        style.id = id
        if let version = (data["version"] as? NSNumber)?.intValue { style.version = max(1, version) }
        return style
    }
}
