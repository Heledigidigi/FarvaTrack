import Foundation
import SwiftData

// MARK: - Kilo
@Model
final class WeightEntry {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var date: Date
    var weightKg: Double
    var note: String?
    var needsSync: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), ownerID: String, date: Date, weightKg: Double, note: String? = nil) {
        self.id = id
        self.ownerID = ownerID
        self.date = date
        self.weightKg = weightKg
        self.note = note
        self.needsSync = true
        self.createdAt = .now
        self.updatedAt = .now
    }

    static func make(from dto: WeightDTO, ownerID: String) -> WeightEntry {
        let entry = WeightEntry(
            id: UUID(uuidString: dto.id) ?? UUID(), ownerID: ownerID,
            date: dto.date, weightKg: dto.weightKg, note: dto.note
        )
        entry.createdAt = dto.createdAt
        entry.updatedAt = dto.updatedAt
        entry.needsSync = false
        return entry
    }

    func apply(_ dto: WeightDTO) {
        date = dto.date
        weightKg = dto.weightKg
        note = dto.note
        updatedAt = dto.updatedAt
        needsSync = false
    }

    var point: WeightPoint { WeightPoint(date: date, weightKg: weightKg) }
}

struct WeightDTO: Codable, Equatable {
    var id: String
    var date: Date
    var weightKg: Double
    var note: String?
    var createdAt: Date
    var updatedAt: Date
}

extension WeightEntry {
    var dto: WeightDTO {
        WeightDTO(id: id.uuidString, date: date, weightKg: weightKg, note: note, createdAt: createdAt, updatedAt: updatedAt)
    }
}

// MARK: - Vücut ölçüleri
/// Takip edilen ölçüler. Kalça ölçüsü listeden çıkarıldı; eski kayıtlardaki değer silinmez, yalnızca gösterilmez.
enum BodyMeasure: String, CaseIterable, Identifiable, Codable {
    case neck, chest, arm, forearm, wrist, waist, thigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neck: return "Boyun"
        case .chest: return "Göğüs"
        case .arm: return "Kol"
        case .forearm: return "Ön Kol"
        case .wrist: return "Bilek"
        case .waist: return "Bel"
        case .thigh: return "Bacak"
        }
    }

    var systemImage: String {
        switch self {
        case .neck: return "person.crop.circle"
        case .chest: return "heart.circle"
        case .arm: return "figure.strengthtraining.traditional"
        case .forearm: return "hand.raised.fill"
        case .wrist: return "applewatch"
        case .waist: return "circle.dashed"
        case .thigh: return "figure.walk"
        }
    }

    /// Makul giriş aralığı (cm).
    var validRange: ClosedRange<Double> {
        switch self {
        case .waist, .chest: return 40...250
        case .arm: return 10...80
        case .forearm: return 10...60
        case .wrist: return 8...30
        case .thigh: return 20...120
        case .neck: return 20...70
        }
    }
}

@Model
final class MeasurementEntry {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var date: Date
    var waistCm: Double?
    var chestCm: Double?
    /// Eski sürümlerden kalan kalça ölçüsü (artık gösterilmez, veri korunur).
    var hipCm: Double?
    var armCm: Double?
    var forearmCm: Double?
    var wristCm: Double?
    var thighCm: Double?
    var neckCm: Double?
    var needsSync: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), ownerID: String, date: Date, values: [BodyMeasure: Double] = [:]) {
        self.id = id
        self.ownerID = ownerID
        self.date = date
        self.needsSync = true
        self.createdAt = .now
        self.updatedAt = .now
        for (measure, value) in values { setValue(value, for: measure) }
    }

    static func make(from dto: MeasurementDTO, ownerID: String) -> MeasurementEntry {
        let entry = MeasurementEntry(id: UUID(uuidString: dto.id) ?? UUID(), ownerID: ownerID, date: dto.date)
        entry.apply(dto)
        entry.createdAt = dto.createdAt
        return entry
    }

    func value(for measure: BodyMeasure) -> Double? {
        switch measure {
        case .waist: return waistCm
        case .chest: return chestCm
        case .arm: return armCm
        case .forearm: return forearmCm
        case .wrist: return wristCm
        case .thigh: return thighCm
        case .neck: return neckCm
        }
    }

    func setValue(_ value: Double?, for measure: BodyMeasure) {
        switch measure {
        case .waist: waistCm = value
        case .chest: chestCm = value
        case .arm: armCm = value
        case .forearm: forearmCm = value
        case .wrist: wristCm = value
        case .thigh: thighCm = value
        case .neck: neckCm = value
        }
    }

    var values: [BodyMeasure: Double] {
        var result: [BodyMeasure: Double] = [:]
        for measure in BodyMeasure.allCases {
            if let value = value(for: measure) { result[measure] = value }
        }
        return result
    }

    func apply(_ dto: MeasurementDTO) {
        date = dto.date
        waistCm = dto.waistCm
        chestCm = dto.chestCm
        hipCm = dto.hipCm
        armCm = dto.armCm
        forearmCm = dto.forearmCm
        wristCm = dto.wristCm
        thighCm = dto.thighCm
        neckCm = dto.neckCm
        updatedAt = dto.updatedAt
        needsSync = false
    }
}

struct MeasurementDTO: Codable, Equatable {
    var id: String
    var date: Date
    var waistCm: Double?
    var chestCm: Double?
    var hipCm: Double?
    var armCm: Double?
    var thighCm: Double?
    var neckCm: Double?
    var createdAt: Date
    var updatedAt: Date
    var forearmCm: Double?
    var wristCm: Double?
}

extension MeasurementEntry {
    var dto: MeasurementDTO {
        MeasurementDTO(
            id: id.uuidString, date: date,
            waistCm: waistCm, chestCm: chestCm, hipCm: hipCm,
            armCm: armCm, thighCm: thighCm, neckCm: neckCm,
            createdAt: createdAt, updatedAt: updatedAt,
            forearmCm: forearmCm, wristCm: wristCm
        )
    }
}
