import SwiftUI

struct AppLogo: View {
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.ftAccent, Color.ftAccentLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.ftAccent.opacity(0.5), radius: 18, y: 8)

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
