import Foundation

extension Notification.Name {
    static let farvaDeepLink = Notification.Name("farvaDeepLink")
}

/// Bildirimden gelen yönlendirmeyi, arayüz hazır olana kadar saklar.
@MainActor
enum DeepLinkCenter {
    private static var pendingURL: URL?

    static func open(_ url: URL) {
        pendingURL = url
        NotificationCenter.default.post(name: .farvaDeepLink, object: url)
    }

    static func consumePending() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }
}
