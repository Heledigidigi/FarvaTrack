import Foundation
import SwiftData

@Model
final class WaterEntry {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var date: Date
    var amountMl: Int
    var needsSync: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), ownerID: String, date: Date = .now, amountMl: Int) {
        self.id = id
        self.ownerID = ownerID
        self.date = date
        self.amountMl = amountMl
        self.needsSync = true
        self.createdAt = .now
        self.updatedAt = .now
    }

    static func make(from dto: WaterDTO, ownerID: String) -> WaterEntry {
        let entry = WaterEntry(id: UUID(uuidString: dto.id) ?? UUID(), ownerID: ownerID, date: dto.date, amountMl: dto.amountMl)
        entry.createdAt = dto.createdAt
        entry.updatedAt = dto.updatedAt
        entry.needsSync = false
        return entry
    }
}

struct WaterDTO: Codable, Equatable {
    var id: String
    var date: Date
    var amountMl: Int
    var createdAt: Date
    var updatedAt: Date
}

extension WaterEntry {
    var dto: WaterDTO {
        WaterDTO(id: id.uuidString, date: date, amountMl: amountMl, createdAt: createdAt, updatedAt: updatedAt)
    }
}
