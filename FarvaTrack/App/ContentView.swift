import SwiftUI

struct ContentView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        ZStack {
            Color.ftBackground.ignoresSafeArea()

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