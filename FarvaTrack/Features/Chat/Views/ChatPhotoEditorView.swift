import SwiftUI
import UIKit

// MARK: - Yazı renkleri

enum PhotoEditPalette {
    static let colors: [Color] = [
        .white, .black, Color(red: 0.85, green: 0.12, blue: 0.22), Color(red: 1, green: 0.8, blue: 0.1),
        Color(red: 0.2, green: 0.78, blue: 0.35), Color(red: 0.15, green: 0.5, blue: 1), Color(red: 1, green: 0.45, blue: 0.7)
    ]
    static let names = ["Beyaz", "Siyah", "Kırmızı", "Sarı", "Yeşil", "Mavi", "Pembe"]

    static func color(_ index: Int) -> Color {
        colors[min(max(index, 0), colors.count - 1)]
    }
}

extension PhotoEditColor {
    var swiftUI: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(min(max(r, 0), 1)), green: Double(min(max(g, 0), 1)), blue: Double(min(max(b, 0), 1)), alpha: 1)
    }
}

// MARK: - Çizgilerin çizimi (ekranda ve son görüntüde aynı)

enum PhotoEditStrokeRenderer {
    /// Yumuşak çizgi: ardışık noktaların orta noktalarından geçen eğriler (titrek görünmez).
    static func path(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: first)
            return path
        }
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        for index in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[index].x + points[index + 1].x) / 2, y: (points[index].y + points[index + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[index])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    static func draw(_ strokes: [PhotoEditStroke], in context: inout GraphicsContext, full: CGSize) {
        for stroke in strokes { draw(stroke, in: &context, full: full) }
    }

    static func draw(_ stroke: PhotoEditStroke, in context: inout GraphicsContext, full: CGSize) {
        let path = path(stroke.points.map { CGPoint(x: $0.x * full.width, y: $0.y * full.height) })
        let width = max(0.5, stroke.width * full.width)
        if stroke.isEraser {
            // Yalnızca çizim katmanını siler (fotoğraf ayrı katmanda).
            var eraser = context
            eraser.blendMode = .clear
            eraser.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            return
        }
        let color = stroke.color.swiftUI
        switch stroke.brush {
        case .pen:
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        case .marker:
            context.stroke(path, with: .color(color.opacity(stroke.brush.opacity)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        case .highlighter:
            context.stroke(path, with: .color(color.opacity(stroke.brush.opacity)),
                           style: StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round))
        case .neon:
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: width * 0.9))
                glow.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * 1.6, lineCap: .round, lineJoin: .round))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: width * 0.4, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Bileşik görüntü

/// Fotoğraf + çizimler (+ isteğe bağlı katmanlar), `crop` bölgesi `size` boyutunda gösterilir.
struct PhotoEditComposite: View {
    let image: UIImage
    let document: PhotoEditDocument
    let crop: CGRect
    let size: CGSize
    var showsLayers = true
    var liveStroke: PhotoEditStroke?
    var stickerImages: [String: UIImage] = [:]

    var body: some View {
        let full = PhotoEditGeometry.fullDisplaySize(displaySize: size, crop: crop)
        ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .frame(width: full.width, height: full.height)
            Canvas { context, _ in
                PhotoEditStrokeRenderer.draw(document.strokes + (liveStroke.map { [$0] } ?? []), in: &context, full: full)
            }
            .frame(width: full.width, height: full.height)
            if showsLayers {
                ForEach(document.layers) { layer in
                    PhotoEditLayerView(layer: layer, fullWidth: full.width, stickerImages: stickerImages)
                        .position(x: layer.center.x * full.width, y: layer.center.y * full.height)
                }
            }
        }
        .frame(width: full.width, height: full.height, alignment: .topLeading)
        .offset(x: -crop.minX * full.width, y: -crop.minY * full.height)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }
}

/// Tek bir yazı ya da sticker katmanı (boyutlar orijinal genişliğe göre; ölçek yazı boyutuna işlenir: net çizim).
struct PhotoEditLayerView: View {
    let layer: PhotoEditLayer
    let fullWidth: CGFloat
    let stickerImages: [String: UIImage]

    var body: some View {
        Group {
            switch layer.content {
            case .text(let text, let colorIndex):
                Text(text)
                    .font(.system(size: max(4, PhotoEditLayer.textSizeFraction * fullWidth * layer.scale), weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PhotoEditPalette.color(colorIndex))
                    .shadow(color: .black.opacity(colorIndex == 1 ? 0 : 0.45), radius: fullWidth * 0.004 * layer.scale)
                    .fixedSize()
            case .sticker(let id, let aspect):
                let width = PhotoEditLayer.stickerWidthFraction * fullWidth * layer.scale
                if let image = stickerImages[id] {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: width, height: width / max(aspect, 0.05))
                } else {
                    Color.clear.frame(width: width, height: width / max(aspect, 0.05))
                }
            }
        }
        .rotationEffect(.radians(layer.rotation))
    }
}

// MARK: - Düzenleyici

/// WhatsApp benzeri: kırp, sticker, yazı, kalemler (silgi, boyut, ofset, renk damlalığı), açıklama, kaydet, gönder.
struct ChatPhotoEditorView: View {
    let image: UIImage
    let stickers: [StickerItem]
    /// Gönderirken fotoğrafın altına yazı (açıklama) eklenebilsin mi.
    var allowsCaption = true
    /// Sol üstteki ✕: düzenlemeyi bırakır.
    let onClose: () -> Void
    /// Düzenlenmemişse görüntü `nil` (orijinal dosya gider); ikinci değer açıklama.
    let onSend: (UIImage?, String) -> Void
    let onSave: (UIImage?) async -> String

    private enum Mode: Equatable { case none, draw, crop }

    @State private var document = PhotoEditDocument()
    @State private var history = UndoStack<PhotoEditDocument>(limit: 30)
    @State private var mode: Mode = .none
    @State private var caption = ""
    @FocusState private var captionFocused: Bool

    // Kalem
    @State private var brush: PhotoEditBrush = .pen
    @State private var erasing = false
    @State private var penColor: PhotoEditColor = .white
    @State private var liveStroke: PhotoEditStroke?
    @State private var drawTouch: CGPoint?
    @State private var drawPoint: CGPoint?
    @State private var showColorPanel = false
    @State private var showBrushSettings = false
    @AppStorage("photoEdit.brushSize") private var brushSize: Double = 7
    @AppStorage("photoEdit.brushOffset") private var brushOffset: Double = 0
    // Renk damlalığı
    @State private var picking = false
    @State private var sampler: PhotoEditPixelSampler?
    @State private var pickerTouch: CGPoint?
    @State private var pickedPreview: PhotoEditColor?

    // Kırpma
    @State private var draftCrop = PhotoEditDocument.fullCrop
    @State private var cropStart: CGRect?
    @State private var activeCropHandle: PhotoEditGeometry.CropHandle?

    // Katmanlar
    @State private var selectedLayerID: UUID?
    @State private var activeLayerID: UUID?
    @State private var draggingLayerOverTrash = false
    @State private var trashFrame: CGRect = .zero
    @State private var textEntry: TextEntry?
    @State private var showStickerSheet = false
    @State private var stickerImages: [String: UIImage] = [:]
    @State private var toast: String?
    @State private var saving = false

    private struct TextEntry: Equatable {
        var layerID: UUID?
        var text: String
        var colorIndex: Int
    }

    private static let coordinateSpace = "photoEditor"
    private static let cropSpace = "photoCrop"
    /// Renk damlalığının parmağın ne kadar üstünde ölçtüğü.
    private static let pickerOffset: CGFloat = 72
    private var imageSize: CGSize { image.size }
    private var heightOverWidth: CGFloat { imageSize.height / max(imageSize.width, 1) }
    private var settings: PhotoEditBrushSettings {
        PhotoEditBrushSettings(size: CGFloat(brushSize), offset: CGFloat(brushOffset))
    }

    init(image: UIImage, stickers: [StickerItem], allowsCaption: Bool = true,
         onClose: @escaping () -> Void, onSend: @escaping (UIImage?, String) -> Void, onSave: @escaping (UIImage?) async -> String) {
        self.image = image
        self.stickers = stickers
        self.allowsCaption = allowsCaption
        self.onClose = onClose
        self.onSend = onSend
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                let bounds = geometry.size
                let crop = mode == .crop ? PhotoEditDocument.fullCrop : document.crop
                let size = PhotoEditGeometry.fitted(aspect: PhotoEditGeometry.aspect(of: crop, imageSize: imageSize),
                                                    in: CGSize(width: bounds.width - (mode == .crop ? 32 : 0),
                                                               height: bounds.height - (mode == .crop ? 32 : 0)))
                let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
                ZStack(alignment: .topLeading) {
                    // Alan her kipte aynı kalsın: tuval yalnızca kendi boyutunda olursa (kalem/kırpma kipinde)
                    // ortalanıp üstüne bir de öteleme eklenir ve fotoğraf sağa-aşağı kayar.
                    Color.clear.frame(width: bounds.width, height: bounds.height)
                    canvas(crop: crop, size: size)
                        .frame(width: size.width, height: size.height)
                        .offset(x: origin.x, y: origin.y)
                    if mode == .none, textEntry == nil {
                        // Katman hareketleri tüm alanda: taşı, iki parmakla büyüt ve döndür (aynı anda).
                        PhotoEditTransformSurface(
                            onTap: { location in tapCanvas(at: location, origin: origin, size: size, crop: crop) },
                            onBegin: { location in beginLayerGesture(at: location, origin: origin, size: size, crop: crop) },
                            onChange: { translation, scale, rotation, location in
                                updateLayerGesture(translation: translation, scale: scale, rotation: rotation,
                                                   location: location, size: size, crop: crop)
                            },
                            onEnd: { endLayerGesture() }
                        )
                    }
                }
                .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            }
            .padding(.top, 64)
            .padding(.bottom, 96)
            .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }

            if let entry = textEntry {
                textEditor(entry)
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .sheet(isPresented: $showStickerSheet) { stickerSheet }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 70)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { self.toast = nil }
                    }
            }
        }
    }

    // MARK: Tuval

    @ViewBuilder
    private func canvas(crop: CGRect, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            PhotoEditComposite(image: image, document: document, crop: crop, size: size,
                               showsLayers: mode == .crop, liveStroke: liveStroke, stickerImages: stickerImages)
                .accessibilityLabel("Düzenlenen fotoğraf")
            switch mode {
            case .crop:
                cropOverlay(size: size)
            case .draw:
                layersOverlay(crop: crop, size: size).allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(drawGesture(size: size, crop: crop), including: picking ? .none : .all)
                    .accessibilityHidden(true)
                brushCursor
                if picking {
                    pickerOverlay(size: size)
                }
            case .none:
                layersOverlay(crop: crop, size: size).allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func layersOverlay(crop: CGRect, size: CGSize) -> some View {
        let full = PhotoEditGeometry.fullDisplaySize(displaySize: size, crop: crop)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: full.width, height: full.height)
            ForEach(document.layers) { layer in
                PhotoEditLayerView(layer: layer, fullWidth: full.width, stickerImages: stickerImages)
                    .scaleEffect(activeLayerID == layer.id && draggingLayerOverTrash ? 0.6 : 1)
                    .opacity(activeLayerID == layer.id && draggingLayerOverTrash ? 0.6 : 1)
                    .position(x: layer.center.x * full.width, y: layer.center.y * full.height)
                    .accessibilityElement()
                    .accessibilityLabel(layerLabel(layer))
                    .accessibilityAction(named: "Sil") { delete(layer.id) }
                    .accessibilityAction(named: "Büyüt") { rescale(layer.id, by: 1.2) }
                    .accessibilityAction(named: "Küçült") { rescale(layer.id, by: 1 / 1.2) }
            }
        }
        .frame(width: full.width, height: full.height, alignment: .topLeading)
        .offset(x: -crop.minX * full.width, y: -crop.minY * full.height)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .animation(.easeOut(duration: 0.15), value: draggingLayerOverTrash)
    }

    private func layerLabel(_ layer: PhotoEditLayer) -> String {
        switch layer.content {
        case .text(let text, _): return "Yazı: \(text)"
        case .sticker: return "Sticker"
        }
    }

    // MARK: Katman hareketleri

    private func toImagePoint(_ location: CGPoint, origin: CGPoint, size: CGSize, crop: CGRect) -> CGPoint {
        PhotoEditGeometry.toImage(CGPoint(x: location.x - origin.x, y: location.y - origin.y), displaySize: size, crop: crop)
    }

    /// Dokunma: yazıya dokununca düzenlenir; sticker'a dokunmak bir şey yapmaz (seçim çizgisi yok).
    private func tapCanvas(at location: CGPoint, origin: CGPoint, size: CGSize, crop: CGRect) {
        captionFocused = false
        let point = toImagePoint(location, origin: origin, size: size, crop: crop)
        guard let id = PhotoEditGeometry.layerHit(document.layers, at: point, heightOverWidth: heightOverWidth),
              let layer = document.layers.first(where: { $0.id == id }) else { return }
        selectedLayerID = id
        edit(layer)
    }

    /// Hareket başladığı yerdeki katmana (yoksa en son dokunulan/eklenen katmana) uygulanır.
    private func beginLayerGesture(at location: CGPoint, origin: CGPoint, size: CGSize, crop: CGRect) -> Bool {
        let point = toImagePoint(location, origin: origin, size: size, crop: crop)
        let target = PhotoEditGeometry.layerHit(document.layers, at: point, heightOverWidth: heightOverWidth) ?? selectedLayerID
        guard let target, document.layers.contains(where: { $0.id == target }) else { return false }
        history.record(document)
        selectedLayerID = target
        activeLayerID = target
        captionFocused = false
        return true
    }

    private func updateLayerGesture(translation: CGSize, scale: CGFloat, rotation: CGFloat, location: CGPoint,
                                    size: CGSize, crop: CGRect) {
        guard let id = activeLayerID, let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
        let full = PhotoEditGeometry.fullDisplaySize(displaySize: size, crop: crop)
        let delta = CGSize(width: translation.width / max(full.width, 1), height: translation.height / max(full.height, 1))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            document.layers[index] = document.layers[index].applying(translation: delta, scale: scale, rotation: Double(rotation))
        }
        // Yüzey, düzenleyicinin 64 pt altından başlar.
        let over = trashFrame.insetBy(dx: -24, dy: -24).contains(CGPoint(x: location.x, y: location.y + 64))
        if over != draggingLayerOverTrash {
            draggingLayerOverTrash = over
            if over { Haptics.impact(.light) }
        }
    }

    private func endLayerGesture() {
        if draggingLayerOverTrash, let id = activeLayerID {
            document.layers.removeAll { $0.id == id }
            if selectedLayerID == id { selectedLayerID = nil }
            Haptics.impact(.medium)
        }
        activeLayerID = nil
        draggingLayerOverTrash = false
    }

    // MARK: Kalem

    private func drawGesture(size: CGSize, crop: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let full = PhotoEditGeometry.fullDisplaySize(displaySize: size, crop: crop)
                let display = settings.drawPoint(forTouch: value.location)
                drawTouch = value.location
                drawPoint = display
                let point = PhotoEditGeometry.toImage(display, displaySize: size, crop: crop)
                if liveStroke == nil {
                    let base = CGFloat(brushSize) * (erasing ? 1.4 : brush.widthFactor)
                    liveStroke = PhotoEditStroke(points: [point], color: penColor, width: base / max(full.width, 1),
                                                 brush: brush, isEraser: erasing)
                } else if let last = liveStroke?.points.last {
                    // Çok yakın noktalar atlanır (pürüzsüz eğri).
                    let dx = (point.x - last.x) * full.width, dy = (point.y - last.y) * full.height
                    if dx * dx + dy * dy > 2.25 { liveStroke?.points.append(point) }
                }
            }
            .onEnded { _ in
                drawTouch = nil
                drawPoint = nil
                guard let stroke = liveStroke else { return }
                liveStroke = nil
                history.record(document)
                document.strokes.append(stroke)
            }
    }

    /// Çizerken fırçanın nereye çizdiğini gösteren halka (ofset varsa parmağa ince çizgiyle bağlı).
    @ViewBuilder
    private var brushCursor: some View {
        if let drawPoint, let drawTouch {
            let diameter = max(10, CGFloat(brushSize) * (erasing ? 1.4 : brush.widthFactor))
            ZStack {
                if brushOffset > 1 {
                    Path { path in
                        path.move(to: drawTouch)
                        path.addLine(to: CGPoint(x: drawPoint.x, y: drawPoint.y + diameter / 2))
                    }
                    .stroke(.white.opacity(0.5), lineWidth: 1)
                }
                Circle()
                    .strokeBorder(erasing ? Color.white : (penColor.isLight ? Color.black.opacity(0.6) : Color.white), lineWidth: 1.5)
                    .frame(width: diameter, height: diameter)
                    .position(drawPoint)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: Renk damlalığı

    /// Parmağı basılı tutup sürükledikçe parmağın üstündeki noktanın rengi önizlenir; bırakınca seçilir.
    private func pickerOverlay(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            pickerTouch = value.location
                            let sample = CGPoint(x: value.location.x, y: value.location.y - Self.pickerOffset)
                            let unit = CGPoint(x: sample.x / max(size.width, 1), y: sample.y / max(size.height, 1))
                            if let color = sampler?.color(atUnit: unit), color != pickedPreview {
                                pickedPreview = color
                                Haptics.selection()
                            }
                        }
                        .onEnded { _ in
                            if let pickedPreview { penColor = pickedPreview }
                            picking = false
                            pickerTouch = nil
                            pickedPreview = nil
                            sampler = nil
                            erasing = false
                            Haptics.success()
                        }
                )
            if let touch = pickerTouch {
                let sample = CGPoint(x: touch.x, y: touch.y - Self.pickerOffset)
                ZStack {
                    Circle()
                        .fill((pickedPreview ?? penColor).swiftUI)
                        .frame(width: 58, height: 58)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.4), radius: 6)
                        .offset(y: -44)
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                        .background(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 3.5))
                        .frame(width: 14, height: 14)
                }
                .position(sample)
                .allowsHitTesting(false)
            } else {
                Text("Parmağını basılı tutup renklerin üzerinde gezdir")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(width: size.width)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Ekrandaki görüntü (fotoğraf + çizimler + katmanlar) piksel olarak hazırlanır.
    private func startPicking() {
        let crop = document.crop
        let displayWidth: CGFloat = min(UIScreen.main.bounds.width, 600)
        let size = PhotoEditGeometry.fitted(aspect: PhotoEditGeometry.aspect(of: crop, imageSize: imageSize),
                                            in: CGSize(width: displayWidth, height: displayWidth * 3))
        let composite = PhotoEditComposite(image: image, document: document, crop: crop, size: size,
                                           showsLayers: true, stickerImages: stickerImages)
        let renderer = ImageRenderer(content: composite)
        renderer.scale = 1
        renderer.isOpaque = true
        sampler = renderer.cgImage.flatMap(PhotoEditPixelSampler.init(cgImage:))
        guard sampler != nil else {
            withAnimation { toast = "Renk okunamadı" }
            return
        }
        showColorPanel = false
        showBrushSettings = false
        picking = true
        Haptics.selection()
    }

    // MARK: Kırpma

    private func cropOverlay(size: CGSize) -> some View {
        let rect = CGRect(x: draftCrop.minX * size.width, y: draftCrop.minY * size.height,
                          width: draftCrop.width * size.width, height: draftCrop.height * size.height)
        let dragging = activeCropHandle != nil
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(dragging ? 0.4 : 0.6), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            // Çerçeve, taşıma alanı ve (sürüklerken) üçte bir kılavuzları.
            Path { path in
                path.addRect(rect)
                if dragging {
                    for i in 1...2 {
                        let x = rect.minX + rect.width * CGFloat(i) / 3, y = rect.minY + rect.height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
                        path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y))
                    }
                }
            }
            .stroke(.white.opacity(0.85), lineWidth: 1)
            .allowsHitTesting(false)

            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: max(rect.width - 60, 1), height: max(rect.height - 60, 1))
                .position(x: rect.midX, y: rect.midY)
                .gesture(cropGesture(.move, size: size))
                .accessibilityLabel("Kırpma alanı")

            // Kenar tutamaçları (kısa çubuklar).
            ForEach(PhotoEditGeometry.CropHandle.edges, id: \.self) { handle in
                let horizontal = handle == .top || handle == .bottom
                Capsule()
                    .fill(.white)
                    .frame(width: horizontal ? 28 : 4, height: horizontal ? 4 : 28)
                    .frame(width: horizontal ? max(rect.width - 70, 30) : 44, height: horizontal ? 44 : max(rect.height - 70, 30))
                    .contentShape(Rectangle())
                    .position(edgePoint(handle, rect: rect))
                    .gesture(cropGesture(handle, size: size))
                    .accessibilityHidden(true)
            }

            // Köşe tutamaçları (L biçimli).
            ForEach(PhotoEditGeometry.CropHandle.corners, id: \.self) { handle in
                CropCorner(handle: handle)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .square))
                    .frame(width: 22, height: 22)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .position(cornerPoint(handle, rect: rect))
                    .gesture(cropGesture(handle, size: size))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: Self.cropSpace)
        .transaction { $0.animation = nil }
    }

    private func cornerPoint(_ handle: PhotoEditGeometry.CropHandle, rect: CGRect) -> CGPoint {
        // Köşe simgesi çerçevenin içine doğru açılır; tutamaç merkezi köşenin biraz içinde.
        let inset: CGFloat = 9
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX + inset, y: rect.minY + inset)
        case .topRight: return CGPoint(x: rect.maxX - inset, y: rect.minY + inset)
        case .bottomLeft: return CGPoint(x: rect.minX + inset, y: rect.maxY - inset)
        default: return CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        }
    }

    private func edgePoint(_ handle: PhotoEditGeometry.CropHandle, rect: CGRect) -> CGPoint {
        switch handle {
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        default: return CGPoint(x: rect.maxX, y: rect.midY)
        }
    }

    /// Öteleme sabit (tutamaçla birlikte kaymayan) koordinat alanında ölçülür: titreme olmaz.
    private func cropGesture(_ handle: PhotoEditGeometry.CropHandle, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.cropSpace))
            .onChanged { value in
                if cropStart == nil {
                    cropStart = draftCrop
                    activeCropHandle = handle
                }
                guard let start = cropStart else { return }
                let next = PhotoEditGeometry.adjust(start, handle: handle,
                                                    translation: CGSize(width: value.translation.width / max(size.width, 1),
                                                                        height: value.translation.height / max(size.height, 1)))
                if next != draftCrop {
                    // En küçük boyuta ya da kenara dayanınca hafif titreşim.
                    let hitLimit = handle != .move && (abs(next.width - PhotoEditGeometry.minimumCropSide) < 0.0005
                                                        || abs(next.height - PhotoEditGeometry.minimumCropSide) < 0.0005)
                    if hitLimit, abs(draftCrop.width - next.width) > 0.0005 || abs(draftCrop.height - next.height) > 0.0005 {
                        Haptics.selection()
                    }
                    draftCrop = next
                }
            }
            .onEnded { _ in
                cropStart = nil
                withAnimation(.easeOut(duration: 0.2)) { activeCropHandle = nil }
            }
    }

    // MARK: Çubuklar

    private var topBar: some View {
        HStack(spacing: 12) {
            switch mode {
            case .none:
                circleButton("xmark", label: "Kapat") { onClose() }
                circleButton(saving ? "hourglass" : "arrow.down.to.line", label: "Fotoğraflar'a indir") { save() }
                    .disabled(saving)
                Spacer()
                if history.canUndo {
                    circleButton("arrow.uturn.backward", label: "Geri al") { undo() }
                }
                circleButton("crop", label: "Kırp") {
                    draftCrop = document.crop
                    captionFocused = false
                    mode = .crop
                }
                if !stickers.isEmpty {
                    circleButton("face.smiling", label: "Sticker ekle") { showStickerSheet = true }
                }
                circleButton("textformat", label: "Yazı ekle") {
                    textEntry = TextEntry(layerID: nil, text: "", colorIndex: 0)
                }
                circleButton("pencil.tip", label: "Çiz") {
                    captionFocused = false
                    erasing = false
                    mode = .draw
                }
            case .draw:
                circleButton("arrow.uturn.backward", label: "Geri al") { undo() }
                    .disabled(!history.canUndo)
                    .opacity(history.canUndo ? 1 : 0.4)
                Spacer()
                circleButton("checkmark", label: "Çizimi bitir", highlighted: true) {
                    mode = .none
                    erasing = false
                    picking = false
                    showColorPanel = false
                    showBrushSettings = false
                }
            case .crop:
                circleButton("xmark", label: "Kırpmayı iptal et") { mode = .none }
                Spacer()
                Button("Sıfırla") { draftCrop = PhotoEditDocument.fullCrop }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .disabled(PhotoEditGeometry.isFull(draftCrop))
                Spacer()
                circleButton("checkmark", label: "Kırpmayı uygula", highlighted: true) {
                    if draftCrop != document.crop {
                        history.record(document)
                        document.crop = draftCrop
                    }
                    mode = .none
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch mode {
        case .draw:
            drawToolbar
        case .none:
            if activeLayerID != nil {
                trash
            } else {
                captionBar
            }
        case .crop:
            EmptyView()
        }
    }

    private var trash: some View {
        Image(systemName: draggingLayerOverTrash ? "trash.fill" : "trash")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(draggingLayerOverTrash ? Color.ftDanger : Color.white.opacity(0.2), in: Circle())
            .scaleEffect(draggingLayerOverTrash ? 1.15 : 1)
            .animation(.spring(response: 0.25), value: draggingLayerOverTrash)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { trashFrame = proxy.frame(in: .named(Self.coordinateSpace)) }
                    .onChange(of: proxy.frame(in: .named(Self.coordinateSpace))) { _, frame in trashFrame = frame }
            })
            .padding(.bottom, 24)
            .accessibilityLabel("Silmek için buraya sürükle")
    }

    /// Fotoğrafın altına yazı (normal sohbetteki gibi) ve gönder.
    private var captionBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if allowsCaption {
                TextField("Açıklama ekle…", text: $caption, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($captionFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Fotoğrafın altına yazı")
            } else {
                Spacer()
            }
            Button {
                Haptics.impact(.medium)
                captionFocused = false
                onSend(document.isEdited ? render() : nil, caption.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.ftAccent, in: Circle())
            }
            .accessibilityLabel("Gönder")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    // MARK: Kalem araç çubuğu

    private var drawToolbar: some View {
        VStack(spacing: 10) {
            if showBrushSettings { brushSettingsPanel }
            if showColorPanel { colorPanel }
            HStack(spacing: 6) {
                ForEach(PhotoEditBrush.allCases) { item in
                    toolButton(item.systemImage, label: item.title, selected: !erasing && brush == item) {
                        brush = item
                        erasing = false
                    }
                }
                toolButton("eraser", label: "Silgi", selected: erasing) { erasing = true }
                Spacer(minLength: 4)
                Button {
                    Haptics.selection()
                    showBrushSettings = false
                    withAnimation(.easeOut(duration: 0.18)) { showColorPanel.toggle() }
                } label: {
                    Circle()
                        .fill(penColor.swiftUI)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                        .frame(width: 42, height: 42)
                }
                .accessibilityLabel("Renk seç")
                toolButton("slider.horizontal.3", label: "Kalem ayarları", selected: showBrushSettings) {
                    showColorPanel = false
                    withAnimation(.easeOut(duration: 0.18)) { showBrushSettings.toggle() }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func toolButton(_ systemImage: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Color.white)
                .frame(width: 40, height: 40)
                .background(selected ? Color.white : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var brushSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Boyut").font(.subheadline.weight(.semibold))
                Spacer()
                Circle()
                    .fill(erasing ? Color.white.opacity(0.4) : penColor.swiftUI)
                    .frame(width: CGFloat(brushSize), height: CGFloat(brushSize))
                    .frame(width: 42, height: 42)
            }
            Slider(value: $brushSize, in: Double(PhotoEditBrushSettings.sizeRange.lowerBound)...Double(PhotoEditBrushSettings.sizeRange.upperBound))
                .accessibilityLabel("Kalem boyutu")
            HStack {
                Text("Ofset").font(.subheadline.weight(.semibold))
                Spacer()
                Text(brushOffset < 1 ? "Parmağın altında" : "\(Int(brushOffset)) pt yukarıda")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Slider(value: $brushOffset, in: Double(PhotoEditBrushSettings.offsetRange.lowerBound)...Double(PhotoEditBrushSettings.offsetRange.upperBound))
                .accessibilityLabel("Kalem ofseti")
                .accessibilityHint("Çizimin parmağın ne kadar üstünde olacağı")
        }
        .tint(Color.ftAccentLight)
        .foregroundStyle(.white)
        .padding(14)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var colorPanel: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                ForEach(PhotoEditColor.palette, id: \.self) { color in
                    Circle()
                        .fill(color.swiftUI)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(.white, lineWidth: color == penColor ? 3 : 1))
                        .onTapGesture {
                            penColor = color
                            erasing = false
                            Haptics.selection()
                        }
                        .accessibilityElement()
                        .accessibilityLabel("Renk")
                        .accessibilityAddTraits(color == penColor ? [.isButton, .isSelected] : .isButton)
                }
            }
            HStack(spacing: 10) {
                Button {
                    startPicking()
                } label: {
                    Label("Fotoğraftan seç", systemImage: "eyedropper")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }
                .accessibilityHint("Parmağını fotoğrafın üzerinde gezdirip bırakınca o renk seçilir")
                Spacer()
                ColorPicker("Özel renk", selection: Binding(
                    get: { penColor.swiftUI },
                    set: { penColor = PhotoEditColor($0); erasing = false }
                ), supportsOpacity: false)
                .labelsHidden()
                Text("Özel").font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func circleButton(_ systemImage: String, label: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(highlighted ? Color.ftAccent : Color.black.opacity(0.45), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func colorRow(selection: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            ForEach(PhotoEditPalette.colors.indices, id: \.self) { index in
                Circle()
                    .fill(PhotoEditPalette.colors[index])
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(.white, lineWidth: selection.wrappedValue == index ? 3 : 1))
                    .scaleEffect(selection.wrappedValue == index ? 1.15 : 1)
                    .onTapGesture {
                        selection.wrappedValue = index
                        Haptics.selection()
                    }
                    .accessibilityElement()
                    .accessibilityLabel(PhotoEditPalette.names[index])
                    .accessibilityAddTraits(selection.wrappedValue == index ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.35), in: Capsule())
    }

    private func save() {
        Task {
            saving = true
            let message = await onSave(document.isEdited ? render() : nil)
            saving = false
            withAnimation { toast = message }
        }
    }

    // MARK: Yazı

    private func textEditor(_ entry: TextEntry) -> some View {
        let binding = Binding(get: { textEntry ?? entry }, set: { textEntry = $0 })
        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { commitText() }
            VStack(spacing: 18) {
                HStack {
                    if entry.layerID != nil {
                        Button(role: .destructive) {
                            if let id = entry.layerID { delete(id) }
                            textEntry = nil
                        } label: {
                            Image(systemName: "trash").font(.body.weight(.semibold)).foregroundStyle(.white)
                                .frame(width: 40, height: 40).background(Color.black.opacity(0.45), in: Circle())
                        }
                        .accessibilityLabel("Yazıyı sil")
                    }
                    Spacer()
                    circleButton("checkmark", label: "Yazıyı bitir", highlighted: true) { commitText() }
                }
                .padding(.horizontal, 16)
                Spacer()
                PhotoTextField(text: binding.text)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(PhotoEditPalette.color(binding.wrappedValue.colorIndex))
                Spacer()
                colorRow(selection: binding.colorIndex)
                    .padding(.bottom, 16)
            }
            .padding(.top, 10)
        }
    }

    private func commitText() {
        guard let entry = textEntry else { return }
        textEntry = nil
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        history.record(document)
        if let id = entry.layerID, let index = document.layers.firstIndex(where: { $0.id == id }) {
            if text.isEmpty {
                document.layers.remove(at: index)
            } else {
                document.layers[index].content = .text(text, colorIndex: entry.colorIndex)
            }
        } else if !text.isEmpty {
            let layer = PhotoEditLayer(content: .text(text, colorIndex: entry.colorIndex), center: visibleCenter)
            document.layers.append(layer)
            selectedLayerID = layer.id
        }
    }

    private func edit(_ layer: PhotoEditLayer) {
        if case .text(let text, let color) = layer.content {
            textEntry = TextEntry(layerID: layer.id, text: text, colorIndex: color)
        }
    }

    private var visibleCenter: CGPoint {
        CGPoint(x: document.crop.midX, y: document.crop.midY)
    }

    // MARK: Sticker

    private var stickerSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 12)], spacing: 12) {
                    ForEach(stickers) { sticker in
                        Button {
                            addSticker(sticker)
                        } label: {
                            CachedImageView(url: sticker.fileURL, contentMode: .fit)
                                .frame(width: 80, height: 80)
                        }
                        .accessibilityLabel("Sticker ekle")
                    }
                }
                .padding(16)
            }
            .ftScreenBackground()
            .navigationTitle("Sticker ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showStickerSheet = false } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Kapat")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addSticker(_ sticker: StickerItem) {
        showStickerSheet = false
        if stickerImages[sticker.id] == nil {
            stickerImages[sticker.id] = UIImage(contentsOfFile: sticker.fileURL.path)
        }
        let aspect = CGFloat(sticker.width) / CGFloat(max(sticker.height, 1))
        history.record(document)
        let layer = PhotoEditLayer(content: .sticker(id: sticker.id, aspect: aspect), center: visibleCenter)
        document.layers.append(layer)
        selectedLayerID = layer.id
        Haptics.impact(.light)
    }

    // MARK: Düzenleme işlemleri

    private func delete(_ id: UUID) {
        history.record(document)
        document.layers.removeAll { $0.id == id }
        if selectedLayerID == id { selectedLayerID = nil }
    }

    private func rescale(_ id: UUID, by factor: CGFloat) {
        guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
        history.record(document)
        document.layers[index] = document.layers[index].applying(translation: .zero, scale: factor, rotation: 0)
    }

    private func undo() {
        if let previous = history.undo(current: document) {
            document = previous
            Haptics.selection()
        }
    }

    // MARK: Son görüntü

    /// Kırpılmış bölge orijinal çözünürlükte (piksel = nokta, ölçek 1) çizilir.
    @MainActor
    private func render() -> UIImage? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let rect = PhotoEditGeometry.pixelRect(crop: document.crop, pixelSize: pixelSize)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        let crop = CGRect(x: rect.minX / pixelSize.width, y: rect.minY / pixelSize.height,
                          width: rect.width / pixelSize.width, height: rect.height / pixelSize.height)
        let composite = PhotoEditComposite(image: image, document: document, crop: crop, size: rect.size,
                                           showsLayers: true, stickerImages: stickerImages)
        let renderer = ImageRenderer(content: composite.environment(\.colorScheme, .dark))
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// Kırpma köşesindeki L biçimi (çerçevenin içine doğru açılır).
private struct CropCorner: Shape {
    let handle: PhotoEditGeometry.CropHandle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch handle {
        case .topLeft:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .topRight:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomLeft:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        default:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return path
    }
}

/// Çok satırlı, ortalı yazı alanı (açılınca klavye gelir).
private struct PhotoTextField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Yazı", text: $text, axis: .vertical)
            .multilineTextAlignment(.center)
            .lineLimit(1...5)
            .focused($focused)
            .padding(.horizontal, 24)
            .onAppear { focused = true }
            .accessibilityLabel("Fotoğraf yazısı")
    }
}

// MARK: - Taşı + büyüt + döndür yüzeyi (UIKit)

/// Tek ya da iki parmakla taşıma, iki parmakla büyütme ve döndürme aynı anda ve artımlı uygulanır:
/// bir hareket bitip diğeri sürerken katman eski yerine dönmez. Parmak sayısı değişince öteleme sıçramaz.
struct PhotoEditTransformSurface: UIViewRepresentable {
    let onTap: (CGPoint) -> Void
    /// Hareketin uygulanacağı katman varsa `true`.
    let onBegin: (CGPoint) -> Bool
    let onChange: (_ translation: CGSize, _ scale: CGFloat, _ rotation: CGFloat, _ location: CGPoint) -> Void
    let onEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let coordinator = context.coordinator

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleRotate(_:)))
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        for recognizer in [pan, pinch, rotate] as [UIGestureRecognizer] {
            recognizer.delegate = coordinator
            view.addGestureRecognizer(recognizer)
        }
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PhotoEditTransformSurface
        private var active = Set<ObjectIdentifier>()
        private var engaged = false
        private var lastCentroid: CGPoint?
        private var lastTouchCount = 0

        init(parent: PhotoEditTransformSurface) {
            self.parent = parent
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onTap(gesture.location(in: gesture.view))
        }

        private func begin(_ gesture: UIGestureRecognizer) {
            if active.isEmpty {
                engaged = parent.onBegin(gesture.location(in: gesture.view))
            }
            active.insert(ObjectIdentifier(gesture))
        }

        private func finish(_ gesture: UIGestureRecognizer) {
            active.remove(ObjectIdentifier(gesture))
            if active.isEmpty {
                if engaged { parent.onEnd() }
                engaged = false
                lastCentroid = nil
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                begin(gesture)
                lastCentroid = location
                lastTouchCount = gesture.numberOfTouches
            case .changed:
                guard engaged else { return }
                // Parmak eklenip çıkınca ağırlık merkezi sıçrar: o adım uygulanmaz.
                if gesture.numberOfTouches != lastTouchCount || lastCentroid == nil {
                    lastTouchCount = gesture.numberOfTouches
                    lastCentroid = location
                    return
                }
                let previous = lastCentroid ?? location
                lastCentroid = location
                parent.onChange(CGSize(width: location.x - previous.x, height: location.y - previous.y), 1, 0, location)
            case .ended, .cancelled, .failed:
                finish(gesture)
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                begin(gesture)
                gesture.scale = 1
            case .changed:
                guard engaged else { return }
                parent.onChange(.zero, gesture.scale, 0, gesture.location(in: gesture.view))
                gesture.scale = 1
            case .ended, .cancelled, .failed:
                finish(gesture)
            default:
                break
            }
        }

        @objc func handleRotate(_ gesture: UIRotationGestureRecognizer) {
            switch gesture.state {
            case .began:
                begin(gesture)
                gesture.rotation = 0
            case .changed:
                guard engaged else { return }
                parent.onChange(.zero, 1, gesture.rotation, gesture.location(in: gesture.view))
                gesture.rotation = 0
            case .ended, .cancelled, .failed:
                finish(gesture)
            default:
                break
            }
        }
    }
}
