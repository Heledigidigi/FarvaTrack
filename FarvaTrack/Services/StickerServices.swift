import Foundation
import CoreGraphics
import CoreVideo
import Vision
import FirebaseStorage

// MARK: - Arka plan kaldırma

protocol StickerSegmenting {
    /// Ön plandaki öznelerin (insan, hayvan, nesne) maskesi; görüntüyle aynı boyutta.
    func foregroundMask(for image: CGImage) async throws -> StickerMask
}

enum StickerSegmentationError: LocalizedError {
    case noSubject
    case unavailable

    var errorDescription: String? {
        switch self {
        case .noSubject: return "Fotoğrafta belirgin bir özne bulunamadı. Silgiyle arka planı elle temizleyebilirsin."
        case .unavailable: return "Bu cihazda otomatik arka plan kaldırma kullanılamıyor. Silgiyle elle düzenleyebilirsin."
        }
    }
}

/// `VNGenerateForegroundInstanceMaskRequest` (iOS 17): tamamen cihaz üzerinde çalışır, fotoğraf hiçbir yere gönderilmez.
struct VisionStickerSegmenter: StickerSegmenting {
    func foregroundMask(for image: CGImage) async throws -> StickerMask {
        try await Task.detached(priority: .userInitiated) {
            try Self.segment(image)
        }.value
    }

    private static func segment(_ image: CGImage) throws -> StickerMask {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Simülatörde ve eski cihazlarda istek desteklenmeyebilir.
            throw StickerSegmentationError.unavailable
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw StickerSegmentationError.noSubject
        }
        // Tüm özneler birlikte; maske görüntü çözünürlüğüne ölçeklenir (yumuşak kenarlı, 0…1).
        let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        return try mask(from: buffer, width: image.width, height: image.height)
    }

    /// Tek kanallı float/8 bit piksel tamponu → 0…255 maske.
    static func mask(from buffer: CVPixelBuffer, width: Int, height: Int) throws -> StickerMask {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw StickerSegmentationError.unavailable }
        let bufferWidth = CVPixelBufferGetWidth(buffer)
        let bufferHeight = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)

        var mask = StickerMask(width: width, height: height, fill: 0)
        for y in 0..<height {
            let sourceY = min(bufferHeight - 1, y * bufferHeight / max(height, 1))
            let row = base.advanced(by: sourceY * rowBytes)
            for x in 0..<width {
                let sourceX = min(bufferWidth - 1, x * bufferWidth / max(width, 1))
                let value: Float
                switch format {
                case kCVPixelFormatType_OneComponent32Float:
                    value = row.assumingMemoryBound(to: Float.self)[sourceX]
                default:
                    value = Float(row.assumingMemoryBound(to: UInt8.self)[sourceX]) / 255
                }
                mask[x, y] = UInt8(clamping: Int((min(max(value, 0), 1) * 255).rounded()))
            }
        }
        return mask
    }
}

// MARK: - Sticker deposu (Storage + Firestore)

/// `users/{uid}/stickers/{id}` belgesi.
struct StickerDTO: Codable, Equatable, Identifiable {
    var id: String
    var storagePath: String
    var width: Int
    var height: Int
    var createdAt: Date
    var updatedAt: Date
}

protocol StickerSyncing: AnyObject {
    func upload(pngAt fileURL: URL, sticker: StickerDTO, userID: String) async throws
    func fetchAll(userID: String) async throws -> [StickerDTO]
    func download(sticker: StickerDTO, to destination: URL) async throws
    func delete(sticker id: String, storagePath: String, userID: String) async throws
    /// Hesap silinirken tüm sticker dosyaları.
    func purge(userID: String) async throws
}

enum StickerPath {
    static func storage(userID: String, stickerID: String) -> String {
        "\(Constants.Collection.users)/\(userID)/\(Constants.Collection.stickers)/\(stickerID).png"
    }
}

final class StickerService: StickerSyncing {
    private let client = FirestoreCollectionClient(collectionName: Constants.Collection.stickers)
    private let media: ChatMediaStoring

    init(media: ChatMediaStoring = ChatMediaStorage()) {
        self.media = media
    }

    func upload(pngAt fileURL: URL, sticker: StickerDTO, userID: String) async throws {
        // Önce dosya, sonra belge: diğer cihaz belgeyi görünce dosya hazırdır.
        try await media.upload(fileURL: fileURL, to: sticker.storagePath, contentType: "image/png", senderID: userID, progress: { _ in })
        try await client.upload(sticker, id: sticker.id, userID: userID)
    }

    func fetchAll(userID: String) async throws -> [StickerDTO] {
        try await client.fetchAll(StickerDTO.self, userID: userID)
    }

    func download(sticker: StickerDTO, to destination: URL) async throws {
        try await media.download(path: sticker.storagePath, to: destination, progress: { _ in })
    }

    func delete(sticker id: String, storagePath: String, userID: String) async throws {
        try await client.delete(id: id, userID: userID)
        await media.delete(paths: [storagePath])
    }

    func purge(userID: String) async throws {
        guard FirebaseBootstrap.isConfigured else { return }
        let folder = Storage.storage().reference(withPath: "\(Constants.Collection.users)/\(userID)/\(Constants.Collection.stickers)")
        let list = try await folder.listAll()
        for item in list.items { try? await item.delete() }
    }
}
