// Sohbet baloncuğu efektleri (Aşama 8F). SwiftUI `colorEffect` / `layerEffect` ile kullanılır.
// Hepsi yalnızca baloncuğun dolu (alfa > 0) piksellerini etkiler; saydam alan saydam kalır.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Tekrarlanabilir sözde rastgele sayı (hücre başına).
static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Parıltı: baloncuğun üzerinden çapraz geçen yumuşak ışık bandı.
[[ stitchable ]] half4 bubbleShimmer(float2 position, half4 color, float2 size, float time, half4 tint, float intensity) {
    if (color.a <= 0.001h) { return color; }
    float diagonal = (position.x + position.y * 0.6) / max(size.x + size.y * 0.6, 1.0);
    float sweep = fract(time * 0.28) * 1.8 - 0.4;              // -0.4 … 1.4: kenarlardan taşarak geçer
    float band = smoothstep(0.16, 0.0, abs(diagonal - sweep));
    half amount = half(band * intensity * 0.85);
    half3 lit = mix(color.rgb, tint.rgb * color.a, amount);
    return half4(lit + tint.rgb * amount * 0.25h * color.a, color.a);
}

// Parçacık: ızgaraya dağılmış, farklı fazlarda yanıp sönen küçük yıldızlar.
[[ stitchable ]] half4 bubbleSparkle(float2 position, half4 color, float time, half4 tint, float intensity) {
    if (color.a <= 0.001h) { return color; }
    const float cell = 16.0;
    float2 id = floor(position / cell);
    float2 local = fract(position / cell);
    float seed = hash21(id);
    float2 star = float2(hash21(id + 7.1), hash21(id + 3.7)) * 0.7 + 0.15;
    float twinkle = pow(max(0.0, sin(time * (1.5 + seed * 2.5) + seed * 6.2831)), 8.0);
    float distanceToStar = length((local - star) * cell);
    float core = smoothstep(1.8, 0.0, distanceToStar);
    // Artı biçimli ince ışınlar.
    float2 delta = abs((local - star) * cell);
    float rays = smoothstep(0.7, 0.0, min(delta.x, delta.y)) * smoothstep(4.0, 0.0, max(delta.x, delta.y));
    float sparkle = (core + rays * 0.6) * twinkle * step(0.45, seed) * intensity;
    half amount = half(min(sparkle, 1.0));
    return half4(mix(color.rgb, tint.rgb * color.a, amount), color.a);
}

// Işıma: kenarlarda nabız gibi atan iç ışık. Çevredeki pikseller örneklenerek kenara yakınlık bulunur.
[[ stitchable ]] half4 bubbleGlow(float2 position, SwiftUI::Layer layer, float time, half4 tint, float intensity) {
    half4 color = layer.sample(position);
    if (color.a <= 0.001h) { return color; }
    const float radius = 7.0;
    float minimumAlpha = 1.0;
    for (int i = 0; i < 12; i++) {
        float angle = float(i) * 0.5235988;                     // 30°
        float2 offset = float2(cos(angle), sin(angle));
        minimumAlpha = min(minimumAlpha, float(layer.sample(position + offset * radius).a));
        minimumAlpha = min(minimumAlpha, float(layer.sample(position + offset * radius * 0.5).a));
    }
    float rim = (1.0 - minimumAlpha) * float(color.a);
    float pulse = 0.55 + 0.45 * sin(time * 2.4);
    half amount = half(clamp(rim * pulse * intensity * 1.2, 0.0, 1.0));
    return half4(mix(color.rgb, tint.rgb * color.a, amount), color.a);
}
