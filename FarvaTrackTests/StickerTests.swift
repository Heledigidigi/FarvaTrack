import XCTest
import SwiftData
import UIKit
import ImageIO
import CoreVideo
@testable import FarvaTrack

// MARK: - Yardımcılar

private func makeImage(width: Int, height: Int, color: UIColor = .systemRed) -> CGImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    format.preferredRange = .standard
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }.cgImage!
}

/// Ortasında `radius` yarıçaplı dolu daire olan maske.
private func circleMask(width: Int, height: Int, center: CGPoint, radius: Double) -> StickerMask {
    var mask = StickerMask(width: width, height: height, fill: 0)
    mask.stamp(at: center, brush: StickerBrush(mode: .restore, radius: radius, softness: 0))
    return mask
}

private func decodePNG(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// MARK: - Maske ve fırça

final class StickerMaskTests: XCTestCase {
    func testBasicsAndBoundingBox() {
        var mask = StickerMask(width: 10, height: 6, fill: 0)
        XCTAssertTrue(mask.isEmpty)
        XCTAssertNil(mask.boundingBox())
        mask[2, 1] = 255
        mask[7, 4] = 200
        mask[9, 5] = 5  // eşiğin altında
        XCTAssertFalse(mask.isEmpty)
        XCTAssertEqual(mask.boundingBox(threshold: 8), CGRect(x: 2, y: 1, width: 6, height: 4))
        XCTAssertEqual(StickerMask(width: 4, height: 4).coverage, 1)
        XCTAssertEqual(StickerMask(width: 4, height: 4, fill: 0).coverage, 0)
    }

    func testBrushWeightHardAndSoft() {
        XCTAssertEqual(StickerBrush.weight(distance: 0, radius: 10, softness: 0), 1)
        XCTAssertEqual(StickerBrush.weight(distance: 9.9, radius: 10, softness: 0), 1, "sert fırça kenara kadar tam")
        XCTAssertEqual(StickerBrush.weight(distance: 10, radius: 10, softness: 0), 0)
        XCTAssertEqual(StickerBrush.weight(distance: 3, radius: 0, softness: 0.5), 0)

        // Yumuşak: merkez tam, kenara doğru azalır.
        XCTAssertEqual(StickerBrush.weight(distance: 0, radius: 10, softness: 1), 1, accuracy: 0.001)
        let near = StickerBrush.weight(distance: 3, radius: 10, softness: 1)
        let far = StickerBrush.weight(distance: 8, radius: 10, softness: 1)
        XCTAssertGreaterThan(near, far)
        XCTAssertGreaterThan(far, 0)
        XCTAssertLessThan(near, 1)
        // Yarı yumuşak: çekirdek (yarıçapın yarısı) tam.
        XCTAssertEqual(StickerBrush.weight(distance: 4.9, radius: 10, softness: 0.5), 1)
        XCTAssertLessThan(StickerBrush.weight(distance: 7, radius: 10, softness: 0.5), 1)
    }

    func testHardEraseAndRestore() {
        var mask = StickerMask(width: 50, height: 50)
        let center = CGPoint(x: 25, y: 25)
        mask.stamp(at: center, brush: StickerBrush(mode: .erase, radius: 10, softness: 0))
        XCTAssertEqual(mask[25, 25], 0)
        XCTAssertEqual(mask[25, 33], 0)
        XCTAssertEqual(mask[25, 40], 255, "fırça dışı değişmez")
        XCTAssertEqual(mask[0, 0], 255)
        // Silinen alan ≈ πr²
        let erased = mask.alpha.filter { $0 == 0 }.count
        XCTAssertEqual(Double(erased), Double.pi * 100, accuracy: 25)

        mask.stamp(at: center, brush: StickerBrush(mode: .restore, radius: 12, softness: 0))
        XCTAssertEqual(mask.alpha.filter { $0 != 255 }.count, 0, "onar fırçası geri getirir")
    }

    func testSoftEraseLeavesGradient() {
        var mask = StickerMask(width: 41, height: 41)
        mask.stamp(at: CGPoint(x: 20.5, y: 20.5), brush: StickerBrush(mode: .erase, radius: 20, softness: 1))
        XCTAssertLessThan(mask[20, 20], 5)
        let mid = mask[20, 32]
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 255)
        XCTAssertGreaterThan(mask[20, 38], mid, "kenara doğru daha az silinir")
    }

    func testStrokeHasNoGapsOnFastMoves() {
        var mask = StickerMask(width: 60, height: 20)
        mask.stroke(from: CGPoint(x: 5, y: 10), to: CGPoint(x: 55, y: 10), brush: StickerBrush(mode: .erase, radius: 3, softness: 0))
        for x in 5...55 {
            XCTAssertEqual(mask[x, 10], 0, "x=\(x) boşluk kalmamalı")
        }
        XCTAssertEqual(mask[30, 17], 255)
    }

    func testStampOutsideImageIsSafe() {
        var mask = StickerMask(width: 10, height: 10)
        mask.stamp(at: CGPoint(x: -50, y: -50), brush: StickerBrush(mode: .erase, radius: 5, softness: 0))
        mask.stamp(at: CGPoint(x: 9.5, y: 9.5), brush: StickerBrush(mode: .erase, radius: 30, softness: 0))
        XCTAssertTrue(mask.isEmpty)
        var empty = StickerMask(width: 0, height: 0)
        empty.stamp(at: .zero, brush: StickerBrush(mode: .erase, radius: 3, softness: 0))
        XCTAssertNil(empty.boundingBox())
    }

    func testDistanceFieldApproximatesEuclidean() {
        var mask = StickerMask(width: 21, height: 21, fill: 0)
        mask[10, 10] = 255
        let field = mask.distanceField()
        func d(_ x: Int, _ y: Int) -> Float { field[y * 21 + x] }
        XCTAssertEqual(d(10, 10), 0)
        XCTAssertEqual(d(11, 10), 1)
        XCTAssertEqual(d(11, 11), 1.414, accuracy: 0.01)
        XCTAssertEqual(d(15, 10), 5, accuracy: 0.01)
        XCTAssertEqual(d(14, 13), 5, accuracy: 0.5, "çapraz yönde de yaklaşık Öklid")
        XCTAssertEqual(d(0, 0), 14.14, accuracy: 0.6)
    }

    func testOutlineSurroundsShape() {
        var mask = StickerMask(width: 40, height: 40, fill: 0)
        for y in 15..<25 { for x in 15..<25 { mask[x, y] = 255 } }
        let ring = mask.outline(width: 4)
        XCTAssertEqual(ring[20, 20], 255, "şeklin içi de kapsanır (altına çizilir)")
        XCTAssertEqual(ring[13, 20], 255, "2 px dışarısı kontur")
        XCTAssertEqual(ring[12, 20], 255, "3 px dışarısı kontur")
        // Tam 4 px: kenar yumuşatılır (yarı saydam), 5 px ve ötesi boş.
        XCTAssertGreaterThan(ring[11, 20], 0, "kenar yumuşak geçiş")
        XCTAssertLessThan(ring[11, 20], 255)
        XCTAssertEqual(ring[10, 20], 0)
        XCTAssertEqual(ring[5, 20], 0, "kalınlığın dışı boş")
        XCTAssertTrue(mask.outline(width: 0).isEmpty)
    }
}

// MARK: - Geometri ve geri al

final class StickerGeometryTests: XCTestCase {
    func testBrushPointIsAboveFinger() {
        XCTAssertEqual(StickerGeometry.brushPoint(forTouch: CGPoint(x: 100, y: 300)), CGPoint(x: 100, y: 300 - StickerGeometry.brushOffset))
        XCTAssertEqual(StickerGeometry.brushPoint(forTouch: CGPoint(x: 10, y: 10), offset: 0), CGPoint(x: 10, y: 10))
    }

    func testViewToImageConversionFollowsZoom() {
        let frame = CGRect(x: 100, y: 50, width: 200, height: 100)
        let pixels = CGSize(width: 1000, height: 500)
        XCTAssertEqual(StickerGeometry.imagePoint(fromView: CGPoint(x: 200, y: 100), imageFrame: frame, pixelSize: pixels), CGPoint(x: 500, y: 250))
        XCTAssertEqual(StickerGeometry.imagePoint(fromView: CGPoint(x: 100, y: 50), imageFrame: frame, pixelSize: pixels), .zero)
        // Yakınlaştırınca aynı ekran çapı daha az piksel kaplar.
        XCTAssertEqual(StickerGeometry.pixelRadius(forDiameter: 40, imageFrame: frame, pixelSize: pixels), 100)
        let zoomed = CGRect(x: 0, y: 0, width: 800, height: 400)
        XCTAssertEqual(StickerGeometry.pixelRadius(forDiameter: 40, imageFrame: zoomed, pixelSize: pixels), 25)
        XCTAssertEqual(StickerGeometry.imagePoint(fromView: .zero, imageFrame: .zero, pixelSize: pixels), .zero)
    }

    func testAspectFit() {
        let rect = StickerGeometry.aspectFit(CGSize(width: 400, height: 200), in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(rect, CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    func testOutputLayoutFitsWithin512() {
        let big = StickerGeometry.outputLayout(contentSize: CGSize(width: 1000, height: 500), maxSide: 512, inset: 10)
        XCTAssertEqual(big.canvas.width, 512)
        XCTAssertLessThanOrEqual(big.canvas.height, 512)
        XCTAssertEqual(big.scale, 492.0 / 1000, accuracy: 0.0001)

        let small = StickerGeometry.outputLayout(contentSize: CGSize(width: 100, height: 50), maxSide: 512, inset: 10)
        XCTAssertEqual(small.scale, 1, "küçük içerik büyütülmez")
        XCTAssertEqual(small.canvas, CGSize(width: 120, height: 70))
    }

    func testUndoStack() {
        var stack = UndoStack<Int>(limit: 3)
        XCTAssertFalse(stack.canUndo)
        stack.record(1)
        stack.record(1)
        XCTAssertEqual(stack.past, [1], "aynı hal iki kez kaydedilmez")
        stack.record(2)
        XCTAssertEqual(stack.undo(current: 3), 2)
        XCTAssertEqual(stack.undo(current: 2), 1)
        XCTAssertNil(stack.undo(current: 1))
        XCTAssertEqual(stack.redo(current: 1), 2)
        XCTAssertTrue(stack.canRedo)
        stack.record(9)
        XCTAssertFalse(stack.canRedo, "yeni değişiklik ileri al geçmişini siler")

        for value in 10...20 { stack.record(value) }
        XCTAssertEqual(stack.past.count, 3, "sınır")
        XCTAssertEqual(stack.discardLast(), 20)
        XCTAssertFalse(stack.canRedo, "iptal ileri al'a eklenmez")
    }
}

// MARK: - Tampon ve çıktı

final class StickerRenderTests: XCTestCase {
    func testBufferMultiplyAndComposite() throws {
        var buffer = try XCTUnwrap(RGBABuffer(image: makeImage(width: 4, height: 1, color: .white)))
        var mask = StickerMask(width: 4, height: 1, fill: 255)
        mask[1, 0] = 0
        mask[2, 0] = 128
        buffer.multiply(by: mask)
        XCTAssertEqual(buffer.pixel(x: 0, y: 0).a, 255)
        XCTAssertEqual(buffer.pixel(x: 1, y: 0).a, 0)
        XCTAssertEqual(buffer.pixel(x: 1, y: 0).r, 0, "ön çarpımlı: renk de sıfırlanır")
        XCTAssertEqual(Int(buffer.pixel(x: 2, y: 0).a), 128)

        let red = RGBABuffer.solid(red: 255, green: 0, blue: 0, mask: StickerMask(width: 4, height: 1))
        buffer.composite(over: red)
        XCTAssertEqual(buffer.pixel(x: 1, y: 0).r, 255, "saydam yerden alttaki görünür")
        XCTAssertEqual(buffer.pixel(x: 1, y: 0).g, 0)
        XCTAssertEqual(buffer.pixel(x: 0, y: 0).g, 255, "opak üst katman örter")
        XCTAssertEqual(buffer.pixel(x: 2, y: 0).a, 255)
    }

    func testRenderCropsToShapeWithTransparentBackground() throws {
        let source = makeImage(width: 200, height: 100)
        let mask = circleMask(width: 200, height: 100, center: CGPoint(x: 60, y: 50), radius: 20)
        var options = StickerRenderOptions()
        options.outlineEnabled = false

        let result = try StickerRenderer.render(source: source, mask: mask, overlays: [], options: options)
        XCTAssertEqual(result.width, 40 + 2 * StickerRenderer.margin, "sınır kutusuna kırpılır")
        XCTAssertEqual(result.height, 40 + 2 * StickerRenderer.margin)

        let decoded = try XCTUnwrap(decodePNG(result.pngData))
        XCTAssertNotEqual(decoded.alphaInfo, .none, "PNG saydam")
        let pixels = try XCTUnwrap(RGBABuffer(image: decoded))
        XCTAssertEqual(pixels.pixel(x: 0, y: 0).a, 0, "köşe saydam")
        let center = pixels.pixel(x: result.width / 2, y: result.height / 2)
        XCTAssertEqual(center.a, 255)
        XCTAssertGreaterThan(center.r, 200)
        XCTAssertLessThan(center.g, 80)
    }

    func testOutlineIsWhiteAroundShape() throws {
        let source = makeImage(width: 200, height: 200)
        let mask = circleMask(width: 200, height: 200, center: CGPoint(x: 100, y: 100), radius: 30)
        var options = StickerRenderOptions()
        options.outlineWidth = 8

        let result = try StickerRenderer.render(source: source, mask: mask, overlays: [], options: options)
        XCTAssertEqual(result.width, 60 + 2 * (8 + StickerRenderer.margin))
        let pixels = try XCTUnwrap(RGBABuffer(image: result.image))
        let inset = 8 + StickerRenderer.margin
        // Şeklin hemen solu (dairenin kenarının 4 px dışı): beyaz kontur.
        let ring = pixels.pixel(x: inset - 4, y: result.height / 2)
        XCTAssertEqual(ring.a, 255)
        XCTAssertEqual(ring.r, 255)
        XCTAssertEqual(ring.g, 255)
        XCTAssertEqual(ring.b, 255)
        // İç kısım kırmızı kalır.
        let inside = pixels.pixel(x: result.width / 2, y: result.height / 2)
        XCTAssertLessThan(inside.g, 80)
        XCTAssertEqual(pixels.pixel(x: 0, y: 0).a, 0)
    }

    func testLargeContentIsLimitedTo512() throws {
        let source = makeImage(width: 1024, height: 768)
        let result = try StickerRenderer.render(source: source, mask: StickerMask(width: 1024, height: 768), overlays: [], options: StickerRenderOptions())
        XCTAssertEqual(result.width, 512)
        XCTAssertLessThanOrEqual(result.height, 512)
        XCTAssertGreaterThan(result.height, 300, "en-boy oranı korunur")
    }

    func testEmptyMaskThrows() {
        let source = makeImage(width: 50, height: 50)
        XCTAssertThrowsError(try StickerRenderer.render(source: source, mask: StickerMask(width: 50, height: 50, fill: 0), overlays: [], options: StickerRenderOptions())) { error in
            XCTAssertEqual(error as? StickerRenderError, .empty)
        }
    }

    func testOverlaysAreIncludedInCrop() throws {
        let source = makeImage(width: 400, height: 400)
        let mask = circleMask(width: 400, height: 400, center: CGPoint(x: 100, y: 100), radius: 20)
        var options = StickerRenderOptions()
        options.outlineEnabled = false
        let plain = try StickerRenderer.render(source: source, mask: mask, overlays: [], options: options)
        var emoji = StickerOverlay.emoji("🔥")
        emoji.center = CGPoint(x: 0.8, y: 0.8)
        let withEmoji = try StickerRenderer.render(source: source, mask: mask, overlays: [emoji], options: options)
        XCTAssertGreaterThan(withEmoji.width, plain.width * 3, "emoji maskenin dışında olsa da sticker'a girer")

        // Maske tamamen silinse de yalnızca yazıdan sticker olur.
        let textOnly = try StickerRenderer.render(source: source, mask: StickerMask(width: 400, height: 400, fill: 0), overlays: [.text("Merhaba")], options: StickerRenderOptions())
        XCTAssertGreaterThan(textOnly.width, 50)
    }

    func testWorkingImageIsDownscaled() throws {
        let image = UIImage(cgImage: makeImage(width: 3000, height: 1500))
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let working = try XCTUnwrap(StickerImageLoader.workingImage(from: data))
        XCTAssertEqual(max(working.width, working.height), Int(StickerImageLoader.workingMaxSide))
        XCTAssertNil(StickerImageLoader.workingImage(from: Data("resim değil".utf8)))
    }
}

// MARK: - Vision maskesi dönüşümü

final class StickerSegmenterTests: XCTestCase {
    func testFloatPixelBufferIsScaledToImageSize() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 2, kCVPixelFormatType_OneComponent32Float, nil, &buffer)
        let pixelBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let values: [[Float]] = [[0, 1, 0.5, 2], [1, 1, -1, 0]]
        for y in 0..<2 {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<4 { row[x] = values[y][x] }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let mask = try VisionStickerSegmenter.mask(from: pixelBuffer, width: 8, height: 4)
        XCTAssertEqual(mask.width, 8)
        XCTAssertEqual(mask.height, 4)
        XCTAssertEqual(mask[0, 0], 0)
        XCTAssertEqual(mask[2, 0], 255)
        XCTAssertEqual(mask[4, 0], 128)
        XCTAssertEqual(mask[6, 1], 255, "1'in üstü sınırlanır")
        XCTAssertEqual(mask[4, 3], 0, "negatif sınırlanır")
        XCTAssertEqual(mask[0, 2], 255)
    }
}

// MARK: - Editör

struct MockSegmenter: StickerSegmenting {
    var result: Result<StickerMask?, Error>

    func foregroundMask(for image: CGImage) async throws -> StickerMask {
        switch result {
        case .success(let mask?): return mask
        case .success(nil): return circleMask(width: image.width, height: image.height, center: CGPoint(x: image.width / 2, y: image.height / 2), radius: Double(min(image.width, image.height)) / 4)
        case .failure(let error): throw error
        }
    }
}

@MainActor
final class StickerEditorViewModelTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000)

    private func makeSUT(_ result: Result<StickerMask?, Error> = .success(nil)) -> StickerEditorViewModel {
        StickerEditorViewModel(segmenter: MockSegmenter(result: result), clock: { [unowned self] in self.now }, finalPreviewDelay: .zero)
    }

    func testLoadUsesAutomaticMask() async {
        let sut = makeSUT()
        await sut.load(image: makeImage(width: 120, height: 80))
        XCTAssertEqual(sut.phase, .editing)
        XCTAssertEqual(sut.pixelSize, CGSize(width: 120, height: 80))
        XCTAssertLessThan(sut.mask.coverage, 0.5, "arka plan kaldırıldı")
        XCTAssertTrue(sut.hasAutomaticMask)
        XCTAssertNotNil(sut.preview)
        XCTAssertNil(sut.notice)
        XCTAssertFalse(sut.canUndo)
    }

    func testSegmentationFailureFallsBackToWholePhoto() async {
        let sut = makeSUT(.failure(StickerSegmentationError.noSubject))
        await sut.load(image: makeImage(width: 50, height: 50))
        XCTAssertEqual(sut.phase, .editing)
        XCTAssertEqual(sut.mask.coverage, 1)
        XCTAssertFalse(sut.hasAutomaticMask)
        XCTAssertEqual(sut.notice, StickerSegmentationError.noSubject.errorDescription)

        let wrongSize = makeSUT(.success(StickerMask(width: 3, height: 3)))
        await wrongSize.load(image: makeImage(width: 50, height: 50))
        XCTAssertEqual(wrongSize.mask.width, 50)
        XCTAssertNotNil(wrongSize.notice)
    }

    func testBadImageDataShowsError() async {
        let sut = makeSUT()
        await sut.load(imageData: Data("x".utf8))
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertEqual(sut.phase, .idle)
    }

    func testStrokeEraseRestoreWithUndoRedo() async {
        let sut = makeSUT(.success(StickerMask(width: 100, height: 100)))
        await sut.load(image: makeImage(width: 100, height: 100))
        sut.tool = .erase
        sut.softness = 0
        sut.beginStroke(at: CGPoint(x: 10, y: 50), radius: 5)
        sut.continueStroke(to: CGPoint(x: 90, y: 50), radius: 5)
        sut.endStroke()
        XCTAssertEqual(sut.mask[50, 50], 0)
        XCTAssertEqual(sut.mask[50, 10], 255)
        XCTAssertTrue(sut.canUndo)

        sut.undo()
        XCTAssertEqual(sut.mask[50, 50], 255, "tüm darbe tek adımda geri alınır")
        XCTAssertTrue(sut.canRedo)
        sut.redo()
        XCTAssertEqual(sut.mask[50, 50], 0)

        sut.tool = .restore
        sut.beginStroke(at: CGPoint(x: 50, y: 50), radius: 8)
        sut.endStroke()
        XCTAssertEqual(sut.mask[50, 50], 255)
    }

    func testCancelledStrokeIsRevertedWithoutRedo() async {
        let sut = makeSUT(.success(StickerMask(width: 60, height: 60)))
        await sut.load(image: makeImage(width: 60, height: 60))
        sut.beginStroke(at: CGPoint(x: 30, y: 30), radius: 6)
        XCTAssertTrue(sut.isStroking)
        sut.cancelStroke()
        XCTAssertFalse(sut.isStroking)
        XCTAssertEqual(sut.mask.coverage, 1, "yakınlaştırma için iki parmak gelince boyama geri alınır")
        XCTAssertFalse(sut.canUndo)
        XCTAssertFalse(sut.canRedo)
    }

    func testMoveToolDoesNotPaint() async {
        let sut = makeSUT(.success(StickerMask(width: 40, height: 40)))
        await sut.load(image: makeImage(width: 40, height: 40))
        sut.tool = .move
        sut.beginStroke(at: CGPoint(x: 20, y: 20), radius: 10)
        sut.continueStroke(to: CGPoint(x: 30, y: 20), radius: 10)
        sut.endStroke()
        XCTAssertEqual(sut.mask.coverage, 1)
        XCTAssertFalse(sut.canUndo)
    }

    func testPreviewIsThrottledDuringStroke() async {
        let sut = makeSUT(.success(StickerMask(width: 40, height: 40)))
        await sut.load(image: makeImage(width: 40, height: 40))
        let initial = sut.preview
        sut.beginStroke(at: CGPoint(x: 5, y: 5), radius: 3)
        let afterBegin = sut.preview
        XCTAssertTrue(afterBegin === initial, "aynı anda ikinci yenileme yapılmaz")
        sut.endStroke()
        XCTAssertFalse(sut.preview === initial, "darbe bitince önizleme yenilenir")
    }

    func testOverlaysAddMoveRemoveAndUndo() async {
        let sut = makeSUT()
        await sut.load(image: makeImage(width: 100, height: 100))
        sut.addOverlay(.text("   "))
        XCTAssertTrue(sut.overlays.isEmpty, "boş yazı eklenmez")

        let text = StickerOverlay.text("Selam")
        sut.addOverlay(text)
        XCTAssertEqual(sut.selectedOverlayID, text.id)
        sut.beginOverlayChange()
        sut.updateOverlay(text.id, center: CGPoint(x: 1.4, y: -0.2), relativeSize: 2, colorHex: "#111111")
        sut.endOverlayChange()
        XCTAssertEqual(sut.overlays.first?.center, CGPoint(x: 1, y: 0), "görüntü içinde kalır")
        XCTAssertEqual(sut.overlays.first?.relativeSize, 0.45)
        XCTAssertEqual(sut.overlays.first?.colorHex, "#111111")

        sut.undo()
        XCTAssertEqual(sut.overlays.first?.center, text.center, "taşıma tek adımda geri alınır")
        sut.addOverlay(.emoji("🔥"))
        XCTAssertEqual(sut.overlays.count, 2)
        sut.removeOverlay(text.id)
        XCTAssertEqual(sut.overlays.map(\.text), ["🔥"])
        sut.undo()
        XCTAssertEqual(sut.overlays.count, 2)
    }

    func testResetMask() async {
        let sut = makeSUT()
        await sut.load(image: makeImage(width: 80, height: 80))
        let automatic = sut.mask
        sut.resetMask(toAutomatic: false)
        XCTAssertEqual(sut.mask.coverage, 1)
        sut.resetMask(toAutomatic: true)
        XCTAssertEqual(sut.mask, automatic)
        sut.undo()
        XCTAssertEqual(sut.mask.coverage, 1)
    }

    func testRenderAndFinalPreview() async throws {
        let sut = makeSUT()
        await sut.load(image: makeImage(width: 300, height: 300))
        // Hata ayıklama derlemesinde (testler) piksel döngüleri yavaştır; 5 sn'ye kadar beklenir.
        for _ in 0..<250 {
            if sut.finalPreview != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(sut.finalPreview, "konturlu son hal önizlemesi hazırlanır")

        let result = try await sut.render()
        XCTAssertLessThanOrEqual(max(result.width, result.height), 512)
        XCTAssertNotNil(decodePNG(result.pngData))
        XCTAssertEqual(sut.phase, .editing)

        sut.resetMask(toAutomatic: false)
        sut.tool = .erase
        sut.softness = 0
        sut.beginStroke(at: CGPoint(x: 150, y: 150), radius: 400)
        sut.endStroke()
        do {
            _ = try await sut.render()
            XCTFail("boş sticker kaydedilmemeli")
        } catch {
            XCTAssertEqual(error as? StickerRenderError, .empty)
        }
    }
}

// MARK: - Kütüphane

final class MockStickerSync: StickerSyncing {
    var remote: [StickerDTO] = []
    var offline = false
    private(set) var uploaded: [String] = []
    private(set) var deleted: [String] = []
    private(set) var downloaded: [String] = []

    func upload(pngAt fileURL: URL, sticker: StickerDTO, userID: String) async throws {
        if offline { throw AppError.network }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(sticker.storagePath, "users/\(userID)/stickers/\(sticker.id).png")
        uploaded.append(sticker.id)
        remote.append(sticker)
    }

    func fetchAll(userID: String) async throws -> [StickerDTO] {
        if offline { throw AppError.network }
        return remote
    }

    func download(sticker: StickerDTO, to destination: URL) async throws {
        downloaded.append(sticker.id)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("png".utf8).write(to: destination)
    }

    func delete(sticker id: String, storagePath: String, userID: String) async throws {
        if offline { throw AppError.network }
        deleted.append(id)
        remote.removeAll { $0.id == id }
    }

    func purge(userID: String) async throws {}
}

@MainActor
final class StickerLibraryViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockStickerSync!
    private var root: URL!
    private var sut: StickerLibraryViewModel!
    private var counter = 0

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: StickerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sync = MockStickerSync()
        root = makeTemporaryDirectory()
        counter = 0
        sut = StickerLibraryViewModel(
            sync: sync, files: StickerFiles(root: root), defaults: makeTestDefaults("stickers.\(name)"),
            clock: { Date(timeIntervalSince1970: 2_000) },
            makeID: { [unowned self] in
                self.counter += 1
                return "s\(self.counter)"
            }
        )
        sut.configure(context: container.mainContext, userID: "me")
    }

    override func tearDown() async throws {
        await settleTasks()
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func result() throws -> StickerRenderResult {
        try StickerRenderer.render(source: makeImage(width: 64, height: 64), mask: StickerMask(width: 64, height: 64), overlays: [], options: StickerRenderOptions())
    }

    func testAddSavesLocallyThenUploads() async throws {
        sync.offline = true
        try sut.add(try result())
        await sut.syncAll()
        XCTAssertEqual(sut.stickers.map(\.id), ["s1"])
        XCTAssertFalse(sut.stickers[0].isSynced, "çevrimdışıyken de kütüphanede")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sut.stickers[0].fileURL.path))
        XCTAssertEqual(sut.stickers[0].width, 64 + 2 * (8 + StickerRenderer.margin))

        sync.offline = false
        await sut.syncAll()
        XCTAssertEqual(sync.uploaded, ["s1"])
        XCTAssertTrue(sut.stickers[0].isSynced)
    }

    func testDeletingSyncedStickerRemovesItRemotely() async throws {
        try sut.add(try result())
        await sut.syncAll()
        sync.offline = true
        sut.delete("s1")
        await sut.syncAll()
        XCTAssertTrue(sut.stickers.isEmpty)
        XCTAssertTrue(sync.deleted.isEmpty)

        sync.offline = false
        await sut.syncAll()
        XCTAssertEqual(sync.deleted, ["s1"], "bağlantı gelince sunucudan da silinir")
        XCTAssertTrue(sync.downloaded.isEmpty, "silinen yeniden indirilmez")
    }

    func testDeletingUnsyncedStickerNeedsNoServerCall() async throws {
        sync.offline = true
        try sut.add(try result())
        sut.delete("s1")
        sync.offline = false
        await sut.syncAll()
        XCTAssertTrue(sync.deleted.isEmpty)
        XCTAssertTrue(sync.uploaded.isEmpty)
        XCTAssertTrue(sut.stickers.isEmpty)
    }

    func testStickersFromOtherDeviceAreDownloadedAndRemovalsMirrored() async throws {
        let other = StickerDTO(id: "remote-1", storagePath: StickerPath.storage(userID: "me", stickerID: "remote-1"),
                               width: 300, height: 200, createdAt: .now, updatedAt: .now)
        sync.remote = [other]
        await sut.syncAll()
        XCTAssertEqual(sut.stickers.map(\.id), ["remote-1"])
        XCTAssertTrue(sut.stickers[0].isSynced)
        await sut.syncAll()
        XCTAssertEqual(sync.downloaded, ["remote-1"], "bir kez indirilir")

        // Diğer cihazda silindi.
        sync.remote = []
        await sut.syncAll()
        XCTAssertTrue(sut.stickers.isEmpty)
    }
}
