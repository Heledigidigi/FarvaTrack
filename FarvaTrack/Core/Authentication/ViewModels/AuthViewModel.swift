import Foundation
import Observation
import SwiftData
import AuthenticationServices
import CryptoKit

@MainActor
@Observable
final class AuthViewModel {

    enum AuthState: Equatable {
        case loading
        case unauthenticated
        case onboarding
        case authenticated
    }

    // MARK: - Durum
    private(set) var authState: AuthState = .loading
    private(set) var currentUser: AppUser?
    private(set) var isWorking = false
    var errorMessage: String?
    var infoMessage: String?

    // MARK: - Form alanları
    var displayName = ""
    var email = ""
    var password = ""
    var confirmPassword = ""

    // MARK: - Bağımlılıklar (gözlemlenmez)
    @ObservationIgnored private let service: FirebaseServicing
    @ObservationIgnored private let modelContext: ModelContext?
    @ObservationIgnored private var listenerToken: Any?
    @ObservationIgnored private var currentNonce: String?
    @ObservationIgnored private var isPerformingAuthAction = false

    init(service: FirebaseServicing, modelContext: ModelContext? = nil) {
        self.service = service
        self.modelContext = modelContext
    }

    // MARK: - Uyarı yardımcıları
    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    var hasInfo: Bool {
        get { infoMessage != nil }
        set { if !newValue { infoMessage = nil } }
    }

    /// 0...4 arası basit şifre gücü.
    var passwordStrength: Int {
        var score = 0
        if password.count >= Constants.Validation.minPasswordLength { score += 1 }
        if password.count >= 12 { score += 1 }
        let hasLetters = password.rangeOfCharacter(from: .letters) != nil
        let hasDigits = password.rangeOfCharacter(from: .decimalDigits) != nil
        if hasLetters && hasDigits { score += 1 }
        let hasMixedCase = password.rangeOfCharacter(from: .uppercaseLetters) != nil
            && password.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasSymbol = password.rangeOfCharacter(from: CharacterSet.punctuationCharacters.union(.symbols)) != nil
        if hasMixedCase || hasSymbol { score += 1 }
        return score
    }

    // MARK: - Yaşam döngüsü
    func start() {
        guard listenerToken == nil else { return }
        listenerToken = service.observeAuthState { [weak self] uid in
            Task { @MainActor [weak self] in
                await self?.handleAuthStateChange(uid: uid)
            }
        }
    }

    func stop() {
        if let token = listenerToken {
            service.stopObserving(token)
            listenerToken = nil
        }
    }

    private func handleAuthStateChange(uid: String?) async {
        guard let uid else {
            currentUser = nil
            authState = .unauthenticated
            return
        }
        // Giriş/kayıt akışı profili kendisi yüklüyor; yarış durumunu engelle.
        guard !isPerformingAuthAction else { return }
        await bootstrapProfile(uid: uid)
    }

    // MARK: - E-posta ile giriş / kayıt
    func signIn() async {
        let mail = email.trimmed
        guard mail.isValidEmail else { return present(AppError.invalidEmail) }
        guard !password.isEmpty else { return present(AppError.invalidInput("Şifreni gir.")) }

        isWorking = true
        isPerformingAuthAction = true
        defer { isWorking = false; isPerformingAuthAction = false }

        do {
            let uid = try await service.signIn(email: mail, password: password)
            await bootstrapProfile(uid: uid, email: mail)
            password = ""
            Haptics.success()
        } catch {
            present(error)
        }
    }

    func register() async {
        let name = displayName.trimmed
        let mail = email.trimmed

        guard !name.isEmpty else { return present(AppError.invalidInput("Adını gir.")) }
        guard mail.isValidEmail else { return present(AppError.invalidEmail) }
        guard password.count >= Constants.Validation.minPasswordLength else {
            return present(AppError.weakPassword)
        }
        guard password == confirmPassword else {
            return present(AppError.invalidInput("Şifreler eşleşmiyor."))
        }

        isWorking = true
        isPerformingAuthAction = true
        defer { isWorking = false; isPerformingAuthAction = false }

        do {
            let uid = try await service.register(email: mail, password: password)
            await bootstrapProfile(uid: uid, displayName: name, email: mail)
            password = ""
            confirmPassword = ""
            Haptics.success()
        } catch {
            present(error)
        }
    }

    func sendPasswordReset() async {
        let mail = email.trimmed
        guard mail.isValidEmail else { return present(AppError.invalidEmail) }

        isWorking = true
        defer { isWorking = false }

        do {
            try await service.sendPasswordReset(email: mail)
            infoMessage = "Bu e-posta ile kayıtlı bir hesap varsa, şifre sıfırlama bağlantısı gönderildi."
        } catch {
            present(error)
        }
    }

    // MARK: - Apple ile giriş
    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            present(AppError.appleSignInFailed)

        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let nonce = currentNonce,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                return present(AppError.appleSignInFailed)
            }

            isWorking = true
            isPerformingAuthAction = true
            defer { isWorking = false; isPerformingAuthAction = false }

            do {
                let result = try await service.signInWithApple(
                    idToken: idToken,
                    rawNonce: nonce,
                    fullName: credential.fullName
                )
                // Apple adı yalnızca ilk girişte verir.
                let name = credential.fullName
                    .map { PersonNameComponentsFormatter().string(from: $0).trimmed }
                    .flatMap { $0.isEmpty ? nil : $0 }

                await bootstrapProfile(
                    uid: result.uid,
                    displayName: name,
                    email: result.email ?? credential.email
                )
                currentNonce = nil
                Haptics.success()
            } catch {
                present(error)
            }
        }
    }

    // MARK: - Çıkış
    func signOut() {
        do {
            try service.signOut()
            clearCache()
            SharedStore.clearAll()      // widget'lar önceki hesabın verisini göstermesin
            resetForm()
            currentUser = nil
            authState = .unauthenticated
            Haptics.impact()
        } catch {
            present(error)
        }
    }

    // MARK: - Profil güncelleme
    func completeOnboarding(_ profile: AppUser) async {
        var user = profile
        user.hasCompletedOnboarding = true
        await persist(user)
    }

    func updateUser(_ user: AppUser) async {
        await persist(user)
    }

    private func persist(_ user: AppUser) async {
        var updated = user
        updated.updatedAt = .now
        do {
            try await service.saveUser(updated)
            apply(updated)
            Haptics.success()
        } catch {
            present(error)
        }
    }

    // MARK: - Profil fotoğrafı
    /// Fotoğrafı yükler ve profile bağlar. Storage kurulmamışsa anlaşılır bir hata gösterir.
    @discardableResult
    func updateProfilePhoto(_ jpegData: Data) async -> Bool {
        guard var user = currentUser else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await service.uploadProfileImage(jpegData, uid: user.id)
            user.photoURL = url.absoluteString
            await persist(user)
            return true
        } catch {
            errorMessage = "Fotoğraf yüklenemedi. \(AppError.map(error).errorDescription ?? "")"
            Haptics.error()
            return false
        }
    }

    func removeProfilePhoto() async {
        guard var user = currentUser, user.photoURL != nil else { return }
        user.photoURL = nil
        await persist(user)
    }

    // MARK: - Hesap silme
    var usesPasswordSignIn: Bool { service.usesPasswordSignIn }

    /// Sunucudaki tüm verileri ve hesabı, ardından cihazdaki verileri siler. Başarılıysa `true`.
    @discardableResult
    func deleteAccount(password: String) async -> Bool {
        guard let user = currentUser else { return false }
        if service.usesPasswordSignIn && password.isEmpty {
            present(AppError.invalidInput("Hesabını silmek için şifreni gir."))
            return false
        }

        isWorking = true
        isPerformingAuthAction = true
        defer { isWorking = false; isPerformingAuthAction = false }

        do {
            if service.usesPasswordSignIn {
                try await service.reauthenticate(email: user.email, password: password)
            }
            try await service.deleteAccount(uid: user.id)
        } catch {
            let mapped = AppError.map(error)
            if case .requiresRecentLogin = mapped {
                errorMessage = "Güvenlik nedeniyle yakın zamanda giriş yapmış olman gerekiyor. Çıkış yapıp tekrar giriş yaptıktan sonra yeniden dene."
                Haptics.error()
            } else {
                present(mapped)
            }
            return false
        }

        if let modelContext {
            try? LocalDataCleaner.purge(ownerID: user.id, context: modelContext)
        }
        SharedStore.clearAll()
        resetForm()
        currentUser = nil
        authState = .unauthenticated
        infoMessage = "Hesabın ve tüm verilerin silindi."
        Haptics.success()
        return true
    }

    // MARK: - Profil yükleme
    private func bootstrapProfile(uid: String, displayName: String? = nil, email: String? = nil) async {
        do {
            if let existing = try await service.fetchUser(uid: uid) {
                apply(existing)
            } else {
                let newUser = AppUser.makeNew(
                    id: uid,
                    email: email ?? "",
                    displayName: displayName ?? ""
                )
                try await service.saveUser(newUser)
                apply(newUser)
            }
        } catch {
            if let cached = loadCachedUser(uid: uid) {
                apply(cached)      // çevrimdışı yedek
            } else {
                errorMessage = AppError.map(error).errorDescription
                authState = .unauthenticated
            }
        }
    }

    private func apply(_ user: AppUser) {
        currentUser = user
        cache(user)
        authState = user.hasCompletedOnboarding ? .authenticated : .onboarding
    }

    // MARK: - SwiftData önbelleği
    private func cache(_ user: AppUser) {
        guard let modelContext, let data = try? JSONEncoder().encode(user) else { return }
        let uid = user.id
        let descriptor = FetchDescriptor<LocalUserProfile>(predicate: #Predicate { $0.uid == uid })

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.payload = data
            existing.updatedAt = .now
        } else {
            modelContext.insert(LocalUserProfile(uid: uid, payload: data))
        }
        try? modelContext.save()
    }

    private func loadCachedUser(uid: String) -> AppUser? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<LocalUserProfile>(predicate: #Predicate { $0.uid == uid })
        guard let cached = try? modelContext.fetch(descriptor).first else { return nil }
        return try? JSONDecoder().decode(AppUser.self, from: cached.payload)
    }

    private func clearCache() {
        guard let modelContext else { return }
        try? modelContext.delete(model: LocalUserProfile.self)
        try? modelContext.save()
    }

    // MARK: - Yardımcılar
    private func resetForm() {
        displayName = ""
        email = ""
        password = ""
        confirmPassword = ""
    }

    private func present(_ error: Error) {
        errorMessage = AppError.map(error).errorDescription
        Haptics.error()
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        // `randomElement()` Apple platformlarında kriptografik olarak güvenli üreteci kullanır.
        return String((0..<length).compactMap { _ in charset.randomElement() })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
