import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        @Bindable var auth = auth

        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header

                    VStack(spacing: 16) {
                        CustomTextField(
                            title: "E-posta",
                            systemImage: "envelope.fill",
                            text: $auth.email,
                            keyboard: .emailAddress,
                            contentType: .emailAddress
                        )
                        CustomTextField(
                            title: "Şifre",
                            systemImage: "lock.fill",
                            text: $auth.password,
                            isSecure: true,
                            contentType: .password
                        )
                        HStack {
                            Spacer()
                            Button("Şifremi unuttum") {
                                Task { await auth.sendPasswordReset() }
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.ftAccentLight)
                        }
                    }

                    Button {
                        hideKeyboard()
                        Task { await auth.signIn() }
                    } label: {
                        Text("Giriş Yap")
                    }
                    .buttonStyle(PrimaryButtonStyle(isLoading: auth.isWorking))
                    .disabled(auth.isWorking)

                    orDivider

                    SignInWithAppleButton(.signIn) { request in
                        auth.configureAppleRequest(request)
                    } onCompletion: { result in
                        Task { await auth.handleAppleCompletion(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: Constants.Layout.fieldHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous))
                    .disabled(auth.isWorking)

                    NavigationLink {
                        RegisterView()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Hesabın yok mu?")
                                .foregroundStyle(Color.ftTextSecondary)
                            Text("Kayıt ol")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.ftAccentLight)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal, Constants.Layout.screenPadding)
                .padding(.vertical, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.ftBackground.ignoresSafeArea())
        }
        .authAlerts()
    }

    private var header: some View {
        VStack(spacing: 14) {
            AppLogo()
            Text("FarvaTrack")
                .font(.largeTitle.bold())
            Text("Sağlıklı yaşamın tek ekranda.")
                .font(.subheadline)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            Text("veya")
                .font(.footnote)
                .foregroundStyle(Color.ftTextSecondary)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Ortak uyarılar (Giriş, Kayıt, Onboarding)
struct AuthAlertsModifier: ViewModifier {
    @Environment(AuthViewModel.self) private var auth

    func body(content: Content) -> some View {
        @Bindable var auth = auth

        content
            .alert("Bir sorun oluştu", isPresented: $auth.hasError) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(auth.errorMessage ?? "")
            }
            .alert("Bilgi", isPresented: $auth.hasInfo) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(auth.infoMessage ?? "")
            }
    }
}

extension View {
    func authAlerts() -> some View {
        modifier(AuthAlertsModifier())
    }
}
