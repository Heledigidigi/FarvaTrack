import SwiftUI

// MARK: - Mesaj konumları

/// Her mesajın sohbet içeriği koordinatındaki çerçevesi (yerleştirmeler buna bağlanır).
struct MessageFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// İçeriğin görünüm içindeki üst kenarı (kaydırınca değişir).
struct ChatContentOffsetPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

enum ChatCoordinateSpace {
    static let content = "chatContent"
    static let viewport = "chatViewport"
}

/// Kaydırma sırasında sık değişen ölçüler; gözlemlenmez (her karede ekran yeniden çizilmesin).
final class ChatScrollMetrics {
    var contentMinY: CGFloat = 0
    var viewportSize: CGSize = .zero
    var frames: [String: CGRect] = [:]
}

// MARK: - Sticker paneli

struct ChatStickerPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case recent, library
        var id: Self { self }
        var title: String { self == .recent ? "Son kullanılanlar" : "Kütüphanem" }
    }

    let library: StickerLibraryViewModel
    let recents: [StickerItem]
    let onSend: (StickerItem) -> Void
    let onPlace: (StickerItem) -> Void
    let onCreate: () -> Void

    @State private var tab: Tab = .recent

    private var items: [StickerItem] { tab == .recent ? recents : library.stickers }
    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 10)]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Sticker'lar", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Button(action: onCreate) {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .foregroundStyle(Color.ftAccentLight)
                .accessibilityLabel("Yeni sticker oluştur")
            }

            if items.isEmpty {
                VStack(spacing: 8) {
                    Text(tab == .recent ? "Gönderdiğin sticker'lar burada görünür." : "Kütüphanen boş.")
                        .font(.footnote)
                        .foregroundStyle(Color.ftTextSecondary)
                    if tab == .library || library.stickers.isEmpty {
                        Button("Fotoğraftan sticker oluştur", action: onCreate)
                            .font(.footnote.weight(.semibold))
                            .tint(Color.ftAccentLight)
                    } else {
                        Button("Kütüphaneme bak") { tab = .library }
                            .font(.footnote.weight(.semibold))
                            .tint(Color.ftAccentLight)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(items) { sticker in
                            Button {
                                Haptics.impact(.light)
                                onSend(sticker)
                            } label: {
                                CachedImageView(url: sticker.fileURL, contentMode: .fit)
                                    .frame(width: 72, height: 72)
                                    .background(Color.clear)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { onSend(sticker) } label: { Label("Gönder", systemImage: "paperplane") }
                                Button { onPlace(sticker) } label: { Label("Sohbete yerleştir", systemImage: "hand.draw") }
                            }
                            .accessibilityLabel("Sticker")
                            .accessibilityHint("Göndermek için dokun")
                            .accessibilityAction(named: "Sohbete yerleştir") { onPlace(sticker) }
                        }
                    }
                }
                .frame(height: 170)
                Text("Dokun: gönder · Uzun bas: sohbetin üstüne yerleştir")
                    .font(.caption2)
                    .foregroundStyle(Color.ftTextSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.ftCard)
        .onAppear { if recents.isEmpty { tab = .library } }
    }
}

// MARK: - Sticker mesajı

struct ChatStickerBubbleContent: View {
    let item: ChatMessageItem
    let sticker: ChatSticker
    let onLoad: () async -> Void

    static let maxSide: CGFloat = 150

    private var size: CGSize {
        let ratio = CGFloat(min(max(sticker.aspectRatio, 0.4), 2.5))
        return ratio >= 1 ? CGSize(width: Self.maxSide, height: Self.maxSide / ratio) : CGSize(width: Self.maxSide * ratio, height: Self.maxSide)
    }

    var body: some View {
        ZStack {
            if let url = item.localOriginalURL {
                StickerImage(url: url)
            } else {
                ProgressView()
            }
            if item.isUploading {
                ProgressView()
                    .padding(8)
                    .background(.black.opacity(0.35), in: Circle())
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: item.localOriginalURL == nil) {
            if item.localOriginalURL == nil { await onLoad() }
        }
    }
}

/// Saydam PNG (yer tutucu da saydam).
struct StickerImage: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path) }.value
        }
    }
}

// MARK: - Sohbet üstü yerleştirmeler

/// Mesajlarla birlikte kayar: konum her çizimde bağlı mesajın güncel çerçevesinden hesaplanır.
struct ChatPlacementLayer: View {
    let placements: [ChatPlacementItem]
    let frames: [String: CGRect]
    let containerWidth: CGFloat
    let hiddenID: String?
    let onLoad: (ChatPlacementItem) async -> Void
    let onMove: (ChatPlacementItem, CGPoint) -> Void
    let onReorder: (ChatPlacementItem, Bool) -> Void
    let onDelete: (ChatPlacementItem) -> Void
    let onSaveToLibrary: (ChatPlacementItem) -> Void
    let partnerName: String

    var body: some View {
        ForEach(placements) { item in
            if item.id != hiddenID,
               let center = PlacementGeometry.center(x: item.placement.x, y: item.placement.y,
                                                     anchorFrame: frames[item.placement.anchorMessageID],
                                                     containerWidth: containerWidth) {
                let size = PlacementGeometry.displaySize(containerWidth: containerWidth, scale: item.placement.scale,
                                                         aspectRatio: item.placement.sticker.aspectRatio)
                StickerImage(url: item.localImageURL)
                    .frame(width: size.width, height: size.height)
                    .rotationEffect(.radians(item.placement.rotation))
                    .opacity(item.isSyncing ? 0.85 : 1)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if item.isMine {
                            Button { onMove(item, center) } label: { Label("Taşı / büyüt / döndür", systemImage: "arrow.up.and.down.and.arrow.left.and.right") }
                            Button { onReorder(item, true) } label: { Label("Öne al", systemImage: "square.3.layers.3d.top.filled") }
                            Button { onReorder(item, false) } label: { Label("Arkaya al", systemImage: "square.3.layers.3d.bottom.filled") }
                            Button(role: .destructive) { onDelete(item) } label: { Label("Sil", systemImage: "trash") }
                        } else {
                            Button { onSaveToLibrary(item) } label: { Label("Kütüphaneme kaydet", systemImage: "square.and.arrow.down") }
                        }
                    }
                    .position(center)
                    .task(id: item.localImageURL == nil) {
                        if item.localImageURL == nil { await onLoad(item) }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(item.isMine ? "Yerleştirdiğin sticker" : "\(partnerName) yerleştirdiği sticker")
                    .accessibilityActions {
                        if item.isMine {
                            Button("Taşı") { onMove(item, center) }
                            Button("Öne al") { onReorder(item, true) }
                            Button("Arkaya al") { onReorder(item, false) }
                            Button("Sil") { onDelete(item) }
                        } else {
                            Button("Kütüphaneme kaydet") { onSaveToLibrary(item) }
                        }
                    }
            }
        }
    }
}

// MARK: - Yerleştirme taslağı (sürükle, iki parmakla büyüt / döndür)

struct PlacementDraft: Equatable {
    var imageURL: URL
    var width: Int
    var height: Int
    /// Var olan yerleştirme taşınıyorsa kimliği.
    var editingID: String?
    var transform: PlacementTransform

    var aspectRatio: Double { height > 0 ? Double(width) / Double(height) : 1 }
}

struct PlacementDraftView: View {
    @Binding var draft: PlacementDraft?
    let containerWidth: CGFloat

    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var rotation: Angle = .zero

    var body: some View {
        if let current = draft {
            let live = current.transform.applying(translation: dragOffset, magnification: Double(magnification), rotation: rotation.radians)
            let size = PlacementGeometry.displaySize(containerWidth: containerWidth, scale: live.scale, aspectRatio: current.aspectRatio)
            StickerImage(url: current.imageURL)
                .frame(width: size.width, height: size.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )
                .rotationEffect(.radians(live.rotation))
                .shadow(color: .black.opacity(0.35), radius: 8)
                .contentShape(Rectangle())
                .position(live.center)
                .gesture(
                    SimultaneousGesture(
                        DragGesture(coordinateSpace: .named(ChatCoordinateSpace.content))
                            .updating($dragOffset) { value, state, _ in state = value.translation }
                            .onEnded { value in commit { $0.applying(translation: value.translation) } },
                        SimultaneousGesture(
                            MagnifyGesture()
                                .updating($magnification) { value, state, _ in state = value.magnification }
                                .onEnded { value in commit { $0.applying(magnification: Double(value.magnification)) } },
                            RotateGesture()
                                .updating($rotation) { value, state, _ in state = value.rotation }
                                .onEnded { value in commit { $0.applying(rotation: value.rotation.radians) } }
                        )
                    )
                )
                .accessibilityElement()
                .accessibilityLabel("Yerleştirilen sticker")
                .accessibilityHint("Sürükleyerek taşı, iki parmakla büyüt ve döndür")
                .accessibilityActions {
                    Button("Büyüt") { commit { $0.applying(magnification: 1.2) } }
                    Button("Küçült") { commit { $0.applying(magnification: 1 / 1.2) } }
                    Button("Sağa döndür") { commit { $0.applying(rotation: .pi / 12) } }
                    Button("Sola döndür") { commit { $0.applying(rotation: -.pi / 12) } }
                    Button("Yukarı taşı") { commit { $0.applying(translation: CGSize(width: 0, height: -24)) } }
                    Button("Aşağı taşı") { commit { $0.applying(translation: CGSize(width: 0, height: 24)) } }
                }
        }
    }

    private func commit(_ change: (PlacementTransform) -> PlacementTransform) {
        guard var current = draft else { return }
        current.transform = change(current.transform)
        draft = current
    }
}
