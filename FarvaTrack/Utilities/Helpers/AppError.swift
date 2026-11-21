import Foundation

/// Uygulama genelinde kullanılan, kullanıcıya gösterilebilir hata türleri.
enum AppError: LocalizedError, Equatable {
    case invalidEmail
    case weakPassword
    case emailAlreadyInUse
    case wrongCredentials
    case tooManyRequests
    case network
    case requiresRecentLogin
    case appleSignInFailed
    case notAuthenticated
    case notAuthorized
    case firebaseNotConfigured
    case healthUnavailable
    case health(String)
    case invalidInput(String)
    case storage(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Geçerli bir e-posta adresi gir."
        case .weakPassword:
            return "Şifre çok zayıf. En az \(Constants.Validation.minPasswordLength) karakter kullan."
        case .emailAlreadyInUse:
            return "Bu e-posta adresiyle zaten bir hesap var."
        case .wrongCredentials:
            return "E-posta veya şifre hatalı."
        case .tooManyRequests:
            return "Çok fazla deneme yapıldı. Lütfen biraz sonra tekrar dene."
        case .network:
            return "İnternet bağlantısı kurulamadı. Bağlantını kontrol et."
        case .requiresRecentLogin:
            return "Bu işlem için yeniden giriş yapman gerekiyor."
        case .appleSignInFailed:
            return "Apple ile giriş tamamlanamadı. Lütfen tekrar dene."
        case .notAuthenticated:
            return "Oturum bulunamadı. Lütfen tekrar giriş yap."
        case .notAuthorized:
            return "Bu özellik için yetkin yok."
        case .firebaseNotConfigured:
            return "Firebase yapılandırılmamış (GoogleService-Info.plist eksik)."
        case .healthUnavailable:
            return "Bu cihazda Sağlık verisi kullanılamıyor."
        case .health(let message):
            return "Sağlık verisi okunamadı: \(message)"
        case .invalidInput(let message):
            return message
        case .storage(let message):
            return "Dosya işlemi başarısız: \(message)"
        case .unknown(let message):
            return "Beklenmeyen bir hata oluştu: \(message)"
        }
    }

    /// Firebase Auth hata alanı. Sürümler arasında değişmediği için metin olarak karşılaştırılır.
    static let firebaseAuthErrorDomain = "FIRAuthErrorDomain"

    /// Herhangi bir `Error`'ı `AppError`'a çevirir.
    static func map(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }

        let nsError = error as NSError

        if nsError.domain == firebaseAuthErrorDomain {
            // FIRAuthErrorCode sayısal değerleri (Firebase 10 ve 11'de aynı).
            switch nsError.code {
            case 17008: return .invalidEmail
            case 17026: return .weakPassword
            case 17007: return .emailAlreadyInUse
            case 17009, 17011, 17004: return .wrongCredentials      // yanlış şifre, kullanıcı yok, geçersiz kimlik
            case 17010: return .tooManyRequests
            case 17020: return .network
            case 17014: return .requiresRecentLogin
            default: return .unknown(nsError.localizedDescription)
            }
        }

        if nsError.domain == NSURLErrorDomain { return .network }
        return .unknown(nsError.localizedDescription)
    }
}
