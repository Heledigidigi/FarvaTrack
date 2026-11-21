import SwiftUI

/// 1–5 yıldız kalite seçici. `isEditable` false ise yalnızca gösterir.
struct StarRatingView: View {
    @Binding var rating: Int
    var isEditable = true
    var size: CGFloat = 28
    var tint: Color = .ftStats

    var body: some View {
        HStack(spacing: size * 0.25) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(star <= rating ? tint : Color.ftTextSecondary.opacity(0.4))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isEditable else { return }
                        Haptics.selection()
                        withAnimation(.spring(response: 0.3)) { rating = star }
                    }
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Uyku kalitesi")
        .accessibilityValue("\(rating) yıldız")
        .accessibilityAdjustableAction { direction in
            guard isEditable else { return }
            switch direction {
            case .increment: rating = min(rating + 1, 5)
            case .decrement: rating = max(rating - 1, 1)
            @unknown default: break
            }
        }
    }
}

extension StarRatingView {
    /// Salt okunur gösterim.
    init(value: Int, size: CGFloat = 14) {
        self.init(rating: .constant(value), isEditable: false, size: size)
    }
}
