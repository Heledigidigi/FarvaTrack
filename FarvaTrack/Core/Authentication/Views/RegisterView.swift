import SwiftUI
import AuthenticationServices

struct RegisterView: View {
    @Environment(AuthViewModel.self) private var auth

    private var strengthColor: Color {
        switch auth.passwordStrength {
        case ...1: return Color.ftDanger
        case 2: return Color.ftWarning
        default: return Color.ftSuccess
        }
    }

    private var strengthText: String {
        ["Çok zayıf", "Zayıf", "Orta", "İyi", "Güçlü"][min(auth.passwordStrength, 4)]
    }

    private var confirmError: String? {
        guard !auth.confirmPassword.isEmpty, auth.confirmPassword != auth.password else { return nil }
        return "Şifreler eşleşmiyor."
    }

    var body: some View {
        @Bindable var auth = auth

        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Hesap oluştur")
                        .font(.largeTitle.bold())
                    Text("Birkaç saniyede başla, hedeflerini birlikte belirleyelim.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.ftTextSecondary)
                }

                VStack(spacing: 16) {
                    CustomTextField(
                        title: "Ad Soyad",
                        systemImage: "person.fill",
                        text: $auth.displayName,
                        contentType: .name,
                        capitalization: .words
                    )
                    CustomTextField(
                        title: "E-posta",
                        systemImage: "envelope.fill",
                        text: $auth.email,
                        keyboard: .emailAddress,
                        contentType: .emailAddress
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        CustomTextField(
                            title: "Şifre (en az \(Constants.Validation.minPasswordLength) karakter)",
                            systemImage: "lock.fill",
                            text: $auth.password,
                            isSecure: true,
                            contentType: .newPassword
                        )
                        if !auth.password.isEmpty {
                            strengthBar
                        }
                    }

                    CustomTextField(
                        title: "Şifre tekrar",
                        systemImage: "lock.rotation",
                        text: $auth.confirmPassword,
                        isSecure: true,
                        contentType: .newPassword,
                        errorMessage: confirmError
                    )
                }

                Button {
                    hideKeyboard()
                    Task { await auth.register() }
                } label: {
                    Text("Kayıt Ol")
                }
                .buttonStyle(PrimaryButtonStyle(isLoading: auth.isWorking))
                .disabled(auth.isWorking)

                SignInWithAppleButton(.signUp) { request in
                    auth.configureAppleRequest(request)
                } onCompletion: { result in
                    Task { await auth.handleAppleCompletion(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: Constants.Layout.fieldHeight)
                .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous))
                .disabled(auth.isWorking)
            }
            .padding(.horizontal, Constants.Layout.screenPadding)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .authAlerts()
    }

    private var strengthBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < auth.passwordStrength ? strengthColor : Color.ftCardElevated)
                        .frame(height: 4)
                }
            }
            Text("Şifre gücü: \(strengthText)")
                .font(.caption)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .animation(.easeInOut(duration: 0.25), value: auth.passwordStrength)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Şifre gücü")
        .accessibilityValue(strengthText)
    }
}
