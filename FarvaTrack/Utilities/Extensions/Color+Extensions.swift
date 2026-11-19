import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // Temel UI Renkleri
    static let ftBackground = Color(hex: "#0A0D14")
    static let ftCard = Color(hex: "#141824")
    static let ftCardElevated = Color(hex: "#1E2438")
    static let ftAccent = Color(hex: "#10B981")
    static let ftAccentLight = Color(hex: "#34D399")
    static let ftTextSecondary = Color(hex: "#94A3B8")
    static let ftDanger = Color(hex: "#EF4444")
    static let ftSuccess = Color(hex: "#10B981")

    // Modül Renkleri
    static let ftCalories = Color(hex: "#FF9F43")
    static let ftWater = Color(hex: "#4DA3FF")
    static let ftSleep = Color(hex: "#8B7CF6")
    static let ftWeight = Color(hex: "#2DD4BF")
    static let ftExercise = Color(hex: "#F06A6A")
    static let ftWaste = Color(hex: "#84CC16")
    static let ftStats = Color(hex: "#F5C451")
}
