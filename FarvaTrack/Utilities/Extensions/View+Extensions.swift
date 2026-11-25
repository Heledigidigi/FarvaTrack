import SwiftUI
import UIKit

// MARK: - View yardımcıları
extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                Color.ftCard,
                in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
            )
            // Klasik temada ince sepya kenar (koyu temada görünmez).
            .overlay(
                RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
                    .strokeBorder(Color.ftCardBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }

    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

// MARK: - Buton stili
struct PrimaryButtonStyle: ButtonStyle {
    var isLoading = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, isLoading: isLoading)
    }
}

/// `@Environment(\.isEnabled)` yalnızca bir View içinde güvenilir okunur.
private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isLoading: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView().tint(.white)
            }
            configuration.label
                .font(.headline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: Constants.Layout.fieldHeight)
        .background(
            LinearGradient(
                colors: [Color.ftAccent, Color.ftAccentLight.opacity(0.85)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
        )
        .opacity(isEnabled ? 1 : 0.5)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Haptic geri bildirim
@MainActor
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
