import Foundation
import SwiftData

// MARK: - Enum'lar
enum Gender: String, Codable, CaseIterable, Identifiable {
    case male, female, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: return "Erkek"
        case .female: return "Kadın"
        case .other: return "Diğer"
        }
    }

    var systemImage: String {
        switch self {
        case .male: return "figure.stand"
        case .female: return "figure.stand.dress"
        case .other: return "person.fill"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: return "Hareketsiz"
        case .light: return "Hafif aktif"
        case .moderate: return "Orta aktif"
        case .active: return "Çok aktif"
        case .veryActive: return "Ekstra aktif"
        }
    }

    var subtitle: String {
        switch self {
        case .sedentary: return "Masa başı iş, az egzersiz"
        case .light: return "Haftada 1–3 gün egzersiz"
        case .moderate: return "Haftada 3–5 gün egzersiz"
        case .active: return "Haftada 6–7 gün egzersiz"
        case .veryActive: return "Günde birden fazla antrenman / fiziksel iş"
        }
    }

    var systemImage: String {
        switch self {
        case .sedentary: return "chair.lounge.fill"
        case .light: return "figure.walk"
        case .moderate: return "figure.run"
        case .active: return "figure.highintensity.intervaltraining"
        case .veryActive: return "flame.fill"
        }
    }

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }

    var waterBonusMl: Double {
        switch self {
        case .sedentary: return 0
        case .light: return 150
        case .moderate: return 300
        case .active: return 500
        case .veryActive: return 700
        }
    }
}

enum FitnessGoal: String, Codable, CaseIterable, Identifiable {
    case loseWeight, maintain, gainMuscle, improveFitness
    var id: String { rawValue }

    var title: String {
        switch self {
        case .loseWeight: return "Kilo vermek"
        case .maintain: return "Kiloyu korumak"
        case .gainMuscle: return "Kas kazanmak"
        case .improveFitness: return "Kondisyonu artırmak"
        }
    }

    var subtitle: String {
        switch self {
        case .loseWeight: return "Kontrollü kalori açığı"
        case .maintain: return "Mevcut dengeni sürdür"
        case .gainMuscle: return "Hafif kalori fazlası"
        case .improveFitness: return "Daha fazla hareket, daha fazla enerji"
        }
    }

    var systemImage: String {
        switch self {
        case .loseWeight: return "arrow.down.right.circle.fill"
        case .maintain: return "equal.circle.fill"
        case .gainMuscle: return "dumbbell.fill"
        case .improveFitness: return "heart.circle.fill"
        }
    }

    var calorieAdjustment: Double {
        switch self {
        case .loseWeight: return -500
        case .maintain, .improveFitness: return 0
        case .gainMuscle: return 300
        }
    }

    var baseStepGoal: Int {
        switch self {
        case .loseWeight, .improveFitness: return 10_000
        case .maintain, .gainMuscle: return 8_000
        }
    }
}

// MARK: - Firestore modeli
/// Firestore `users/{uid}` dökümanı.
struct AppUser: Codable, Identifiable, Equatable {
    var id: String                     // Firebase uid
    var email: String
    var displayName: String
    var birthDate: Date?
    var heightCm: Double?
    var weightKg: Double?
    var gender: Gender?
    var photoURL: String?

    var activityLevel: ActivityLevel
    var goal: FitnessGoal
    var targetWeightKg: Double?
    var startWeightKg: Double?

    var dailyStepGoal: Int
    var dailyCalorieGoal: Int
    var dailyWaterGoalMl: Int
    var sleepGoalHours: Double

    var hasCompletedOnboarding: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Yalnızca Firebase konsolundan / Admin SDK ile atanır. Firestore kuralları istemcinin değiştirmesini engeller.
    var role: String?

    var isAdmin: Bool { role == "admin" }
    var age: Int? { birthDate?.yearsSinceNow }

    static func makeNew(id: String, email: String, displayName: String) -> AppUser {
        AppUser(
            id: id,
            email: email,
            displayName: displayName,
            birthDate: nil,
            heightCm: nil,
            weightKg: nil,
            gender: nil,
            photoURL: nil,
            activityLevel: .moderate,
            goal: .maintain,
            targetWeightKg: nil,
            startWeightKg: nil,
            dailyStepGoal: Constants.Defaults.stepGoal,
            dailyCalorieGoal: Constants.Defaults.calorieGoal,
            dailyWaterGoalMl: Constants.Defaults.waterGoalMl,
            sleepGoalHours: Constants.Defaults.sleepGoalHours,
            hasCompletedOnboarding: false,
            createdAt: .now,
            updatedAt: .now,
            role: nil
        )
    }
}

// MARK: - SwiftData (çevrimdışı önbellek)
/// Kullanıcı profilinin yerel kopyası. İnternetsiz açılışta kullanılır.
@Model
final class LocalUserProfile {
    @Attribute(.unique) var uid: String
    var payload: Data
    var updatedAt: Date

    init(uid: String, payload: Data, updatedAt: Date = .now) {
        self.uid = uid
        self.payload = payload
        self.updatedAt = updatedAt
    }
}
