import SwiftUI
import UIKit

/// Seçilen fotoğrafın profil dairesinde nasıl görüneceğini ayarlama ekranı (iOS'taki "Taşı ve Ölçekle" gibi):
/// tek parmakla kaydır, iki parmakla büyüt, iki kez dokunarak yakınlaştır/uzaklaştır. Dışarısı karartılır.
struct ProfilePhotoCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    /// Daire içindeki kare bölge, JPEG olarak.
    let onChoose: (Data) -> Void

    /// Kalıcı (hareket bittikten sonraki) değerler.
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    /// Süren hareketler.
    @State private var dragTranslation: CGSize = .zero
    @State private var dragConsumed: CGSize = .zero
    @State private var isDragging = false
    @State private var magnification: CGFloat = 1
    @State private var magnificationConsumed: CGFloat = 1
    @State private var magnifyAnchor: CGPoint = .zero
    @State private var isMagnifying = false
    @State private var isRendering = false

    /// Ekranda kenarlardan bırakılan pay.
    private static let margin: CGFloat = 20

    var body: some View {
        GeometryReader { proxy in
            let diameter = max(80, min(proxy.size.width, proxy.size.height) - Self.margin * 2)
            let geometry = AvatarCropGeometry(imageSize: image.size, diameter: diameter)
            let live = liveState(geometry)
            let display = geometry.displaySize(zoom: max(live.zoom, 0.01))
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                Color.black

                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: display.width, height: display.height)
                    .offset(live.offset)
                    .position(center)
                    .accessibilityHidden(true)

                // Daire dışı karartılır.
                Color.black.opacity(0.62)
                    .mask {
                        Rectangle()
                            .overlay {
                                Circle()
                                    .frame(width: diameter, height: diameter)
                                    .position(center)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)

                Circle()
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
                    .position(center)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(geometry).simultaneously(with: magnifyGesture(geometry, center: center)))
            .onTapGesture(count: 2) { toggleZoom(geometry) }
            .accessibilityElement()
            .accessibilityLabel("Profil fotoğrafı önizlemesi")
            .accessibilityHint("Fotoğrafı tek parmakla kaydır, iki parmakla büyüt")
            .accessibilityAdjustableAction { direction in
                withAnimation(.easeOut(duration: 0.2)) {
                    zoom = AvatarCropGeometry.clampZoom(zoom + (direction == .increment ? 0.5 : -0.5))
                    offset = geometry.clampedOffset(offset, zoom: zoom)
                }
            }
            .overlay(alignment: .bottom) { bottomBar(geometry) }
            .overlay(alignment: .top) {
                Text("Taşı ve Ölçekle")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 16)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .ignoresSafeArea(edges: .horizontal)
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
    }

    // MARK: Alt çubuk

    private func bottomBar(_ geometry: AvatarCropGeometry) -> some View {
        HStack {
            Button("Vazgeç") { onCancel() }
                .font(.body)
                .foregroundStyle(.white)
            Spacer()
            if isRendering {
                ProgressView().tint(.white)
            } else {
                Button("Seç") { choose(geometry) }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.black.opacity(0.35))
    }

    // MARK: Hareketler

    /// Süren hareketlerle birlikte o anki büyütme ve kaydırma (sınır dışına çıkınca yaylanır).
    private func liveState(_ geometry: AvatarCropGeometry) -> (zoom: CGFloat, offset: CGSize) {
        let rawZoom = zoom * magnification
        // Sınırların ötesinde direnç: küçültürken 1'in, büyütürken en büyük değerin ötesine az gider.
        let liveZoom: CGFloat
        if rawZoom < 1 {
            liveZoom = 1 - (1 - rawZoom) * 0.35
        } else if rawZoom > AvatarCropGeometry.maxZoom {
            liveZoom = AvatarCropGeometry.maxZoom + (rawZoom - AvatarCropGeometry.maxZoom) * 0.35
        } else {
            liveZoom = rawZoom
        }
        var base = offset
        if isMagnifying {
            let ratio = liveZoom / max(zoom, 0.01)
            base = CGSize(width: magnifyAnchor.x - (magnifyAnchor.x - offset.width) * ratio,
                          height: magnifyAnchor.y - (magnifyAnchor.y - offset.height) * ratio)
        }
        let raw = CGSize(width: base.width + dragTranslation.width, height: base.height + dragTranslation.height)
        let clamped = geometry.clampedOffset(raw, zoom: AvatarCropGeometry.clampZoom(liveZoom))
        // Kenarın ötesine çekilince lastik gibi direnç.
        let rubber = CGSize(width: clamped.width + (raw.width - clamped.width) * 0.3,
                            height: clamped.height + (raw.height - clamped.height) * 0.3)
        return (liveZoom, rubber)
    }

    private func dragGesture(_ geometry: AvatarCropGeometry) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                isDragging = true
                dragTranslation = CGSize(width: value.translation.width - dragConsumed.width,
                                         height: value.translation.height - dragConsumed.height)
            }
            .onEnded { _ in
                commit(geometry)
                isDragging = false
                dragConsumed = .zero
            }
    }

    private func magnifyGesture(_ geometry: AvatarCropGeometry, center: CGPoint) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isMagnifying {
                    isMagnifying = true
                    magnifyAnchor = CGPoint(x: value.startLocation.x - center.x, y: value.startLocation.y - center.y)
                }
                magnification = value.magnification / magnificationConsumed
            }
            .onEnded { _ in
                commit(geometry)
                isMagnifying = false
                magnificationConsumed = 1
            }
    }

    /// Bir hareket bitince o anki durum kalıcı olur ve sınırların içine yaylanarak döner.
    /// Diğer hareket sürüyorsa onun bundan sonraki değişimi yeni duruma göre sayılır.
    private func commit(_ geometry: AvatarCropGeometry) {
        let live = liveState(geometry)
        let finalZoom = AvatarCropGeometry.clampZoom(live.zoom)
        if isDragging {
            dragConsumed = CGSize(width: dragConsumed.width + dragTranslation.width,
                                  height: dragConsumed.height + dragTranslation.height)
        }
        if isMagnifying {
            magnificationConsumed *= magnification
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            zoom = finalZoom
            offset = geometry.clampedOffset(live.offset, zoom: finalZoom)
            dragTranslation = .zero
            magnification = 1
        }
    }

    private func toggleZoom(_ geometry: AvatarCropGeometry) {
        Haptics.selection()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if zoom > 1.05 {
                zoom = 1
                offset = .zero
            } else {
                zoom = 2.5
                offset = geometry.clampedOffset(CGSize(width: offset.width * 2.5, height: offset.height * 2.5), zoom: 2.5)
            }
        }
    }

    // MARK: Sonuç

    private func choose(_ geometry: AvatarCropGeometry) {
        isRendering = true
        let rect = geometry.cropRect(zoom: zoom, offset: offset)
        let image = image
        Task {
            let data = await Task.detached(priority: .userInitiated) {
                ProfilePhotoRenderer.jpeg(from: image, crop: rect)
            }.value
            isRendering = false
            if let data {
                Haptics.success()
                onChoose(data)
            } else {
                Haptics.error()
            }
        }
    }
}

// MARK: - Kırpılmış fotoğrafın çizimi

enum ProfilePhotoRenderer {
    /// Profil fotoğrafının kenar uzunluğu (piksel). Büyük ekranlarda da net, yüklemesi hızlı.
    static let side: CGFloat = 640

    /// `crop` (fotoğraf noktalarında kare) bölgesini `side × side` JPEG'e çizer. Yön bilgisi `draw` ile uygulanır.
    static func jpeg(from image: UIImage, crop: CGRect, quality: CGFloat = 0.85) -> Data? {
        guard crop.width > 0 else { return nil }
        let factor = side / crop.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: -crop.minX * factor, y: -crop.minY * factor,
                                  width: image.size.width * factor, height: image.size.height * factor))
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    /// Çok büyük fotoğraflar hizalama ekranından önce küçültülür (bellek); yön düzeltilmiş olarak döner.
    static func prepared(from data: Data, maxSide: CGFloat = 2400) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image.preparingForDisplay() ?? image }
        let scale = maxSide / longest
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        return image.preparingThumbnail(of: size) ?? image
    }
}

/// `fullScreenCover(item:)` için.
struct CropCandidate: Identifiable {
    let id = UUID()
    let image: UIImage
}
