import UIKit

/// Firebase, `FarvaTrackApp.init` içinde başlatılır (en erken nokta).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
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
}
