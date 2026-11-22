import Foundation
import SwiftData
import Observation

/// Ekranda gösterilen tek mesaj.
struct ChatMessageItem: Identifiable, Equatable {
    let message: ChatMessageDTO
    let isMine: Bool
    /// Yalnızca kendi mesajlarımızda.
    let status: ChatMessageStatus?
    let myReaction: String?
    let canEdit: Bool
    /// Kendi medya mesajımızda orijinal dosyanın yükleme ilerlemesi (0…1).
    var uploadProgress: Double? = nil
    /// Cihazdaki önizleme / orijinal dosya (varsa).
    var localThumbnailURL: URL? = nil
    var localOriginalURL: URL? = nil

    var id: String { message.id }

    /// Sesli mesaj karşı tarafça dinlendi mi.
    var isListened: Bool { message.listenedAt != nil }

    /// Gönderen tarafta yükleme sürüyor mu (iptal düğmesi için).
    var isUploading: Bool { isMine && message.media != nil && status == .sending }

    /// Bubble altında gösterilecek tepkiler (aynı emoji bir kez, sayısıyla).
    var reactionSummary: [(emoji: String, count: Int)] {
        guard !message.deleted else { return [] }
        var counts: [String: Int] = [:]
        for emoji in message.reactions.values { counts[emoji, default: 0] += 1 }
        return counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var displayText: String {
        if message.deleted { return "Bu mesaj silindi" }
        if let call = message.call { return CallFormat.summary(call, isMine: isMine) }
        return message.type == .text ? message.text : message.type.placeholder
    }

    static func == (lhs: ChatMessageItem, rhs: ChatMessageItem) -> Bool {
        lhs.message == rhs.message && lhs.isMine == rhs.isMine && lhs.status == rhs.status
            && lhs.myReaction == rhs.myReaction && lhs.canEdit == rhs.canEdit
            && lhs.uploadProgress == rhs.uploadProgress && lhs.localThumbnailURL == rhs.localThumbnailURL
            && lhs.localOriginalURL == rhs.localOriginalURL
    }
}

@MainActor
@Observable
final class ChatViewModel {
    enum Phase: Equatable {
        /// Henüz bir kullanıcıyla yapılandırılmadı.
        case idle
        /// Sunucudan oda bilgisi bekleniyor.
        case loading
        /// Eşleşme yok: davet kodu oluştur / gir.
        case unpaired
        case ready
    }

    // MARK: Durum
    private(set) var phase: Phase = .idle
    private(set) var room: ChatRoomDTO?
    private(set) var messages: [ChatMessageItem] = []
    private(set) var invite: ChatInvite?
    private(set) var replyingTo: ChatMessageItem?
    private(set) var editing: ChatMessageItem?
    private(set) var searchResults: [ChatMessageItem] = []
    private(set) var isLoadingOlder = false
    private(set) var hasMoreOlder = false
    private(set) var isWorking = false
    private(set) var unreadCount = 0
    private(set) var now: Date
    /// Orijinal dosya yükleme ilerlemeleri (mesaj kimliği → 0…1).
    private(set) var uploadProgress: [String: Double] = [:]
    /// Tam ekran görüntüleyicideki indirme ilerlemeleri.
    private(set) var downloadProgress: [String: Double] = [:]
    /// Seçilen medya hazırlanıyor (önizleme üretimi / Hızlı modda küçültme).
    private(set) var isPreparingMedia = false
    /// Sohbet üstüne bırakılmış sticker'lar (8E), katman sırasına göre.
    private(set) var placements: [ChatPlacementItem] = []

    var draft = ""
    /// Seçilen baloncuk stili; metin ve sesli mesajlara eklenir (8F). `nil` = varsayılan.
    var outgoingBubble: ChatBubbleRef?
    var inviteCodeInput = ""
    var searchQuery = "" {
        didSet { if searchQuery != oldValue { updateSearch() } }
    }
    var errorMessage: String?

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    // MARK: Bağımlılıklar
    private let sync: ChatSyncing
    private let mediaStore: ChatMediaStoring
    private let processor: ChatMediaProcessing
    let files: ChatMediaFiles
    private let roomCache: ChatRoomCache
    private let clock: () -> Date
    private let makeID: () -> String

    private var context: ModelContext?
    private(set) var userID: String?
    private var userName = ""
    private var roomSubscription: ChatSubscription?
    private var messagesSubscription: ChatSubscription?
    private var placementsSubscription: ChatSubscription?
    private var isSyncingPlacements = false
    private var displayLimit = ChatLimits.pageSize
    private var remoteExhausted = false
    private var isVisible = false
    private var isFlushing = false
    private var flushRequested = false
    private var lastTypingSentAt: Date?
    private var typingTask: Task<Void, Never>?
    private var uploadTasks: [String: Task<Void, Never>] = [:]
    private var thumbnailLoads: Set<String> = []
    /// Ağ hatasından sonra orijinal yüklemesi bu zamana kadar kendiliğinden yeniden denenmez.
    private var uploadBackoff: [String: Date] = [:]
    static let uploadRetryDelay: TimeInterval = 20
    private var retryTimer: Task<Void, Never>?
    private let defaults: UserDefaults
    private let photoSaver: PhotoLibrarySaving
    /// Alıcı cihaz gelen orijalleri kendiliğinden indirir (bulut kopyası 60 gün sonra silinir).
    /// Uygulamada açık; testlerde ayrıca açılır.
    private let autoFetchOriginals: Bool
    private var originalFetchTask: Task<Void, Never>?
    private var originalFetchRequested = false
    /// Karşı tarafa push bildirimi isteği (8G). `nil`: gönderilmez (testler, sunucusuz kurulum).
    private let notifier: ChatNotifying?
    /// Uygulama açıkken yeni gelen mesaj (uygulama içi bildirim şeridi için).
    @ObservationIgnored var onIncoming: ((ChatMessageItem) -> Void)?
    /// Aynı orijal için eşzamanlı indirmeler (otomatik + görüntüleyici) tek indirmede birleşir.
    private var originalLoads: [String: Task<URL, Error>] = [:]

    /// Karşılıklı sohbet ya da kendine not sohbeti. İkisi aynı akışı kullanır.
    let kind: ChatRoomKind

    init(
        kind: ChatRoomKind = .partner,
        sync: ChatSyncing = ChatService(),
        mediaStore: ChatMediaStoring = MediaServerClient(),
        processor: ChatMediaProcessing = ChatMediaProcessor(),
        files: ChatMediaFiles = .live,
        defaults: UserDefaults = .standard,
        photoSaver: PhotoLibrarySaving = PhotoLibrarySaver(),
        autoFetchOriginals: Bool = false,
        notifier: ChatNotifying? = nil,
        clock: @escaping () -> Date = { .now },
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.sync = sync
        self.mediaStore = mediaStore
        self.processor = processor
        self.files = files
        self.defaults = defaults
        self.photoSaver = photoSaver
        self.autoFetchOriginals = autoFetchOriginals
        self.notifier = notifier
        self.kind = kind
        self.roomCache = ChatRoomCache(defaults: defaults, kind: kind)
        self.clock = clock
        self.makeID = makeID
        self.now = clock()
    }

    // MARK: Türetilen değerler

    var otherMemberID: String? {
        guard let userID else { return nil }
        return room?.otherMember(of: userID)
    }

    var partnerName: String {
        if kind == .personal {
            let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Ben (Sen)" : "\(name) (Sen)"
        }
        guard let room, let other = otherMemberID else { return "Sohbet" }
        return room.displayName(of: other)
    }

    var isPartnerTyping: Bool {
        guard let room, let other = otherMemberID else { return false }
        return room.isTyping(other, now: now)
    }

    var canSend: Bool {
        ChatText.sanitizedOutgoing(draft) != nil && room != nil
    }

    var draftIsTooLong: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).count > ChatLimits.maxTextLength
    }

    // MARK: Yaşam döngüsü

    func configure(context: ModelContext, user: AppUser) {
        if userID == user.id, self.context != nil {
            userName = user.displayName
            return
        }
        reset()
        self.context = context
        self.userID = user.id
        self.userName = user.displayName

        if let cached = roomCache.load(userID: user.id) {
            room = cached
            phase = .ready
            reloadMessages()
            startMessagesListener(chatID: cached.id)
        } else {
            phase = .loading
        }

        roomSubscription = sync.observeRoom(
            userID: user.id,
            kind: kind,
            onChange: { [weak self] room, fromCache in self?.handleRoom(room, isFromCache: fromCache) },
            onError: { [weak self] error in self?.handleListenerError(error) }
        )
        scheduleFlush()
    }

    /// Çıkış yapıldığında ya da kullanıcı değiştiğinde.
    func reset() {
        // Oturum kapanınca hiçbir arka plan görevi eski veritabanına dokunmasın.
        retryTimer?.cancel()
        retryTimer = nil
        originalFetchTask?.cancel()
        originalFetchTask = nil
        originalFetchRequested = false
        originalLoads.values.forEach { $0.cancel() }
        originalLoads = [:]
        typingTask?.cancel()
        typingTask = nil
        uploadTasks.values.forEach { $0.cancel() }
        uploadTasks = [:]
        uploadProgress = [:]
        uploadBackoff = [:]
        downloadProgress = [:]
        thumbnailLoads = []
        roomSubscription?.cancel()
        messagesSubscription?.cancel()
        placementsSubscription?.cancel()
        roomSubscription = nil
        messagesSubscription = nil
        placementsSubscription = nil
        placements = []
        context = nil
        userID = nil
        room = nil
        messages = []
        invite = nil
        replyingTo = nil
        editing = nil
        searchResults = []
        draft = ""
        unreadCount = 0
        displayLimit = ChatLimits.pageSize
        remoteExhausted = false
        hasMoreOlder = false
        lastTypingSentAt = nil
        phase = .idle
    }

    /// Sohbet ekranı görünür/gizli olunca; okundu bilgisi yalnızca ekran açıkken gönderilir.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            markVisibleAsRead()
        } else {
            stopTyping()
        }
    }

    /// Uygulama öne gelince bekleyenleri yeniden dener.
    func handleForeground() async {
        tick()
        markVisibleAsRead()
        // Öne gelince bekleme süresi beklenmez: bağlantı büyük olasılıkla değişti.
        uploadBackoff = [:]
        await flushOutbox()
        await syncPlacements()
        scheduleOriginalFetch()
    }

    /// Ekrandaki zamana bağlı bilgiler ("yazıyor…", düzenleme süresi) için periyodik yenileme.
    func tick() {
        now = clock()
        if editing != nil || messages.contains(where: \.canEdit) {
            reloadMessages()
        }
    }

    // MARK: Oda

    func handleRoom(_ newRoom: ChatRoomDTO?, isFromCache: Bool) {
        guard let userID else { return }
        if let newRoom {
            guard newRoom.members.contains(userID) else { return }
            // Diğer türdeki oda (ör. eşleşme ekranında kendi kodunu yapıştırınca açılan not sohbeti) bu modeli ilgilendirmez.
            guard ChatRoomKind.of(newRoom, userID: userID) == kind else { return }
            let changed = room?.id != newRoom.id
            room = newRoom
            roomCache.save(newRoom, userID: userID)
            invite = nil
            phase = .ready
            now = clock()
            if changed {
                displayLimit = ChatLimits.pageSize
                remoteExhausted = false
                reloadMessages()
                startMessagesListener(chatID: newRoom.id)
                scheduleFlush()
            }
            return
        }

        // Yerel önbellek boş dönebilir; kesin bilgi sunucudan gelir.
        if isFromCache {
            if room == nil { phase = .unpaired }
            return
        }
        if let old = room {
            // Oda sunucudan kaldırıldı (karşı taraf hesabını sildi).
            messagesSubscription?.cancel()
            messagesSubscription = nil
            placementsSubscription?.cancel()
            placementsSubscription = nil
            purgeLocal(chatID: old.id)
            roomCache.clear(userID: userID)
            room = nil
            messages = []
            placements = []
        }
        phase = .unpaired
    }

    private func handleListenerError(_ error: AppError) {
        if phase == .loading { phase = room == nil ? .unpaired : .ready }
        if case .firebaseNotConfigured = error {
            errorMessage = "Sohbet için Firebase kurulumu gerekli."
        } else if case .network = error {
            // Çevrimdışı: önbellek gösterilmeye devam eder.
        } else {
            errorMessage = error.errorDescription
        }
    }

    // MARK: Eşleşme

    func createInvite() async {
        guard let userID, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            invite = try await sync.createInvite(ownerID: userID, ownerName: userName, now: clock())
        } catch {
            errorMessage = AppError.map(error).errorDescription
        }
    }

    @discardableResult
    func redeemInvite() async -> Bool {
        guard let userID, !isWorking else { return false }
        let code = ChatInviteCode.normalize(inviteCodeInput)
        guard ChatInviteCode.isValid(code) else {
            errorMessage = "Davet kodu \(ChatInviteCode.length) karakterden oluşur (harf ve rakam)."
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let newRoom = try await sync.redeemInvite(code: code, userID: userID, userName: userName, now: clock())
            inviteCodeInput = ""
            // Kendi kodu kullanıldı: kod tükendi, gösterilmesin (açılan not sohbetini diğer model dinler).
            if invite?.code == code { invite = nil }
            handleRoom(newRoom, isFromCache: false)
            return true
        } catch {
            errorMessage = AppError.map(error).errorDescription
            return false
        }
    }

    // MARK: Mesajlar: uzak değişiklikler

    private func startMessagesListener(chatID: String) {
        startPlacementsListener(chatID: chatID)
        messagesSubscription?.cancel()
        messagesSubscription = sync.observeRecentMessages(
            chatID: chatID,
            limit: ChatLimits.pageSize,
            onChange: { [weak self] items in self?.handleRemoteMessages(items, chatID: chatID) },
            onError: { [weak self] error in self?.handleListenerError(error) }
        )
    }

    func handleRemoteMessages(_ items: [ChatMessageDTO], chatID: String) {
        guard room?.id == chatID else { return }
        // Önbellekte olmayan, az önce gelmiş karşı taraf mesajları: uygulama içi bildirim şeridi.
        let current = clock()
        let fresh = items.filter {
            $0.senderID != userID && !$0.deleted && cachedRecord(for: $0.id) == nil
                && abs(current.timeIntervalSince($0.createdAt)) < 120
        }.sorted { $0.createdAt < $1.createdAt }.map(\.id)
        // Son sayfa bir sayfadan azsa sunucuda daha eski mesaj yoktur (sayfalama başlamadan önce geçerli).
        if displayLimit == ChatLimits.pageSize { remoteExhausted = items.count < ChatLimits.pageSize }
        upsert(items, chatID: chatID)
        reloadMessages()
        if let onIncoming, !isVisible {
            for id in fresh {
                if let item = messages.first(where: { $0.id == id }) { onIncoming(item) }
            }
        }
        markVisibleAsRead()
        scheduleOriginalFetch()
    }

    /// Mesaj sunucuya yazılınca karşı tarafın cihazlarına bildirim istenir (en iyi çaba; ağ yoksa bir kez daha denenir).
    private func notifyRecipient(chatID: String, messageID: String) {
        guard kind == .partner, let notifier else { return }
        Task {
            for attempt in 0..<2 {
                do {
                    try await notifier.notify(chatID: chatID, messageID: messageID)
                    return
                } catch {
                    guard attempt == 0, AppError.map(error) == .network else { return }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
    }

    /// Sunucudan gelenleri önbelleğe yazar. Kuyrukta bekleyen yerel değişiklik varsa yerel hal kazanır;
    /// yalnızca karşı tarafın alanları (okundu, onun tepkisi) alınır.
    private func upsert(_ items: [ChatMessageDTO], chatID: String) {
        guard let context, let userID, !items.isEmpty else { return }
        let pending = Set(pendingOperations().map(\.messageID))

        for dto in items {
            if let record = cachedRecord(for: dto.id) {
                if dto.deleted, !record.deletedForEveryone, record.media != nil || record.audio != nil || record.sticker != nil {
                    // Karşı taraf herkesten sildi: indirilmiş dosyalar da kaldırılır.
                    removeLocalFiles(of: record)
                }
                if pending.contains(dto.id) {
                    if let readAt = dto.readAt { record.readAt = readAt }
                    if let listenedAt = dto.listenedAt { record.listenedAt = listenedAt }
                    var merged = dto.reactions
                    merged[userID] = record.reactions[userID]
                    record.reactions = merged
                } else {
                    record.apply(remote: dto)
                    if dto.senderID == userID {
                        record.sendState = dto.hasPendingWrites ? .pending : .sent
                    }
                }
            } else {
                let state: ChatSendState = (dto.senderID == userID && dto.hasPendingWrites) ? .pending : .sent
                context.insert(ChatMessageRecord(dto: dto, ownerID: userID, chatID: chatID, sendState: state))
            }
        }
        save()
    }

    // MARK: Gösterim

    func reloadMessages() {
        guard let context, let userID, let chatID = room?.id else {
            messages = []
            unreadCount = 0
            return
        }
        var descriptor = FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate { $0.ownerID == userID && $0.chatID == chatID && !$0.hiddenForMe },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = displayLimit + 1
        let records = (try? context.fetch(descriptor)) ?? []
        let localHasMore = records.count > displayLimit
        let pendingCreates = Set(pendingOperations().filter { $0.kind == .create }.map(\.messageID))

        messages = records.prefix(displayLimit).reversed().map { makeItem($0, pendingCreates: pendingCreates) }
        hasMoreOlder = localHasMore || !remoteExhausted

        let unread = FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate {
                $0.ownerID == userID && $0.chatID == chatID && $0.senderID != userID
                    && $0.readAt == nil && !$0.hiddenForMe && !$0.deletedForEveryone
            }
        )
        unreadCount = (try? context.fetchCount(unread)) ?? 0

        if !searchQuery.isEmpty { updateSearch() }
    }

    private func makeItem(_ record: ChatMessageRecord, pendingCreates: Set<String>) -> ChatMessageItem {
        let dto = record.dto
        let mine = dto.senderID == userID
        var status: ChatMessageStatus?
        if mine {
            if record.sendState == .failed {
                status = .failed
            } else if record.sendState == .pending || pendingCreates.contains(dto.id)
                        || (record.uploadStage.map { $0 < .done } ?? false) {
                status = .sending
            } else if dto.readAt != nil {
                status = .read
            } else {
                status = .delivered
            }
        }
        let canEdit = mine && dto.type == .text && !dto.deleted && status != .failed
            && now.timeIntervalSince(dto.createdAt) < ChatLimits.editWindow
        return ChatMessageItem(
            message: dto,
            isMine: mine,
            status: status,
            myReaction: userID.flatMap { dto.reactions[$0] },
            canEdit: canEdit,
            uploadProgress: status == .sending ? uploadProgress[dto.id] : nil,
            localThumbnailURL: dto.media == nil || dto.deleted ? nil : localThumbnailURL(for: record),
            localOriginalURL: (dto.media == nil && dto.audio == nil && dto.sticker == nil) || dto.deleted ? nil : localOriginalURL(for: record)
        )
    }

    /// Yukarı kaydırınca bir önceki sayfa: önce sunucudan (boşluk kalmasın diye), çevrimdışıysa önbellekten.
    func loadOlder() async {
        guard !isLoadingOlder, hasMoreOlder, let chatID = room?.id else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        let oldest = messages.first?.message.createdAt ?? clock()
        if !remoteExhausted {
            do {
                let older = try await sync.fetchMessages(chatID: chatID, before: oldest, limit: ChatLimits.pageSize)
                if older.count < ChatLimits.pageSize { remoteExhausted = true }
                upsert(older, chatID: chatID)
            } catch {
                // Çevrimdışı: önbellekteki eski mesajlarla devam edilir.
            }
        }
        displayLimit += ChatLimits.pageSize
        reloadMessages()
    }

    // MARK: Gönderme ve düzenleme

    func send() {
        if editing != nil {
            commitEdit()
            return
        }
        guard let context, let userID, let chatID = room?.id else { return }
        guard let text = ChatText.sanitizedOutgoing(draft) else {
            if draftIsTooLong { errorMessage = "Mesaj en fazla \(ChatLimits.maxTextLength) karakter olabilir." }
            return
        }
        let dto = ChatMessageDTO(
            id: makeID(),
            senderID: userID,
            type: .text,
            text: text,
            createdAt: clock(),
            replyTo: replyingTo.map { ChatReplyReference.make(from: $0.message) },
            bubble: outgoingBubble
        )
        context.insert(ChatMessageRecord(dto: dto, ownerID: userID, chatID: chatID, sendState: .pending))
        enqueue(.create, messageID: dto.id)
        draft = ""
        replyingTo = nil
        // Gönderim, sunucudaki "yazıyor" alanını da temizler.
        lastTypingSentAt = nil
        save()
        reloadMessages()
        scheduleFlush()
    }

    func beginReply(to item: ChatMessageItem) {
        guard !item.message.deleted else { return }
        if editing != nil { draft = "" }
        editing = nil
        replyingTo = item
    }

    func beginEdit(_ item: ChatMessageItem) {
        guard item.canEdit else { return }
        replyingTo = nil
        editing = item
        draft = item.message.text
    }

    /// Alıntıyı ya da düzenlemeyi bırakır.
    func cancelComposerContext() {
        if editing != nil { draft = "" }
        editing = nil
        replyingTo = nil
    }

    private func commitEdit() {
        guard let item = editing, let record = cachedRecord(for: item.id) else {
            cancelComposerContext()
            return
        }
        guard let text = ChatText.sanitizedOutgoing(draft) else {
            if draftIsTooLong { errorMessage = "Mesaj en fazla \(ChatLimits.maxTextLength) karakter olabilir." }
            return
        }
        defer {
            editing = nil
            draft = ""
            save()
            reloadMessages()
            scheduleFlush()
        }
        guard text != record.text, !record.deletedForEveryone else { return }

        record.text = text
        if hasPendingCreate(item.id) {
            // Henüz sunucuya gitmedi: gönderim zaten güncel metni yollar, "düzenlendi" yazmaz.
            return
        }
        record.editedAt = clock()
        removeOperations(for: item.id, kinds: [.edit])
        enqueue(.edit, messageID: item.id, text: text)
    }

    /// Gönderilemeyen mesajı yeniden kuyruğa alır.
    func retry(_ item: ChatMessageItem) {
        guard item.status == .failed, let record = cachedRecord(for: item.id) else { return }
        record.sendState = .pending
        uploadBackoff[item.id] = nil
        let operations = pendingOperations().filter { $0.messageID == item.id }
        if let stage = record.uploadStage, stage >= .original, record.media != nil {
            // Mesaj belgesi sunucuda; yalnızca orijinal dosya yeniden yüklenir.
            if !operations.contains(where: { $0.kind == .uploadOriginal }) { enqueue(.uploadOriginal, messageID: item.id) }
            operations.filter { $0.kind == .uploadOriginal }.forEach { $0.attempts = 0 }
        } else if !operations.contains(where: { $0.kind == .create }) {
            enqueue(.create, messageID: item.id)
        }
        save()
        reloadMessages()
        scheduleFlush()
    }

    // MARK: Silme, tepki, kopyalama

    /// Yalnızca bu cihazdan gizler.
    func deleteForMe(_ item: ChatMessageItem) {
        guard let record = cachedRecord(for: item.id) else { return }
        record.hiddenForMe = true
        if !item.isUploading {
            // İndirilmiş kopyalar gereksiz; gönderimi süren kendi dosyamız yükleme bitene kadar kalır.
            removeLocalFiles(of: record)
        }
        clearComposer(ifReferencing: item.id)
        save()
        reloadMessages()
    }

    /// Kendi mesajını iki taraftan da siler ("Bu mesaj silindi" olarak kalır).
    func deleteForEveryone(_ item: ChatMessageItem) {
        guard item.isMine, let context, let record = cachedRecord(for: item.id) else { return }
        clearComposer(ifReferencing: item.id)

        // Süren yükleme durdurulur.
        uploadTasks[item.id]?.cancel()
        uploadTasks[item.id] = nil
        uploadProgress[item.id] = nil

        let media = record.media
        let audioPath = record.audio?.path ?? record.sticker?.path
        let thumbnailUploaded = (record.uploadStage.map { $0 >= .original } ?? true)
        removeLocalFiles(of: record)

        if hasPendingCreate(item.id) {
            // Mesaj belgesi sunucuya hiç gitmemiş: tamamen kaldırılır (önizleme yüklendiyse o da).
            removeOperations(for: item.id, kinds: nil)
            context.delete(record)
            if let media, thumbnailUploaded {
                let store = mediaStore
                Task { await store.delete(paths: [media.thumbnailPath]) }
            }
        } else {
            record.deletedForEveryone = true
            record.text = ""
            record.media = nil
            record.audio = nil
            record.sticker = nil
            record.uploadStage = nil
            record.localOriginalName = nil
            record.localThumbnailName = nil
            removeOperations(for: item.id, kinds: [.edit, .react, .uploadOriginal])
            // Storage'daki dosyalar, mesaj silindikten sonra kaldırılır (yollar işlemde saklanır).
            var paths = media.map { [$0.thumbnailPath, $0.originalPath] } ?? []
            if let audioPath { paths.append(audioPath) }
            enqueue(.deleteForEveryone, messageID: item.id, text: paths.isEmpty ? nil : paths.joined(separator: "\n"))
        }
        save()
        reloadMessages()
        scheduleFlush()
    }

    /// Aynı emojiye tekrar dokunmak tepkiyi kaldırır.
    func toggleReaction(_ emoji: String, on item: ChatMessageItem) {
        guard let userID, !item.message.deleted, let record = cachedRecord(for: item.id) else { return }
        var reactions = record.reactions
        let newValue: String? = reactions[userID] == emoji ? nil : emoji
        reactions[userID] = newValue
        record.reactions = reactions
        removeOperations(for: item.id, kinds: [.react])
        enqueue(.react, messageID: item.id, emoji: newValue)
        save()
        reloadMessages()
        scheduleFlush()
    }

    /// Panoya kopyalanacak metin (silinmiş / metin dışı mesajlarda yok).
    func copyText(for item: ChatMessageItem) -> String? {
        guard !item.message.deleted, item.message.type == .text else { return nil }
        return item.message.text
    }

    private func clearComposer(ifReferencing messageID: String) {
        if replyingTo?.id == messageID { replyingTo = nil }
        if editing?.id == messageID {
            editing = nil
            draft = ""
        }
    }

    // MARK: Okundu

    private func markVisibleAsRead() {
        guard isVisible, let context, let userID, let chatID = room?.id else { return }
        let descriptor = FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate {
                $0.ownerID == userID && $0.chatID == chatID && $0.senderID != userID && $0.readAt == nil
            }
        )
        let unread = (try? context.fetch(descriptor)) ?? []
        guard !unread.isEmpty else { return }
        let readAt = clock()
        let queued = Set(pendingOperations().filter { $0.kind == .markRead }.map(\.messageID))
        for record in unread {
            record.readAt = readAt
            if !queued.contains(record.messageID) { enqueue(.markRead, messageID: record.messageID) }
        }
        save()
        reloadMessages()
        scheduleFlush()
    }

    // MARK: Yazıyor…

    /// Taslak her değiştiğinde görünümden çağrılır; sunucuya en sık `typingThrottle` aralıkla yazar.
    func draftChanged() {
        guard let userID, let chatID = room?.id else { return }
        let isEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let current = clock()
        if isEmpty || editing != nil {
            stopTyping()
            return
        }
        if let last = lastTypingSentAt, current.timeIntervalSince(last) < ChatLimits.typingThrottle { return }
        lastTypingSentAt = current
        sendTyping(true, chatID: chatID, userID: userID, at: current)
    }

    private func stopTyping() {
        guard lastTypingSentAt != nil, let userID, let chatID = room?.id else { return }
        lastTypingSentAt = nil
        sendTyping(false, chatID: chatID, userID: userID, at: clock())
    }

    /// Sinyaller sırayla gider; "yazmayı bıraktı" bir önceki "yazıyor"un önüne geçmez.
    private func sendTyping(_ isTyping: Bool, chatID: String, userID: String, at date: Date) {
        // Not sohbetinde "yazıyor" gösterilecek kimse yok.
        guard kind == .partner else { return }
        let previous = typingTask
        let sync = sync
        typingTask = Task {
            await previous?.value
            try? await sync.setTyping(isTyping, chatID: chatID, userID: userID, at: date)
        }
    }

    // MARK: Arama

    private func updateSearch() {
        guard let context, let userID, let chatID = room?.id,
              !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        let descriptor = FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate {
                $0.ownerID == userID && $0.chatID == chatID && !$0.hiddenForMe && !$0.deletedForEveryone
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let query = searchQuery
        let pendingCreates = Set(pendingOperations().filter { $0.kind == .create }.map(\.messageID))
        searchResults = ((try? context.fetch(descriptor)) ?? [])
            .filter { ChatText.matches($0.text, query: query) }
            .map { makeItem($0, pendingCreates: pendingCreates) }
    }

    /// Arama sonucundaki mesaj ekranda yoksa gösterim penceresini genişletir.
    @discardableResult
    func reveal(messageID: String) -> Bool {
        if messages.contains(where: { $0.id == messageID }) { return true }
        guard let context, let userID, let chatID = room?.id, let target = cachedRecord(for: messageID) else { return false }
        let date = target.createdAt
        let newer = FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate {
                $0.ownerID == userID && $0.chatID == chatID && !$0.hiddenForMe && $0.createdAt >= date
            }
        )
        let count = (try? context.fetchCount(newer)) ?? 0
        displayLimit = max(displayLimit, count + 10)
        reloadMessages()
        return messages.contains { $0.id == messageID }
    }

    // MARK: Bekleyen kuyruk

    private func enqueue(_ kind: ChatOperationKind, messageID: String, text: String? = nil, emoji: String? = nil) {
        guard let context, let userID, let chatID = room?.id else { return }
        context.insert(ChatPendingOperation(
            ownerID: userID, chatID: chatID, messageID: messageID,
            kind: kind, text: text, emoji: emoji, createdAt: clock()
        ))
    }

    func pendingOperations() -> [ChatPendingOperation] {
        // İki oda (karşılıklı + not) aynı veritabanını paylaşır: her model yalnızca kendi odasının kuyruğunu işler.
        guard let context, let userID, let chatID = room?.id else { return [] }
        let descriptor = FetchDescriptor<ChatPendingOperation>(
            predicate: #Predicate { $0.ownerID == userID && $0.chatID == chatID },
            sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.kindRaw), SortDescriptor(\.messageID)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func hasPendingCreate(_ messageID: String) -> Bool {
        pendingOperations().contains { $0.messageID == messageID && $0.kind == .create }
    }

    /// `kinds == nil` ise mesajın tüm bekleyen işlemleri.
    private func removeOperations(for messageID: String, kinds: Set<ChatOperationKind>?) {
        guard let context else { return }
        for operation in pendingOperations() where operation.messageID == messageID {
            if kinds == nil || kinds!.contains(operation.kind) { context.delete(operation) }
        }
    }

    private func scheduleFlush() {
        Task { await flushOutbox() }
    }

    /// Kuyruğu sırayla sunucuya yazar. Ağ hatasında durur (sonra yeniden denenir);
    /// başka bir hatada üç denemeden sonra işlem bırakılır, mesaj "gönderilemedi" olur.
    func flushOutbox() async {
        guard !isFlushing else {
            flushRequested = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }

        repeat {
            flushRequested = false
            await drainOutbox()
        } while flushRequested
        startMediaUploads()
    }

    private func drainOutbox() async {
        // Orijinal dosya yüklemeleri sıralı kuyruğu bekletmez; `startMediaUploads` ayrıca yürütür.
        while let context, let operation = pendingOperations().first(where: { $0.kind != .uploadOriginal }) {
            let operationID = operation.id
            let kind = operation.kind
            let chatID = operation.chatID
            let messageID = operation.messageID
            var batchIDs: [UUID] = [operationID]

            do {
                switch kind {
                case .create:
                    guard let record = cachedRecord(for: messageID), !record.deletedForEveryone else {
                        context.delete(operation)
                        save()
                        continue
                    }
                    if let media = record.media, record.uploadStage == .thumbnail {
                        // Önce küçük önizleme: karşı taraf mesajı hemen görür, orijinal arkadan gelir.
                        guard let name = record.localThumbnailName, files.exists(files.outgoingURL(named: name)) else {
                            throw AppError.storage("Önizleme dosyası cihazda bulunamadı.")
                        }
                        try await mediaStore.upload(
                            fileURL: files.outgoingURL(named: name), to: media.thumbnailPath,
                            contentType: "image/jpeg", senderID: operation.ownerID, progress: { _ in }
                        )
                        cachedRecord(for: messageID)?.uploadStage = .original
                        save()
                    }
                    if let upload = singleFileUpload(of: record), record.uploadStage == .original {
                        // Sesli mesaj ve sticker küçüktür: dosya önce yüklenir, mesaj hazır olarak yazılır (alıcı hemen açabilir).
                        guard let name = record.localOriginalName, files.exists(files.outgoingURL(named: name)) else {
                            throw AppError.storage("Gönderilecek dosya cihazda bulunamadı.")
                        }
                        try await mediaStore.upload(
                            fileURL: files.outgoingURL(named: name), to: upload.path,
                            contentType: upload.contentType, senderID: operation.ownerID,
                            progress: { [weak self] value in self?.setAudioProgress(value, for: messageID) }
                        )
                        cachedRecord(for: messageID)?.uploadStage = .done
                        uploadProgress[messageID] = nil
                        save()
                    }
                    guard let fresh = cachedRecord(for: messageID), !fresh.deletedForEveryone else {
                        finish(batchIDs, kind: kind, messageID: messageID, succeeded: true)
                        continue
                    }
                    try await sync.sendMessage(fresh.dto, chatID: chatID)
                    notifyRecipient(chatID: chatID, messageID: messageID)
                case .edit:
                    let text = operation.text ?? cachedRecord(for: messageID)?.text ?? ""
                    let editedAt = cachedRecord(for: messageID)?.editedAt ?? operation.createdAt
                    try await sync.editMessage(id: messageID, chatID: chatID, text: text, editedAt: editedAt)
                case .deleteForEveryone:
                    let paths = (operation.text ?? "").split(separator: "\n").map(String.init)
                    try await sync.deleteMessageForEveryone(id: messageID, chatID: chatID)
                    if !paths.isEmpty { await mediaStore.delete(paths: paths) }
                case .react:
                    try await sync.setReaction(operation.emoji, messageID: messageID, chatID: chatID, userID: operation.ownerID)
                case .markRead:
                    // Aynı sohbetteki tüm bekleyen okundu bilgileri tek toplu yazımda gider.
                    let reads = pendingOperations().filter { $0.kind == .markRead && $0.chatID == chatID }
                    batchIDs = reads.map(\.id)
                    let readAt = cachedRecord(for: messageID)?.readAt ?? operation.createdAt
                    try await sync.markRead(messageIDs: reads.map(\.messageID), chatID: chatID, at: readAt)
                case .markListened:
                    let listenedAt = cachedRecord(for: messageID)?.listenedAt ?? operation.createdAt
                    try await sync.markListened(messageID: messageID, chatID: chatID, at: listenedAt)
                case .uploadOriginal:
                    continue
                }
                finish(batchIDs, kind: kind, messageID: messageID, succeeded: true)
            } catch {
                let appError = AppError.map(error)
                switch appError {
                case .network, .firebaseNotConfigured, .notAuthenticated:
                    // Bağlantı gelince yeniden denenir.
                    return
                default:
                    guard let current = pendingOperation(id: operationID) else { continue }
                    current.attempts += 1
                    if current.attempts >= 3 {
                        finish(batchIDs, kind: kind, messageID: messageID, succeeded: false)
                    } else {
                        save()
                        return
                    }
                }
            }
        }
    }

    private func finish(_ operationIDs: [UUID], kind: ChatOperationKind, messageID: String, succeeded: Bool) {
        guard let context else { return }
        // Bekleme sırasında kullanıcı işlemi iptal etmiş olabilir; yeniden okunur.
        for id in operationIDs {
            if let stale = pendingOperation(id: id) { context.delete(stale) }
        }
        if kind == .create, let record = cachedRecord(for: messageID), !hasPendingCreate(messageID) {
            record.sendState = succeeded ? .sent : .failed
            if succeeded, record.audio != nil || record.sticker != nil { moveOutgoingToCache(record) }
        }
        save()
        reloadMessages()
        if kind == .create, succeeded { startMediaUploads() }
    }

    // MARK: Medya: gönderme

    /// Galeriden ya da kameradan gelenleri gönderir. Önizleme cihazda üretilir; her dosya ayrı mesajdır.
    func sendMedia(_ items: [PickedMedia], quality: ChatMediaQuality) async {
        guard let userID, let chatID = room?.id, context != nil, !items.isEmpty else { return }
        isPreparingMedia = true
        defer { isPreparingMedia = false }
        var reply = replyingTo.map { ChatReplyReference.make(from: $0.message) }
        replyingTo = nil

        for picked in items {
            defer { files.remove([picked.fileURL]) }
            let messageID = makeID()
            do {
                let prepared = try await processor.prepare(picked, quality: quality, messageID: messageID, directory: files.outgoingDirectory)
                // Hazırlık sürerken oturum değiştiyse gönderilmez.
                guard let context, self.userID == userID, room?.id == chatID else {
                    files.remove([files.outgoingURL(named: prepared.originalFileName), files.outgoingURL(named: prepared.thumbnailFileName)])
                    return
                }
                let media = ChatMedia(
                    originalPath: ChatMediaPath.original(chatID: chatID, messageID: messageID, fileExtension: prepared.fileExtension),
                    thumbnailPath: ChatMediaPath.thumbnail(chatID: chatID, messageID: messageID),
                    contentType: prepared.contentType,
                    fileExtension: ChatMediaPath.sanitizedExtension(prepared.fileExtension),
                    byteSize: prepared.byteSize,
                    width: prepared.width,
                    height: prepared.height,
                    duration: prepared.duration,
                    quality: quality,
                    status: .uploading
                )
                let dto = ChatMessageDTO(
                    id: messageID, senderID: userID, type: picked.kind.messageType, text: "",
                    createdAt: clock(), replyTo: reply, media: media
                )
                reply = nil
                let record = ChatMessageRecord(dto: dto, ownerID: userID, chatID: chatID, sendState: .pending)
                record.localOriginalName = prepared.originalFileName
                record.localThumbnailName = prepared.thumbnailFileName
                record.uploadStage = .thumbnail
                context.insert(record)
                enqueue(.create, messageID: messageID)
                enqueue(.uploadOriginal, messageID: messageID)
                save()
                reloadMessages()
                scheduleFlush()
            } catch {
                errorMessage = AppError.map(error).errorDescription
            }
        }
    }

    /// Yüklemeyi iptal eder: mesaj iki taraftan da kaldırılır.
    func cancelUpload(_ item: ChatMessageItem) {
        guard item.isUploading else { return }
        deleteForEveryone(item)
    }

    /// Önizlemesi yüklenmiş, belgesi sunucuda olan mesajların orijinallerini paralel yükler.
    func startMediaUploads() {
        guard userID != nil else { return }
        let current = clock()
        for operation in pendingOperations() where operation.kind == .uploadOriginal && uploadTasks[operation.messageID] == nil {
            let messageID = operation.messageID
            if let retryAt = uploadBackoff[messageID], retryAt > current { continue }
            guard let record = cachedRecord(for: messageID), record.sendState != .failed,
                  let stage = record.uploadStage, stage >= .original, !hasPendingCreate(messageID) else { continue }
            let chatID = operation.chatID
            uploadTasks[messageID] = Task { [weak self] in
                await self?.runUpload(messageID: messageID, chatID: chatID)
                self?.uploadTasks[messageID] = nil
            }
        }
    }

    private func runUpload(messageID: String, chatID: String) async {
        guard let userID, let record = cachedRecord(for: messageID), var media = record.media else { return }
        do {
            if record.uploadStage == .original {
                guard let name = record.localOriginalName, files.exists(files.outgoingURL(named: name)) else {
                    throw AppError.storage("Gönderilecek dosya cihazda bulunamadı.")
                }
                uploadProgress[messageID] = 0
                reloadMessages()
                try await mediaStore.upload(
                    fileURL: files.outgoingURL(named: name), to: media.originalPath,
                    contentType: media.contentType, senderID: userID,
                    progress: { [weak self] value in self?.setUploadProgress(value, for: messageID) }
                )
                guard let current = cachedRecord(for: messageID) else { return }
                current.uploadStage = .finalize
                save()
            }
            media.status = .ready
            try await sync.updateMedia(media, messageID: messageID, chatID: chatID)

            guard let current = cachedRecord(for: messageID) else { return }
            current.media = media
            current.uploadStage = .done
            current.sendState = .sent
            moveOutgoingToCache(current)
            if kind == .personal {
                // Not sohbetinde alıcı da benim: orijal bu cihazda, bulut kopyası 60 gün sonra temizlenebilir.
                let store = mediaStore
                let path = media.originalPath
                Task { try? await store.acknowledge(path: path) }
            }
            removeOperations(for: messageID, kinds: [.uploadOriginal])
            uploadProgress[messageID] = nil
            uploadBackoff[messageID] = nil
            save()
            reloadMessages()
        } catch is CancellationError {
            uploadProgress[messageID] = nil
        } catch {
            uploadProgress[messageID] = nil
            switch AppError.map(error) {
            case .network, .firebaseNotConfigured, .notAuthenticated:
                // Bağlantı gelince (uygulama öne gelince ya da kısa bir beklemeden sonra) kaldığı aşamadan sürer.
                uploadBackoff[messageID] = clock().addingTimeInterval(Self.uploadRetryDelay)
                let delay = Self.uploadRetryDelay
                retryTimer?.cancel()
                retryTimer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.startMediaUploads()
                }
            default:
                if let operation = pendingOperations().first(where: { $0.messageID == messageID && $0.kind == .uploadOriginal }) {
                    operation.attempts += 1
                    if operation.attempts >= 3 {
                        context?.delete(operation)
                        cachedRecord(for: messageID)?.sendState = .failed
                    }
                }
                if pendingOperations().contains(where: { $0.messageID == messageID && $0.kind == .uploadOriginal }) {
                    // Bir sonraki denemede yeniden başlatılsın.
                    save()
                    reloadMessages()
                    return
                }
            }
            save()
            reloadMessages()
        }
    }

    private func setUploadProgress(_ value: Double, for messageID: String) {
        guard uploadTasks[messageID] != nil else { return }
        uploadProgress[messageID] = value
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].uploadProgress = value
        }
    }

    /// Yükleme bitince dosyalar silinmeyi bekleyen klasörden önbelleğe taşınır (görüntüleyici yine anında açılır).
    private func moveOutgoingToCache(_ record: ChatMessageRecord) {
        guard let ext = originalExtension(of: record) else { return }
        let fm = FileManager.default
        if let name = record.localOriginalName {
            let target = files.originalURL(messageID: record.messageID, fileExtension: ext)
            try? fm.removeItem(at: target)
            try? fm.moveItem(at: files.outgoingURL(named: name), to: target)
        }
        if let name = record.localThumbnailName {
            let target = files.cachedThumbnailURL(messageID: record.messageID)
            try? fm.removeItem(at: target)
            try? fm.moveItem(at: files.outgoingURL(named: name), to: target)
        }
        record.localOriginalName = nil
        record.localThumbnailName = nil
    }

    // MARK: Sesli mesaj

    /// Kaydı biten sesi gönderir: dosya hemen yüklenir, ardından mesaj yazılır.
    func sendVoice(_ voice: RecordedVoice) {
        guard let context, let userID, let chatID = room?.id else {
            files.remove([voice.fileURL])
            return
        }
        let messageID = makeID()
        let fileName = "\(messageID).\(ChatAudioPath.fileExtension)"
        let destination = files.outgoingURL(named: fileName)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: voice.fileURL, to: destination)
        } catch {
            errorMessage = "Ses kaydı kaydedilemedi."
            files.remove([voice.fileURL])
            return
        }
        let audio = ChatAudio(
            path: ChatAudioPath.voice(chatID: chatID, messageID: messageID),
            contentType: ChatAudioPath.contentType,
            byteSize: ChatMediaProcessor.fileSize(destination),
            duration: voice.duration,
            waveform: voice.waveform
        )
        let dto = ChatMessageDTO(
            id: messageID, senderID: userID, type: .audio, text: "", createdAt: clock(),
            replyTo: replyingTo.map { ChatReplyReference.make(from: $0.message) },
            audio: audio,
            bubble: outgoingBubble
        )
        replyingTo = nil
        let record = ChatMessageRecord(dto: dto, ownerID: userID, chatID: chatID, sendState: .pending)
        record.localOriginalName = fileName
        record.uploadStage = .original
        context.insert(record)
        enqueue(.create, messageID: messageID)
        save()
        reloadMessages()
        scheduleFlush()
    }

    private func setAudioProgress(_ value: Double, for messageID: String) {
        uploadProgress[messageID] = value
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].uploadProgress = value
        }
    }

    /// Çalmak için ses dosyası: cihazda yoksa indirilir (bir kez).
    func loadAudio(for item: ChatMessageItem) async throws -> URL {
        guard item.message.audio != nil else { throw AppError.storage("Bu mesajda ses yok.") }
        return try await loadAttachment(for: item)
    }

    /// Sesli mesaj ya da sticker dosyası: cihazda yoksa indirilir (bir kez).
    func loadAttachment(for item: ChatMessageItem) async throws -> URL {
        if let url = item.localOriginalURL { return url }
        guard !item.message.deleted else { throw AppError.storage("Bu mesaj silindi.") }
        let path: String
        let ext: String
        if let audio = item.message.audio {
            path = audio.path
            ext = ChatAudioPath.fileExtension
        } else if let sticker = item.message.sticker {
            path = sticker.path
            ext = ChatStickerPath.fileExtension
        } else {
            throw AppError.storage("Bu mesajda dosya yok.")
        }
        let destination = files.originalURL(messageID: item.id, fileExtension: ext)
        if files.exists(destination) { return destination }
        downloadProgress[item.id] = 0
        defer { downloadProgress[item.id] = nil }
        try await mediaStore.download(path: path, to: destination, progress: { [weak self] value in
            self?.downloadProgress[item.id] = value
        })
        reloadMessages()
        return destination
    }

    /// Mesaj belgesinden önce yüklenen tek dosya (ses / sticker).
    private func singleFileUpload(of record: ChatMessageRecord) -> (path: String, contentType: String)? {
        if let audio = record.audio { return (audio.path, audio.contentType) }
        if let sticker = record.sticker { return (sticker.path, ChatStickerPath.contentType) }
        return nil
    }

    /// Alıcı sesli mesajı çalmaya başladı: "dinlendi" bilgisi gönderilir (okundu da sayılır).
    func markListened(_ messageID: String) {
        guard let record = cachedRecord(for: messageID), record.senderID != userID,
              record.audio != nil, record.listenedAt == nil, !record.deletedForEveryone else { return }
        let now = clock()
        record.listenedAt = now
        if record.readAt == nil {
            record.readAt = now
            enqueue(.markRead, messageID: messageID)
        }
        enqueue(.markListened, messageID: messageID)
        save()
        reloadMessages()
        scheduleFlush()
    }

    // MARK: Sticker mesajı (8E)

    /// Kütüphanedeki PNG'yi normal bir mesaj (`type: sticker`) olarak gönderir.
    func sendSticker(fileURL: URL, width: Int, height: Int) {
        guard let context, let userID, let chatID = room?.id else { return }
        let messageID = makeID()
        let fileName = "\(messageID).\(ChatStickerPath.fileExtension)"
        let destination = files.outgoingURL(named: fileName)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: fileURL, to: destination)
        } catch {
            errorMessage = "Sticker hazırlanamadı."
            return
        }
        let dto = ChatMessageDTO(
            id: messageID, senderID: userID, type: .sticker, text: "", createdAt: clock(),
            replyTo: replyingTo.map { ChatReplyReference.make(from: $0.message) },
            sticker: ChatSticker(path: ChatStickerPath.file(chatID: chatID, itemID: messageID), width: width, height: height)
        )
        replyingTo = nil
        let record = ChatMessageRecord(dto: dto, ownerID: userID, chatID: chatID, sendState: .pending)
        record.localOriginalName = fileName
        record.uploadStage = .original
        context.insert(record)
        enqueue(.create, messageID: messageID)
        save()
        reloadMessages()
        scheduleFlush()
    }

    // MARK: Serbest yerleştirme (8E)

    private func startPlacementsListener(chatID: String) {
        placementsSubscription?.cancel()
        reloadPlacements()
        placementsSubscription = sync.observePlacements(
            chatID: chatID,
            onChange: { [weak self] items, fromCache in self?.handleRemotePlacements(items, chatID: chatID, isFromCache: fromCache) },
            onError: { [weak self] error in self?.handleListenerError(error) }
        )
        Task { await syncPlacements() }
    }

    /// Sunucudan gelenler önbelleğe yazılır; bekleyen yerel değişiklik kazanır.
    /// Sunucuda artık olmayan (sahibi sildi) kayıtlar, yalnızca sunucudan gelen kesin sonuçta kaldırılır.
    func handleRemotePlacements(_ items: [ChatPlacementDTO], chatID: String, isFromCache: Bool) {
        guard let context, let userID, room?.id == chatID else { return }
        let remoteIDs = Set(items.map(\.id))
        for dto in items {
            if let record = placementRecord(dto.id) {
                if !record.needsSync { record.apply(remote: dto) }
            } else {
                context.insert(ChatPlacementRecord(dto: dto, ownerID: userID, chatID: chatID, needsSync: false, isOnServer: true))
            }
        }
        if !isFromCache {
            for record in placementRecords(chatID: chatID) where !record.needsSync && record.isOnServer && !remoteIDs.contains(record.placementID) {
                removePlacementFiles(record)
                context.delete(record)
            }
        }
        save()
        reloadPlacements()
    }

    func reloadPlacements() {
        guard let userID, let chatID = room?.id else {
            placements = []
            return
        }
        placements = placementRecords(chatID: chatID)
            .filter { !$0.pendingDelete }
            .sorted { $0.z == $1.z ? $0.createdAt < $1.createdAt : $0.z < $1.z }
            .map { record in
                ChatPlacementItem(
                    placement: record.dto,
                    isMine: record.senderID == userID,
                    localImageURL: placementImageURL(record),
                    isSyncing: record.needsSync
                )
            }
    }

    /// Yeni yerleştirme. Konum hesabı görünümde (`PlacementGeometry.anchored`) yapılır.
    @discardableResult
    func placeSticker(fileURL: URL, width: Int, height: Int, anchorMessageID: String,
                      x: Double, y: Double, scale: Double, rotation: Double) -> String? {
        guard let context, let userID, let chatID = room?.id else { return nil }
        let placementID = makeID()
        let fileName = "placement-\(placementID).\(ChatStickerPath.fileExtension)"
        do {
            let destination = files.outgoingURL(named: fileName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: fileURL, to: destination)
        } catch {
            errorMessage = "Sticker hazırlanamadı."
            return nil
        }
        let now = clock()
        let topZ = placementRecords(chatID: chatID).map(\.z).max() ?? now.timeIntervalSince1970
        let dto = ChatPlacementDTO(
            id: placementID, senderID: userID, anchorMessageID: anchorMessageID,
            x: PlacementGeometry.clampX(x), y: y, scale: PlacementGeometry.clampScale(scale),
            rotation: PlacementGeometry.normalizedRotation(rotation), z: max(topZ + 1, now.timeIntervalSince1970),
            sticker: ChatSticker(path: ChatStickerPath.file(chatID: chatID, itemID: placementID), width: width, height: height),
            createdAt: now, updatedAt: now
        )
        let record = ChatPlacementRecord(dto: dto, ownerID: userID, chatID: chatID, needsSync: true, isOnServer: false)
        record.localFileName = fileName
        context.insert(record)
        save()
        reloadPlacements()
        Task { await syncPlacements() }
        return placementID
    }

    /// Yerleştiren kişi taşır / büyütür / döndürür.
    func movePlacement(_ id: String, anchorMessageID: String, x: Double, y: Double, scale: Double, rotation: Double) {
        guard let record = placementRecord(id), record.senderID == userID, !record.pendingDelete else { return }
        record.anchorMessageID = anchorMessageID
        record.x = PlacementGeometry.clampX(x)
        record.y = y
        record.scale = PlacementGeometry.clampScale(scale)
        record.rotation = PlacementGeometry.normalizedRotation(rotation)
        markPlacementChanged(record)
    }

    /// Öne al / arkaya al.
    func reorderPlacement(_ id: String, toFront: Bool) {
        guard let record = placementRecord(id), record.senderID == userID, let chatID = room?.id else { return }
        let others = placementRecords(chatID: chatID).filter { $0.placementID != id && !$0.pendingDelete }.map(\.z)
        if toFront {
            record.z = (others.max() ?? record.z) + 1
        } else {
            record.z = (others.min() ?? record.z) - 1
        }
        markPlacementChanged(record)
    }

    func deletePlacement(_ id: String) {
        guard let context, let record = placementRecord(id), record.senderID == userID else { return }
        if record.isOnServer {
            record.pendingDelete = true
            record.needsSync = true
        } else {
            // Sunucuya hiç gitmemiş: dosyası yüklendiyse o da silinir.
            if record.fileUploaded {
                let store = mediaStore, path = record.sticker.path
                Task { await store.delete(paths: [path]) }
            }
            removePlacementFiles(record)
            context.delete(record)
        }
        save()
        reloadPlacements()
        Task { await syncPlacements() }
    }

    private func markPlacementChanged(_ record: ChatPlacementRecord) {
        record.updatedAt = clock()
        record.needsSync = true
        save()
        reloadPlacements()
        Task { await syncPlacements() }
    }

    /// Bekleyen yerleştirmeleri sırayla sunucuya yazar (önce PNG, sonra belge). Ağ hatasında durur.
    func syncPlacements() async {
        guard !isSyncingPlacements, let userID, let chatID = room?.id else { return }
        isSyncingPlacements = true
        defer { isSyncingPlacements = false }

        // Kimliklerle dönülür; her adımda kayıt yeniden okunur (oturum kapanırsa güvenle durur).
        let pendingIDs = placementRecords(chatID: chatID).filter(\.needsSync).map(\.placementID)
        for id in pendingIDs {
            guard let record = placementRecord(id), record.needsSync else { continue }
            do {
                if record.pendingDelete {
                    let path = record.sticker.path
                    try await sync.deletePlacement(id: id, chatID: chatID)
                    await mediaStore.delete(paths: [path])
                    if let current = placementRecord(id) {
                        removePlacementFiles(current)
                        context?.delete(current)
                    }
                } else {
                    if !record.fileUploaded {
                        guard let name = record.localFileName, files.exists(files.outgoingURL(named: name)) else {
                            throw AppError.storage("Sticker dosyası cihazda bulunamadı.")
                        }
                        try await mediaStore.upload(fileURL: files.outgoingURL(named: name), to: record.sticker.path,
                                                    contentType: ChatStickerPath.contentType, senderID: userID, progress: { _ in })
                        placementRecord(id)?.fileUploaded = true
                        save()
                    }
                    guard let current = placementRecord(id), !current.pendingDelete else { continue }
                    let dto = current.dto
                    try await sync.savePlacement(dto, chatID: chatID)
                    if let fresh = placementRecord(id) {
                        fresh.isOnServer = true
                        // Yazım sırasında yeni değişiklik olmadıysa eşitlendi.
                        if fresh.dto == dto { fresh.needsSync = false }
                        movePlacementFileToCache(fresh)
                    }
                }
                save()
            } catch {
                save()
                if case .network = AppError.map(error) { break }
                errorMessage = AppError.map(error).errorDescription
            }
        }
        reloadPlacements()
    }

    /// Yerleştirmenin PNG'si: cihazda yoksa indirilir.
    func loadPlacementImage(_ item: ChatPlacementItem) async -> URL? {
        if let url = item.localImageURL { return url }
        let destination = files.originalURL(messageID: "placement-\(item.id)", fileExtension: ChatStickerPath.fileExtension)
        if files.exists(destination) { return destination }
        do {
            try await mediaStore.download(path: item.placement.sticker.path, to: destination, progress: { _ in })
            reloadPlacements()
            return destination
        } catch {
            return nil
        }
    }

    private func placementImageURL(_ record: ChatPlacementRecord) -> URL? {
        if let name = record.localFileName, files.exists(files.outgoingURL(named: name)) { return files.outgoingURL(named: name) }
        let cached = files.originalURL(messageID: "placement-\(record.placementID)", fileExtension: ChatStickerPath.fileExtension)
        return files.exists(cached) ? cached : nil
    }

    private func movePlacementFileToCache(_ record: ChatPlacementRecord) {
        guard let name = record.localFileName else { return }
        let target = files.originalURL(messageID: "placement-\(record.placementID)", fileExtension: ChatStickerPath.fileExtension)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: files.outgoingURL(named: name), to: target)
        record.localFileName = nil
    }

    private func removePlacementFiles(_ record: ChatPlacementRecord) {
        var urls = [files.originalURL(messageID: "placement-\(record.placementID)", fileExtension: ChatStickerPath.fileExtension)]
        if let name = record.localFileName { urls.append(files.outgoingURL(named: name)) }
        files.remove(urls)
    }

    private func placementRecords(chatID: String) -> [ChatPlacementRecord] {
        guard let context, let userID else { return [] }
        let descriptor = FetchDescriptor<ChatPlacementRecord>(predicate: #Predicate { $0.ownerID == userID && $0.chatID == chatID })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func placementRecord(_ id: String) -> ChatPlacementRecord? {
        guard let context, let userID else { return nil }
        let key = ChatPlacementRecord.key(ownerID: userID, placementID: id)
        var descriptor = FetchDescriptor<ChatPlacementRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: Medya: gösterme

    private func localThumbnailURL(for record: ChatMessageRecord) -> URL? {
        if let name = record.localThumbnailName, files.exists(files.outgoingURL(named: name)) {
            return files.outgoingURL(named: name)
        }
        let cached = files.cachedThumbnailURL(messageID: record.messageID)
        return files.exists(cached) ? cached : nil
    }

    private func localOriginalURL(for record: ChatMessageRecord) -> URL? {
        if let name = record.localOriginalName, files.exists(files.outgoingURL(named: name)) {
            return files.outgoingURL(named: name)
        }
        guard let ext = originalExtension(of: record) else { return nil }
        let cached = files.originalURL(messageID: record.messageID, fileExtension: ext)
        return files.exists(cached) ? cached : nil
    }

    /// Orijinal dosyanın uzantısı: fotoğraf/videoda kaydedilen, seste `m4a`.
    private func originalExtension(of record: ChatMessageRecord) -> String? {
        if let media = record.media { return media.fileExtension }
        if record.audio != nil { return ChatAudioPath.fileExtension }
        if record.sticker != nil { return ChatStickerPath.fileExtension }
        return nil
    }

    /// Karşı tarafın gönderdiği önizlemeyi indirir (bir kez; sonra önbellekten).
    @discardableResult
    func loadThumbnail(for item: ChatMessageItem) async -> URL? {
        if let url = item.localThumbnailURL { return url }
        guard let media = item.message.media, !item.message.deleted, !thumbnailLoads.contains(item.id) else { return nil }
        thumbnailLoads.insert(item.id)
        defer { thumbnailLoads.remove(item.id) }
        let destination = files.cachedThumbnailURL(messageID: item.id)
        do {
            try await mediaStore.download(path: media.thumbnailPath, to: destination, progress: { _ in })
            reloadMessages()
            return destination
        } catch {
            return nil
        }
    }

    /// Tam ekran için orijinal dosya: cihazda yoksa ilerlemeyle indirilir.
    func loadOriginal(for item: ChatMessageItem) async throws -> URL {
        if let url = item.localOriginalURL { return url }
        guard let media = item.message.media, !item.message.deleted else {
            throw AppError.storage("Bu mesajda dosya yok.")
        }
        guard media.status == .ready else {
            throw AppError.storage("Dosya hâlâ gönderiliyor, biraz sonra tekrar dene.")
        }
        if cachedRecord(for: item.id)?.originalUnavailable == true { throw AppError.mediaRemoved }
        return try await fetchOriginal(messageID: item.id, media: media)
    }

    /// Orijali kalıcı klasöre indirir; aynı anda gelen istekler tek indirmeyi bekler.
    private func fetchOriginal(messageID: String, media: ChatMedia) async throws -> URL {
        let destination = files.originalURL(messageID: messageID, fileExtension: media.fileExtension)
        if files.exists(destination) { return destination }
        if let running = originalLoads[messageID] { return try await running.value }
        let task = Task<URL, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            self.downloadProgress[messageID] = 0
            defer { self.downloadProgress[messageID] = nil }
            try await self.mediaStore.download(path: media.originalPath, to: destination, progress: { [weak self] value in
                self?.downloadProgress[messageID] = value
            })
            return destination
        }
        originalLoads[messageID] = task
        defer { originalLoads[messageID] = nil }
        do {
            let url = try await task.value
            reloadMessages()
            return url
        } catch {
            if AppError.map(error) == .mediaRemoved, let record = cachedRecord(for: messageID) {
                record.originalUnavailable = true
                save()
            }
            throw error
        }
    }

    // MARK: Gelen orijallerin cihaza alınması

    /// Gelen fotoğraf/videoların orijallerini arka planda sırayla indirir, sunucuya "aldım" der
    /// ve ayar açıksa Fotoğraflar'a kaydeder. Bulut, ancak bundan sonra orijali temizleyebilir.
    func scheduleOriginalFetch() {
        guard autoFetchOriginals, context != nil else { return }
        guard originalFetchTask == nil else {
            originalFetchRequested = true
            return
        }
        originalFetchTask = Task { [weak self] in
            await self?.fetchPendingOriginals()
            guard let self else { return }
            self.originalFetchTask = nil
            if self.originalFetchRequested {
                self.originalFetchRequested = false
                self.scheduleOriginalFetch()
            }
        }
    }

    /// Alınmayı bekleyen gelen orijaller (eskiden yeniye).
    func pendingIncomingOriginals() -> [ChatMessageRecord] {
        guard let context, let userID, let chatID = room?.id else { return [] }
        let descriptor = FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate {
                $0.ownerID == userID && $0.chatID == chatID && $0.senderID != userID
                    && !$0.deletedForEveryone && $0.mediaData != nil && !$0.originalAcked && !$0.originalUnavailable
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.media?.status == .ready }
    }

    func fetchPendingOriginals() async {
        for record in pendingIncomingOriginals() {
            guard !Task.isCancelled, context != nil, let media = record.media else { return }
            let messageID = record.messageID
            let destination = files.originalURL(messageID: messageID, fileExtension: media.fileExtension)
            let alreadyLocal = files.exists(destination)
            let url: URL
            do {
                url = try await fetchOriginal(messageID: messageID, media: media)
            } catch {
                // Ağ yoksa sonraki fırsata kalır; buluttan silinmişse kayıt işaretlendi.
                if AppError.map(error) == .network { return }
                continue
            }
            guard let current = cachedRecord(for: messageID), !current.deletedForEveryone else { continue }

            // Yalnızca bu adımda yeni indirilen dosyalar kaydedilir (eski indirilmişler Fotoğraflar'ı doldurmasın).
            if !alreadyLocal, !current.savedToPhotos, ChatMediaPreferences.autoSaveToPhotos(defaults) {
                try? await photoSaver.save(fileURL: url, isVideo: media.contentType.hasPrefix("video/"))
                current.savedToPhotos = true
                save()
            }
            do {
                try await mediaStore.acknowledge(path: media.originalPath)
                cachedRecord(for: messageID)?.originalAcked = true
                save()
            } catch {
                if AppError.map(error) == .network { return }
            }
        }
    }

    private func removeLocalFiles(of record: ChatMessageRecord) {
        var urls: [URL] = [files.cachedThumbnailURL(messageID: record.messageID)]
        if let ext = originalExtension(of: record) {
            urls.append(files.originalURL(messageID: record.messageID, fileExtension: ext))
        }
        if let name = record.localOriginalName { urls.append(files.outgoingURL(named: name)) }
        if let name = record.localThumbnailName { urls.append(files.outgoingURL(named: name)) }
        files.remove(urls)
    }

    // MARK: Önbellek yardımcıları

    private func cachedRecord(for messageID: String) -> ChatMessageRecord? {
        guard let context, let userID else { return nil }
        let key = ChatMessageRecord.key(ownerID: userID, messageID: messageID)
        var descriptor = FetchDescriptor<ChatMessageRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func pendingOperation(id: UUID) -> ChatPendingOperation? {
        guard let context else { return nil }
        var descriptor = FetchDescriptor<ChatPendingOperation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func purgeLocal(chatID: String) {
        guard let context, let userID else { return }
        let records = (try? context.fetch(FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate { $0.ownerID == userID && $0.chatID == chatID }
        ))) ?? []
        records.forEach {
            removeLocalFiles(of: $0)
            context.delete($0)
        }
        pendingOperations().filter { $0.chatID == chatID }.forEach { context.delete($0) }
        for placement in placementRecords(chatID: chatID) {
            removePlacementFiles(placement)
            context.delete(placement)
        }
        save()
    }

    private func save() {
        try? context?.save()
    }
}
