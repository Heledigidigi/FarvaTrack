import XCTest
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
