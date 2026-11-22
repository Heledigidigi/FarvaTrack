import CoreGraphics

/// Profil fotoğrafı hizalama ekranının saf geometrisi (testli).
///
/// Fotoğraf, çapı `diameter` olan dairenin tamamını kaplayacak en küçük ölçekle (`baseScale`) başlar.
/// Kullanıcı `zoom` (1…`maxZoom`) ile büyütür ve `offset` ile kaydırır; daire hiçbir zaman fotoğrafın
/// dışına taşmaz. Sonuç, fotoğraf koordinatında (nokta) kare bir kırpma bölgesidir.
struct AvatarCropGeometry: Equatable {
    var imageSize: CGSize
    var diameter: CGFloat

    static let maxZoom: CGFloat = 6

    /// Dairenin tamamını kaplayan ölçek (fotoğrafın kısa kenarı = çap).
    var baseScale: CGFloat {
        let shortSide = min(imageSize.width, imageSize.height)
        guard shortSide > 0 else { return 1 }
        return diameter / shortSide
    }

    static func clampZoom(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, 1), maxZoom)
    }

    /// Ekranda gösterilen fotoğraf boyutu.
    func displaySize(zoom: CGFloat) -> CGSize {
        let scale = baseScale * Self.clampZoom(zoom)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Kaydırma payı: fotoğraf kenarı dairenin içine giremez.
    func clampedOffset(_ offset: CGSize, zoom: CGFloat) -> CGSize {
        let size = displaySize(zoom: zoom)
        let maxX = max(0, (size.width - diameter) / 2)
        let maxY = max(0, (size.height - diameter) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX),
                      height: min(max(offset.height, -maxY), maxY))
    }

    /// Dairenin gördüğü kare bölge (fotoğraf noktalarında).
    func cropRect(zoom: CGFloat, offset: CGSize) -> CGRect {
        let zoom = Self.clampZoom(zoom)
        let offset = clampedOffset(offset, zoom: zoom)
        let scale = baseScale * zoom
        guard scale > 0 else { return CGRect(origin: .zero, size: imageSize) }
        let side = min(diameter / scale, min(imageSize.width, imageSize.height))
        // Fotoğraf sağa kaydırılınca daire fotoğrafın soluna denk gelir.
        let centerX = imageSize.width / 2 - offset.width / scale
        let centerY = imageSize.height / 2 - offset.height / scale
        var rect = CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
        // Yuvarlama hatalarına karşı fotoğrafın içinde tut.
        rect.origin.x = min(max(rect.origin.x, 0), imageSize.width - side)
        rect.origin.y = min(max(rect.origin.y, 0), imageSize.height - side)
        return rect
    }

    /// İki parmakla büyütürken parmakların ortasındaki nokta yerinde kalsın diye kaydırmanın yeni değeri.
    /// `anchor`: dairenin merkezine göre ekran noktası.
    func offset(afterZoomingFrom oldZoom: CGFloat, to newZoom: CGFloat, offset: CGSize, anchor: CGPoint) -> CGSize {
        let old = Self.clampZoom(oldZoom)
        let new = Self.clampZoom(newZoom)
        guard old > 0 else { return offset }
        let ratio = new / old
        let raw = CGSize(width: anchor.x - (anchor.x - offset.width) * ratio,
                         height: anchor.y - (anchor.y - offset.height) * ratio)
        return clampedOffset(raw, zoom: new)
    }
}
