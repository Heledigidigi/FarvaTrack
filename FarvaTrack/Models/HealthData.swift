import Foundation

/// Grafiklerde kullanılan günlük tek değer (adım, su, kalori vb.).
struct DailyValue: Identifiable, Equatable, Hashable {
    let date: Date
    let value: Double

    var id: Date { date }
}