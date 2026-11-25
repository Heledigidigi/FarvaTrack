import XCTest
import SwiftUI
import UIKit
@testable import FarvaTrack

final class AppThemeTests: XCTestCase {
    func testVarsayilanKlasik() {
        XCTAssertEqual(AppTheme.default, .klasik)
        XCTAssertEqual(AppTheme.resolve(nil), .klasik)
        XCTAssertEqual(AppTheme.resolve(""), .klasik)
        XCTAssertEqual(AppTheme.resolve("bilinmeyen"), .klasik)
    }

    func testKayitliDegerCozulur() {
        XCTAssertEqual(AppTheme.resolve("koyu"), .koyu)
        XCTAssertEqual(AppTheme.resolve("klasik"), .klasik)
    }

    func testGorunumEslesmesi() {
        XCTAssertEqual(AppTheme.klasik.colorScheme, .light)
        XCTAssertEqual(AppTheme.koyu.colorScheme, .dark)
        XCTAssertEqual(AppTheme.klasik.title, "Klasik")
        XCTAssertEqual(AppTheme.koyu.title, "Koyu")
    }

    /// Renkler görünüme göre farklı çözülmeli; koyu tema eski paleti korumalı.
    func testRenklerGorunumeGoreCozulur() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        func hex(_ color: Color, _ traits: UITraitCollection) -> String {
            let resolved = UIColor(color).resolvedColor(with: traits)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
        }
        XCTAssertEqual(hex(.ftAccent, dark), "800020")
        XCTAssertEqual(hex(.ftBackground, dark), "0E0E12")
        XCTAssertEqual(hex(.ftText, light), "3E2A1C")
        XCTAssertEqual(hex(.ftAccentLight, light), "A23A2E")
        XCTAssertNotEqual(hex(.ftCard, light), hex(.ftCard, dark))
    }
}
