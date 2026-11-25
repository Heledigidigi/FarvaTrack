import SwiftUI

/// Uygulamanın görünüm teması. Klasik (varsayılan): vintage kâğıt zemin, krem kartlar,
/// sepya yazılar. Koyu: önceki koyu tema. Seçim Ayarlar → Görünüm'den yapılır.
enum AppTheme: String, CaseIterable, Identifiable {
    case klasik
    case koyu

    /// `@AppStorage` anahtarı.
    static let storageKey = "app.theme"
    /// Hiç seçim yapılmamışsa kullanılan tema.
    static let `default`: AppTheme = .klasik

    var id: String { rawValue }

    var title: String {
        switch self {
        case .klasik: "Klasik"
        case .koyu: "Koyu"
        }
    }

    /// Renkler `Color.ft*` içinde açık/koyu görünüme göre çözülür; tema bunu belirler.
    var colorScheme: ColorScheme {
        switch self {
        case .klasik: .light
        case .koyu: .dark
        }
    }

    /// Kayıtlı değerden tema; bilinmeyen ya da boş değer varsayılana düşer.
    static func resolve(_ raw: String?) -> AppTheme {
        raw.flatMap(AppTheme.init(rawValue:)) ?? .default
    }

    /// Şu an kayıtlı tema (UIKit görünüm ayarları gibi SwiftUI dışı yerler için).
    static var current: AppTheme {
        resolve(UserDefaults.standard.string(forKey: storageKey))
    }
}

/// Ekran arka planı: klasik temada vintage kâğıt görseli, koyu temada düz koyu renk.
struct ThemeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.ftBackground
            .overlay {
                if colorScheme == .light {
                    Image("VintageZemin")
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                }
            }
            .clipped()
    }
}

extension View {
    /// Tam ekran tema zemini (eski `.ftScreenBackground()`).
    func ftScreenBackground() -> some View {
        background { ThemeBackground().ignoresSafeArea() }
    }
}
