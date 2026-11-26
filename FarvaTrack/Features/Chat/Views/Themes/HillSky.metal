// Tepedeki Kedi teması: gerçekçi, sıcak geçişli gökyüzü ve akan bulutlar (Aşama 10).
// MTKView tam ekran üçgenle çizer; düşük çözünürlükte ve 20 fps (bulutlar yumuşak, telefonu yormaz).

#include <metal_stdlib>
using namespace metal;

struct HillSkyUniforms {
    float4 top, mid, low, hor, sunColor, lit, shade;
    float2 resolution;
    float2 sun;        // görsel uzayında: x / 736 * 0.5, y / 1472
    float time, cover, glow, stars, cirrus, puff, stretch, pad;
};

struct HillSkyVertexOut {
    float4 position [[position]];
};

vertex HillSkyVertexOut hillSkyVertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2)) * 2.0 - 1.0;   // (-1,-1) (3,-1) (-1,3)
    HillSkyVertexOut out;
    out.position = float4(p, 0, 1);
    return out;
}

static float hsHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float hsNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hsHash(i), hsHash(i + float2(1, 0)), u.x),
               mix(hsHash(i + float2(0, 1)), hsHash(i + float2(1, 1)), u.x), u.y);
}

constant float2x2 hsM = float2x2(float2(1.6, 1.2), float2(-1.2, 1.6));

static float hsFbm(float2 p, int octaves) {
    float v = 0, a = 0.5;
    for (int i = 0; i < octaves; i++) { v += a * hsNoise(p); p = hsM * p; a *= 0.5; }
    return v;
}

static float hsBillow(float2 p) {
    float v = 0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * abs(hsNoise(p) * 2.0 - 1.0); p = hsM * p; a *= 0.5; }
    return v;
}

static float3 hsGrad(constant HillSkyUniforms &u, float y) {
    float3 c = mix(u.top.rgb, u.mid.rgb, smoothstep(0.0, 0.38, y));
    c = mix(c, u.low.rgb, smoothstep(0.3, 0.62, y));
    return mix(c, u.hor.rgb, smoothstep(0.55, 0.76, y));
}

// k = 0 uzak/yüksek katman, k = 1 yakın/alçak katman.
static float hsLayer(constant HillSkyUniforms &u, float2 q, float y, float k) {
    float lo = mix(0.05, 0.30, k), hi = mix(0.45, 0.84, k);
    float band = smoothstep(lo, lo + 0.18, y) * (1.0 - smoothstep(hi - 0.12, hi, y));
    if (band <= 0.0) { return 0.0; }                          // katmanın dışında hesap yapılmaz
    float persp = 1.0 / (0.9 - y);
    float sc = mix(3.2, 1.9, k);
    float2 cp = float2(q.x * sc * persp * 0.6 * u.stretch + u.time * mix(0.012, 0.026, k), persp * mix(2.8, 1.7, k));
    float2 w = float2(hsFbm(cp * 0.6 + float2(0, u.time * 0.005), 3), hsFbm(cp * 0.6 + float2(5.2, 1.3) - u.time * 0.004, 3));
    float d = hsFbm(cp + 1.7 * w + k * 7.3, 4);
    d += (0.5 - hsBillow(cp * 2.6 + w)) * 0.22 * u.puff;      // kabarık kenarlar
    return smoothstep(u.cover + (1.0 - k) * 0.04, u.cover + 0.26, d) * band;
}

static float3 hsShade(constant HillSkyUniforms &u, float2 q, float y, float k, float d, float ds, float2 toSun) {
    // Güneşe doğru iki örnek: bulutun içinden geçen ışık azalır (hacim hissi).
    float acc = 0;
    for (int i = 1; i <= 2; i++) { float2 o = toSun * 0.022 * float(i); acc += hsLayer(u, q + o, y + o.y, k); }
    float sunL = exp(-acc * 1.1);
    float3 amb = mix(u.shade.rgb, hsGrad(u, y), 0.42) * (0.95 + 0.3 * (1.0 - d));
    float det = hsFbm(float2(q.x * 12.0, y * 9.0) + float2(u.time * 0.015, 0), 2);
    float3 c = amb * (0.86 + 0.28 * det) + u.lit.rgb * sunL * 1.15;
    c += u.hor.rgb * (1.0 - d) * 0.32;                          // ince kenarlara ufuktan sıcak ışık
    c += u.sunColor.rgb * exp(-ds * 5.0) * (1.0 - d) * 1.5 * u.glow;  // güneşe yakın gümüş kenar
    c += u.lit.rgb * pow(sunL, 6.0) * 0.25;
    return c;
}

fragment float4 hillSkyFragment(HillSkyVertexOut in [[stage_in]], constant HillSkyUniforms &u [[buffer(0)]]) {
    float2 uv = in.position.xy / u.resolution;   // Metal: y aşağı doğru
    float y = uv.y;
    float2 q = float2(uv.x * 0.5, y);
    float2 sd = q - u.sun;
    float ds = length(sd * float2(1.0, 1.15));

    float3 rad = mix(u.hor.rgb, u.low.rgb, smoothstep(0.0, 0.28, ds));
    rad = mix(rad, u.mid.rgb, smoothstep(0.22, 0.55, ds));
    rad = mix(rad, u.top.rgb, smoothstep(0.5, 0.95, ds));
    float3 col = mix(rad, hsGrad(u, y), 0.22);
    col += u.sunColor.rgb * (exp(-ds * 9.0) * 0.32 + exp(-ds * 3.4) * 0.1) * u.glow;

    if (u.stars > 0) {
        float2 g = floor(in.position.xy / 1.5);
        float s = step(0.9965, hsHash(g));
        col += s * u.stars * smoothstep(0.38, 0.7, ds) * (1.0 - smoothstep(0.55, 0.7, y)) * (0.6 + 0.4 * sin(u.time * 2.0 + hsHash(g + 3.0) * 30.0));
    }

    // Işık huzmeleri yalnızca güneşin çevresinde hesaplanır.
    float ray = 0;
    if (ds < 0.75) {
        float ang = atan2(sd.y, sd.x);
        ray = hsFbm(float2(ang * 7.0, u.time * 0.04), 3) * hsFbm(float2(ang * 13.0 + 3.0, u.time * 0.03 + 2.0), 3);
    }

    float ci = hsFbm(float2(q.x * 3.0 + u.time * 0.004, y * 26.0) + hsFbm(q * 6.0, 3) * 1.4, 4);
    float cirr = smoothstep(0.55, 0.85, ci) * (1.0 - smoothstep(0.25, 0.6, y)) * u.cirrus;
    col = mix(col, mix(u.lit.rgb, float3(1.0), 0.25), cirr * 0.5);

    float2 toSun = normalize(u.sun - q);
    float fade = smoothstep(0.02, 0.1, ds);
    for (int k = 0; k < 2; k++) {
        float kk = float(k);
        float d = hsLayer(u, q, y, kk) * fade;
        if (d > 0.002) {
            float3 cc = hsShade(u, q, y, kk, d, ds, toSun);
            col = mix(col, cc, clamp(d * 1.08, 0.0, 0.97));
        }
    }
    col += u.sunColor.rgb * ray * exp(-ds * 2.6) * 0.24 * u.glow;
    col = mix(col, float3(1.0), smoothstep(0.024, 0.014, ds) * min(u.glow, 1.0));
    col += u.sunColor.rgb * exp(-ds * 26.0) * 0.9 * u.glow;
    col += (hsHash(in.position.xy + u.time) - 0.5) / 255.0;
    return float4(saturate(col), 1.0);
}
