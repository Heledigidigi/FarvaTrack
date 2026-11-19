import Foundation
import Observation

struct ProfileDraft: Equatable {
    var displayName: String
    var birthDate: Date
    var heightCm: Double
    var gender: Gender?
    var activityLevel: ActivityLevel
    var goal: FitnessGoal

    init(user: AppUser, now: Date = .now) {
        displayName = user.displayName
        birthDate = user.birthDate ?? (Calendar.current.date(byAdding: .year, value: -25, to: now) ?? now)
        heightCm = user.heightCm ?? 170
        gender = user.gender
        activityLevel = user.activityLevel
        goal = user.goal
    }
}

struct RecalcOffer: Equatable {
    /// Adım hedefi de yeniden hesaplansın mı (yalnızca aktivite veya hedef türü değiştiyse).
    let includesSteps: Bool
}

@MainActor
@Observable
final class ProfileViewModel {
    var errorMessage: String?
    private(set) var isUploadingPhoto = false
    private(set) var recalcOffer: RecalcOffer?
    private(set) var user: AppUser?

    @ObservationIgnored private var updateProfile: ((AppUser) async -> Void)?
    @ObservationIgnored private let photos: ProfilePhotoStoring
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    init(
        photos: ProfilePhotoStoring = FirebaseManager.shared,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.photos = photos
        self.calendar = calendar
        self.now = now
    }

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func configure(user: AppUser, updateProfile: @escaping (AppUser) async -> Void) {
        self.user = user
        self.updateProfile = updateProfile
    }

    // MARK: - Doğrulama
    func age(of birthDate: Date) -> Int {
        calendar.dateComponents([.year], from: birthDate, to: now()).year ?? 0
    }

    func validate(_ draft: ProfileDraft) throws {
        let name = draft.displayName.trimmed
        guard (1...50).contains(name.count) else {
            throw AppError.invalidInput("Ad 1 ile 50 karakter arasında olmalı.")
        }
        guard (100.0...250.0).contains(draft.heightCm) else {
            throw AppError.invalidInput("Boy 100 ile 250 cm arasında olmalı.")
        }
        guard draft.birthDate <= now() else {
            throw AppError.invalidInput("Doğum tarihi gelecekte olamaz.")
        }
        let age = age(of: draft.birthDate)
        guard (Constants.Validation.minAge...Constants.Validation.maxAge).contains(age) else {
            throw AppError.invalidInput("Yaş \(Constants.Validation.minAge) ile \(Constants.Validation.maxAge) arasında olmalı.")
        }
        if age < 18, draft.goal == .loseWeight {
            throw AppError.invalidInput("18 yaş altında kilo verme hedefi belirlemek yerine bir sağlık uzmanına danışmanı öneririz. Lütfen başka bir hedef seç.")
        }
    }

    // MARK: - Kaydetme
    @discardableResult
    func save(_ draft: ProfileDraft) async throws -> AppUser {
        guard var updated = user, let updateProfile else { throw AppError.notAuthenticated }
        try validate(draft)

        let birthDateChanged = updated.birthDate.map { !calendar.isDate($0, inSameDayAs: draft.birthDate) } ?? true
        let activityOrGoalChanged = updated.activityLevel != draft.activityLevel || updated.goal != draft.goal
        let relevantChanged = birthDateChanged
            || updated.heightCm != draft.heightCm
            || updated.gender != draft.gender
            || activityOrGoalChanged

        updated.displayName = draft.displayName.trimmed
        updated.birthDate = draft.birthDate
        updated.heightCm = draft.heightCm
        updated.gender = draft.gender
        updated.activityLevel = draft.activityLevel
        updated.goal = draft.goal

        user = updated
        if relevantChanged {
            recalcOffer = RecalcOffer(includesSteps: activityOrGoalChanged)
        }
        Haptics.success()
        await updateProfile(updated)
        return updated
    }

    // MARK: - Hedefleri yeniden hesaplama
    /// Kalori, su ve uyku hedeflerini yeni profile göre hesaplar; adım hedefi yalnızca istenirse güncellenir.
    static func recalculatedGoals(for user: AppUser, includeSteps: Bool, now: Date = .now, calendar: Calendar = .current) -> AppUser? {
        guard let weight = user.weightKg, let height = user.heightCm,
              let birthDate = user.birthDate, let gender = user.gender else { return nil }

        let age = calendar.dateComponents([.year], from: birthDate, to: now).year ?? 0
        let recommendation = CalorieCalculator.recommendation(
            weightKg: weight, heightCm: height, age: age,
            gender: gender, activity: user.activityLevel, goal: user.goal
        )

        var updated = user
        updated.dailyCalorieGoal = recommendation.calorieGoal
        updated.dailyWaterGoalMl = recommendation.waterGoalMl
        updated.sleepGoalHours = recommendation.sleepHours
        if includeSteps { updated.dailyStepGoal = recommendation.stepGoal }
        return updated
    }

    func acceptRecalculation() async {
        let offer = recalcOffer
        recalcOffer = nil
        guard let offer, let user, let updateProfile,
              let updated = Self.recalculatedGoals(for: user, includeSteps: offer.includesSteps, now: now(), calendar: calendar)
        else { return }
        self.user = updated
        Haptics.success()
        await updateProfile(updated)
    }

    func dismissRecalculation() {
        recalcOffer = nil
    }

    // MARK: - Fotoğraf
    func uploadPhoto(_ data: Data) async {
        guard var updated = user, let updateProfile else { return }
        guard let processed = ProfileImageProcessor.process(data) else {
            errorMessage = "Seçilen fotoğraf işlenemedi. Başka bir görsel dene."
            return
        }

        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            let url = try await photos.uploadPhoto(processed, uid: updated.id)
            updated.photoURL = url.absoluteString
            user = updated
            Haptics.success()
            await updateProfile(updated)
        } catch {
            errorMessage = AppError.map(error).errorDescription
            Haptics.error()
        }
    }

    func removePhoto() async {
        guard var updated = user, let updateProfile, updated.photoURL != nil else { return }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }

        await photos.deletePhoto(uid: updated.id)
        updated.photoURL = nil
        user = updated
        await updateProfile(updated)
    }
}