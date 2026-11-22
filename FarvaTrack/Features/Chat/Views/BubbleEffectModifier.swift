import SwiftUI

extension View {
    /// Baloncuk efekti (Metal). `enabled` yanlışsa (ör. "Hareketi azalt" açık) hiçbir şey eklenmez.
    func bubbleEffect(_ effect: BubbleEffect, enabled: Bool) -> some View {
        modifier(BubbleEffectModifier(effect: effect, enabled: enabled))
    }
}

struct BubbleEffectModifier: ViewModifier {
    let effect: BubbleEffect
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            GeometryReader { proxy in
                TimelineView(.animation) { timeline in
                    let time = Float(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
                    content.modifier(ShaderEffect(kind: effect.kind, size: proxy.size, time: time,
                                                  tint: Color(hex: effect.colorHex), intensity: Float(effect.intensity)))
                }
            }
        } else {
            content
        }
    }
}

/// Seçilen efektin gölgelendiricisini uygular.
private struct ShaderEffect: ViewModifier {
    let kind: BubbleEffect.Kind
    let size: CGSize
    let time: Float
    let tint: Color
    let intensity: Float

    func body(content: Content) -> some View {
        switch kind {
        case .none:
            content
        case .shimmer:
            content.colorEffect(ShaderLibrary.bubbleShimmer(.float2(size), .float(time), .color(tint), .float(intensity)))
        case .particles:
            content.colorEffect(ShaderLibrary.bubbleSparkle(.float(time), .color(tint), .float(intensity)))
        case .glow:
            content.layerEffect(ShaderLibrary.bubbleGlow(.float(time), .color(tint), .float(intensity)),
                                maxSampleOffset: CGSize(width: 8, height: 8))
        }
    }
}
