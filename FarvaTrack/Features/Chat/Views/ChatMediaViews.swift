import SwiftUI
import PhotosUI
import QuickLookThumbnailing
import UniformTypeIdentifiers

// MARK: - Galeri seçici (PHPicker)

/// Fotoğraf ve videoları **orijinal** dosyalarıyla getirir: `preferredAssetRepresentationMode = .current`
/// sayesinde sistem HEIC/HEVC'yi JPEG/H.264'e çevirmez.
struct ChatMediaPicker: UIViewControllerRepresentable {
    var selectionLimit = 10
    let onComplete: ([PickedMedia]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = selectionLimit
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: ([PickedMedia]) -> Void

        init(onComplete: @escaping ([PickedMedia]) -> Void) {
            self.onComplete = onComplete
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            let providers = results.map(\.itemProvider)
            Task { @MainActor in
                var picked: [PickedMedia] = []
                for provider in providers {
                    if let media = await ChatMediaPicker.load(provider) { picked.append(media) }
                }
                onComplete(picked)
            }
        }
    }

    /// Sağlayıcının asıl dosyasını uygulamanın geçici klasörüne kopyalar.
    static func load(_ provider: NSItemProvider) async -> PickedMedia? {
        let identifiers = provider.registeredTypeIdentifiers
        let kind: ChatMediaKind
        let typeID: String
        if let movie = identifiers.first(where: { UTType($0)?.conforms(to: .movie) ?? false }) {
            kind = .video
            typeID = movie
        } else if let image = identifiers.first(where: { UTType($0)?.conforms(to: .image) ?? false }) {
            kind = .image
            typeID = image
        } else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, _ in
                // `url` yalnızca bu blok içinde geçerlidir; hemen kopyalanır.
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let ext = url.pathExtension.isEmpty
                    ? (UTType(typeID)?.preferredFilenameExtension ?? (kind == .image ? "jpg" : "mov"))
                    : url.pathExtension
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChatPicked", isDirectory: true)
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent("\(UUID().uuidString).\(ext.lowercased())")
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: PickedMedia(fileURL: destination, kind: kind))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Cihazdaki dosyanın küçük resmi

/// Henüz gönderilmemiş (geçici klasördeki) bir fotoğraf/videonun küçük resmi.
struct LocalFileThumbnail: View {
    let url: URL
    let kind: ChatMediaKind
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.ftCardElevated
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ProgressView()
            }
            if kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .video ? "Video" : "Fotoğraf")
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 240, height: 320),
                scale: UIScreen.main.scale, representationTypes: .thumbnail
            )
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
        }
    }
}

/// Önbellekteki küçük bir resmi ana iş parçacığını bekletmeden yükler.
struct CachedImageView: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Color.ftCardElevated
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path) }.value
        }
    }
}

// MARK: - Baloncuktaki medya

struct ChatMediaBubbleContent: View {
    let item: ChatMessageItem
    let media: ChatMedia
    let onOpen: () -> Void
    let onCancelUpload: () -> Void
    let onLoadThumbnail: () async -> Void

    private static let maxWidth: CGFloat = 240

    /// Çok uzun / çok geniş medyada baloncuk makul sınırlarda kalır.
    private var displaySize: CGSize {
        let ratio = min(max(media.aspectRatio, 0.6), 1.8)
        let width = Self.maxWidth
        return CGSize(width: width, height: width / ratio)
    }

    var body: some View {
        ZStack {
            CachedImageView(url: item.localThumbnailURL)
                .frame(width: displaySize.width, height: displaySize.height)
                .clipped()

            overlay
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !item.isUploading else { return }
            onOpen()
        }
        .task(id: item.localThumbnailURL == nil) {
            if item.localThumbnailURL == nil { await onLoadThumbnail() }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if item.isUploading {
            // Gönderen: yükleme ilerlemesi ve iptal.
            Button(action: onCancelUpload) {
                ZStack {
                    Circle().fill(.black.opacity(0.45)).frame(width: 52, height: 52)
                    if let progress = item.uploadProgress {
                        Circle()
                            .trim(from: 0, to: max(0.02, progress))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 44, height: 44)
                            .animation(.linear(duration: 0.2), value: progress)
                    } else {
                        ProgressView().tint(.white)
                    }
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Yüklemeyi iptal et")
            .accessibilityValue(item.uploadProgress.map { "Yüzde \(Int($0 * 100))" } ?? "Hazırlanıyor")
        } else if !item.isMine, media.status == .uploading {
            // Alıcı: önizleme geldi, orijinal yolda.
            Label("Gönderiliyor…", systemImage: "arrow.up.circle")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5), in: Capsule())
                .foregroundStyle(.white)
        } else if item.message.type == .video {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(radius: 6)
                .accessibilityHidden(true)
        }

        if item.message.type == .video, let duration = media.formattedDuration {
            VStack {
                Spacer()
                HStack {
                    Label(duration, systemImage: "video.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
            .padding(8)
            .accessibilityHidden(true)
        }
    }
}
