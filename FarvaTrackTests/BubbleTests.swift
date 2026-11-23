import XCTest
import SwiftData
import UIKit
@testable import FarvaTrack

// MARK: - 9-dilim

final class NineSliceTests: XCTestCase {
    private let image = CGSize(width: 180, height: 110)
    private let insets = BubbleInsets(top: 20, leading: 20, bottom: 24, trailing: 30)

    private func slice(_ slices: [NineSlice.Slice], row: Int, column: Int) -> NineSlice.Slice? {
        slices.first { $0.row == row && $0.column == column }
    }

    func testCornersFixedEdgesStretchOneWayCenterBoth() throws {
        let slices = NineSlice.slices(imageSize: image, insets: insets, target: CGSize(width: 400, height: 300))
        XCTAssertEqual(slices.count, 9)

        for (row, column) in [(0, 0), (0, 2), (2, 0), (2, 2)] {
            let corner = try XCTUnwrap(slice(slices, row: row, column: column))
            XCTAssertEqual(corner.region, .corner)
            XCTAssertEqual(corner.destination.size, corner.source.size, "köşe hiç esnemez")
        }
        let top = try XCTUnwrap(slice(slices, row: 0, column: 1))
        XCTAssertEqual(top.region, .horizontalEdge)
        XCTAssertEqual(top.destination.height, top.source.height, "üst kenar dikeyde esnemez")
        XCTAssertEqual(top.destination.width, 400 - 50)

        let left = try XCTUnwrap(slice(slices, row: 1, column: 0))
        XCTAssertEqual(left.region, .verticalEdge)
        XCTAssertEqual(left.destination.width, left.source.width, "sol kenar yatayda esnemez")
        XCTAssertEqual(left.destination.height, 300 - 44)

        let center = try XCTUnwrap(slice(slices, row: 1, column: 1))
        XCTAssertEqual(center.region, .center)
        XCTAssertEqual(center.destination.size, CGSize(width: 350, height: 256), "orta iki yönde esner")
        XCTAssertEqual(center.source.size, CGSize(width: 130, height: 66))
    }

    func testSlicesTileTargetExactly() {
        let target = CGSize(width: 263, height: 141)
        let slices = NineSlice.slices(imageSize: image, insets: insets, target: target)
        let area = slices.reduce(0) { $0 + $1.destination.width * $1.destination.height }
        XCTAssertEqual(area, target.width * target.height, accuracy: 0.001, "boşluksuz ve üst üste binmeden")
        let union = slices.map(\.destination).reduce(CGRect.null) { $0.union($1) }
        XCTAssertEqual(union, CGRect(origin: .zero, size: target))
        XCTAssertEqual(slices.map(\.index), Array(0..<9))
    }

    func testTinyTargetShrinksCornersProportionally() throws {
        // "ok" gibi çok kısa mesaj: hedef paylardan dar.
        let slices = NineSlice.slices(imageSize: image, insets: insets, target: CGSize(width: 30, height: 22))
        let topLeft = try XCTUnwrap(slice(slices, row: 0, column: 0))
        let topRight = try XCTUnwrap(slice(slices, row: 0, column: 2))
        XCTAssertEqual(topLeft.destination.width, 12, accuracy: 0.0001)
        XCTAssertEqual(topRight.destination.width, 18, accuracy: 0.0001)
        XCTAssertEqual(topLeft.destination.width / topRight.destination.width, 20.0 / 30.0, accuracy: 0.0001, "oran korunur")
        XCTAssertNil(slice(slices, row: 0, column: 1), "ortada esneyecek yer kalmadı")
        XCTAssertEqual(topLeft.source.width, 20, "kaynak değişmez, yalnızca küçülerek çizilir")
        let union = slices.map(\.destination).reduce(CGRect.null) { $0.union($1) }
        XCTAssertEqual(union.size.width, 30, accuracy: 0.0001)
    }

    func testInsetsAreClampedAndZeroInsetsWork() {
        let clamped = NineSlice.clamped(BubbleInsets(top: 100, leading: 150, bottom: 100, trailing: 150), to: image)
        XCTAssertLessThan(clamped.horizontal, Double(image.width))
        XCTAssertEqual(clamped.leading, clamped.trailing)
        XCTAssertEqual(clamped.horizontal, Double(image.width) - 1, accuracy: 0.0001, "ortada 1 pt kalır")

        let none = NineSlice.slices(imageSize: image, insets: BubbleInsets(top: 0, leading: 0, bottom: 0, trailing: 0), target: CGSize(width: 50, height: 50))
        XCTAssertEqual(none.count, 1)
        XCTAssertEqual(none.first?.region, .center)
        XCTAssertEqual(none.first?.index, 4, "sol pay 0 olsa da parça doğru sütunda")
        XCTAssertTrue(NineSlice.slices(imageSize: .zero, insets: insets, target: CGSize(width: 10, height: 10)).isEmpty)
        XCTAssertTrue(NineSlice.slices(imageSize: image, insets: insets, target: .zero).isEmpty)
    }
}

// MARK: - Yerleşim

final class BubbleLayoutTests: XCTestCase {
    private var bordo: BubbleStyle { BubblePresets.style(id: "preset.bordo")! }

    func testAutomaticInsetsFromShape() {
        let insets = BubbleLayout.automaticInsets(for: bordo)  // yarıçap 18, sivri kuyruk (8×10), kenarlık yok
        XCTAssertEqual(insets.top, 20)
        XCTAssertEqual(insets.leading, 20)
        XCTAssertEqual(insets.bottom, 20)
        XCTAssertEqual(insets.trailing, 28, "kuyruk tarafı kuyruk genişliği kadar geniş")

        var dots = bordo
        dots.shape.tail = .dots
        dots.border = BubbleBorder(colorHex: "#FFFFFF", width: 2)
        let dotInsets = BubbleLayout.automaticInsets(for: dots)
        XCTAssertEqual(dotInsets.top, 22)
        XCTAssertEqual(dotInsets.bottom, 22 + 12, "düşünce baloncuğunda alt pay noktalar kadar artar")

        var manual = bordo
        manual.manualInsets = BubbleInsets(top: 5, leading: 6, bottom: 7, trailing: 8)
        XCTAssertEqual(BubbleLayout.insets(for: manual), manual.manualInsets, "elle ayarlanan kullanılır")
    }

    func testContentPaddingFollowsTailSide() {
        let mine = BubbleLayout.contentPadding(for: bordo, mirrored: false)
        XCTAssertEqual(mine.leading, 12)
        XCTAssertEqual(mine.trailing, 20)
        let theirs = BubbleLayout.contentPadding(for: bordo, mirrored: true)
        XCTAssertEqual(theirs.leading, 20, "gelen mesajda kuyruk solda")
        XCTAssertEqual(theirs.trailing, 12)
    }

    func testDecorationsStayPinnedWhenBubbleGrows() {
        let decoration = BubbleDecoration(id: "d", kind: .emoji, text: "🌸", assetID: nil, colorHex: nil,
                                          anchor: .topTrailing, offset: CGSize(width: -4, height: -2), size: 18, rotation: 0)
        let small = BubbleLayout.position(of: decoration, in: CGSize(width: 200, height: 60), tail: .classic, mirrored: false)
        XCTAssertEqual(small, CGPoint(x: 188, y: -2))
        let large = BubbleLayout.position(of: decoration, in: CGSize(width: 400, height: 200), tail: .classic, mirrored: false)
        XCTAssertEqual(large, CGPoint(x: 388, y: -2), "köşeye uzaklık aynı kalır")

        // Aynalı (gelen): sağ üst → sol üst, kaydırma yönü de döner.
        let mirrored = BubbleLayout.position(of: decoration, in: CGSize(width: 200, height: 60), tail: .classic, mirrored: true)
        XCTAssertEqual(mirrored, CGPoint(x: 12, y: -2))

        var edge = decoration
        edge.anchor = .bottom
        edge.offset = .zero
        XCTAssertEqual(BubbleLayout.position(of: edge, in: CGSize(width: 208, height: 60), tail: .classic, mirrored: false), CGPoint(x: 100, y: 60),
                       "kenar ortası gövdeyle birlikte kayar")
    }

    func testAnchorMirroring() {
        XCTAssertEqual(BubbleAnchor.topLeading.mirrored, .topTrailing)
        XCTAssertEqual(BubbleAnchor.trailing.mirrored, .leading)
        XCTAssertEqual(BubbleAnchor.top.mirrored, .top)
        for anchor in BubbleAnchor.allCases { XCTAssertEqual(anchor.mirrored.mirrored, anchor) }
        XCTAssertEqual(BubbleInsets(top: 1, leading: 2, bottom: 3, trailing: 4).mirrored, BubbleInsets(top: 1, leading: 4, bottom: 3, trailing: 2))
    }

    func testEffectPolicyRespectsReduceMotion() {
        let glow = BubbleEffect(kind: .glow, colorHex: "#FFFFFF", intensity: 0.7)
        XCTAssertTrue(BubbleEffectPolicy.isEnabled(glow, reduceMotion: false))
        XCTAssertFalse(BubbleEffectPolicy.isEnabled(glow, reduceMotion: true), "Hareketi azalt açık: efekt kapalı")
        XCTAssertFalse(BubbleEffectPolicy.isEnabled(.none, reduceMotion: false))
        XCTAssertFalse(BubbleEffectPolicy.isEnabled(BubbleEffect(kind: .shimmer, colorHex: "#FFFFFF", intensity: 0), reduceMotion: false))
    }
}

// MARK: - Model

final class BubbleStyleModelTests: XCTestCase {
    func testPresets() {
        let presets = BubblePresets.all
        XCTAssertTrue((6...9).contains(presets.count))
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
        for preset in presets {
            XCTAssertTrue(preset.isPreset)
            XCTAssertEqual(preset.sanitized(), preset, "\(preset.name) sınırlar içinde")
            XCTAssertEqual(try BubbleStyle.decode(json: preset.jsonData()), preset, "\(preset.name) JSON gidiş-dönüş")
        }
        XCTAssertTrue(presets.contains { $0.fill.colors.contains(BubblePalette.bordo) || $0.border?.colorHex == BubblePalette.bordo }, "bordo vurgu")
        XCTAssertEqual(BubblePalette.bordo, "#800020")
        let effects = Set(presets.map(\.effect.kind))
        XCTAssertTrue(effects.isSuperset(of: [.shimmer, .glow, .particles]))
        XCTAssertTrue(presets.contains { !$0.decorations.isEmpty })
    }

    func testSanitizeClampsAndDropsInvalid() {
        var style = BubblePresets.all[0]
        style.name = "   "
        style.version = -3
        style.shape.cornerRadius = 100
        style.fill = BubbleFill(kind: .linear, colors: ["kırmızı", "#12345"], angle: 725)
        style.border = BubbleBorder(colorHex: "x", width: 10)
        style.textColorHex = "beyaz"
        style.effect = BubbleEffect(kind: .glow, colorHex: "#ZZZZZZ", intensity: 7)
        style.manualInsets = BubbleInsets(top: -5, leading: 500, bottom: .nan, trailing: 10)
        style.decorations = (0..<20).map { index in
            BubbleDecoration(id: "d\(index)", kind: .emoji, text: index == 0 ? "  " : "😀", assetID: nil, colorHex: nil,
                             anchor: .top, offset: CGSize(width: 999, height: -999), size: 1, rotation: 900)
        } + [BubbleDecoration(id: "s", kind: .sticker, text: nil, assetID: "../kötü", colorHex: nil, anchor: .top, offset: .zero, size: 20, rotation: 0)]

        let clean = style.sanitized()
        XCTAssertEqual(clean.name, "Baloncuğum")
        XCTAssertEqual(clean.version, 1)
        XCTAssertEqual(clean.shape.cornerRadius, 28)
        XCTAssertEqual(clean.fill.colors, [BubblePalette.bordo, BubblePalette.bordo], "geçersiz renkler atılır, geçişte iki renk")
        XCTAssertEqual(clean.fill.angle, 5)
        XCTAssertEqual(clean.border?.width, 4)
        XCTAssertEqual(clean.border?.colorHex, "#FFFFFF")
        XCTAssertEqual(clean.textColorHex, "#FFFFFF")
        XCTAssertEqual(clean.effect.intensity, 1)
        XCTAssertEqual(clean.effect.colorHex, "#FFFFFF")
        XCTAssertEqual(clean.manualInsets, BubbleInsets(top: 0, leading: 60, bottom: 0, trailing: 10))
        XCTAssertEqual(clean.decorations.count, BubbleStyle.maxDecorations - 1, "ilk 12 alınır, boş yazı atılır")
        XCTAssertEqual(clean.decorations.first?.offset, CGSize(width: 40, height: -40))
        XCTAssertEqual(clean.decorations.first?.size, 10)
        XCTAssertEqual(clean.decorations.first?.rotation, 180)
        XCTAssertFalse(clean.decorations.contains { $0.kind == .sticker }, "geçersiz dosya kimliği atılır")
    }

    func testVersionAssetsAndRef() {
        var style = BubblePresets.all[0]
        style.id = "b1"
        style.drawingAssetID = "draw-1"
        style.decorations = [
            BubbleDecoration(id: "a", kind: .sticker, text: nil, assetID: "stk-2", colorHex: nil, anchor: .top, offset: .zero, size: 20, rotation: 0),
            BubbleDecoration(id: "b", kind: .sticker, text: nil, assetID: "stk-2", colorHex: nil, anchor: .bottom, offset: .zero, size: 20, rotation: 0)
        ]
        XCTAssertEqual(style.assetIDs, ["draw-1", "stk-2"])
        XCTAssertEqual(style.bumpedVersion().version, 2)
        XCTAssertEqual(style.ref, ChatBubbleRef(id: "b1", version: 1))
        XCTAssertFalse(style.isPreset)
        XCTAssertTrue(BubbleAssetID.isValid(BubbleAssetID.make()))
        XCTAssertFalse(BubbleAssetID.isValid("a/b"))
        XCTAssertFalse(BubbleAssetID.isValid("ğ"))
    }

    func testRefFields() {
        let ref = ChatBubbleRef(id: "b1", version: 4)
        XCTAssertEqual(ChatBubbleRefFields.decode(ChatBubbleRefFields.encode(ref)), ref)
        XCTAssertEqual(ChatBubbleRefFields.decode(["id": "x", "version": NSNumber(value: 0)])?.version, 1)
        XCTAssertNil(ChatBubbleRefFields.decode(["id": ""]))
        XCTAssertNil(ChatBubbleRefFields.decode(nil))
    }

    @MainActor
    func testMessageRecordCarriesBubbleRef() throws {
        let container = try ModelContainer(for: ChatMessageRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let dto = ChatMessageDTO(id: "m", senderID: "a", text: "selam", createdAt: .now, bubble: ChatBubbleRef(id: "preset.gece", version: 1))
        let record = ChatMessageRecord(dto: dto, ownerID: "a", chatID: "c", sendState: .sent)
        container.mainContext.insert(record)
        XCTAssertEqual(record.dto.bubble, dto.bubble)
        var updated = dto
        updated.bubble = ChatBubbleRef(id: "b9", version: 3)
        record.apply(remote: updated)
        XCTAssertEqual(record.bubble?.version, 3)
    }
}

// MARK: - Sanat işleyici

@MainActor
final class BubbleArtRendererTests: XCTestCase {
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let buffer = try XCTUnwrap(RGBABuffer(image: image))
        return buffer.pixel(x: x, y: y)
    }

    func testRendersRoundedShapeWithTail() throws {
        let style = BubblePresets.style(id: "preset.bordo")!
        let image = try XCTUnwrap(BubbleArtRenderer.render(style: style, assets: .empty, mirrored: false))
        let scale = Int(BubbleArtRenderer.scale)
        XCTAssertEqual(image.width, 180 * scale)
        XCTAssertEqual(image.height, 110 * scale)
        XCTAssertEqual(try pixel(image, x: 0, y: 0).a, 0, "yuvarlatılmış köşe saydam")
        let center = try pixel(image, x: 90 * scale, y: 55 * scale)
        XCTAssertEqual(center.a, 255)
        XCTAssertGreaterThan(center.r, center.g, "bordo tonu")

        // Kuyruk ucu sağ altta; aynalıda sol altta.
        let tipY = 110 * scale - 2
        XCTAssertGreaterThan(try pixel(image, x: 180 * scale - 6, y: tipY).a, 0)
        let mirrored = try XCTUnwrap(BubbleArtRenderer.render(style: style, assets: .empty, mirrored: true))
        XCTAssertEqual(try pixel(mirrored, x: 180 * scale - 6, y: tipY).a, 0)
        XCTAssertGreaterThan(try pixel(mirrored, x: 5, y: tipY).a, 0)
    }

    func testBorderIsDrawnInside() throws {
        let style = BubblePresets.style(id: "preset.altin")!  // altın kenarlık, koyu dolgu
        let image = try XCTUnwrap(BubbleArtRenderer.render(style: style, assets: .empty, mirrored: false))
        let scale = Int(BubbleArtRenderer.scale)
        let edge = try pixel(image, x: 1, y: 55 * scale)
        let inside = try pixel(image, x: 40 * scale, y: 55 * scale)
        XCTAssertGreaterThan(Int(edge.r) + Int(edge.g), Int(inside.r) + Int(inside.g) + 100, "kenarda altın, içte koyu")
    }

    func testArtPiecesMatchSlices() throws {
        var style = BubblePresets.style(id: "preset.minimal")!
        style.manualInsets = BubbleInsets(top: 0, leading: 0, bottom: 20, trailing: 20)
        let image = try XCTUnwrap(BubbleArtRenderer.render(style: style, assets: .empty, mirrored: false))
        let art = BubbleArt(image: image, insets: BubbleLayout.insets(for: style))
        XCTAssertEqual(art.pieces.compactMap { $0 }.count, 4, "yalnızca var olan parçalar")
        XCTAssertNotNil(art.pieces[4], "sol ve üst pay 0 olsa da orta parça yerinde")
        XCTAssertNil(art.pieces[0])
        XCTAssertEqual(art.pieces[8]?.width, 20 * Int(BubbleArtRenderer.scale))
    }

    func testCacheReusesArtPerVersion() {
        BubbleArtCache.removeAll()
        var style = BubblePresets.style(id: "preset.gece")!
        let first = BubbleArtCache.art(for: style, assets: .empty, mirrored: false, keyPrefix: "u1")
        XCTAssertTrue(first === BubbleArtCache.art(for: style, assets: .empty, mirrored: false, keyPrefix: "u1"))
        XCTAssertFalse(first === BubbleArtCache.art(for: style, assets: .empty, mirrored: true, keyPrefix: "u1"))
        style.version = 2
        XCTAssertFalse(first === BubbleArtCache.art(for: style, assets: .empty, mirrored: false, keyPrefix: "u1"), "yeni sürüm yeniden çizilir")
    }
}

// MARK: - Stil deposu

final class MockBubbleSync: BubbleSyncing {
    var remote: [String: [BubbleStyle]] = [:]
    var offline = false
    private(set) var events: [String] = []
    private(set) var fetches: [String] = []
    private(set) var deleted: [String] = []

    func save(_ style: BubbleStyle, userID: String) async throws {
        if offline { throw AppError.network }
        events.append("save:\(style.id):v\(style.version)")
        remote[userID, default: []].removeAll { $0.id == style.id }
        remote[userID, default: []].append(style)
    }

    func uploadAsset(_ fileURL: URL, styleID: String, assetID: String, userID: String) async throws {
        if offline { throw AppError.network }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        events.append("asset:\(assetID)")
    }

    func fetch(styleID: String, ownerID: String) async throws -> BubbleStyle? {
        if offline { throw AppError.network }
        fetches.append("\(ownerID)/\(styleID)")
        return remote[ownerID]?.first { $0.id == styleID }
    }

    func fetchAll(userID: String) async throws -> [BubbleStyle] {
        if offline { throw AppError.network }
        return remote[userID] ?? []
    }

    func downloadAsset(styleID: String, assetID: String, ownerID: String, to destination: URL) async throws {
        events.append("download:\(assetID)")
        try Data("png".utf8).write(to: destination)
    }

    func delete(styleID: String, userID: String) async throws {
        if offline { throw AppError.network }
        deleted.append(styleID)
        remote[userID]?.removeAll { $0.id == styleID }
    }

    func purge(userID: String) async throws {}
}

@MainActor
final class BubbleStyleStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockBubbleSync!
    private var root: URL!
    private var defaults: UserDefaults!
    private var sut: BubbleStyleStore!
    private var counter = 0

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: BubbleStyleRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sync = MockBubbleSync()
        root = makeTemporaryDirectory()
        defaults = makeTestDefaults("bubbles.\(name)")
        counter = 0
        sut = makeStore()
    }

    override func tearDown() async throws {
        await sut.waitForPendingSync()
        await settleTasks()
        sut = nil
        container = nil
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func makeStore() -> BubbleStyleStore {
        let store = BubbleStyleStore(
            sync: sync, files: BubbleFiles(persistentRoot: root.appendingPathComponent("mine"), cacheRoot: root.appendingPathComponent("cache")),
            defaults: defaults, clock: { Date(timeIntervalSince1970: 5_000) },
            makeID: { [unowned self] in
                self.counter += 1
                return "b\(self.counter)"
            }
        )
        store.configure(context: container.mainContext, userID: "me")
        return store
    }

    private func pngFile() throws -> URL {
        let url = root.appendingPathComponent("\(UUID().uuidString).png")
        try XCTUnwrap(UIImage(systemName: "star.fill")?.pngData()).write(to: url)
        return url
    }

    func testPresetsAndSelectionPersist() {
        XCTAssertNotNil(sut.style(for: ChatBubbleRef(id: "preset.neon", version: 1), ownerID: "someone"), "hazırlar her iki cihazda da var")
        XCTAssertNil(sut.selectedRef)
        sut.select("preset.neon")
        XCTAssertEqual(sut.selectedRef, ChatBubbleRef(id: "preset.neon", version: 1))
        sut.select("yok-boyle-bir-stil")
        XCTAssertEqual(sut.selectedID, "preset.neon", "bilinmeyen stil seçilmez")
        XCTAssertEqual(makeStore().selectedID, "preset.neon", "seçim hatırlanır")
        sut.select(nil)
        XCTAssertNil(makeStore().selectedID)
    }

    func testSaveNewStyleUploadsAssetsThenDocument() async throws {
        var draft = BubblePresets.style(id: "preset.gul")!
        draft.id = ""
        draft.decorations.append(BubbleDecoration(id: "x", kind: .sticker, text: nil, assetID: "stk-1", colorHex: nil,
                                                  anchor: .topLeading, offset: .zero, size: 24, rotation: 0))
        let saved = try sut.save(draft, drawingPNG: Data("cizim".utf8), drawingData: Data("pk".utf8), stickerFiles: ["stk-1": try pngFile()])
        XCTAssertEqual(saved.id, "b1")
        XCTAssertEqual(saved.version, 1)
        XCTAssertNotNil(saved.drawingAssetID)
        XCTAssertEqual(sut.myStyles.map(\.id), ["b1"])
        XCTAssertEqual(sut.selectedRef, ChatBubbleRef(id: "b1", version: 1), "kaydedilen seçilir")
        XCTAssertEqual(sut.drawingData(for: "b1"), Data("pk".utf8))
        XCTAssertNotNil(sut.assets(for: saved, ownerID: "me").stickerURLs["stk-1"])

        await sut.waitForPendingSync()
        XCTAssertEqual(sync.events.last, "save:b1:v1")
        XCTAssertEqual(Set(sync.events.dropLast()), Set(saved.assetIDs.map { "asset:\($0)" }), "önce dosyalar, sonra belge")
    }

    func testEditingBumpsVersion() async throws {
        var draft = BubblePresets.all[0]
        draft.id = ""
        let first = try sut.save(draft, drawingPNG: nil, drawingData: nil)
        await sut.waitForPendingSync()
        var edited = first
        edited.shape.cornerRadius = 8
        let second = try sut.save(edited, drawingPNG: nil, drawingData: nil)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.version, 2)
        XCTAssertEqual(sut.selectedRef?.version, 2, "giden mesajlar yeni sürümü taşır")
        await sut.waitForPendingSync()
        XCTAssertEqual(sync.events.filter { $0.hasPrefix("save:") }, ["save:b1:v1", "save:b1:v2"])
    }

    func testOfflineSaveSyncsLater() async throws {
        sync.offline = true
        var draft = BubblePresets.all[1]
        draft.id = ""
        _ = try sut.save(draft, drawingPNG: nil, drawingData: nil)
        await sut.waitForPendingSync()
        XCTAssertTrue(sync.events.isEmpty)
        sync.offline = false
        await sut.syncAll()
        XCTAssertEqual(sync.events, ["save:b1:v1"])
    }

    func testPartnerStyleIsFetchedOnceAndRefreshedOnNewVersion() async throws {
        var theirs = BubblePresets.style(id: "preset.yildiz")!
        theirs.id = "their-1"
        theirs.drawingAssetID = "draw-9"
        sync.remote["friend"] = [theirs]
        let ref = ChatBubbleRef(id: "their-1", version: 1)

        XCTAssertNil(sut.style(for: ref, ownerID: "friend"))
        XCTAssertTrue(sut.needsFetch(ref, ownerID: "friend"))
        await sut.ensure(ref, ownerID: "friend")
        XCTAssertEqual(sut.style(for: ref, ownerID: "friend")?.id, "their-1")
        XCTAssertEqual(sync.events, ["download:draw-9"], "dosyaları da önbelleğe alınır")
        XCTAssertFalse(sut.needsFetch(ref, ownerID: "friend"))
        await sut.ensure(ref, ownerID: "friend")
        XCTAssertEqual(sync.fetches.count, 1, "aynı sürüm yeniden indirilmez")

        // Karşı taraf baloncuğunu düzenledi; yeni mesaj v2 taşıyor.
        theirs.version = 2
        theirs.shape.cornerRadius = 6
        sync.remote["friend"] = [theirs]
        let newer = ChatBubbleRef(id: "their-1", version: 2)
        XCTAssertNotNil(sut.style(for: newer, ownerID: "friend"), "yenisi gelene kadar eldeki gösterilir")
        XCTAssertTrue(sut.needsFetch(newer, ownerID: "friend"))
        await sut.ensure(newer, ownerID: "friend")
        XCTAssertEqual(sut.style(for: newer, ownerID: "friend")?.shape.cornerRadius, 6)
        XCTAssertFalse(sut.needsFetch(ref, ownerID: "friend"), "eski mesajlar da yeni sürümle gösterilir")
    }

    func testPresetAndOwnStylesNeverFetch() async {
        XCTAssertFalse(sut.needsFetch(ChatBubbleRef(id: "preset.gece", version: 1), ownerID: "friend"))
        XCTAssertFalse(sut.needsFetch(ChatBubbleRef(id: "b1", version: 1), ownerID: "me"))
        XCTAssertFalse(sut.needsFetch(nil, ownerID: "friend"))
        await sut.ensure(ChatBubbleRef(id: "preset.gece", version: 1), ownerID: "friend")
        XCTAssertTrue(sync.fetches.isEmpty)
    }

    func testDeleteRemovesRemotelyAndClearsSelection() async throws {
        var draft = BubblePresets.all[0]
        draft.id = ""
        let saved = try sut.save(draft, drawingPNG: nil, drawingData: nil)
        await sut.waitForPendingSync()
        sync.offline = true
        sut.delete(saved.id)
        XCTAssertNil(sut.selectedID)
        XCTAssertTrue(sut.myStyles.isEmpty)
        await sut.waitForPendingSync()
        XCTAssertTrue(sync.deleted.isEmpty)
        sync.offline = false
        await sut.syncAll()
        XCTAssertEqual(sync.deleted, [saved.id])
        XCTAssertTrue(sut.myStyles.isEmpty, "silinen diğer cihazdan geri gelmez")
    }

    func testStylesFromOtherDeviceArePulledAndRemovalsMirrored() async {
        var other = BubblePresets.style(id: "preset.pati")!
        other.id = "remote-1"
        other.version = 3
        sync.remote["me"] = [other]
        await sut.syncAll()
        XCTAssertEqual(sut.myStyles.map(\.id), ["remote-1"])
        XCTAssertEqual(sut.myStyles.first?.version, 3)
        sut.select("remote-1")

        sync.remote["me"] = []
        await sut.syncAll()
        XCTAssertTrue(sut.myStyles.isEmpty)
        XCTAssertNil(sut.selectedID, "silinen stil seçili kalmaz")
    }
}

// MARK: - Mesaja ekleme

@MainActor
final class ChatBubbleMessageTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockChatSync!
    private var store: MockMediaStore!
    private var root: URL!
    private var sut: ChatViewModel!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: ChatMessageRecord.self, ChatPendingOperation.self, ChatPlacementRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        sync = MockChatSync()
        store = MockMediaStore()
        root = makeTemporaryDirectory()
        var counter = 0
        sut = ChatViewModel(sync: sync, mediaStore: store, processor: MockMediaProcessor(),
                            files: ChatMediaFiles(persistentRoot: root.appendingPathComponent("s"), cacheRoot: root.appendingPathComponent("c")),
                            defaults: makeTestDefaults("bubblemsg.\(name)"),
                            makeID: {
                                counter += 1
                                return "m\(counter)"
                            })
        sut.configure(context: container.mainContext, user: AppUser.makeNew(id: "me", email: "a@b.com", displayName: "Ben"))
        sync.roomHandler?(ChatRoomDTO(id: ChatID.make("me", "friend"), members: ChatID.sortedMembers("me", "friend"), createdAt: .now), false)
        await settleTasks()
    }

    override func tearDown() async throws {
        await settleTasks()
        sut.reset()
        await settleTasks()
        sut = nil
        container = nil
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func settle() async {
        for _ in 0..<3 {
            await settleTasks()
            await sut.flushOutbox()
        }
    }

    func testSelectedBubbleTravelsWithTextAndVoiceButNotStickers() async throws {
        sut.outgoingBubble = ChatBubbleRef(id: "b7", version: 2)
        sut.draft = "Merhaba"
        sut.send()
        let voiceFile = root.appendingPathComponent("v.m4a")
        try Data("ses".utf8).write(to: voiceFile)
        sut.sendVoice(RecordedVoice(fileURL: voiceFile, duration: 2, waveform: []))
        let stickerFile = root.appendingPathComponent("s.png")
        try XCTUnwrap(UIImage(systemName: "star")?.pngData()).write(to: stickerFile)
        sut.sendSticker(fileURL: stickerFile, width: 10, height: 10)
        await settle()

        func sent(_ type: ChatMessageType) -> ChatMessageDTO? { sync.sent.first { $0.type == type } }
        XCTAssertEqual(try XCTUnwrap(sent(.text)).bubble, ChatBubbleRef(id: "b7", version: 2))
        XCTAssertEqual(try XCTUnwrap(sent(.audio)).bubble, ChatBubbleRef(id: "b7", version: 2))
        XCTAssertNil(try XCTUnwrap(sent(.sticker)).bubble, "sticker baloncuksuz")

        sut.outgoingBubble = nil
        sut.draft = "Varsayılan"
        sut.send()
        await settle()
        XCTAssertNil(sync.sent.last?.bubble)
    }
}
