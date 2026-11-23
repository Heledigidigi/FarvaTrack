import XCTest
@testable import FarvaTrack

final class CatBoxBubbleTests: XCTestCase {
    func testParserHandlesMoveLineQuadCubicClose() {
        let path = SVGPathParser.parse("M10,20 L30,20 Q40,20 40,30 C40,40 30,50 20,50 Z M0,0 L5,5Z")
        let box = path.boundingBoxOfPath
        XCTAssertEqual(box.minX, 0, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 40, accuracy: 0.5)
        XCTAssertEqual(box.maxY, 50, accuracy: 0.5)
        XCTAssertFalse(SVGPathParser.parse("M-5.5,-2 L3,4").isEmpty, "eksi sayılar")
    }

    func testEmbroideryArtParsesInsidePhotoBounds() {
        let ink = CatBoxGeometry.ink.boundingBoxOfPath
        let silhouette = CatBoxGeometry.silhouette.boundingBoxOfPath
        XCTAssertFalse(CatBoxGeometry.ink.isEmpty)
        XCTAssertGreaterThanOrEqual(silhouette.minX, CatBoxGeometry.left - 2, "daraltılmış pati")
        XCTAssertLessThanOrEqual(ink.maxY, 581)
        XCTAssertGreaterThan(ink.width, 1000)
    }

    func testSmallContentKeepsBaseBox() {
        let size = CatBoxGeometry.bubbleSize(content: CGSize(width: 20, height: 18))
        let layout = CatBoxGeometry.layout(for: size)
        XCTAssertEqual(layout.top, CatBoxGeometry.baseTop, accuracy: 0.5)
        XCTAssertEqual(layout.right, CatBoxGeometry.baseRight, accuracy: 0.5)
    }

    func testBodyGrowsRightAndUpHeadStaysFixed() {
        let small = CatBoxGeometry.layout(for: CatBoxGeometry.bubbleSize(content: CatBoxGeometry.minimumContentSize))
        let wide = CatBoxGeometry.layout(for: CatBoxGeometry.bubbleSize(content: CGSize(width: 180, height: 30)))
        let tall = CatBoxGeometry.layout(for: CatBoxGeometry.bubbleSize(content: CGSize(width: 82, height: 90)))
        XCTAssertGreaterThan(wide.right, small.right + 600, "100 nokta ≈ 700 piksel sağa")
        XCTAssertEqual(wide.top, small.top, accuracy: 0.5)
        XCTAssertLessThan(tall.top, small.top - 300, "yukarı büyür")
        XCTAssertEqual(tall.right, small.right, accuracy: 0.5)
        // Kafa her zaman aynı yerde: sol kenar dönüşümü değişmez.
        XCTAssertEqual(CGPoint(x: CatBoxGeometry.left, y: 0).applying(wide.transform).x,
                       CGPoint(x: CatBoxGeometry.left, y: 0).applying(small.transform).x, accuracy: 0.01)
    }

    func testContentSitsInsideBox() {
        let content = CGSize(width: 150, height: 63)
        let size = CatBoxGeometry.bubbleSize(content: content)
        let layout = CatBoxGeometry.layout(for: size)
        let p = CatBoxGeometry.contentPadding
        let inverse = layout.transform.inverted()
        let topLeft = CGPoint(x: p.leading, y: p.top).applying(inverse)
        let bottomRight = CGPoint(x: p.leading + content.width, y: p.top + content.height).applying(inverse)
        XCTAssertGreaterThan(topLeft.y, layout.top + CatBoxGeometry.lineWidth, "yazı sırt çizgisinin altında")
        XCTAssertGreaterThan(topLeft.x, 800, "yazı kafanın sağında")
        XCTAssertLessThan(bottomRight.x, layout.right - CatBoxGeometry.lineWidth)
        XCTAssertLessThan(bottomRight.y, CatBoxGeometry.belly - CatBoxGeometry.lineWidth)
    }

    func testPresetAndMirroredPadding() throws {
        let style = try XCTUnwrap(BubblePresets.style(id: "preset.kutuKedi"))
        XCTAssertEqual(style.art, .catBox)
        XCTAssertEqual(try BubbleStyle.decode(json: style.jsonData()).art, .catBox)
        let normal = BubbleLayout.contentPadding(for: style, mirrored: false)
        let mirrored = BubbleLayout.contentPadding(for: style, mirrored: true)
        XCTAssertEqual(normal.leading, mirrored.trailing)
        XCTAssertGreaterThan(normal.leading, normal.trailing, "kafa solda")
        XCTAssertNotNil(BubbleLayout.minimumContentSize(for: style))
        XCTAssertNil(BubbleLayout.minimumContentSize(for: BubblePresets.style(id: "preset.bordo")!))
    }

    func testOldStylesWithoutArtStillDecode() throws {
        var style = BubblePresets.style(id: "preset.bordo")!
        style.art = nil
        let data = try style.jsonData()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "art")
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try BubbleStyle.decode(json: old).art)
    }

    func testTextIsVerticallyCenteredInBox() {
        let content = CGSize(width: 120, height: 21)
        let size = CatBoxGeometry.bubbleSize(content: content)
        let layout = CatBoxGeometry.layout(for: size)
        let p = CatBoxGeometry.contentPadding
        let minimum = CatBoxGeometry.minimumContentSize
        let inverse = layout.transform.inverted()
        // İçerik alanı en küçük yükseklikte; metin onun ortasında. Alanın kutuya uzaklığı üstte ve altta eşit.
        let top = CGPoint(x: 0, y: p.top).applying(inverse).y
        let bottom = CGPoint(x: 0, y: p.top + max(content.height, minimum.height)).applying(inverse).y
        XCTAssertEqual(top - layout.top, CatBoxGeometry.belly - bottom, accuracy: 0.5)
    }

    func testStatusMarkSitsOnBellyLineNearFoot() {
        let size = CatBoxGeometry.bubbleSize(content: CGSize(width: 100, height: 21))
        let layout = CatBoxGeometry.layout(for: size)
        let offset = CatBoxGeometry.statusMarkOffset
        let center = CGPoint(x: size.width - offset.width, y: size.height - offset.height).applying(layout.transform.inverted())
        XCTAssertEqual(center.y, CatBoxGeometry.belly, accuracy: 10, "karın çizgisinin üstünde")
        XCTAssertLessThan(center.x, layout.right, "arka bacağın solunda")
        XCTAssertGreaterThan(center.x, layout.right - 120)
    }
}

final class ChatPanelLayoutGapTests: XCTestCase {
    func testBottomGapIsSubtractedFromLift() {
        XCTAssertEqual(ChatPanelLayout.bottomGap(viewMaxY: 810, windowHeight: 844), 34)
        XCTAssertEqual(ChatPanelLayout.bottomGap(viewMaxY: 844, windowHeight: 844), 0)
        XCTAssertEqual(ChatPanelLayout.bottomGap(viewMaxY: 843.8, windowHeight: 844), 0, "yarım noktadan küçük fark yok sayılır")
        XCTAssertEqual(ChatPanelLayout.bottomGap(viewMaxY: 500, windowHeight: nil), 0)
        XCTAssertEqual(ChatPanelLayout.visibleLift(336, bottomGap: 34), 302)
        XCTAssertEqual(ChatPanelLayout.visibleLift(20, bottomGap: 34), 0)
        XCTAssertEqual(ChatPanelLayout.visibleLift(336, bottomGap: -5), 336)
    }
}
