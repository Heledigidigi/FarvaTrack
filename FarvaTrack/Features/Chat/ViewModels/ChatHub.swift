import Foundation
import Observation
import SwiftData
import UIKit

/// Uygulama açıkken gelen mesaj için üstte kısa süre görünen şerit (sistem bildirimi yerine).
struct ChatBanner: Identifiable, Equatable {
    let id: String
    let destination: ChatDestination
    let title: String
    let body: String
}

/// Sohbet sekmesindeki odalar: her arkadaşla ayrı oda ve kendine not sohbeti.
/// Her oda kendi `ChatViewModel`'iyle çalışır; burada odaların listesi, görünürlük ve ortak yaşam döngüsü yönetilir.
/// Arkadaş odalarının bilgisi tek bir dinleyiciden (`observeRooms`) gelir ve ilgili modele iletilir.
@MainActor @Observable
final class ChatHub {
    let personal: ChatViewModel
    let friends: FriendsViewModel
    /// Oda kimliği → model (arkadaş odaları).
    private(set) var rooms: [String: ChatViewModel] = [:]

    /// Uygulama önde mi.
    var isAppActive = true {
        didSet {
            updateVisibility()
            guard isAppActive != oldValue else { return }
            if isAppActive { startPresence() } else { stopPresence() }
        }
    }
    /// Önde olduğum sürece dakikada bir "çevrimiçi" sinyali.
    @ObservationIgnored private var presenceTask: Task<Void, Never>?
    /// Sohbet sekmesi ekranda mı.
    var isTabVisible = false { didSet { updateVisibility() } }
    /// Açık konuşma: yalnızca ekrandaki odanın mesajları okundu sayılır.
    var openConversation: ChatDestination? { didSet { updateVisibility() } }
    /// Uygulama içi bildirim şeridi.
    var banner: ChatBanner?
    /// Bildirime ya da şeride dokunulunca açılacak oda (sohbet ekranı tüketir).
    var pendingOpen: ChatDestination?
    /// Sunucudan oda listesi en az bir kez geldi mi (boş liste "arkadaşın yok" demektir).
    private(set) var hasLoadedRooms = false
    private(set) var isCreatingPersonal = false
    var errorMessage: String?

    @ObservationIgnored private let sync: ChatSyncing
    @ObservationIgnored private let friendService: FriendSyncing
    @ObservationIgnored private let makeRoom: (String) -> ChatViewModel
    @ObservationIgnored private let listCache: ChatRoomListCache
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var roomsSubscription: ChatSubscription?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var user: AppUser?

    init(
        sync: ChatSyncing,
        personal: ChatViewModel,
        friends: FriendsViewModel,
        friendService: FriendSyncing,
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = { .now },
        makeRoom: @escaping (String) -> ChatViewModel
    ) {
        self.sync = sync
        self.personal = personal
        self.friends = friends
        self.friendService = friendService
        self.listCache = ChatRoomListCache(defaults: defaults)
        self.clock = clock
        self.makeRoom = makeRoom
        personal.onIncoming = { [weak self] item in self?.incoming(item, destination: .personal) }
        friends.friendIDs = { [weak self] in self?.friendIDs ?? [] }
        friends.onRoomCreated = { [weak self] room in self?.upsert([room], isFromCache: false, removeMissing: false) }
    }

    convenience init() {
        let server = MediaServerClient()
        let sync = ChatService()
        let friendService = FriendService()
        self.init(sync: sync,
                  personal: ChatViewModel(kind: .personal, autoFetchOriginals: true, notifier: server),
                  friends: FriendsViewModel(service: friendService),
                  friendService: friendService) { chatID in
            ChatViewModel(kind: .partner, sync: sync, autoFetchOriginals: true, notifier: server, chatID: chatID)
        }
    }

    // MARK: Odalar

    /// Arkadaş odaları, en son mesajlaşılan üstte.
    var friendRooms: [ChatViewModel] {
        rooms.values.sorted { lhs, rhs in
            let left = Self.activity(lhs), right = Self.activity(rhs)
            return left != right ? left > right : lhs.partnerName < rhs.partnerName
        }
    }

    private static func activity(_ model: ChatViewModel) -> Date {
        model.messages.last?.message.createdAt ?? model.room?.lastMessage?.createdAt ?? model.room?.createdAt ?? .distantPast
    }

    /// Arkadaş olunan kişiler (odası olanlar).
    var friendIDs: Set<String> {
        Set(rooms.values.compactMap(\.otherMemberID))
    }

    func viewModel(for destination: ChatDestination) -> ChatViewModel? {
        switch destination {
        case .personal: return personal
        case .room(let chatID): return rooms[chatID]
        }
    }

    /// Oda kimliğinden hedef (push bildiriminde gelen `chatId`).
    func destination(forChatID chatID: String) -> ChatDestination? {
        if personal.room?.id == chatID { return .personal }
        if rooms[chatID] != nil { return .room(chatID) }
        return nil
    }

    /// Bildirim / şeritten: sohbet sekmesinde ilgili odayı aç.
    func open(_ destination: ChatDestination) {
        banner = nil
        pendingOpen = destination
    }

    /// Gelen aramaları dinlemek için: oda kimliği → kişinin adı.
    var callRooms: [String: String] {
        rooms.reduce(into: [:]) { result, entry in
            if entry.value.room != nil { result[entry.key] = entry.value.partnerName }
        }
    }

    private func incoming(_ item: ChatMessageItem, destination: ChatDestination) {
        // Arka planda sistem bildirimi gelir; ekrandaki konuşma için şerit gereksiz.
        guard isAppActive, !(isTabVisible && openConversation == destination),
              let model = viewModel(for: destination) else { return }
        banner = ChatBanner(id: item.id, destination: destination, title: model.partnerName, body: item.displayText)
    }

    var unreadCount: Int { rooms.values.reduce(personal.unreadCount) { $0 + $1.unreadCount } }

    /// Sağ üstteki "arkadaş ekle" düğmesindeki rozet.
    var incomingRequestCount: Int { friends.incoming.count }

    // MARK: Yaşam döngüsü

    func configure(context: ModelContext, user: AppUser) {
        let sameUser = self.user?.id == user.id && self.context != nil
        self.user = user
        personal.configure(context: context, user: user)
        friends.configure(user: user)
        if sameUser {
            for model in rooms.values { model.configure(context: context, user: user) }
            return
        }
        removeAllRooms()
        self.context = context

        // Çevrimdışı açılış: son bilinen odalar (eski sürümün tek odası da taşınır).
        var cached = listCache.load(userID: user.id)
        if cached.isEmpty, let legacy = ChatRoomCache(defaults: listCache.defaults, kind: .partner).load(userID: user.id) {
            cached = [legacy]
        }
        upsert(cached, isFromCache: true, removeMissing: false)

        roomsSubscription = sync.observeRooms(
            userID: user.id,
            onChange: { [weak self] rooms, fromCache in
                guard let self else { return }
                self.upsert(rooms, isFromCache: fromCache, removeMissing: !fromCache)
                if !fromCache { self.hasLoadedRooms = true }
            },
            onError: { [weak self] error in
                guard let self else { return }
                if case .network = error { return }
                self.hasLoadedRooms = true
                self.errorMessage = error.errorDescription
            }
        )
        if isAppActive, presenceTask == nil { startPresence() }
    }

    /// Sunucudan gelen odalar: yeni arkadaş odası için model açılır, kalkan oda (silinen hesap) kapanır.
    private func upsert(_ incoming: [ChatRoomDTO], isFromCache: Bool, removeMissing: Bool) {
        guard let user, let context else { return }
        let friendRooms = incoming.filter { $0.members.contains(user.id) && ChatRoomKind.of($0, userID: user.id) == .partner }
        for room in friendRooms {
            let model: ChatViewModel
            if let existing = rooms[room.id] {
                model = existing
            } else {
                model = makeRoom(room.id)
                let chatID = room.id
                model.onIncoming = { [weak self] item in self?.incoming(item, destination: .room(chatID)) }
                model.configure(context: context, user: user)
                rooms[room.id] = model
            }
            model.handleRoom(room, isFromCache: isFromCache)
        }
        if removeMissing {
            let present = Set(friendRooms.map(\.id))
            for (chatID, model) in rooms where !present.contains(chatID) {
                model.handleRoom(nil, isFromCache: false)
                model.reset()
                rooms[chatID] = nil
            }
        }
        if !isFromCache || removeMissing {
            listCache.save(rooms.values.compactMap(\.room), userID: user.id)
        }
        updateVisibility()
    }

    private func removeAllRooms() {
        roomsSubscription?.cancel()
        roomsSubscription = nil
        for model in rooms.values { model.reset() }
        rooms = [:]
        hasLoadedRooms = false
    }

    func reset() {
        presenceTask?.cancel()
        presenceTask = nil
        removeAllRooms()
        personal.reset()
        friends.reset()
        context = nil
        user = nil
        openConversation = nil
    }

    func handleForeground() async {
        await personal.handleForeground()
        for model in Array(rooms.values) { await model.handleForeground() }
    }

    func tick() {
        personal.tick()
        for model in rooms.values { model.tick() }
    }

    /// Tek dokunuşla kendime not sohbeti (davet kodu gerekmez).
    func createPersonalRoom() async -> Bool {
        guard let user, !isCreatingPersonal else { return false }
        isCreatingPersonal = true
        defer { isCreatingPersonal = false }
        do {
            let room = try await friendService.createPersonalRoom(userID: user.id, userName: user.displayName, now: clock())
            personal.handleRoom(room, isFromCache: false)
            return true
        } catch {
            errorMessage = AppError.map(error).errorDescription
            return false
        }
    }

    // MARK: Çevrimiçi / son görülme

    private func startPresence() {
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                // Bekleme sırasında merkez tutulmaz (zayıf başvuru).
                guard let models = self?.presenceTargets() else { return }
                var wroteAny = models.isEmpty
                for model in models {
                    if await model.updatePresence(online: true) { wroteAny = true }
                }
                // Odalar henüz yüklenmediyse ya da çevrimdışıysak kısa aralıkla yeniden denenir.
                try? await Task.sleep(for: .seconds(wroteAny ? ChatPresence.heartbeat : 5))
            }
        }
    }

    private func presenceTargets() -> [ChatViewModel] { Array(rooms.values) }

    /// Arka plana geçerken son görülme zamanı yazılır; sistem uygulamayı askıya almadan bitsin diye kısa ek süre istenir.
    private func stopPresence() {
        presenceTask?.cancel()
        presenceTask = nil
        let models = Array(rooms.values)
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "chat-presence") {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        Task {
            for model in models { await model.updatePresence(online: false) }
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }
    }

    private func updateVisibility() {
        let visible = isAppActive && isTabVisible
        personal.setVisible(visible && openConversation == .personal)
        for (chatID, model) in rooms {
            model.setVisible(visible && openConversation == .room(chatID))
        }
    }
}
