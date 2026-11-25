import Foundation

// MARK: - Öğün kaydı

enum DietMealStatus: String, Codable, CaseIterable, Hashable {
    /// Programdaki gibi yedi.
    case eaten
    /// Bazı yiyecekleri değiştirerek yedi.
    case changed
    case skipped
    /// Henüz işaretlenmedi ama fotoğrafı ya da notu var (yemekten önce çekilen fotoğraf).
    case pending

    var title: String {
        switch self {
        case .eaten: return "Yedim"
        case .changed: return "Değiştirdim"
        case .skipped: return "Atladım"
        case .pending: return "Bekliyor"
        }
    }

    /// İnceleyen kişinin gözünden (üçüncü tekil).
    var thirdPersonTitle: String {
        switch self {
        case .eaten: return "Yedi"
        case .changed: return "Değiştirdi"
        case .skipped: return "Atladı"
        case .pending: return "Bekliyor"
        }
    }

    var isMarked: Bool { self != .pending }
}

/// `dietPrograms/{programID}/logs/{id}`: o günün o öğünü. Kimlik `<gün>_<öğün>`.
struct DietMealLog: Codable, Hashable, Identifiable {
    var id: String
    var programID: String
    var dayKey: String
    var programDay: Int
    var mealID: String
    var mealName: String
    var mealMinutes: Int
    var status: DietMealStatus
    /// İşaretlendiği andaki plan (program sonradan değişse de rapor doğru kalır).
    var planned: [DietPortion]
    /// Yenenler. "Yedim"de plan, "Değiştirdim"de gerçekte yenenler, "Atladım"da boş.
    var eaten: [DietPortion]
    /// "Elma → Armut 1 orta"
    var swaps: [String]
    var note: String
    /// Medya sunucusundaki fotoğraf: `diet/{programID}/{ad}.jpg`.
    var photoPath: String?
    var photoTakenAt: Date?
    var loggedAt: Date
    var updatedAt: Date

    static func makeID(dayKey: String, mealID: String) -> String { "\(dayKey)_\(mealID)" }

    init(programID: String, dayKey: String, programDay: Int, meal: DietMeal, status: DietMealStatus,
         eaten: [DietPortion], swaps: [String] = [], note: String = "", now: Date = .now) {
        self.id = Self.makeID(dayKey: dayKey, mealID: meal.id)
        self.programID = programID
        self.dayKey = dayKey
        self.programDay = programDay
        self.mealID = meal.id
        self.mealName = meal.name
        self.mealMinutes = meal.minutes
        self.status = status
        self.planned = meal.portions
        self.eaten = eaten
        self.swaps = swaps
        self.note = note
        self.photoPath = nil
        self.photoTakenAt = nil
        self.loggedAt = now
        self.updatedAt = now
    }

    private enum CodingKeys: String, CodingKey {
        case id, programID, dayKey, programDay, mealID, mealName, mealMinutes, status, planned, eaten, swaps, note
        case photoPath, photoTakenAt, loggedAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        programID = try c.decode(String.self, forKey: .programID)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        programDay = try c.decodeIfPresent(Int.self, forKey: .programDay) ?? 0
        mealID = try c.decode(String.self, forKey: .mealID)
        mealName = try c.decodeIfPresent(String.self, forKey: .mealName) ?? "Öğün"
        mealMinutes = try c.decodeIfPresent(Int.self, forKey: .mealMinutes) ?? 0
        status = (try? c.decode(DietMealStatus.self, forKey: .status)) ?? .pending
        planned = try c.decodeIfPresent([DietPortion].self, forKey: .planned) ?? []
        eaten = try c.decodeIfPresent([DietPortion].self, forKey: .eaten) ?? []
        swaps = try c.decodeIfPresent([String].self, forKey: .swaps) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        photoPath = try c.decodeIfPresent(String.self, forKey: .photoPath)
        photoTakenAt = try c.decodeIfPresent(Date.self, forKey: .photoTakenAt)
        loggedAt = try c.decodeIfPresent(Date.self, forKey: .loggedAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? loggedAt
    }

    var plannedNutrition: DietNutrition { DietNutrition.sum(planned.map(\.nutrition)) }
    var eatenNutrition: DietNutrition { DietNutrition.sum(eaten.map(\.nutrition)) }
    var timeText: String { DietFormat.time(minutes: mealMinutes) }
    var hasPhoto: Bool { photoPath != nil }

    /// Yenenlerin kısa listesi.
    var eatenSummary: String { eaten.map(\.label).joined(separator: " · ") }
}

// MARK: - Günün notu

/// `dietPrograms/{programID}/notes/{gün}`
struct DietDayNote: Codable, Hashable, Identifiable {
    var dayKey: String
    var programID: String
    var text: String
    var tags: [String]
    var updatedAt: Date

    var id: String { dayKey }
    var isEmpty: Bool { text.trimmed.isEmpty && tags.isEmpty }

    static let suggestedTags = ["Enerjik", "Acıktım", "Şişkinlik", "Antrenman", "Yorgun", "Dışarıda yedim", "İyi uyudum"]
}

// MARK: - Yorum

/// `dietPrograms/{programID}/comments/{id}`: inceleyen ya da sahibi bir öğüne (ya da güne) yorum bırakır.
struct DietComment: Codable, Hashable, Identifiable {
    var id: String
    var programID: String
    /// Öğün kaydı kimliği (`<gün>_<öğün>`) ya da gün yorumunda gün anahtarı.
    var targetID: String
    var authorID: String
    var authorName: String
    var text: String
    /// "👍", "❤️" gibi tek emoji (isteğe bağlı).
    var reaction: String?
    var createdAt: Date

    static let reactions = ["👍", "❤️", "👏", "🤔"]
}

// MARK: - Değişiklik önerisi

enum DietSuggestionStatus: String, Codable, Hashable {
    case pending, accepted, rejected
}

/// `dietPrograms/{programID}/suggestions/{id}`: programı inceleyen kişinin önerdiği yeni plan.
struct DietSuggestion: Codable, Hashable, Identifiable {
    var id: String
    var programID: String
    var authorID: String
    var authorName: String
    var note: String
    var basedOnVersion: Int
    var plan: DietPlan
    var status: DietSuggestionStatus
    var createdAt: Date
    var decidedAt: Date?
}

// MARK: - Sohbetten gönderilen program teklifi

enum DietOfferStatus: String, Codable, Hashable {
    case pending, accepted, declined
}

/// `dietOffers/{id}`: sohbette gönderilen programın kopyası. Alıcı kabul edince kendi programı olur.
struct DietOffer: Codable, Hashable, Identifiable {
    var id: String
    var fromID: String
    var fromName: String
    var toID: String
    var name: String
    var plan: DietPlan
    var status: DietOfferStatus
    var acceptedProgramID: String?
    var createdAt: Date
    var decidedAt: Date?
}

/// Sohbet mesajındaki program kartı (mesajın `diet` alanı).
struct ChatDietInfo: Codable, Equatable, Hashable {
    var offerID: String
    var name: String
    var days: Int
    var mealsPerDay: Int
    var calories: Int
    var proteinShare: Int
    var carbsShare: Int
    var fatShare: Int
    var alternatives: Int

    init(offer: DietOffer) {
        let average = offer.plan.averageNutrition
        offerID = offer.id
        name = offer.name
        days = offer.plan.dayCount
        mealsPerDay = Int(offer.plan.averageMealsPerDay.rounded())
        calories = average.kcal
        proteinShare = Int((average.energyShare(of: .protein) * 100).rounded())
        carbsShare = Int((average.energyShare(of: .carbs) * 100).rounded())
        fatShare = Int((average.energyShare(of: .fat) * 100).rounded())
        alternatives = offer.plan.alternativeCount
    }

    init(offerID: String, name: String, days: Int, mealsPerDay: Int, calories: Int,
         proteinShare: Int, carbsShare: Int, fatShare: Int, alternatives: Int) {
        self.offerID = offerID
        self.name = name
        self.days = days
        self.mealsPerDay = mealsPerDay
        self.calories = calories
        self.proteinShare = proteinShare
        self.carbsShare = carbsShare
        self.fatShare = fatShare
        self.alternatives = alternatives
    }

    var summary: String { "\(days) gün · günde \(mealsPerDay) öğün · ort. \(DietFormat.kcal(Double(calories))) kcal" }
}

// MARK: - Gün anahtarı

enum DietDayKey {
    static func make(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// Sohbet mesajındaki `diet` alanının Firestore karşılığı.
enum ChatDietFields {
    static func encode(_ info: ChatDietInfo) -> [String: Any] {
        ["offerId": info.offerID, "name": info.name, "days": info.days, "mealsPerDay": info.mealsPerDay,
         "calories": info.calories, "protein": info.proteinShare, "carbs": info.carbsShare, "fat": info.fatShare,
         "alternatives": info.alternatives]
    }

    static func decode(_ value: Any?) -> ChatDietInfo? {
        guard let map = value as? [String: Any], let id = map["offerId"] as? String, !id.isEmpty else { return nil }
        func int(_ key: String) -> Int { (map[key] as? NSNumber)?.intValue ?? 0 }
        return ChatDietInfo(offerID: id, name: map["name"] as? String ?? "Diyet programı", days: int("days"),
                            mealsPerDay: int("mealsPerDay"), calories: int("calories"), proteinShare: int("protein"),
                            carbsShare: int("carbs"), fatShare: int("fat"), alternatives: int("alternatives"))
    }
}
