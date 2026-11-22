import SwiftUI
import AVKit
import UIKit

/// Tam ekran fotoğraf/video görüntüleyici.
///
/// - Sohbetteki tüm fotoğraf ve videolar arasında sağa-sola kaydırarak geçilir (eskiden yeniye).
/// - Aşağı (ya da yukarı) yeterince çekince kapanır, sohbet arkadan görünür; ✕ da kapatır.
/// - Tarih, boyut gibi bilgiler gösterilmez; altta Paylaş, İndir ve (fotoğrafta) Düzenle vardır.
/// - Düzenle: kırp, çiz, yazı, sticker; sonra Fotoğraflar'a indir ya da sohbete gönder.
struct ChatMediaViewer: View {
    let item: ChatMessageItem
    let viewModel: ChatViewModel
    /// Düzenleyicide eklenebilecek sticker'lar.
    var stickers: [StickerItem] = []

    @Environment(\.dismiss) private var dismiss
    @State private var items: [ChatMessageItem] = []
    @State private var selection: String
    @State private var chromeVisible = true
    @State private var dragOffset: CGFloat = 0
    @State private var isClosing = false
    /// Cihazdaki orijinal dosyalar (paylaş / indir / düzenle için).
    @State private var files: [String: URL] = [:]
    @State private var editing: ChatEditTarget?
    @State private var toast: String?
    @State private var isSaving = false
    @State private var isPreparingEdit = false
    /// Alttaki yanıt çubuğu: bu fotoğrafı alıntılayarak mesaj.
    @State private var replyText = ""
    @FocusState private var replyFocused: Bool

    private let photoSaver: PhotoLibrarySaving = PhotoLibrarySaver()

    init(item: ChatMessageItem, viewModel: ChatViewModel, stickers: [StickerItem] = []) {
        self.item = item
        self.viewModel = viewModel
        self.stickers = stickers
        _selection = State(initialValue: item.id)
    }

    private var current: ChatMessageItem? { items.first { $0.id == selection } ?? (selection == item.id ? item : nil) }
    private var currentFile: URL? { files[selection] }
    private var isVideo: Bool { current?.message.type == .video }

    /// Çektikçe arka plan saydamlaşır; sohbet görünür.
    private var backgroundOpacity: Double { 1 - min(abs(dragOffset) / 420, 1) * 0.85 }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(backgroundOpacity).ignoresSafeArea()

                TabView(selection: $selection) {
                    ForEach(items) { media in
                        ChatMediaPage(
                            item: media,
                            viewModel: viewModel,
                            isCurrent: selection == media.id,
                            onLoaded: { files[media.id] = $0 },
                            onTap: toggleChrome,
                            onDrag: { dragOffset = $0 },
                            onDragEnd: { translation, velocity in
                                finishDrag(translation: translation, velocity: velocity, height: proxy.size.height)
                            }
                        )
                        .tag(media.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .offset(y: dragOffset)
                .scaleEffect(1 - min(abs(dragOffset) / 1600, 0.12))

                chrome
                    .opacity((chromeVisible || replyFocused) && dragOffset == 0 && !isClosing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: chromeVisible)
                    .animation(.easeInOut(duration: 0.15), value: dragOffset == 0)
            }
        }
        .presentationBackground(.clear)
        .statusBarHidden(!chromeVisible || dragOffset != 0)
        .onAppear(perform: loadItems)
        .onChange(of: selection) { _, _ in Haptics.selection() }
        .fullScreenCover(item: $editing) { target in
            ChatPhotoEditorView(
                image: target.image,
                stickers: stickers,
                onClose: { editing = nil },
                onSend: { edited, caption in sendEdited(target, edited: edited, caption: caption) },
                onSave: { edited in await saveEdited(target, edited: edited) }
            )
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 60)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { self.toast = nil }
                    }
            }
        }
    }

    // MARK: Üst ve alt çubuk

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { close() } label: { roundIcon("xmark") }
                    .accessibilityLabel("Kapat")
                Spacer()
                if let url = currentFile {
                    ShareLink(item: url) { roundIcon("square.and.arrow.up") }
                        .accessibilityLabel("Paylaş")
                } else {
                    roundIcon("square.and.arrow.up").opacity(0.4)
                }
                Button { download() } label: { roundIcon(isSaving ? "hourglass" : "arrow.down.to.line") }
                    .disabled(currentFile == nil || isSaving)
                    .opacity(currentFile == nil ? 0.4 : 1)
                    .accessibilityLabel("Fotoğraflar'a indir")
                if !isVideo {
                    Button { startEditing() } label: { roundIcon(isPreparingEdit ? "hourglass" : "slider.horizontal.3") }
                        .disabled(currentFile == nil || isPreparingEdit)
                        .opacity(currentFile == nil ? 0.4 : 1)
                        .accessibilityLabel("Düzenle")
                        .accessibilityHint("Kırp, çiz, yazı ekle; sonra indir ya da sohbete gönder")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            replyBar
        }
    }

    private func roundIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color.black.opacity(0.4), in: Circle())
    }

    /// Bu fotoğrafa alıntılı yanıt: dokununca klavye açılır, gönderince sohbete dönülür.
    private var replyBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                CachedImageView(url: current?.localThumbnailURL)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
                TextField("Yanıtla…", text: $replyText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($replyFocused)
                    .foregroundStyle(.white)
                    .padding(.vertical, 9)
                    .accessibilityLabel("Bu fotoğrafa yanıt yaz")
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 21, style: .continuous))

            if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { sendReply() } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Color.ftAccent, in: Circle())
                }
                .accessibilityLabel("Yanıtı gönder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private func sendReply() {
        guard let item = current, viewModel.sendReply(replyText, to: item) else { return }
        Haptics.impact(.light)
        replyText = ""
        replyFocused = false
        dismiss()
    }

    // MARK: Hareketler

    private func toggleChrome() {
        if replyFocused {
            replyFocused = false
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() }
    }

    private func finishDrag(translation: CGFloat, velocity: CGFloat, height: CGFloat) {
        if abs(translation) > 110 || abs(velocity) > 900 {
            isClosing = true
            let upward = translation == 0 ? velocity < 0 : translation < 0
            let target: CGFloat = upward ? -height : height
            withAnimation(.easeOut(duration: 0.2)) { dragOffset = target }
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dismiss() }
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = 0 }
        }
    }

    private func close() {
        dismiss()
    }

    // MARK: Veri

    /// Sohbetteki tüm fotoğraf ve videolar, eskiden yeniye (sağa kaydırınca daha yeni).
    private func loadItems() {
        guard items.isEmpty else { return }
        let all = Array(viewModel.sharedMedia().reversed())
        items = all.contains(where: { $0.id == item.id }) ? all : [item]
    }

    private func download() {
        guard let url = currentFile else { return }
        let video = isVideo
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await photoSaver.save(fileURL: url, isVideo: video)
                Haptics.success()
                withAnimation { toast = "Fotoğraflar'a kaydedildi" }
            } catch AppError.notAuthorized {
                Haptics.error()
                withAnimation { toast = "Fotoğraflar'a erişim izni yok" }
            } catch {
                Haptics.error()
                withAnimation { toast = "Kaydedilemedi" }
            }
        }
    }

    private func startEditing() {
        guard let url = currentFile, let id = current?.id else { return }
        isPreparingEdit = true
        Task {
            let image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path)?.preparingForDisplay()
            }.value
            isPreparingEdit = false
            guard let image else {
                withAnimation { toast = "Fotoğraf açılamadı" }
                return
            }
            editing = ChatEditTarget(messageID: id, sourceURL: url, image: image)
        }
    }

    /// Düzenlenmişse son hali, düzenlenmemişse orijinalin kopyası sohbete yeni mesaj olarak gider.
    private func sendEdited(_ target: ChatEditTarget, edited: UIImage?, caption: String) {
        let outgoing: URL?
        if let edited {
            outgoing = ChatEditedImage.write(edited)
        } else {
            outgoing = ChatEditedImage.copy(target.sourceURL)
        }
        guard let outgoing else {
            withAnimation { toast = "Gönderilemedi" }
            return
        }
        Haptics.impact(.medium)
        let quality = ChatMediaPreferences.sendQuality(.standard)
        let viewModel = viewModel
        Task { await viewModel.sendMedia([PickedMedia(fileURL: outgoing, kind: .image)], quality: quality, caption: caption) }
        editing = nil
        // Düzenleyici kapanınca görüntüleyici de kapanır; yeni mesaj sohbette görünür.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            dismiss()
        }
    }

    private func saveEdited(_ target: ChatEditTarget, edited: UIImage?) async -> String {
        var url = target.sourceURL
        var temporary: URL?
        if let edited {
            guard let written = ChatEditedImage.write(edited) else { return "Kaydedilemedi" }
            url = written
            temporary = written
        }
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
        do {
            try await photoSaver.save(fileURL: url, isVideo: false)
            Haptics.success()
            return "Fotoğraflar'a kaydedildi"
        } catch AppError.notAuthorized {
            Haptics.error()
            return "Fotoğraflar'a erişim izni yok"
        } catch {
            Haptics.error()
            return "Kaydedilemedi"
        }
    }
}

/// Düzenlenecek fotoğraf.
struct ChatEditTarget: Identifiable {
    var id: String { messageID }
    let messageID: String
    let sourceURL: URL
    let image: UIImage
}

/// Düzenlenen ya da yeniden gönderilen fotoğrafların geçici dosyaları.
enum ChatEditedImage {
    static var directory: URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChatPicked", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// HEIC olarak (desteklenmiyorsa JPEG) yazar.
    static func write(_ image: UIImage) -> URL? {
        if let data = image.heicData() {
            let url = directory.appendingPathComponent("\(UUID().uuidString).heic")
            if (try? data.write(to: url)) != nil { return url }
        }
        guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }
        let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    /// Gönderim kaynak dosyayı sildiği için cihazdaki orijinalin kopyası.
    static func copy(_ source: URL) -> URL? {
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension
        let url = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        return (try? FileManager.default.copyItem(at: source, to: url)) != nil ? url : nil
    }
}

// MARK: - Tek sayfa

/// Görüntüleyicide tek fotoğraf/video: orijinali indirir (ya da cihazdan açar), yakınlaştırılır,
/// yakınlaştırılmamışken dikey çekme hareketini görüntüleyiciye bildirir.
private struct ChatMediaPage: View {
    let item: ChatMessageItem
    let viewModel: ChatViewModel
    /// Yalnızca ekrandaki sayfanın videosu oynar.
    let isCurrent: Bool
    let onLoaded: (URL) -> Void
    let onTap: () -> Void
    let onDrag: (CGFloat) -> Void
    let onDragEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    @State private var fileURL: URL?
    @State private var loadError: String?
    @State private var player: AVPlayer?

    private var isVideo: Bool { item.message.type == .video }

    var body: some View {
        ZStack {
            if let fileURL {
                if isVideo {
                    VideoPlayer(player: player)
                        .onAppear {
                            if player == nil { player = AVPlayer(url: fileURL) }
                            if isCurrent { player?.play() }
                        }
                        .onDisappear { player?.pause() }
                        .onChange(of: isCurrent) { _, current in
                            if current { player?.play() } else { player?.pause() }
                        }
                        .simultaneousGesture(videoDragGesture)
                        .accessibilityLabel("Video")
                } else {
                    ZoomableImage(url: fileURL, onSingleTap: onTap, onDismissDrag: onDrag, onDismissEnd: onDragEnd)
                        .ignoresSafeArea()
                        .accessibilityLabel("Fotoğraf")
                        .accessibilityHint("Yakınlaştırmak için iki parmakla aç ya da iki kez dokun. Kapatmak için aşağı çek.")
                }
            } else if let loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(Color.ftWarning)
                    Text(loadError).multilineTextAlignment(.center).foregroundStyle(.white)
                    Button("Tekrar dene") { Task { await load() } }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(videoDragGesture)
            } else {
                ZStack {
                    CachedImageView(url: item.localThumbnailURL, contentMode: .fit)
                        .blur(radius: 8)
                        .opacity(0.6)
                    if let progress = viewModel.downloadProgress[item.id] {
                        VStack(spacing: 10) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(Color.ftAccentLight)
                                .frame(width: 180)
                            Text("%\(Int(progress * 100))")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.white)
                        }
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(videoDragGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Yükleniyor")
            }
        }
        .task(id: item.id) { await load() }
    }

    /// Video ve yükleme ekranında dikey çekerek kapatma (SwiftUI hareketi).
    private var videoDragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                onDrag(value.translation.height)
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) else {
                    onDragEnd(0, 0)
                    return
                }
                let velocity = (value.predictedEndTranslation.height - value.translation.height) * 4
                onDragEnd(value.translation.height, velocity)
            }
    }

    private func load() async {
        guard fileURL == nil else { return }
        loadError = nil
        do {
            let url = try await viewModel.loadOriginal(for: item)
            fileURL = url
            onLoaded(url)
        } catch {
            loadError = AppError.map(error).errorDescription ?? "Dosya açılamadı."
        }
    }
}

// MARK: - Yakınlaştırılabilir fotoğraf

/// UIScrollView tabanlı: iki parmakla yakınlaştırma, iki kez dokununca büyütme/küçültme, tek dokunuş (çubukları
/// gizle/göster) ve yakınlaştırılmamışken dikey çekme (kapatma). Yatay kaydırma sayfa geçişine kalır.
struct ZoomableImage: UIViewRepresentable {
    let url: URL
    var onSingleTap: () -> Void = {}
    var onDismissDrag: (CGFloat) -> Void = { _ in }
    var onDismissEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void = { _, _ in }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor)
        ])
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        scrollView.addGestureRecognizer(pan)
        context.coordinator.dismissPan = pan

        // Büyük HEIC'ler ana iş parçacığını kilitlemesin.
        let path = url.path
        Task.detached(priority: .userInitiated) {
            let image = UIImage(contentsOfFile: path)?.preparingForDisplay()
            await MainActor.run { imageView.image = image }
        }
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomableImage
        weak var imageView: UIImageView?
        weak var dismissPan: UIPanGestureRecognizer?

        init(parent: ZoomableImage) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 3, height: scrollView.bounds.height / 3)
                scrollView.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
            }
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            parent.onSingleTap()
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view).y
            switch gesture.state {
            case .changed:
                parent.onDismissDrag(translation)
            case .ended, .cancelled, .failed:
                parent.onDismissEnd(translation, gesture.velocity(in: gesture.view).y)
            default:
                break
            }
        }

        /// Yalnızca yakınlaştırılmamışken ve hareket belirgin biçimde dikeyse başlar.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === dismissPan, let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let scrollView = pan.view as? UIScrollView else { return true }
            guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else { return false }
            let velocity = pan.velocity(in: scrollView)
            return abs(velocity.y) > abs(velocity.x) * 1.2
        }
    }
}
