import XCTest
@testable import FarvaTrack

final class OzetBicimTests: XCTestCase {

    func testUykuSaatVeDakikayaBolunur() {
        let parca = OzetBicim.uykuParcalari(7 + 20.0 / 60)
        XCTAssertEqual(parca?.saat, 7)
        XCTAssertEqual(parca?.dakika, 20)
    }

    func testUykuYoksaBos() {
        XCTAssertNil(OzetBicim.uykuParcalari(nil))
        XCTAssertNil(OzetBicim.uykuParcalari(0))
    }

    func testCicekYuzde45AltindaKapali() {
        XCTAssertEqual(OzetBicim.cicekAcikligi(deger: 3_000, hedef: 8_000), 0)
        XCTAssertEqual(OzetBicim.cicekAcikligi(deger: 3_600, hedef: 8_000), 0, accuracy: 0.0001)
    }

    func testCicekHedefteTamAcik() {
        XCTAssertEqual(OzetBicim.cicekAcikligi(deger: 8_000, hedef: 8_000), 1)
        XCTAssertEqual(OzetBicim.cicekAcikligi(deger: 12_000, hedef: 8_000), 1)
    }

    func testCicekKademeliAcilir() {
        let orta = OzetBicim.cicekAcikligi(deger: 5_800, hedef: 8_000)
        XCTAssertGreaterThan(orta, 0.3)
        XCTAssertLessThan(orta, 0.6)
    }

    func testHedefSifirsaKapali() {
        XCTAssertEqual(OzetBicim.cicekAcikligi(deger: 5_000, hedef: 0), 0)
    }
}
