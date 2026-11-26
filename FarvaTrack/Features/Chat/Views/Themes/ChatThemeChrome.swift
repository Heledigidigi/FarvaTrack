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
        .shadow(color: isMine && look.sunPalette != nil ? Color.black.opacity(0.12) : .clear, radius: 6, y: 2)
    }
}

// MARK: - Çubuklar

extension ChatThemeLook {
    /// Yazma alanı ve altındaki boşluk: buzlu cam + tema rengi.
    @ViewBuilder
    var chromeBackground: some View {
        ZStack {
            if chrome.a < 0.95 { Rectangle().fill(.ultraThinMaterial) }
            chrome.color
        }
        .environment(\.colorScheme, colorScheme)
    }

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
