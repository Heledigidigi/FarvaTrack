import SwiftUI

/// Sohbet sekmesinin kökü: her zaman sohbet listesi (karşılıklı sohbet + kendime notlar).
/// Bir konuşma açılınca sekme çubuğu gizlenir; geri dönünce yeniden görünür.
struct ChatView: View {
    @Environment(ChatHub.self) private var hub
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    /// Baloncuk stilleri (8F): hazırlar, kendi tasarımlarım, karşı taraftan indirilenler. İki odada ortak.
    @State private var bubbleStore = BubbleStyleStore()
    @State private var showBubbles = false
    @State private var showPersonalSetup = false
    @State private var path: [ChatRoomKind] = []

    var body: some View {
        NavigationStack(path: $path) {
            ChatRoomListView(onOpenPersonalSetup: { showPersonalSetup = true })
                .navigationTitle("Sohbetler")
                .navigationBarTitleDisplayMode(.inline)
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationDestination(for: ChatRoomKind.self) { kind in
                ChatRoomContent(showBubbles: $showBubbles)
                    .environment(hub.viewModel(for: kind))
            }
            .sheet(isPresented: $showBubbles) {
                BubblePickerView(store: bubbleStore)
            }
            .sheet(isPresented: $showPersonalSetup) {
                ChatPersonalSetupSheet()
                    .environment(hub.personal)
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
        .onChange(of: hub.pendingOpen, initial: true) { _, kind in
            guard let kind else { return }
            path = [kind]
            hub.pendingOpen = nil
        }
        .onChange(of: hub.partner.phase) { updateOpenConversation() }
        .onChange(of: hub.personal.phase) { _, phase in
            // Not sohbeti açıldı: kurulum kapanır ve doğrudan nota geçilir.
            if phase == .ready, showPersonalSetup {
                showPersonalSetup = false
                path = [.personal]
            }
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
                Image(systemName: banner.kind == .personal ? "note.text" : "bubble.left.fill")
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

/// Bir odanın ekranı: yükleniyor / eşleşme (ya da not sohbeti kurulumu) / konuşma.
struct ChatRoomContent: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Binding var showBubbles: Bool

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            switch viewModel.phase {
            case .idle, .loading:
                ProgressView("Sohbet yükleniyor…")
                    .tint(Color.ftAccentLight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unpaired:
                ChatPairingView(purpose: viewModel.kind)
            case .ready:
                ChatConversationView()
            }
        }
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // Açık konuşmada (ve sticker panelinde) alttaki sekmeler gizlenir; geri dönünce görünür.
        .toolbar(viewModel.phase == .ready ? .hidden : .visible, for: .tabBar)
        .toolbar {
            if viewModel.phase == .ready, viewModel.kind == .partner {
                ToolbarItem(placement: .primaryAction) {
                    Button { CallLauncher.call(viewModel) } label: { Image(systemName: "phone.fill") }
                        .accessibilityLabel("Sesli ara")
                        .accessibilityHint("\(viewModel.partnerName) adlı kişiyi sesli arar")
                        .disabled(CallManager.shared.phase.isActive)
                }
            }
            if viewModel.phase == .ready {
                ToolbarItem(placement: .primaryAction) {
                    Button { showBubbles = true } label: { Image(systemName: "paintpalette") }
                        .accessibilityLabel("Baloncuk seç")
                        .accessibilityHint("Mesaj baloncuğunun görünümünü değiştir ya da kendi baloncuğunu tasarla")
                }
            }
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

// MARK: - Sohbet listesi

/// Not sohbeti açıldıktan sonra sekmenin kökü.
struct ChatRoomListView: View {
    @Environment(ChatHub.self) private var hub
    var onOpenPersonalSetup: () -> Void = {}

    var body: some View {
        List {
            NavigationLink(value: ChatRoomKind.partner) {
                ChatRoomRow(viewModel: hub.partner)
            }
            .listRowBackground(Color.ftCard)

            if hub.personal.phase == .ready {
                NavigationLink(value: ChatRoomKind.personal) {
                    ChatRoomRow(viewModel: hub.personal)
                }
                .listRowBackground(Color.ftCard)
            } else {
                // Not sohbeti henüz yok: kendi kodunu kendine yapıştırarak açılır.
                Button(action: onOpenPersonalSetup) {
                    ChatRoomRow(viewModel: hub.personal)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.ftCard)
                .accessibilityHint("Kendine not sohbeti açar")
            }
        }
        .scrollContentBackground(.hidden)
    }
}

struct ChatRoomRow: View {
    let viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(viewModel.kind == .personal ? Color.ftCardElevated : Color.ftAccent, in: Circle())
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
        .accessibilityHint(viewModel.unreadCount > 0 ? "\(viewModel.unreadCount) okunmamış mesaj" : "")
    }

    private var icon: String {
        viewModel.kind == .personal ? "note.text" : (viewModel.phase == .ready ? "person.2.fill" : "person.badge.plus")
    }

    private var title: String {
        switch (viewModel.kind, viewModel.phase) {
        case (.personal, .ready): return viewModel.partnerName
        case (.personal, _): return "Kendime not"
        case (.partner, .ready): return viewModel.partnerName
        case (.partner, .unpaired): return "Sohbet arkadaşını ekle"
        default: return "Sohbet"
        }
    }

    private var subtitle: String {
        if let last = viewModel.messages.last {
            let prefix = last.isMine && viewModel.kind == .partner ? "Sen: " : ""
            return prefix + last.displayText
        }
        switch (viewModel.kind, viewModel.phase) {
        case (.personal, .ready): return "Kendine not al"
        case (.personal, _): return "Kendine not sohbeti aç"
        case (.partner, .unpaired): return "Davet kodu oluştur ya da gir"
        default: return "Henüz mesaj yok"
        }
    }
}

// MARK: - Not sohbeti kurulumu

/// Kendi davet kodunu oluşturup yine kendine yapıştırarak not sohbeti açılır.
struct ChatPersonalSetupSheet: View {
    @Environment(ChatViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ChatPairingView(purpose: .personal)
                .background(Color.ftBackground.ignoresSafeArea())
                .navigationTitle("Kendime not")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Kapat") { dismiss() }
                    }
                }
                .alert("Bir sorun oluştu", isPresented: $viewModel.hasError) {
                    Button("Tamam", role: .cancel) {}
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
        }
    }
}

// MARK: - Eşleşme

struct ChatPairingView: View {
    @Environment(ChatViewModel.self) private var viewModel
    /// Karşılıklı eşleşme ya da kendine not sohbeti kurulumu (aynı akış: kendi kodunu kendine yapıştırırsın).
    var purpose: ChatRoomKind = .partner
    @FocusState private var codeFocused: Bool
    @State private var copied = false

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: purpose == .personal ? "note.text" : "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.ftAccentLight)
                        .accessibilityHidden(true)
                    Text(purpose == .personal ? "Kendine not sohbeti" : "Özel sohbetini başlat")
                        .font(.title2.bold())
                    Text(purpose == .personal
                         ? "Kendine yazdığın, karşılıklı sohbetle tıpatıp aynı çalışan bir sohbet: fotoğraf, ses, sticker ve baloncuklar dahil. Bir davet kodu oluştur, kopyala ve aşağıdaki alana kendin yapıştır."
                         : "Sohbet yalnızca iki kişi arasındadır. Biriniz davet kodu oluşturur, diğeriniz bu kodu girer; sohbeti yalnızca siz ikiniz görebilirsiniz. Kendi kodunu kendin girersen kendine not sohbeti açılır.")
                        .font(.subheadline)
                        .foregroundStyle(Color.ftTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                inviteCard
                redeemCard(code: $viewModel.inviteCodeInput)
            }
            .padding(Constants.Layout.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Davet kodu oluştur", systemImage: "qrcode")
                .font(.headline)

            if let invite = viewModel.invite {
                Text(invite.code)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .kerning(6)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
                    .accessibilityLabel("Davet kodun: \(invite.code.map(String.init).joined(separator: " "))")

                Text(purpose == .personal
                     ? "Kodu kopyala ve aşağıdaki alana yapıştır."
                     : "Kod \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened)) tarihine kadar geçerli. Karşı taraf kodu girince sohbet kendiliğinden açılır.")
                    .font(.footnote)
                    .foregroundStyle(Color.ftTextSecondary)

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = invite.code
                        copied = true
                        Haptics.success()
                    } label: {
                        Label(copied ? "Kopyalandı" : "Kopyala", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Davet kodunu panoya kopyalar")

                    ShareLink(item: "FarvaTrack sohbet davet kodum: \(invite.code)") {
                        Label("Paylaş", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .tint(Color.ftAccentLight)

                if purpose == .partner {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Eşleşme bekleniyor…")
                            .font(.footnote)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                Text(purpose == .personal
                     ? "Önce kendine bir kod oluştur. Kod yalnızca bir kez kullanılabilir."
                     : "Kodu sohbet edeceğin kişiye gönder. Kod 24 saat geçerlidir ve yalnızca bir kez kullanılabilir.")
                    .font(.footnote)
                    .foregroundStyle(Color.ftTextSecondary)
                Button("Kod oluştur") {
                    Haptics.impact(.light)
                    Task { await viewModel.createInvite() }
                }
                .buttonStyle(PrimaryButtonStyle(isLoading: viewModel.isWorking))
                .disabled(viewModel.isWorking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func redeemCard(code: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(purpose == .personal ? "Kodu buraya yapıştır" : "Kodun var mı?", systemImage: "key.fill")
                .font(.headline)

            TextField("Örn. K7P2QX", text: code)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFocused)
                .padding(.horizontal, 14)
                .frame(height: Constants.Layout.fieldHeight)
                .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .submitLabel(.join)
                .onSubmit(redeem)
                .accessibilityLabel("Davet kodu")
                .accessibilityHint(purpose == .personal
                                   ? "Oluşturduğun \(ChatInviteCode.length) karakterlik kodu yapıştır"
                                   : "Karşı tarafın gönderdiği \(ChatInviteCode.length) karakterlik kodu yaz")

            Button {
                if let pasted = UIPasteboard.general.string {
                    code.wrappedValue = ChatInviteCode.normalize(pasted)
                    Haptics.selection()
                }
            } label: {
                Label("Panodan yapıştır", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .tint(Color.ftAccentLight)

            Button(purpose == .personal ? "Not sohbetini aç" : "Eşleş", action: redeem)
                .buttonStyle(PrimaryButtonStyle(isLoading: viewModel.isWorking))
                .disabled(viewModel.isWorking || code.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func redeem() {
        codeFocused = false
        Task {
            if await viewModel.redeemInvite() {
                Haptics.success()
            } else {
                Haptics.error()
            }
        }
    }
}
