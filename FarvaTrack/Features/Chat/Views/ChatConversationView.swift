import SwiftUI

/// Konuşma ekranı: mesaj listesi, "yazıyor…", arama ve yazma alanı.
struct ChatConversationView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @FocusState private var composerFocused: Bool
    @State private var highlightedID: String?
    @State private var confirmDelete: ChatMessageItem?

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
                ChatComposer(viewModel: viewModel, focused: $composerFocused)
            }
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
            onOpenQuote: { id in jump(to: id, proxy: proxy) }
        )
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
