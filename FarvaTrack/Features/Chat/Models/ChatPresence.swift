import Foundation

// MARK: - Çevrimiçi / son görülme

/// Oda belgesindeki `presence.{uid}`: uygulama öndeyken dakikada bir "çevrimiçi" yazılır,
/// arka plana geçince `online = false` ile son görülme zamanı bırakılır.
struct ChatPresence: Codable, Equatable {
    var online: Bool
    /// Son sinyal (çevrimiçiyken) ya da uygulamadan çıkış zamanı.
    var at: Date

    /// Uygulama öndeyken bu aralıkla yenilenir.
    static let heartbeat: TimeInterval = 60
    /// Son sinyal bundan eskiyse (uygulama kapandı ama "çıktım" yazılamadı) çevrimdışı sayılır.
    static let staleAfter: TimeInterval = 150

    /// Gerçekten çevrimiçi mi (sinyal tazeyse).
    func isOnline(now: Date) -> Bool {
        online && now.timeIntervalSince(at) < Self.staleAfter && now.timeIntervalSince(at) > -Self.staleAfter
    }
}

/// Başlık altında gösterilen durum.
enum ChatPresenceStatus: Equatable {
    case online
    case lastSeen(Date)
    /// Karşı taraf henüz bu özelliği destekleyen sürümü açmadı.
    case unknown

    static func of(_ presence: ChatPresence?, now: Date) -> ChatPresenceStatus {
        guard let presence else { return .unknown }
        return presence.isOnline(now: now) ? .online : .lastSeen(presence.at)
    }

    var isOnline: Bool { self == .online }

    /// "çevrimiçi", "son görülme bugün 14:32", "son görülme dün 21:05", "son görülme 12 Kas 09:10".
    func text(now: Date, calendar: Calendar = .current) -> String? {
        switch self {
        case .online:
            return "çevrimiçi"
        case .unknown:
            return nil
        case .lastSeen(let date):
            let time = ChatDateText.time(date)
            if now.timeIntervalSince(date) < 60 { return "son görülme az önce" }
            if calendar.isDate(date, inSameDayAs: now) { return "son görülme bugün \(time)" }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
                return "son görülme dün \(time)"
            }
            return "son görülme \(ChatDateText.dayMonth(date, now: now, calendar: calendar)) \(time)"
        }
    }
}

/// Sohbetteki tarih/saat metinleri (Türkçe).
enum ChatDateText {
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(ChatText.turkish))
    }

    /// "12 Kas" (bu yıl) ya da "12 Kas 2025".
    static func dayMonth(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.day().month(.abbreviated).locale(ChatText.turkish))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year().locale(ChatText.turkish))
    }

    /// Bilgi ekranı: "Bugün 14:32", "Dün 21:05", "12 Kas 09:10".
    static func full(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Bugün \(time(date))" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Dün \(time(date))"
        }
        return "\(dayMonth(date, now: now, calendar: calendar)) \(time(date))"
    }
}

// MARK: - Mesaj bilgisi (uzun bas → Bilgi)

/// WhatsApp'taki "Mesaj bilgisi": gönderildi / iletildi / görüldü (sesli mesajda dinlendi).
struct ChatMessageInfo: Equatable {
    struct Row: Equatable {
        let title: String
        let systemImage: String
        /// `nil`: henüz olmadı.
        let date: Date?
    }

    let rows: [Row]

    init(message: ChatMessageDTO, isMine: Bool, isSending: Bool) {
        if !isMine {
            rows = [Row(title: "Gönderildi", systemImage: "paperplane", date: message.createdAt),
                    Row(title: "Sende görüldü", systemImage: "eye", date: message.readAt)]
            return
        }
        var rows = [Row(title: "Gönderildi", systemImage: "paperplane", date: isSending ? nil : message.createdAt)]
        // Eski sürümden gelen okumalarda `deliveredAt` olmayabilir: okunduysa iletilmiştir.
        rows.append(Row(title: "İletildi", systemImage: "checkmark", date: message.deliveredAt ?? message.readAt))
        rows.append(Row(title: "Görüldü", systemImage: "checkmark.circle.fill", date: message.readAt))
        if message.type == .audio {
            rows.append(Row(title: "Dinlendi", systemImage: "headphones", date: message.listenedAt))
        }
        self.rows = rows
    }
}

// MARK: - Sohbet içinde bul (Ctrl+F)

/// Konuşmadaki eşleşmeler arasında yukarı (daha eski) / aşağı (daha yeni) gezinme.
/// `matches` eskiden yeniye sıralı mesaj kimlikleridir; başlangıçta en yeni eşleşme seçilir.
struct ChatFindState: Equatable {
    private(set) var matches: [String] = []
    private(set) var index: Int?

    var current: String? { index.map { matches[$0] } }
    var count: Int { matches.count }
    /// "3/12" (en yeniden sayılır: 1 = en yeni).
    var positionText: String {
        guard let index, !matches.isEmpty else { return "0/0" }
        return "\(matches.count - index)/\(matches.count)"
    }
    var canGoOlder: Bool { (index ?? 0) > 0 }
    var canGoNewer: Bool { index.map { $0 < matches.count - 1 } ?? false }

    /// Yeni sonuçlar: önceki seçim hâlâ eşleşiyorsa korunur, yoksa en yeni eşleşme seçilir.
    mutating func update(matches newMatches: [String]) {
        let previous = current
        matches = newMatches
        if newMatches.isEmpty {
            index = nil
        } else if let previous, let kept = newMatches.firstIndex(of: previous) {
            index = kept
        } else {
            index = newMatches.count - 1
        }
    }

    @discardableResult
    mutating func older() -> String? {
        guard let index, index > 0 else { return nil }
        self.index = index - 1
        return current
    }

    @discardableResult
    mutating func newer() -> String? {
        guard let index, index < matches.count - 1 else { return nil }
        self.index = index + 1
        return current
    }

    mutating func clear() {
        matches = []
        index = nil
    }
}
