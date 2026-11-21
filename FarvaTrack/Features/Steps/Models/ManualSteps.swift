import Foundation
import SwiftData

/// Elle girilen günlük adım. Apple Sağlık izni yoksa ya da yanlış sayıyorsa kullanılır; o günün Sağlık verisinin yerine geçer.
@Model
final class ManualStepEntry {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    /// Günün başlangıcı
    var day: Date
    var steps: Int
    var needsSync: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), ownerID: String, day: Date, steps: Int) {
        self.id = id
        self.ownerID = ownerID
        self.day = day
        self.steps = steps
        self.needsSync = true
        self.createdAt = .now
        self.updatedAt = .now
    }

    static func make(from dto: ManualStepDTO, ownerID: String) -> ManualStepEntry {
        let entry = ManualStepEntry(id: UUID(uuidString: dto.id) ?? UUID(), ownerID: ownerID, day: dto.day, steps: dto.steps)
        entry.createdAt = dto.createdAt
        entry.updatedAt = dto.updatedAt
        entry.needsSync = false
        return entry
    }

    func apply(_ dto: ManualStepDTO) {
        day = dto.day
        steps = dto.steps
        updatedAt = dto.updatedAt
        needsSync = false
    }

    var dto: ManualStepDTO {
        ManualStepDTO(id: id.uuidString, day: day, steps: steps, createdAt: createdAt, updatedAt: updatedAt)
    }
}

struct ManualStepDTO: Codable, Equatable {
    var id: String
    var day: Date
    var steps: Int
    var createdAt: Date
    var updatedAt: Date
}

enum StepMerger {
    static let maxDailySteps = 150_000

    /// Sağlık verisiyle elle girilenleri birleştirir: elle girilen gün Sağlık'taki değerin yerine geçer.
    /// Mesafe boydan tahmin edilir, aktif enerji 0 bırakılır (kalori adımdan tahmin edilir).
    static func merge(
        health: [DailyActivity],
        manual: [Date: Int],
        heightCm: Double?,
        calendar: Calendar = .current
    ) -> [DailyActivity] {
        var byDay = Dictionary(health.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { first, _ in first })
        for (rawDay, steps) in manual {
            let day = calendar.startOfDay(for: rawDay)
            let distance = heightCm.map { CalorieCalculator.estimatedDistanceKm(steps: steps, heightCm: $0) } ?? 0
            byDay[day] = DailyActivity(date: day, steps: steps, distanceKm: distance, activeEnergyKcal: 0)
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// Kayıtlardan gün → adım sözlüğü (aynı güne iki kayıt varsa en son güncellenen).
    static func manualMap(_ entries: [ManualStepEntry], calendar: Calendar = .current) -> [Date: Int] {
        var latest: [Date: ManualStepEntry] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.day)
            if let existing = latest[day], existing.updatedAt >= entry.updatedAt { continue }
            latest[day] = entry
        }
        return latest.mapValues(\.steps)
    }

    @MainActor
    static func manualMap(context: ModelContext, ownerID: String, since: Date) -> [Date: Int] {
        let entries = (try? context.fetch(FetchDescriptor<ManualStepEntry>(
            predicate: #Predicate { $0.ownerID == ownerID && $0.day >= since }
        ))) ?? []
        return manualMap(entries)
    }
}

protocol ManualStepSyncing {
    func upload(_ entry: ManualStepDTO, userID: String) async throws
    func delete(id: String, userID: String) async throws
    func fetch(userID: String, since: Date) async throws -> [ManualStepDTO]
}

final class FirestoreManualStepSyncService: ManualStepSyncing {
    private let client = FirestoreCollectionClient(collectionName: Constants.Collection.manualSteps)

    func upload(_ entry: ManualStepDTO, userID: String) async throws {
        try await client.upload(entry, id: entry.id, userID: userID)
    }

    func delete(id: String, userID: String) async throws {
        try await client.delete(id: id, userID: userID)
    }

    func fetch(userID: String, since: Date) async throws -> [ManualStepDTO] {
        try await client.fetch(ManualStepDTO.self, userID: userID, since: since, dateField: "updatedAt")
    }
}
