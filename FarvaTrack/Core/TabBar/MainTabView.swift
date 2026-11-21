import SwiftUI

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = AppRouter()
    /// Su modülü hem sekmede hem widget içe aktarımında kullanıldığından burada yaşar.
    @State private var waterViewModel = WaterViewModel()

    init() {
        // Koyu, opak sekme çubuğu
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.ftCard)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem { Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.systemImage) }
                .tag(AppTab.dashboard)

            ExerciseListView()
                .tabItem { Label(AppTab.exercise.title, systemImage: AppTab.exercise.systemImage) }
                .tag(AppTab.exercise)

            NutritionView()
                .tabItem { Label(AppTab.nutrition.title, systemImage: AppTab.nutrition.systemImage) }
                .tag(AppTab.nutrition)

            WaterTrackingView()
                .tabItem { Label(AppTab.water.title, systemImage: AppTab.water.systemImage) }
                .tag(AppTab.water)

            ProfileView()
                .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage) }
                .tag(AppTab.profile)
        }
        .environment(router)
        .environment(waterViewModel)
        .tint(Color.ftAccentLight)
        .sensoryFeedback(.selection, trigger: router.selectedTab)
        .onOpenURL { router.handle($0) }
        .onReceive(NotificationCenter.default.publisher(for: .farvaDeepLink)) { _ in
            if let url = DeepLinkCenter.consumePending() { router.handle(url) }
        }
        .onAppear {
            // Uygulama bildirime dokunularak açıldıysa bekleyen bağlantı vardır.
            if let url = DeepLinkCenter.consumePending() { router.handle(url) }
        }
        .onChange(of: auth.currentUser, initial: true) { _, user in
            if let user { waterViewModel.configure(context: modelContext, user: user) }
        }
        .task(id: auth.currentUser?.id) {
            if let user = auth.currentUser {
                waterViewModel.configure(context: modelContext, user: user)
                await waterViewModel.handleForeground()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, auth.currentUser != nil else { return }
            Task { await waterViewModel.handleForeground() }
        }
    }
}
