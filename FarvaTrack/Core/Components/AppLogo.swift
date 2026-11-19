import SwiftUI

struct AppLogo: View {
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.ftAccent, Color.ftAccentLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color.ftAccent.opacity(0.35), radius: size * 0.15, y: size * 0.08)

            Image(systemName: "bolt.heart.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundStyle(Color.ftBackground)
        }
    }
}
