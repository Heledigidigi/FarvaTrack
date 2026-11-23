import SwiftUI

/// "Kutu Kedi" baloncuğunun arkası: nakış kafa ve patiler sabit, kumaş dokulu krem gövde içerikle büyür.
/// Gelen mesajda kedi aynalanır (kafa sağda).
struct CatBoxBubbleView: View {
    let mirrored: Bool

    private static let inkColor = Color(hex: "#2A2320")
    private static let cream = Color(hex: "#F3E6D0")
    private static let hasTexture = UIImage(named: "KumasDoku") != nil

    var body: some View {
        Canvas { context, size in
            let layout = CatBoxGeometry.layout(for: size)
            var art = context
            art.concatenate(layout.transform)
            let fill: GraphicsContext.Shading = Self.hasTexture
                ? .tiledImage(Image("KumasDoku"), scale: 1)
                : .color(Self.cream)
            let ink: GraphicsContext.Shading = .color(Self.inkColor)
            let line = StrokeStyle(lineWidth: CatBoxGeometry.lineWidth, lineCap: .round, lineJoin: .round)
            let even = FillStyle(eoFill: true)
            let headClip = Path(CatBoxGeometry.headClip)

            // Dolgu: gövde, kafa/patiler (fotoğraftan), arka ayak.
            art.fill(Path(CatBoxGeometry.bodyFill(layout)), with: fill)
            art.drawLayer { layer in
                layer.clip(to: headClip)
                layer.fill(Path(CatBoxGeometry.silhouette), with: fill, style: even)
            }
            art.fill(Path(CatBoxGeometry.foot(layout, closed: true)), with: fill)

            // Çizgiler: kutu kenarları, sonra nakış kafa ve patiler en üstte.
            art.stroke(Path(CatBoxGeometry.back(layout)), with: ink, style: line)
            art.stroke(Path(CatBoxGeometry.belly(layout)), with: ink, style: line)
            art.stroke(Path(CatBoxGeometry.foot(layout, closed: false)), with: ink, style: line)
            art.stroke(Path(CatBoxGeometry.toes(layout)), with: ink,
                       style: StrokeStyle(lineWidth: CatBoxGeometry.lineWidth * 0.7, lineCap: .round))
            art.drawLayer { layer in
                layer.clip(to: headClip)
                layer.fill(Path(CatBoxGeometry.ink), with: ink, style: even)
            }
        }
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }
}

/// Kutu Kedi'nin durum işareti: arkasız, düz tik. Karın çizgisinin üstüne biner; hem krem gövdede hem
/// koyu sohbet zemininde görünsün diye orta tonlar kullanılır.
struct CatBoxStatusMark: View {
    let status: ChatMessageStatus

    static let size = CGSize(width: 16, height: 10)
    private static let neutral = Color(hex: "#9A8877")

    var body: some View {
        switch status {
        case .sending:
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Self.neutral)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.ftDanger)
        case .delivered:
            TickShape(double: false)
                .stroke(Self.neutral, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        case .read:
            TickShape(double: true)
                .stroke(Color.ftWater, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }

    /// Tek ya da çift tik (16×10 kutuda).
    struct TickShape: Shape {
        let double: Bool

        func path(in rect: CGRect) -> Path {
            let sx = rect.width / 16, sy = rect.height / 10
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
            var path = Path()
            if double {
                path.move(to: p(1, 5)); path.addLine(to: p(4.4, 8.4)); path.addLine(to: p(11.2, 1.6))
                path.move(to: p(7, 7.6)); path.addLine(to: p(7.8, 8.4)); path.addLine(to: p(14.6, 1.6))
            } else {
                path.move(to: p(3, 5)); path.addLine(to: p(6.4, 8.4)); path.addLine(to: p(13.4, 1.6))
            }
            return path
        }
    }
}
