import Foundation
import CoreGraphics
import ImageIO
import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Yazı ve emoji katmanları

struct StickerOverlay: Identifiable, Equatable, Codable {
    enum Kind: String, Codable { case text, emoji }

    var id = UUID()
    var kind: Kind
    var text: String
    /// Görüntü içinde merkez (0…1).
    var center: CGPoint
    /// Yazı boyu, görüntü genişliğine oranla (0,02…0,5).
    var relativeSize: Double
    var colorHex: String

    static let colors = ["#FFFFFF", "#111111", "#E0607F", "#F5C451", "#4DA3FF", "#30A46C"]
    static let emojis = ["😂", "😍", "🥹", "😎", "🤪", "😭", "🥳", "😡", "🤔", "😴", "💪", "🔥",
                         "❤️", "💔", "✨", "👏", "🙏", "👍", "👀", "💯", "🎉", "🌸", "🐱", "☕️"]

    static func text(_ value: String, color: String = "#FFFFFF") -> StickerOverlay {
        StickerOverlay(kind: .text, text: value, center: CGPoint(x: 0.5, y: 0.8), relativeSize: 0.1, colorHex: color)
    }

    static func emoji(_ value: String) -> StickerOverlay {
        StickerOverlay(kind: .emoji, text: value, center: CGPoint(x: 0.78, y: 0.22), relativeSize: 0.18, colorHex: "#FFFFFF")
    }

    /// Görüntü genişliğine göre punto.
    func fontSize(forImageWidth width: CGFloat) -> CGFloat {
        CGFloat(min(max(relativeSize, 0.02), 0.5)) * width
    }

    var uiFont: (CGFloat) -> UIFont {
        { size in
            let base = UIFont.systemFont(ofSize: size, weight: .heavy)
            if let rounded = base.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: rounded, size: size)
            }
            return base
        }
    }

    func attributedString(forImageWidth width: CGFloat) -> NSAttributedString {
        let size = fontSize(forImageWidth: width)
        var attributes: [NSAttributedString.Key: Any] = [.font: uiFont(size)]
        if kind == .text {
            attributes[.foregroundColor] = UIColor(Color(hex: colorHex))
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}

// MARK: - RGBA tampon

/// Ön çarpımlı (premultiplied) RGBA, 8 bit; sol üstten satır satır.
struct RGBABuffer: Equatable {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = Array(repeating: 0, count: width * height * 4)
    }

    /// Görüntüyü verilen boyuta çizerek okur.
    init?(image: CGImage, width: Int? = nil, height: Int? = nil) {
        let w = width ?? image.width
        let h = height ?? image.height
        guard w > 0, h > 0 else { return nil }
        self.init(width: w, height: h)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = RGBABuffer.makeContext(raw.baseAddress, width: w, height: h) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
    }

    static func makeContext(_ data: UnsafeMutableRawPointer?, width: Int, height: Int) -> CGContext? {
        CGContext(
            data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    func makeImage() -> CGImage? {
        var copy = pixels
        return copy.withUnsafeMutableBytes { raw in
            RGBABuffer.makeContext(raw.baseAddress, width: width, height: height)?.makeImage()
        }
    }

    var alphaMask: StickerMask {
        var alpha = [UInt8](repeating: 0, count: width * height)
        for index in 0..<alpha.count { alpha[index] = pixels[index * 4 + 3] }
        return StickerMask(width: width, height: height, alpha: alpha)
    }

    /// Maskeyle çarpar (ön çarpımlı olduğu için dört kanal birlikte).
    mutating func multiply(by mask: StickerMask) {
        precondition(mask.width == width && mask.height == height, "maske boyutu uyuşmuyor")
        for index in 0..<(width * height) {
            let a = UInt16(mask.alpha[index])
            if a == 255 { continue }
            let base = index * 4
            for channel in 0..<4 {
                pixels[base + channel] = UInt8((UInt16(pixels[base + channel]) * a + 127) / 255)
            }
        }
    }

    /// Bu tamponu `top` ile "üstüne" birleştirir (source-over, ön çarpımlı).
    mutating func composite(over bottom: RGBABuffer) {
        precondition(bottom.width == width && bottom.height == height)
        for index in 0..<(width * height) {
            let base = index * 4
            let inverse = 255 - UInt16(pixels[base + 3])
            for channel in 0..<4 {
                let value = UInt16(pixels[base + channel]) + (UInt16(bottom.pixels[base + channel]) * inverse + 127) / 255
                pixels[base + channel] = UInt8(min(255, value))
            }
        }
    }

    /// Düz renkli, saydamlığı maskeden gelen katman (kontur için).
    static func solid(red: UInt8, green: UInt8, blue: UInt8, mask: StickerMask) -> RGBABuffer {
        var buffer = RGBABuffer(width: mask.width, height: mask.height)
        for index in 0..<mask.alpha.count {
            let a = UInt16(mask.alpha[index])
            let base = index * 4
            buffer.pixels[base] = UInt8((UInt16(red) * a + 127) / 255)
            buffer.pixels[base + 1] = UInt8((UInt16(green) * a + 127) / 255)
            buffer.pixels[base + 2] = UInt8((UInt16(blue) * a + 127) / 255)
            buffer.pixels[base + 3] = UInt8(a)
        }
        return buffer
    }

    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let base = (y * width + x) * 4
        return (pixels[base], pixels[base + 1], pixels[base + 2], pixels[base + 3])
    }
}

// MARK: - Çıktı

struct StickerRenderOptions: Equatable {
    var outlineEnabled = true
    /// Çıktı pikseli cinsinden kontur kalınlığı.
    var outlineWidth: Double = 8
    var maxSide = StickerRenderer.maxSide

    static let outlineRange: ClosedRange<Double> = 2...20
}

enum StickerRenderError: LocalizedError, Equatable {
    case empty
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .empty: return "Sticker boş görünüyor. Silgiyle çok fazla silinmiş olabilir; Onar fırçasıyla geri getir."
        case .encodingFailed: return "Sticker kaydedilemedi."
        }
    }
}

struct StickerRenderResult {
    var image: CGImage
    var pngData: Data
    var width: Int { image.width }
    var height: Int { image.height }
}

enum StickerRenderer {
    /// WhatsApp / iMessage sticker'ları gibi en fazla 512×512.
    static let maxSide = 512
    /// Kontur dışında bırakılan kenar boşluğu (px).
    static let margin = 2

    /// Fotoğraf + maske + katmanlar → kırpılmış, sığdırılmış, isteğe bağlı beyaz konturlu şeffaf PNG.
    static func render(source: CGImage, mask: StickerMask, overlays: [StickerOverlay], options: StickerRenderOptions) throws -> StickerRenderResult {
        // 1) Çalışma boyutunda içerik: maskelenmiş fotoğraf + yazı/emoji.
        guard var masked = RGBABuffer(image: source, width: mask.width, height: mask.height) else { throw StickerRenderError.encodingFailed }
        masked.multiply(by: mask)
        guard let maskedImage = masked.makeImage() else { throw StickerRenderError.encodingFailed }
        let content = drawOverlays(on: maskedImage, overlays: overlays)

        // 2) Görünür içeriğin sınırı.
        guard let contentBuffer = RGBABuffer(image: content),
              let box = contentBuffer.alphaMask.boundingBox(threshold: 8) else { throw StickerRenderError.empty }

        // 3) 512'ye sığdır; kontur + boşluk kadar iç pay.
        let outline = options.outlineEnabled ? Int(options.outlineWidth.rounded(.up)) : 0
        let inset = outline + margin
        let layout = StickerGeometry.outputLayout(contentSize: box.size, maxSide: options.maxSide, inset: inset)
        guard layout.canvas.width > 0, let cropped = content.cropping(to: box) else { throw StickerRenderError.empty }

        var output = RGBABuffer(width: Int(layout.canvas.width), height: Int(layout.canvas.height))
        let drawRect = CGRect(
            x: CGFloat(inset), y: CGFloat(inset),
            width: (box.width * layout.scale).rounded(.down), height: (box.height * layout.scale).rounded(.down)
        )
        output.pixels.withUnsafeMutableBytes { raw in
            guard let context = RGBABuffer.makeContext(raw.baseAddress, width: output.width, height: output.height) else { return }
            context.interpolationQuality = .high
            // CGContext alt-soldan çizer; tampon sol üstten okunduğu için dikey konum çevrilir.
            context.draw(cropped, in: CGRect(x: drawRect.minX, y: CGFloat(output.height) - drawRect.maxY, width: drawRect.width, height: drawRect.height))
        }

        // 4) Beyaz kontur: içeriğin (yazılar dahil) saydamlığından mesafe alanıyla.
        if options.outlineEnabled, outline > 0 {
            let ring = output.alphaMask.outline(width: options.outlineWidth, threshold: 96)
            output.composite(over: RGBABuffer.solid(red: 255, green: 255, blue: 255, mask: ring))
        }

        guard let image = output.makeImage(), let png = pngData(image) else { throw StickerRenderError.encodingFailed }
        return StickerRenderResult(image: image, pngData: png)
    }

    /// Yazı ve emojiler (yazıya ince koyu gölge: beyaz yazı beyaz konturda kaybolmasın).
    static func drawOverlays(on image: CGImage, overlays: [StickerOverlay]) -> CGImage {
        guard !overlays.isEmpty else { return image }
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
            for overlay in overlays where !overlay.text.trimmingCharacters(in: .whitespaces).isEmpty {
                let string = overlay.attributedString(forImageWidth: size.width)
                let textSize = string.size()
                let origin = CGPoint(x: overlay.center.x * size.width - textSize.width / 2,
                                     y: overlay.center.y * size.height - textSize.height / 2)
                if overlay.kind == .text {
                    context.cgContext.setShadow(offset: .zero, blur: max(2, textSize.height * 0.06), color: UIColor.black.withAlphaComponent(0.45).cgColor)
                }
                string.draw(at: origin)
                context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            }
        }
        return rendered.cgImage ?? image
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Düzenleme önizlemesi: maskelenmiş fotoğraf (katmanlar SwiftUI'da ayrıca çizilir).
    static func maskedPreview(source: RGBABuffer, mask: StickerMask) -> CGImage? {
        var copy = source
        copy.multiply(by: mask)
        return copy.makeImage()
    }
}

// MARK: - Çalışma görüntüsü

enum StickerImageLoader {
    /// Düzenleme için en fazla bu boyut (çıktı 512 olduğu için fazlası gereksiz yük).
    static let workingMaxSide: CGFloat = 1024

    /// Veriden yönü uygulanmış, küçültülmüş CGImage.
    static func workingImage(from data: Data, maxSide: CGFloat = workingMaxSide) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
