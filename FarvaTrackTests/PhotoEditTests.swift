import XCTest
import UIKit
@testable import FarvaTrack

final class PhotoEditTests: XCTestCase {
    func testNewDocumentIsUnedited() {
        var document = PhotoEditDocument()
        XCTAssertFalse(document.isEdited, "dokunulmamış fotoğraf orijinal dosyayla gider")
        document.crop = CGRect(x: 0.1, y: 0, width: 0.9, height: 1)
        XCTAssertTrue(document.isEdited)
        document.crop = PhotoEditDocument.fullCrop
        document.layers.append(PhotoEditLayer(content: .text("Merhaba", colorIndex: 0), center: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertTrue(document.isEdited)
    }

    func testDisplayImageRoundTripWithCrop() {
        let crop = CGRect(x: 0.2, y: 0.1, width: 0.5, height: 0.4)
        let size = CGSize(width: 300, height: 200)
        let image = PhotoEditGeometry.toImage(CGPoint(x: 150, y: 100), displaySize: size, crop: crop)
        XCTAssertEqual(image.x, 0.45, accuracy: 1e-9)
        XCTAssertEqual(image.y, 0.3, accuracy: 1e-9)
        let back = PhotoEditGeometry.toDisplay(image, displaySize: size, crop: crop)
        XCTAssertEqual(back.x, 150, accuracy: 1e-9)
        XCTAssertEqual(back.y, 100, accuracy: 1e-9)
        let full = PhotoEditGeometry.fullDisplaySize(displaySize: size, crop: crop)
        XCTAssertEqual(full.width, 600, accuracy: 1e-9)
        XCTAssertEqual(full.height, 500, accuracy: 1e-9)
    }

    func testFittedAndAspect() {
        let fitted = PhotoEditGeometry.fitted(aspect: 0.75, in: CGSize(width: 400, height: 400))
        XCTAssertEqual(fitted.width, 300, accuracy: 1e-9)
        XCTAssertEqual(fitted.height, 400, accuracy: 1e-9)
        let aspect = PhotoEditGeometry.aspect(of: CGRect(x: 0, y: 0, width: 0.5, height: 1), imageSize: CGSize(width: 4000, height: 3000))
        XCTAssertEqual(aspect, 2000.0 / 3000.0, accuracy: 1e-9)
    }

    func testCropAdjustStaysInsideAndKeepsMinimum() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let moved = PhotoEditGeometry.adjust(start, handle: .move, translation: CGSize(width: 0.5, height: -0.5))
        XCTAssertEqual(moved.minX, 0.4, accuracy: 1e-9, "sağ kenar 1'de durur")
        XCTAssertEqual(moved.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(moved.size, start.size)

        let shrunk = PhotoEditGeometry.adjust(start, handle: .topLeft, translation: CGSize(width: 0.9, height: 0.9))
        XCTAssertEqual(shrunk.width, PhotoEditGeometry.minimumCropSide, accuracy: 1e-9)
        XCTAssertEqual(shrunk.maxX, start.maxX, accuracy: 1e-9)

        let grown = PhotoEditGeometry.adjust(start, handle: .bottomRight, translation: CGSize(width: 1, height: 1))
        XCTAssertEqual(grown.maxX, 1, accuracy: 1e-9)
        XCTAssertEqual(grown.maxY, 1, accuracy: 1e-9)
    }

    func testPixelRectIsIntegralAndInside() {
        let rect = PhotoEditGeometry.pixelRect(crop: CGRect(x: 0.333, y: 0.5, width: 0.7, height: 0.6), pixelSize: CGSize(width: 1000, height: 800))
        XCTAssertEqual(rect.minX, 333)
        XCTAssertEqual(rect.maxX, 1000, "resmin dışına taşmaz")
        XCTAssertEqual(rect.maxY, 800)
    }

    func testEraserHitsNearbyStrokesOnly() {
        let near = PhotoEditStroke(points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)], colorIndex: 0, width: 0.01)
        let far = PhotoEditStroke(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.1)], colorIndex: 0, width: 0.01)
        let dot = PhotoEditStroke(points: [CGPoint(x: 0.52, y: 0.52)], colorIndex: 0, width: 0.01)
        let hit = PhotoEditGeometry.strokesHit([near, far, dot], at: CGPoint(x: 0.5, y: 0.51), radius: 0.03, heightOverWidth: 1)
        XCTAssertEqual(hit, [near.id, dot.id])
        // Dikey eksen genişlik birimine çevrilir: yüksek bir resimde aynı oran daha uzak demektir.
        let tall = PhotoEditGeometry.strokesHit([near], at: CGPoint(x: 0.5, y: 0.52), radius: 0.03, heightOverWidth: 2)
        XCTAssertTrue(tall.isEmpty)
    }

    func testSendQualityFollowsDataSaver() {
        let defaults = UserDefaults(suiteName: "PhotoEditTests.\(UUID().uuidString)")!
        XCTAssertEqual(ChatMediaPreferences.sendQuality(defaults), .original, "varsayılan orijinal")
        defaults.set(true, forKey: ChatMediaPreferences.dataSaverKey)
        XCTAssertEqual(ChatMediaPreferences.sendQuality(defaults), .fast)
    }

    func testStickerDragPayloadRoundTrip() {
        XCTAssertEqual(StickerDragPayload.stickerID(from: StickerDragPayload.text(for: "abc")), "abc")
        XCTAssertNil(StickerDragPayload.stickerID(from: "abc"), "başka uygulamadan gelen yazı sticker değildir")
        XCTAssertNil(StickerDragPayload.stickerID(from: StickerDragPayload.prefix))
    }
}

final class PhotoEditToolTests: XCTestCase {
    func testEdgeHandlesMoveOnlyOneSide() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let top = PhotoEditGeometry.adjust(start, handle: .top, translation: CGSize(width: 0.3, height: -0.1))
        XCTAssertEqual(top.minX, 0.2, accuracy: 1e-9, "üst kenar yatayda oynamaz")
        XCTAssertEqual(top.minY, 0.1, accuracy: 1e-9)
        XCTAssertEqual(top.maxY, 0.8, accuracy: 1e-9)
        let right = PhotoEditGeometry.adjust(start, handle: .right, translation: CGSize(width: 0.5, height: 0.2))
        XCTAssertEqual(right.maxX, 1, accuracy: 1e-9, "resmin dışına çıkmaz")
        XCTAssertEqual(right.minY, 0.2, accuracy: 1e-9)
        let squeezed = PhotoEditGeometry.adjust(start, handle: .left, translation: CGSize(width: 0.9, height: 0))
        XCTAssertEqual(squeezed.width, PhotoEditGeometry.minimumCropSide, accuracy: 1e-9)
    }

    func testLayerGesturePiecesAccumulate() {
        var layer = PhotoEditLayer(content: .sticker(id: "s", aspect: 1), center: CGPoint(x: 0.5, y: 0.5))
        // Taşırken döndürme ve büyütme aynı anda gelir; hiçbiri diğerini geri almaz.
        layer = layer.applying(translation: CGSize(width: 0.1, height: 0), scale: 1, rotation: 0)
        layer = layer.applying(translation: .zero, scale: 1.5, rotation: 0.3)
        layer = layer.applying(translation: CGSize(width: 0, height: 0.1), scale: 1, rotation: 0.2)
        XCTAssertEqual(layer.center.x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(layer.center.y, 0.6, accuracy: 1e-9)
        XCTAssertEqual(layer.scale, 1.5, accuracy: 1e-9)
        XCTAssertEqual(layer.rotation, 0.5, accuracy: 1e-9)
        XCTAssertEqual(layer.applying(translation: .zero, scale: 100, rotation: 0).scale, PhotoEditLayer.scaleRange.upperBound)
    }

    func testBrushOffsetMovesDrawPointUp() {
        let settings = PhotoEditBrushSettings(size: 10, offset: 40)
        XCTAssertEqual(settings.drawPoint(forTouch: CGPoint(x: 100, y: 200)), CGPoint(x: 100, y: 160))
        XCTAssertEqual(PhotoEditBrushSettings().drawPoint(forTouch: CGPoint(x: 5, y: 5)), CGPoint(x: 5, y: 5))
        let legacy = PhotoEditStroke(points: [.zero], colorIndex: 2, width: 0.01)
        XCTAssertEqual(legacy.color, PhotoEditColor.legacy(2))
        XCTAssertFalse(legacy.isEraser)
    }

    func testPixelSamplerReadsColors() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 1), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).image { context in
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            UIColor(red: 0, green: 0, blue: 1, alpha: 1).setFill()
            context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        }
        let sampler = try XCTUnwrap(image.cgImage.flatMap(PhotoEditPixelSampler.init(cgImage:)))
        let left = sampler.color(atUnit: CGPoint(x: 0.1, y: 0.5))
        let right = sampler.color(atUnit: CGPoint(x: 0.9, y: 0.5))
        XCTAssertGreaterThan(left.red, 0.9)
        XCTAssertLessThan(left.blue, 0.1)
        XCTAssertGreaterThan(right.blue, 0.9)
        // Dışarıdaki nokta kenar pikseline sabitlenir.
        XCTAssertEqual(sampler.color(atUnit: CGPoint(x: 5, y: -3)), right)
    }
}
