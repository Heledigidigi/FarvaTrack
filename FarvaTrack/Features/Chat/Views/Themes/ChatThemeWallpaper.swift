import SwiftUI
import MetalKit

// MARK: - Duvar kâğıdı

/// Sohbetin arkasındaki tema zemini. Ekranı doldurur (güvenli alanı yok sayar).
/// "Hareketi azalt" açıkken animasyonlar durur, görsel sabit kalır.
struct ChatThemeWallpaper: View {
    let choice: ChatThemeChoice

    var body: some View {
        switch choice.id {
        case .plain: Color.clear
        case .rainbow: RainbowWallpaper()
        case .pixelMeadow: PixelMeadowWallpaper()
        case .hillCat: HillCatWallpaper(sky: choice.hillSky)
        }
    }
}

/// İçeriği görsel uzayında (ör. 676 × 1200) çizer ve kabı dolduracak biçimde ölçekler.
private struct ImageSpace<Content: View>: View {
    let size: CGSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let fill = AspectFill(image: size, container: proxy.size)
            ZStack(alignment: .topLeading) { content() }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(fill.scale, anchor: .topLeading)
                .offset(x: fill.origin.x, y: fill.origin.y)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private extension GraphicsContext {
    /// Yumuşak ışık lekesi.
    func glow(_ center: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        guard opacity > 0.002, radius > 0 else { return }
        fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
             with: .radialGradient(Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
                                   center: center, startRadius: 0, endRadius: radius))
    }

    /// Dört kollu parıltı (+ hale).
    func sparkle(_ center: CGPoint, size s: CGFloat, opacity: Double, rotation: Double) {
        guard opacity > 0.003 else { return }
        glow(center, radius: s * 2.6, color: Color(red: 1, green: 0.96, blue: 0.89), opacity: 0.5 * opacity)
        var path = Path()
        for i in 0..<8 {
            let r = i % 2 == 1 ? s * 0.16 : s * (i % 4 == 0 ? 1.7 : 1.05)
            let a = Double(i) * .pi / 4 + rotation
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        fill(path, with: .color(.white.opacity(opacity)))
    }
}

// MARK: - 1 · Gökkuşağı Cenneti

private struct RainbowWallpaper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = RainbowScene()

    var body: some View {
        ImageSpace(size: RainbowScene.size) {
            Image("TemaGokkusagi").resizable().frame(width: RainbowScene.size.width, height: RainbowScene.size.height)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                Canvas { context, _ in
                    scene.draw(in: &context, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .frame(width: RainbowScene.size.width, height: RainbowScene.size.height)
            .allowsHitTesting(false)
        }
    }
}

/// Parçacıklar ve ışıklar; kare başına `draw` hem ilerletir hem çizer. Koordinatlar görsel uzayında (676 × 1200).
private final class RainbowScene {
    static let size = CGSize(width: 676, height: 1200)

    private struct Spark { var p: CGPoint; var v: CGVector; var size: CGFloat; var life: Double; var t: Double; var star: Bool; var rot: Double; var spin: Double }
    private struct Mist { var x: CGFloat; let y: CGFloat; let r: CGFloat; let v: CGFloat; let phase: Double; let a: Double }
    private struct Mote { var x: CGFloat; var y: CGFloat; var r: CGFloat; var vy: CGFloat; var sway: CGFloat; var phase: Double; var color: Color; var a: Double }
    private struct Feather { var x: CGFloat; var y: CGFloat; var t: Double; let life: Double; let phase: Double; let scale: CGFloat }
    private struct Highlight { var s: Double; let speed: Double }
    private struct Arc { let point: (Double) -> CGPoint; let weight: Double; let band: CGFloat; var highlights: [Highlight] }

    private let sun = CGPoint(x: 338, y: 122)
    private let horns: [(base: CGPoint, tip: CGPoint, phase: Double)] = [
        (CGPoint(x: 43, y: 553), CGPoint(x: 41, y: 529), 0), (CGPoint(x: 616, y: 582), CGPoint(x: 640, y: 551), 1.9)
    ]
    private let castles = [CGPoint(x: 213, y: 216), CGPoint(x: 462, y: 283), CGPoint(x: 62, y: 409),
                           CGPoint(x: 186, y: 505), CGPoint(x: 421, y: 248), CGPoint(x: 545, y: 258)]
    private let doves = [CGPoint(x: 128, y: 330), CGPoint(x: 40, y: 262), CGPoint(x: 548, y: 192), CGPoint(x: 566, y: 262), CGPoint(x: 520, y: 515)]
    private let road: Path = {
        var p = Path()
        p.addLines([CGPoint(x: 262, y: 775), CGPoint(x: 420, y: 775), CGPoint(x: 676, y: 1010),
                    CGPoint(x: 676, y: 1200), CGPoint(x: 0, y: 1200), CGPoint(x: 0, y: 1030)])
        p.closeSubpath()
        return p
    }()
    private let hamster = CGRect(x: 222, y: 555, width: 220, height: 240)
    private let warm = [Color(red: 1, green: 0.91, blue: 0.75), Color(red: 1, green: 0.81, blue: 0.87),
                        Color(red: 0.94, green: 0.84, blue: 1), Color(red: 1, green: 0.96, blue: 0.84)]

    private var arcs: [Arc]
    private var sparks: [Spark] = []
    private var mists: [Mist] = []
    private var motes: [Mote] = []
    private var feathers: [Feather] = []
    private var castleTimers: [(t: Double, next: Double)]
    private var featherIn = 2.0
    private var sparkAccumulator = 0.0
    private var roadAccumulator = 0.0
    private var last: Double?

    init() {
        func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint) -> (Double) -> CGPoint {
            { t in CGPoint(x: (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * c.x + t * t * b.x,
                           y: (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * c.y + t * t * b.y) }
        }
        arcs = [
            Arc(point: { t in let a = Double.pi * (1.03 - t * 0.8); return CGPoint(x: 330 + 318 * cos(a), y: 415 - 342 * sin(a)) },
                weight: 5, band: 22, highlights: [Highlight(s: 0, speed: 0.09), Highlight(s: 0.45, speed: 0.06), Highlight(s: 0.8, speed: 0.12)]),
            Arc(point: quad(CGPoint(x: 572, y: 452), CGPoint(x: 612, y: 380), CGPoint(x: 676, y: 366)), weight: 1.4, band: 14, highlights: [Highlight(s: 0.2, speed: 0.16)]),
            Arc(point: quad(CGPoint(x: 0, y: 548), CGPoint(x: 118, y: 488), CGPoint(x: 206, y: 612)), weight: 1.6, band: 16, highlights: [Highlight(s: 0.6, speed: 0.13)]),
            Arc(point: quad(CGPoint(x: 30, y: 458), CGPoint(x: 88, y: 452), CGPoint(x: 122, y: 525)), weight: 0.8, band: 10, highlights: [Highlight(s: 0.1, speed: 0.2)])
        ]
        castleTimers = (0..<6).map { _ in (Double.random(in: 0...6), Double.random(in: 1...6)) }
        for _ in 0..<11 {
            mists.append(Mist(x: .random(in: -100...780), y: .random(in: 170...770), r: .random(in: 80...150),
                              v: .random(in: 3...6) * (Bool.random() ? -1 : 1), phase: .random(in: 0...6), a: .random(in: 0.08...0.15)))
        }
        for _ in 0..<34 { motes.append(makeMote(initial: true)) }
    }

    private func makeMote(initial: Bool) -> Mote {
        Mote(x: .random(in: 0...Self.size.width), y: initial ? .random(in: 0...Self.size.height) : Self.size.height + 20,
             r: .random(in: 3...9), vy: .random(in: -16 ... -7), sway: .random(in: 6...16), phase: .random(in: 0...6),
             color: warm.randomElement()!, a: .random(in: 0.18...0.4))
    }

    private static func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    private static func bell(_ t: Double) -> Double { let s = sin(.pi * min(1, max(0, t))); return s * s }
    private func nearHamster(_ p: CGPoint, _ r: CGFloat) -> Bool { hamster.insetBy(dx: -r, dy: -r).contains(p) }

    func draw(in context: inout GraphicsContext, time T: Double) {
        let dt = min(0.05, max(0, T - (last ?? T)))
        last = T
        context.blendMode = .screen

        // 1) Pembe sis: yavaş süzülür, nefes alır; hamster'ın üstünde silikleşir.
        for i in mists.indices {
            mists[i].x += mists[i].v * dt
            if mists[i].x > 820 { mists[i].x = -140 }
            if mists[i].x < -140 { mists[i].x = 820 }
            let m = mists[i]
            let r = m.r * (1 + 0.07 * sin(T * 0.35 + m.phase))
            let a = m.a * (0.8 + 0.2 * sin(T * 0.5 + m.phase)) * (nearHamster(CGPoint(x: m.x, y: m.y), r * 0.5) ? 0.25 : 1)
            var c = context
            c.translateBy(x: m.x, y: m.y)
            c.scaleBy(x: 1, y: 0.55)
            c.glow(.zero, radius: r, color: Color(red: 1, green: 0.88, blue: 0.93), opacity: a)
        }

        // 2) Güneş: ağır dönen ince ışınlar ve nefes alan hale.
        var rays = context
        rays.translateBy(x: sun.x, y: sun.y)
        rays.rotate(by: .radians(T * 0.035))
        for i in 0..<24 {
            rays.rotate(by: .radians(.pi * 2 / 24))
            let length = (i % 2 == 1 ? 200 : 300) + 45 * sin(T * 0.6 + Double(i) * 1.3)
            let w: CGFloat = i % 2 == 1 ? 5 : 9
            var ray = Path()
            ray.move(to: .zero); ray.addLine(to: CGPoint(x: length, y: -w)); ray.addLine(to: CGPoint(x: length, y: w)); ray.closeSubpath()
            let tone = Color(red: 1, green: 0.98, blue: 0.89)
            rays.fill(ray, with: .linearGradient(Gradient(colors: [tone.opacity(0.16 + 0.05 * sin(T * 0.8 + Double(i))), tone.opacity(0)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: length, y: 0)))
        }
        context.glow(sun, radius: 78 + 14 * sin(T * 0.9), color: Color(red: 1, green: 1, blue: 0.94), opacity: 0.5)
        context.glow(sun, radius: 150 + 20 * sin(T * 0.5 + 1), color: Color(red: 1, green: 0.93, blue: 0.84), opacity: 0.16)

        // 3) Merdivenden güneşe yükselen ışık.
        let stair = T.truncatingRemainder(dividingBy: 7) / 7
        if stair < 0.75 {
            let t = Self.ease(stair / 0.75)
            var c = context
            c.translateBy(x: 337, y: 560 - 410 * t)
            c.scaleBy(x: 1, y: 0.42)
            c.glow(.zero, radius: 58 * (1 - t) + 12, color: Color(red: 1, green: 0.97, blue: 0.87), opacity: 0.38 * Self.bell(stair / 0.75))
        }

        // 4) Gökkuşaklarında sürekli kayan yumuşak ışıklar.
        for a in arcs.indices {
            for h in arcs[a].highlights.indices {
                var s = arcs[a].highlights[h].s + dt * arcs[a].highlights[h].speed
                if s > 1.25 { s -= 1.25 }
                arcs[a].highlights[h].s = s
                guard s <= 1 else { continue }
                let envelope = Self.bell(s)
                for k in -5...5 {
                    let t = min(1, max(0, s + Double(k) * 0.01))
                    context.glow(arcs[a].point(t), radius: arcs[a].band * 1.15, color: .white,
                                 opacity: (1 - Double(abs(k)) / 6) * 0.22 * envelope)
                }
            }
        }

        // 5) Boynuzlar: tabandan uca kayan ışık, uçta nefes alan parıltı, ara ara minik ışıltılar.
        for horn in horns {
            let cycle = (T + horn.phase).truncatingRemainder(dividingBy: 3.8) / 3.8
            if cycle < 0.5 {
                let t = Self.ease(cycle / 0.5)
                let p = CGPoint(x: horn.base.x + (horn.tip.x - horn.base.x) * t, y: horn.base.y + (horn.tip.y - horn.base.y) * t)
                context.glow(p, radius: 7, color: Color(red: 1, green: 0.97, blue: 0.84), opacity: 0.95 * Self.bell(cycle / 0.5))
            }
            context.glow(horn.tip, radius: 16, color: Color(red: 1, green: 0.96, blue: 0.84), opacity: 0.3 + 0.22 * sin(T * 1.8 + horn.phase))
            if cycle > 0.48, cycle < 0.5, Double.random(in: 0...1) < 0.35 {
                sparks.append(Spark(p: horn.tip, v: CGVector(dx: .random(in: -7...7), dy: .random(in: -20 ... -9)),
                                    size: .random(in: 1.5...2.8), life: .random(in: 1.2...2), t: 0, star: true, rot: 0, spin: .random(in: -1...1)))
            }
        }

        // 6) Kale kulelerinde ara ara parıltı.
        for i in castles.indices {
            castleTimers[i].t += dt
            if castleTimers[i].t > castleTimers[i].next { castleTimers[i] = (0, .random(in: 2.5...7)) }
            if castleTimers[i].t < 1.4 {
                context.sparkle(castles[i], size: 3.2, opacity: Self.bell(castleTimers[i].t / 1.4) * 0.9, rotation: T * 0.4)
            }
        }

        // 7) Yükselen ışık tanecikleri.
        for i in motes.indices {
            motes[i].y += motes[i].vy * dt
            if motes[i].y < -20 { motes[i] = makeMote(initial: false) }
            let m = motes[i]
            let p = CGPoint(x: m.x + sin(T * 0.6 + m.phase) * m.sway, y: m.y)
            if !nearHamster(p, m.r) {
                context.glow(p, radius: m.r * 2.2, color: m.color, opacity: m.a * (0.65 + 0.35 * sin(T * 1.3 + m.phase)))
            }
        }

        // 8) Gökkuşağı yolunda bize doğru akan ışık dalgaları.
        var roadContext = context
        roadContext.clip(to: road)
        for k in 0..<3 {
            let s = (T * 0.11 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let y = 780 + 420 * pow(s, 1.7), h = 16 + 70 * s, a = 0.2 * Self.bell(s)
            roadContext.fill(Path(CGRect(x: 0, y: y - h, width: Self.size.width, height: h * 2)),
                             with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                                    .init(color: .white.opacity(a), location: 0.5),
                                                                    .init(color: .white.opacity(0), location: 1)]),
                                                   startPoint: CGPoint(x: 0, y: y - h), endPoint: CGPoint(x: 0, y: y + h)))
        }

        // 9) Güvercinlerden süzülen tüyler.
        featherIn -= dt
        if featherIn <= 0 {
            featherIn = .random(in: 2.5...5)
            let d = doves.randomElement()!
            feathers.append(Feather(x: d.x + .random(in: -10...10), y: d.y + .random(in: 0...10), t: 0,
                                    life: .random(in: 7...10), phase: .random(in: 0...6), scale: .random(in: 0.8...1.2)))
        }
        var normal = context
        normal.blendMode = .normal
        feathers = feathers.compactMap { feather in
            var f = feather
            f.t += dt
            guard f.t <= f.life else { return nil }
            f.y += 14 * dt
            let swing = sin(f.t * 1.1 + f.phase)
            var c = normal
            c.opacity = min(1, f.t, (f.life - f.t) / 1.5) * 0.9
            c.translateBy(x: f.x + swing * 18, y: f.y)
            c.rotate(by: .radians(swing * 0.7))
            c.scaleBy(x: f.scale, y: f.scale)
            c.fill(Path(ellipseIn: CGRect(x: -3.2, y: -9, width: 6.4, height: 18)), with: .color(Color(red: 1, green: 0.99, blue: 0.97).opacity(0.95)))
            var quill = Path()
            quill.move(to: CGPoint(x: 0, y: -8)); quill.addLine(to: CGPoint(x: 0, y: 11))
            c.stroke(quill, with: .color(Color(red: 0.8, green: 0.75, blue: 0.78).opacity(0.8)), lineWidth: 0.7)
            return f
        }

        // 10) Gökkuşağı ve yol parıltıları.
        sparkAccumulator += dt * 8
        while sparkAccumulator > 1 {
            sparkAccumulator -= 1
            let total = arcs.reduce(0) { $0 + $1.weight }
            var pick = Double.random(in: 0..<total)
            var arc = arcs[0]
            for candidate in arcs { pick -= candidate.weight; if pick <= 0 { arc = candidate; break } }
            let p = arc.point(.random(in: 0...1)), off = CGFloat.random(in: -arc.band / 2 ... arc.band / 2)
            sparks.append(Spark(p: CGPoint(x: p.x + off * 0.3, y: p.y + off), v: .zero, size: .random(in: 3...8.5),
                                life: .random(in: 1.1...2.2), t: 0, star: true, rot: .random(in: 0...1), spin: .random(in: -0.6...0.6)))
        }
        roadAccumulator += dt * 15
        while roadAccumulator > 1 {
            roadAccumulator -= 1
            for _ in 0..<10 {
                let p = CGPoint(x: .random(in: 0...Self.size.width), y: .random(in: 780...Self.size.height))
                if road.contains(p), !nearHamster(p, 4) {
                    let k = (p.y - 780) / 420
                    sparks.append(Spark(p: p, v: .zero, size: .random(in: 1.6...3.6) * (0.6 + k), life: .random(in: 0.6...1.3),
                                        t: 0, star: false, rot: 0, spin: 0))
                    break
                }
            }
        }
        sparks = sparks.compactMap { spark in
            var s = spark
            s.t += dt
            guard s.t <= s.life else { return nil }
            s.p.x += s.v.dx * dt
            s.p.y += s.v.dy * dt
            let u = s.t / s.life, a = Self.bell(u)
            if s.star {
                context.sparkle(s.p, size: s.size * (0.7 + 0.3 * sin(.pi * u)), opacity: a, rotation: s.rot + s.spin * s.t)
            } else {
                context.fill(Path(ellipseIn: CGRect(x: s.p.x - s.size / 2, y: s.p.y - s.size / 2, width: s.size, height: s.size)),
                             with: .color(.white.opacity(a * 0.9)))
                context.fill(Path(CGRect(x: s.p.x - s.size * 1.7, y: s.p.y - 0.4, width: s.size * 3.4, height: 0.8)),
                             with: .color(.white.opacity(a * 0.3)))
            }
            return s
        }
    }
}

// MARK: - 2 · Piksel Çayır

private struct PixelMeadowWallpaper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let clock = PixelMeadowClock()
    private let stars: [(CGPoint, CGFloat, Double)] = {
        var generator = SeededGenerator(seed: 42)
        return (0..<70).map { _ in
            (CGPoint(x: (Double.random(in: 0..<600, using: &generator) / 4).rounded(.down) * 4,
                     y: (Double.random(in: 0..<470, using: &generator) / 4).rounded(.down) * 4),
             Double.random(in: 0...1, using: &generator) < 0.2 ? 4 : 2.5,
             Double.random(in: 0...6, using: &generator))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { timeline in
            let hour = clock.virtualHour(at: timeline.date)
            let sky = PixelMeadowSky.at(hour)
            let t = timeline.date.timeIntervalSinceReferenceDate
            ImageSpace(size: CGSize(width: 600, height: 1200)) {
                Canvas { context, _ in drawSky(&context, sky: sky, time: t) }
                    .frame(width: 600, height: 600)
                Image("TemaCayirGokyuzu").resizable().frame(width: 600, height: 600)
                    .opacity(sky.sunsetWeight)
                Canvas { context, _ in drawBodies(&context, hour: hour) }
                    .frame(width: 600, height: 600)
                clouds(sky, time: t)
                ground(sky)
            }
            .compositingGroup()
        }
    }

    private func clouds(_ sky: PixelMeadowSky, time t: Double) -> some View {
        let bright = sky.cloudBrightness
        return Image("TemaCayirBulut").resizable()
            .frame(width: 500, height: 426)
            .saturation(sky.cloudSaturation)
            .colorMultiply(Color(white: min(1, bright)))
            .brightness(max(0, bright - 1) * 0.5)
            .offset(x: 100 + sin(t / 40) * 18, y: 10)
    }

    @ViewBuilder
    private func ground(_ sky: PixelMeadowSky) -> some View {
        let night = sky.nightWeight
        let haze = min(1, max(0, 0.28 + 0.72 * night - 0.3 * sky.sunsetWeight))
        let hazeColor = sky.horizon.mixed(with: .rgb(22, 28, 62), night)
        let glowAmount = max(0, min(1, 1 - sky.sunsetWeight - night * 0.6))
        ZStack(alignment: .topLeading) {
            Image("TemaCayirZemin").resizable()
            // Uzak tepeler gökyüzü rengine karışır (gece temiz siluet).
            LinearGradient(stops: [.init(color: hazeColor.color.opacity(haze), location: 0),
                                   .init(color: hazeColor.color.opacity(haze * 0.92), location: 0.04),
                                   .init(color: hazeColor.color.opacity(haze * 0.5), location: 0.107),
                                   .init(color: hazeColor.color.opacity(0), location: 0.207)],
                           startPoint: .top, endPoint: .bottom)
            // Gece ay ışığı: sıcak tonlar soğur.
            ThemeRGBA.rgb(70, 88, 150).color.opacity(0.7 * night).blendMode(.color)
            // Gündüz ufuktaki turuncu gün batımı ışığı bastırılır.
            RadialGradient(colors: [ThemeRGBA.rgb(120, 150, 95).color.opacity(0.85 * glowAmount), .clear],
                           center: UnitPoint(x: 70.0 / 600, y: 45.0 / 700), startRadius: 0, endRadius: 330)
                .scaleEffect(x: 1, y: 120.0 / 330, anchor: UnitPoint(x: 70.0 / 600, y: 45.0 / 700))
                .blendMode(.color)
            sky.groundTint.color.blendMode(.multiply)
        }
        .compositingGroup()
        .mask(Image("TemaCayirZemin").resizable())
        .frame(width: 600, height: 700)
        .offset(y: 500)
    }

    private func drawSky(_ context: inout GraphicsContext, sky: PixelMeadowSky, time t: Double) {
        context.fill(Path(CGRect(x: 0, y: 0, width: 600, height: 600)),
                     with: .linearGradient(Gradient(colors: [sky.top.color, sky.horizon.color]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: 560)))
        guard sky.nightWeight > 0 else { return }
        for (p, s, phase) in stars {
            let a = sky.nightWeight * (0.55 + 0.45 * sin(t * 1.6 + phase))
            context.fill(Path(CGRect(x: p.x, y: p.y, width: s, height: s)), with: .color(.white.opacity(a)))
        }
    }

    /// Kare güneş (gündüz) ve kare ay (gece).
    private func drawBodies(_ context: inout GraphicsContext, hour: Double) {
        func body(_ c: CGPoint, day: Bool) {
            context.glow(c, radius: 120, color: Color(red: 1, green: 0.96, blue: 0.78), opacity: day ? 0.55 : 0.25)
            context.fill(Path(CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 68)),
                         with: .color(day ? Color(red: 1, green: 0.96, blue: 0.78) : Color(red: 0.91, green: 0.93, blue: 0.97)))
            context.fill(Path(CGRect(x: c.x - 22, y: c.y - 22, width: 44, height: 44)),
                         with: .color(day ? Color(red: 1, green: 0.98, blue: 0.9) : Color(red: 0.96, green: 0.97, blue: 0.98)))
            if !day {
                let crater = Color(red: 0.67, green: 0.7, blue: 0.78).opacity(0.7)
                context.fill(Path(CGRect(x: c.x - 22, y: c.y - 14, width: 10, height: 10)), with: .color(crater))
                context.fill(Path(CGRect(x: c.x + 6, y: c.y + 4, width: 12, height: 8)), with: .color(crater))
                context.fill(Path(CGRect(x: c.x - 8, y: c.y + 14, width: 8, height: 8)), with: .color(crater))
            }
        }
        if let t = PixelMeadowSky.sunProgress(hour) { body(PixelMeadowSky.bodyPosition(t), day: true) }
        if let t = PixelMeadowSky.moonProgress(hour) { body(PixelMeadowSky.bodyPosition(t), day: false) }
    }
}

/// Yıldızlar her açılışta aynı yerde dursun diye sabit tohumlu üreteç.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - 3 · Tepedeki Kedi

/// Gökyüzü ve sahne renkleri (önizlemede onaylanan üç seçenek).
struct HillSkyPreset: Equatable {
    var top, mid, low, horizon, sun, lit, shade: ThemeRGBA
    var cover, glow, stars, cirrus, puff, stretch: Float
    /// Tepe ve kedi: çarpma rengi, sol alttaki gölge, sağ üstten gelen sıcak ışık.
    var sceneMultiply: ThemeRGBA
    var sceneShade: ThemeRGBA
    var sceneWarm: ThemeRGBA

    static func preset(_ sky: ChatHillSky) -> HillSkyPreset {
        switch sky {
        case .golden:
            return HillSkyPreset(top: ThemeRGBA(hex: "#3B5B8E"), mid: ThemeRGBA(hex: "#9A93B6"), low: ThemeRGBA(hex: "#F2B48C"),
                                 horizon: ThemeRGBA(hex: "#FFD9A2"), sun: ThemeRGBA(hex: "#FFF0C6"), lit: ThemeRGBA(hex: "#FFD6A4"),
                                 shade: ThemeRGBA(hex: "#806C88"), cover: 0.47, glow: 1, stars: 0, cirrus: 1, puff: 1.2, stretch: 1,
                                 sceneMultiply: ThemeRGBA(hex: "#FFF0DC"), sceneShade: .rgb(96, 78, 120, 0.38), sceneWarm: .rgb(255, 196, 130, 0.55))
        case .rose:
            return HillSkyPreset(top: ThemeRGBA(hex: "#1D2550"), mid: ThemeRGBA(hex: "#5C4B80"), low: ThemeRGBA(hex: "#DC8C98"),
                                 horizon: ThemeRGBA(hex: "#F7BB90"), sun: ThemeRGBA(hex: "#FFD3AC"), lit: ThemeRGBA(hex: "#F6B0A6"),
                                 shade: ThemeRGBA(hex: "#4B3E64"), cover: 0.46, glow: 0.55, stars: 0.9, cirrus: 0.7, puff: 0.6, stretch: 1.6,
                                 sceneMultiply: ThemeRGBA(hex: "#C6B2D8"), sceneShade: .rgb(44, 36, 92, 0.5), sceneWarm: .rgb(250, 170, 196, 0.45))
        case .fire:
            return HillSkyPreset(top: ThemeRGBA(hex: "#232F50"), mid: ThemeRGBA(hex: "#7C4E72"), low: ThemeRGBA(hex: "#EF7B50"),
                                 horizon: ThemeRGBA(hex: "#FFC66C"), sun: ThemeRGBA(hex: "#FFF1C2"), lit: ThemeRGBA(hex: "#FFAE6C"),
                                 shade: ThemeRGBA(hex: "#4C2F4C"), cover: 0.43, glow: 1.2, stars: 0, cirrus: 1.2, puff: 1, stretch: 1.25,
                                 sceneMultiply: ThemeRGBA(hex: "#F2B896"), sceneShade: .rgb(72, 30, 62, 0.5), sceneWarm: .rgb(255, 150, 80, 0.6))
        }
    }
}

private struct HillCatWallpaper: View {
    let sky: ChatHillSky
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let preset = HillSkyPreset.preset(sky)
        ImageSpace(size: ChatThemeSun.imageSize) {
            Group {
                if HillSkyRenderer.isSupported {
                    HillSkyView(preset: preset, paused: reduceMotion)
                } else {
                    LinearGradient(colors: [preset.top.color, preset.mid.color, preset.low.color, preset.horizon.color],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: 736, height: 1472)
            scene(preset)
        }
    }

    /// Tepe ve kedi: gökyüzünün ışığına göre renklenir (sağ üstten ışık, sol altta gölge).
    private func scene(_ preset: HillSkyPreset) -> some View {
        ZStack {
            Image("TemaKediOnPlan").resizable()
            preset.sceneMultiply.color.blendMode(.multiply)
            LinearGradient(stops: [.init(color: .clear, location: 0.25), .init(color: preset.sceneShade.color, location: 0.85)],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
                .blendMode(.multiply)
            RadialGradient(colors: [preset.sceneWarm.color, .clear], center: UnitPoint(x: 1, y: -420.0 / 747),
                           startRadius: 0, endRadius: 950 * 0.75)
                .blendMode(.softLight)
        }
        .compositingGroup()
        .mask(Image("TemaKediOnPlan").resizable())
        .frame(width: 736, height: 747)
        .offset(y: 725)
    }
}

// MARK: Metal gökyüzü

/// Shader'a giden değerler (`HillSky.metal` içindeki `HillSkyUniforms` ile aynı düzen).
struct HillSkyUniforms {
    var top: SIMD4<Float>, mid: SIMD4<Float>, low: SIMD4<Float>, hor: SIMD4<Float>
    var sunColor: SIMD4<Float>, lit: SIMD4<Float>, shade: SIMD4<Float>
    var resolution: SIMD2<Float>
    var sun: SIMD2<Float>
    var time: Float, cover: Float, glow: Float, stars: Float, cirrus: Float, puff: Float, stretch: Float, pad: Float

    init(preset p: HillSkyPreset, resolution: SIMD2<Float>, time: Float) {
        top = p.top.simd; mid = p.mid.simd; low = p.low.simd; hor = p.horizon.simd
        sunColor = p.sun.simd; lit = p.lit.simd; shade = p.shade.simd
        self.resolution = resolution
        sun = SIMD2(Float(ChatThemeSun.sunInImage.x / ChatThemeSun.imageSize.width * 0.5),
                    Float(ChatThemeSun.sunInImage.y / ChatThemeSun.imageSize.height))
        self.time = time
        cover = p.cover; glow = p.glow; stars = p.stars; cirrus = p.cirrus; puff = p.puff; stretch = p.stretch; pad = 0
    }
}

final class HillSkyRenderer: NSObject, MTKViewDelegate {
    static let isSupported: Bool = {
        guard let device = MTLCreateSystemDefaultDevice(), let library = device.makeDefaultLibrary() else { return false }
        return library.makeFunction(name: "hillSkyFragment") != nil
    }()

    var preset: HillSkyPreset
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let start = CACurrentMediaTime()

    init?(device: MTLDevice, preset: HillSkyPreset, format: MTLPixelFormat) {
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "hillSkyVertex"),
              let fragment = library.makeFunction(name: "hillSkyFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = format
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.queue = queue
        self.pipeline = pipeline
        self.preset = preset
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let size = view.drawableSize
        var uniforms = HillSkyUniforms(preset: preset, resolution: SIMD2(Float(size.width), Float(size.height)),
                                       time: Float(CACurrentMediaTime() - start))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<HillSkyUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// Gökyüzü düşük çözünürlükte (görsel noktası başına 0,75 piksel), saniyede 30 kare çizilir; bulutlar yumuşak, pil dostu.
private struct HillSkyView: UIViewRepresentable {
    let preset: HillSkyPreset
    let paused: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var renderer: HillSkyRenderer? }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = true
        view.contentScaleFactor = 0.75
        view.preferredFramesPerSecond = 30
        view.isUserInteractionEnabled = false
        if let device = view.device {
            context.coordinator.renderer = HillSkyRenderer(device: device, preset: preset, format: view.colorPixelFormat)
        }
        view.delegate = context.coordinator.renderer
        apply(paused: paused, to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.preset = preset
        apply(paused: paused, to: view)
        if paused { view.setNeedsDisplay() }
    }

    private func apply(paused: Bool, to view: MTKView) {
        view.isPaused = paused
        view.enableSetNeedsDisplay = paused
    }
}
