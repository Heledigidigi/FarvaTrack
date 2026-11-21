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
    /// Bugünkü son kaydın saati (widget'ta "son 08:40" ve geri al süresi için).
    var lastAt: Date? = nil
    /// Widget'tan yapılan son dokunuşun kimliği (geri al bunu siler).
    var lastWidgetTapID: UUID? = nil

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
    private static let pendingWasteUndoKey = "pendingWasteUndos"
    private static let stepsMetricKey = "stepsWidgetMetric"

    /// Widget'ta "Geri al" düğmesinin görünür kaldığı süre.
    static let wasteUndoWindow: TimeInterval = 5 * 60

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

    /// Adım widget'ında dokununca değişen gösterim: 0 adım, 1 km, 2 kcal.
    static var stepsMetric: Int {
        get { defaults.integer(forKey: stepsMetricKey) % 3 }
        set { defaults.set(newValue % 3, forKey: stepsMetricKey) }
    }

    static func cycleStepsMetric() {
        stepsMetric = (stepsMetric + 1) % 3
        WidgetCenter.shared.reloadTimelines(ofKind: stepsWidgetKind)
    }

    static func clearSteps() {
        defaults.removeObject(forKey: stepsKey)
        defaults.removeObject(forKey: stepsMetricKey)
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

        let tap = PendingWasteTap(id: UUID(), date: now)
        var pending = pendingWasteTaps()
        pending.append(tap)
        defaults.set(try? JSONEncoder().encode(pending), forKey: pendingWasteKey)

        snapshot.count += 1
        snapshot.updatedAt = now
        snapshot.lastAt = now
        snapshot.lastWidgetTapID = tap.id
        saveWaste(snapshot)
    }

    /// Widget'taki "Geri al": son widget dokunuşunu kuyruktan siler; uygulama onu çoktan
    /// aktardıysa silinmek üzere ayrı bir kuyruğa yazar.
    static func undoLastWasteFromWidget(now: Date = .now) {
        guard var snapshot = loadWaste(),
              let id = snapshot.lastWidgetTapID,
              let lastAt = snapshot.lastAt,
              now.timeIntervalSince(lastAt) <= wasteUndoWindow + 60 else { return }

        var pending = pendingWasteTaps()
        if pending.contains(where: { $0.id == id }) {
            pending.removeAll { $0.id == id }
            defaults.set(try? JSONEncoder().encode(pending), forKey: pendingWasteKey)
        } else {
            var undos = pendingWasteUndos()
            undos.append(id)
            defaults.set(try? JSONEncoder().encode(undos), forKey: pendingWasteUndoKey)
        }

        snapshot.count = max(0, snapshot.count - 1)
        snapshot.lastWidgetTapID = nil
        snapshot.lastAt = pending.filter { Calendar.current.isDate($0.date, inSameDayAs: now) }.map(\.date).max()
        snapshot.updatedAt = now
        saveWaste(snapshot)
    }

    static func pendingWasteUndos() -> [UUID] {
        guard let data = defaults.data(forKey: pendingWasteUndoKey) else { return [] }
        return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
    }

    static func removePendingWasteUndos(ids: [UUID]) {
        let remaining = pendingWasteUndos().filter { !ids.contains($0) }
        defaults.set(try? JSONEncoder().encode(remaining), forKey: pendingWasteUndoKey)
    }

    static func clearWaste() {
        defaults.removeObject(forKey: wasteKey)
        defaults.removeObject(forKey: pendingWasteKey)
        defaults.removeObject(forKey: pendingWasteUndoKey)
        WidgetCenter.shared.reloadTimelines(ofKind: wasteWidgetKind)
    }

    /// Çıkışta veya hesap silmede tüm widget verilerini temizler.
    static func clearAll() {
        clearSteps()
        clearWater()
        clearWaste()
    }
}
