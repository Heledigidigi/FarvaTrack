import UIKit
import UserNotifications

/// Firebase, `FarvaTrackApp.init` içinde başlatılır (en erken nokta).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Birim testleri uygulamayı barındırıcı olarak açar; orada HealthKit gözlemcisi gereksiz.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !isRunningTests {
            // Yeni adım verisi geldiğinde (uygulama kapalıyken bile) widget'ı güncelle.
            HealthKitManager.shared.startBackgroundDelivery {
                await StepsWidgetRefresher.refresh()
            }
        }
        return true
    }

    // MARK: - Bildirimler
    /// Uygulama açıkken de hatırlatıcılar banner olarak görünsün.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Bildirime dokunulunca ilgili ekranı aç (ör. farvatrack://water).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string) else { return }
        await MainActor.run { DeepLinkCenter.open(url) }
    }
}
