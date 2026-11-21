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
    case unknown

    init(rawOrUnknown raw: String) {
        self = ChatMessageType(rawValue: raw) ?? .unknown
    }

    /// Bu sürümün gönderebildiği türler (8C: metin, fotoğraf, video, sesli mesaj).
    static let sendable: Set<ChatMessageType> = [.text, .image, .video, .audio]

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
        let base = message.deleted ? "Bu mesaj silindi" : (message.type == .text ? message.text : message.type.placeholder)
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

    init(
        id: String,
        members: [String],
        names: [String: String] = [:],
        createdAt: Date,
        lastMessage: ChatLastMessage? = nil,
        typing: [String: Date] = [:]
    ) {
        self.id = id
        self.members = members
        self.names = names
        self.createdAt = createdAt
        self.lastMessage = lastMessage
        self.typing = typing
    }

    func otherMember(of userID: String) -> String? {
        members.first { $0 != userID }
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

enum ChatText {
    static let turkish = Locale(identifier: "tr_TR")

    /// Arama: büyük/küçük harf ve aksan duyarsız, Türkçe kurallarıyla (İ/ı).
    static func matches(_ text: String, query: String) -> Bool {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return false }
        return fold(text).contains(needle)
    }

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
