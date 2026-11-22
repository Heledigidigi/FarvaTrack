import Foundation
import Photos

/// Fotoğraflar'a dosya ekleme. Testlerde sahte uygulamayla değiştirilir.
protocol PhotoLibrarySaving: AnyObject {
    /// Dosyayı olduğu gibi (HEIC/HEVC korunarak) ekler. İzin yoksa `AppError.notAuthorized`.
    func save(fileURL: URL, isVideo: Bool) async throws
}

final class PhotoLibrarySaver: PhotoLibrarySaving {
    func save(fileURL: URL, isVideo: Bool) async throws {
        // Yalnızca "ekleme" izni: uygulama kullanıcının fotoğraflarını göremez.
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw AppError.notAuthorized }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            request.addResource(with: isVideo ? .video : .photo, fileURL: fileURL, options: options)
        }
    }
}

/// Sohbet medya tercihleri (Ayarlar'dan değişir).
enum ChatMediaPreferences {
    static let autoSaveKey = "chat.autoSaveToPhotos"

    /// Gelen fotoğraf ve videolar Fotoğraflar'a otomatik kaydedilsin mi (varsayılan: açık).
    static func autoSaveToPhotos(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: autoSaveKey) as? Bool ?? true
    }
}
