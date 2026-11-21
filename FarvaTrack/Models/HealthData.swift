import Foundation

/// Grafiklerde kullanılan günlük tek değer (adım, su, kalori vb.).
struct DailyValue: Identifiable, Equatable, Hashable {
    let date: Date
    let value: Double

    var id: Date { date }
}

/// Bir güne ait HealthKit özeti.
struct DailyActivity: Identifiable, Equatable {
    let date: Date                 // günün başlangıcı
    var steps: Int
    var distanceKm: Double
    var activeEnergyKcal: Double

    var id: Date { date }

    static func empty(on date: Date) -> DailyActivity {
        DailyActivity(date: date, steps: 0, distanceKm: 0, activeEnergyKcal: 0)
    }
}

enum HealthAccessStatus: Equatable {
    case unavailable      // cihaz desteklemiyor
    case notDetermined    // izin penceresi henüz gösterilmedi
    case requested        // izin istendi (okuma izninin verilip verilmediği uygulamaya bildirilmez)
}
