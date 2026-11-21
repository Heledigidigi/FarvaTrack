import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Anlık dinleyici aboneliği; `cancel()` dinlemeyi bırakır.
final class ChatSubscription {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    /// Hiçbir şey dinlemeyen abonelik (Firebase kurulmamışsa ya da testlerde).
    static let none = ChatSubscription {}

    func cancel() {
        onCancel?()
        onCancel = nil
    }

    deinit { onCancel?() }
}

/// Sohbet için sunucu işlemleri. Testlerde sahte uygulamayla değiştirilir.
protocol ChatSyncing: AnyObject {
    func createInvite(ownerID: String, ownerName: String, now: Date) async throws -> ChatInvite
    func redeemInvite(code: String, userID: String, userName: String, now: Date) async throws -> ChatRoomDTO

    /// Kullanıcının üyesi olduğu sohbet (en fazla bir tane). `isFromCache` yalnızca yerel önbellekten geldiyse `true`.
    func observeRoom(
        userID: String,
        onChange: @escaping @MainActor (_ room: ChatRoomDTO?, _ isFromCache: Bool) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> ChatSubscription

    /// En yeni `limit` mesaj (yeniden eskiye).
    func observeRecentMessages(
        chatID: String,
        limit: Int,
        onChange: @escaping @MainActor ([ChatMessageDTO]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> ChatSubscription

    /// `before` tarihinden eski `limit` mesaj (yeniden eskiye).
    func fetchMessages(chatID: String, before: Date, limit: Int) async throws -> [ChatMessageDTO]

    func sendMessage(_ message: ChatMessageDTO, chatID: String) async throws
    func editMessage(id: String, chatID: String, text: String, editedAt: Date) async throws
    func deleteMessageForEveryone(id: String, chatID: String) async throws
    /// Medya bilgisini günceller (ör. orijinal yüklenince `status = ready`).
    func updateMedia(_ media: ChatMedia, messageID: String, chatID: String) async throws
    /// Alıcı: sesli mesaj dinlendi.
    func markListened(messageID: String, chatID: String, at: Date) async throws
    func setReaction(_ emoji: String?, messageID: String, chatID: String, userID: String) async throws
    func markRead(messageIDs: [String], chatID: String, at: Date) async throws
    func setTyping(_ isTyping: Bool, chatID: String, userID: String, at: Date) async throws

    /// Hesap silinirken: kullanıcının sohbetleri, mesajları ve davetleri.
    func purgeUserData(userID: String) async throws
}

// MARK: - Firestore alan adları

enum ChatField {
    static let members = "members"
    static let names = "names"
    static let createdAt = "createdAt"
    static let lastMessage = "lastMessage"
    static let typing = "typing"
    static let inviteCode = "inviteCode"

    static let senderId = "senderId"
    static let type = "type"
    static let text = "text"
    static let readAt = "readAt"
    static let replyTo = "replyTo"
    static let reactions = "reactions"
    static let editedAt = "editedAt"
    static let deleted = "deleted"
    static let media = "media"
    static let audio = "audio"
    static let listenedAt = "listenedAt"

    static let messageId = "messageId"
    static let preview = "preview"

    static let ownerId = "ownerId"
    static let ownerName = "ownerName"
    static let expiresAt = "expiresAt"
    static let redeemedBy = "redeemedBy"
}

// MARK: - Firestore uygulaması

final class ChatService: ChatSyncing {
    private var db: Firestore {
        get throws {
            guard FirebaseBootstrap.isConfigured else { throw AppError.firebaseNotConfigured }
            return Firestore.firestore()
        }
    }

    private func chats() throws -> CollectionReference {
        try db.collection(Constants.Collection.chats)
    }

    private func messages(_ chatID: String) throws -> CollectionReference {
        try chats().document(chatID).collection(Constants.Collection.chatMessages)
    }

    private func invites() throws -> CollectionReference {
        try db.collection(Constants.Collection.chatInvites)
    }

    // MARK: Davet

    func createInvite(ownerID: String, ownerName: String, now: Date) async throws -> ChatInvite {
        do {
            // Eski davetler temizlenir; her kullanıcının tek geçerli kodu olur.
            let old = try await invites().whereField(ChatField.ownerId, isEqualTo: ownerID).getDocuments()
            for document in old.documents { try? await document.reference.delete() }

            let expires = now.addingTimeInterval(ChatLimits.inviteLifetime)
            var lastError: Error?
            // Kod çakışırsa (kural `create` yerine `update` görür ve reddeder) yeni kodla tekrar denenir.
            for _ in 0..<3 {
                let code = ChatInviteCode.generate()
                do {
                    try await invites().document(code).setData([
                        ChatField.ownerId: ownerID,
                        ChatField.ownerName: ownerName,
                        ChatField.createdAt: Timestamp(date: now),
                        ChatField.expiresAt: Timestamp(date: expires)
                    ])
                    return ChatInvite(code: code, ownerID: ownerID, ownerName: ownerName, createdAt: now, expiresAt: expires)
                } catch {
                    lastError = error
                }
            }
            throw lastError ?? AppError.unknown("Davet kodu oluşturulamadı.")
        } catch {
            throw AppError.map(error)
        }
    }

    func redeemInvite(code: String, userID: String, userName: String, now: Date) async throws -> ChatRoomDTO {
        let normalized = ChatInviteCode.normalize(code)
        guard ChatInviteCode.isValid(normalized) else {
            throw AppError.invalidInput("Davet kodu \(ChatInviteCode.length) karakter olmalı.")
        }
        do {
            let inviteRef = try invites().document(normalized)
            // Sunucudan okunur: çevrimdışıyken eşleşme yapılamaz.
            let snapshot = try await inviteRef.getDocument(source: .server)
            guard snapshot.exists, let data = snapshot.data(), let invite = ChatFirestoreMapper.invite(code: normalized, data: data) else {
                throw AppError.invalidInput("Bu davet kodu bulunamadı.")
            }
            try ChatPairingRules.validate(invite: invite, redeemerID: userID, now: now)

            let members = ChatID.sortedMembers(invite.ownerID, userID)
            let chatID = ChatID.make(invite.ownerID, userID)
            let room = ChatRoomDTO(
                id: chatID,
                members: members,
                names: [invite.ownerID: invite.ownerName, userID: userName],
                createdAt: now
            )

            // Davetin kullanıldığı ve odanın oluşturulduğu tek bir toplu yazım; kurallar `getAfter` ile doğrular.
            let batch = try db.batch()
            batch.updateData([ChatField.redeemedBy: userID], forDocument: inviteRef)
            batch.setData([
                ChatField.members: members,
                ChatField.names: room.names,
                ChatField.createdAt: Timestamp(date: now),
                ChatField.inviteCode: normalized,
                ChatField.typing: [String: Any]()
            ], forDocument: try chats().document(chatID))
            try await batch.commit()
            return room
        } catch {
            throw AppError.map(error)
        }
    }

    // MARK: Dinleyiciler

    func observeRoom(
        userID: String,
        onChange: @escaping @MainActor (ChatRoomDTO?, Bool) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> ChatSubscription {
        guard let query = try? chats().whereField(ChatField.members, arrayContains: userID).limit(to: 1) else {
            Task { @MainActor in onError(.firebaseNotConfigured) }
            return .none
        }
        let registration = query.addSnapshotListener { snapshot, error in
            if let error {
                Task { @MainActor in onError(AppError.map(error)) }
                return
            }
            guard let snapshot else { return }
            let room = snapshot.documents.first.flatMap { ChatFirestoreMapper.room(id: $0.documentID, data: $0.data()) }
            let fromCache = snapshot.metadata.isFromCache
            Task { @MainActor in onChange(room, fromCache) }
        }
        return ChatSubscription { registration.remove() }
    }

    func observeRecentMessages(
        chatID: String,
        limit: Int,
        onChange: @escaping @MainActor ([ChatMessageDTO]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> ChatSubscription {
        guard let query = try? messages(chatID).order(by: ChatField.createdAt, descending: true).limit(to: limit) else {
            Task { @MainActor in onError(.firebaseNotConfigured) }
            return .none
        }
        // Meta veri değişiklikleri de dinlenir: yerel yazım sunucuya ulaşınca "gönderiliyor" → "iletildi".
        let registration = query.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            if let error {
                Task { @MainActor in onError(AppError.map(error)) }
                return
            }
            guard let snapshot else { return }
            let items = snapshot.documents.compactMap {
                ChatFirestoreMapper.message(id: $0.documentID, data: $0.data(), hasPendingWrites: $0.metadata.hasPendingWrites)
            }
            Task { @MainActor in onChange(items) }
        }
        return ChatSubscription { registration.remove() }
    }

    func fetchMessages(chatID: String, before: Date, limit: Int) async throws -> [ChatMessageDTO] {
        do {
            let snapshot = try await messages(chatID)
                .whereField(ChatField.createdAt, isLessThan: Timestamp(date: before))
                .order(by: ChatField.createdAt, descending: true)
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents.compactMap {
                ChatFirestoreMapper.message(id: $0.documentID, data: $0.data(), hasPendingWrites: $0.metadata.hasPendingWrites)
            }
        } catch {
            throw AppError.map(error)
        }
    }

    // MARK: Yazımlar

    func sendMessage(_ message: ChatMessageDTO, chatID: String) async throws {
        do {
            let batch = try db.batch()
            // `merge`: aynı mesaj yeniden denenirse karşı tarafın yazdığı okundu/tepki alanları ezilmez.
            batch.setData(ChatFirestoreMapper.newMessageFields(message), forDocument: try messages(chatID).document(message.id), merge: true)
            batch.updateData([
                ChatField.lastMessage: ChatFirestoreMapper.lastMessageFields(message),
                "\(ChatField.typing).\(message.senderID)": FieldValue.delete()
            ], forDocument: try chats().document(chatID))
            try await batch.commit()
        } catch {
            throw AppError.map(error)
        }
    }

    func editMessage(id: String, chatID: String, text: String, editedAt: Date) async throws {
        try await update(chatID: chatID, messageID: id, [
            ChatField.text: text,
            ChatField.editedAt: Timestamp(date: editedAt)
        ])
    }

    func deleteMessageForEveryone(id: String, chatID: String) async throws {
        // Belge kalır (sıra ve alıntılar bozulmasın), içerik ve medya bilgisi boşaltılır.
        try await update(chatID: chatID, messageID: id, [
            ChatField.deleted: true,
            ChatField.text: "",
            ChatField.media: FieldValue.delete(),
            ChatField.audio: FieldValue.delete()
        ])
    }

    func markListened(messageID: String, chatID: String, at: Date) async throws {
        try await update(chatID: chatID, messageID: messageID, [ChatField.listenedAt: Timestamp(date: at)])
    }

    func updateMedia(_ media: ChatMedia, messageID: String, chatID: String) async throws {
        try await update(chatID: chatID, messageID: messageID, [ChatField.media: ChatMediaFields.encode(media)])
    }

    func setReaction(_ emoji: String?, messageID: String, chatID: String, userID: String) async throws {
        let value: Any = emoji ?? FieldValue.delete()
        try await update(chatID: chatID, messageID: messageID, ["\(ChatField.reactions).\(userID)": value])
    }

    func markRead(messageIDs: [String], chatID: String, at: Date) async throws {
        guard !messageIDs.isEmpty else { return }
        do {
            let collection = try messages(chatID)
            // Toplu yazım en fazla 500 işlem alır.
            for chunk in stride(from: 0, to: messageIDs.count, by: 400).map({ Array(messageIDs[$0..<min($0 + 400, messageIDs.count)]) }) {
                let batch = try db.batch()
                for id in chunk {
                    batch.updateData([ChatField.readAt: Timestamp(date: at)], forDocument: collection.document(id))
                }
                try await batch.commit()
            }
        } catch {
            throw AppError.map(error)
        }
    }

    func setTyping(_ isTyping: Bool, chatID: String, userID: String, at: Date) async throws {
        do {
            let value: Any = isTyping ? Timestamp(date: at) : FieldValue.delete()
            try await chats().document(chatID).updateData(["\(ChatField.typing).\(userID)": value])
        } catch {
            throw AppError.map(error)
        }
    }

    private func update(chatID: String, messageID: String, _ fields: [AnyHashable: Any]) async throws {
        do {
            try await messages(chatID).document(messageID).updateData(fields)
        } catch {
            throw AppError.map(error)
        }
    }

    // MARK: Hesap silme

    func purgeUserData(userID: String) async throws {
        do {
            let rooms = try await chats().whereField(ChatField.members, arrayContains: userID).getDocuments()
            for room in rooms.documents {
                let collection = room.reference.collection(Constants.Collection.chatMessages)
                while true {
                    let page = try await collection.limit(to: 300).getDocuments()
                    guard !page.documents.isEmpty else { break }
                    // Önce Storage'daki fotoğraf/videolar (kurallar üyeliği Firestore'dan okuduğu için oda silinmeden).
                    for document in page.documents {
                        if let media = ChatMediaFields.decode(document.data()[ChatField.media]) {
                            try? await Storage.storage().reference(withPath: media.originalPath).delete()
                            try? await Storage.storage().reference(withPath: media.thumbnailPath).delete()
                        }
                        if let audio = ChatAudioFields.decode(document.data()[ChatField.audio]) {
                            try? await Storage.storage().reference(withPath: audio.path).delete()
                        }
                    }
                    let batch = try db.batch()
                    page.documents.forEach { batch.deleteDocument($0.reference) }
                    try await batch.commit()
                }
                try await room.reference.delete()
            }
            let owned = try await invites().whereField(ChatField.ownerId, isEqualTo: userID).getDocuments()
            for invite in owned.documents { try await invite.reference.delete() }
        } catch {
            throw AppError.map(error)
        }
    }
}

// MARK: - Eşleşme kuralları (istemci tarafı; aynıları Firestore kurallarında da var)

enum ChatPairingRules {
    static func validate(invite: ChatInvite, redeemerID: String, now: Date) throws {
        if invite.ownerID == redeemerID {
            throw AppError.invalidInput("Kendi davet kodunu kullanamazsın. Kodu sohbet edeceğin kişiye gönder.")
        }
        if invite.isExpired(now: now) {
            throw AppError.invalidInput("Bu davet kodunun süresi dolmuş. Yeni bir kod iste.")
        }
        if let redeemer = invite.redeemedBy, redeemer != redeemerID {
            throw AppError.invalidInput("Bu davet kodu zaten kullanılmış.")
        }
    }
}

// MARK: - Firestore ↔ model dönüşümü

enum ChatFirestoreMapper {
    private static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        return value as? Date
    }

    static func message(id: String, data: [String: Any], hasPendingWrites: Bool) -> ChatMessageDTO? {
        guard let sender = data[ChatField.senderId] as? String else { return nil }
        // Sunucu zaman damgası henüz çözülmediyse (yerel yazım) şimdiki zaman kullanılır.
        let created = date(data[ChatField.createdAt]) ?? .now
        var reply: ChatReplyReference?
        if let map = data[ChatField.replyTo] as? [String: Any],
           let messageID = map[ChatField.messageId] as? String,
           let replySender = map[ChatField.senderId] as? String {
            reply = ChatReplyReference(
                messageID: messageID,
                senderID: replySender,
                preview: map[ChatField.preview] as? String ?? "",
                type: ChatMessageType(rawOrUnknown: map[ChatField.type] as? String ?? "text")
            )
        }
        return ChatMessageDTO(
            id: id,
            senderID: sender,
            type: ChatMessageType(rawOrUnknown: data[ChatField.type] as? String ?? "text"),
            text: data[ChatField.text] as? String ?? "",
            createdAt: created,
            readAt: date(data[ChatField.readAt]),
            replyTo: reply,
            reactions: (data[ChatField.reactions] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:],
            editedAt: date(data[ChatField.editedAt]),
            deleted: data[ChatField.deleted] as? Bool ?? false,
            media: ChatMediaFields.decode(data[ChatField.media]),
            audio: ChatAudioFields.decode(data[ChatField.audio]),
            listenedAt: date(data[ChatField.listenedAt]),
            hasPendingWrites: hasPendingWrites
        )
    }

    /// Yeni mesaj alanları. `readAt`, `reactions`, `editedAt` karşı tarafın / sonraki işlemlerin alanlarıdır, yazılmaz.
    static func newMessageFields(_ message: ChatMessageDTO) -> [String: Any] {
        var fields: [String: Any] = [
            ChatField.senderId: message.senderID,
            ChatField.type: message.type.rawValue,
            ChatField.text: message.text,
            ChatField.createdAt: Timestamp(date: message.createdAt),
            ChatField.deleted: false
        ]
        if let reply = message.replyTo {
            fields[ChatField.replyTo] = [
                ChatField.messageId: reply.messageID,
                ChatField.senderId: reply.senderID,
                ChatField.preview: reply.preview,
                ChatField.type: reply.type.rawValue
            ]
        }
        if let media = message.media {
            fields[ChatField.media] = ChatMediaFields.encode(media)
        }
        if let audio = message.audio {
            fields[ChatField.audio] = ChatAudioFields.encode(audio)
        }
        return fields
    }

    static func lastMessageFields(_ message: ChatMessageDTO) -> [String: Any] {
        [
            ChatField.messageId: message.id,
            ChatField.senderId: message.senderID,
            ChatField.type: message.type.rawValue,
            ChatField.preview: ChatText.preview(message.type == .text ? message.text : message.type.placeholder, limit: ChatLimits.replyPreviewLength),
            ChatField.createdAt: Timestamp(date: message.createdAt)
        ]
    }

    static func room(id: String, data: [String: Any]) -> ChatRoomDTO? {
        guard let members = data[ChatField.members] as? [String], members.count == 2 else { return nil }
        var last: ChatLastMessage?
        if let map = data[ChatField.lastMessage] as? [String: Any],
           let messageID = map[ChatField.messageId] as? String,
           let sender = map[ChatField.senderId] as? String {
            last = ChatLastMessage(
                id: messageID,
                senderID: sender,
                type: ChatMessageType(rawOrUnknown: map[ChatField.type] as? String ?? "text"),
                preview: map[ChatField.preview] as? String ?? "",
                createdAt: date(map[ChatField.createdAt]) ?? .now
            )
        }
        let typing = (data[ChatField.typing] as? [String: Any])?.compactMapValues { date($0) } ?? [:]
        return ChatRoomDTO(
            id: id,
            members: members,
            names: (data[ChatField.names] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:],
            createdAt: date(data[ChatField.createdAt]) ?? .now,
            lastMessage: last,
            typing: typing
        )
    }

    static func invite(code: String, data: [String: Any]) -> ChatInvite? {
        guard let owner = data[ChatField.ownerId] as? String, let expires = date(data[ChatField.expiresAt]) else { return nil }
        return ChatInvite(
            code: code,
            ownerID: owner,
            ownerName: data[ChatField.ownerName] as? String ?? "",
            createdAt: date(data[ChatField.createdAt]) ?? .now,
            expiresAt: expires,
            redeemedBy: data[ChatField.redeemedBy] as? String
        )
    }
}
