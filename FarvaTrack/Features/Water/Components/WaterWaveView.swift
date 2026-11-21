import SwiftUI

/// Üstü dalgalı su yüzeyi. `progress` değişince seviye yumuşakça hareket eder.
struct WaveShape: Shape {
    var progress: Double
    var phase: Double
    var amplitude: CGFloat
    var wavelength: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0.001 else { return path }

        let clamped = CGFloat(min(progress, 1))
        let level = rect.height * (1 - clamped)

        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: level))
        for x in stride(from: CGFloat(0), through: rect.width, by: 2) {
            let angle = Double(x / wavelength) * 2 * .pi + phase
            path.addLine(to: CGPoint(x: x, y: level + amplitude * CGFloat(sin(angle))))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct WaterWaveView: View {
    var progress: Double
    var colors: [Color] = [Color(hex: "#4DA3FF"), Color(hex: "#1F5FB8")]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // "Hareketi Azalt" açıkken dalga akışı durur, seviye değişimi yine görünür.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                WaveShape(progress: progress, phase: t * 1.4, amplitude: 9, wavelength: 220)
                    .fill(LinearGradient(
                        colors: colors.map { $0.opacity(0.5) },
                        startPoint: .top, endPoint: .bottom
                    ))
                WaveShape(progress: progress, phase: -t * 2.0 + 1.5, amplitude: 7, wavelength: 160)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            }
        }
        .animation(.spring(response: 1.0, dampingFraction: 0.8), value: progress)
        .accessibilityHidden(true)
    }
}
