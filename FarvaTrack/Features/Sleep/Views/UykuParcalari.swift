import SwiftUI

// Uyku ekranının çizimleri: gerçek ay haritalı 3B ay, gece şeritleri ve 24 saatlik kadran.

enum UykuRenk {
    static let koyu = Color(hex: "#6E5A80")
    static let acik = Color(hex: "#9C8AB0")
    static let gunes = Color(hex: "#B98D45")
    static let gunesIc = Color(hex: "#E8C88A")
    static let tutac = Color(hex: "#F3E8D0")
}

// MARK: - Biçim

enum UykuBicim {
    /// "7 sa 20 dk", "45 dk", "8 sa".
    static func sure(_ dakika: Int) -> String {
        let h = dakika / 60, d = dakika % 60
        if h == 0 { return "\(d) dk" }
        return d == 0 ? "\(h) sa" : "\(h) sa \(d) dk"
    }

    static func saat(_ dakika: Int) -> String {
        let m = ((dakika % 1_440) + 1_440) % 1_440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Saatten sonra gelen bulunma eki: "23:15’te", "07:30’da", "22:00’de".
    static func saatEki(_ dakika: Int) -> String {
        let m = ((dakika % 1_440) + 1_440) % 1_440
        let sayi = m % 60 == 0 ? m / 60 : m % 60
        let birler = ["da", "de", "de", "te", "te", "te", "da", "de", "de", "da"]
        let onlar = [0: "da", 1: "da", 2: "de", 3: "da", 4: "ta", 5: "de"]
        let ek = sayi % 10 != 0 ? birler[sayi % 10] : (onlar[sayi / 10] ?? "da")
        return "\(saat(dakika))’\(ek)"
    }
}

// MARK: - 3B ay

/// Gerçek ay haritası (Metal gölgelendirici). Uyku hedefe yaklaştıkça önünden geçen yuvarlak çekilir;
/// hedefin yarısı ve altında yalnız sol altta ince bir hilal kalır. Parmakla çevrilebilir.
struct UykuAyi: View {
    /// Günün toplam uykusu / hedef.
    let oran: Double
    var boy: CGFloat = 200

    @Environment(\.accessibilityReduceMotion) private var hareketiAzalt
    @State private var baslangic = Date.now
    @State private var eskiKap: Double = 2.2
    @State private var yeniKap: Double = 2.2
    @State private var degisim = Date.distantPast
    @State private var surukleme: Double = 0
    @State private var surukleBas: Double?
    @State private var birakilan: Double = 0
    @State private var birakma = Date.distantPast

    static func kap(_ oran: Double) -> Double {
        let f = max(0, min(1, (oran - 0.5) / 0.5))
        return 0.25 + (2.2 - 0.25) * pow(f, 0.85)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: hareketiAzalt && surukleBas == nil)) { zaman in
            let simdi = zaman.date
            let t = simdi.timeIntervalSince(baslangic)
            let u = min(1, simdi.timeIntervalSince(degisim) / 0.9)
            let e = 1 - pow(1 - u, 3)
            let kap = eskiKap + (yeniKap - eskiKap) * e
            let el = surukleBas != nil ? surukleme : birakilan * pow(0.94, simdi.timeIntervalSince(birakma) / 0.04)
            let salinim = hareketiAzalt ? 0 : sin(t * 0.23) * 0.09
            let egim = 0.05 + (hareketiAzalt ? 0 : sin(t * 0.17) * 0.06)
            Rectangle()
                .fill(.white)
                .frame(width: boy, height: boy)
                .colorEffect(ShaderLibrary.ayYuzeyi(.float2(boy, boy), .float(el + salinim), .float(egim), .float(kap),
                                                    .image(Image("AyDokusu"))))
        }
        .frame(width: boy, height: boy)
        .shadow(color: OzetRenk.golge.opacity(0.42), radius: 1.5, x: 1.5, y: 2.5)
        .shadow(color: OzetRenk.golge.opacity(0.46), radius: 9, x: 5, y: 10)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { d in
                    if surukleBas == nil { surukleBas = birakilan * pow(0.94, Date.now.timeIntervalSince(birakma) / 0.04) }
                    surukleme = (surukleBas ?? 0) - d.translation.width * 0.012
                }
                .onEnded { _ in
                    birakilan = surukleme
                    birakma = .now
                    surukleBas = nil
                }
        )
        .onAppear {
            let k = Self.kap(oran)
            eskiKap = k
            yeniKap = k
        }
        .onChange(of: oran) { _, yeni in
            eskiKap = yeniKap
            yeniKap = Self.kap(yeni)
            degisim = .now
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Yıldızlar

struct YildizSekli: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.025), r = min(rect.width, rect.height) / 2
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * .pi / 5
            let rr = i % 2 == 1 ? r * 0.45 : r
            let n = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
            if i == 0 { p.move(to: n) } else { p.addLine(to: n) }
        }
        p.closeSubpath()
        return p
    }
}

struct UykuYildizlari: View {
    let deger: Int
    var boy: CGFloat = 18
    var degistir: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                Button { degistir?(i) } label: {
                    ZStack {
                        YildizSekli().fill(i <= deger ? UykuRenk.acik.opacity(0.85) : .clear)
                        YildizSekli().stroke(UykuRenk.koyu, lineWidth: 0.9)
                    }
                    .frame(width: boy, height: boy)
                    .frame(width: boy + 14, height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(degistir == nil)
                .accessibilityLabel("\(i) yıldız")
                .accessibilityAddTraits(i == deger ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: degistir == nil ? .ignore : .contain)
        .accessibilityLabel(degistir == nil ? "Kalite \(deger) / 5" : "Uyku kalitesi")
    }
}

// MARK: - Gece şeritleri

/// Her gün bir satır: yatıştan uyanışa fırça şerit (18:00 → ertesi 18:00), şekerlemeler aynı satırda.
struct GeceSeritleri: View {
    struct Satir: Identifiable {
        let id: Date
        let ad: String
        /// [yatış, uyanış] dakika; 18:00 = 1080'den başlayan eksende (gün sonrası +1440).
        let uykular: [(Int, Int, Bool)]
    }
    let satirlar: [Satir]
    let secili: Date
    var ortYatis: Int?
    var ortUyanis: Int?
    let sec: (Date) -> Void

    private let t0 = 18.0 * 60, t1 = 42.0 * 60

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 350
            let x: (Double) -> CGFloat = { m in (40 + (m - t0) / (t1 - t0) * 306) * k }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for h in stride(from: 18, through: 42, by: 4) {
                        ctx.draw(Text(String(format: "%02d", h % 24)).font(.system(size: 9.5)).foregroundStyle(KlasikRenk.ikincil),
                                 at: CGPoint(x: x(Double(h * 60)), y: 5), anchor: .center)
                    }
                    for m in [ortYatis, ortUyanis].compactMap({ $0 }) {
                        var p = Path()
                        p.move(to: CGPoint(x: x(Double(m)), y: 16))
                        p.addLine(to: CGPoint(x: x(Double(m)), y: 140))
                        ctx.stroke(p, with: .color(KlasikRenk.hedefCizgisi), style: StrokeStyle(lineWidth: 0.7, lineCap: .round, dash: [1, 4]))
                    }
                    var golgeli = ctx
                    golgeli.addFilter(.shadow(color: OzetRenk.golge.opacity(0.36), radius: 3, x: 2, y: 5))
                    for (i, s) in satirlar.enumerated() {
                        let y = 24 + CGFloat(i) * 17
                        let sec = s.id == secili
                        for (j, u) in s.uykular.enumerated() {
                            let a = Double(u.0), b = Double(u.1)
                            let yol = Firca.duz(CGPoint(x: x(a), y: y), CGPoint(x: max(x(b), x(a) + 3), y: y),
                                                Firca.Ayar(w: (sec ? 8 : 6.5) * (u.2 ? 0.88 : 1), tohum: 70 + i * 3 + j, giris: u.2 ? 0.1 : 0.05, cikis: u.2 ? 0.1 : 0.08, basinc: 0.2))
                            golgeli.fill(yol, with: .color((sec ? UykuRenk.koyu : UykuRenk.acik).opacity(sec ? (u.2 ? 0.8 : 0.95) : (u.2 ? 0.45 : 0.6))))
                        }
                    }
                }
                ForEach(Array(satirlar.enumerated()), id: \.element.id) { i, s in
                    let secMi = s.id == secili
                    Button { sec(s.id) } label: {
                        HStack {
                            Text(s.ad)
                                .font(.system(size: 10.5, weight: secMi ? .bold : .regular))
                                .foregroundStyle(secMi ? KlasikRenk.vurgu : Color(hex: "#6E523C"))
                            Spacer()
                        }
                        .frame(width: geo.size.width, height: 17)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(y: 15.5 + CGFloat(i) * 17)
                    .accessibilityLabel("\(s.ad) gecesini göster")
                    .accessibilityAddTraits(secMi ? [.isSelected] : [])
                }
            }
        }
        .frame(height: 150)
    }
}

// MARK: - 24 saatlik kadran

/// Yatış (ay) ve uyanış (güneş) tutaçları sürüklenerek ayarlanır; aynı günün diğer uykuları soluk görünür.
struct UykuKadrani: View {
    @Binding var yatis: Int
    @Binding var uyanis: Int
    var digerleri: [(Int, Int)] = []
    var boy: CGFloat = 290

    private func nokta(_ c: CGFloat, _ r: CGFloat, _ m: Int) -> CGPoint {
        let a = (Double(m) / 1_440 * 360 - 90) * .pi / 180
        return CGPoint(x: c + CGFloat(cos(a)) * r, y: c + CGFloat(sin(a)) * r)
    }

    private func yay(_ c: CGFloat, _ r: CGFloat, _ m1: Int, _ m2: Int, w: Double, tohum: Int) -> Path {
        let a1 = Double(m1) / 1_440 * 360
        let sp = Double(((m2 - m1) % 1_440 + 1_440) % 1_440) / 1_440 * 360
        let n = max(20, Int(sp))
        let pts = (0...n).map { i -> CGPoint in
            let a = (a1 + sp * Double(i) / Double(n) - 90) * .pi / 180
            return CGPoint(x: c + CGFloat(cos(a)) * r, y: c + CGFloat(sin(a)) * r)
        }
        return Firca.cizgi(pts, Firca.Ayar(w: w, tohum: tohum, giris: 0.06, cikis: 0.12, basinc: 0.22))
    }

    var body: some View {
        let c = boy / 2, R = boy / 2 - 22
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                ctx.stroke(Path(ellipseIn: CGRect(x: c - R, y: c - R, width: 2 * R, height: 2 * R)), with: .color(KlasikRenk.soluk.opacity(0.3)), lineWidth: 0.5)
                for h in 0..<24 {
                    var p = Path()
                    p.move(to: nokta(c, R - 12, h * 60))
                    p.addLine(to: nokta(c, R - (h % 6 == 0 ? 4 : 8), h * 60))
                    ctx.stroke(p, with: .color(KlasikRenk.ikincil.opacity(0.7)), lineWidth: h % 6 == 0 ? 1 : 0.6)
                }
                for h in [0, 6, 12, 18] {
                    let q = nokta(c, R - 22, h * 60)
                    ctx.draw(Text(String(format: "%02d", h)).font(.system(size: 10)).foregroundStyle(KlasikRenk.ikincil), at: q)
                }
                for (k, d) in digerleri.enumerated() {
                    ctx.fill(yay(c, R, d.0, d.1, w: 5, tohum: 30 + k), with: .color(UykuRenk.acik.opacity(0.32)))
                }
                var g = ctx
                g.addFilter(.shadow(color: OzetRenk.golge.opacity(0.36), radius: 3, x: 2, y: 5))
                g.fill(yay(c, R, yatis, uyanis, w: 7, tohum: 5), with: .color(UykuRenk.acik.opacity(0.9)))
            }
            .frame(width: boy, height: boy)

            VStack(spacing: 4) {
                let d = ((uyanis - yatis) % 1_440 + 1_440) % 1_440
                (Text("\(d / 60)").font(.system(size: 40, weight: .bold)) + Text(" sa ").font(.system(size: 17))
                 + Text("\(d % 60)").font(.system(size: 40, weight: .bold)) + Text(" dk").font(.system(size: 17)))
                    .foregroundStyle(Color.ftText)
                    .monospacedDigit()
                Text("\(UykuBicim.saat(yatis)) – \(UykuBicim.saat(uyanis))")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ftTextSecondary)
            }
            .frame(width: boy, height: boy)
            .allowsHitTesting(false)

            tutac(ay: true, m: yatis, c: c, R: R)
            tutac(ay: false, m: uyanis, c: c, R: R)
        }
        .frame(width: boy, height: boy)
        .coordinateSpace(name: "kadran")
    }

    private func tutac(ay: Bool, m: Int, c: CGFloat, R: CGFloat) -> some View {
        let p = nokta(c, R, m)
        return ZStack {
            Circle().fill(UykuRenk.tutac)
            Circle().stroke(ay ? UykuRenk.koyu : UykuRenk.gunes, lineWidth: 0.8)
            if ay {
                Image(systemName: "moon.fill").font(.system(size: 11)).foregroundStyle(UykuRenk.koyu)
            } else {
                Image(systemName: "sun.max").font(.system(size: 12)).foregroundStyle(UykuRenk.gunes)
            }
        }
        .frame(width: 26, height: 26)
        .murekkepGolgesi(hafif: true)
        .frame(width: 48, height: 48)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("kadran"))
                .onChanged { d in
                    var a = atan2(d.location.y - c, d.location.x - c) * 180 / .pi + 90
                    if a < 0 { a += 360 }
                    let dakika = (Int((a / 360 * 1_440 / 5).rounded()) * 5) % 1_440
                    if ay {
                        if dakika != yatis { Haptics.selection() }
                        yatis = dakika
                    } else {
                        if dakika != uyanis { Haptics.selection() }
                        uyanis = dakika
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel(ay ? "Yatış" : "Uyanış")
        .accessibilityValue(UykuBicim.saat(m))
        .accessibilityAdjustableAction { yon in
            let adim = yon == .increment ? 5 : -5
            if ay { yatis = (yatis + adim + 1_440) % 1_440 } else { uyanis = (uyanis + adim + 1_440) % 1_440 }
        }
        .position(p)
    }
}
