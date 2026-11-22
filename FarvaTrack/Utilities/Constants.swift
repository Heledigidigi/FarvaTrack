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
        static let wasteDaily = "wasteDaily"
        static let library = "library"
        static let templates = "templates"
        static let programs = "programs"
        static let manualSteps = "manualSteps"
        /// Kişisel sticker kütüphanesi (8D): belge + Storage'da `users/{uid}/stickers/{id}.png`.
        static let stickers = "stickers"
        /// Baloncuk stilleri (8F): belge `json` + Storage `users/{uid}/bubbles/{id}/{asset}.png`.
        static let bubbles = "bubbles"
        /// Push bildirimi cihazları (8G): `users/{uid}/devices/{cihazId}` → `token`, `muted`.
        static let devices = "devices"

        /// Sohbet: `chats/{chatId}/messages/{id}` ve `chatInvites/{code}` (kullanıcı altında değil, iki kişiye ortak).
        /// Hesap silinirken `ChatSyncing.purgeUserData` ile temizlenir.
        static let chats = "chats"
        static let chatMessages = "messages"
        static let chatInvites = "chatInvites"
        /// Sohbet üstüne serbestçe bırakılan sticker'lar (8E).
        static let chatPlacements = "placements"

        /// Hesap silinirken temizlenen `users/{uid}` alt koleksiyonları.
        static let userSubcollections = [workouts, meals, water, sleep, weight, measurements, waste, wasteDaily, library, templates, programs, manualSteps, stickers, bubbles, devices]
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
        static let minAge = 13          // Mağaza/yasal gereksinimlere göre güncelle
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
}
