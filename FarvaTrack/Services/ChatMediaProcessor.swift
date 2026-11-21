import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Seçilen dosyayı gönderime hazırlar: küçük önizleme üretir ve (Hızlı modda) küçültür.
protocol ChatMediaProcessing {
    func prepare(_ media: PickedMedia, quality: ChatMediaQuality, messageID: String, directory: URL) async throws -> PreparedMedia
}

struct ChatMediaProcessor: ChatMediaProcessing {
    /// Sohbetteki önizlemenin uzun kenarı.
    static let thumbnailMaxPixel: CGFloat = 480
    /// Hızlı modda fotoğrafın uzun kenarı.
    static let fastImageMaxPixel: CGFloat = 2048

    func prepare(_ media: PickedMedia, quality: ChatMediaQuality, messageID: String, directory: URL) async throws -> PreparedMedia {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        switch media.kind {
        case .image: return try prepareImage(media.fileURL, quality: quality, messageID: messageID, directory: directory)
        case .video: return try await prepareVideo(media.fileURL, quality: quality, messageID: messageID, directory: directory)
        }
    }

    // MARK: Fotoğraf

    private func prepareImage(_ source: URL, quality: ChatMediaQuality, messageID: String, directory: URL) throws -> PreparedMedia {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw AppError.invalidInput("Fotoğraf okunamadı.")
        }

        let ext: String
        let originalURL: URL
        switch quality {
        case .original:
            // Bayt bayt kopya: HEIC, ProRAW, PNG… ne geldiyse o gider.
            ext = ChatMediaPath.sanitizedExtension(source.pathExtension.isEmpty ? "jpg" : source.pathExtension)
            originalURL = directory.appendingPathComponent("\(messageID).\(ext)")
            try copyReplacing(source, to: originalURL)
        case .fast:
            ext = "jpg"
            originalURL = directory.appendingPathComponent("\(messageID).jpg")
            try writeJPEG(from: imageSource, maxPixel: Self.fastImageMaxPixel, quality: 0.82, to: originalURL)
        }

        let thumbURL = directory.appendingPathComponent("\(messageID)-thumb.jpg")
        try writeJPEG(from: imageSource, maxPixel: Self.thumbnailMaxPixel, quality: 0.7, to: thumbURL)

        let size = Self.orientedPixelSize(of: CGImageSourceCreateWithURL(originalURL as CFURL, nil) ?? imageSource)
        return PreparedMedia(
            originalFileName: originalURL.lastPathComponent,
            thumbnailFileName: thumbURL.lastPathComponent,
            contentType: ChatMediaKind.contentType(forExtension: ext, kind: .image),
            fileExtension: ext,
            byteSize: Self.fileSize(originalURL),
            width: Int(size.width),
            height: Int(size.height),
            duration: nil
        )
    }

    /// Yönü (EXIF) uygulanmış, en fazla `maxPixel` boyutlu JPEG.
    private func writeJPEG(from source: CGImageSource, maxPixel: CGFloat, quality: CGFloat, to url: URL) throws {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AppError.invalidInput("Fotoğraf işlenemedi.")
        }
        try writeJPEG(image, quality: quality, to: url)
    }

    private func writeJPEG(_ image: CGImage, quality: CGFloat, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AppError.storage("Önizleme dosyası yazılamadı.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AppError.storage("Önizleme dosyası yazılamadı.") }
    }

    static func orientedPixelSize(of source: CGImageSource) -> CGSize {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return .zero }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        // 5…8: 90° döndürülmüş; genişlik ve yükseklik yer değiştirir.
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    // MARK: Video

    private func prepareVideo(_ source: URL, quality: ChatMediaQuality, messageID: String, directory: URL) async throws -> PreparedMedia {
        let ext: String
        let originalURL: URL
        switch quality {
        case .original:
            // HEVC/MOV olduğu gibi kopyalanır.
            ext = ChatMediaPath.sanitizedExtension(source.pathExtension.isEmpty ? "mov" : source.pathExtension)
            originalURL = directory.appendingPathComponent("\(messageID).\(ext)")
            try copyReplacing(source, to: originalURL)
        case .fast:
            ext = "mp4"
            originalURL = directory.appendingPathComponent("\(messageID).mp4")
            try await exportFast(source, to: originalURL)
        }

        let asset = AVURLAsset(url: originalURL)
        let duration = try await asset.load(.duration).seconds
        var size = CGSize.zero
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            size = CGSize(width: abs(rect.width), height: abs(rect.height))
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Self.thumbnailMaxPixel, height: Self.thumbnailMaxPixel)
        let frameTime = CMTime(seconds: min(0.5, max(duration / 2, 0)), preferredTimescale: 600)
        let (frame, _) = try await generator.image(at: frameTime)
        let thumbURL = directory.appendingPathComponent("\(messageID)-thumb.jpg")
        try writeJPEG(frame, quality: 0.7, to: thumbURL)

        return PreparedMedia(
            originalFileName: originalURL.lastPathComponent,
            thumbnailFileName: thumbURL.lastPathComponent,
            contentType: ChatMediaKind.contentType(forExtension: ext, kind: .video),
            fileExtension: ext,
            byteSize: Self.fileSize(originalURL),
            width: Int(size.width.rounded()),
            height: Int(size.height.rounded()),
            duration: duration.isFinite ? duration : nil
        )
    }

    private func exportFast(_ source: URL, to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw AppError.invalidInput("Video küçültülemedi.")
        }
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { continuation.resume() }
            }
        } onCancel: {
            session.cancelExport()
        }
        try Task.checkCancellation()
        guard session.status == .completed else {
            throw AppError.invalidInput(session.error?.localizedDescription ?? "Video küçültülemedi.")
        }
    }

    // MARK: Yardımcılar

    private func copyReplacing(_ source: URL, to destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
