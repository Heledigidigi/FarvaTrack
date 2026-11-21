import Foundation
import FirebaseStorage

/// Sohbet fotoğraf/videolarının Firebase Storage işlemleri. Testlerde sahte uygulamayla değiştirilir.
protocol ChatMediaStoring: AnyObject {
    /// Dosyayı yükler. İlerleme 0…1 arası bildirilir. `Task` iptal edilirse yükleme de iptal olur.
    func upload(fileURL: URL, to path: String, contentType: String, senderID: String,
                progress: @escaping @MainActor (Double) -> Void) async throws
    /// Dosyayı `destination` konumuna indirir.
    func download(path: String, to destination: URL,
                  progress: @escaping @MainActor (Double) -> Void) async throws
    /// En iyi çabayla siler (dosya yoksa hata sayılmaz).
    func delete(paths: [String]) async
}

final class ChatMediaStorage: ChatMediaStoring {
    private var storage: Storage {
        get throws {
            guard FirebaseBootstrap.isConfigured else { throw AppError.firebaseNotConfigured }
            let storage = Storage.storage()
            // Bağlantı koptuğunda SDK yüklemeyi bu süre boyunca kaldığı yerden sürdürür.
            storage.maxUploadRetryTime = 60 * 60
            storage.maxDownloadRetryTime = 10 * 60
            return storage
        }
    }

    func upload(fileURL: URL, to path: String, contentType: String, senderID: String,
                progress: @escaping @MainActor (Double) -> Void) async throws {
        let reference = try storage.reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        // Storage kuralları yükleyenin gönderen olduğunu bu alanla doğrular.
        metadata.customMetadata = ["senderId": senderID]

        try Task.checkCancellation()
        let holder = TaskHolder()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // `putFile`, Storage'ın parça parça (resumable) yükleme protokolünü kullanır;
                // dosya bellekte tutulmaz, büyük videolarda da güvenlidir.
                let task = reference.putFile(from: fileURL, metadata: metadata)
                holder.attach { task.cancel() }
                let once = OnceFlag()
                task.observe(.progress) { snapshot in
                    guard let value = snapshot.progress?.fractionCompleted else { return }
                    Task { @MainActor in progress(value) }
                }
                task.observe(.success) { _ in
                    guard once.claim() else { return }
                    Task { @MainActor in progress(1) }
                    continuation.resume()
                }
                task.observe(.failure) { snapshot in
                    guard once.claim() else { return }
                    continuation.resume(throwing: ChatMediaStorage.map(snapshot.error))
                }
                if holder.isCancelled { task.cancel() }
            }
        } onCancel: {
            holder.cancel()
        }
    }

    func download(path: String, to destination: URL,
                  progress: @escaping @MainActor (Double) -> Void) async throws {
        let reference = try storage.reference(withPath: path)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Önce geçici dosyaya; yarım inen dosya önbellekte "tam" sanılmasın.
        let partial = destination.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partial)

        let holder = TaskHolder()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = reference.write(toFile: partial)
                holder.attach { task.cancel() }
                let once = OnceFlag()
                task.observe(.progress) { snapshot in
                    guard let value = snapshot.progress?.fractionCompleted else { return }
                    Task { @MainActor in progress(value) }
                }
                task.observe(.success) { _ in
                    guard once.claim() else { return }
                    continuation.resume()
                }
                task.observe(.failure) { snapshot in
                    guard once.claim() else { return }
                    continuation.resume(throwing: ChatMediaStorage.map(snapshot.error))
                }
                if holder.isCancelled { task.cancel() }
            }
        } onCancel: {
            holder.cancel()
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
    }

    func delete(paths: [String]) async {
        guard let storage = try? storage else { return }
        for path in paths {
            try? await storage.reference(withPath: path).delete()
        }
    }

    /// Storage hatalarını uygulama hatalarına çevirir.
    static func map(_ error: Error?) -> Error {
        guard let error else { return AppError.unknown("Dosya aktarımı tamamlanamadı.") }
        let nsError = error as NSError
        if nsError.domain == StorageErrorDomain {
            switch StorageErrorCode(rawValue: nsError.code) {
            case .cancelled: return CancellationError()
            case .retryLimitExceeded: return AppError.network
            case .unauthenticated: return AppError.notAuthenticated
            case .unauthorized: return AppError.notAuthorized
            case .objectNotFound: return AppError.storage("Dosya bulunamadı. Gönderen silmiş olabilir.")
            case .quotaExceeded: return AppError.storage("Depolama kotası doldu.")
            default: break
            }
        }
        return AppError.map(error)
    }
}

/// İptal isteği, Storage görevi oluşmadan gelirse de kaybolmasın.
private final class TaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelAction: (() -> Void)?
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    /// Görev oluşunca iptal yöntemi kaydedilir.
    func attach(_ cancel: @escaping () -> Void) {
        lock.withLock { cancelAction = cancel }
    }

    func cancel() {
        let action: (() -> Void)? = lock.withLock {
            cancelled = true
            return cancelAction
        }
        action?()
    }
}

/// Devamın (continuation) yalnızca bir kez sürdürülmesi için.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}
