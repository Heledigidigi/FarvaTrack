import XCTest
import SwiftData
@testable import FarvaTrack

/// Aşama 10: sohbet temaları (saf hesaplar).
final class ChatThemeModelTests: XCTestCase {
    func testVirtualHourMapsSunriseAndSunset() {
        let rise = 7.2, set = 17.0
        XCTAssertEqual(PixelMeadowClock.virtualHour(rise, rise: rise, set: set), 6.5, accuracy: 0.0001)
        XCTAssertEqual(PixelMeadowClock.virtualHour(set, rise: rise, set: set), 19.0, accuracy: 0.0001)
        XCTAssertEqual(PixelMeadowClock.virtualHour((rise + set) / 2, rise: rise, set: set), 12.75, accuracy: 0.0001)
        // Gece yarısı ile ertesi doğuş arası sabaha doğru ilerler, 24'ü geçmez.
        let midnight = PixelMeadowClock.virtualHour(0, rise: rise, set: set)
        let beforeRise = PixelMeadowClock.virtualHour(rise - 0.01, rise: rise, set: set)
        XCTAssertTrue((0..<24).contains(midnight))
        XCTAssertGreaterThan(beforeRise, midnight)
        XCTAssertEqual(beforeRise, 6.5, accuracy: 0.01)
    }

    func testSunTimesFollowSeasons() {
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.timeZone = zone
        let clock = PixelMeadowClock(latitude: 41, timeZone: zone)
        let summer = clock.sunTimes(on: calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!)
        let winter = clock.sunTimes(on: calendar.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12))!)
        XCTAssertGreaterThan(summer.set - summer.rise, 14.5, "yazın gün uzun")
        XCTAssertLessThan(winter.set - winter.rise, 9.6, "kışın gün kısa")
        XCTAssertTrue((4...7).contains(summer.rise))
        XCTAssertTrue((6.5...9).contains(winter.rise))
    }

    func testSkyKeyframes() {
        XCTAssertEqual(PixelMeadowSky.at(18.7).sunsetWeight, 1, "gün batımında görselin orijinali")
        XCTAssertEqual(PixelMeadowSky.at(12).sunsetWeight, 0)
        XCTAssertEqual(PixelMeadowSky.at(12).nightWeight, 0)
        XCTAssertEqual(PixelMeadowSky.at(23).nightWeight, 1)
        XCTAssertEqual(PixelMeadowSky.at(2).nightWeight, 1)
        // Anahtar karede tam değer, arada geçiş.
        XCTAssertEqual(PixelMeadowSky.at(8.5).top, ThemeRGBA(hex: "#78A7FF"))
        let mid = PixelMeadowSky.at(7.65)
        XCTAssertNotEqual(mid.top, ThemeRGBA(hex: "#6F8FCF"))
        XCTAssertNotEqual(mid.top, ThemeRGBA(hex: "#78A7FF"))
    }

    func testSunAndMoonArcs() {
        let rise = PixelMeadowSky.bodyPosition(0), noon = PixelMeadowSky.bodyPosition(0.5), set = PixelMeadowSky.bodyPosition(1)
        XCTAssertGreaterThan(rise.x, set.x, "sağdan doğar, sola batar")
        XCTAssertLessThan(noon.y, rise.y, "öğlen en yukarıda")
        XCTAssertNotNil(PixelMeadowSky.sunProgress(12))
        XCTAssertNil(PixelMeadowSky.sunProgress(23))
        XCTAssertNotNil(PixelMeadowSky.moonProgress(23))
        XCTAssertNil(PixelMeadowSky.moonProgress(12))
    }

    func testSunDistanceFactor() {
        let screen = CGSize(width: 393, height: 852)
        let sun = ChatThemeSun.sunPoint(in: screen)
        XCTAssertGreaterThan(sun.x, screen.width * 0.85, "güneş sağ üstte")
        XCTAssertLessThan(sun.y, screen.height * 0.12)
        XCTAssertEqual(ChatThemeSun.distanceFactor(center: CGPoint(x: sun.x - 20, y: sun.y + 40), sun: sun, screen: screen), 0)
        let far = ChatThemeSun.distanceFactor(center: CGPoint(x: 20, y: screen.height - 20), sun: sun, screen: screen)
        XCTAssertGreaterThan(far, 0.9, "sol alt köşe en koyu")
        let middle = ChatThemeSun.distanceFactor(center: CGPoint(x: screen.width / 2, y: screen.height / 2), sun: sun, screen: screen)
        XCTAssertTrue((0.05...0.9).contains(middle))
    }

    func testSunPaletteMixes() {
        let palette = ChatThemeSunPalette.golden
        XCTAssertEqual(palette.outgoing(0), palette.outgoingNear)
        XCTAssertEqual(palette.outgoing(1), palette.outgoingFar)
        XCTAssertEqual(palette.incoming(0.5).a, (palette.incomingNear.a + palette.incomingFar.a) / 2, accuracy: 0.0001)
    }

    func testAspectFill() {
        let fill = AspectFill(image: CGSize(width: 600, height: 1200), container: CGSize(width: 300, height: 700))
        XCTAssertEqual(fill.scale, 700.0 / 1200, accuracy: 0.0001, "yüksekliği doldurur")
        XCTAssertLessThan(fill.origin.x, 0, "yanlar kırpılır, ortalanır")
        XCTAssertEqual(fill.origin.y, 0, accuracy: 0.0001)
    }

    func testLooks() {
        XCTAssertNil(ChatThemeLook.look(for: nil))
        let none = ChatThemeChoice(id: .plain, variant: nil, by: "a", at: .now)
        XCTAssertNil(ChatThemeLook.look(for: none))
        XCTAssertEqual(ChatThemeLook.look(for: ChatThemeChoice(id: .rainbow, variant: nil, by: "a", at: .now)), .rainbow)
        let rose = ChatThemeChoice(id: .hillCat, variant: "gul", by: "a", at: .now)
        XCTAssertEqual(ChatThemeLook.look(for: rose)?.sunPalette, .rose)
        XCTAssertEqual(ChatThemeChoice(id: .hillCat, variant: "bilinmeyen", by: "a", at: .now).hillSky, .golden)
        // Piksel Çayır: gece çubuklar gece mavisi.
        let zone = TimeZone(identifier: "Europe/Istanbul")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let clock = PixelMeadowClock(latitude: 41, timeZone: zone)
        let pixel = ChatThemeChoice(id: .pixelMeadow, variant: nil, by: "a", at: .now)
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 12))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 23))!
        XCTAssertEqual(ChatThemeLook.look(for: pixel, date: noon, clock: clock), .pixelDay)
        XCTAssertEqual(ChatThemeLook.look(for: pixel, date: night, clock: clock), .pixelNight)
    }

    func testSameLookAndCodable() throws {
        let a = ChatThemeChoice(id: .hillCat, variant: "gul", by: "a", at: Date(timeIntervalSince1970: 1))
        let b = ChatThemeChoice(id: .hillCat, variant: "gul", by: "b", at: Date(timeIntervalSince1970: 2))
        XCTAssertTrue(a.sameLook(as: b))
        XCTAssertFalse(a.sameLook(as: ChatThemeChoice(id: .hillCat, variant: "ates", by: "a", at: .now)))
        XCTAssertTrue(ChatThemeChoice(id: .plain, variant: nil, by: "a", at: .now).sameLook(as: nil))

        // Oda önbelleği: temalı oda gidip gelir; eski kayıt (tema yok) çözülür.
        let room = ChatRoomDTO(id: "a_b", members: ["a", "b"], createdAt: Date(timeIntervalSince1970: 0), theme: a)
        let data = try JSONEncoder().encode(room)
        XCTAssertEqual(try JSONDecoder().decode(ChatRoomDTO.self, from: data).theme, a)
        let legacy = try JSONEncoder().encode(ChatRoomDTO(id: "a_b", members: ["a", "b"], createdAt: Date(timeIntervalSince1970: 0)))
        XCTAssertNil(try JSONDecoder().decode(ChatRoomDTO.self, from: legacy).theme)
    }

    func testThemeBubblePresets() {
        let ids = Set(BubblePresets.all.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["preset.gokkusagi", "preset.piksel", "preset.gunBatimi"]))
    }
}

/// Aşama 10: temanın odaya yazılması.
@MainActor
final class ChatThemeViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockChatSync!
    private var defaults: UserDefaults!
    private var sut: ChatViewModel!
    private let me = AppUser.makeNew(id: "me", email: "ben@ornek.com", displayName: "Ben")
    private var room: ChatRoomDTO {
        ChatRoomDTO(id: ChatID.make("me", "friend"), members: ChatID.sortedMembers("me", "friend"),
                    names: ["me": "Ben", "friend": "Elif"], createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: ChatMessageRecord.self, ChatPendingOperation.self, ChatPlacementRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sync = MockChatSync()
        defaults = makeTestDefaults("chattheme.\(name)")
        sut = ChatViewModel(sync: sync, defaults: defaults, clock: { Date(timeIntervalSince1970: 1_800_000_000) })
        sut.configure(context: container.mainContext, user: me)
        sync.roomHandler?(room, false)
        await settleTasks()
    }

    override func tearDown() async throws {
        await settleTasks()
        sut.reset()
        await settleTasks()
        sut = nil
        sync = nil
        container = nil
        try await super.tearDown()
    }

    func testSetThemeWritesOnceAndShowsImmediately() async {
        XCTAssertNil(sut.theme)
        sut.setTheme(.hillCat, sky: .rose)
        XCTAssertEqual(sut.theme?.id, .hillCat, "sunucudan dönmeden görünür")
        XCTAssertEqual(sut.theme?.hillSky, .rose)
        await settleTasks()
        XCTAssertEqual(sync.themeUpdates.count, 1)
        XCTAssertEqual(sync.themeUpdates.first?.by, "me")
        XCTAssertEqual(sync.themeUpdates.first?.variant, "gul")

        // Aynı görünüm yeniden yazılmaz.
        sut.setTheme(.hillCat, sky: .rose)
        await settleTasks()
        XCTAssertEqual(sync.themeUpdates.count, 1)

        // Sunucudan dönen oda bekleyen seçimi siler; karşı tarafın sonraki değişikliği görünür.
        var updated = room
        updated.theme = sync.themeUpdates.first
        sync.roomHandler?(updated, false)
        await settleTasks()
        XCTAssertNil(sut.pendingTheme)
        updated.theme = ChatThemeChoice(id: .rainbow, variant: nil, by: "friend", at: .now)
        sync.roomHandler?(updated, false)
        await settleTasks()
        XCTAssertEqual(sut.theme?.id, .rainbow)
    }

    func testFailedWriteRevertsAndShowsError() async {
        sync.isOffline = true
        sut.setTheme(.pixelMeadow)
        await settleTasks()
        XCTAssertNil(sut.theme, "yazılamazsa eski tema kalır")
        XCTAssertNotNil(sut.errorMessage)
    }

    func testChoosingDefaultWithoutThemeDoesNothing() async {
        sut.setTheme(.plain)
        await settleTasks()
        XCTAssertTrue(sync.themeUpdates.isEmpty)
    }
}
