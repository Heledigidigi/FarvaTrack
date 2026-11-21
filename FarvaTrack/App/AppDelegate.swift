import UIKit

/// Firebase, `FarvaTrackApp.init` içinde başlatılır (en erken nokta).
/// Bildirim ve HealthKit arka plan işleri sonraki aşamalarda buraya eklenecek.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }
}
