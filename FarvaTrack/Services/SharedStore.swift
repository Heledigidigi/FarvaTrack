import Foundation
import WidgetKit

// Bu dosya hem uygulama hem widget hedefinde derlenir (project.yml).
// Uygulamaya özel tiplere (Constants, AppError vb.) bağımlı olmamalı.

struct StepsSnapshot: Codable, Equatable {
    var steps: Int
    var goal: Int
    var distanceKm: Double
    var updatedAt: Date

    static let empty = StepsSnapshot(steps: 0, goal: 8_000, distanceKm: 0, updatedAt: .distantPast)
}

/// Uygulama ile widget arasındaki paylaşılan depo (App Group).
enum SharedStore {
    /// Config/*.entitlements içindeki App Group kimliğiyle aynı olmalı.
    static let appGroupID = "group.com.farvatrack.shared"
    static let stepsWidgetKind = "StepsWidget"

    private static let stepsKey = "stepsSnapshot"

    /// App Group yoksa (ör. imzasız test derlemesi) standart depoya düşer; uygulama çalışmaya devam eder.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // MARK: Adımlar
    static func save(_ snapshot: StepsSnapshot) {
        // Aynı değeri tekrar yazıp widget'ı gereksiz yenilemeyelim.
        if let old = loadSteps(),
           old.steps == snapshot.steps,
           old.goal == snapshot.goal,
           Calendar.current.isDateInToday(old.updatedAt) {
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: stepsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: stepsWidgetKind)
    }

    static func loadSteps() -> StepsSnapshot? {
        guard let data = defaults.data(forKey: stepsKey) else { return nil }
        return try? JSONDecoder().decode(StepsSnapshot.self, from: data)
    }

    static func clearSteps() {
        defaults.removeObject(forKey: stepsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: stepsWidgetKind)
    }

    /// Çıkışta veya hesap silmede tüm widget verilerini temizler.
    static func clearAll() {
        clearSteps()
    }
}
