import SwiftUI

struct ProgressRing<Content: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 12
    var color: Color = Color.ftAccentLight
    @ViewBuilder var content: () -> Content

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.55), color]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(max(360 * clamped, 1))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: clamped)

            content()
        }
        .padding(lineWidth / 2)
    }
}

extension ProgressRing where Content == EmptyView {
    init(progress: Double, lineWidth: CGFloat = 12, color: Color = Color.ftAccentLight) {
        self.init(progress: progress, lineWidth: lineWidth, color: color) { EmptyView() }
    }
}