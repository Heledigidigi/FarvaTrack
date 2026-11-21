import Foundation
import CoreGraphics
import Observation

enum StickerTool: String, CaseIterable, Identifiable {
    case erase, restore
    /// Tek parmakla kaydırma (fırça kapalı).
    case move

    var id: Self { self }

    var title: String {
        switch self {
        case .erase: return "Silgi"
        case .restore: return "Onar"
        case .move: return "Gezin"
        }
    }

    var systemImage: String {
        switch self {
        case .erase: return "eraser.fill"
        case .restore: return "paintbrush.pointed.fill"
        case .move: return "hand.draw.fill"
        }
    }

    var brushMode: StickerBrushMode? {
        switch self {
        case .erase: return .erase
        case .restore: return .restore
        case .move: return nil
        }
    }
}

/// Geri al / ileri al kapsamındaki düzenleme hali.
struct StickerEditorSnapshot: Equatable {
    var mask: StickerMask
    var overlays: [StickerOverlay]
}

@MainActor
@Observable
final class StickerEditorViewModel {
    enum Phase: Equatable { case idle, processing, editing, saving }

    static let brushDiameterRange: ClosedRange<Double> = 8...90
    /// Fırça hareketinde önizleme en sık bu aralıkla yenilenir (~30 fps).
    static let previewInterval: TimeInterval = 1.0 / 30

    private(set) var phase: Phase = .idle
    private(set) var source: CGImage?
    private(set) var mask = StickerMask(width: 0, height: 0)
    private(set) var overlays: [StickerOverlay] = []
    /// Maskelenmiş fotoğraf (düzenleme tuvali).
    private(set) var preview: CGImage?
    /// Konturlu son hal (küçük önizleme kartı).
    private(set) var finalPreview: CGImage?
    /// Otomatik kaldırma olmadıysa kullanıcıya açıklama.
    private(set) var notice: String?
    var errorMessage: String?

    var tool: StickerTool = .erase
    /// Ekranda fırça çapı (pt).
    var brushDiameter: Double = 34
    var softness: Double = 0.35
    var selectedOverlayID: UUID?
    var options = StickerRenderOptions() {
        didSet { if options != oldValue { scheduleFinalPreview() } }
    }

    private var history = UndoStack<StickerEditorSnapshot>(limit: 30)
    private var sourceBuffer: RGBABuffer?
    private var automaticMask: StickerMask?
    private var lastStrokePoint: CGPoint?
    private var lastPreviewAt: Date = .distantPast
    @ObservationIgnored private var finalPreviewTask: Task<Void, Never>?

    private let segmenter: StickerSegmenting
    private let clock: () -> Date
    private let finalPreviewDelay: Duration

    init(segmenter: StickerSegmenting = VisionStickerSegmenter(),
         clock: @escaping () -> Date = { .now },
         finalPreviewDelay: Duration = .milliseconds(250)) {
        self.segmenter = segmenter
        self.clock = clock
        self.finalPreviewDelay = finalPreviewDelay
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var isStroking: Bool { lastStrokePoint != nil }
    var pixelSize: CGSize { CGSize(width: mask.width, height: mask.height) }
    var hasAutomaticMask: Bool { automaticMask != nil }
    var selectedOverlay: StickerOverlay? { overlays.first { $0.id == selectedOverlayID } }

    // MARK: Yükleme

    /// Seçilen fotoğrafı açar ve arka planı cihazda kaldırır.
    func load(imageData: Data) async {
        guard let image = StickerImageLoader.workingImage(from: imageData) else {
            errorMessage = "Fotoğraf açılamadı."
            return
        }
        await load(image: image)
    }

    func load(image: CGImage) async {
        phase = .processing
        notice = nil
        source = image
        sourceBuffer = RGBABuffer(image: image)
        overlays = []
        history.clear()
        do {
            let detected = try await segmenter.foregroundMask(for: image)
            if detected.width == image.width, detected.height == image.height {
                mask = detected
                automaticMask = detected
            } else {
                mask = StickerMask(width: image.width, height: image.height)
                notice = StickerSegmentationError.unavailable.errorDescription
            }
        } catch {
            // Otomatik olmadıysa fotoğrafın tamamıyla başlanır; silgiyle elle düzenlenir.
            mask = StickerMask(width: image.width, height: image.height)
            automaticMask = nil
            notice = (error as? LocalizedError)?.errorDescription ?? StickerSegmentationError.unavailable.errorDescription
        }
        phase = .editing
        refreshPreview(force: true)
        scheduleFinalPreview()
    }

    // MARK: Fırça

    /// `point`: görüntü pikseli; `radius`: görüntü pikseli.
    func beginStroke(at point: CGPoint, radius: Double) {
        guard phase == .editing, let mode = tool.brushMode else { return }
        history.record(snapshot)
        lastStrokePoint = point
        mask.stamp(at: point, brush: StickerBrush(mode: mode, radius: radius, softness: softness))
        refreshPreview(force: false)
    }

    func continueStroke(to point: CGPoint, radius: Double) {
        guard let last = lastStrokePoint, let mode = tool.brushMode else { return }
        mask.stroke(from: last, to: point, brush: StickerBrush(mode: mode, radius: radius, softness: softness))
        lastStrokePoint = point
        refreshPreview(force: false)
    }

    func endStroke() {
        guard lastStrokePoint != nil else { return }
        lastStrokePoint = nil
        refreshPreview(force: true)
        scheduleFinalPreview()
    }

    /// İkinci parmak gelince (yakınlaştırma başladı) yarım fırça darbesi geri alınır.
    func cancelStroke() {
        guard lastStrokePoint != nil else { return }
        lastStrokePoint = nil
        if let previous = history.discardLast() { apply(previous) }
        refreshPreview(force: true)
    }

    // MARK: Geri al / ileri al

    func undo() {
        guard let previous = history.undo(current: snapshot) else { return }
        apply(previous)
        refreshPreview(force: true)
        scheduleFinalPreview()
    }

    func redo() {
        guard let next = history.redo(current: snapshot) else { return }
        apply(next)
        refreshPreview(force: true)
        scheduleFinalPreview()
    }

    /// Otomatik maskeye ya da fotoğrafın tamamına dönüş (geri alınabilir).
    func resetMask(toAutomatic: Bool) {
        guard phase == .editing else { return }
        history.record(snapshot)
        mask = toAutomatic ? (automaticMask ?? StickerMask(width: mask.width, height: mask.height)) : StickerMask(width: mask.width, height: mask.height)
        refreshPreview(force: true)
        scheduleFinalPreview()
    }

    private var snapshot: StickerEditorSnapshot { StickerEditorSnapshot(mask: mask, overlays: overlays) }

    private func apply(_ state: StickerEditorSnapshot) {
        mask = state.mask
        overlays = state.overlays
        if let selectedOverlayID, !overlays.contains(where: { $0.id == selectedOverlayID }) { self.selectedOverlayID = nil }
    }

    // MARK: Yazı ve emoji

    func addOverlay(_ overlay: StickerOverlay) {
        guard phase == .editing, !overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        history.record(snapshot)
        overlays.append(overlay)
        selectedOverlayID = overlay.id
        scheduleFinalPreview()
    }

    /// Sürükleme / boyutlandırma başlarken bir kez çağrılır (tek geri al adımı).
    func beginOverlayChange() {
        history.record(snapshot)
    }

    func updateOverlay(_ id: UUID, center: CGPoint? = nil, relativeSize: Double? = nil, colorHex: String? = nil, text: String? = nil) {
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { return }
        if let center {
            overlays[index].center = CGPoint(x: min(max(center.x, 0), 1), y: min(max(center.y, 0), 1))
        }
        if let relativeSize { overlays[index].relativeSize = min(max(relativeSize, 0.03), 0.45) }
        if let colorHex { overlays[index].colorHex = colorHex }
        if let text { overlays[index].text = text }
        scheduleFinalPreview()
    }

    func endOverlayChange() {
        scheduleFinalPreview()
    }

    func removeOverlay(_ id: UUID) {
        guard overlays.contains(where: { $0.id == id }) else { return }
        history.record(snapshot)
        overlays.removeAll { $0.id == id }
        if selectedOverlayID == id { selectedOverlayID = nil }
        scheduleFinalPreview()
    }

    // MARK: Önizleme ve çıktı

    private func refreshPreview(force: Bool) {
        let now = clock()
        guard force || now.timeIntervalSince(lastPreviewAt) >= Self.previewInterval, let sourceBuffer else { return }
        lastPreviewAt = now
        preview = StickerRenderer.maskedPreview(source: sourceBuffer, mask: mask)
    }

    private func scheduleFinalPreview() {
        finalPreviewTask?.cancel()
        guard phase == .editing, let source else { return }
        let mask = mask, overlays = overlays, options = options, delay = finalPreviewDelay
        finalPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .utility) {
                try? StickerRenderer.render(source: source, mask: mask, overlays: overlays, options: options).image
            }.value
            guard !Task.isCancelled else { return }
            self?.finalPreview = image
        }
    }

    /// Kaydetmek için şeffaf PNG (en fazla 512×512).
    func render() async throws -> StickerRenderResult {
        guard let source else { throw StickerRenderError.empty }
        phase = .saving
        defer { phase = .editing }
        let mask = mask, overlays = overlays, options = options
        return try await Task.detached(priority: .userInitiated) {
            try StickerRenderer.render(source: source, mask: mask, overlays: overlays, options: options)
        }.value
    }

    func cancelBackgroundWork() {
        finalPreviewTask?.cancel()
        finalPreviewTask = nil
    }
}
