import Foundation

// MARK: - Sinyalleşme belgesi

/// `chats/{chatId}/calls/{callId}` belgesindeki durum.
enum CallSignalStatus: String, Codable, Equatable {
    /// Arayan teklifi yazdı, karşı taraf çalıyor.
    case ringing
    /// Karşı taraf cevap verdi (yanıt SDP'si yazıldı).
    case accepted
    /// Karşı taraf reddetti.
    case declined
    /// Karşı taraf başka bir aramadaydı.
    case busy
    /// Çalma süresi doldu ya da arayan çalarken kapattı.
    case missed
    /// Konuşma bitti.
    case ended
    /// Bağlantı kurulamadı.
    case failed

    var isFinal: Bool {
        switch self {
        case .ringing, .accepted: return false
        default: return true
        }
    }
}

/// WebRTC oturum tanımı (SDP).
struct SessionDescription: Codable, Equatable {
    enum Kind: String, Codable { case offer, answer }
    var kind: Kind
    var sdp: String
}

/// ICE adayı (`calls/{callId}/candidates/{id}`).
struct CallCandidate: Codable, Equatable, Identifiable {
    var id: String
    var from: String
    var candidate: String
    var sdpMid: String?
    var sdpMLineIndex: Int32
    /// Yeniden bağlanmada (ICE restart) eski adaylar ayıklanır.
    var offerVersion: Int
}

struct CallDocument: Equatable, Identifiable {
    var id: String
    var chatID: String
    var callerID: String
    var calleeID: String
    var status: CallSignalStatus
    var offer: SessionDescription?
    var answer: SessionDescription?
    /// Her ICE yeniden başlatmada artar; karşı taraf yeni teklife yeni yanıt verir.
    var offerVersion: Int
    var answerVersion: Int
    var createdAt: Date
    var answeredAt: Date?
    var endedAt: Date?
    var endedBy: String?

    func other(than userID: String) -> String { callerID == userID ? calleeID : callerID }
}

// MARK: - Arama durumu (yerel)

enum CallDirection: Equatable { case outgoing, incoming }

enum CallEndReason: Equatable {
    /// Biri kapattı.
    case hungUp
    case declined
    case busy
    /// Cevapsız (çalma süresi doldu ya da arayan vazgeçti).
    case missed
    case failed
    /// Bu cihazdan kapatılmadan başka yerde cevaplandı / bitti.
    case remoteEnded
}

/// Arama yaşam döngüsü. Saf: geçişler `CallStateMachine` ile test edilir.
enum CallPhase: Equatable {
    case idle
    /// Giden: karşı taraf çalıyor. Gelen: bu cihaz çalıyor.
    case ringing(CallDirection)
    /// Cevaplandı, bağlantı kuruluyor.
    case connecting
    case connected(since: Date)
    /// Ağ değişti ya da koptu; ICE yeniden başlatılıyor.
    case reconnecting(since: Date)
    case ended(CallEndReason)

    var isActive: Bool {
        switch self {
        case .idle, .ended: return false
        default: return true
        }
    }

    var connectedSince: Date? {
        switch self {
        case .connected(let since), .reconnecting(let since): return since
        default: return nil
        }
    }
}

enum CallEvent: Equatable {
    case answered
    case mediaConnected(Date)
    case mediaInterrupted
    case remoteStatus(CallSignalStatus)
    case hangUp
    case ringTimeout
    case connectFailed
}

enum CallStateMachine {
    /// Geçersiz olaylar durumu değiştirmez.
    static func next(_ phase: CallPhase, _ event: CallEvent) -> CallPhase {
        switch (phase, event) {
        case (.ringing, .answered), (.ringing, .remoteStatus(.accepted)):
            return .connecting
        case (.ringing, .remoteStatus(.declined)):
            return .ended(.declined)
        case (.ringing, .remoteStatus(.busy)):
            return .ended(.busy)
        case (.ringing, .remoteStatus(.missed)), (.ringing, .ringTimeout):
            return .ended(.missed)
        case (.ringing(.outgoing), .hangUp):
            return .ended(.missed)
        case (.ringing(.incoming), .hangUp):
            return .ended(.declined)
        case (.connecting, .mediaConnected(let date)), (.ringing, .mediaConnected(let date)):
            return .connected(since: date)
        case (.reconnecting(let since), .mediaConnected):
            return .connected(since: since)
        case (.connected(let since), .mediaInterrupted):
            return .reconnecting(since: since)
        case (.connecting, .connectFailed), (.reconnecting, .connectFailed):
            return .ended(.failed)
        case (_, .hangUp) where phase.isActive:
            return .ended(.hungUp)
        case (_, .remoteStatus(let status)) where phase.isActive && status.isFinal:
            return .ended(status == .failed ? .failed : .remoteEnded)
        default:
            return phase
        }
    }
}

// MARK: - Sohbetteki arama satırı

/// Arama bitince sohbete yazılan mesajın (`type: call`) bilgisi.
struct ChatCallInfo: Codable, Equatable, Hashable {
    enum Outcome: String, Codable {
        case answered, missed, declined, busy, failed
    }

    var callID: String
    var outcome: Outcome
    /// Konuşma süresi (saniye); cevaplanmadıysa 0.
    var duration: Double

    static func outcome(for reason: CallEndReason, connected: Bool) -> Outcome {
        if connected { return .answered }
        switch reason {
        case .declined: return .declined
        case .busy: return .busy
        case .failed: return .failed
        case .missed, .hungUp, .remoteEnded: return .missed
        }
    }
}

enum CallFormat {
    /// 0:07, 2:34, 1:02:05
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    /// Sohbette ve bildirimde görünen metin.
    static func summary(_ info: ChatCallInfo, isMine: Bool) -> String {
        switch info.outcome {
        case .answered: return "📞 Sesli arama · \(duration(info.duration))"
        case .missed: return isMine ? "📞 Cevaplanmayan arama" : "📞 Cevapsız arama"
        case .declined: return isMine ? "📞 Arama reddedildi" : "📞 Reddedilen arama"
        case .busy: return "📞 Hat meşguldü"
        case .failed: return "📞 Arama bağlanamadı"
        }
    }
}

enum ChatCallFields {
    static func encode(_ info: ChatCallInfo) -> [String: Any] {
        ["callId": info.callID, "outcome": info.outcome.rawValue, "duration": info.duration]
    }

    static func decode(_ value: Any?) -> ChatCallInfo? {
        guard let map = value as? [String: Any], let id = map["callId"] as? String, !id.isEmpty,
              let raw = map["outcome"] as? String, let outcome = ChatCallInfo.Outcome(rawValue: raw) else { return nil }
        let duration = (map["duration"] as? NSNumber)?.doubleValue ?? 0
        return ChatCallInfo(callID: id, outcome: outcome, duration: max(0, duration))
    }
}

// MARK: - Ses ayarı (Opus)

enum CallAudioTuning {
    /// Konuşma için yüksek kalite: 64 kbps Opus, paket kaybına karşı FEC, sessizlikte kesme (DTX) kapalı.
    static let maxAverageBitrate = 64_000

    /// SDP'de Opus'u en öne alır ve `fmtp` satırına kalite parametrelerini yazar.
    static func tune(_ sdp: String, maxAverageBitrate: Int = maxAverageBitrate) -> String {
        let separator = sdp.contains("\r\n") ? "\r\n" : "\n"
        var lines = sdp.components(separatedBy: separator)
        guard let opusLine = lines.first(where: { $0.lowercased().hasPrefix("a=rtpmap:") && $0.lowercased().contains("opus/48000") }),
              let payload = opusLine.dropFirst("a=rtpmap:".count).split(separator: " ").first.map(String.init) else { return sdp }

        let params = ["minptime=10", "useinbandfec=1", "usedtx=0", "stereo=0", "maxaveragebitrate=\(maxAverageBitrate)"]
        if let index = lines.firstIndex(where: { $0.hasPrefix("a=fmtp:\(payload) ") }) {
            let existing = lines[index].dropFirst("a=fmtp:\(payload) ".count).split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { item in !params.contains { $0.split(separator: "=").first == item.split(separator: "=").first } }
            lines[index] = "a=fmtp:\(payload) " + (existing + params).joined(separator: ";")
        } else if let rtpmap = lines.firstIndex(of: opusLine) {
            lines.insert("a=fmtp:\(payload) " + params.joined(separator: ";"), at: rtpmap + 1)
        }

        if let mIndex = lines.firstIndex(where: { $0.hasPrefix("m=audio ") }) {
            var parts = lines[mIndex].split(separator: " ").map(String.init)
            if parts.count > 3 {
                var formats = Array(parts[3...])
                formats.removeAll { $0 == payload }
                parts = Array(parts[0..<3]) + [payload] + formats
                lines[mIndex] = parts.joined(separator: " ")
            }
        }
        return lines.joined(separator: separator)
    }
}

// MARK: - Bağlantı kalitesi

struct CallStatsSample: Equatable {
    /// Gidiş-dönüş süresi (saniye).
    var roundTripTime: Double?
    /// 0…1
    var packetLoss: Double?
    /// Saniye.
    var jitter: Double?
    var usingRelay: Bool = false
}

enum CallQuality: Int, Comparable {
    case poor, fair, good

    static func < (lhs: CallQuality, rhs: CallQuality) -> Bool { lhs.rawValue < rhs.rawValue }

    static func evaluate(_ sample: CallStatsSample) -> CallQuality {
        var quality = CallQuality.good
        func lower(to value: CallQuality) { quality = min(quality, value) }
        if let rtt = sample.roundTripTime {
            if rtt > 0.6 { lower(to: .poor) } else if rtt > 0.3 { lower(to: .fair) }
        }
        if let loss = sample.packetLoss {
            if loss > 0.08 { lower(to: .poor) } else if loss > 0.03 { lower(to: .fair) }
        }
        if let jitter = sample.jitter {
            if jitter > 0.1 { lower(to: .poor) } else if jitter > 0.04 { lower(to: .fair) }
        }
        return quality
    }

    var label: String {
        switch self {
        case .good: return "Bağlantı iyi"
        case .fair: return "Bağlantı orta"
        case .poor: return "Bağlantı zayıf"
        }
    }

    /// Gösterge çubuğu sayısı (1–3).
    var bars: Int { rawValue + 1 }
}

// MARK: - ICE sunucuları

struct IceServer: Codable, Equatable {
    var urls: [String]
    var username: String?
    var credential: String?

    init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }

    private enum CodingKeys: String, CodingKey { case urls, username, credential }

    /// Sağlayıcılar `urls` alanını dizi ya da tek metin olarak verebilir.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decode([String].self, forKey: .urls) {
            urls = list
        } else {
            urls = [try container.decode(String.self, forKey: .urls)]
        }
        username = try container.decodeIfPresent(String.self, forKey: .username)
        credential = try container.decodeIfPresent(String.self, forKey: .credential)
    }

    /// TURN yapılandırılmamışsa yalnızca ücretsiz STUN.
    static let fallback = [IceServer(urls: ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"])]
}

enum CallLimits {
    /// Bu süre içinde cevaplanmayan arama cevapsız sayılır.
    static let ringTimeout: TimeInterval = 45
    /// Bağlantı koparsa bu süre boyunca yeniden bağlanmaya çalışılır.
    static let reconnectTimeout: TimeInterval = 30
    /// Bağlantı kurulamazsa vazgeçilir.
    static let connectTimeout: TimeInterval = 30
    static let statsInterval: TimeInterval = 2
}
