import Foundation

enum Gender: String, Codable, CaseIterable, Identifiable {
    case male = "male"
    case female = "female"
    case other = "other"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .male: return "Erkek"
        case .female: return "Kadın"
        case .other: return "Diğer"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary = "sedentary"
    case lightlyActive = "lightlyActive"
    case moderatelyActive = "moderatelyActive"
    case veryActive = "veryActive"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sedentary: return "Hareketsiz"
        case .lightlyActive: return "Hafif Hareketli"
        case .moderatelyActive: return "Orta Derece"
        case .veryActive: return "Çok Aktif"
        }
    }
}

enum FitnessGoal: String, Codable, CaseIterable, Identifiable {
    case loseWeight = "loseWeight"
    case maintain = "maintain"
    case buildMuscle = "buildMuscle"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .loseWeight: return "Kilo Vermek"
        case .maintain: return "Kiloyu Korumak"
        case .buildMuscle: return "Kas Yapmak"
        }
    }
}

struct AppUser: Identifiable, Codable, Equatable {
    var id: String { uid }
    let uid: String
    var email: String
    var displayName: String
    var photoURL: URL?
    var birthDate: Date?
    var heightCm: Double?
    var gender: Gender?
    var activityLevel: ActivityLevel
    var goal: FitnessGoal
    var createdAt: Date = .now

    init(
        uid: String,
        email: String,
        displayName: String,
        photoURL: URL? = nil,
        birthDate: Date? = nil,
        heightCm: Double? = 175,
        gender: Gender? = .male,
        activityLevel: ActivityLevel = .moderatelyActive,
        goal: FitnessGoal = .buildMuscle
    ) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.gender = gender
        self.activityLevel = activityLevel
        self.goal = goal
    }
}
