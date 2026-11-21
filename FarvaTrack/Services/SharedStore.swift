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

struct WaterSnapshot: Codable, Equatable {
    var totalMl: Int
    var goalMl: Int
    var updatedAt: Date

    static let empty = WaterSnapshot(totalMl: 0, goalMl: 2_500, updatedAt: .distantPast)
}

/// Widget'tan eklenmiş ama henüz uygulamaya aktarılmamış su kaydı.
struct PendingWaterAdd: Codable, Equatable, Identifiable {
    let id: UUID
    let amountMl: Int
    let date: Date
}

struct WasteSnapshot: Codable, Equatable {
    var count: Int
    var updatedAt: Date

    static let empty = WasteSnapshot(count: 0, updatedAt: .distantPast)
}

/// Widget'tan yapılmış ama henüz uygulamaya aktarılmamış sayaç dokunuşu.
struct PendingWasteTap: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
}

/// Uygulama ile widget arasındaki paylaşılan depo (App Group).
enum SharedStore {
    /// Config/*.entitlements içindeki App Group kimliğiyle aynı olmalı.
    static let appGroupID = "group.com.farvatrack.shared"
    static let stepsWidgetKind = "StepsWidget"
    static let waterWidgetKind = "WaterWidget"
    static let wasteWidgetKind = "WasteWidget"

    /// Yanlış dokunmalara karşı su sınırları (uygulama ve widget aynı değerleri kullanır).
    static let maxSingleWaterMl = 2_000
    static let maxDailyWaterMl = 6_000
    /// Yanlış dokunmalara karşı günlük sayaç sınırı.
    static let maxDailyWasteCount = 40

    private static let stepsKey = "stepsSnapshot"
    private static let waterKey = "waterSnapshot"
    private static let pendingWaterKey = "pendingWaterAdds"
    private static let wasteKey = "wasteSnapshot"
    private static let pendingWasteKey = "pendingWasteTaps"

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

    // MARK: Su
    static func loadWater() -> WaterSnapshot? {
        guard let data = defaults.data(forKey: waterKey) else { return nil }
        return try? JSONDecoder().decode(WaterSnapshot.self, from: data)
    }

    static func saveWater(_ snapshot: WaterSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: waterKey)
        WidgetCenter.shared.reloadTimelines(ofKind: waterWidgetKind)
    }

    static func pendingWaterAdds() -> [PendingWaterAdd] {
        guard let data = defaults.data(forKey: pendingWaterKey) else { return [] }
        return (try? JSONDecoder().decode([PendingWaterAdd].self, from: data)) ?? []
    }

    /// Yalnızca verilen kayıtları kuyruktan siler (aradan widget yeni kayıt eklemiş olabilir).
    static func removePendingWater(ids: [UUID]) {
        let remaining = pendingWaterAdds().filter { !ids.contains($0.id) }
        defaults.set(try? JSONEncoder().encode(remaining), forKey: pendingWaterKey)
    }

    /// Widget butonu çağırır: kuyruğa ekler ve widget'ın gösterdiği toplamı hemen günceller.
    static func addWaterFromWidget(amountMl: Int, now: Date = .now) {
        guard (1...maxSingleWaterMl).contains(amountMl) else { return }

        var snapshot = loadWater() ?? .empty
        if !Calendar.current.isDate(snapshot.updatedAt, inSameDayAs: now) {
            snapshot.totalMl = 0
        }
        guard snapshot.totalMl + amountMl <= maxDailyWaterMl else { return }

        var pending = pendingWaterAdds()
        pending.append(PendingWaterAdd(id: UUID(), amountMl: amountMl, date: now))
        defaults.set(try? JSONEncoder().encode(pending), forKey: pendingWaterKey)

        snapshot.totalMl += amountMl
        snapshot.updatedAt = now
        saveWater(snapshot)
    }

    /// Çıkışta: bekleyen su kuyruğu başka bir hesaba aktarılmasın.
    static func clearWater() {
        defaults.removeObject(forKey: waterKey)
        defaults.removeObject(forKey: pendingWaterKey)
        WidgetCenter.shared.reloadTimelines(ofKind: waterWidgetKind)
    }

    // MARK: Biyolojik atık sayacı
    static func loadWaste() -> WasteSnapshot? {
        guard let data = defaults.data(forKey: wasteKey) else { return nil }
        return try? JSONDecoder().decode(WasteSnapshot.self, from: data)
    }

    static func saveWaste(_ snapshot: WasteSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: wasteKey)
        WidgetCenter.shared.reloadTimelines(ofKind: wasteWidgetKind)
    }

    static func pendingWasteTaps() -> [PendingWasteTap] {
        guard let data = defaults.data(forKey: pendingWasteKey) else { return [] }
        return (try? JSONDecoder().decode([PendingWasteTap].self, from: data)) ?? []
    }

    static func removePendingWaste(ids: [UUID]) {
        let remaining = pendingWasteTaps().filter { !ids.contains($0.id) }
        defaults.set(try? JSONEncoder().encode(remaining), forKey: pendingWasteKey)
    }

    /// Widget butonu çağırır: kuyruğa ekler ve widget'taki sayıyı hemen artırır.
    static func addWasteFromWidget(now: Date = .now) {
        var snapshot = loadWaste() ?? .empty
        if !Calendar.current.isDate(snapshot.updatedAt, inSameDayAs: now) {
            snapshot.count = 0
        }
        guard snapshot.count < maxDailyWasteCount else { return }

        var pending = pendingWasteTaps()
        pending.append(PendingWasteTap(id: UUID(), date: now))
        defaults.set(try? JSONEncoder().encode(pending), forKey: pendingWasteKey)

        snapshot.count += 1
        snapshot.updatedAt = now
        saveWaste(snapshot)
    }

    static func clearWaste() {
        defaults.removeObject(forKey: wasteKey)
        defaults.removeObject(forKey: pendingWasteKey)
        WidgetCenter.shared.reloadTimelines(ofKind: wasteWidgetKind)
    }

    /// Çıkışta veya hesap silmede tüm widget verilerini temizler.
    static func clearAll() {
        clearSteps()
        clearWater()
        clearWaste()
    }
}
