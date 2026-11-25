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
    /// Her arkadaşla ayrı oda ve kendine not sohbeti.
    @State private var chatHub = ChatHub()

    /// Görünüm teması; değişince sekme çubuğu yeni görünümle yeniden kurulur.
    @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.default.rawValue

    /// Sekme çubuğu görünümü: klasikte saydam (vintage zemin görünür), koyuda opak koyu.
    static func applyTabBarAppearance(_ theme: AppTheme) {
        let appearance = UITabBarAppearance()
        switch theme {
        case .klasik:
            appearance.configureWithTransparentBackground()
            let normal = UIColor(red: 0x8E / 255, green: 0x76 / 255, blue: 0x60 / 255, alpha: 1)
            for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
                item.normal.iconColor = normal
                item.normal.titleTextAttributes = [.foregroundColor: normal]
            }
        case .koyu:
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0x1A / 255, green: 0x1A / 255, blue: 0x21 / 255, alpha: 1)
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        @Bindable var router = router
        let theme = AppTheme.resolve(themeRaw)
        // Görünüm, yeni sekme çubuğu oluşturulmadan önce ayarlanmalı (aşağıdaki `.id`).
        let _ = Self.applyTabBarAppearance(theme)

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
                .badge(chatHub.unreadCount + chatHub.incomingRequestCount)

            ProfileView()
                .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage) }
                .tag(AppTab.profile)
        }
        .id(theme)
        .environment(router)
        .environment(waterViewModel)
        .environment(wasteViewModel)
        .environment(liveWorkout)
        .environment(chatHub)
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
        // Arkadaş odaları hazır olunca her birinden gelen aramalar dinlenir.
        .onChange(of: chatHub.callRooms, initial: true) { _, rooms in
            CallManager.shared.watch(rooms: rooms)
        }
        .overlay(alignment: .top) {
            if let banner = chatHub.banner {
                ChatBannerView(banner: banner) {
                    router.selectedTab = .chat
                    chatHub.open(banner.destination)
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
            // Liste henüz yüklenmediyse oda kimliğiyle açılır; sohbet ekranı oda gelince gösterir.
            chatHub.open(chatHub.destination(forChatID: chatID) ?? .room(chatID))
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
