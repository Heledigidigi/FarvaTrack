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
    /// Panel açılırken klavye görünüyorsa onun o anki yüksekliği: panel ve yazma alanı klavyeyle birebir aynı
    /// yerde kalır (klavye → panel geçişinde içerik zıplamaz). Yoksa saklanan klavye yüksekliği kullanılır.
    @State private var capturedPanelHeight: CGFloat?
    /// Ev çubuğu payı (pencerenin alt güvenli alanı).
    @State private var homeInset: CGFloat = 0
    /// Yazma alanının altındaki boşluğun alt kenarı ile pencerenin alt kenarı arasındaki pay (sıfır olmalı;
    /// değilse klavye ölçüsünden düşülür, yoksa yazma alanı ile klavye arasında boşluk kalır).
    @State private var bottomGap: CGFloat = 0
    /// Klavyenin o anki yüksekliği (ekranın altından; parmakla kapatırken de her karede güncellenir).
    @State private var keyboardOverlap: CGFloat = 0
    /// Kaydırarak yanıtlama: hangi mesaj ve ne kadar çekildi.
    @State private var swipeReply: (id: String, offset: CGFloat)?
    /// Sola kaydırınca saatler (Instagram gibi).
    @State private var timeReveal: CGFloat = 0
    /// Uzun bas → Bilgi.
    @State private var infoItem: ChatMessageItem?
    @FocusState private var findFocused: Bool
    @State private var scrollToBottomRequest = 0
    @State private var viewerReplyAction: ChatViewerReplyAction?
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
            conversation(fullHeight: root.size.height + root.safeAreaInsets.top, topInset: root.safeAreaInsets.top)
        }
        // Klavye ve ev çubuğu payı elle yönetilir: her şey ekranın altına göre ölçülür (klavye kılavuzuyla aynı).
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// Yazma alanının görünümün altından yüksekliği: klavye, açık panel ve ev çubuğundan en yükseği,
    /// görünümün pencere altına uzanmayan payı düşülerek.
    /// Panelin (ve panel açıkken yazma alanının) yüksekliği.
    private var panelHeight: CGFloat {
        ChatPanelLayout.panelHeight(captured: capturedPanelHeight, stored: keyboard.height)
    }

    private var lift: CGFloat {
        ChatPanelLayout.visibleLift(
            ChatPanelLayout.lift(panel: placementDraft == nil && !viewModel.isFinding ? panel : .none,
                                 keyboardHeight: panelHeight, keyboardOverlap: keyboardOverlap, homeInset: homeInset),
            bottomGap: bottomGap)
    }

    private func updateBottomGap(rootMaxY: CGFloat) {
        let gap = ChatPanelLayout.bottomGap(viewMaxY: rootMaxY, windowHeight: ChatPanelLayout.keyWindowHeight())
        if abs(gap - bottomGap) > 0.5 { bottomGap = gap }
    }

    @ViewBuilder
    private func conversation(fullHeight: CGFloat, topInset: CGFloat) -> some View {
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
                            // Sola kaydırınca tüm baloncuklar kayar, sağda gönderim saatleri belirir;
                            // tek baloncuğu çekince (kendininkini sola, karşıdakini sağa) o mesaj yanıtlanır.
                            .offset(x: timeReveal + replyOffset(for: item.id))
                            .overlay(alignment: item.isMine ? .trailing : .leading) {
                                let offset = replyOffset(for: item.id)
                                if offset != 0 {
                                    Image(systemName: "arrowshape.turn.up.left.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Color.ftCardElevated, in: Circle())
                                        // Eşiğe gelince küçük bir sıçrama: "bırakırsan yanıtlayacaksın".
                                        .scaleEffect(ChatSwipeReply.isTriggered(offset) ? 1.15 : 0.55 + 0.45 * ChatSwipeReply.progress(offset))
                                        .opacity(ChatSwipeReply.progress(offset))
                                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: ChatSwipeReply.isTriggered(offset))
                                        .padding(.horizontal, 4)
                                        .accessibilityHidden(true)
                                }
                            }
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
                        shouldBegin: { location, velocity in
                            if let hit = bubbleHit(at: location), hit.isMine == (velocity.x < 0) { return true }
                            return velocity.x < 0
                        },
                        onBegan: { location, velocity in
                            if let hit = bubbleHit(at: location), hit.isMine == (velocity.x < 0) {
                                swipeReply = (hit.id, 0)
                                return true
                            }
                            swipeReply = nil
                            return false
                        },
                        onChanged: { translation in
                            if let current = swipeReply {
                                let isMine = viewModel.messages.first { $0.id == current.id }?.isMine ?? true
                                let offset = ChatSwipeReply.offset(forTranslation: translation, isMine: isMine)
                                if ChatSwipeReply.isTriggered(offset) != ChatSwipeReply.isTriggered(current.offset) {
                                    Haptics.impact(.light)
                                }
                                swipeReply = (current.id, offset)
                            } else {
                                timeReveal = ChatTimeReveal.offset(forTranslation: translation)
                            }
                        },
                        onEnded: {
                            if let current = swipeReply {
                                if ChatSwipeReply.isTriggered(current.offset),
                                   let item = viewModel.messages.first(where: { $0.id == current.id }) {
                                    viewModel.beginReply(to: item)
                                    composerFocused = true
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { swipeReply = nil }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { timeReveal = 0 }
                            }
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
                .onPreferenceChange(ChatBubbleFramePreference.self) { metrics.bubbleFrames = $0 }
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
            .onChange(of: scrollToBottomRequest) { _, _ in
                withAnimation(ChatPanelLayout.keyboardAnimation) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
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
                    }
                    // Klavyenin / panelin / ev çubuğunun yeri. Panel bunun üstüne (ekranın altından) çizilir.
                    // Alt kenarı pencerenin altına oturmuyorsa (devralınan güvenli alan payı) aradaki pay ölçülüp
                    // düşülür; yoksa klavye ile yazma alanı arasında boşluk kalır.
                    ChatChromeBackground().frame(height: lift)
                        .background(GeometryReader { spacer in
                            Color.clear
                                .onAppear { updateBottomGap(rootMaxY: spacer.frame(in: .global).maxY) }
                                .onChange(of: spacer.frame(in: .global).maxY) { _, maxY in updateBottomGap(rootMaxY: maxY) }
                        })
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
                    // Görünüm pencerenin altına kadar uzanmıyorsa (gizli sekme çubuğu payı) panel o kadar aşağı
                    // kaydırılır; böylece panelin üstü tam yazma alanının altına oturur, yazma alanını örtmez.
                    .offset(y: bottomGap)
                    .transition(.move(edge: .bottom))
            }
        }
        .background(
            ChatKeyboardTracker { overlap, animated, home in
                let wasHidden = keyboardOverlap < 100
                if abs(homeInset - home) > 0.5 { homeInset = home }
                if animated {
                    withAnimation(ChatPanelLayout.keyboardAnimation) { keyboardOverlap = overlap }
                } else {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { keyboardOverlap = overlap }
                }
                if wasHidden, overlap >= 100, panel == .none, isNearBottom {
                    // Klavye açılırken son mesajlar klavyenin altında kalmasın.
                    withAnimation(ChatPanelLayout.keyboardAnimation) { scrollToBottomRequest += 1 }
                }
            }
        )
        .onAppear {
            keyboard.start()
            keyboard.onDidShow = {
                // Klavye panelin üstüne tamamen geldi: panel sessizce kaldırılır (yerleşim değişmez).
                if panel != .none { setPanel(.none) }
                capturedPanelHeight = nil
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
            ChatCameraView(stickers: stickerLibrary.stickers) { media, caption in
                let quality = ChatMediaPreferences.sendQuality(.standard)
                Task { await viewModel.sendMedia([media], quality: quality, caption: caption) }
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
        .fullScreenCover(item: $viewerItem, onDismiss: runViewerReplyAction) { item in
            ChatMediaViewer(item: item, viewModel: viewModel, stickers: stickerLibrary.stickers) { quoted, action in
                // Fotoğrafa yanıt: sohbete dönülür, alıntı hazır, seçilen işlem açılır (kamera, galeri…).
                viewModel.beginReply(to: quoted)
                viewerReplyAction = action
            }
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
            onInfo: { infoItem = item },
            quoteThumbnail: item.message.replyTo.flatMap { viewModel.replyThumbnail(for: $0.messageID) }
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
        .background(Color.ftChrome.ignoresSafeArea(edges: .bottom))
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
            .frame(height: panelHeight)
            .background(Color.ftChrome)
        case .gallery:
            ChatGalleryPanel(
                collapsedHeight: panelHeight,
                expandedHeight: max(panelHeight, fullHeight - topInset - 8),
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

    /// Görüntüleyiciden gelen yanıt işlemi (görüntüleyici kapanınca).
    private func runViewerReplyAction() {
        guard let action = viewerReplyAction else { return }
        viewerReplyAction = nil
        switch action {
        case .camera: showCamera = true
        case .gallery: togglePanel(.gallery)
        case .stickers: togglePanel(.stickers)
        case .voice:
            // Kayıt basılı tutarak yapılır: alıntı hazır, mikrofon düğmesi aynı yerde.
            recorder.hint = "Yanıtı kaydetmek için mikrofonu basılı tut"
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
        // Klavye açıkken panele geçiş: panel klavyenin o anki yüksekliğini alır.
        if panel == .none {
            capturedPanelHeight = ChatPanelLayout.capture(keyboardOverlap: keyboardOverlap)
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
        // Klavyenin inişiyle aynı yay: panel ve yazma alanı birlikte süzülür.
        withAnimation(ChatPanelLayout.keyboardAnimation) { panel = .none }
    }

    private func replyOffset(for id: String) -> CGFloat {
        guard let swipeReply, swipeReply.id == id else { return 0 }
        return swipeReply.offset
    }

    /// Pencere koordinatındaki noktanın altındaki baloncuk.
    private func bubbleHit(at location: CGPoint) -> (id: String, isMine: Bool)? {
        guard let id = metrics.bubbleFrames.first(where: { $0.value.insetBy(dx: -6, dy: -4).contains(location) })?.key,
              let item = viewModel.messages.first(where: { $0.id == id }),
              !item.message.deleted else { return nil }
        return (id, item.isMine)
    }

    /// Son mesaj ekranın altına yakın mı (klavye açılınca alta kaydırmak için).
    private var isNearBottom: Bool {
        guard let last = viewModel.messages.last, let frame = metrics.frames[last.id] else { return true }
        return frame.maxY + metrics.contentMinY <= metrics.viewportSize.height + 120
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
    @Environment(\.chatThemeLook) private var look

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Bugün" }
        if calendar.isDateInYesterday(date) { return "Dün" }
        return date.formatted(.dateTime.day().month(.wide).year().locale(ChatText.turkish))
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(look?.dayText.color ?? Color.ftTextSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background {
                if let look {
                    RoundedRectangle(cornerRadius: look.cornerRadius < 6 ? 2 : 12, style: .continuous)
                        .fill(look.dayBackground.color)
                } else {
                    Capsule().fill(Color.ftCard)
                }
            }
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

