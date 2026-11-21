import WidgetKit
import SwiftUI

/// Widget renkleri (uygulamanın paletiyle uyumlu; widget hedefi uygulama dosyalarını derlemez).
enum Palette {
    static let accent = Color(red: 0.50, green: 0.0, blue: 0.125)        // #800020
    static let accentLight = Color(red: 0.88, green: 0.38, blue: 0.50)   // #E0607F
    static let background = Color(red: 0.055, green: 0.055, blue: 0.07)  // #0E0E12
    static let track = Color.white.opacity(0.1)
    static let secondary = Color.white.opacity(0.65)
    static let water = Color(red: 0.30, green: 0.64, blue: 1.0)          // #4DA3FF
    static let waste = Color(red: 0.52, green: 0.80, blue: 0.09)         // #84CC16
}

@main
struct FarvaTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        StepsWidget()
        WaterWidget()
        WasteWidget()
    }
}
