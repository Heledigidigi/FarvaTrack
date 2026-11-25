import Foundation
import Observation

/// Kullanıcı adı seçimi, arkadaş arama ve arkadaşlık istekleri.
@MainActor @Observable
final class FriendsViewModel {
    /// `nil`: henüz yüklenmedi; "": ad seçilmemiş.
    private(set) var myUsername: String?
    var usernameInput = ""
    private(set) var isSavingUsername = false

    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var results: [FriendProfile] = []
    private(set) var isSearching = false

    private(set) var incoming: [FriendRequest] = []
    private(set) var outgoing: [FriendRequest] = []
    /// İşlemi süren kişiler (düğmeler kilitlenir).
    private(set) var busy: Set<String> = []
    var errorMessage: String?

    /// Arkadaş odası açılınca (kabul ettiğimde) haber verilir; `ChatHub` odayı hemen listeye ekler.
    @ObservationIgnored var onRoomCreated: ((ChatRoomDTO) -> Void)?
    /// Zaten arkadaş olunan kişiler (oda var).
    @ObservationIgnored var friendIDs: () -> Set<String> = { [] }

    @ObservationIgnored private let service: FriendSyncing
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var subscription: ChatSubscription?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    private(set) var userID: String?
    private var displayName = ""
    private var photoURL: String?

    init(service: FriendSyncing = FriendService(), clock: @escaping () -> Date = { .now }, debounce: Duration = .milliseconds(300)) {
        self.service = service
        self.clock = clock
        self.debounce = debounce
    }

    var hasUsername: Bool { !(myUsername ?? "").isEmpty }
    var me: FriendProfile? {
        guard let userID, let myUsername, !myUsername.isEmpty else { return nil }
        return FriendProfile(userID: userID, username: myUsername, displayName: displayName, photoURL: photoURL)
    }

    func relation(to userID: String) -> FriendRelation {
        FriendRelation.of(userID, me: self.userID ?? "", friends: friendIDs(), incoming: incoming, outgoing: outgoing)
    }

    // MARK: Yaşam döngüsü

    func configure(user: AppUser) {
        displayName = user.displayName
        photoURL = user.photoURL
        guard userID != user.id else { return }
        reset()
        userID = user.id
        subscription = service.observeRequests(
            userID: user.id,
            onChange: { [weak self] incoming, outgoing in
                self?.incoming = incoming
                self?.outgoing = outgoing
            },
            onError: { [weak self] error in
                if case .network = error { return }
                self?.errorMessage = error.errorDescription
            }
        )
        Task { await loadUsername() }
    }

    func reset() {
        subscription?.cancel()
        subscription = nil
        searchTask?.cancel()
        userID = nil
        myUsername = nil
        usernameInput = ""
        query = ""
        results = []
        incoming = []
        outgoing = []
        busy = []
    }

    func loadUsername() async {
        guard let userID else { return }
        do {
            let name = try await service.username(of: userID) ?? ""
            guard self.userID == userID else { return }
            myUsername = name
            if name.isEmpty, usernameInput.isEmpty { usernameInput = ChatUsername.suggestion(from: displayName) }
        } catch {
            // Çevrimdışı: ad bilinmiyor; ekran yeniden deneme sunar.
        }
    }

    // MARK: Kullanıcı adı

    var usernameProblem: String? {
        let name = ChatUsername.normalize(usernameInput)
        return name.isEmpty ? nil : ChatUsername.problem(name)
    }

    @discardableResult
    func saveUsername() async -> Bool {
        guard let userID, !isSavingUsername else { return false }
        let name = ChatUsername.normalize(usernameInput)
        if let problem = ChatUsername.problem(name) {
            errorMessage = problem
            return false
        }
        isSavingUsername = true
        defer { isSavingUsername = false }
        do {
            try await service.claimUsername(name, userID: userID, displayName: displayName, photoURL: photoURL,
                                            previous: hasUsername ? myUsername : nil)
            myUsername = name
            usernameInput = name
            Haptics.success()
            return true
        } catch {
            errorMessage = AppError.map(error).errorDescription
            Haptics.error()
            return false
        }
    }

    // MARK: Arama

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = ChatUsername.normalize(query)
        guard !text.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        let debounce = debounce
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.search(text)
        }
    }

    func search(_ text: String) async {
        do {
            let found = try await service.search(prefix: text)
            guard ChatUsername.normalize(query) == text else { return }
            results = found
        } catch {
            errorMessage = AppError.map(error).errorDescription
        }
        isSearching = false
    }

    // MARK: İstekler

    /// Karşı taraf bana zaten istek göndermişse istek göndermek yerine kabul edilir.
    func add(_ profile: FriendProfile) async {
        guard let me, !busy.contains(profile.userID) else { return }
        if let reverse = incoming.first(where: { $0.from.userID == profile.userID }) {
            _ = await accept(reverse)
            return
        }
        busy.insert(profile.userID)
        defer { busy.remove(profile.userID) }
        do {
            try await service.sendRequest(from: me, to: profile, now: clock())
            // Dinleyici gelene kadar arayüz hemen güncellensin.
            if !outgoing.contains(where: { $0.to.userID == profile.userID }) {
                outgoing.insert(FriendRequest(from: me, to: profile, createdAt: clock()), at: 0)
            }
            Haptics.success()
        } catch {
            errorMessage = AppError.map(error).errorDescription
            Haptics.error()
        }
    }

    @discardableResult
    func accept(_ request: FriendRequest) async -> Bool {
        let other = request.from.userID
        guard !busy.contains(other) else { return false }
        busy.insert(other)
        defer { busy.remove(other) }
        do {
            let room = try await service.accept(request, roomExists: friendIDs().contains(other), now: clock())
            incoming.removeAll { $0.id == request.id }
            onRoomCreated?(room)
            Haptics.success()
            return true
        } catch {
            errorMessage = AppError.map(error).errorDescription
            Haptics.error()
            return false
        }
    }

    /// Gelen isteği reddet ya da gönderdiğimi geri çek.
    func remove(_ request: FriendRequest) async {
        let other = request.other(than: userID ?? "").userID
        guard !busy.contains(other) else { return }
        busy.insert(other)
        defer { busy.remove(other) }
        do {
            try await service.remove(request)
            incoming.removeAll { $0.id == request.id }
            outgoing.removeAll { $0.id == request.id }
            Haptics.selection()
        } catch {
            errorMessage = AppError.map(error).errorDescription
        }
    }
}
