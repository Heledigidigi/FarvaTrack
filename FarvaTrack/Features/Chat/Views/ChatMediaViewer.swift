import SwiftUI
import AVKit
import Photos

/// Tam ekran fotoğraf/video: orijinal dosya indirilir (ya da cihazdan açılır), yakınlaştırılır, oynatılır, kaydedilir.
struct ChatMediaViewer: View {
    let item: ChatMessageItem
    let viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var fileURL: URL?
    @State private var loadError: String?
    @State private var player: AVPlayer?
    @State private var saveState: SaveState = .idle

    enum SaveState: Equatable {
        case idle, saving, saved, failed(String)
    }

    private var isVideo: Bool { item.message.type == .video }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .toolbarBackground(.black.opacity(0.6), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(item.message.createdAt.formatted(date: .abbreviated, time: .shortened))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Kapat")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let fileURL {
                        ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Paylaş")
                        Button { Task { await save(fileURL) } } label: {
                            Image(systemName: saveState == .saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        }
                        .disabled(saveState == .saving || saveState == .saved)
                        .accessibilityLabel(saveState == .saved ? "Fotoğraflar'a kaydedildi" : "Fotoğraflar'a kaydet")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .task { await load() }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var content: some View {
        if let fileURL {
            if isVideo {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .horizontal)
                    .onAppear {
                        if player == nil {
                            player = AVPlayer(url: fileURL)
                            player?.play()
                        }
                    }
                    .accessibilityLabel("Video")
            } else {
                ZoomableImage(url: fileURL)
                    .ignoresSafeArea()
                    .accessibilityLabel("Fotoğraf")
                    .accessibilityHint("Yakınlaştırmak için iki parmakla aç ya da iki kez dokun")
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
        } else {
            ZStack {
                CachedImageView(url: item.localThumbnailURL, contentMode: .fit)
                    .blur(radius: 8)
                    .opacity(0.6)
                VStack(spacing: 10) {
                    if let progress = viewModel.downloadProgress[item.id] {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(Color.ftAccentLight)
                            .frame(width: 180)
                        Text("Orijinal indiriliyor · %\(Int(progress * 100))")
                            .font(.footnote)
                            .foregroundStyle(.white)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Orijinal dosya indiriliyor")
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let media = item.message.media {
            HStack(spacing: 8) {
                Text(media.quality == .original ? "Orijinal" : "Hızlı")
                Text("·")
                Text(media.formattedSize)
                if media.width > 0 {
                    Text("·")
                    Text("\(media.width)×\(media.height)")
                }
                if case .failed(let message) = saveState {
                    Text("·")
                    Text(message).foregroundStyle(Color.ftDanger)
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.6))
            .accessibilityElement(children: .combine)
        }
    }

    private func load() async {
        loadError = nil
        do {
            fileURL = try await viewModel.loadOriginal(for: item)
        } catch {
            loadError = AppError.map(error).errorDescription ?? "Dosya açılamadı."
        }
    }

    /// Dosya Fotoğraflar'a olduğu gibi eklenir (HEIC/HEVC korunur). Yalnızca "ekleme" izni istenir.
    private func save(_ url: URL) async {
        saveState = .saving
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveState = .failed("Fotoğraflar'a kaydetme izni yok")
            Haptics.error()
            return
        }
        do {
            let video = isVideo
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: video ? .video : .photo, fileURL: url, options: options)
            }
            saveState = .saved
            Haptics.success()
        } catch {
            saveState = .failed("Kaydedilemedi")
            Haptics.error()
        }
    }
}

// MARK: - Yakınlaştırılabilir fotoğraf

/// UIScrollView tabanlı: iki parmakla yakınlaştırma ve iki kez dokununca büyütme/küçültme.
struct ZoomableImage: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black

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

        // Büyük HEIC'ler ana iş parçacığını kilitlemesin.
        let path = url.path
        Task.detached(priority: .userInitiated) {
            let image = UIImage(contentsOfFile: path)?.preparingForDisplay()
            await MainActor.run { imageView.image = image }
        }
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

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
    }
}
