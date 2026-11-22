import SwiftUI
import UIKit

/// Profil fotoğrafı; yoksa baş harfler (o da yoksa kişi simgesi).
struct AvatarView: View {
    let name: String
    let photoURL: String?

    private var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.ftAccent, Color.ftAccentLight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            if let url = photoURL.flatMap(URL.init(string:)) {
                RemoteAvatarImage(url: url) { initialsView }
                    .clipShape(Circle())
            } else {
                initialsView
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var initialsView: some View {
        if initials.isEmpty {
            Image(systemName: "person.fill").foregroundStyle(.white)
        } else {
            Text(initials)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Önbellekli uzak fotoğraf

/// Profil fotoğrafları bellekte tutulur: sohbet başlığı, liste ve profil aynı adresi tekrar indirmez,
/// ekranlar arasında geçerken fotoğraf yanıp sönmez. Yeni fotoğraf yeni adresle geldiği için eski kayıt sorun olmaz.
@MainActor
enum AvatarImageCache {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 40
        return cache
    }()
    private static var inFlight: [URL: Task<UIImage?, Never>] = [:]

    static func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func load(_ url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        if let task = inFlight[url] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
            return await Task.detached(priority: .userInitiated) {
                UIImage(data: data)?.preparingForDisplay()
            }.value
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

struct RemoteAvatarImage<Placeholder: View>: View {
    let url: URL
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image ?? AvatarImageCache.cached(url) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = AvatarImageCache.cached(url)
            if image == nil { image = await AvatarImageCache.load(url) }
        }
    }
}

// MARK: - Çevrimiçi göstergeli avatar (sohbet)

/// Sağ altta yeşil (çevrimiçi) ya da gri (çevrimdışı) nokta; durum bilinmiyorsa nokta yok.
struct PresenceAvatarView: View {
    let name: String
    let photoURL: String?
    var presence: ChatPresenceStatus = .unknown
    var size: CGFloat = 40

    var body: some View {
        AvatarView(name: name, photoURL: photoURL)
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if presence != .unknown {
                    Circle()
                        .fill(presence.isOnline ? Color.ftOnline : Color.ftOffline)
                        .frame(width: max(8, size * 0.27), height: max(8, size * 0.27))
                        .overlay(Circle().strokeBorder(Color.ftBackground, lineWidth: max(1.5, size * 0.055)))
                        .offset(x: size * 0.02, y: size * 0.02)
                        .animation(.easeInOut(duration: 0.3), value: presence.isOnline)
                }
            }
    }
}

extension Color {
    /// Çevrimiçi göstergesi (sosyal uygulamalardaki yeşil).
    static let ftOnline = Color(red: 0.20, green: 0.80, blue: 0.40)
    /// Çevrimdışı göstergesi.
    static let ftOffline = Color(white: 0.55)
}
