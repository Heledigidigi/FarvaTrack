import SwiftUI
import CoreMotion
import Observation

// Su ekranının canlı parçaları: telefonun eğimine göre su yüzeyi yere paralel kalan Damla
// ve "Son 7 Gün" tüplerindeki su. Damla'nın çizimi widget'takiyle aynıdır (`DropTheme`, `DropFace`).

// MARK: - Eğim

/// Telefonun sağa-sola eğimini yaylı bir açıya çevirir; hareket edince su çalkalanır.
@MainActor
@Observable
final class SuEgimi {
    private(set) var aci: Double = 0
    private(set) var calkanti: Double = 0

    @ObservationIgnored private let hareket = CMMotionManager()
    @ObservationIgnored private var hedef: Double = 0
    @ObservationIgnored private var hiz: Double = 0

    func baslat() {
        guard hareket.isDeviceMotionAvailable, !hareket.isDeviceMotionActive else { return }
        hareket.deviceMotionUpdateInterval = 1.0 / 30
        hareket.startDeviceMotionUpdates(to: .main) { [weak self] veri, _ in
            guard let self, let g = veri?.gravity else { return }
            // Telefon saat yönünde θ kadar dönünce su yüzeyi ekranda −θ döner (yere paralel kalır).
            let teta = atan2(g.x, -g.y) * 180 / .pi
            MainActor.assumeIsolated { self.adim(hedef: max(-40, min(40, -teta))) }
        }
    }

    func durdur() {
        hareket.stopDeviceMotionUpdates()
        hedef = 0
    }

    private func adim(hedef yeni: Double) {
        hedef = yeni
        hiz += (hedef - aci) * 0.12
        hiz *= 0.8
        aci += hiz
        calkanti = min(2.6, abs(hiz) * 0.9)
    }
}

// MARK: - Su yüzeyi

/// 170'lik tasarım tuvalinde geniş bir dalga; döndürülünce kenarlarda boşluk kalmasın diye taşkın çizilir.
struct SuYuzeyi: Shape {
    var seviye: CGFloat
    var faz: CGFloat
    var genlik: CGFloat = 1.6

    var animatableData: CGFloat {
        get { seviye }
        set { seviye = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 170
        var p = Path()
        var x: CGFloat = -80
        p.move(to: CGPoint(x: x * s, y: (seviye + genlik * sin(x * 0.09 + faz)) * s))
        while x < 250 {
            x += 4
            p.addLine(to: CGPoint(x: x * s, y: (seviye + genlik * sin(x * 0.09 + faz)) * s))
        }
        p.addLine(to: CGPoint(x: 250 * s, y: 260 * s))
        p.addLine(to: CGPoint(x: -80 * s, y: 260 * s))
        p.closeSubpath()
        return p
    }
}

// MARK: - Canlı Damla

struct CanliDamla: View {
    let toplam: Int
    let hedef: Int
    let tema: DropTheme
    var egim: Double = 0
    var calkanti: Double = 0
    var zipla = 0

    @Environment(\.accessibilityReduceMotion) private var hareketiAzalt

    private var mood: DropMood { DropMood(total: toplam, goal: hedef) }
    private var oran: CGFloat { hedef > 0 ? min(CGFloat(toplam) / CGFloat(hedef), 1) : 0 }
    private var sekil: String { tema.isCat ? DropPaths.cat : DropPaths.drop }
    private var seviye: CGFloat {
        let alt: CGFloat = tema.isCat ? 150 : 145, ust: CGFloat = tema.isCat ? 34 : 30
        return alt - oran * (alt - ust)
    }
    private var olu: Bool { mood == .dead }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: hareketiAzalt)) { zaman in
            let t = hareketiAzalt ? 0 : zaman.date.timeIntervalSinceReferenceDate
            ArtCanvas {
                if tema.isCat {
                    StrokePath(d: "M122 146 C 142 148 151 134 147 120 C 145 112 151 105 157 108", style: olu ? Color(hex: 0xD5DCE2) : tema.stroke, width: 9)
                }
                FillPath(d: sekil, style: olu ? Color(hex: 0xEEF1F4) : tema.base)

                ZStack {
                    SuYuzeyi(seviye: seviye - 2.5, faz: CGFloat(t * 1.9 + 1.7), genlik: 1.6 * (1 + calkanti * 1.3))
                        .fill(LinearGradient(colors: [tema.back1, tema.back2], startPoint: .top, endPoint: .bottom))
                    SuYuzeyi(seviye: seviye, faz: CGFloat(t * 2.4), genlik: 1.6 * (1 + calkanti))
                        .fill(LinearGradient(colors: [tema.water1, tema.water2], startPoint: .top, endPoint: .bottom))
                }
                .frame(width: 170, height: 170)
                .offset(x: egim * 0.05)
                .rotationEffect(.degrees(egim), anchor: UnitPoint(x: 0.5, y: seviye / 170))
                .opacity(toplam > 0 ? 1 : 0)
                .mask(SVGShape(d: sekil).frame(width: 170, height: 170))
                .animation(.spring(response: 0.7, dampingFraction: 0.55), value: toplam)

                StrokePath(d: sekil, style: olu ? Color(hex: 0xD5DCE2) : tema.stroke, width: 1.5)

                if tema.isCat {
                    StrokePath(d: "M76 150 L76 141 M94 150 L94 141", style: tema.stroke, width: 1.8)
                    Oval(cx: 64, cy: 112, rx: 4.5, ry: 9, style: Color.white.opacity(0.8), rotation: 25)
                } else {
                    Oval(cx: 66, cy: 76, rx: 4.5, ry: 9, style: Color.white.opacity(0.8), rotation: 25)
                    Oval(cx: 71, cy: 92, rx: 1.8, ry: 1.8, style: Color.white.opacity(0.7))
                }

                DropFace(mood: mood, theme: tema)
                    .offset(x: -egim * 0.05, y: tema.isCat ? -42 : 0)
                    .id(mood)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))

                DropDecorations(mood: mood, isCat: tema.isCat)
                    .id("deco-\(mood.label)")
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: zipla) { icerik, olcek in
            icerik.scaleEffect(x: 2 - olcek, y: olcek, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(0.9, duration: 0.12)
                SpringKeyframe(1.05, duration: 0.18)
                SpringKeyframe(1.0, duration: 0.3)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: mood)
    }
}

// MARK: - Son 7 Gün: tüpteki su

/// Her gün bir cam tüp; yalnız suyun olduğu kısım görünür. Su yüzeyi eğimle hafifçe yatar ve dalgalanır.
struct SuTupleri: View {
    let gunler: [DailyValue]
    let hedef: Int
    var egim: Double = 0
    var calkanti: Double = 0
    var nostalji = false

    @Environment(\.accessibilityReduceMotion) private var hareketiAzalt

    private var renk1: Color { nostalji ? Color(hex: "#6E8E92") : Color(hex: "#6C97BC") }
    private var renk2: Color { nostalji ? Color(hex: "#4F6F72") : Color(hex: "#3F6E99") }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: hareketiAzalt)) { zaman in
            let t = hareketiAzalt ? 0 : zaman.date.timeIntervalSinceReferenceDate
            Canvas { ctx, boyut in ciz(&ctx, boyut: boyut, t: t) }
        }
        .frame(height: 112)
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                ForEach(Array(gunler.enumerated()), id: \.offset) { i, g in
                    EksenEtiketi(metin: i == gunler.count - 1 ? "Bugün" : KlasikTarih.gunKisa(g.date), bugun: i == gunler.count - 1)
                        .position(x: geo.size.width * (44 + CGFloat(i) * 42) / 350, y: geo.size.height - 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(erisim)
    }

    private var erisim: String {
        let tutan = gunler.filter { $0.value >= Double(hedef) }.count
        return "Son 7 gün su: \(gunler.map { "\(Int($0.value)) ml" }.joined(separator: ", ")). \(tutan) günde hedefe ulaşıldı."
    }

    private func ciz(_ ctx: inout GraphicsContext, boyut: CGSize, t: Double) {
        let kx = boyut.width / 350
        let taban: CGFloat = 92, ust: CGFloat = 4, bw: CGFloat = 18, H = taban - ust
        let enCok = max(Double(hedef) * 1.18, gunler.map(\.value).max() ?? 0, 1)
        func seviye(_ v: Double) -> CGFloat { taban - max(3, CGFloat(v / enCok) * H) }

        // Hedef çizgisi
        let hy = taban - CGFloat(Double(hedef) / enCok) * H
        var cizgi = Path()
        cizgi.move(to: CGPoint(x: 24 * kx, y: hy))
        cizgi.addLine(to: CGPoint(x: 306 * kx, y: hy))
        ctx.stroke(cizgi, with: .color(KlasikRenk.hedefCizgisi), style: StrokeStyle(lineWidth: 0.6, lineCap: .round, dash: [1, 4]))
        ctx.draw(Text(hedef.formatted()).font(.system(size: 8.5)).foregroundStyle(Color(hex: "#6E523C")),
                 at: CGPoint(x: boyut.width, y: hy), anchor: .trailing)

        let k = max(-14, min(14, egim * 0.4))
        var golgeli = ctx
        golgeli.addFilter(.shadow(color: OzetRenk.golge.opacity(0.36), radius: 3, x: 2, y: 5))
        for (i, g) in gunler.enumerated() {
            let cx = (44 + CGFloat(i) * 42) * kx
            let x = cx - bw / 2
            let y = seviye(g.value)
            let bugun = i == gunler.count - 1
            let tup = Path(roundedRect: CGRect(x: x, y: ust, width: bw, height: H), cornerRadius: bw / 2)
            let dolu = Path(CGRect(x: x - 2, y: y + 1.6, width: bw + 4, height: taban - y + 4))
            let sure = 2.6 + Double(i % 3) * 0.5

            golgeli.drawLayer { k2 in
                k2.clip(to: tup)
                k2.drawLayer { cam in
                    cam.clip(to: dolu)
                    cam.fill(tup, with: .color(Color(hex: "#FFFAF0").opacity(0.22)))
                }
                let suYolu: (Double, Double, Double) -> Path = { A, per, faz in
                    var p = Path()
                    var xx = x - 30
                    p.move(to: CGPoint(x: xx, y: y + CGFloat(A * sin(Double(xx - x) / per * 6.283 + faz))))
                    while xx < x + bw + 30 {
                        xx += 2
                        p.addLine(to: CGPoint(x: xx, y: y + CGFloat(A * sin(Double(xx - x) / per * 6.283 + faz))))
                    }
                    return p
                }
                let kapat: (Path) -> Path = { ac in
                    var p = ac
                    p.addLine(to: CGPoint(x: x + bw + 30, y: taban + 40))
                    p.addLine(to: CGPoint(x: x - 30, y: taban + 40))
                    p.closeSubpath()
                    return p
                }
                let gecis = Gradient(stops: bugun
                    ? [.init(color: renk2.opacity(0.7), location: 0), .init(color: renk2, location: 1)]
                    : [.init(color: renk1.opacity(0.55), location: 0), .init(color: renk1.opacity(0.82), location: 0.55), .init(color: renk2.opacity(0.95), location: 1)])
                let dolgu = GraphicsContext.Shading.linearGradient(gecis, startPoint: CGPoint(x: 0, y: ust), endPoint: CGPoint(x: 0, y: taban))
                k2.drawLayer { su in
                    su.translateBy(x: cx, y: y)
                    su.rotate(by: .degrees(k))
                    su.scaleBy(x: 1, y: 1 + calkanti * 0.6)
                    su.translateBy(x: -cx, y: -y)
                    let fazA = t / (sure + 1.3) * 6.283, fazB = t / sure * 6.283
                    var arka = su
                    arka.opacity = 0.55
                    arka.translateBy(x: 0, y: -1.2)
                    arka.fill(kapat(suYolu(1.1, 13, 1.9 + fazA)), with: dolgu)
                    su.fill(kapat(suYolu(1, 12, fazB)), with: dolgu)
                    su.stroke(suYolu(1, 12, fazB), with: .color(.white.opacity(0.6)), lineWidth: 0.7)
                }
                // Kırılan ışık ve kabarcıklar
                k2.fill(Path(ellipseIn: CGRect(x: cx + 2 - bw * 0.3, y: (y + taban) / 2 - max(2, (taban - y) * 0.22),
                                               width: bw * 0.6, height: max(4, (taban - y) * 0.44))),
                        with: .color(.white.opacity(0.1)))
                let yol = taban - y - 8
                if yol > 10 {
                    for b in 0..<3 {
                        let d = 2.8 + Double(b) * 1.1 + Double(i) * 0.2
                        let u = ((t + Double(b) * 1.3 + Double(i) * 0.6).truncatingRemainder(dividingBy: d)) / d
                        let bx = x + 4 + CGFloat((i * 7 + b * 5) % Int(bw - 8))
                        let by = taban - 4 - CGFloat(u) * yol
                        let r: CGFloat = [1.1, 0.8, 1.4][b]
                        k2.stroke(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: 2 * r, height: 2 * r)),
                                  with: .color(.white.opacity(0.75 * (1 - u))), lineWidth: 0.5)
                    }
                }
                k2.fill(Path(CGRect(x: x, y: taban - 6, width: bw, height: 6)), with: .color(renk2.opacity(0.25)))
            }
            // Camın parıltısı ve kenarı yalnız dolu kısımda
            ctx.drawLayer { cam in
                cam.clip(to: dolu)
                cam.fill(Path(roundedRect: CGRect(x: x + 3, y: ust + 7, width: 2.6, height: H - 14), cornerRadius: 1.3),
                         with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)]),
                                               startPoint: CGPoint(x: x + 3, y: 0), endPoint: CGPoint(x: x + 5.6, y: 0)))
                cam.stroke(tup, with: .color(KlasikRenk.murekkep.opacity(0.28)), lineWidth: 0.7)
            }
        }
    }
}
