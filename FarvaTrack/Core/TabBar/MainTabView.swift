import SwiftUI

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = AppRouter()
    @State private var waterViewModel = WaterViewModel()
    @State private var wasteViewModel = BiologicalWasteViewModel()

    init() {
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
        .environment(wasteViewModel)
        .tint(Color.ftAccentLight)
        .sensoryFeedback(.selection, trigger: router.selectedTab)
        .onOpenURL { router.handle($0) }
        .onReceive(NotificationCenter.default.publisher(for: .farvaDeepLink)) { notification in
            if let url = notification.object as? URL { router.handle(url) }
        }
        .onChange(of: auth.currentUser, initial: true) { _, user in
            if let user {
                waterViewModel.configure(context: modelContext, user: user)
                wasteViewModel.configure(context: modelContext, user: user)
            }
        }
        .task {
            // Uygulama kapalıyken gelen bildirime dokunulduysa, açılışta yönlendir.
            if let url = DeepLinkCenter.consumePending() { router.handle(url) }
        }
        .task(id: auth.currentUser?.id) {
            if let user = auth.currentUser {
                waterViewModel.configure(context: modelContext, user: user)
                wasteViewModel.configure(context: modelContext, user: user)
            }
            await waterViewModel.handleForeground()
            await wasteViewModel.handleForeground()
            if let userID = auth.currentUser?.id {
                await LibrarySyncService.shared.sync(context: modelContext, userID: userID)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await waterViewModel.handleForeground()
                    await wasteViewModel.handleForeground()
                    if let userID = auth.currentUser?.id {
                        await LibrarySyncService.shared.sync(context: modelContext, userID: userID)
                    }
                }
            }
        }
    }
}