import Foundation

// MARK: - Sesli mesaj bilgisi (mesajla birlikte Firestore'da)

struct ChatAudio: Codable, Equatable, Hashable {
    var path: String
    var contentType: String
    var byteSize: Int64
    var duration: Double
    /// 0…255 arası, `VoiceWaveform.barCount` çubuk. Hem kayıtta hem baloncukta aynı görünür.
    var waveform: [UInt8]

    var formattedDuration: String { VoiceFormat.time(duration) }
}

enum ChatAudioPath {
    static let fileName = "voice.m4a"
    static let fileExtension = "m4a"
    static let contentType = "audio/mp4"

    static func voice(chatID: String, messageID: String) -> String {
        ChatMediaPath.folder(chatID: chatID, messageID: messageID) + "/" + fileName
    }
}

/// Firestore alanları (Firebase'e bağımlı değil).
enum ChatAudioFields {
    static func encode(_ audio: ChatAudio) -> [String: Any] {
        [
            "path": audio.path,
            "contentType": audio.contentType,
            "size": audio.byteSize,
            "duration": audio.duration,
            "waveform": audio.waveform.map { Int($0) }
        ]
    }

    static func decode(_ value: Any?) -> ChatAudio? {
        guard let map = value as? [String: Any], let path = map["path"] as? String else { return nil }
        let bars = (map["waveform"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        return ChatAudio(
            path: path,
            contentType: map["contentType"] as? String ?? ChatAudioPath.contentType,
            byteSize: (map["size"] as? NSNumber)?.int64Value ?? 0,
            duration: (map["duration"] as? NSNumber)?.doubleValue ?? 0,
            waveform: bars.map { UInt8(clamping: $0) }
        )
    }
}

// MARK: - Dalga formu

enum VoiceWaveform {
    /// Mesajda gösterilen çubuk sayısı.
    static let barCount = 48
    /// Bu desibelin altı sessizlik sayılır.
    static let floorDecibels: Float = -50

    /// `AVAudioRecorder.averagePower` (dBFS, genelde -160…0) → 0…1.
    static func level(fromDecibels decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }
        if decibels <= floorDecibels { return 0 }
        if decibels >= 0 { return 1 }
        // Kulağa daha doğal gelsin diye doğrusal genliğe çevrilip hafifçe yükseltilir.
        let linear = powf(10, decibels / 20)
        let floor = powf(10, floorDecibels / 20)
        return min(1, max(0, (linear - floor) / (1 - floor)).squareRoot())
    }

    /// Kayıt boyunca toplanan seviyeler → sabit sayıda çubuk (her dilimin en yüksek değeri), 0…255.
    static func bars(from levels: [Float], count: Int = barCount) -> [UInt8] {
        guard count > 0 else { return [] }
        guard !levels.isEmpty else { return Array(repeating: 0, count: count) }
        var result: [UInt8] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let start = index * levels.count / count
            let end = max(start + 1, (index + 1) * levels.count / count)
            let slice = levels[min(start, levels.count - 1)..<min(end, levels.count)]
            let peak = slice.max() ?? 0
            result.append(UInt8(clamping: Int((min(max(peak, 0), 1) * 255).rounded())))
        }
        return result
    }

    /// Kayıt sırasında canlı gösterim için son `count` seviye (eksikse başı sıfırla doldurulur).
    static func recent(_ levels: [Float], count: Int) -> [Float] {
        let tail = Array(levels.suffix(count))
        return Array(repeating: 0, count: max(0, count - tail.count)) + tail
    }
}

enum VoiceFormat {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Oynatma hızı

enum VoiceRate: Float, CaseIterable, Codable {
    case normal = 1
    case fast = 1.5
    case double = 2

    var title: String {
        switch self {
        case .normal: return "1x"
        case .fast: return "1,5x"
        case .double: return "2x"
        }
    }

    var next: VoiceRate {
        switch self {
        case .normal: return .fast
        case .fast: return .double
        case .double: return .normal
        }
    }
}

// MARK: - Kaydedilen ses

/// Kaydı biten, gönderilmeyi bekleyen dosya.
struct RecordedVoice: Equatable {
    var fileURL: URL
    var duration: Double
    var waveform: [UInt8]
}
