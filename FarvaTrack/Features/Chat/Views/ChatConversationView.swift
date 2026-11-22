import SwiftUI

/// Konuşma ekranı: mesaj listesi, "yazıyor…", arama ve yazma alanı.
struct ChatConversationView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @FocusState private var composerFocused: Bool
    @State private var highlightedID: String?
    @State private var confirmDelete: ChatMessageItem?
    @State private var showPicker = false
    @State private var showCamera = false
    /// Galeriden seçilenler; gönderim sayfası (Orijinal / Hızlı) bunlar için açılır.
    @State private var viewerItem: ChatMessageItem?
    @State private var showStickers = false
    /// Klavyenin yerini alan panel (sticker / galeri); klavye yüksekliğinde, animasyonsuz geçişle.
    @State private var panel: ChatInputPanel = .none
    @State private var galleryExpanded = false
    @State private var keyboard = ChatKeyboardObserver()
    /// Ev çubuğu payı (klavye kapalıyken alt güvenli alan).
    @State private var homeInset: CGFloat = 0
    /// Sola kaydırınca saatler (Instagram gibi).
    @State private var timeReveal: CGFloat = 0
    /// Uzun bas → Bilgi.
    @State private var infoItem: ChatMessageItem?
    @FocusState private var findFocused: Bool
    @State private var stickerLibrary = StickerLibraryViewModel()
    @State private var recentIDs: [String] = []
    @State private var placementDraft: PlacementDraft?
    @State private var placementLive = PlacementLiveGesture()
    @State private var metrics = ChatScrollMetrics()
    @State private var toast: String?
    @Environment(AuthViewModel.self) private var auth
    @Environment(BubbleStyleStore.self) private var bubbleStore
    @Environment(\.modelContext) private var modelContext
    /// Sesli mesaj kaydı ve oynatma (8C).
    @State private var recorder = ChatVoiceRecorderModel()
    @State private var audioPlayer = ChatAudioPlayer()

    private static let bottomID = "chat-bottom"

    var body: some View {
        GeometryReader { root in
            conversation(bottomInset: root.safeAreaInsets.bottom, fullHeight: root.size.height + root.safeAreaInsets.top + root.safeAreaInsets.bottom, topInset: root.safeAreaInsets.top)
        }
    }

    /// `bottomInset`: o anki alt güvenli alan (klavye açıkken klavye, kapalıyken ev çubuğu). Panel boşluğu bununla
    /// aynı yerleşim adımında hesaplanır; bu yüzden klavye ↔ panel geçişinde yazma alanı hiç kıpırdamaz.
    @ViewBuilder
    private func conversation(bottomInset: CGFloat, fullHeight: CGFloat, topInset: CGFloat) -> some View {
        @Bindable var viewModel = viewModel

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if viewModel.hasMoreOlder {
                        olderLoader(proxy: proxy)
                    }

                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, item in
                        if showsDayHeader(at: index) {
                            ChatDayHeader(date: item.message.createdAt)
                        }
                        bubble(for: item, proxy: proxy)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: MessageFramePreference.self,
                                        value: [item.id: geometry.frame(in: .named(ChatCoordinateSpace.content))]
                                    )
                                }
                            )
                            // Sola kaydırınca tüm baloncuklar kayar, sağda gönderim saatleri belirir.
                            .offset(x: timeReveal)
                            .overlay(alignment: .bottomTrailing) {
                                if timeReveal < 0 {
                                    ChatRevealedTime(date: item.message.createdAt, offset: timeReveal)
                                        .padding(.bottom, item.reactionSummary.isEmpty ? 6 : 18)
                                }
                            }
                            .id(item.id)
                    }

                    if viewModel.isPartnerTyping {
                        ChatTypingIndicator(name: viewModel.partnerName)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .animation(.easeOut(duration: 0.2), value: viewModel.isPartnerTyping)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: ChatContentOffsetPreference.self,
                                               value: geometry.frame(in: .named(ChatCoordinateSpace.viewport)).minY)
                    }
                )
                .background(
                    ChatHorizontalPanAttacher(
                        isEnabled: placementDraft == nil,
                        onChanged: { translation in timeReveal = ChatTimeReveal.offset(forTranslation: translation) },
                        onEnded: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { timeReveal = 0 }
                        }
                    )
                )
                .coordinateSpace(name: ChatCoordinateSpace.content)
                // Panelden sürüklenen sticker: bırakılan nokta doğrudan içerik koordinatındadır (kaydırma hesabı gerekmez).
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, location in
                    handleStickerDrop(items, at: location)
                } isTargeted: { targeted in
                    if targeted { Haptics.selection() }
                }
                // Yerleştirmeler içerikle birlikte kayar; konum bağlı mesajın çerçevesinden hesaplanır.
                .overlayPreferenceValue(MessageFramePreference.self) { frames in
                    GeometryReader { geometry in
                        ZStack {
                            ChatPlacementLayer(
                                placements: viewModel.placements,
                                frames: frames,
                                containerWidth: geometry.size.width,
                                hiddenID: placementDraft?.editingID,
                                onLoad: { _ = await viewModel.loadPlacementImage($0) },
                                onMove: { item, center in startMoving(item, center: center) },
                                onReorder: { item, front in
                                    viewModel.reorderPlacement(item.id, toFront: front)
                                    Haptics.selection()
                                },
                                onDelete: { item in
                                    viewModel.deletePlacement(item.id)
                                    Haptics.impact(.medium)
                                },
                                onSaveToLibrary: { item in savePlacementToLibrary(item) },
                                partnerName: viewModel.partnerName
                            )
                            PlacementDraftView(draft: placementDraft, live: placementLive, containerWidth: geometry.size.width)
                        }
                        .onAppear { metrics.contentWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in metrics.contentWidth = width }
                    }
                }
                .onPreferenceChange(MessageFramePreference.self) { metrics.frames = $0 }
                .onPreferenceChange(ChatContentOffsetPreference.self) { metrics.contentMinY = $0 }
            }
            .coordinateSpace(name: ChatCoordinateSpace.viewport)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { metrics.viewportSize = geometry.size }
                        .onChange(of: geometry.size) { _, size in metrics.viewportSize = size }
                }
            )
            .scrollDisabled(placementDraft != nil)
            // Taslak varken tüm görünen sohbet alanı hareketleri alır (sticker'a dokunmak gerekmez).
            .overlay {
                if placementDraft != nil {
                    PlacementGestureLayer(draft: $placementDraft, live: $placementLive)
                }
            }
            .onChange(of: placementDraft == nil) { _, _ in placementLive = PlacementLiveGesture() }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.last?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            // Profil sayfasındaki aramadan / medyadan seçilen mesaja git (profil kapanınca).
            .onChange(of: viewModel.pendingJumpMessageID) { _, id in
                guard let id else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    viewModel.pendingJumpMessageID = nil
                    jump(to: id, proxy: proxy)
                }
            }
            // Panel açıkken listeye dokununca panel kapanır (klavyedeki gibi).
            .simultaneousGesture(TapGesture().onEnded {
                if panel != .none, !galleryExpanded { closePanel() }
            })
            .safeAreaInset(edge: .bottom) {
                if placementDraft != nil {
                    placementBar
                } else if viewModel.isFinding {
                    ChatFindBar(
                        viewModel: viewModel,
                        focused: $findFocused,
                        onOlder: { _ = viewModel.findOlder() },
                        onNewer: { _ = viewModel.findNewer() },
                        onDone: endFind
                    )
                } else {
                    VStack(spacing: 0) {
                        ChatComposer(
                            viewModel: viewModel,
                            focused: $composerFocused,
                            activePanel: panel,
                            onGallery: { togglePanel(.gallery) },
                            onCamera: { showCamera = true },
                            onStickers: { togglePanel(.stickers) },
                            recorder: recorder,
                            onVoice: { viewModel.sendVoice($0) }
                        )
                        // Panelin kapladığı yer: klavye açıkken 0, kapalıyken klavye yüksekliği − ev çubuğu.
                        Color.clear.frame(height: ChatPanelLayout.spacer(panel: panel, keyboardHeight: keyboard.height,
                                                                         bottomInset: bottomInset))
                    }
                }
            }
            // Find modu: klavye açılır, sorgu değişince en yeni eşleşmeye gidilir.
            .onChange(of: viewModel.isFinding) { _, finding in
                if finding {
                    setPanel(.none)
                    composerFocused = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        findFocused = true
                    }
                } else {
                    highlightedID = nil
                }
            }
            .onChange(of: viewModel.find.current) { _, id in
                guard let id else {
                    highlightedID = nil
                    return
                }
                focusFound(id, proxy: proxy)
            }
        }
        // Panel ekranın altından klavye yüksekliğinde; klavye açılınca onun arkasında kalır.
        .overlay(alignment: .bottom) {
            if panel != .none, placementDraft == nil, !viewModel.isFinding {
                panelView(bottomInset: homeInset, fullHeight: fullHeight, topInset: topInset)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .ignoresSafeArea(.keyboard)
            }
        }
        .onChange(of: bottomInset, initial: true) { _, inset in
            if !keyboard.isVisible, inset < 120 { homeInset = inset }
        }
        .onAppear {
            keyboard.start()
            keyboard.onDidShow = {
                // Klavye panelin üstüne tamamen geldi: panel sessizce kaldırılır (yerleşim değişmez).
                if panel != .none { setPanel(.none) }
                galleryExpanded = false
            }
        }
        .onDisappear { keyboard.stop() }
        .sheet(isPresented: $showPicker) {
            // Seçilenler doğrudan gider; kalite Ayarlar → Sohbet → Veri tasarrufu'ndan.
            ChatMediaPicker { items in
                guard !items.isEmpty else { return }
                let quality = ChatMediaPreferences.sendQuality(.standard)
                Task { await viewModel.sendMedia(items, quality: quality) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            ChatCameraView(stickers: stickerLibrary.stickers) { media in
                let quality = ChatMediaPreferences.sendQuality(.standard)
                Task { await viewModel.sendMedia([media], quality: quality) }
            }
        }
        .onAppear { viewModel.outgoingBubble = bubbleStore.selectedRef }
        .onChange(of: bubbleStore.selectedRef) { _, ref in viewModel.outgoingBubble = ref }
        .sheet(isPresented: $showStickers, onDismiss: { stickerLibrary.reload() }) {
            StickerLibraryView(library: stickerLibrary)
        }
        .task(id: auth.currentUser?.id) {
            guard let userID = auth.currentUser?.id else { return }
            stickerLibrary.configure(context: modelContext, userID: userID)
            recentIDs = StickerRecents(defaults: .standard, userID: userID).ids
            await stickerLibrary.syncAll()
        }
        .overlay(alignment: .top) {
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.ftCardElevated, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { self.toast = nil }
                    }
            }
        }
        .fullScreenCover(item: $viewerItem) { item in
            ChatMediaViewer(item: item, viewModel: viewModel, stickers: stickerLibrary.stickers)
        }
        .sheet(item: $infoItem) { item in
            ChatMessageInfoSheet(item: item, info: viewModel.info(for: item), partnerName: viewModel.partnerName)
        }
        .overlay(alignment: .top) {
            if viewModel.isPreparingMedia {
                Label("Medya hazırlanıyor…", systemImage: "hourglass")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.ftCardElevated, in: Capsule())
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .onAppear {
            audioPlayer.onStartedPlaying = { [weak vm = viewModel] id in vm?.markListened(id) }
            recorder.onAutoFinish = { [weak vm = viewModel] voice in vm?.sendVoice(voice) }
        }
        .onDisappear {
            // Sohbetten çıkınca çalma durur, yarım kayıt silinir.
            audioPlayer.stop()
            recorder.cancel()
        }
        .onChange(of: recorder.hint) { _, hint in
            guard let hint else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                if recorder.hint == hint { recorder.hint = nil }
            }
        }
        .overlay(alignment: .bottom) {
            if let hint = recorder.hint {
                Text(hint)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.ftCardElevated, in: Capsule())
                    .padding(.bottom, 90)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .alert("Sesli mesaj", isPresented: Binding(get: { audioPlayer.errorMessage != nil }, set: { if !$0 { audioPlayer.errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(audioPlayer.errorMessage ?? "")
        }
        .confirmationDialog(
            "Mesaj herkesten silinsin mi?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible,
            presenting: confirmDelete
        ) { item in
            Button("Herkesten sil", role: .destructive) {
                viewModel.deleteForEveryone(item)
                Haptics.impact(.medium)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { _ in
            Text("Mesaj iki taraftan da kaldırılır, yerinde \"Bu mesaj silindi\" yazar.")
        }
    }

    // MARK: Parçalar

    private func olderLoader(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            if viewModel.isLoadingOlder {
                ProgressView().controlSize(.small)
            }
            Text(viewModel.isLoadingOlder ? "Eski mesajlar yükleniyor…" : "Daha eski mesajlar")
                .font(.caption)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear {
            // Yüklemeden sonra kaydırma konumu korunur: önceki en eski mesaj yerinde kalır.
            let anchor = viewModel.messages.first?.id
            Task {
                await viewModel.loadOlder()
                if let anchor { proxy.scrollTo(anchor, anchor: .top) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bubble(for item: ChatMessageItem, proxy: ScrollViewProxy) -> some View {
        // Gönderenin baloncuk stili; karşı tarafınki gerekirse indirilir (önbellek sürümü eskiyse yenisi).
        _ = bubbleStore.revision
        let sender = item.message.senderID
        let style = bubbleStore.style(for: item.message.bubble, ownerID: sender)
        let owner = style?.isPreset == true ? "preset" : sender
        return ChatBubbleView(
            item: item,
            currentUserID: viewModel.userID ?? "",
            partnerName: viewModel.partnerName,
            isHighlighted: highlightedID == item.id,
            onReply: {
                viewModel.beginReply(to: item)
                composerFocused = true
                Haptics.selection()
            },
            onReact: { emoji in
                viewModel.toggleReaction(emoji, on: item)
                Haptics.impact(.light)
            },
            onCopy: {
                if let text = viewModel.copyText(for: item) {
                    UIPasteboard.general.string = text
                    Haptics.success()
                }
            },
            onEdit: {
                viewModel.beginEdit(item)
                composerFocused = true
            },
            onDeleteForMe: {
                viewModel.deleteForMe(item)
                Haptics.impact(.medium)
            },
            onDeleteForEveryone: { confirmDelete = item },
            onRetry: {
                viewModel.retry(item)
                Haptics.impact(.light)
            },
            onOpenQuote: { id in jump(to: id, proxy: proxy) },
            onOpenMedia: { viewerItem = item },
            onCancelUpload: {
                viewModel.cancelUpload(item)
                Haptics.impact(.medium)
            },
            onLoadThumbnail: { await viewModel.loadThumbnail(for: item) },
            onLoadSticker: { _ = try? await viewModel.loadAttachment(for: item) },
            onSaveSticker: { saveMessageStickerToLibrary(item) },
            player: audioPlayer,
            onLoadAudio: { try await viewModel.loadAudio(for: item) },
            onToggleAudio: { toggleAudio(item) },
            bubbleStyle: style,
            bubbleAssets: style.map { bubbleStore.assets(for: $0, ownerID: sender) } ?? .empty,
            bubbleCacheOwner: owner,
            onCallBack: viewModel.kind == .partner ? { CallLauncher.call(viewModel) } : nil,
            onInfo: { infoItem = item }
        )
        .task(id: item.message.bubble) {
            await bubbleStore.ensure(item.message.bubble, ownerID: sender)
        }
    }

    /// Sesli mesajı oynatır / duraklatır; dosya cihazda yoksa önce indirilir.
    private func toggleAudio(_ item: ChatMessageItem) {
        if audioPlayer.isCurrent(item.id) {
            if let url = item.localOriginalURL { audioPlayer.toggle(id: item.id, url: url) }
            else if audioPlayer.isPlaying { audioPlayer.pause() }
            return
        }
        Task {
            do {
                let url = try await viewModel.loadAudio(for: item)
                audioPlayer.toggle(id: item.id, url: url)
            } catch {
                audioPlayer.errorMessage = AppError.map(error).errorDescription
            }
        }
    }

    // MARK: Sticker (8E)

    private var recentStickers: [StickerItem] {
        guard let userID = auth.currentUser?.id else { return [] }
        _ = recentIDs  // değişince yeniden hesaplansın
        return StickerRecents(defaults: .standard, userID: userID).items(from: stickerLibrary.stickers)
    }

    private func useRecent(_ sticker: StickerItem) {
        guard let userID = auth.currentUser?.id else { return }
        let recents = StickerRecents(defaults: .standard, userID: userID)
        recents.use(sticker.id)
        recentIDs = recents.ids
    }

    /// Panelden sohbete sürüklenip bırakılan sticker: bırakılan noktada taslak başlar (büyüt / döndür, sonra onayla).
    private func handleStickerDrop(_ items: [String], at location: CGPoint) -> Bool {
        guard let id = items.lazy.compactMap(StickerDragPayload.stickerID(from:)).first,
              let sticker = stickerLibrary.stickers.first(where: { $0.id == id }) else { return false }
        guard !viewModel.messages.isEmpty else {
            toast = "Yerleştirmek için sohbette en az bir mesaj olmalı"
            return false
        }
        useRecent(sticker)
        withAnimation(.easeOut(duration: 0.2)) { panel = .none }
        placementDraft = PlacementDraft(
            imageURL: sticker.fileURL, width: sticker.width, height: sticker.height, editingID: nil,
            transform: PlacementTransform(center: location, scale: 1, rotation: 0)
        )
        Haptics.impact(.medium)
        return true
    }

    /// VoiceOver: sürükleyemeyen kullanıcı için son mesajın yanına doğrudan yerleştirir.
    private func placeNearLastMessage(_ sticker: StickerItem) {
        guard let last = viewModel.messages.last else {
            toast = "Yerleştirmek için sohbette en az bir mesaj olmalı"
            return
        }
        useRecent(sticker)
        viewModel.placeSticker(fileURL: sticker.fileURL, width: sticker.width, height: sticker.height,
                               anchorMessageID: last.id, x: last.isMine ? 0.25 : 0.75, y: 0, scale: 1, rotation: 0)
        Haptics.success()
    }

    /// Kendi yerleştirmesini taşımak için taslağa alır.
    private func startMoving(_ item: ChatPlacementItem, center: CGPoint) {
        guard let url = item.localImageURL else { return }
        placementDraft = PlacementDraft(
            imageURL: url, width: item.placement.sticker.width, height: item.placement.sticker.height, editingID: item.id,
            transform: PlacementTransform(center: center, scale: item.placement.scale, rotation: item.placement.rotation)
        )
        Haptics.impact(.medium)
    }

    private var placementBar: some View {
        HStack(spacing: 12) {
            Button {
                placementDraft = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.ftCardElevated, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vazgeç")
            Text("Sürükle, iki parmakla büyüt ve döndür")
                .font(.caption)
                .foregroundStyle(Color.ftTextSecondary)
                .frame(maxWidth: .infinity)
            Button {
                commitPlacement()
            } label: {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.ftAccent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Yerleştir")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.ftCard.ignoresSafeArea(edges: .bottom))
    }

    private func commitPlacement() {
        guard let draft = placementDraft else { return }
        // Yatay oran, yerleştirmelerin çizildiği içerik genişliğine göre (kenar boşlukları hariç).
        let width = metrics.contentWidth > 0 ? metrics.contentWidth : metrics.viewportSize.width
        guard let anchor = PlacementGeometry.anchored(center: draft.transform.center,
                                                      containerWidth: width,
                                                      frames: metrics.frames) else {
            toast = "Sticker'ı bir mesajın yakınına bırak"
            return
        }
        if let id = draft.editingID {
            viewModel.movePlacement(id, anchorMessageID: anchor.anchorID, x: anchor.x, y: anchor.y,
                                    scale: draft.transform.scale, rotation: draft.transform.rotation)
        } else {
            viewModel.placeSticker(fileURL: draft.imageURL, width: draft.width, height: draft.height,
                                   anchorMessageID: anchor.anchorID, x: anchor.x, y: anchor.y,
                                   scale: draft.transform.scale, rotation: draft.transform.rotation)
        }
        placementDraft = nil
        Haptics.success()
    }

    private func saveMessageStickerToLibrary(_ item: ChatMessageItem) {
        guard let sticker = item.message.sticker else { return }
        Task {
            do {
                let url = try await viewModel.loadAttachment(for: item)
                try stickerLibrary.addPNG(at: url, width: sticker.width, height: sticker.height)
                Haptics.success()
                withAnimation { toast = "Kütüphanene kaydedildi" }
            } catch {
                viewModel.errorMessage = AppError.map(error).errorDescription
            }
        }
    }

    private func savePlacementToLibrary(_ item: ChatPlacementItem) {
        Task {
            guard let url = await viewModel.loadPlacementImage(item) else {
                viewModel.errorMessage = "Sticker indirilemedi."
                return
            }
            do {
                try stickerLibrary.addPNG(at: url, width: item.placement.sticker.width, height: item.placement.sticker.height)
                Haptics.success()
                withAnimation { toast = "Kütüphanene kaydedildi" }
            } catch {
                viewModel.errorMessage = AppError.map(error).errorDescription
            }
        }
    }

    /// Gönderilmeden vazgeçilen geçici kopyalar silinir.

    private func showsDayHeader(at index: Int) -> Bool {
        let messages = viewModel.messages
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].message.createdAt, inSameDayAs: messages[index - 1].message.createdAt)
    }

    // MARK: Paneller (klavye yüksekliğinde)

    @ViewBuilder
    private func panelView(bottomInset: CGFloat, fullHeight: CGFloat, topInset: CGFloat) -> some View {
        switch panel {
        case .none:
            EmptyView()
        case .stickers:
            ChatStickerPanel(
                library: stickerLibrary,
                recents: recentStickers,
                onSend: { sticker in
                    viewModel.sendSticker(fileURL: sticker.fileURL, width: sticker.width, height: sticker.height)
                    useRecent(sticker)
                },
                onPlace: { sticker in placeNearLastMessage(sticker) },
                onCreate: { showStickers = true }
            )
            .padding(.bottom, bottomInset)
            .frame(height: keyboard.height)
            .background(Color.ftCard)
        case .gallery:
            ChatGalleryPanel(
                collapsedHeight: keyboard.height,
                expandedHeight: max(keyboard.height, fullHeight - topInset - 8),
                bottomInset: bottomInset,
                isExpanded: $galleryExpanded,
                onSend: { items in
                    let quality = ChatMediaPreferences.sendQuality(.standard)
                    Task { await viewModel.sendMedia(items, quality: quality) }
                    closePanel()
                },
                onCamera: {
                    showCamera = true
                },
                onSystemPicker: { showPicker = true },
                onClose: { closePanel() }
            )
        }
    }

    /// Düğmeye basılınca: panel açıksa klavyeye dön, değilse klavyenin yerine paneli koy.
    /// Panel animasyonsuz gelir; klavye kendi animasyonuyla inerken altında aynı yükseklikte panel hazırdır.
    private func togglePanel(_ target: ChatInputPanel) {
        Haptics.selection()
        if panel == target {
            // Panelden klavyeye: panel klavye tamamen çıkınca kaldırılır.
            composerFocused = true
            return
        }
        setPanel(target)
        galleryExpanded = false
        composerFocused = false
    }

    private func setPanel(_ value: ChatInputPanel) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { panel = value }
    }

    private func closePanel() {
        galleryExpanded = false
        withAnimation(.easeOut(duration: 0.22)) { panel = .none }
    }

    // MARK: Bul

    private func endFind() {
        findFocused = false
        viewModel.endFind()
        highlightedID = nil
    }

    /// Eşleşen baloncuğa kayar ve arama sürdükçe vurgulu tutar.
    private func focusFound(_ id: String, proxy: ScrollViewProxy) {
        guard viewModel.reveal(messageID: id) else { return }
        highlightedID = id
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
        }
    }

    /// Arama sonucu ya da alıntıya dokununca mesaja gider ve kısa süre vurgular.
    private func jump(to id: String, proxy: ScrollViewProxy) {
        guard viewModel.reveal(messageID: id) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation { proxy.scrollTo(id, anchor: .center) }
            highlightedID = id
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { if highlightedID == id { highlightedID = nil } }
        }
    }
}

// MARK: - Gün başlığı

struct ChatDayHeader: View {
    let date: Date

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Bugün" }
        if calendar.isDateInYesterday(date) { return "Dün" }
        return date.formatted(.dateTime.day().month(.wide).year().locale(ChatText.turkish))
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.ftTextSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.ftCard, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Yazıyor…

struct ChatTypingIndicator: View {
    let name: String
    @State private var phase = 0.0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.ftTextSecondary)
                        .frame(width: 7, height: 7)
                        .opacity(0.35 + 0.65 * abs(sin(phase + Double(index) * 0.8)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 48)
        }
        .padding(.top, 4)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) yazıyor")
    }
}

