import Foundation
import SwiftData

@Model
final class SleepEntry {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    /// Uyanış gününün başlangıcı (kayıt bu güne aittir).
    var day: Date
    var bedtime: Date
    var wakeTime: Date
    var quality: Int
    /// Gün içi ek uyku (şekerleme). Gece uykusu günde tektir; şekerlemeler ayrı kayıtlardır.
    var isNap: Bool = false
    var needsSync: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerID: String,
        bedtime: Date,
        wakeTime: Date,
        quality: Int,
        isNap: Bool = false,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.ownerID = ownerID
        self.day = calendar.startOfDay(for: wakeTime)
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.quality = quality
        self.isNap = isNap
        self.needsSync = true
        self.createdAt = .now
        self.updatedAt = .now
    }

    static func make(from dto: SleepDTO, ownerID: String) -> SleepEntry {
        let entry = SleepEntry(
            id: UUID(uuidString: dto.id) ?? UUID(), ownerID: ownerID,
            bedtime: dto.bedtime, wakeTime: dto.wakeTime, quality: dto.quality, isNap: dto.isNap ?? false
        )
        entry.day = dto.day
        entry.createdAt = dto.createdAt
        entry.updatedAt = dto.updatedAt
        entry.needsSync = false
        return entry
    }

    var durationHours: Double {
        wakeTime.timeIntervalSince(bedtime) / 3600
    }

    var record: SleepRecord {
        SleepRecord(day: day, bedtime: bedtime, wakeTime: wakeTime, quality: quality)
    }
}

struct SleepDTO: Codable, Equatable {
    var id: String
    var day: Date
    var bedtime: Date
    var wakeTime: Date
    var quality: Int
    var createdAt: Date
    var updatedAt: Date
    /// Şekerleme kaydı (eski kayıtlarda yok → gece uykusu).
    var isNap: Bool? = nil
}

extension SleepEntry {
    var dto: SleepDTO {
        SleepDTO(id: id.uuidString, day: day, bedtime: bedtime, wakeTime: wakeTime,
                 quality: quality, createdAt: createdAt, updatedAt: updatedAt, isNap: isNap ? true : nil)
    }

    func apply(_ dto: SleepDTO) {
        day = dto.day
        bedtime = dto.bedtime
        wakeTime = dto.wakeTime
        quality = dto.quality
        isNap = dto.isNap ?? false
        updatedAt = dto.updatedAt
        needsSync = false
    }
}

/// Cihaza özel uyku ayarları (hedef uyanış saati ve hatırlatıcı).
struct SleepSettings: Codable, Equatable {
    /// Günün dakikası olarak hedef uyanış saati (varsayılan 07:00).
    var targetWakeMinutes = 7 * 60
    var reminderEnabled = false
    /// Önerilen yatış saatinden kaç dakika önce hatırlatılacağı.
    var reminderLeadMinutes = 30

    private static let key = "sleepSettings"

    static func load(defaults: UserDefaults = .standard) -> SleepSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(SleepSettings.self, from: data) else {
            return SleepSettings()
        }
        return settings
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}
