import SwiftUI

/// Sohbet sekmesinin kökü: kendime not + arkadaşlarla sohbetler. Sağ üstteki düğmeyle arkadaş eklenir.
/// Bir konuşma açılınca sekme çubuğu gizlenir; geri dönünce yeniden görünür.
struct ChatView: View {
    @Environment(ChatHub.self) private var hub
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    /// Baloncuk stilleri (8F): hazırlar, kendi tasarımlarım, karşı taraftan indirilenler. Tüm odalarda ortak.
    @State private var bubbleStore = BubbleStyleStore()
    @State private var showBubbles = false
    @State private var showAddFriend = false
    @State private var path: [ChatDestination] = []

    var body: some View {
        @Bindable var hub = hub

        NavigationStack(path: $path) {
            ChatRoomListView(
                onOpenPersonal: openPersonal,
                onAddFriend: { showAddFriend = true }
            )
            .navigationTitle("Sohbetler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.impact(.light)
                        showAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .overlay(alignment: .topTrailing) {
                                if hub.incomingRequestCount > 0 {
                                    Text("\(hub.incomingRequestCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Color.ftAccent, in: Capsule())
                                        .offset(x: 10, y: -8)
                                }
                            }
                    }
                    .accessibilityLabel("Arkadaş ekle")
                    .accessibilityValue(hub.incomingRequestCount > 0 ? "\(hub.incomingRequestCount) arkadaşlık isteği" : "")
                }
            }
            .ftScreenBackground()
            .navigationDestination(for: ChatDestination.self) { destination in
                if let model = hub.viewModel(for: destination) {
                    ChatRoomContent(showBubbles: $showBubbles)
                        .environment(model)
                } else {
                    ProgressView("Sohbet yükleniyor…")
                        .tint(Color.ftAccentLight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ftScreenBackground()
                }
            }
            .sheet(isPresented: $showBubbles) {
                BubblePickerView(store: bubbleStore)
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView(friends: hub.friends) { chatID in
                    // Kabul edilen istekten açılan sohbete geçilir.
                    showAddFriend = false
                    path = [.room(chatID)]
                }
            }
            .alert("Bir sorun oluştu", isPresented: Binding(get: { hub.errorMessage != nil }, set: { if !$0 { hub.errorMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(hub.errorMessage ?? "")
            }
        }
        .environment(bubbleStore)
        .task(id: auth.currentUser?.id) {
            guard let userID = auth.currentUser?.id else { return }
            bubbleStore.configure(context: modelContext, userID: userID)
            await bubbleStore.syncAll()
        }
        .onAppear {
            hub.isTabVisible = true
            updateOpenConversation()
        }
        .onDisappear { hub.isTabVisible = false }
        .onChange(of: path) { updateOpenConversation() }
        // Bildirim ya da uygulama içi şeritten gelen "şu sohbeti aç" isteği.
        .onChange(of: hub.pendingOpen, initial: true) { _, destination in
            guard let destination else { return }
            path = [destination]
            hub.pendingOpen = nil
        }
        .onChange(of: hub.personal.phase) { _, phase in
            if phase != .ready { path.removeAll { $0 == .personal } }
            updateOpenConversation()
        }
        .task {
            // "Yazıyor…" ve düzenleme süresi gibi zamana bağlı bilgileri tazeler.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                hub.tick()
            }
        }
    }

    /// Not sohbeti yoksa tek dokunuşla açılır ve hemen geçilir.
    private func openPersonal() {
        if hub.personal.phase == .ready {
            path = [.personal]
            return
        }
        Task {
            if await hub.createPersonalRoom() {
                Haptics.success()
                path = [.personal]
            }
        }
    }

    /// Yalnızca ekrandaki konuşmanın mesajları okundu sayılır.
    private func updateOpenConversation() {
        hub.openConversation = path.last
    }
}

// MARK: - Uygulama içi bildirim şeridi

/// Uygulama açıkken gelen mesaj: üstte birkaç saniye görünür; dokununca sohbet açılır, yukarı kaydırınca kapanır.
struct ChatBannerView: View {
    let banner: ChatBanner
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: banner.destination == .personal ? "note.text" : "bubble.left.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.ftAccent, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title).font(.subheadline.bold()).lineLimit(1)
                    Text(banner.body).font(.subheadline).foregroundStyle(Color.ftTextSecondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .gesture(DragGesture(minimumDistance: 10).onEnded { value in
            if value.translation.height < -10 { onDismiss() }
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Yeni mesaj, \(banner.title): \(banner.body)")
        .accessibilityHint("Sohbeti açar")
        .task(id: banner.id) {
            Haptics.impact(.light)
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { onDismiss() }
        }
    }
}

// MARK: - Oda içeriği

/// Bir odanın ekranı: yükleniyor / oda yok / konuşma.
struct ChatRoomContent: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Binding var showBubbles: Bool
    @State private var showProfile = false
    /// Piksel Çayır'da çubuk renkleri gece/gündüz değişir; dakikada bir yenilenir.
    @State private var themeClock = Date.now
    /// Ekranda güneşin yeri (Tepedeki Kedi: baloncuk rengi güneşe uzaklığa göre).
    @State private var screenFrame: CGRect = .zero

    /// Odanın teması (iki tarafta aynı). Konuşma hazır değilken tema uygulanmaz.
    private var theme: ChatThemeChoice? {
        guard viewModel.phase == .ready, let theme = viewModel.theme, theme.id != .plain else { return nil }
        return theme
    }

    private var look: ChatThemeLook? { ChatThemeLook.look(for: theme, date: themeClock) }

    private var sunInfo: ChatThemeSunInfo? {
        guard theme?.id == .hillCat, screenFrame.width > 0 else { return nil }
        let sun = ChatThemeSun.sunPoint(in: screenFrame.size)
        return ChatThemeSunInfo(sun: CGPoint(x: screenFrame.minX + sun.x, y: screenFrame.minY + sun.y), screen: screenFrame.size)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            switch viewModel.phase {
            case .idle, .loading:
                ProgressView("Sohbet yükleniyor…")
                    .tint(Color.ftAccentLight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unpaired:
                // Oda kaldırıldı (ör. karşı taraf hesabını sildi).
                ContentUnavailableView("Sohbet bulunamadı", systemImage: "bubble.left.and.exclamationmark.bubble.right",
                                       description: Text("Bu sohbet artık mevcut değil."))
            case .ready:
                ChatConversationView()
            }
        }
        // Tema: sohbet duvar kâğıdının önünde; ince ayırıcı çizgi üst çubuğun hemen altında.
        .safeAreaInset(edge: .top, spacing: 0) { look?.separatorLine }
        .environment(\.chatThemeLook, look)
        .environment(\.chatThemeSun, sunInfo)
        .background {
            if let theme {
                ChatThemeWallpaper(choice: theme)
                    .ignoresSafeArea()
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { screenFrame = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { _, frame in screenFrame = frame }
                    }.ignoresSafeArea())
            }
        }
        .modifier(ThemeOrAppBackground(isThemed: theme != nil))
        .task(id: theme?.id) {
            guard theme?.id == .pixelMeadow else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                themeClock = .now
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // Geri düğmesinde yalnızca ok: "Sohbetler" yazısı gösterilmez (kaydırarak geri dönme korunur).
        .toolbarRole(.editor)
        // Üst çubuk (kişi adı ve geri oku) yazma alanıyla aynı zeminde; temada yarı saydam, duvar kâğıdı arkasından görünür.
        .toolbarBackground(look?.chrome.color ?? Color.ftChrome, for: .navigationBar)
        .toolbarBackground(viewModel.phase == .ready ? .visible : .automatic, for: .navigationBar)
        .toolbarColorScheme(look?.colorScheme, for: .navigationBar)
        .tint(look?.icon.color)
        // Açık konuşmada (ve sticker panelinde) alttaki sekmeler gizlenir; geri dönünce görünür.
        .toolbar(viewModel.phase == .ready ? .hidden : .visible, for: .tabBar)
        .toolbar {
            if viewModel.phase == .ready {
                // Ortadaki başlık boş: kişi solda, geri okunun yanında (WhatsApp gibi). Başlık metni
                // yine de geri düğmesi için `navigationTitle` olarak kalır.
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
                // Başlığa dokununca kişi profili (WhatsApp'taki gibi).
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: {
                        HStack(spacing: 8) {
                            if viewModel.kind == .partner {
                                PresenceAvatarView(name: viewModel.partnerName, photoURL: viewModel.partnerPhotoURL,
                                                   presence: viewModel.partnerPresence, size: 32)
                            } else if viewModel.partnerPhotoURL != nil {
                                AvatarView(name: viewModel.partnerName, photoURL: viewModel.partnerPhotoURL)
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "note.text")
                                    .font(.footnote)
                                    .frame(width: 32, height: 32)
                                    .background(Color.ftCardElevated, in: Circle())
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(viewModel.partnerName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                ChatPresenceSubtitle(viewModel: viewModel)
                            }
                        }
                        .foregroundStyle(look?.chromeText.color ?? Color.ftText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel([viewModel.partnerName, viewModel.partnerSubtitle].compactMap { $0 }.joined(separator: ", "))
                    .accessibilityHint("Kişi bilgisini, medyayı ve aramayı açar")
                    .accessibilityAddTraits(.isButton)
                }
            }
            if viewModel.phase == .ready, viewModel.kind == .partner {
                ToolbarItem(placement: .primaryAction) {
                    Button { CallLauncher.call(viewModel) } label: { Image(systemName: "phone.fill") }
                        .accessibilityLabel("Sesli ara")
                        .accessibilityHint("\(viewModel.partnerName) adlı kişiyi sesli arar")
                        .disabled(CallManager.shared.phase.isActive)
                }
            }
        }
        .navigationDestination(isPresented: $showProfile) {
            ChatContactProfileView(
                viewModel: viewModel,
                showBubbles: $showBubbles,
                onJump: { messageID in
                    viewModel.pendingJumpMessageID = messageID
                    showProfile = false
                },
                onFind: {
                    // WhatsApp gibi: konuşmaya dönülür, altta arama çubuğu açılır.
                    viewModel.beginFind()
                    showProfile = false
                }
            )
        }
        .alert("Bir sorun oluştu", isPresented: $viewModel.hasError) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var title: String {
        if viewModel.phase == .ready { return viewModel.partnerName }
        return viewModel.kind == .personal ? "Kendime not" : "Sohbet"
    }
}


/// Tema yoksa uygulamanın zemini (Klasik / Koyu).
private struct ThemeOrAppBackground: ViewModifier {
    let isThemed: Bool

    func body(content: Content) -> some View {
        if isThemed { content } else { content.ftScreenBackground() }
    }
}

// MARK: - Sohbet listesi

struct ChatRoomListView: View {
    @Environment(ChatHub.self) private var hub
    var onOpenPersonal: () -> Void = {}
    var onAddFriend: () -> Void = {}

    var body: some View {
        let rooms = hub.friendRooms
        let incoming = hub.friends.incoming

        List {
            if !incoming.isEmpty {
                Section("Arkadaşlık istekleri") {
                    ForEach(incoming) { request in
                        FriendRequestRow(request: request, friends: hub.friends)
                    }
                }
                .listRowBackground(Color.ftCard)
            }

            Section {
                Button(action: onOpenPersonal) {
                    ChatRoomRow(viewModel: hub.personal)
                        .overlay(alignment: .trailing) {
                            if hub.isCreatingPersonal { ProgressView().controlSize(.small) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityHint(hub.personal.phase == .ready ? "Kendine not sohbetini açar" : "Kendine not sohbeti oluşturur")

                ForEach(rooms, id: \.pinnedChatID) { model in
                    if let chatID = model.pinnedChatID {
                        NavigationLink(value: ChatDestination.room(chatID)) {
                            ChatRoomRow(viewModel: model)
                        }
                    }
                }
            }
            .listRowBackground(Color.ftCard)

            if rooms.isEmpty, hub.hasLoadedRooms {
                Section {
                    NoFriendsView(onAdd: onAddFriend)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .animation(.easeOut(duration: 0.25), value: rooms.map(\.pinnedChatID))
        .animation(.easeOut(duration: 0.25), value: incoming.map(\.id))
    }
}

/// Henüz arkadaş yokken: sağ üstteki düğmeyi gösteren küçük figür ve konuşma balonu.
/// (Maskotun asıl tasarımı sonra yapılacak; şimdilik yer tutucu bir kedi silüeti.)
struct NoFriendsView: View {
    var onAdd: () -> Void = {}
    @State private var bounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Sağ üste doğru kıvrılan ok.
            PointingArrow()
                .stroke(Color.ftAccentLight.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [6, 6]))
                .frame(width: 90, height: 70)
                .offset(y: bounce ? -4 : 2)
                .padding(.trailing, 18)
                .accessibilityHidden(true)

            HStack(alignment: .bottom, spacing: 10) {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Şu an hiç arkadaşın yok")
                        .font(.headline)
                    Text("İstersen buradan ekleyebilirsin!")
                        .font(.subheadline)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Yer tutucu maskot: parmağıyla (patisiyle) yukarıyı gösteren kedi.
                Image(systemName: "cat.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.ftAccentLight)
                    .rotationEffect(.degrees(bounce ? -6 : 4), anchor: .bottom)
                    .accessibilityHidden(true)
            }

            Button {
                Haptics.impact(.light)
                onAdd()
            } label: {
                Label("Arkadaş ekle", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Color.ftAccentLight)
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Şu an hiç arkadaşın yok. Sağ üstteki düğmeden arkadaş ekleyebilirsin.")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bounce = true }
        }
    }
}

/// Aşağıdan yukarı sağa kıvrılan ok (ucu sağ üstü gösterir).
private struct PointingArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX + 6, y: rect.maxY)
        let end = CGPoint(x: rect.maxX - 4, y: rect.minY + 4)
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: rect.minX + 10, y: rect.minY + 6))
        // Ok ucu.
        path.move(to: CGPoint(x: end.x - 14, y: end.y - 6))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - 10, y: end.y + 12))
        return path
    }
}

struct ChatRoomRow: View {
    let viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            if viewModel.phase == .ready, viewModel.kind == .partner {
                PresenceAvatarView(name: viewModel.partnerName, photoURL: viewModel.partnerPhotoURL,
                                   presence: viewModel.partnerPresence, size: 46)
                    .accessibilityHidden(true)
            } else if viewModel.phase == .ready, viewModel.partnerPhotoURL != nil {
                AvatarView(name: viewModel.partnerName, photoURL: viewModel.partnerPhotoURL)
                    .frame(width: 46, height: 46)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.ftCardElevated, in: Circle())
                            .overlay(Circle().strokeBorder(Color.ftBackground, lineWidth: 2))
                    }
                    .accessibilityHidden(true)
            } else {
                Image(systemName: viewModel.kind == .personal ? "note.text" : "person.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(viewModel.kind == .personal ? Color.ftCardElevated : Color.ftAccent, in: Circle())
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    if let date = viewModel.messages.last?.message.createdAt {
                        Text(date, format: Date.FormatStyle(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                }
                HStack {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.ftTextSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if viewModel.unreadCount > 0 {
                        Text("\(viewModel.unreadCount)")
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.ftAccent, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(viewModel.unreadCount > 0 ? "\(viewModel.unreadCount) okunmamış mesaj" : "")
    }

    private var title: String {
        if viewModel.kind == .personal, viewModel.phase != .ready { return "Kendime not" }
        return viewModel.partnerName
    }

    private var subtitle: String {
        if viewModel.isPartnerTyping { return "yazıyor…" }
        if let last = viewModel.messages.last {
            let prefix = last.isMine && viewModel.kind == .partner ? "Sen: " : ""
            return prefix + last.displayText
        }
        switch (viewModel.kind, viewModel.phase) {
        case (.personal, .ready): return "Kendine not al"
        case (.personal, _): return "Kendine not sohbeti aç"
        default: return "Henüz mesaj yok"
        }
    }
}

// MARK: - Başlık altı: yazıyor / çevrimiçi / son görülme

/// Sohbet başlığında adın altında: yeşil "çevrimiçi", gri "son görülme …", bordo "yazıyor…".
struct ChatPresenceSubtitle: View {
    let viewModel: ChatViewModel

    var body: some View {
        Group {
            if viewModel.isPartnerTyping {
                Text("yazıyor…").foregroundStyle(Color.ftAccentLight)
            } else if let text = viewModel.partnerPresence.text(now: viewModel.now) {
                Text(text).foregroundStyle(viewModel.partnerPresence.isOnline ? Color.ftOnline : Color.ftTextSecondary)
            } else {
                Text(viewModel.kind == .personal ? "kendine not" : "bilgi için dokun").foregroundStyle(Color.ftTextSecondary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: viewModel.partnerSubtitle)
    }
}

