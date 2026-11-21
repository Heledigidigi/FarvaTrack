import SwiftUI

struct MainTabView: View {
    @State private var router = AppRouter()

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
        .tint(Color.ftAccentLight)
        .sensoryFeedback(.selection, trigger: router.selectedTab)
        .onOpenURL { router.handle($0) }
    }
}
