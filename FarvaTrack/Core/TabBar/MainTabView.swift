import SwiftUI

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = AppRouter()
    /// Su modülü hem sekmede hem widget içe aktarımında kullanıldığından burada yaşar.
    @State private var waterViewModel = WaterViewModel()
    /// Biyolojik atık sayacı da widget'tan beslendiği için burada yaşar.
    @State private var wasteViewModel = WasteViewModel()
    /// Özel yiyecek/egzersiz ve favorilerin cihazlar arası eşitlenmesi.
    @State private var librarySync = LibrarySynchronizer()
    /// Salonda yarım kalan antrenman sekmeler arası ve uygulama yeniden açılınca korunur.
    @State private var liveWorkout = LiveWorkoutViewModel()
    /// Sohbet dinleyicileri sekmeler arasında açık kalsın (okunmamış rozeti, bekleyen gönderimler).
    /// İki oda: karşılıklı sohbet ve kendine not sohbeti.
    @State private var chatHub = ChatHub()

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

            ChatView()
                .tabItem { Label(AppTab.chat.title, systemImage: AppTab.chat.systemImage) }
                .tag(AppTab.chat)
                .badge(chatHub.unreadCount)

            ProfileView()
                .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage) }
                .tag(AppTab.profile)
        }
        .environment(router)
        .environment(waterViewModel)
        .environment(wasteViewModel)
        .environment(liveWorkout)
        .environment(chatHub)
        .environment(chatHub.partner)
        .environment(CallManager.shared)
        // Sesli arama (8H): uygulama içi arama ekranı.
        .fullScreenCover(isPresented: Binding(get: { CallManager.shared.isPresenting }, set: { _ in })) {
            CallView()
                .environment(CallManager.shared)
                .preferredColorScheme(.dark)
        }
        .alert("Arama", isPresented: Binding(get: { CallManager.shared.errorMessage != nil && !CallManager.shared.isPresenting },
                                             set: { if !$0 { CallManager.shared.errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(CallManager.shared.errorMessage ?? "")
        }
        // Karşılıklı sohbet odası hazır olunca gelen aramalar dinlenir.
        .onChange(of: chatHub.partner.room?.id, initial: true) { _, chatID in
            CallManager.shared.watch(chatID: chatID, partnerName: chatHub.partner.partnerName)
        }
        .overlay(alignment: .top) {
            if let banner = chatHub.banner {
                ChatBannerView(banner: banner) {
                    router.selectedTab = .chat
                    chatHub.open(banner.kind)
                } onDismiss: {
                    chatHub.banner = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(banner.id)
            }
        }
        .animation(.spring(duration: 0.35), value: chatHub.banner)
        // Uygulama simgesindeki rozet: okunmamış sohbet mesajları.
        .onChange(of: chatHub.unreadCount, initial: true) { _, count in
            PushManager.shared.setBadge(count)
        }
        // Push bildirimine dokunuldu: ilgili sohbeti aç.
        .onChange(of: PushManager.shared.pendingChatID, initial: true) { _, chatID in
            guard let chatID else { return }
            router.selectedTab = .chat
            chatHub.open(chatHub.kind(forChatID: chatID) ?? .partner)
            PushManager.shared.pendingChatID = nil
        }
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
            if let user {
                waterViewModel.configure(context: modelContext, user: user)
                wasteViewModel.configure(context: modelContext, user: user)
                liveWorkout.configure(userID: user.id)
                chatHub.configure(context: modelContext, user: user)
                Task { await PushManager.shared.start(userID: user.id) }
            } else {
                chatHub.reset()
                CallManager.shared.stop()
                Task { await PushManager.shared.stop() }
            }
        }
        .task(id: auth.currentUser?.id) {
            if let user = auth.currentUser {
                waterViewModel.configure(context: modelContext, user: user)
                wasteViewModel.configure(context: modelContext, user: user)
                await waterViewModel.handleForeground()
                await wasteViewModel.handleForeground()
                await librarySync.syncAll(context: modelContext, userID: user.id)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Arka plandayken gelen mesajlar okundu sayılmaz.
            chatHub.isAppActive = phase == .active
            guard phase == .active, let userID = auth.currentUser?.id else { return }
            Task {
                await chatHub.handleForeground()
                await waterViewModel.handleForeground()
                await wasteViewModel.handleForeground()
                await librarySync.syncAll(context: modelContext, userID: userID)
            }
        }
    }
}
