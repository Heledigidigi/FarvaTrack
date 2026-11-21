import SwiftUI

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

    // MARK: - FarvaTrack paleti (koyu tema öncelikli)
    // Laciverte geçmek için: ftAccent -> "#00356B", ftAccentLight -> "#5B8FD6"
    static let ftAccent = Color(hex: "#800020")
    /// Koyu zeminde yazı ve ikonlar için okunaklı açık bordo.
    static let ftAccentLight = Color(hex: "#E0607F")

    static let ftBackground = Color(hex: "#0E0E12")
    static let ftCard = Color(hex: "#1A1A21")
    static let ftCardElevated = Color(hex: "#25252F")

    static let ftTextSecondary = Color.white.opacity(0.65)

    static let ftSuccess = Color(hex: "#30A46C")
    static let ftWarning = Color(hex: "#F5A524")
    static let ftDanger = Color(hex: "#E5484D")

    // Modül renkleri
    static let ftCalories = Color(hex: "#FF9F43")
    static let ftWater = Color(hex: "#4DA3FF")
    static let ftSleep = Color(hex: "#8B7CF6")
    static let ftWeight = Color(hex: "#2DD4BF")
    static let ftExercise = Color(hex: "#F06A6A")
    static let ftWaste = Color(hex: "#84CC16")
    static let ftStats = Color(hex: "#F5C451")
}
