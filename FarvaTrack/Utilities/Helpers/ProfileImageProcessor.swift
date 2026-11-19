import UIKit

/// Profil fotoğrafını ortadan kare kırpar, küçültür ve JPEG olarak sıkıştırır.
enum ProfileImageProcessor {
    static func process(_ data: Data, maxSide: CGFloat = 512, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let shortSide = min(image.size.width, image.size.height)
        guard shortSide > 0 else { return nil }

        let target = min(maxSide, shortSide)
        let scale = target / shortSide
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1                                  // piksel = nokta
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}