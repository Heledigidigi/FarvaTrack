import Foundation
import SwiftData

/// Gönderim durumu (yalnızca kendi mesajlarımız için anlamlı).
enum ChatSendState: String, Codable {
    /// Bekleyen kuyrukta, sunucuya ulaşmadı.
    case pending
    /// Denemeler tükendi; kullanıcı tekrar deneyebilir.
    case failed
    /// Sunucuda.
    case sent
}

/// Sohbet mesajlarının cihazdaki önbelleği. Uygulama çevrimdışı açılınca sohbet buradan gösterilir.
@Model
final class ChatMessageRecord {
    /// `ownerID|messageID`: aynı cihazda iki hesap aynı sohbeti açsa bile kayıtlar karışmaz.
    @Attribute(.unique) var key: String
    var messageID: String
    /// Önbelleğin sahibi (cihazdaki oturum açmış kullanıcı).
    var ownerID: String
    var chatID: String
    var senderID: String
    var typeRaw: String
    var text: String
    var createdAt: Date
    var readAt: Date?
    /// Alıcının cihazına ulaştığı an (Mesaj bilgisi ekranı için).
    var deliveredAt: Date?
    var replyToID: String?
    var replyToSenderID: String?
    var replyToPreview: String?
    var replyToTypeRaw: String?
    /// uid → emoji sözlüğünün JSON hali.
    var reactionsData: Data
    var editedAt: Date?
    /// Herkesten silindi (Firestore'daki `deleted`).
    var deletedForEveryone: Bool
    /// Yalnızca bu cihazda gizlendi ("benden sil").
    var hiddenForMe: Bool
    var sendStateRaw: String
    /// `ChatMedia` JSON'u (fotoğraf/video mesajlarında).
    var mediaData: Data?
    /// Gönderen cihazda `outgoing` klasöründeki dosya adları.
    var localOriginalName: String?
    var localThumbnailName: String?
    /// Gönderen cihazda medya yüklemesinin aşaması.
    var uploadStageRaw: String?
    /// `ChatAudio` JSON'u (sesli mesajlarda).
    var audioData: Data?
    var listenedAt: Date?
    /// `ChatSticker` JSON'u (sticker mesajlarında).
    var stickerData: Data?
    /// `ChatBubbleRef` JSON'u (8F).
    var bubbleData: Data?
    /// `ChatCallInfo` JSON'u (8H, arama satırı).
    var callData: Data?
    /// `ChatDietInfo` JSON'u (Aşama 9, diyet programı kartı).
    var dietData: Data?
    /// Alıcı cihaz: orijal indirildi ve sunucuya "aldım" denildi (bulut temizliği buna bakar).
    var originalAcked: Bool = false
    /// Alıcı cihaz: otomatik Fotoğraflar'a kaydetme denendi (bir kez).
    var savedToPhotos: Bool = false
    /// Orijal buluttan kaldırılmış ve cihazda yok: yeniden indirilmeye çalışılmaz.
    var originalUnavailable: Bool = false

    init(dto: ChatMessageDTO, ownerID: String, chatID: String, sendState: ChatSendState) {
        self.key = ChatMessageRecord.key(ownerID: ownerID, messageID: dto.id)
        self.messageID = dto.id
        self.ownerID = ownerID
        self.chatID = chatID
        self.senderID = dto.senderID
        self.typeRaw = dto.type.rawValue
        self.text = dto.text
        self.createdAt = dto.createdAt
        self.readAt = dto.readAt
        self.deliveredAt = dto.deliveredAt
        self.reactionsData = ChatMessageRecord.encode(dto.reactions)
        self.editedAt = dto.editedAt
        self.deletedForEveryone = dto.deleted
        self.hiddenForMe = false
        self.sendStateRaw = sendState.rawValue
        self.replyToID = dto.replyTo?.messageID
        self.replyToSenderID = dto.replyTo?.senderID
        self.replyToPreview = dto.replyTo?.preview
        self.replyToTypeRaw = dto.replyTo?.type.rawValue
        self.mediaData = dto.media.flatMap { try? JSONEncoder().encode($0) }
        self.localOriginalName = nil
        self.localThumbnailName = nil
        self.uploadStageRaw = nil
        self.audioData = dto.audio.flatMap { try? JSONEncoder().encode($0) }
        self.listenedAt = dto.listenedAt
        self.stickerData = dto.sticker.flatMap { try? JSONEncoder().encode($0) }
        self.bubbleData = dto.bubble.flatMap { try? JSONEncoder().encode($0) }
        self.callData = dto.call.flatMap { try? JSONEncoder().encode($0) }
        self.dietData = dto.diet.flatMap { try? JSONEncoder().encode($0) }
    }

    static func key(ownerID: String, messageID: String) -> String { "\(ownerID)|\(messageID)" }

    var type: ChatMessageType { ChatMessageType(rawOrUnknown: typeRaw) }

    var sendState: ChatSendState {
        get { ChatSendState(rawValue: sendStateRaw) ?? .sent }
        set { sendStateRaw = newValue.rawValue }
    }

    var reactions: [String: String] {
        get { (try? JSONDecoder().decode([String: String].self, from: reactionsData)) ?? [:] }
        set { reactionsData = ChatMessageRecord.encode(newValue) }
    }

    var media: ChatMedia? {
        get { mediaData.flatMap { try? JSONDecoder().decode(ChatMedia.self, from: $0) } }
        set { mediaData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var audio: ChatAudio? {
        get { audioData.flatMap { try? JSONDecoder().decode(ChatAudio.self, from: $0) } }
        set { audioData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var sticker: ChatSticker? {
        get { stickerData.flatMap { try? JSONDecoder().decode(ChatSticker.self, from: $0) } }
        set { stickerData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var call: ChatCallInfo? {
        get { callData.flatMap { try? JSONDecoder().decode(ChatCallInfo.self, from: $0) } }
        set { callData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var diet: ChatDietInfo? {
        get { dietData.flatMap { try? JSONDecoder().decode(ChatDietInfo.self, from: $0) } }
        set { dietData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var bubble: ChatBubbleRef? {
        get { bubbleData.flatMap { try? JSONDecoder().decode(ChatBubbleRef.self, from: $0) } }
        set { bubbleData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var uploadStage: ChatUploadStage? {
        get { uploadStageRaw.flatMap(ChatUploadStage.init(rawValue:)) }
        set { uploadStageRaw = newValue?.rawValue }
    }

    var replyTo: ChatReplyReference? {
        guard let replyToID, let replyToSenderID else { return nil }
        return ChatReplyReference(
            messageID: replyToID,
            senderID: replyToSenderID,
            preview: replyToPreview ?? "",
            type: ChatMessageType(rawOrUnknown: replyToTypeRaw ?? "text")
        )
    }

    var dto: ChatMessageDTO {
        ChatMessageDTO(
            id: messageID, senderID: senderID, type: type, text: text, createdAt: createdAt,
            readAt: readAt, replyTo: replyTo, reactions: reactions, editedAt: editedAt,
            deleted: deletedForEveryone, media: media, audio: audio, listenedAt: listenedAt, sticker: sticker, bubble: bubble, call: call, diet: diet,
            deliveredAt: deliveredAt
        )
    }

    /// Sunucudaki hali yazılır; "benden sil" ve gönderim durumu yerel kalır.
    func apply(remote dto: ChatMessageDTO) {
        senderID = dto.senderID
        typeRaw = dto.type.rawValue
        text = dto.text
        createdAt = dto.createdAt
        readAt = dto.readAt
        // İletildi bilgisi bir kez yazılır; yerelde işaretlenmişse sunucudan gelmesi beklenirken silinmez.
        deliveredAt = dto.deliveredAt ?? deliveredAt
        reactions = dto.reactions
        editedAt = dto.editedAt
        deletedForEveryone = dto.deleted
        media = dto.media
        audio = dto.audio
        listenedAt = dto.listenedAt
        sticker = dto.sticker
        bubble = dto.bubble
        call = dto.call
        diet = dto.diet
        applyReply(dto.replyTo)
    }

    private func applyReply(_ reply: ChatReplyReference?) {
        replyToID = reply?.messageID
        replyToSenderID = reply?.senderID
        replyToPreview = reply?.preview
        replyToTypeRaw = reply?.type.rawValue
    }

    private static func encode(_ reactions: [String: String]) -> Data {
        (try? JSONEncoder().encode(reactions)) ?? Data("{}".utf8)
    }
}

/// Kuyruktaki işlem türü.
enum ChatOperationKind: String, Codable {
    case create, edit, deleteForEveryone, react, markRead
    /// Fotoğraf/video orijinalinin yüklenmesi; sıralı kuyruğu bekletmemek için ayrı, paralel çalışır.
    case uploadOriginal
    /// Alıcı sesli mesajı dinledi.
    case markListened
}

/// Çevrimdışı ya da hata nedeniyle sunucuya yazılamayan işlemler; sırayla yeniden denenir.
@Model
final class ChatPendingOperation {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var chatID: String
    var messageID: String
    var kindRaw: String
    /// `edit` için yeni metin.
    var text: String?
    /// `react` için emoji; `nil` tepkiyi kaldırır.
    var emoji: String?
    var createdAt: Date
    var attempts: Int

    init(ownerID: String, chatID: String, messageID: String, kind: ChatOperationKind, text: String? = nil, emoji: String? = nil, createdAt: Date) {
        self.id = UUID()
        self.ownerID = ownerID
        self.chatID = chatID
        self.messageID = messageID
        self.kindRaw = kind.rawValue
        self.text = text
        self.emoji = emoji
        self.createdAt = createdAt
        self.attempts = 0
    }

    var kind: ChatOperationKind { ChatOperationKind(rawValue: kindRaw) ?? .create }
}

/// Eşleşilen sohbet odasının kimliği ve isimleri; uygulama çevrimdışı açılınca da sohbet görünsün diye.
struct ChatRoomCache {
    let defaults: UserDefaults
    var kind: ChatRoomKind = .partner
    /// Arkadaş odası (her arkadaşın ayrı anahtarı). `nil`: eski tek oda anahtarı.
    var chatID: String?

    /// Karşılıklı sohbetin anahtarı eski sürümle aynı kalır.
    private func key(_ userID: String) -> String {
        if let chatID { return "chatRoom.\(userID).room.\(chatID)" }
        return kind == .partner ? "chatRoom.\(userID)" : "chatRoom.\(userID).\(kind.rawValue)"
    }

    func load(userID: String) -> ChatRoomDTO? {
        guard let data = defaults.data(forKey: key(userID)) else { return nil }
        return try? JSONDecoder().decode(ChatRoomDTO.self, from: data)
    }

    func save(_ room: ChatRoomDTO, userID: String) {
        // "Yazıyor" bilgisi geçicidir, saklanmaz.
        var stored = room
        stored.typing = [:]
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: key(userID))
        }
    }

    func clear(userID: String) {
        defaults.removeObject(forKey: key(userID))
    }
}

/// Veri dışa aktarma için sohbet mesajı.
struct ChatMessageExport: Codable, Equatable {
    var id: String
    var chatID: String
    var senderID: String
    var type: String
    var text: String
    var createdAt: Date
    var readAt: Date?
    var editedAt: Date?
    var deleted: Bool
    var replyToID: String?
    var reactions: [String: String]
    /// Medya mesajlarında Storage yolu ve boyutu (dosyanın kendisi dışa aktarılmaz).
    var media: ChatMedia?
    var audio: ChatAudio?
    var listenedAt: Date?
    var sticker: ChatSticker?
    var call: ChatCallInfo?

    init(record: ChatMessageRecord) {
        id = record.messageID
        chatID = record.chatID
        senderID = record.senderID
        type = record.typeRaw
        text = record.text
        createdAt = record.createdAt
        readAt = record.readAt
        editedAt = record.editedAt
        deleted = record.deletedForEveryone
        replyToID = record.replyToID
        reactions = record.reactions
        media = record.media
        audio = record.audio
        listenedAt = record.listenedAt
        sticker = record.sticker
        call = record.call
    }
}
