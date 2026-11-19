import SwiftUI

enum Constants {
    enum Collection {
        static let users = "users"
        static let workouts = "workouts"
        static let meals = "meals"
        static let water = "water"
        static let sleep = "sleep"
        static let weight = "weight"
        static let measurements = "measurements"
        static let waste = "waste"
        static let library = "library"
    }

    enum StoragePath {
        static let profileImages = "profile_images"
    }

    enum Layout {
        static let cornerRadius: CGFloat = 16
        static let screenPadding: CGFloat = 20
        static let fieldHeight: CGFloat = 54
    }

    enum Validation {
        static let minPasswordLength = 8
        static let minAge = 13          // Mağaza/yasal gereksinimlerine göre güncelle
        static let maxAge = 100
    }

    enum Defaults {
        static let stepGoal = 8_000
        static let calorieGoal = 2_000
        static let waterGoalMl = 2_500
        static let sleepGoalHours = 8.0
    }

    enum Training {
        static let minutesPerSet = 2.5        // set + dinlenme tahmini süre (dk)
        static let fallbackWeightKg = 70.0    // profilde kilo yoksa kullanılır
    }

    enum Links {
        // TODO: Kendi adreslerinle değiştir.
        static let privacyPolicy = "https://example.com/gizlilik"
        static let termsOfUse = "https://example.com/kosullar"
    }
}