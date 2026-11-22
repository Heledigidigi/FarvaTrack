import UIKit
import UserNotifications
import FirebaseMessaging

/// Firebase, `FarvaTrackApp.init` içinde başlatılır (en erken nokta; bu temsilciden önce çalışır).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        ChatNotificationAction.register()
        if FirebaseBootstrap.isConfigured {
            Messaging.messaging().delegate = self
        }

        // Birim testleri uygulamayı barındırıcı olarak açar; orada HealthKit gözlemcisi gereksiz.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !isRunningTests {
            // Kilit ekranında arama (8H): yalnızca VOIP_PUSH build ayarı açıksa kaydolunur.
            VoIPPushRegistrar.shared.start()
            // Yeni adım verisi geldiğinde (uygulama kapalıyken bile) widget'ı güncelle.
            HealthKitManager.shared.startBackgroundDelivery {
                await StepsWidgetRefresher.refresh()
            }
        }
        return true
    }

    // MARK: - Push (8G)

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseBootstrap.isConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
        Task { await PushManager.shared.apnsRegistered() }
    }

    /// Ücretsiz imzada (push yetkisi yok) buraya düşer: uygulama açıkken anlık dinleyiciyle çalışmaya devam eder.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushManager.shared.apnsFailed() }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { await PushManager.shared.tokenReceived(fcmToken) }
    }

    // MARK: - Bildirimler

    /// Sohbet mesajı ya da (VoIP push yokken) gelen arama bildirimi.
    private static func isChat(_ userInfo: [AnyHashable: Any]) -> Bool {
        ["chat", "call"].contains(userInfo["kind"] as? String ?? "")
    }

    /// Uygulama açıkken: hatırlatıcılar banner olarak görünür; sohbet bildirimleri yerine
    /// anlık dinleyicinin uygulama içi şeridi gösterilir (çift bildirim olmasın).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.isChat(notification.request.content.userInfo) ? [] : [.banner, .sound]
    }

    /// Bildirime dokunma ya da bildirim eylemi.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if Self.isChat(userInfo), let chatID = userInfo["chatId"] as? String {
            await handleChat(response: response, chatID: chatID)
            return
        }
        guard let string = userInfo["url"] as? String, let url = URL(string: string) else { return }
        await MainActor.run { DeepLinkCenter.open(url) }
    }

    @MainActor
    private func handleChat(response: UNNotificationResponse, chatID: String) async {
        let actions = ChatQuickActions()
        switch response.actionIdentifier {
        case ChatNotificationAction.reply:
            guard let text = (response as? UNTextInputNotificationResponse)?.userText else { return }
            try? await actions.reply(text, chatID: chatID)
            PushManager.shared.setBadge(0)
        case ChatNotificationAction.markRead:
            _ = try? await actions.markRead(chatID: chatID)
            PushManager.shared.setBadge(0)
        case UNNotificationDismissActionIdentifier:
            break
        default:
            PushManager.shared.pendingChatID = chatID
        }
    }
}
