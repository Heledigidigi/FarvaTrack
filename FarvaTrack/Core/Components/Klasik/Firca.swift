import SwiftUI

// Fırça motoru (önizlemedeki firca.js'in Swift karşılığı): her çizgi dolgulu, uçları sivrilen,
// basınçla kalınlığı değişen bir şekil. Titreme filtresi yok; düzensizlik yumuşak gürültüden gelir.

enum Firca {
    /// Tohumlu sözde rastgele üreteç (0..<1).
    struct Uretec {
        private var a: UInt32
        init(_ tohum: Int) { a = UInt32(truncatingIfNeeded: tohum &* 2_654_435_761) | (tohum == 0 ? 1 : 0) }
        mutating func sonraki() -> Double {
            a = a &+ 0x6D2B_79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
    }

    /// Birkaç sinüsün toplamından yumuşak 1B gürültü (-1…1).
    struct Gurultu {
        private let k: [(Double, Double, Double)]
        private let norm: Double
        init(_ tohum: Int) {
            var r = Uretec(tohum)
            var k: [(Double, Double, Double)] = []
            for i in 0..<4 {
                let f = 1 + Double(i) * 1.7 + r.sonraki() * 1.3
                let faz = r.sonraki() * 6.283
                k.append((f, faz, 1 / Double(i + 1)))
            }
            self.k = k
            norm = k.reduce(0) { $0 + $1.2 }
        }
        func callAsFunction(_ t: Double) -> Double {
            k.reduce(0) { $0 + sin(t * $1.0 * 6.283 + $1.1) * $1.2 } / norm
        }
    }

    struct Ayar {
        var w: Double = 2
        var tohum = 1
        var giris = 0.14
        var cikis = 0.22
        var basinc = 0.22
        var salinim = 0.25
        var enAz = 0.12
    }

    /// Nokta dizisinden fırça şekli.
    static func cizgi(_ noktalar: [CGPoint], _ o: Ayar) -> Path {
        let n = noktalar.count
        guard n > 1 else { return Path() }
        let nz = Gurultu(o.tohum), nz2 = Gurultu(o.tohum + 99)
        var L: [Double] = [0]
        for i in 1..<n { L.append(L[i - 1] + Double(hypot(noktalar[i].x - noktalar[i - 1].x, noktalar[i].y - noktalar[i - 1].y))) }
        let toplam = max(L[n - 1], 1)
        var sol: [CGPoint] = [], sag: [CGPoint] = []
        for i in 0..<n {
            let t = L[i] / toplam
            let a = noktalar[max(0, i - 1)], b = noktalar[min(n - 1, i + 1)]
            var dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let d = max(hypot(dx, dy), 0.0001)
            dx /= d; dy /= d
            let nx = -dy, ny = dx
            var incelme = 1.0
            if t < o.giris { incelme = sin(t / o.giris * .pi / 2) }
            if t > 1 - o.cikis { incelme = min(incelme, sin((1 - t) / o.cikis * .pi / 2)) }
            let w = o.w * max(o.enAz, incelme) * (1 + o.basinc * nz(t * toplam / 60))
            let kay = o.salinim * nz2(t * toplam / 40)
            let cx = Double(noktalar[i].x) + nx * kay, cy = Double(noktalar[i].y) + ny * kay
            sol.append(CGPoint(x: cx + nx * w / 2, y: cy + ny * w / 2))
            sag.append(CGPoint(x: cx - nx * w / 2, y: cy - ny * w / 2))
        }
        var yol = Path()
        yol.move(to: sol[0])
        sol.dropFirst().forEach { yol.addLine(to: $0) }
        sag.reversed().forEach { yol.addLine(to: $0) }
        yol.closeSubpath()
        return yol
    }

    static func duz(_ a: CGPoint, _ b: CGPoint, _ o: Ayar) -> Path {
        let n = max(8, Int((hypot(b.x - a.x, b.y - a.y) / 2).rounded()))
        let p = (0...n).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(n)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        return cizgi(p, o)
    }

    /// Saat 12'den başlayan fırça halkası.
    static func halka(merkez: CGPoint, r: CGFloat, ilerleme: Double, o: Ayar, yaricapSalinimi: Double = 0.9) -> Path {
        let p = min(max(ilerleme, 0.02), 0.985)
        let nz = Gurultu(o.tohum + 7)
        let n = max(24, Int(220 * p))
        let pts = (0...n).map { i -> CGPoint in
            let a = -Double.pi / 2 + 2 * .pi * p * Double(i) / Double(n)
            let rr = Double(r) + yaricapSalinimi * nz(Double(i) / Double(n) * 2)
            return CGPoint(x: Double(merkez.x) + cos(a) * rr, y: Double(merkez.y) + sin(a) * rr)
        }
        var oo = o
        oo.giris = 0.06; oo.cikis = 0.18
        return cizgi(pts, oo)
    }

    /// Kapalı bir şeklin (çember) fırça konturu.
    static func cember(merkez: CGPoint, r: CGFloat, o: Ayar) -> Path {
        let n = max(24, Int(2 * .pi * r / 1.5))
        let pts = (0...Int(Double(n) * 1.05)).map { i -> CGPoint in
            let a = -Double.pi / 2 + 2 * .pi * (0.02 + Double(i) / Double(n))
            return CGPoint(x: Double(merkez.x) + cos(a) * Double(r), y: Double(merkez.y) + sin(a) * Double(r))
        }
        var oo = o
        oo.giris = 0.05; oo.cikis = 0.08
        return cizgi(pts, oo)
    }

    /// Suluboya leke kenarlı sütun: üstü yuvarlak, kenarları hafif dalgalı.
    static func sutun(_ r: CGRect, tohum: Int) -> Path {
        let nz = Gurultu(tohum), nz2 = Gurultu(tohum + 5)
        let x = Double(r.minX), y = Double(r.minY), w = Double(r.width), h = Double(r.height)
        let yr = min(w / 2, h)
        let alt = y + h, n = 14
        var p: [CGPoint] = []
        for i in 0...n { p.append(CGPoint(x: x + 0.4 * nz(Double(i) / Double(n)), y: alt - (h - yr) * Double(i) / Double(n))) }
        for i in 0...n {
            let a = Double.pi + .pi * Double(i) / Double(n)
            p.append(CGPoint(x: x + w / 2 + cos(a) * w / 2 + 0.3 * nz2(Double(i) / Double(n)), y: y + yr + sin(a) * yr * 0.9))
        }
        for i in 0...n { p.append(CGPoint(x: x + w + 0.4 * nz2(Double(i) / Double(n) + 3), y: y + yr + (h - yr) * Double(i) / Double(n))) }
        p.append(CGPoint(x: x + w * 0.5, y: alt + 0.6))
        var yol = Path()
        yol.move(to: p[0])
        p.dropFirst().forEach { yol.addLine(to: $0) }
        yol.closeSubpath()
        return yol
    }

    /// Noktalar arasına ara nokta ekler (fırça daha akıcı kıvrılsın).
    static func ornekle(_ p: [CGPoint], _ k: Int) -> [CGPoint] {
        guard p.count > 1 else { return p }
        var out: [CGPoint] = []
        for i in 0..<(p.count - 1) {
            for j in 0..<k {
                let t = CGFloat(j) / CGFloat(k)
                out.append(CGPoint(x: p[i].x + (p[i + 1].x - p[i].x) * t, y: p[i].y + (p[i + 1].y - p[i].y) * t))
            }
        }
        out.append(p[p.count - 1])
        return out
    }
}

// MARK: - Hazır şekiller

/// Yatay fırça çizgisi (ayırıcı, girdi altı çizgisi).
struct FircaCizgiSekli: Shape {
    var kalinlik: Double = 0.8
    var tohum = 1
    func path(in rect: CGRect) -> Path {
        Firca.duz(CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY),
                  Firca.Ayar(w: kalinlik, tohum: tohum, giris: 0.14, basinc: 0.28))
    }
}

/// Bir dikdörtgene oturan suluboya sütun.
struct FircaSutunSekli: Shape {
    var tohum: Int
    func path(in rect: CGRect) -> Path { Firca.sutun(rect, tohum: tohum) }
}

/// Elle çizilmiş çember konturu.
struct FircaCemberSekli: Shape {
    var kalinlik: Double = 1
    var tohum = 4
    func path(in rect: CGRect) -> Path {
        Firca.cember(merkez: CGPoint(x: rect.midX, y: rect.midY), r: min(rect.width, rect.height) / 2 - CGFloat(kalinlik),
                     o: Firca.Ayar(w: kalinlik, tohum: tohum, basinc: 0.35))
    }
}
