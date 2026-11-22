import Foundation
import UIKit
import UserNotifications
import Observation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

// MARK: - Cihaz kaydı

/// `users/{uid}/devices/{cihazId}`: FCM belirteci ve sessize alma. Medya sunucusu bildirimi buradan gönderir.
struct PushDevice: Equatable {
    var id: String
    var token: String
    var muted: Bool
    var appVersion: String
    /// PushKit VoIP belirteci (8H): kilit ekranında arama çalsın diye. Yoksa alan silinir.
    var voipToken: String? = nil
}

protocol PushDeviceStoring: AnyObject {
    func save(_ device: PushDevice, userID: String) async throws
    func delete(deviceID: String, userID: String) async throws
}

final class PushDeviceService: PushDeviceStoring {
    private func document(_ id: String, userID: String) throws -> DocumentReference {
        guard FirebaseBootstrap.isConfigured else { throw AppError.firebaseNotConfigured }
        return Firestore.firestore().collection(Constants.Collection.users).document(userID)
            .collection(Constants.Collection.devices).document(id)
    }

    func save(_ device: PushDevice, userID: String) async throws {
        do {
            try await document(device.id, userID: userID).setData([
                "token": device.token,
                "platform": "ios",
                "muted": device.muted,
                "appVersion": device.appVersion,
                "voipToken": device.voipToken ?? FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            throw AppError.map(error)
        }
    }

    func delete(deviceID: String, userID: String) async throws {
        do {
            try await document(deviceID, userID: userID).delete()
        } catch {
            throw AppError.map(error)
        }
    }
}

// MARK: - Sistem

/// İzin, APNs kaydı, FCM belirteci ve uygulama simgesi rozeti. Testlerde sahte uygulamayla değiştirilir.
protocol PushSystem: AnyObject {
    func requestAuthorization() async -> Bool
    func registerForRemoteNotifications()
    /// APNs kaydı yoksa (ücretsiz imza) `nil`.
    func fcmToken() async -> String?
    func deleteFCMToken() async
    func setBadge(_ count: Int)
}

final class LivePushSystem: PushSystem {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    func registerForRemoteNotifications() {
        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
    }

    func fcmToken() async -> String? {
        guard FirebaseBootstrap.isConfigured, Messaging.messaging().apnsToken != nil else { return nil }
        return try? await Messaging.messaging().token()
    }

    func deleteFCMToken() async {
        guard FirebaseBootstrap.isConfigured else { return }
        try? await Messaging.messaging().deleteToken()
    }

    func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count), withCompletionHandler: nil)
    }
}

// MARK: - Yönetici

enum PushAvailability: Equatable {
    case unknown
    /// Bildirimler bu cihaza gelir.
    case enabled
    /// Kullanıcı izin vermedi.
    case denied
    /// APNs kaydı yok (ücretli Apple Developer imzası gerekiyor).
    case unavailable
}

/// Push bildirimi kaydı (8G). Ücretsiz imzada APNs olmadığı için kayıt düşer; uygulama açıkken
/// mesajlar yine anlık dinleyiciyle gelir ve uygulama içi şeritte gösterilir.
@MainActor @Observable
final class PushManager {
    static let shared = PushManager()

    private(set) var availability: PushAvailability = .unknown
    /// Bu cihazda sohbet bildirimleri sessizde mi (sunucu bu cihaza göndermez).
    var muted: Bool {
        didSet {
            guard muted != oldValue else { return }
            defaults.set(muted, forKey: Self.mutedKey)
            Task { await saveDevice() }
        }
    }
    /// Bildirime dokunulunca açılacak sohbet (`MainTabView` tüketir).
    var pendingChatID: String?

    @ObservationIgnored private let system: PushSystem
    @ObservationIgnored private let devices: PushDeviceStoring
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private(set) var userID: String?
    @ObservationIgnored private var token: String?
    @ObservationIgnored private(set) var voipToken: String?

    static let mutedKey = "push.muted"
    static let deviceIDKey = "push.deviceID"

    init(system: PushSystem = LivePushSystem(),
         devices: PushDeviceStoring = PushDeviceService(),
         defaults: UserDefaults = .standard,
         appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") {
        self.system = system
        self.devices = devices
        self.defaults = defaults
        self.appVersion = appVersion
        self.muted = defaults.bool(forKey: Self.mutedKey)
    }

    /// Cihaza özel, kalıcı kimlik (belge adı).
    var deviceID: String {
        if let id = defaults.string(forKey: Self.deviceIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.deviceIDKey)
        return id
    }

    /// Oturum açılınca: izin iste, APNs'e kaydol; belirteç gelince Firestore'a yaz.
    func start(userID: String) async {
        if self.userID == userID, availability != .unknown { return }
        self.userID = userID
        guard await system.requestAuthorization() else {
            availability = .denied
            return
        }
        system.registerForRemoteNotifications()
        if let token = await system.fcmToken() { await tokenReceived(token) }
    }

    /// `AppDelegate`: APNs belirteci FCM'e verildi.
    func apnsRegistered() async {
        if let token = await system.fcmToken() { await tokenReceived(token) }
    }

    /// `AppDelegate`: APNs kaydı başarısız (ör. push yetkisi olmayan imza).
    func apnsFailed() {
        if availability != .enabled { availability = .unavailable }
    }

    /// FCM belirteci geldi ya da yenilendi.
    func tokenReceived(_ token: String) async {
        self.token = token
        availability = .enabled
        await saveDevice()
    }

    /// PushKit VoIP belirteci geldi / geçersizleşti (8H).
    func voipTokenReceived(_ token: String?) async {
        voipToken = token
        await saveDevice()
    }

    /// Oturum kapanırken: belirteç silinir (bu cihaza artık bildirim gitmez; sunucu eski kaydı ilk gönderimde temizler).
    func stop() async {
        if let userID { try? await devices.delete(deviceID: deviceID, userID: userID) }
        await system.deleteFCMToken()
        userID = nil
        token = nil
        availability = .unknown
        system.setBadge(0)
    }

    func setBadge(_ count: Int) {
        system.setBadge(count)
    }

    private func saveDevice() async {
        guard let userID, let token else { return }
        try? await devices.save(PushDevice(id: deviceID, token: token, muted: muted, appVersion: appVersion, voipToken: voipToken),
                                userID: userID)
    }

    var statusText: String {
        switch availability {
        case .enabled:
            return muted ? "Bu cihaza sohbet bildirimi gönderilmiyor." : "Yeni mesajlarda bildirim alırsın."
        case .denied:
            return "Bildirim izni kapalı. Ayarlar → Bildirimler → FarvaTrack'ten açabilirsin."
        case .unavailable:
            return "Bu kurulumda anlık bildirim yok (ücretli Apple Developer imzası gerekiyor). Uygulama açıkken mesajlar yine anında gelir."
        case .unknown:
            return "Bildirim durumu denetleniyor…"
        }
    }
}

// MARK: - Bildirim eylemleri

enum ChatNotificationAction {
    static let category = "CHAT_MESSAGE"
    static let reply = "CHAT_REPLY"
    static let markRead = "CHAT_MARK_READ"

    /// Bildirimde "Yanıtla" ve "Okundu işaretle".
    static func register() {
        let reply = UNTextInputNotificationAction(identifier: reply, title: "Yanıtla", options: [],
                                                  textInputButtonTitle: "Gönder", textInputPlaceholder: "Mesaj")
        let read = UNNotificationAction(identifier: markRead, title: "Okundu işaretle", options: [])
        let category = UNNotificationCategory(identifier: category, actions: [reply, read], intentIdentifiers: [],
                                              options: [.customDismissAction])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

/// Uygulama açılmadan, bildirimden yanıt ve okundu işaretleme. Doğrudan sunucuya yazar; sohbet ekranı
/// açıldığında dinleyici değişiklikleri önbelleğe alır.
@MainActor
final class ChatQuickActions {
    private let sync: ChatSyncing
    private let notifier: ChatNotifying?
    private let currentUserID: () -> String?
    private let clock: () -> Date
    private let makeID: () -> String

    init(sync: ChatSyncing = ChatService(),
         notifier: ChatNotifying? = MediaServerClient(),
         currentUserID: @escaping () -> String? = { FirebaseBootstrap.isConfigured ? Auth.auth().currentUser?.uid : nil },
         clock: @escaping () -> Date = { .now },
         makeID: @escaping () -> String = { UUID().uuidString }) {
        self.sync = sync
        self.notifier = notifier
        self.currentUserID = currentUserID
        self.clock = clock
        self.makeID = makeID
    }

    private func member(of chatID: String) throws -> String {
        guard let userID = currentUserID() else { throw AppError.notAuthenticated }
        guard chatID.split(separator: "_").contains(Substring(userID)) else { throw AppError.notAuthorized }
        return userID
    }

    func reply(_ text: String, chatID: String) async throws {
        let userID = try member(of: chatID)
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ChatLimits.maxTextLength))
        guard !trimmed.isEmpty else { return }
        let message = ChatMessageDTO(id: makeID(), senderID: userID, type: .text, text: trimmed, createdAt: clock())
        try await sync.sendMessage(message, chatID: chatID)
        // Yanıtlanan mesajlar da okunmuş sayılır.
        try? await markRead(chatID: chatID)
        try? await notifier?.notify(chatID: chatID, messageID: message.id)
    }

    /// Karşı tarafın okunmamış son mesajları okundu olur. Döndürülen: işaretlenen mesaj sayısı.
    @discardableResult
    func markRead(chatID: String) async throws -> Int {
        let userID = try member(of: chatID)
        let recent = try await sync.fetchMessages(chatID: chatID, before: clock().addingTimeInterval(60), limit: ChatLimits.pageSize)
        let unread = recent.filter { $0.senderID != userID && $0.readAt == nil && !$0.deleted }.map(\.id)
        guard !unread.isEmpty else { return 0 }
        try await sync.markRead(messageIDs: unread, chatID: chatID, at: clock())
        return unread.count
    }
}
