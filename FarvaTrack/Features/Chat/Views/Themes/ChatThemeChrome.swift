import SwiftUI

// MARK: - Temalı varsayılan baloncuk

/// Tema seçiliyken (ve kişi özel baloncuk seçmemişken) mesajın zemini.
/// Tepedeki Kedi'de renk, baloncuğun ekrandaki yerinin güneşe uzaklığına göre değişir; kaydırdıkça yumuşakça güncellenir.
struct ChatThemeBubbleBackground: View {
    let look: ChatThemeLook
    let isMine: Bool
    var sun: ChatThemeSunInfo?

    private var shape: UnevenRoundedRectangle {
        let r = look.cornerRadius, tail = look.tailRadius
        return UnevenRoundedRectangle(topLeadingRadius: r,
                                      bottomLeadingRadius: isMine ? r : tail,
                                      bottomTrailingRadius: isMine ? tail : r,
                                      topTrailingRadius: r,
                                      style: .continuous)
    }

    var body: some View {
        Group {
            if let palette = look.sunPalette, let sun {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    let t = ChatThemeSun.distanceFactor(center: CGPoint(x: frame.midX, y: frame.midY), sun: sun.sun, screen: sun.screen)
                    if isMine {
                        shape.fill(LinearGradient(colors: palette.outgoing(t).map(\.color), startPoint: .topTrailing, endPoint: .bottomLeading))
                    } else {
                        shape.fill(palette.incoming(t).color)
                    }
                }
            } else {
                shape.fill((isMine ? look.outgoing : look.incoming).style)
            }
        }
        .background {
            if !isMine, look.incomingBlur { shape.fill(.ultraThinMaterial) }
        }
        .overlay(alignment: .bottom) {
            // Piksel teması: baloncuğun altında "basılabilir" blok gölgesi.
            if look.blockShade > 0 {
                Rectangle().fill(Color.black.opacity(look.blockShade)).frame(height: 3)
            }
        }
        .clipShape(shape)
    }
}

// MARK: - Çubuklar

extension ChatThemeLook {
    /// Yazma alanı ve altındaki boşluk: yarı saydam tema rengi. Buzlu cam kullanılmaz: animasyonlu duvar kâğıdının
    /// üstünde her karede yeniden bulanıklaştırılır ve telefonu yorar.
    var chromeBackground: some View { chrome.color }

    /// Sohbeti duvar kâğıdından ayıran ince çizgi.
    var separatorLine: some View {
        Rectangle().fill(separator.style).frame(height: separator.width)
    }
}

/// Yazma alanının zemini: tema varsa temanın çubuğu, yoksa uygulamanın.
struct ChatChromeBackground: View {
    @Environment(\.chatThemeLook) private var look

    var body: some View {
        if let look { look.chromeBackground } else { Color.ftChrome }
    }
}

// MARK: - Yazma alanı düğmeleri (önizlemede tasarlanan simgeler; her temada ve varsayılanda)

/// Gönder simgesi: sağa bakan kâğıt uçak (24 × 24 birimlik çizimden).
struct ChatSendGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var path = Path()
        path.move(to: p(3.4, 20.4))
        path.addLine(to: p(20.8, 12.9))
        path.addQuadCurve(to: p(20.8, 11.1), control: p(21.7, 12))
        path.addLine(to: p(3.4, 3.6))
        path.addQuadCurve(to: p(2.1, 4.6), control: p(2.0, 3.6))
        path.addLine(to: p(3.9, 11.0))
        path.addLine(to: p(12.0, 12.0))
        path.addLine(to: p(3.9, 13.0))
        path.addLine(to: p(2.1, 19.4))
        path.addQuadCurve(to: p(3.4, 20.4), control: p(2.0, 20.4))
        path.closeSubpath()
        return path
    }
}

/// Yazma alanının sağındaki dolu yuvarlak düğme (mikrofon / gönder). Tema varsa temanın rengi ve köşesi.
struct ChatActionCircle<Glyph: View>: View {
    var size: CGFloat = 34
    var enabled = true
    @ViewBuilder var glyph: () -> Glyph
    @Environment(\.chatThemeLook) private var look

    var body: some View {
        let corner: CGFloat = (look?.cornerRadius ?? 18) < 6 ? 3 : size / 2
        glyph()
            .foregroundStyle(look?.sendText.color ?? .white)
            .frame(width: size, height: size)
            .background(look?.send.style ?? AnyShapeStyle(Color.ftAccent),
                        in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
    }
}

// MARK: - Temanın açık/koyu hâli

/// Tema koyuysa (ör. Gül alacakaranlık) sistem denetimleri (bölümlü seçici, imleç, yer tutucu) koyu çizilir.
private struct ChatTintScheme: ViewModifier {
    @Environment(\.chatTint) private var tint
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, tint.colorScheme ?? scheme)
    }
}

extension View {
    func chatTintScheme() -> some View { modifier(ChatTintScheme()) }
}
