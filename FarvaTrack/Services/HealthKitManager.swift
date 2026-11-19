import Foundation

struct DailyActivity: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let steps: Int
    let activeEnergyBurned: Double
    let distanceMeters: Double
}

protocol HealthDataProviding {
    var isHealthDataAvailable: Bool { get }
    func activity(from start: Date, to end: Date) async throws -> [DailyActivity]
}

final class HealthKitManager: HealthDataProviding {
    static let shared = HealthKitManager()
    private init() {}

    var isHealthDataAvailable: Bool {
        true
    }

    func activity(from start: Date, to end: Date) async throws -> [DailyActivity] {
        var results: [DailyActivity] = []
        var current = start
        let calendar = Calendar.current
        while current <= end {
            results.append(DailyActivity(
                date: current,
                steps: 7500 + Int.random(in: 500...4500),
                activeEnergyBurned: 350 + Double.random(in: 50...250),
                distanceMeters: 5000 + Double.random(in: 500...3000)
            ))
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? end.addingTimeInterval(86400)
        }
        return results
    }
}
