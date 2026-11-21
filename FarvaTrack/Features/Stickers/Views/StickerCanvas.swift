import SwiftUI
import UIKit

/// Düzenleme tuvali: tek parmak = fırça (ya da "Gezin" aracında kaydırma), iki parmak = yakınlaştır / kaydır.
/// Görüntünün ekrandaki çerçevesini SwiftUI katmanlarına (imleç, büyüteç, yazılar) bildirir.
struct StickerCanvas: UIViewRepresentable {
    let image: CGImage?
    let pixelSize: CGSize
    let brushEnabled: Bool
    /// Ekran noktası (parmak) → fırça olayları.
    var onBrushBegan: (CGPoint) -> Void
    var onBrushMoved: (CGPoint) -> Void
    var onBrushEnded: () -> Void
    var onBrushCancelled: () -> Void
    var onImageFrameChanged: (CGRect) -> Void

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        context.coordinator.parent = self
        view.brushEnabled = brushEnabled
        view.setImage(image, pixelSize: pixelSize)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator {
        var parent: StickerCanvas
        init(parent: StickerCanvas) { self.parent = parent }
    }

    final class CanvasView: UIView, UIGestureRecognizerDelegate {
        weak var coordinator: Coordinator?
        var brushEnabled = true

        private let imageView = UIImageView()
        private var pixelSize: CGSize = .zero
        private var zoom: CGFloat = 1
        private var pan: CGPoint = .zero
        private var lastReportedFrame: CGRect = .null
        private var brushActive = false
        private var pinchStartZoom: CGFloat = 1
        private var pinchStartPan: CGPoint = .zero
        private var pinchAnchor: CGPoint = .zero

        static let zoomRange: ClosedRange<CGFloat> = 1...8

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            isMultipleTouchEnabled = true
            imageView.contentMode = .scaleToFill
            imageView.layer.magnificationFilter = .nearest
            addSubview(imageView)

            let brush = UIPanGestureRecognizer(target: self, action: #selector(handleBrush(_:)))
            brush.maximumNumberOfTouches = 1
            brush.delegate = self
            addGestureRecognizer(brush)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            addGestureRecognizer(pinch)

            let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
            twoFingerPan.minimumNumberOfTouches = 2
            twoFingerPan.delegate = self
            addGestureRecognizer(twoFingerPan)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.numberOfTouchesRequired = 2
            addGestureRecognizer(doubleTap)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

        func setImage(_ image: CGImage?, pixelSize: CGSize) {
            if let image { imageView.image = UIImage(cgImage: image) } else { imageView.image = nil }
            if self.pixelSize != pixelSize {
                self.pixelSize = pixelSize
                zoom = 1
                pan = .zero
                setNeedsLayout()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyTransform()
        }

        /// Sığdırılmış çerçeve × yakınlaştırma + kaydırma.
        private var imageFrame: CGRect {
            let fitted = StickerGeometry.aspectFit(pixelSize, in: bounds.insetBy(dx: 12, dy: 12))
            let width = fitted.width * zoom
            let height = fitted.height * zoom
            return CGRect(x: bounds.midX - width / 2 + pan.x, y: bounds.midY - height / 2 + pan.y, width: width, height: height)
        }

        private func applyTransform() {
            clampPan()
            let frame = imageFrame
            imageView.frame = frame
            if frame != lastReportedFrame {
                lastReportedFrame = frame
                let report = frame
                DispatchQueue.main.async { [weak self] in self?.coordinator?.parent.onImageFrameChanged(report) }
            }
        }

        /// Görüntü ekrandan tamamen kaçmasın.
        private func clampPan() {
            let fitted = StickerGeometry.aspectFit(pixelSize, in: bounds.insetBy(dx: 12, dy: 12))
            let maxX = max(0, (fitted.width * zoom - fitted.width) / 2 + fitted.width / 3)
            let maxY = max(0, (fitted.height * zoom - fitted.height) / 2 + fitted.height / 3)
            pan.x = min(max(pan.x, -maxX), maxX)
            pan.y = min(max(pan.y, -maxY), maxY)
        }

        // MARK: Hareketler

        @objc private func handleBrush(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: self)
            guard brushEnabled else {
                // "Gezin": tek parmakla kaydır.
                if gesture.state == .changed {
                    let translation = gesture.translation(in: self)
                    pan.x += translation.x
                    pan.y += translation.y
                    gesture.setTranslation(.zero, in: self)
                    applyTransform()
                }
                return
            }
            switch gesture.state {
            case .began:
                brushActive = true
                coordinator?.parent.onBrushBegan(point)
            case .changed:
                if brushActive { coordinator?.parent.onBrushMoved(point) }
            case .ended:
                if brushActive { coordinator?.parent.onBrushEnded() }
                brushActive = false
            case .cancelled, .failed:
                if brushActive { coordinator?.parent.onBrushCancelled() }
                brushActive = false
            default:
                break
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            cancelBrushIfNeeded()
            switch gesture.state {
            case .began:
                pinchStartZoom = zoom
                pinchStartPan = pan
                pinchAnchor = gesture.location(in: self)
            case .changed:
                let newZoom = min(max(pinchStartZoom * gesture.scale, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
                // Parmakların ortası sabit kalsın.
                let factor = newZoom / pinchStartZoom
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                pan.x = (pinchStartPan.x - (pinchAnchor.x - center.x)) * factor + (pinchAnchor.x - center.x)
                pan.y = (pinchStartPan.y - (pinchAnchor.y - center.y)) * factor + (pinchAnchor.y - center.y)
                zoom = newZoom
                applyTransform()
            default:
                break
            }
        }

        @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            cancelBrushIfNeeded()
            guard gesture.state == .changed else { return }
            let translation = gesture.translation(in: self)
            pan.x += translation.x
            pan.y += translation.y
            pinchStartPan.x += translation.x
            pinchStartPan.y += translation.y
            gesture.setTranslation(.zero, in: self)
            applyTransform()
        }

        @objc private func handleDoubleTap() {
            UIView.animate(withDuration: 0.25) {
                self.zoom = 1
                self.pan = .zero
                self.applyTransform()
            }
        }

        private func cancelBrushIfNeeded() {
            guard brushActive else { return }
            brushActive = false
            coordinator?.parent.onBrushCancelled()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // Hepsi birlikte tanınabilir: fırça sürerken ikinci parmak gelirse yakınlaştırma başlar
            // ve yarım fırça darbesi iptal edilir (`cancelBrushIfNeeded`).
            true
        }
    }
}

// MARK: - Dama deseni (saydamlık)

struct CheckerboardBackground: View {
    var square: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / square))
            let rows = Int(ceil(size.height / square))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.22)))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)
                    context.fill(Path(rect), with: .color(Color(white: 0.32)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Büyüteç

/// Fırçanın altındaki bölgeyi büyütür; parmak köşeye yaklaşınca karşı köşeye geçer.
struct StickerMagnifier: View {
    let image: CGImage
    /// Görüntü pikseli cinsinden merkez ve fırça yarıçapı.
    let center: CGPoint
    let radius: Double
    static let side: CGFloat = 116

    private var cropRect: CGRect {
        let span = max(48, radius * 4)
        return CGRect(x: center.x - span / 2, y: center.y - span / 2, width: span, height: span)
    }

    var body: some View {
        ZStack {
            CheckerboardBackground(square: 8)
            GeometryReader { _ in
                let rect = cropRect
                let scale = Self.side / rect.width
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                    .offset(x: -rect.minX * scale, y: -rect.minY * scale)
            }
            Circle()
                .strokeBorder(.white, lineWidth: 1.5)
                .frame(width: Self.side * (radius * 2) / cropRect.width, height: Self.side * (radius * 2) / cropRect.width)
                .shadow(color: .black.opacity(0.6), radius: 1)
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 2))
        .shadow(radius: 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
