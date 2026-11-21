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
    @State private var pickedMedia: [PickedMedia] = []
    @State private var viewerItem: ChatMessageItem?
    /// Sesli mesaj kaydı ve oynatma (8C).
    @State private var recorder = ChatVoiceRecorderModel()
    @State private var audioPlayer = ChatAudioPlayer()

    private static let bottomID = "chat-bottom"

    var body: some View {
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
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.last?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .overlay {
                if !viewModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    ChatSearchResults(viewModel: viewModel) { id in
                        jump(to: id, proxy: proxy)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ChatComposer(
                    viewModel: viewModel,
                    focused: $composerFocused,
                    onGallery: { showPicker = true },
                    onCamera: { showCamera = true },
                    recorder: recorder,
                    onVoice: { viewModel.sendVoice($0) }
                )
            }
        }
        .sheet(isPresented: $showPicker) {
            ChatMediaPicker { items in
                pickedMedia = items
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(get: { !pickedMedia.isEmpty }, set: { if !$0 { discardPicked() } })) {
            ChatMediaSendSheet(items: pickedMedia) { quality in
                let items = pickedMedia
                pickedMedia = []
                Task { await viewModel.sendMedia(items, quality: quality) }
            } onCancel: {
                discardPicked()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            ChatCameraView { media, quality in
                Task { await viewModel.sendMedia([media], quality: quality) }
            }
        }
        .fullScreenCover(item: $viewerItem) { item in
            ChatMediaViewer(item: item, viewModel: viewModel)
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
        .searchable(text: $viewModel.searchQuery, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Mesajlarda ara")
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
        ChatBubbleView(
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
            player: audioPlayer,
            onLoadAudio: { try await viewModel.loadAudio(for: item) },
            onToggleAudio: { toggleAudio(item) }
        )
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

    /// Gönderilmeden vazgeçilen geçici kopyalar silinir.
    private func discardPicked() {
        pickedMedia.forEach { try? FileManager.default.removeItem(at: $0.fileURL) }
        pickedMedia = []
    }

    private func showsDayHeader(at index: Int) -> Bool {
        let messages = viewModel.messages
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].message.createdAt, inSameDayAs: messages[index - 1].message.createdAt)
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

// MARK: - Arama sonuçları

struct ChatSearchResults: View {
    let viewModel: ChatViewModel
    let onSelect: (String) -> Void
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        Group {
            if viewModel.searchResults.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchQuery)
            } else {
                List(viewModel.searchResults) { item in
                    Button {
                        let id = item.id
                        dismissSearch()
                        viewModel.searchQuery = ""
                        onSelect(id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.isMine ? "Sen" : viewModel.partnerName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(item.message.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(Color.ftTextSecondary)
                            }
                            Text(item.message.text)
                                .font(.subheadline)
                                .lineLimit(2)
                                .foregroundStyle(.white)
                        }
                    }
                    .listRowBackground(Color.ftCard)
                    .accessibilityHint("Mesaja gider")
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.ftBackground)
    }
}
