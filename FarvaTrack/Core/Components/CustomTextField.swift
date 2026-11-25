import SwiftUI

struct CustomTextField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var isSecure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var capitalization: TextInputAutocapitalization = .never
    var errorMessage: String?

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    private var borderColor: Color {
        if errorMessage != nil { return Color.ftDanger }
        return isFocused ? Color.ftAccentLight : Color.ftSubtle(0.08)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(isFocused ? Color.ftAccentLight : Color.ftTextSecondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                field
                    .focused($isFocused)
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
                    .accessibilityLabel(title)

                if isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                    .accessibilityLabel(isRevealed ? "Şifreyi gizle" : "Şifreyi göster")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: Constants.Layout.fieldHeight)
            .background(
                Color.ftCard,
                in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.ftDanger)
                    .accessibilityLabel("Hata: \(errorMessage)")
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        let prompt = Text(title).foregroundStyle(Color.ftTextSecondary)
        if isSecure && !isRevealed {
            SecureField("", text: $text, prompt: prompt)
        } else {
            TextField("", text: $text, prompt: prompt)
        }
    }
}
