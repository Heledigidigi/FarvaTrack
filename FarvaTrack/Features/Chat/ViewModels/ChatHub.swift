import Foundation
import Observation
import SwiftData
import UIKit

/// Uygulama açıkken gelen mesaj için üstte kısa süre görünen şerit (sistem bildirimi yerine).
struct ChatBanner: Identifiable, Equatable {
    let id: String
    let kind: ChatRoomKind
    let title: String
    let body: String
}

/// Sohbet sekmesindeki iki oda: karşılıklı sohbet ve kendine not sohbeti.
/// Her oda kendi `ChatViewModel`'iyle çalışır; burada yalnızca görünürlük ve ortak yaşam döngüsü yönetilir.
@MainActor @Observable
final class ChatHub {
    let partner: ChatViewModel
    let personal: ChatViewModel

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
    var openConversation: ChatRoomKind? { didSet { updateVisibility() } }
    /// Uygulama içi bildirim şeridi.
    var banner: ChatBanner?
    /// Bildirime ya da şeride dokunulunca açılacak oda (sohbet ekranı tüketir).
    var pendingOpen: ChatRoomKind?

    init(partner: ChatViewModel, personal: ChatViewModel) {
        self.partner = partner
        self.personal = personal
        for kind in ChatRoomKind.allCases {
            viewModel(for: kind).onIncoming = { [weak self] item in self?.incoming(item, kind: kind) }
        }
    }

    convenience init() {
        let server = MediaServerClient()
        self.init(partner: ChatViewModel(kind: .partner, autoFetchOriginals: true, notifier: server),
                  personal: ChatViewModel(kind: .personal, autoFetchOriginals: true, notifier: server))
    }

    /// Oda kimliğinden tür (push bildiriminde gelen `chatId`).
    func kind(forChatID chatID: String) -> ChatRoomKind? {
        if partner.room?.id == chatID { return .partner }
        if personal.room?.id == chatID { return .personal }
        return nil
    }

    /// Bildirim / şeritten: sohbet sekmesinde ilgili odayı aç.
    func open(_ kind: ChatRoomKind) {
        banner = nil
        pendingOpen = kind
    }

    private func incoming(_ item: ChatMessageItem, kind: ChatRoomKind) {
        // Arka planda sistem bildirimi gelir; ekrandaki konuşma için şerit gereksiz.
        guard isAppActive, !(isTabVisible && openConversation == kind) else { return }
        banner = ChatBanner(id: item.id, kind: kind, title: viewModel(for: kind).partnerName, body: item.displayText)
    }

    func viewModel(for kind: ChatRoomKind) -> ChatViewModel {
        kind == .partner ? partner : personal
    }

    /// Not sohbeti varsa sekme iki satırlık listeyle açılır; yoksa eskisi gibi doğrudan karşılıklı sohbet.
    var showsRoomList: Bool { personal.phase == .ready }

    var unreadCount: Int { partner.unreadCount + personal.unreadCount }

    func configure(context: ModelContext, user: AppUser) {
        partner.configure(context: context, user: user)
        personal.configure(context: context, user: user)
        if isAppActive, presenceTask == nil { startPresence() }
    }

    func reset() {
        presenceTask?.cancel()
        presenceTask = nil
        partner.reset()
        personal.reset()
        openConversation = nil
    }

    func handleForeground() async {
        await partner.handleForeground()
        await personal.handleForeground()
    }

    func tick() {
        partner.tick()
        personal.tick()
    }

    // MARK: Çevrimiçi / son görülme

    private func startPresence() {
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                // Bekleme sırasında merkez tutulmaz (zayıf başvuru).
                guard let wrote = await self?.partner.updatePresence(online: true) else { return }
                // Oda henüz yüklenmediyse ya da çevrimdışıysak kısa aralıkla yeniden denenir.
                try? await Task.sleep(for: .seconds(wrote ? ChatPresence.heartbeat : 5))
            }
        }
    }

    /// Arka plana geçerken son görülme zamanı yazılır; sistem uygulamayı askıya almadan bitsin diye kısa ek süre istenir.
    private func stopPresence() {
        presenceTask?.cancel()
        presenceTask = nil
        let partner = partner
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "chat-presence") {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        Task {
            await partner.updatePresence(online: false)
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }
    }

    private func updateVisibility() {
        let visible = isAppActive && isTabVisible
        partner.setVisible(visible && openConversation == .partner)
        personal.setVisible(visible && openConversation == .personal)
    }
}
