import SwiftUI

// Özet ekranının elle çizilmiş öğeleri: fırça halkası (enso), bulutlu hilal, süzülen tüy,
// modül simgeleri ve mürekkep gölgesi. Tasarım tuvali: "Özet — sıradan dışı denemeler".

// MARK: - Renkler

enum OzetRenk {
    static let adim = Color(hex: "#A8584C")
    static let kalori = Color(hex: "#B98D45")
    static let su = Color(hex: "#6E8E92")
    static let uykuBaslik = Color(hex: "#5C4A6E")
    static let kiloBaslik = Color(hex: "#4E6A4A")
    static let tumu = Color(hex: "#A23A2E")
    static let golge = Color(hex: "#462A0F")
    static let soluk = Color(hex: "#8A7458")
}

// MARK: - Biçim yardımcıları (test edilir)

enum OzetBicim {
    /// Uyku süresini saat ve dakikaya böler; değer yoksa `nil`.
    nonisolated static func uykuParcalari(_ saat: Double?) -> (saat: Int, dakika: Int)? {
        guard let saat, saat > 0 else { return nil }
        let toplam = Int((saat * 60).rounded())
        return (toplam / 60, toplam % 60)
    }

    /// Haftalık çiçeğin açıklığı: hedefin %45'ine kadar kapalı tohum (0), hedefte tam açık (1).
    nonisolated static func cicekAcikligi(deger: Double, hedef: Double) -> Double {
        guard hedef > 0 else { return 0 }
        let oran = min(1, max(0, deger / hedef))
        return min(1, max(0, (oran - 0.45) / 0.55))
    }
}

// MARK: - Mürekkep gölgesi

extension View {
    /// Kâğıda yapıştırılmış kesik kâğıt hissi veren iki katlı gölge.
    func murekkepGolgesi(hafif: Bool = false) -> some View {
        shadow(color: OzetRenk.golge.opacity(hafif ? 0.38 : 0.42), radius: hafif ? 0.6 : 0.9, x: hafif ? 1 : 1.5, y: hafif ? 2 : 2.5)
            .shadow(color: OzetRenk.golge.opacity(hafif ? 0.36 : 0.46), radius: hafif ? 3.5 : 5, x: hafif ? 3 : 5, y: hafif ? 6 : 10)
    }
}

// MARK: - Fırça halkası (enso)

/// Fırçayla tek hareketle çekilmiş halka; kalınlığı fırça açısına ve basınca göre değişir.
struct FircaHalka: Shape {
    var ilerleme: Double
    var tohum: Double

    var animatableData: Double {
        get { ilerleme }
        set { ilerleme = newValue }
    }

    private static func gurultu(_ t: Double, _ s: Double) -> Double {
        0.55 * sin(t * 7.3 + s) + 0.3 * sin(t * 17.1 + s * 2.3) + 0.15 * sin(t * 41 + s * 5)
    }

    func path(in rect: CGRect) -> Path {
        let p = min(1, max(0, ilerleme))
        guard p > 0.005 else { return Path() }
        let merkez = CGPoint(x: rect.midX, y: rect.midY)
        let olcek = min(rect.width, rect.height) / 80
        let r = 36 * olcek
        let n = max(Int(140 * p), 6)
        let uc = 28.0 * .pi / 180
        var sol: [CGPoint] = []
        var sag: [CGPoint] = []
        for i in 0...n {
            let t = Double(i) / Double(n)
            let a = -Double.pi / 2 + 2 * .pi * p * t
            let x = merkez.x + r * cos(a)
            let y = merkez.y + r * sin(a)
            var w = 1.2 + (8.5 - 1.2) * pow(abs(sin(a + .pi / 2 - uc)), 1.4)
            w *= 1 + 0.16 * Self.gurultu(t, tohum)
            w *= min(1, t / 0.06 + 0.15) * min(1, (1 - t) / 0.22 + 0.2)
            w *= Double(olcek)
            sol.append(CGPoint(x: x + cos(a) * w / 2, y: y + sin(a) * w / 2))
            sag.append(CGPoint(x: x - cos(a) * w / 2, y: y - sin(a) * w / 2))
        }
        var yol = Path()
        yol.move(to: sol[0])
        sol.dropFirst().forEach { yol.addLine(to: $0) }
        sag.reversed().forEach { yol.addLine(to: $0) }
        yol.closeSubpath()
        return yol
    }
}

// MARK: - Bulutlu hilal (Uyku)

/// Bulutlara yaslanmış hilal. Çizim 162×184 tasarım biriminde, `olcek` ile küçültülür.
struct BulutluHilal: View {
    var body: some View {
        Canvas { ctx, _ in
            let s = 0.588
            ctx.translateBy(x: -0.17, y: -4.1)
            ctx.scaleBy(x: s, y: s)
            let ay = Path(ellipseIn: CGRect(x: 2, y: 18, width: 156, height: 156))
            let golgeDaire = Path(ellipseIn: CGRect(x: 62, y: 6, width: 124, height: 124))
            ctx.drawLayer { katman in
                katman.clip(to: ay)
                katman.clip(to: golgeDaire, options: .inverse)
                katman.fill(Path(ellipseIn: CGRect(x: 4, y: 20, width: 152, height: 152)), with: .color(Color(hex: "#DDCFB8")))
                katman.stroke(ay, with: .color(Color(hex: "#6E5A80")), lineWidth: 0.9)
            }
            ctx.drawLayer { bulut in
                bulut.addFilter(.blur(radius: 1.2))
                bulut.opacity = 0.92
                bulut.fill(Path(ellipseIn: CGRect(x: 90, y: 148, width: 60, height: 20)), with: .color(Color(hex: "#F4EDE0")))
                bulut.fill(Path(ellipseIn: CGRect(x: 122, y: 139, width: 36, height: 22)), with: .color(Color(hex: "#F7F1E6")))
                bulut.fill(Path(ellipseIn: CGRect(x: 90, y: 144, width: 28, height: 16)), with: .color(Color(hex: "#EFE6D6")))
                bulut.fill(Path(ellipseIn: CGRect(x: 136, y: 161, width: 28, height: 10)), with: .color(Color(hex: "#EFE6D6")))
            }
            var cizgi = Path()
            cizgi.move(to: CGPoint(x: 92, y: 162))
            cizgi.addQuadCurve(to: CGPoint(x: 126, y: 164), control: CGPoint(x: 106, y: 168))
            cizgi.addQuadCurve(to: CGPoint(x: 156, y: 154), control: CGPoint(x: 144, y: 162))
            ctx.stroke(cizgi, with: .color(Color(hex: "#9C8A78")), lineWidth: 0.6)
        }
        .frame(width: 136, height: 155)
        .accessibilityHidden(true)
    }
}

// MARK: - Süzülen tüy (Kilo)

/// Alttan gelen rüzgârla süzülen tüy. 162×184 tasarım biriminde, 0,84 ile küçültülür.
struct SuzulenTuy: View {
    @Environment(\.accessibilityReduceMotion) private var hareketiAzalt

    private static let tuy: (sap: Path, kil: Path) = {
        let x0 = 62.0, y0 = 86.0, cx = 96.0, cy = 56.0, x1 = 152.0, y1 = 40.0, w = 20.0
        let n = 34
        func nokta(_ t: Double) -> CGPoint {
            CGPoint(x: (1 - t) * (1 - t) * x0 + 2 * (1 - t) * t * cx + t * t * x1,
                    y: (1 - t) * (1 - t) * y0 + 2 * (1 - t) * t * cy + t * t * y1)
        }
        func yon(_ t: Double) -> CGPoint {
            let dx = 2 * (1 - t) * (cx - x0) + 2 * t * (x1 - cx)
            let dy = 2 * (1 - t) * (cy - y0) + 2 * t * (y1 - cy)
            let l = hypot(dx, dy)
            return CGPoint(x: dx / l, y: dy / l)
        }
        var kil = Path()
        for i in 2..<n {
            let t = Double(i) / Double(n)
            let p = nokta(t), d = yon(t)
            let nrm = CGPoint(x: -d.y, y: d.x)
            let profil = pow(sin(.pi * min(1, t * 1.15)), 0.6) * (t > 0.92 ? (1 - t) * 10 : 1)
            let yarik = (i == Int((Double(n) * 0.55).rounded()) || i == Int((Double(n) * 0.7).rounded())) ? 0.75 : 1
            for s in [1.0, -1.0] {
                let L = w * profil * (s > 0 ? 1 : 0.8) * yarik
                let uc = CGPoint(x: p.x + nrm.x * L * s + d.x * L * 0.5, y: p.y + nrm.y * L * s + d.y * L * 0.5)
                let orta = CGPoint(x: p.x + nrm.x * L * s * 0.5 + d.x * L * 0.1, y: p.y + nrm.y * L * s * 0.5 + d.y * L * 0.1)
                kil.move(to: p)
                kil.addQuadCurve(to: uc, control: orta)
            }
        }
        for i in 0..<5 {
            let t = 0.04 + Double(i) * 0.025
            let p = nokta(t), k = Double(i)
            kil.move(to: p)
            kil.addQuadCurve(to: CGPoint(x: p.x + 9 + k * 2, y: p.y + 3 - k), control: CGPoint(x: p.x + 6 + k, y: p.y - 2 - k))
            kil.move(to: p)
            kil.addQuadCurve(to: CGPoint(x: p.x - 8 - k * 2, y: p.y - 2 - k), control: CGPoint(x: p.x - 5 - k, y: p.y + 1 + k))
        }
        var sap = Path()
        sap.move(to: CGPoint(x: x0, y: y0))
        sap.addQuadCurve(to: CGPoint(x: x1, y: y1), control: CGPoint(x: cx, y: cy))
        return (sap, kil)
    }()

    private static let ruzgar: [Path] = {
        let veri: [[CGPoint]] = [
            [CGPoint(x: 40, y: 182), CGPoint(x: 34, y: 160), CGPoint(x: 52, y: 146), CGPoint(x: 48, y: 126),
             CGPoint(x: 46, y: 112), CGPoint(x: 58, y: 104), CGPoint(x: 66, y: 98)],
            [CGPoint(x: 78, y: 186), CGPoint(x: 70, y: 166), CGPoint(x: 88, y: 150), CGPoint(x: 82, y: 132),
             CGPoint(x: 78, y: 118), CGPoint(x: 92, y: 108), CGPoint(x: 100, y: 96)],
            [CGPoint(x: 112, y: 184), CGPoint(x: 108, y: 168), CGPoint(x: 120, y: 156), CGPoint(x: 116, y: 140),
             CGPoint(x: 114, y: 128), CGPoint(x: 124, y: 118), CGPoint(x: 130, y: 110)]
        ]
        return veri.map { p in
            var yol = Path()
            yol.move(to: p[0])
            yol.addCurve(to: p[3], control1: p[1], control2: p[2])
            yol.addCurve(to: p[6], control1: p[4], control2: p[5])
            return yol
        }
    }()

    private static let iz: Path = {
        var yol = Path()
        yol.move(to: CGPoint(x: 18, y: 96))
        yol.addCurve(to: CGPoint(x: 84, y: 70), control1: CGPoint(x: 40, y: 70), control2: CGPoint(x: 60, y: 92))
        yol.addCurve(to: CGPoint(x: 132, y: 44), control1: CGPoint(x: 108, y: 48), control2: CGPoint(x: 120, y: 52))
        return yol
    }()

    /// Tüyün 7 sn'lik süzülme döngüsü: (x, y, açı).
    private static func suzulme(_ zaman: Double) -> (Double, Double, Double) {
        let anahtarlar: [(Double, Double, Double)] = [(0, 0, 0), (5, 5, 6), (10, 2, -3), (4, -4, -7), (0, 0, 0)]
        let u = zaman.truncatingRemainder(dividingBy: 7) / 7 * 4
        let i = min(3, Int(u))
        let f = u - Double(i)
        let e = f * f * (3 - 2 * f)
        let a = anahtarlar[i], b = anahtarlar[i + 1]
        return (a.0 + (b.0 - a.0) * e, a.1 + (b.1 - a.1) * e, a.2 + (b.2 - a.2) * e)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: hareketiAzalt)) { zaman in
            let t = zaman.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                ctx.scaleBy(x: 0.84, y: 0.84)
                ctx.stroke(Self.iz, with: .color(Color(hex: "#A89A88").opacity(0.7)),
                           style: StrokeStyle(lineWidth: 0.7, lineCap: .round, dash: [1, 5]))
                if !hareketiAzalt {
                    for (i, yol) in Self.ruzgar.enumerated() {
                        let u = ((t + Double(i) * 1.1).truncatingRemainder(dividingBy: 3.2)) / 3.2
                        let opak = u < 0.2 ? u / 0.2 * 0.9 : (u < 0.8 ? 0.9 - (u - 0.2) / 0.6 * 0.3 : 0.6 * (1 - u) / 0.2)
                        let bas = min(1, u * 1.22), son = max(0, u * 1.22 - 0.22)
                        ctx.stroke(yol.trimmedPath(from: son, to: bas),
                                   with: .color(Color(hex: "#B3A592").opacity(opak)),
                                   style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                    }
                }
                let (dx, dy, aci) = hareketiAzalt ? (0, 0, 0) : Self.suzulme(t)
                ctx.drawLayer { tuy in
                    tuy.translateBy(x: 80 + dx, y: 70 + dy)
                    tuy.rotate(by: .degrees(aci))
                    tuy.translateBy(x: -80, y: -70)
                    tuy.stroke(Self.tuy.kil, with: .color(Color(hex: "#9A8C7C")), lineWidth: 0.55)
                    tuy.stroke(Self.tuy.sap, with: .color(Color(hex: "#6E5A48")), lineWidth: 1.1)
                }
            }
        }
        .frame(width: 136, height: 155)
        .accessibilityHidden(true)
    }
}

// MARK: - Modül simgeleri

/// İnce çizgili, kendi sınırına göre ölçeklenen modül simgesi.
struct ModulSimgesi: Shape {
    let route: AppRoute

    func path(in rect: CGRect) -> Path {
        let ham = Self.hamYol(route)
        let b = Self.sinir(route)
        guard b.width > 0, b.height > 0 else { return ham }
        let s = min(rect.width / b.width, rect.height / b.height)
        let t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -b.midX, y: -b.midY)
        return ham.applying(t)
    }

    private static func yay(_ yol: inout Path, merkez: CGPoint, r: CGFloat, ry: CGFloat? = nil, bas: Double, son: Double, yeni: Bool = true) {
        let adim = 48
        for i in 0...adim {
            let a = (bas + (son - bas) * Double(i) / Double(adim)) * .pi / 180
            let p = CGPoint(x: merkez.x + r * cos(a), y: merkez.y + (ry ?? r) * sin(a))
            if i == 0 && yeni { yol.move(to: p) } else { yol.addLine(to: p) }
        }
    }

    static func hamYol(_ route: AppRoute) -> Path {
        var y = Path()
        switch route {
        case .steps:
            y.move(to: CGPoint(x: -6, y: -2))
            y.addCurve(to: CGPoint(x: -3, y: -16), control1: CGPoint(x: -9, y: -10), control2: CGPoint(x: -7, y: -16))
            y.addCurve(to: CGPoint(x: -1, y: -2), control1: CGPoint(x: 1, y: -16), control2: CGPoint(x: 1, y: -9))
            y.closeSubpath()
            y.addEllipse(in: CGRect(x: -6, y: 1, width: 4, height: 6))
            y.move(to: CGPoint(x: 5, y: 6))
            y.addCurve(to: CGPoint(x: 8, y: -8), control1: CGPoint(x: 2, y: -2), control2: CGPoint(x: 4, y: -8))
            y.addCurve(to: CGPoint(x: 10, y: 6), control1: CGPoint(x: 12, y: -8), control2: CGPoint(x: 12, y: -1))
            y.closeSubpath()
            y.addEllipse(in: CGRect(x: 5, y: 9, width: 4, height: 6))
        case .sleep:
            yay(&y, merkez: .zero, r: 13, bas: -77, son: -343)
            yay(&y, merkez: CGPoint(x: 9.43, y: -5.34), r: 10, bas: 69, son: 220, yeni: false)
            y.closeSubpath()
        case .weight:
            y.addRoundedRect(in: CGRect(x: -12, y: -11, width: 24, height: 23), cornerSize: CGSize(width: 5, height: 5))
            yay(&y, merkez: CGPoint(x: 0, y: 0.6), r: 7, bas: 211, son: 329)
            y.move(to: CGPoint(x: 0, y: -3))
            y.addLine(to: CGPoint(x: 2.5, y: -7.5))
        case .biologicalWaste:
            y.move(to: CGPoint(x: 9, y: 30))
            y.addLine(to: CGPoint(x: 13, y: 44))
            y.addLine(to: CGPoint(x: 43, y: 44))
            y.addLine(to: CGPoint(x: 47, y: 30))
            y.move(to: CGPoint(x: 7, y: 30))
            y.addLine(to: CGPoint(x: 49, y: 30))
            yay(&y, merkez: CGPoint(x: 28, y: 30), r: 10, ry: 11, bas: 180, son: 360)
            y.move(to: CGPoint(x: 19.4, y: 25))
            y.addLine(to: CGPoint(x: 19, y: 16))
            y.addLine(to: CGPoint(x: 24, y: 20.5))
            y.move(to: CGPoint(x: 36.6, y: 25))
            y.addLine(to: CGPoint(x: 37, y: 16))
            y.addLine(to: CGPoint(x: 32, y: 20.5))
            yay(&y, merkez: CGPoint(x: 23.5, y: 25.5), r: 1.8, ry: 1.2, bas: 0, son: 180)
            yay(&y, merkez: CGPoint(x: 32.5, y: 25.5), r: 1.8, ry: 1.2, bas: 0, son: 180)
        case .statistics:
            y.move(to: CGPoint(x: -12, y: -12))
            y.addLine(to: CGPoint(x: -12, y: 11))
            y.addLine(to: CGPoint(x: 13, y: 11))
            y.move(to: CGPoint(x: -8, y: 6))
            y.addLine(to: CGPoint(x: -3, y: -1))
            y.addLine(to: CGPoint(x: 2, y: 2))
            y.addLine(to: CGPoint(x: 10, y: -8))
        case .water:
            y.move(to: CGPoint(x: 0, y: -12))
            y.addCurve(to: CGPoint(x: 0, y: 12), control1: CGPoint(x: 10, y: 0), control2: CGPoint(x: 9, y: 12))
            y.addCurve(to: CGPoint(x: 0, y: -12), control1: CGPoint(x: -9, y: 12), control2: CGPoint(x: -10, y: 0))
        }
        return y
    }

    private static let kalpHam: Path = {
        var k = Path()
        k.move(to: CGPoint(x: 28, y: 12))
        k.addCurve(to: CGPoint(x: 25.4, y: 13.6), control1: CGPoint(x: 26.4, y: 10), control2: CGPoint(x: 23.6, y: 11.4))
        k.addLine(to: CGPoint(x: 28, y: 16.2))
        k.addLine(to: CGPoint(x: 30.6, y: 13.6))
        k.addCurve(to: CGPoint(x: 28, y: 12), control1: CGPoint(x: 32.4, y: 11.4), control2: CGPoint(x: 29.6, y: 10))
        k.closeSubpath()
        return k
    }()

    /// Simgenin ölçeklendiği sınır; kum kabında başın üstündeki kalbi de kapsar.
    static func sinir(_ route: AppRoute) -> CGRect {
        let b = hamYol(route).boundingRect
        return route == .biologicalWaste ? b.union(kalpHam.boundingRect) : b
    }

    /// Kum kabındaki kedinin başındaki küçük kalp (simgeyle aynı ölçekte).
    static func kalp(in rect: CGRect) -> Path {
        let b = sinir(.biologicalWaste)
        let s = min(rect.width / b.width, rect.height / b.height)
        let t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -b.midX, y: -b.midY)
        return kalpHam.applying(t)
    }
}

extension AppRoute {
    /// Özet'in modül şeridindeki kısa ad.
    var ozetAdi: String {
        switch self {
        case .biologicalWaste: return "Kaka"
        case .statistics: return "İstatik"
        default: return title
        }
    }

    /// Özet'in modül şeridindeki çizgi rengi.
    var ozetRengi: Color {
        switch self {
        case .steps: return Color(hex: "#A23A2E")
        case .sleep: return Color(hex: "#6E5A80")
        case .weight: return Color(hex: "#4E6A4A")
        case .biologicalWaste: return Color(hex: "#8E6A32")
        case .statistics: return Color(hex: "#8E6E2E")
        case .water: return Color(hex: "#5F8796")
        }
    }
}

/// Özet'teki modül şeridinin tek öğesi.
struct OzetModulOgesi: View {
    let route: AppRoute

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ModulSimgesi(route: route)
                    .stroke(route.ozetRengi, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                if route == .biologicalWaste {
                    GeometryReader { geo in
                        ModulSimgesi.kalp(in: CGRect(origin: .zero, size: geo.size))
                            .fill(Color(hex: "#D98A86"))
                    }
                }
            }
            .frame(width: 40, height: 31)
            .padding(.vertical, 9)
            .murekkepGolgesi(hafif: true)

            Text(route.ozetAdi)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.ftText)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 70)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(route.title)
        .accessibilityAddTraits(.isButton)
    }
}
