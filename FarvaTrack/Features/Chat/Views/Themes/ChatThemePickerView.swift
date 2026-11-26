import SwiftUI

/// Kişi bilgisi → Görünüm → Sohbet teması. Seçilen tema iki tarafta da görünür.
struct ChatThemePickerView: View {
    let viewModel: ChatViewModel

    private var current: ChatThemeChoice? { viewModel.theme }
    private var currentID: ChatThemeID { current?.id ?? .plain }

    var body: some View {
        List {
            Section {
                ForEach(ChatThemeID.allCases) { theme in
                    Button { select(theme) } label: { row(theme) }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(theme.title)
                        .accessibilityValue(currentID == theme ? "Seçili" : "")
                        .accessibilityHint(theme.subtitle)
                        .accessibilityAddTraits(currentID == theme ? [.isButton, .isSelected] : .isButton)
                }
            } footer: {
                Text("Tema bu sohbette iki tarafta da görünür. Kendi özel baloncuğunu seçtiysen mesajların o baloncukla kalır; tema yalnızca varsayılan baloncuğu boyar.")
            }
            .listRowBackground(Color.ftCard)

            if currentID == .hillCat {
                Section("Gökyüzü") {
                    Picker("Gökyüzü", selection: Binding(
                        get: { current?.hillSky ?? .golden },
                        set: { sky in
                            Haptics.selection()
                            viewModel.setTheme(.hillCat, sky: sky)
                        }
                    )) {
                        ForEach(ChatHillSky.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .listRowBackground(Color.ftCard)
            }
        }
        .scrollContentBackground(.hidden)
        .ftScreenBackground()
        .navigationTitle("Sohbet teması")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func row(_ theme: ChatThemeID) -> some View {
        HStack(spacing: 14) {
            thumbnail(theme)
            VStack(alignment: .leading, spacing: 3) {
                Text(theme.title).font(.body.weight(.semibold)).foregroundStyle(Color.ftText)
                Text(theme.subtitle).font(.footnote).foregroundStyle(Color.ftTextSecondary)
            }
            Spacer(minLength: 0)
            if currentID == theme {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.ftAccent)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func thumbnail(_ theme: ChatThemeID) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let asset = theme.thumbnailAsset {
                Image(asset).resizable().scaledToFill()
            } else {
                Color.ftCardElevated.overlay(Image(systemName: "circle.slash").foregroundStyle(Color.ftTextSecondary))
            }
        }
        .frame(width: 52, height: 92)
        .clipShape(shape)
        .overlay(shape.strokeBorder(currentID == theme ? Color.ftAccent : Color.ftCardBorder, lineWidth: currentID == theme ? 2 : 1))
    }

    private func select(_ theme: ChatThemeID) {
        guard theme != currentID else { return }
        Haptics.selection()
        viewModel.setTheme(theme, sky: theme == .hillCat ? (current?.hillSky ?? .golden) : nil)
    }
}
