import SwiftUI
import UIKit

// MARK: - Renk paleti

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

// MARK: - Bileşik görüntü (ekranda ve son çizimde aynı)

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
                for stroke in document.strokes + (liveStroke.map { [$0] } ?? []) {
                    Self.draw(stroke, in: &context, full: full)
                }
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

    static func draw(_ stroke: PhotoEditStroke, in context: inout GraphicsContext, full: CGSize) {
        guard let first = stroke.points.first else { return }
        var path = Path()
        let scaled = { (p: CGPoint) in CGPoint(x: p.x * full.width, y: p.y * full.height) }
        path.move(to: scaled(first))
        if stroke.points.count == 1 {
            path.addLine(to: scaled(first))
        } else {
            for point in stroke.points.dropFirst() { path.addLine(to: scaled(point)) }
        }
        context.stroke(path, with: .color(PhotoEditPalette.color(stroke.colorIndex)),
                       style: StrokeStyle(lineWidth: stroke.width * full.width, lineCap: .round, lineJoin: .round))
    }
}

/// Tek bir yazı ya da sticker katmanı (boyutlar orijinal genişliğe göre, ölçek yazı boyutuna işlenir: net çizim).
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

/// WhatsApp benzeri: kırp, sticker, yazı, kalem (silgi + geri al), Fotoğraflar'a kaydet, gönder.
struct ChatPhotoEditorView: View {
    let image: UIImage
    let stickers: [StickerItem]
    /// Sol üstteki ✕: düzenlemeyi bırakıp yeniden çekime döner.
    let onClose: () -> Void
    /// Düzenlenmemişse `nil` (orijinal dosya gider), düzenlenmişse son görüntü.
    let onSend: (UIImage?) -> Void
    let onSave: (UIImage?) async -> String

    private enum Mode: Equatable { case none, draw, crop }

    @State private var document = PhotoEditDocument()
    @State private var history = UndoStack<PhotoEditDocument>(limit: 30)
    @State private var mode: Mode = .none
    @State private var erasing = false
    @State private var colorIndex = 0
    @State private var liveStroke: PhotoEditStroke?
    @State private var draftCrop = PhotoEditDocument.fullCrop
    @State private var cropStart: CGRect?
    @State private var layerStart: PhotoEditLayer?
    /// Ekranın herhangi bir yerindeki hareketin uygulanacağı katman (son dokunulan / eklenen).
    @State private var selectedLayerID: UUID?
    /// Süren hareket hiçbir katmana denk gelmediyse true (bitene kadar yok sayılır).
    @State private var gestureIgnored = false
    @State private var draggingLayerOverTrash = false
    @State private var draggingLayer = false
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
    private var imageSize: CGSize { image.size }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                let bounds = CGSize(width: geometry.size.width, height: geometry.size.height)
                let crop = mode == .crop ? PhotoEditDocument.fullCrop : document.crop
                let size = PhotoEditGeometry.fitted(aspect: PhotoEditGeometry.aspect(of: crop, imageSize: imageSize), in: bounds)
                ZStack {
                    // Katman hareketleri tüm alanda: parmağın katmanın üstünde olması gerekmez.
                    Color.clear.contentShape(Rectangle())
                    canvas(crop: crop, size: size)
                        .frame(width: size.width, height: size.height)
                        .position(x: bounds.width / 2, y: bounds.height / 2)
                }
                .frame(width: bounds.width, height: bounds.height)
                .simultaneousGesture(canvasGesture(crop: crop, size: size, bounds: bounds), including: mode == .none ? .all : .subviews)
            }
            .padding(.top, 64)
            .padding(.bottom, 96)

            VStack {
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
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(drawGesture(size: size, crop: crop))
                    .accessibilityHidden(true)
            case .none:
                layersOverlay(crop: crop, size: size)
            }
            if mode == .draw {
                // Çizerken katmanlar görünsün ama dokunuşları almasın.
                layersOverlay(crop: crop, size: size).allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func layersOverlay(crop: CGRect, size: CGSize) -> some View {
        let full = PhotoEditGeometry.fullDisplaySize(displaySize: size, crop: crop)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: full.width, height: full.height).allowsHitTesting(false)
            ForEach(document.layers) { layer in
                PhotoEditLayerView(layer: layer, fullWidth: full.width, stickerImages: stickerImages)
                    .padding(10)
                    .overlay {
                        if selectedLayerID == layer.id {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                                .rotationEffect(.radians(layer.rotation))
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // İlk dokunuş seçer; seçiliyken yazıya dokunmak düzenler.
                        if selectedLayerID == layer.id { edit(layer) } else { selectedLayerID = layer.id; Haptics.selection() }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(layerLabel(layer))
                    .accessibilityAction(named: "Sil") { delete(layer.id) }
                    .accessibilityAction(named: "Büyüt") { rescale(layer.id, by: 1.2) }
                    .accessibilityAction(named: "Küçült") { rescale(layer.id, by: 1 / 1.2) }
                    .position(x: layer.center.x * full.width, y: layer.center.y * full.height)
            }
        }
        .frame(width: full.width, height: full.height, alignment: .topLeading)
        .offset(x: -crop.minX * full.width, y: -crop.minY * full.height)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    private func layerLabel(_ layer: PhotoEditLayer) -> String {
        switch layer.content {
        case .text(let text, _): return "Yazı: \(text)"
        case .sticker: return "Sticker"
        }
    }

    // MARK: Hareketler

    private func drawGesture(size: CGSize, crop: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = PhotoEditGeometry.toImage(value.location, displaySize: size, crop: crop)
                let full = PhotoEditGeometry.fullDisplaySize(displaySize: size, crop: crop)
                if erasing {
                    let radius = 16 / max(full.width, 1)
                    let hit = PhotoEditGeometry.strokesHit(document.strokes, at: point, radius: radius,
                                                           heightOverWidth: imageSize.height / max(imageSize.width, 1))
                    guard !hit.isEmpty else { return }
                    history.record(document)
                    document.strokes.removeAll { hit.contains($0.id) }
                    return
                }
                if liveStroke == nil {
                    liveStroke = PhotoEditStroke(points: [point], colorIndex: colorIndex, width: 7 / max(full.width, 1))
                } else {
                    liveStroke?.points.append(point)
                }
            }
            .onEnded { _ in
                guard let stroke = liveStroke else { return }
                liveStroke = nil
                history.record(document)
                document.strokes.append(stroke)
            }
    }

    /// Tüm düzenleme alanındaki sürükle / iki parmak büyüt / döndür: başladığı yerdeki katmana,
    /// yoksa seçili katmana uygulanır.
    private func canvasGesture(crop: CGRect, size: CGSize, bounds: CGSize) -> some Gesture {
        let full = PhotoEditGeometry.fullDisplaySize(displaySize: size, crop: crop)
        let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        let drag = DragGesture(minimumDistance: 4, coordinateSpace: .local)
        return drag.simultaneously(with: MagnifyGesture().simultaneously(with: RotateGesture()))
            .onChanged { value in
                guard mode == .none, !gestureIgnored else { return }
                if layerStart == nil {
                    var targetID = selectedLayerID
                    if let start = value.first?.startLocation {
                        let local = CGPoint(x: start.x - origin.x, y: start.y - origin.y)
                        let point = PhotoEditGeometry.toImage(local, displaySize: size, crop: crop)
                        if let hit = PhotoEditGeometry.layerHit(document.layers, at: point,
                                                                heightOverWidth: imageSize.height / max(imageSize.width, 1)) {
                            targetID = hit
                        }
                    }
                    guard let targetID, let layer = document.layers.first(where: { $0.id == targetID }) else {
                        gestureIgnored = true
                        return
                    }
                    selectedLayerID = targetID
                    layerStart = layer
                    history.record(document)
                }
                guard let start = layerStart, let index = document.layers.firstIndex(where: { $0.id == start.id }) else { return }
                var updated = start
                if let drag = value.first {
                    updated.center = CGPoint(x: start.center.x + drag.translation.width / max(full.width, 1),
                                             y: start.center.y + drag.translation.height / max(full.height, 1))
                    draggingLayer = true
                    let location = CGPoint(x: drag.location.x, y: drag.location.y + 64)
                    draggingLayerOverTrash = isOverTrash(location)
                }
                if let magnification = value.second?.first?.magnification {
                    updated.scale = min(max(start.scale * magnification, PhotoEditLayer.scaleRange.lowerBound), PhotoEditLayer.scaleRange.upperBound)
                }
                if let angle = value.second?.second?.rotation {
                    updated.rotation = start.rotation + angle.radians
                }
                document.layers[index] = updated
            }
            .onEnded { _ in
                if draggingLayerOverTrash, let id = layerStart?.id {
                    document.layers.removeAll { $0.id == id }
                    if selectedLayerID == id { selectedLayerID = nil }
                    Haptics.impact(.medium)
                }
                layerStart = nil
                gestureIgnored = false
                draggingLayer = false
                draggingLayerOverTrash = false
            }
    }

    /// Çöp kutusu alt çubuğun ortasında; editör koordinatında.
    @State private var trashFrame: CGRect = .zero

    private func isOverTrash(_ location: CGPoint) -> Bool {
        trashFrame.insetBy(dx: -24, dy: -24).contains(location)
    }

    // MARK: Kırpma

    private func cropOverlay(size: CGSize) -> some View {
        let rect = CGRect(x: draftCrop.minX * size.width, y: draftCrop.minY * size.height,
                          width: draftCrop.width * size.width, height: draftCrop.height * size.height)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .fill(Color.white.opacity(0.001))
                .overlay {
                    ZStack {
                        Rectangle().stroke(.white, lineWidth: 1.5)
                        // Üçte bir kılavuzları
                        Path { path in
                            for i in 1...2 {
                                let x = rect.width * CGFloat(i) / 3, y = rect.height * CGFloat(i) / 3
                                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: rect.height))
                                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: rect.width, y: y))
                            }
                        }
                        .stroke(.white.opacity(0.4), lineWidth: 0.5)
                    }
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .gesture(cropGesture(.move, size: size))
                .accessibilityLabel("Kırpma alanı")

            ForEach([PhotoEditGeometry.CropHandle.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { handle in
                let point: CGPoint = {
                    switch handle {
                    case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
                    case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
                    case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
                    default: return CGPoint(x: rect.maxX, y: rect.maxY)
                    }
                }()
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(radius: 2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .gesture(cropGesture(handle, size: size))
                    .position(point)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func cropGesture(_ handle: PhotoEditGeometry.CropHandle, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = cropStart ?? draftCrop
                if cropStart == nil { cropStart = draftCrop }
                draftCrop = PhotoEditGeometry.adjust(start, handle: handle,
                                                     translation: CGSize(width: value.translation.width / max(size.width, 1),
                                                                         height: value.translation.height / max(size.height, 1)))
            }
            .onEnded { _ in cropStart = nil }
    }

    // MARK: Çubuklar

    private var topBar: some View {
        HStack(spacing: 14) {
            switch mode {
            case .none:
                circleButton("xmark", label: "Kapat") { onClose() }
                Spacer()
                circleButton("crop", label: "Kırp") {
                    draftCrop = document.crop
                    mode = .crop
                }
                if !stickers.isEmpty {
                    circleButton("face.smiling", label: "Sticker ekle") { showStickerSheet = true }
                }
                circleButton("textformat", label: "Yazı ekle") {
                    textEntry = TextEntry(layerID: nil, text: "", colorIndex: colorIndex)
                }
                circleButton("pencil.tip", label: "Çiz") {
                    erasing = false
                    mode = .draw
                }
                if history.canUndo {
                    circleButton("arrow.uturn.backward", label: "Geri al") { undo() }
                }
            case .draw:
                circleButton("arrow.uturn.backward", label: "Geri al") { undo() }
                    .disabled(!history.canUndo)
                    .opacity(history.canUndo ? 1 : 0.4)
                circleButton(erasing ? "eraser.fill" : "eraser", label: erasing ? "Silgi açık" : "Silgi",
                             highlighted: erasing) {
                    erasing.toggle()
                    Haptics.selection()
                }
                Spacer()
                circleButton("checkmark", label: "Çizimi bitir", highlighted: true) {
                    mode = .none
                    erasing = false
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
        if mode == .draw {
            colorRow(selection: $colorIndex)
                .opacity(erasing ? 0.35 : 1)
                .disabled(erasing)
                .padding(.bottom, 28)
        } else if mode == .none {
            HStack {
                if draggingLayer {
                    Spacer()
                    Image(systemName: draggingLayerOverTrash ? "trash.fill" : "trash")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(draggingLayerOverTrash ? Color.ftDanger : Color.white.opacity(0.2), in: Circle())
                        .scaleEffect(draggingLayerOverTrash ? 1.15 : 1)
                        .animation(.spring(response: 0.25), value: draggingLayerOverTrash)
                        .background(GeometryReader { proxy in
                            Color.clear.onAppear { trashFrame = proxy.frame(in: .named(Self.coordinateSpace)) }
                        })
                        .accessibilityLabel("Silmek için buraya sürükle")
                    Spacer()
                } else {
                    Button {
                        Task {
                            saving = true
                            let message = await onSave(document.isEdited ? render() : nil)
                            saving = false
                            withAnimation { toast = message }
                        }
                    } label: {
                        Image(systemName: saving ? "hourglass" : "square.and.arrow.down")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    .disabled(saving)
                    .accessibilityLabel("Fotoğraflar'a kaydet")
                    Spacer()
                    Button {
                        Haptics.impact(.medium)
                        onSend(document.isEdited ? render() : nil)
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(Color.ftAccent, in: Circle())
                    }
                    .accessibilityLabel("Gönder")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
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
        colorIndex = entry.colorIndex
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
            .background(Color.ftBackground.ignoresSafeArea())
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
    }

    private func rescale(_ id: UUID, by factor: CGFloat) {
        guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
        history.record(document)
        let scale = document.layers[index].scale * factor
        document.layers[index].scale = min(max(scale, PhotoEditLayer.scaleRange.lowerBound), PhotoEditLayer.scaleRange.upperBound)
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
