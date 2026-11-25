import SwiftUI

struct ContentView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        ZStack {
            ThemeBackground().ignoresSafeArea()

            switch auth.authState {
            case .loading:
                SplashView()
                    .transition(.opacity)
            case .unauthenticated:
                LoginView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingView()
                    .transition(.opacity)
            case .authenticated:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.authState)
        .task { auth.start() }
    }
}

private struct SplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            AppLogo(size: 100)
            ProgressView().tint(Color.ftAccentLight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Yükleniyor")
    }
}

/// `GoogleService-Info.plist` pakette yoksa gösterilir.
struct FirebaseSetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    AppLogo(size: 90)
                    Spacer()
                }
                .padding(.top, 40)

                Text("Firebase yapılandırılmadı")
                    .font(.title2.bold())

                Text("Bu derlemede GoogleService-Info.plist dosyası yok. Giriş ve veri senkronizasyonu için dosyayı ekleyip uygulamayı yeniden derle.")
                    .foregroundStyle(Color.ftTextSecondary)

                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Firebase konsolunda iOS uygulaması ekle ve GoogleService-Info.plist dosyasını indir.")
                    step(2, "GitHub'da Settings → Secrets and variables → Actions bölümüne GOOGLE_SERVICE_INFO_PLIST adlı bir secret ekle; değer olarak dosyanın içeriğini yapıştır.")
                    step(3, "Yeni bir derleme başlat ve yeni IPA'yı kur.")
                }
                .cardStyle()
            }
            .padding(Constants.Layout.screenPadding)
        }
        .ftScreenBackground()
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.bold())
                .frame(width: 24, height: 24)
                .background(Color.ftAccent, in: Circle())
            Text(text)
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }
}
