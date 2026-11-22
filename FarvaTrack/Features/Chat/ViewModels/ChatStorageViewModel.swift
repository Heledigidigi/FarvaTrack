import Foundation
import Observation

/// Ayarlar → Sohbet depolaması: buluttaki kullanım ve elle temizlik.
@MainActor @Observable
final class ChatStorageViewModel {
    private(set) var usage: MediaUsage?
    private(set) var isLoading = false
    private(set) var isCleaning = false
    var errorMessage: String?
    var resultMessage: String?

    @ObservationIgnored private let media: ChatMediaStoring

    init(media: ChatMediaStoring) {
        self.media = media
    }

    convenience init() {
        self.init(media: MediaServerClient())
    }

    var usageText: String {
        guard let usage else { return "—" }
        return "\(Self.format(usage.usedBytes)) / \(Self.format(usage.limitBytes))"
    }

    var originalsText: String? {
        guard let usage else { return nil }
        return "Orijal fotoğraf ve videolar: \(Self.format(usage.originalBytes))"
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            usage = try await media.usage()
            errorMessage = nil
        } catch {
            errorMessage = AppError.map(error).errorDescription
        }
    }

    func cleanNow() async {
        isCleaning = true
        defer { isCleaning = false }
        do {
            let result = try await media.cleanup()
            if result.deleted == 0 {
                resultMessage = "Silinecek orijal yok. Yalnızca karşı tarafın aldığı ve 60 günü geçen (ya da yer dolunca en eski) orijaller silinir."
            } else {
                resultMessage = "\(result.deleted) orijal buluttan kaldırıldı. Cihazlardaki kopyalar duruyor."
            }
            if result.waitingBytes > 0 {
                resultMessage? += " Karşı tarafın henüz almadığı \(Self.format(result.waitingBytes)) bekliyor."
            }
            Haptics.success()
            await load()
        } catch {
            errorMessage = AppError.map(error).errorDescription
            Haptics.error()
        }
    }
}
