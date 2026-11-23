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
