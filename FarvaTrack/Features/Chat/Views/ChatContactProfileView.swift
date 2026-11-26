import SwiftUI

// MARK: - Kişi profili (sohbet başlığına dokununca)

/// WhatsApp'taki kişi bilgisi gibi: büyük avatar, ad, Sesli ara / Ara düğmeleri,
/// medya ve bağlantılar, sohbet baloncuğu (görünüm).
struct ChatContactProfileView: View {
    let viewModel: ChatViewModel
    @Binding var showBubbles: Bool
    /// Medya/bağlantıdan "Sohbette göster": profil (ve üstündekiler) kapanır, konuşma oraya kayar.
    let onJump: (String) -> Void
    /// "Ara": profil kapanır, konuşmada alttaki arama çubuğu açılır (Ctrl+F gibi).
    let onFind: () -> Void

    @Environment(BubbleStyleStore.self) private var bubbleStore
    @State private var media: [ChatMessageItem] = []
    @State private var links: [ChatSharedLink] = []
    @State private var viewerItem: ChatMessageItem?

    private var isPartner: Bool { viewModel.kind == .partner }

    var body: some View {
        List {
            header
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            Section {
                NavigationLink {
                    ChatSharedContentView(viewModel: viewModel, initialTab: .media, onJump: onJump)
                } label: {
                    HStack {
                        Label("Medya ve bağlantılar", systemImage: "photo.on.rectangle")
                        Spacer()
                        Text("\(media.count + links.count)")
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                }
                if !media.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(media.prefix(12)) { item in
                                ChatSharedMediaCell(item: item, viewModel: viewModel)
                                    .frame(width: 82, height: 82)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .onTapGesture { viewerItem = item }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listRowBackground(Color.ftCard)

            Section("Görünüm") {
                Button {
                    showBubbles = true
                } label: {
                    HStack {
                        Label("Sohbet baloncuğu", systemImage: "paintpalette")
                        Spacer()
                        Text(bubbleStore.selectedStyle?.name ?? "Varsayılan")
                            .foregroundStyle(Color.ftTextSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                }
                .foregroundStyle(Color.ftText)
                .accessibilityHint("Mesaj baloncuğunun görünümünü değiştir ya da kendi baloncuğunu tasarla")

                NavigationLink {
                    ChatThemePickerView(viewModel: viewModel)
                } label: {
                    HStack {
                        Label("Sohbet teması", systemImage: "photo.artframe")
                        Spacer()
                        Text(viewModel.theme?.id.title ?? ChatThemeID.plain.title)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                }
                .foregroundStyle(Color.ftText)
                .accessibilityHint("Bu sohbetin duvar kâğıdını, çubuklarını ve varsayılan baloncuğunu değiştirir; iki tarafta da görünür")
            }
            .listRowBackground(Color.ftCard)
        }
        .scrollContentBackground(.hidden)
        .ftScreenBackground()
        .navigationTitle(isPartner ? "Kişi bilgisi" : "Notlarım")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(item: $viewerItem) { item in
            ChatMediaViewer(item: item, viewModel: viewModel)
        }
        .onAppear(perform: reload)
        .onChange(of: viewModel.messages.count) { _, _ in reload() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            if isPartner || viewModel.partnerPhotoURL != nil {
                PresenceAvatarView(name: viewModel.partnerName, photoURL: viewModel.partnerPhotoURL,
                                   presence: viewModel.partnerPresence, size: 104)
            } else {
                Image(systemName: "note.text")
                    .font(.system(size: 42))
                    .foregroundStyle(.white)
                    .frame(width: 104, height: 104)
                    .background(Color.ftCardElevated, in: Circle())
                    .accessibilityHidden(true)
            }
            Text(viewModel.partnerName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if isPartner, let presence = viewModel.partnerPresence.text(now: viewModel.now) {
                Text(presence)
                    .font(.subheadline)
                    .foregroundStyle(viewModel.partnerPresence.isOnline ? Color.ftOnline : Color.ftTextSecondary)
            } else {
                Text(isPartner ? "Özel sohbet" : "Yalnızca sen görürsün")
                    .font(.subheadline)
                    .foregroundStyle(Color.ftTextSecondary)
            }

            HStack(spacing: 12) {
                if isPartner {
                    actionButton("Sesli ara", systemImage: "phone.fill") {
                        CallLauncher.call(viewModel)
                    }
                    .disabled(CallManager.shared.phase.isActive)
                }
                actionButton("Ara", systemImage: "magnifyingglass") {
                    onFind()
                }
                .accessibilityLabel("Mesajlarda ara")
                .accessibilityHint("Sohbete döner ve altta arama çubuğunu açar")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.ftAccentLight)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ftText)
            }
            .frame(width: 96, height: 68)
            .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func reload() {
        media = viewModel.sharedMedia()
        links = viewModel.sharedLinks()
    }
}

// MARK: - Medya ve bağlantılar

struct ChatSharedContentView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case media = "Medya"
        case links = "Bağlantılar"
        var id: Self { self }
    }

    let viewModel: ChatViewModel
    let initialTab: Tab
    let onJump: (String) -> Void

    @State private var tab: Tab = .media
    @State private var media: [ChatMessageItem] = []
    @State private var links: [ChatSharedLink] = []
    @State private var viewerItem: ChatMessageItem?
    @Environment(\.openURL) private var openURL

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tür", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            switch tab {
            case .media: mediaGrid
            case .links: linkList
            }
        }
        .ftScreenBackground()
        .navigationTitle("Medya ve bağlantılar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(item: $viewerItem) { item in
            ChatMediaViewer(item: item, viewModel: viewModel)
        }
        .onAppear {
            tab = initialTab
            media = viewModel.sharedMedia()
            links = viewModel.sharedLinks()
        }
    }

    @ViewBuilder
    private var mediaGrid: some View {
        if media.isEmpty {
            ContentUnavailableView("Medya yok", systemImage: "photo", description: Text("Sohbette paylaşılan fotoğraf ve videolar burada görünür."))
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(media) { item in
                        ChatSharedMediaCell(item: item, viewModel: viewModel)
                            .onTapGesture { viewerItem = item }
                            .contextMenu {
                                Button { onJump(item.id) } label: { Label("Sohbette göster", systemImage: "text.bubble") }
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var linkList: some View {
        if links.isEmpty {
            ContentUnavailableView("Bağlantı yok", systemImage: "link", description: Text("Mesajlarda paylaşılan bağlantılar burada görünür."))
        } else {
            List(links) { link in
                Button {
                    openURL(link.url)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "link")
                            .foregroundStyle(Color.ftAccentLight)
                            .frame(width: 40, height: 40)
                            .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(link.url.host() ?? link.url.absoluteString)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.ftText)
                                .lineLimit(1)
                            Text(link.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(Color.ftAccentLight)
                                .lineLimit(1)
                            Text("\(link.isMine ? "Sen" : viewModel.partnerName) · \(link.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(Color.ftTextSecondary)
                        }
                    }
                }
                .listRowBackground(Color.ftCard)
                .contextMenu {
                    Button { onJump(link.messageID) } label: { Label("Sohbette göster", systemImage: "text.bubble") }
                    Button { UIPasteboard.general.url = link.url } label: { Label("Kopyala", systemImage: "doc.on.doc") }
                }
                .accessibilityHint("Bağlantıyı açar. Diğer seçenekler için basılı tut")
            }
            .scrollContentBackground(.hidden)
        }
    }
}

/// Profil/medya ızgarasında tek küçük resim (gerekirse önizlemeyi indirir).
struct ChatSharedMediaCell: View {
    let item: ChatMessageItem
    let viewModel: ChatViewModel
    @State private var url: URL?

    var body: some View {
        // Kare hücre: boyutu ızgaradan alır, fotoğraf ortadan kırpılarak doldurur (taşmaz, üst üste binmez).
        Color.ftCardElevated
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CachedImageView(url: url ?? item.localThumbnailURL, contentMode: .fill)
            }
            .overlay(alignment: .bottomLeading) {
                if item.message.type == .video {
                    HStack(spacing: 3) {
                        Image(systemName: "video.fill")
                        if let duration = item.message.media?.duration {
                            Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(5)
                }
            }
            .clipped()
            .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(item.message.type == .video ? "Video" : "Fotoğraf")
        .accessibilityAddTraits(.isButton)
        .task(id: item.id) {
            if url == nil, item.localThumbnailURL == nil {
                url = await viewModel.loadThumbnail(for: item)
            }
        }
    }
}
