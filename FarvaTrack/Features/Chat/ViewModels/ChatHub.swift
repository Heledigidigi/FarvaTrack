import Foundation
import Observation
import SwiftData

/// Sohbet sekmesindeki iki oda: karşılıklı sohbet ve kendine not sohbeti.
/// Her oda kendi `ChatViewModel`'iyle çalışır; burada yalnızca görünürlük ve ortak yaşam döngüsü yönetilir.
@MainActor @Observable
final class ChatHub {
    let partner: ChatViewModel
    let personal: ChatViewModel

    /// Uygulama önde mi.
    var isAppActive = true { didSet { updateVisibility() } }
    /// Sohbet sekmesi ekranda mı.
    var isTabVisible = false { didSet { updateVisibility() } }
    /// Açık konuşma: yalnızca ekrandaki odanın mesajları okundu sayılır.
    var openConversation: ChatRoomKind? { didSet { updateVisibility() } }

    init(partner: ChatViewModel, personal: ChatViewModel) {
        self.partner = partner
        self.personal = personal
    }

    convenience init() {
        self.init(partner: ChatViewModel(kind: .partner, autoFetchOriginals: true),
                  personal: ChatViewModel(kind: .personal, autoFetchOriginals: true))
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
    }

    func reset() {
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

    private func updateVisibility() {
        let visible = isAppActive && isTabVisible
        partner.setVisible(visible && openConversation == .partner)
        personal.setVisible(visible && openConversation == .personal)
    }
}
