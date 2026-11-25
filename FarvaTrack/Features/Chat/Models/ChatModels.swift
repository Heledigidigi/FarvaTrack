import Foundation

// MARK: - Sabitler

enum ChatLimits {
    /// Anlık dinleyicinin izlediği ve her sayfada yüklenen mesaj sayısı.
    static let pageSize = 50
    /// Tek mesajda izin verilen en fazla karakter (Firestore kurallarıyla aynı).
    static let maxTextLength = 4_000
    /// Gönderilen mesaj bu süre içinde düzenlenebilir.
    static let editWindow: TimeInterval = 15 * 60
    /// "Yazıyor…" bilgisi bu süreden eskiyse gösterilmez.
    static let typingTimeout: TimeInterval = 6
    /// Yazarken sunucuya en sık bu aralıkla "yazıyor" sinyali gönderilir.
    static let typingThrottle: TimeInterval = 3
    /// Davet kodunun geçerlilik süresi.
    static let inviteLifetime: TimeInterval = 24 * 60 * 60
    /// Alıntı önizlemesinin en fazla uzunluğu.
    static let replyPreviewLength = 120
    /// Tepki menüsündeki hazır emojiler.
    static let quickReactions = ["❤️", "😂", "👍", "😮", "😢", "🔥"]
}

// MARK: - Mesaj türü

/// Firestore'daki `type` alanı. İleride medya, ses, sticker ve arama satırları eklenecek;
/// tanınmayan bir tür gelirse uygulama çökmez, `.unknown` olarak gösterilir.
enum ChatMessageType: String, Codable, CaseIterable {
    case text, image, video, audio, sticker, call
    /// Sohbette gönderilen diyet programı kartı (Aşama 9).
    case diet
    case unknown

    init(rawOrUnknown raw: String) {
        self = ChatMessageType(rawValue: raw) ?? .unknown
    }

    /// Bu sürümün gönderebildiği türler (8C: metin, fotoğraf, video, sesli mesaj).
    static let sendable: Set<ChatMessageType> = [.text, .image, .video, .audio, .sticker]

    var isMedia: Bool { self == .image || self == .video }

    /// Metin içermeyen türlerin sohbet ve alıntılardaki kısa açıklaması.
    var placeholder: String {
        switch self {
        case .text: return ""
        case .image: return "📷 Fotoğraf"
        case .video: return "🎬 Video"
        case .audio: return "🎤 Sesli mesaj"
        case .sticker: return "Sticker"
        case .call: return "📞 Arama"
        case .diet: return "📋 Diyet programı"
        case .unknown: return "Bu mesaj türü bu sürümde gösterilemiyor"
        }
    }
}

// MARK: - Alıntı

/// Yanıtlanan mesajın kısa bir kopyası; orijinal silinse de alıntı okunabilir kalır.
struct ChatReplyReference: Codable, Equatable, Hashable {
    var messageID: String
    var senderID: String
    var preview: String
    var type: ChatMessageType

    static func make(from message: ChatMessageDTO) -> ChatReplyReference {
        let base = message.deleted ? "Bu mesaj silindi" : ChatText.summary(of: message)
        return ChatReplyReference(
            messageID: message.id,
            senderID: message.senderID,
            preview: ChatText.preview(base, limit: ChatLimits.replyPreviewLength),
            type: message.type
        )
    }
}

// MARK: - Mesaj (sunucu ↔ önbellek arasında taşınan değer)

struct ChatMessageDTO: Equatable, Identifiable {
    var id: String
    var senderID: String
    var type: ChatMessageType
    var text: String
    var createdAt: Date
    var readAt: Date?
    /// Mesaj alıcının cihazına ulaştığında (yalnızca alıcı, bir kez yazar).
    var deliveredAt: Date?
    var replyTo: ChatReplyReference?
    /// uid → emoji. Her katılımcının en fazla bir tepkisi olur.
    var reactions: [String: String]
    var editedAt: Date?
    var deleted: Bool
    /// Fotoğraf / video mesajlarının dosya bilgisi.
    var media: ChatMedia?
    /// Sesli mesajın dosya bilgisi ve dalga formu.
    var audio: ChatAudio?
    /// Alıcı sesli mesajı dinlediğinde (yalnızca alıcı yazar).
    var listenedAt: Date?
    /// Sticker mesajının PNG'si (8E).
    var sticker: ChatSticker?
    /// Gönderenin seçtiği baloncuk stili ve sürümü (8F).
    var bubble: ChatBubbleRef?
    /// Arama satırı (8H): süre ve sonuç.
    var call: ChatCallInfo?
    /// Diyet programı kartı (Aşama 9).
    var diet: ChatDietInfo?
    /// Firestore'un yerel (henüz sunucuya ulaşmamış) yazımı mı; sunucuya yazılmaz.
    var hasPendingWrites: Bool = false

    init(
        id: String,
        senderID: String,
        type: ChatMessageType = .text,
        text: String,
        createdAt: Date,
        readAt: Date? = nil,
        replyTo: ChatReplyReference? = nil,
        reactions: [String: String] = [:],
        editedAt: Date? = nil,
        deleted: Bool = false,
        media: ChatMedia? = nil,
        audio: ChatAudio? = nil,
        listenedAt: Date? = nil,
        sticker: ChatSticker? = nil,
        bubble: ChatBubbleRef? = nil,
        call: ChatCallInfo? = nil,
        diet: ChatDietInfo? = nil,
        deliveredAt: Date? = nil,
        hasPendingWrites: Bool = false
    ) {
        self.id = id
        self.senderID = senderID
        self.type = type
        self.text = text
        self.createdAt = createdAt
        self.readAt = readAt
        self.replyTo = replyTo
        self.reactions = reactions
        self.editedAt = editedAt
        self.deleted = deleted
        self.media = media
        self.audio = audio
        self.listenedAt = listenedAt
        self.sticker = sticker
        self.bubble = bubble
        self.call = call
        self.diet = diet
        self.deliveredAt = deliveredAt
        self.hasPendingWrites = hasPendingWrites
    }
}

// MARK: - Sohbet odası

struct ChatLastMessage: Codable, Equatable {
    var id: String
    var senderID: String
    var type: ChatMessageType
    var preview: String
    var createdAt: Date
}

/// `chats/{chatId}` belgesi.
struct ChatRoomDTO: Codable, Equatable, Identifiable {
    var id: String
    var members: [String]
    /// uid → görünen ad (eşleşme anında yazılır; profiller birbirine kapalıdır).
    var names: [String: String]
    var createdAt: Date
    var lastMessage: ChatLastMessage?
    /// uid → son "yazıyor" sinyalinin zamanı.
    var typing: [String: Date]
    /// uid → profil fotoğrafının adresi. Profiller birbirine kapalı olduğu için her üye kendininkini odaya yazar.
    var photos: [String: String]
    /// uid → çevrimiçi bilgisi (her üye yalnızca kendininkini yazar).
    var presence: [String: ChatPresence]

    init(
        id: String,
        members: [String],
        names: [String: String] = [:],
        createdAt: Date,
        lastMessage: ChatLastMessage? = nil,
        typing: [String: Date] = [:],
        photos: [String: String] = [:],
        presence: [String: ChatPresence] = [:]
    ) {
        self.id = id
        self.members = members
        self.names = names
        self.createdAt = createdAt
        self.lastMessage = lastMessage
        self.typing = typing
        self.photos = photos
        self.presence = presence
    }

    private enum CodingKeys: String, CodingKey {
        case id, members, names, createdAt, lastMessage, typing, photos, presence
    }

    /// Eski sürümün önbelleğe yazdığı odalarda `photos` / `presence` yoktur.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        members = try container.decode([String].self, forKey: .members)
        names = try container.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastMessage = try container.decodeIfPresent(ChatLastMessage.self, forKey: .lastMessage)
        typing = try container.decodeIfPresent([String: Date].self, forKey: .typing) ?? [:]
        photos = try container.decodeIfPresent([String: String].self, forKey: .photos) ?? [:]
        presence = try container.decodeIfPresent([String: ChatPresence].self, forKey: .presence) ?? [:]
    }

    /// Üyenin profil fotoğrafı (boşsa `nil`).
    func photoURL(of userID: String) -> String? {
        guard let value = photos[userID]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    func otherMember(of userID: String) -> String? {
        members.first { $0 != userID }
    }

    /// Kullanıcının kendisiyle konuştuğu (not tuttuğu) oda mı: tüm üyeler kendisi.
    func isPersonal(for userID: String) -> Bool {
        !members.isEmpty && members.allSatisfy { $0 == userID }
    }

    func displayName(of userID: String) -> String {
        let name = names[userID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Sohbet arkadaşın" : name
    }

    /// Karşı taraf son birkaç saniye içinde yazıyor sinyali gönderdiyse.
    func isTyping(_ userID: String, now: Date) -> Bool {
        guard let date = typing[userID] else { return false }
        let age = now.timeIntervalSince(date)
        return age >= -ChatLimits.typingTimeout && age < ChatLimits.typingTimeout
    }
}

// MARK: - Oda türü

/// Karşılıklı sohbet ya da kullanıcının kendine yazdığı not sohbeti. İkisi aynı altyapıyı kullanır;
/// fark yalnızca mesajın gittiği yerdir (not sohbetinde iki üye de kullanıcının kendisidir).
enum ChatRoomKind: String, Codable, Hashable, CaseIterable {
    case partner
    case personal

    static func of(_ room: ChatRoomDTO, userID: String) -> ChatRoomKind {
        room.isPersonal(for: userID) ? .personal : .partner
    }
}

// MARK: - Sohbet kimliği

enum ChatID {
    /// İki uid'den her iki tarafta da aynı çıkan kimlik: küçük olan önce, aralarında `_`.
    /// Firestore kuralları da aynı biçimi doğrular.
    static func make(_ first: String, _ second: String) -> String {
        let sorted = [first, second].sorted()
        return "\(sorted[0])_\(sorted[1])"
    }

    static func sortedMembers(_ first: String, _ second: String) -> [String] {
        [first, second].sorted()
    }
}

// MARK: - Davet kodu

struct ChatInvite: Equatable {
    var code: String
    var ownerID: String
    var ownerName: String
    var createdAt: Date
    var expiresAt: Date
    var redeemedBy: String?

    func isExpired(now: Date) -> Bool { now >= expiresAt }
}

enum ChatInviteCode {
    /// Karışan karakterler (0/O, 1/I/L) yok.
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let length = 6

    static func generate<R: RandomNumberGenerator>(using generator: inout R) -> String {
        String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    /// Kullanıcının yazdığını düzeltir: boşluk/tire atılır, büyük harfe çevrilir (Türkçe "i" → "I").
    static func normalize(_ input: String) -> String {
        let cleaned = input
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "İ", with: "I")
            .filter { !$0.isWhitespace && $0 != "-" }
        return cleaned
    }

    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy { alphabet.contains($0) }
    }
}

// MARK: - Mesaj durumu

enum ChatMessageStatus: Equatable {
    case sending, failed, delivered, read

    var systemImage: String {
        switch self {
        case .sending: return "clock"
        case .failed: return "exclamationmark.circle.fill"
        case .delivered: return "checkmark"
        case .read: return "checkmark.circle.fill"
        }
    }

    var accessibilityText: String {
        switch self {
        case .sending: return "gönderiliyor"
        case .failed: return "gönderilemedi, tekrar denemek için dokun"
        case .delivered: return "iletildi"
        case .read: return "okundu"
        }
    }
}

// MARK: - Metin yardımcıları

/// Sohbette paylaşılmış bir bağlantı (profil sayfası).
struct ChatSharedLink: Identifiable, Equatable {
    let id: String
    let url: URL
    let messageID: String
    let text: String
    let date: Date
    let isMine: Bool
}

enum ChatText {
    static let turkish = Locale(identifier: "tr_TR")

    /// Listede / alıntıda kısa metin: metin mesajında metnin kendisi, açıklamalı fotoğrafta "📷 açıklama".
    static func summary(of message: ChatMessageDTO) -> String {
        if message.type == .text { return message.text }
        let caption = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.type.isMedia, !caption.isEmpty {
            return "\(message.type == .video ? "🎬" : "📷") \(caption)"
        }
        return message.type.placeholder
    }

    /// Arama: büyük/küçük harf ve aksan duyarsız, Türkçe kurallarıyla (İ/ı).
    static func matches(_ text: String, query: String) -> Bool {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return false }
        return fold(text).contains(needle)
    }

    /// Yazım hatasına dayanıklı arama. Eşleşmezse `nil`; eşleşirse puan (0 = birebir, büyüdükçe daha uzak).
    /// Sorgudaki her kelime mesajdaki bir kelimeyle eşleşmeli: içinde geçmesi 0 puan; değilse
    /// harf ekleme/silme/değiştirme/yer değiştirme sayısı kelime uzunluğuna göre (4–5 harf: 1, 6–8: 2, 9+: 3) sınırlı.
    static func fuzzyScore(_ text: String, query: String) -> Int? {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return nil }
        let haystack = fold(text)
        if haystack.contains(needle) { return 0 }
        let queryWords = words(needle)
        let textWords = words(haystack)
        guard !queryWords.isEmpty, !textWords.isEmpty else { return nil }
        var total = 0
        for word in queryWords {
            var best: Int?
            for candidate in textWords {
                if candidate.contains(word) { best = 0; break }
                let limit = typoAllowance(word.count)
                guard limit > 0, abs(candidate.count - word.count) <= limit + 2 else { continue }
                // Yarım yazılmış kelime: "antrenm" ~ "antrenman" için aday kelimenin başıyla da karşılaştır.
                var distance = editDistance(word, candidate, limit: limit)
                if candidate.count > word.count {
                    distance = min(distance, editDistance(word, String(candidate.prefix(word.count)), limit: limit))
                }
                if distance <= limit { best = min(best ?? distance, distance) }
            }
            guard let best else { return nil }
            total += best
        }
        return total + 1
    }

    /// Kelime uzunluğuna göre izin verilen yazım hatası.
    static func typoAllowance(_ length: Int) -> Int {
        switch length {
        case ..<4: return 0
        case 4...5: return 1
        case 6...8: return 2
        default: return 3
        }
    }

    static func words(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Damerau–Levenshtein (bitişik harf yer değiştirmesi 1 sayılır). `limit` aşılınca erken döner.
    static func editDistance(_ a: String, _ b: String, limit: Int = .max) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        if abs(s.count - t.count) > limit { return limit + 1 }
        var previous2 = [Int](repeating: 0, count: t.count + 1)
        var previous = Array(0...t.count)
        var current = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    value = min(value, previous2[j - 2] + 1)
                }
                current[j] = value
                rowMin = min(rowMin, value)
            }
            if rowMin > limit { return limit + 1 }
            (previous2, previous, current) = (previous, current, previous2)
        }
        return previous[t.count]
    }

    /// Metindeki bağlantılar (http/https; "www.ornek.com" gibi şemasızlar https'e tamamlanır).
    static func links(in text: String) -> [URL] {
        guard !text.isEmpty, let detector = linkDetector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return detector.matches(in: text, range: range).compactMap { match -> URL? in
            guard var url = match.url else { return nil }
            if url.scheme == nil, let fixed = URL(string: "https://" + url.absoluteString) { url = fixed }
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
            guard seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Türkçe küçük harfe çevirir (İ→i, I→ı), aksanları atar (ç→c, ğ→g…) ve ı/i farkını kaldırır;
    /// böylece "istanbul", "İSTANBUL" ve "ISTANBUL" aynı eşleşir.
    static func fold(_ text: String) -> String {
        text
            .lowercased(with: turkish)
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// Tek satırlık kısa önizleme.
    static func preview(_ text: String, limit: Int) -> String {
        let single = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard single.count > limit else { return single }
        return String(single.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Gönderilecek metni temizler; boş ya da çok uzunsa `nil`.
    static func sanitizedOutgoing(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= ChatLimits.maxTextLength else { return nil }
        return trimmed
    }
}
