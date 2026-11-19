import Foundation
import Observation
import SwiftData
import AuthenticationServices

@MainActor
@Observable
final class AccountDeletionViewModel {
    enum Phase: Equatable {
        case idle
        case working(String)
        case failed(String)
        case finished
    }

    private(set) var phase: Phase = .idle
    var password = ""
    var confirmed = false
    private(set) var usesApple = false
    private(set) var usesPassword = false

    @ObservationIgnored private let service: AccountDeleting
    @ObservationIgnored private var user: AppUser?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var currentNonce: String?
    @ObservationIgnored private let defaults: UserDefaults

    init(service: AccountDeleting = FirebaseAccountDeletionService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    var hasFailure: Bool {
        get { failureMessage != nil }
        set { if !newValue, hasFailure { phase = .idle } }
    }

    var canSubmitPassword: Bool {
        confirmed && !password.isEmpty && !isWorking
    }

    func configure(user: AppUser, context: ModelContext) {
        self.user = user
        self.context = context
        let providers = service.providerIDs
        usesApple = providers.contains("apple.com")
        usesPassword = providers.contains("password")
    }

    // MARK: - E-posta / şifre
    func deleteWithPassword() async {
        guard canSubmitPassword else { return }
        let entered = password
        await run {
            try await self.service.reauthenticate(password: entered)
            return nil
        }
        password = ""
    }

    // MARK: - Apple
    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleNonce.random()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(nonce)
    }

    func deleteWithApple(_ result: Result<ASAuthorization, Error>) async {
        guard confirmed, !isWorking else { return }

        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            phase = .failed(AppError.appleSignInFailed.errorDescription ?? "Apple doğrulaması tamamlanamadı.")

        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let nonce = currentNonce,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                phase = .failed(AppError.appleSignInFailed.errorDescription ?? "Apple doğrulaması tamamlanamadı.")
                return
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }

            await run {
                try await self.service.reauthenticateWithApple(idToken: idToken, rawNonce: nonce, fullName: credential.fullName)
                return code
            }
        }
    }

    // MARK: - Silme akışı
    /// `reauthenticate`, kimlik doğrulamasını yapar ve (Apple ise) token iptali için yetkilendirme kodunu döndürür.
    private func run(reauthenticate: () async throws -> String?) async {
        guard let user, let context else { return }

        do {
            phase = .working("Bağlantı kontrol ediliyor…")
            guard await service.isOnline() else { throw AppError.network }

            phase = .working("Kimlik doğrulanıyor…")
            let appleCode = try await reauthenticate()

            phase = .working("Sunucudaki verilerin siliniyor…")
            try await service.deleteRemoteData(userID: user.id, includeAdminCollections: user.isAdmin)
            await service.deleteProfilePhoto(userID: user.id)

            if let appleCode {
                // Token iptali başarısız olsa bile silme devam eder (en iyi çaba).
                try? await service.revokeAppleToken(authorizationCode: appleCode)
            }

            phase = .working("Bu cihazdaki veriler siliniyor…")
            LocalDataCleaner.wipe(userID: user.id, context: context, defaults: defaults)

            phase = .working("Hesabın siliniyor…")
            try await service.deleteAuthUser()

            phase = .finished
            Haptics.success()
        } catch {
            phase = .failed(AppError.map(error).errorDescription ?? "Hesap silinemedi. Lütfen tekrar dene.")
            Haptics.error()
        }
    }
}