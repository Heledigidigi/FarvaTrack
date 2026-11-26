// Uyku ekranının 3B ayı: gerçek ay haritası (AyDokusu) küreye sarılır.
// Lommel–Seeliger ışıklandırma (dolunayda düz parlaklık, terminatörde kabartma).
// Uyku hedefe yaklaştıkça ayın önünden sağ üstten geçen büyük yuvarlak çekilir; kapanan yer tamamen saydamdır.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float3 ayRY(float3 v, float a) { float c = cos(a), s = sin(a); return float3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z); }
static float3 ayRX(float3 v, float a) { float c = cos(a), s = sin(a); return float3(v.x, c * v.y - s * v.z, s * v.y + c * v.z); }
static float2 ayUV(float3 p) { return float2(atan2(p.x, p.z) / (2.0 * M_PI_F) + 0.5, 0.5 - asin(clamp(p.y, -1.0, 1.0)) / M_PI_F); }
static float ayParlaklik(texture2d<half> doku, float2 uv) {
    constexpr sampler s(filter::linear, mip_filter::linear, address::repeat);
    return dot(float3(doku.sample(s, uv).rgb), float3(0.299, 0.587, 0.114));
}

[[ stitchable ]] half4 ayYuzeyi(float2 konum, half4 renk0, float2 boyut, float rot, float tilt, float kap, texture2d<half> doku) {
    float2 q = (konum - boyut * 0.5) / (boyut.x * 0.5 * 0.94);
    q.y = -q.y;                                   // yukarı pozitif
    float r2 = dot(q, q);
    if (r2 > 1.0) { return half4(0.0); }
    float3 n = float3(q, sqrt(1.0 - r2));
    float3 p = ayRX(ayRY(n, rot), tilt);
    float alb = ayParlaklik(doku, ayUV(p));

    // Dokudan kabartma: parlaklık eğiminden normal
    float3 t1 = normalize(cross(n, float3(0.0, 1.0, 0.0001)));
    float3 t2 = cross(n, t1);
    float e = 0.006;
    float ax = ayParlaklik(doku, ayUV(ayRX(ayRY(normalize(n + t1 * e), rot), tilt)));
    float ay = ayParlaklik(doku, ayUV(ayRX(ayRY(normalize(n + t2 * e), rot), tilt)));
    float3 nb = normalize(n - (t1 * (ax - alb) + t2 * (ay - alb)) * 3.2);

    float3 L = normalize(float3(-0.22, 0.18, 0.96));
    float mu0 = max(dot(nb, L), 0.0), mu = max(n.z, 0.05);
    float ls = mu0 / (mu0 + mu) * 2.0;
    float ter = smoothstep(-0.04, 0.18, dot(n, L));
    float isik = mix(mu0, ls, 0.75) * ter;
    float3 renk = float3(1.0, 0.965, 0.9) * clamp(pow(alb, 1.75) * 1.85, 0.0, 1.2) * isik * 1.12;
    renk += float3(0.5, 0.53, 0.62) * alb * 0.07 * (1.0 - ter);   // dünya ışığı

    // Sağ üstten geçen büyük yuvarlak: kapanan yer saydam, kenarında hafif yarı gölge
    float2 oc = normalize(float2(1.0, 1.0)) * kap;
    float od = length(q - oc);
    const float RO = 1.18;
    float acik = smoothstep(RO, RO + 0.012, od);
    renk *= mix(0.72, 1.0, smoothstep(RO, RO + 0.07, od));
    float a = smoothstep(1.0, 0.985, sqrt(r2)) * acik;
    return half4(half3(renk * a), half(a));
}
