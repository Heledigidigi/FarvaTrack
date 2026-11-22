import XCTest
@testable import FarvaTrack

final class ChatFuzzySearchTests: XCTestCase {
    func testExactAndSubstringScoreZero() {
        XCTAssertEqual(ChatText.fuzzyScore("Yarın İstanbul'dayım", query: "istanbul"), 0)
        XCTAssertEqual(ChatText.fuzzyScore("Antrenman saat kaçta?", query: "SAAT KAÇ"), 0)
    }

    func testTyposAreToleratedByWordLength() {
        XCTAssertNotNil(ChatText.fuzzyScore("Yarın İstanbul'dayım", query: "istnabul"), "yer değiştirme")
        XCTAssertNotNil(ChatText.fuzzyScore("Bugün antrenman var", query: "antrenmam"))
        XCTAssertNotNil(ChatText.fuzzyScore("Selam nasılsın", query: "nasilsn"))
        XCTAssertNotNil(ChatText.fuzzyScore("Akşam yemeği", query: "aksam yemegi"), "Türkçe harfsiz yazım")
        XCTAssertNil(ChatText.fuzzyScore("kedi", query: "kod"), "kısa kelimede hata kabul edilmez")
        XCTAssertNil(ChatText.fuzzyScore("Bugün antrenman var", query: "bisiklet"))
    }

    func testAllQueryWordsMustMatch() {
        XCTAssertNotNil(ChatText.fuzzyScore("yarın spor salonu", query: "salon yarin"))
        XCTAssertNil(ChatText.fuzzyScore("yarın spor salonu", query: "salon pazar"))
    }

    func testCloserMatchScoresLower() {
        let exact = ChatText.fuzzyScore("istanbul", query: "istanbul")!
        let typo = ChatText.fuzzyScore("istanbul", query: "istanbol")!
        XCTAssertLessThan(exact, typo)
    }

    func testEditDistance() {
        XCTAssertEqual(ChatText.editDistance("kitap", "kitap"), 0)
        XCTAssertEqual(ChatText.editDistance("kitap", "ktiap"), 1, "bitişik yer değiştirme tek hata")
        XCTAssertEqual(ChatText.editDistance("kitap", "kitaplar"), 3)
        XCTAssertGreaterThan(ChatText.editDistance("abcdef", "uvwxyz", limit: 2), 2)
    }

    func testLinksAreExtractedAndDeduplicated() {
        let links = ChatText.links(in: "Bak https://ornek.com/a ve www.farva.app sonra yine https://ornek.com/a")
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links.first?.absoluteString, "https://ornek.com/a")
        XCTAssertEqual(links.last?.host(), "www.farva.app")
        XCTAssertTrue(ChatText.links(in: "bağlantı yok").isEmpty)
    }
}

final class PhotoEditLayerHitTests: XCTestCase {
    func testTopmostLayerUnderPointIsHit() {
        let below = PhotoEditLayer(content: .sticker(id: "a", aspect: 1), center: CGPoint(x: 0.5, y: 0.5))
        let above = PhotoEditLayer(content: .sticker(id: "b", aspect: 1), center: CGPoint(x: 0.55, y: 0.5))
        let hit = PhotoEditGeometry.layerHit([below, above], at: CGPoint(x: 0.52, y: 0.5), heightOverWidth: 1)
        XCTAssertEqual(hit, above.id, "üstteki (son eklenen) önce")
        XCTAssertNil(PhotoEditGeometry.layerHit([below], at: CGPoint(x: 0.05, y: 0.05), heightOverWidth: 1))
    }

    func testLargerScaleWidensHitArea() {
        var layer = PhotoEditLayer(content: .text("Merhaba", colorIndex: 0), center: CGPoint(x: 0.5, y: 0.5))
        let point = CGPoint(x: 0.75, y: 0.5)
        XCTAssertNil(PhotoEditGeometry.layerHit([layer], at: point, heightOverWidth: 1))
        layer.scale = 3
        XCTAssertEqual(PhotoEditGeometry.layerHit([layer], at: point, heightOverWidth: 1), layer.id)
    }
}
