import SwiftUI
import UIKit

extension Color {
    /// "#RRGGBB" veya "RRGGBB" formatında hex renk.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        guard cleaned.count == 6 else {
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    // MARK: - FarvaTrack paleti
    // Her renk iki görünümle tanımlıdır: koyu tema (eski palet) ve klasik tema (vintage krem/sepya).
    // Hangi görünümün kullanılacağını kökteki `preferredColorScheme(AppTheme.colorScheme)` belirler.

    /// Açık (klasik) ve koyu görünüme göre çözülen renk.
    static func ftDynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// Hex'ten UIColor (isteğe bağlı saydamlık).
    static func ftUI(_ hex: String, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(Color(hex: hex)).withAlphaComponent(alpha)
    }

    // Laciverte geçmek için (koyu): ftAccent -> "#00356B", ftAccentLight -> "#5B8FD6"
    /// Dolgu vurgusu (düğme, giden baloncuk); üstünde beyaz yazı.
    static let ftAccent = ftDynamic(light: ftUI("#8E2A22"), dark: ftUI("#800020"))
    /// Zeminde yazı ve ikonlar için okunaklı vurgu (koyuda açık bordo, klasikte kiremit).
    static let ftAccentLight = ftDynamic(light: ftUI("#A23A2E"), dark: ftUI("#E0607F"))

    /// Düz zemin rengi; klasik temada asıl zemin `ThemeBackground` görselidir.
    static let ftBackground = ftDynamic(light: ftUI("#EADBBE"), dark: ftUI("#0E0E12"))
    /// Kart: klasikte yarı saydam krem (vintage zemin altından görünür).
    static let ftCard = ftDynamic(light: ftUI("#FBF0D4", 0.74), dark: ftUI("#1A1A21"))
    static let ftCardElevated = ftDynamic(light: ftUI("#F3E3C0", 0.92), dark: ftUI("#25252F"))
    /// Üst çubuk, yazma alanı ve klavye panelleri: aynı opak zemin (klasikte kreme yakın).
    static let ftChrome = ftDynamic(light: ftUI("#F3E5C5"), dark: ftUI("#1A1A21"))
    /// Kart kenar çizgisi (yalnızca klasik temada görünür).
    static let ftCardBorder = ftDynamic(light: ftUI("#7A5832", 0.26), dark: .clear)

    /// Ana yazı rengi (koyuda beyaz, klasikte koyu kahve).
    static let ftText = ftDynamic(light: ftUI("#3E2A1C"), dark: .white)
    static let ftTextSecondary = ftDynamic(light: ftUI("#7A5C44"), dark: UIColor.white.withAlphaComponent(0.65))

    /// Halka izi, ızgara çizgisi, ince zemin gibi silik dolgular (koyuda beyaz, klasikte kahve).
    static func ftSubtle(_ opacity: Double) -> Color {
        ftDynamic(light: ftUI("#785A37", CGFloat(min(1, opacity * 1.7))),
                  dark: UIColor.white.withAlphaComponent(CGFloat(opacity)))
    }

    static let ftSuccess = ftDynamic(light: ftUI("#4F7A4A"), dark: ftUI("#30A46C"))
    static let ftWarning = ftDynamic(light: ftUI("#B9772F"), dark: ftUI("#F5A524"))
    static let ftDanger = ftDynamic(light: ftUI("#B3402B"), dark: ftUI("#E5484D"))

    // Modül renkleri
    static let ftCalories = ftDynamic(light: ftUI("#B9772F"), dark: ftUI("#FF9F43"))
    static let ftWater = ftDynamic(light: ftUI("#5F8796"), dark: ftUI("#4DA3FF"))
    static let ftSleep = ftDynamic(light: ftUI("#7D6A93"), dark: ftUI("#8B7CF6"))
    static let ftWeight = ftDynamic(light: ftUI("#6E8A6A"), dark: ftUI("#2DD4BF"))
    static let ftExercise = ftDynamic(light: ftUI("#B0574A"), dark: ftUI("#F06A6A"))
    static let ftWaste = ftDynamic(light: ftUI("#8A8A3A"), dark: ftUI("#84CC16"))
    static let ftStats = ftDynamic(light: ftUI("#A6863F"), dark: ftUI("#F5C451"))
}
