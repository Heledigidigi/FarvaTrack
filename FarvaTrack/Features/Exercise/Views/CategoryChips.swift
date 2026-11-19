import SwiftUI

struct CategoryChips: View {
    @Binding var selected: ExerciseCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Tümü", systemImage: "square.grid.2x2.fill", tint: Color.ftAccentLight, isSelected: selected == nil) {
                    selected = nil
                }
                ForEach(ExerciseCategory.allCases) { category in
                    chip(
                        title: category.title,
                        systemImage: category.systemImage,
                        tint: category.tint,
                        isSelected: selected == category
                    ) {
                        selected = (selected == category) ? nil : category
                    }
                }
            }
            .padding(.horizontal, Constants.Layout.screenPadding)
        }
    }

    private func chip(
        title: String,
        systemImage: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action() }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : Color.ftTextSecondary)
                .background(isSelected ? tint.opacity(0.9) : Color.ftCard, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}