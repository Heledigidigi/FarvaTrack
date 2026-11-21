import Foundation
import SwiftData

/// Tek bir sayaç dokunuşu. Saat bilgisi yalnızca kullanıcının kendisinde ve kendi Firestore alanında tutulur.
@Model
final class WasteEntry {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var date: Date
    var needsSync: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), ownerID: String, date: Date = .now) {
        self.id = id
        self.ownerID = ownerID
        self.date = date
        self.needsSync = true
        self.createdAt = .now
        self.updatedAt = .now
    }

    static func make(from dto: WasteDTO, ownerID: String) -> WasteEntry {
        let entry = WasteEntry(id: UUID(uuidString: dto.id) ?? UUID(), ownerID: ownerID, date: dto.date)
        entry.createdAt = dto.createdAt
        entry.updatedAt = dto.updatedAt
        entry.needsSync = false
        return entry
    }
}

/// `users/{uid}/waste/{id}`: yalnızca sahibi okuyabilir.
struct WasteDTO: Codable, Equatable {
    var id: String
    var date: Date
    var createdAt: Date
    var updatedAt: Date
}

extension WasteEntry {
    var dto: WasteDTO {
        WasteDTO(id: id.uuidString, date: date, createdAt: createdAt, updatedAt: updatedAt)
    }
}

/// `users/{uid}/wasteDaily/{yyyy-MM-dd}`: yalnızca günlük toplam; sahibi ve yönetici okuyabilir.
struct WasteDailyDTO: Codable, Equatable, Identifiable {
    var id: String
    var day: Date
    var count: Int
    var updatedAt: Date
}

/// Yönetici ekranındaki kullanıcı satırı.
struct WasteUserSummary: Identifiable, Equatable {
    let id: String
    let displayName: String
    let email: String
    var days: [WasteDailyDTO]
}

// MARK: - Hesaplamalar
struct WasteStats: Equatable {
    var today: Int
    var average: Double
    var maximum: Int
    var activeDays: Int
}

enum WasteAnalyzer {
    /// Gün anahtarı (`yyyy-MM-dd`), belge kimliği olarak kullanılır.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func day(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Kayıt tarihlerinden son `days` günün (bugün dahil) günlük sayıları, eskiden yeniye.
    static func dailyCounts(dates: [Date], endingOn end: Date = .now, days: Int, calendar: Calendar = .current) -> [DailyValue] {
        var counts: [Date: Int] = [:]
        for date in dates { counts[calendar.startOfDay(for: date), default: 0] += 1 }
        return series(counts: counts, endingOn: end, days: days, calendar: calendar)
    }

    /// Günlük toplam belgelerinden (yönetici görünümü) aynı biçimde seri.
    static func dailyCounts(daily: [WasteDailyDTO], endingOn end: Date = .now, days: Int, calendar: Calendar = .current) -> [DailyValue] {
        var counts: [Date: Int] = [:]
        for item in daily {
            let day = Self.day(fromKey: item.id, calendar: calendar) ?? calendar.startOfDay(for: item.day)
            counts[day] = item.count
        }
        return series(counts: counts, endingOn: end, days: days, calendar: calendar)
    }

    private static func series(counts: [Date: Int], endingOn end: Date, days: Int, calendar: Calendar) -> [DailyValue] {
        let today = calendar.startOfDay(for: end)
        return (0..<max(days, 1)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyValue(date: day, value: Double(counts[day] ?? 0))
        }
    }

    /// Seri üzerinden özet. Ortalama, kayıt olan ilk günden itibaren hesaplanır (henüz kullanmadığı günler sayılmaz).
    static func stats(_ series: [DailyValue]) -> WasteStats {
        let today = Int(series.last?.value ?? 0)
        guard let firstIndex = series.firstIndex(where: { $0.value > 0 }) else {
            return WasteStats(today: today, average: 0, maximum: 0, activeDays: 0)
        }
        let window = series[firstIndex...]
        let total = window.reduce(0) { $0 + $1.value }
        return WasteStats(
            today: today,
            average: total / Double(window.count),
            maximum: Int(window.map(\.value).max() ?? 0),
            activeDays: window.filter { $0.value > 0 }.count
        )
    }
}
