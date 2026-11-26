import SwiftUI

/// "Bu Hafta · Adım" grafiği: her gün bir örümcek zambağı. Hedefin %45'ine kadar kapalı tohum,
/// sonra hedefe yaklaştıkça kademeli açılır. Çizim 340×220 tasarım biriminde, genişliğe ölçeklenir.
struct BuyuyenCicekler: View {
    let gunler: [DailyValue]
    let hedef: Double

    @Environment(\.accessibilityReduceMotion) private var hareketiAzalt

    private static let gunAdlari: [Int: String] = [1: "Paz", 2: "Pzt", 3: "Sal", 4: "Çar", 5: "Per", 6: "Cum", 7: "Cmt"]
    private let taban = 175.0

    private var olcek: Double {
        let enBuyuk = gunler.map(\.value).max() ?? 0
        return 112 / max(hedef * 1.25, enBuyuk, 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: hareketiAzalt)) { zaman in
            let t = zaman.date.timeIntervalSinceReferenceDate
            Canvas { ctx, boyut in
                let k = boyut.width / 340
                ctx.scaleBy(x: k, y: k)
                ciz(&ctx, zaman: hareketiAzalt ? 0 : t)
            }
        }
        .aspectRatio(340 / 220, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(erisimMetni)
    }

    private var erisimMetni: String {
        let ulasilan = gunler.filter { $0.value >= hedef && hedef > 0 }.count
        return "Bu hafta adım grafiği. Yedi günün \(ulasilan) gününde hedefe ulaşıldı; hedefe ulaşılan günlerde çiçek tam açmış."
    }

    private func ciz(_ ctx: inout GraphicsContext, zaman: Double) {
        let sc = olcek
        let hedefY = taban - hedef * sc

        // Hedef çizgisi ve etiketi
        var hedefCizgi = Path()
        hedefCizgi.move(to: CGPoint(x: 24, y: hedefY))
        hedefCizgi.addLine(to: CGPoint(x: 300, y: hedefY))
        ctx.stroke(hedefCizgi, with: .color(Color(hex: "#B49870")),
                   style: StrokeStyle(lineWidth: 0.6, lineCap: .round, dash: [1, 4]))
        ctx.draw(Text(Int(hedef).formatted()).font(.system(size: 8.5)).foregroundStyle(Color(hex: "#8A6E52")),
                 at: CGPoint(x: 340, y: hedefY), anchor: .trailing)

        // Toprak, çiçekler (gölgeli katman)
        ctx.drawLayer { katman in
            katman.addFilter(.shadow(color: OzetRenk.golge.opacity(0.42), radius: 0.9, x: 1.5, y: 2.5))
            katman.addFilter(.shadow(color: OzetRenk.golge.opacity(0.46), radius: 5, x: 5, y: 10))
            var toprak = Path()
            toprak.move(to: CGPoint(x: 10, y: 176))
            toprak.addCurve(to: CGPoint(x: 170, y: 173), control1: CGPoint(x: 60, y: 170), control2: CGPoint(x: 110, y: 178))
            toprak.addCurve(to: CGPoint(x: 330, y: 172), control1: CGPoint(x: 230, y: 168), control2: CGPoint(x: 280, y: 177))
            toprak.addLine(to: CGPoint(x: 330, y: 186))
            toprak.addLine(to: CGPoint(x: 10, y: 186))
            toprak.closeSubpath()
            katman.drawLayer { t in
                t.addFilter(.blur(radius: 1))
                t.fill(toprak, with: .color(Color(hex: "#CDB88E")))
            }
            for (i, gun) in gunler.prefix(7).enumerated() {
                let cx = 44 + Double(i) * 252 / 6
                let aci = -1.4 + 1.5 * (1 + sin(2 * .pi * (zaman + Double(i) * 0.9) / 6 - .pi / 2))
                katman.drawLayer { c in
                    c.translateBy(x: cx, y: taban)
                    c.rotate(by: .degrees(aci))
                    c.translateBy(x: -cx, y: -taban)
                    cicek(&c, i: i, cx: cx, deger: gun.value, sc: sc)
                }
            }
        }

        // Çimen
        var cimen = Path()
        for x in stride(from: 14, to: 328, by: 6) {
            let y = 177 + Double(x % 4)
            cimen.move(to: CGPoint(x: Double(x), y: y))
            cimen.addQuadCurve(
                to: CGPoint(x: Double(x) + Double(x % 3 - 1), y: y - Double(4 + (x * 7) % 5)),
                control: CGPoint(x: Double(x) + (x % 2 == 1 ? 1.5 : -1.5), y: y - 3)
            )
        }
        ctx.stroke(cimen, with: .color(Color(hex: "#7C8B5E")), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))

        // Gün adları
        let takvim = Calendar(identifier: .gregorian)
        for (i, gun) in gunler.prefix(7).enumerated() {
            let cx = 44 + Double(i) * 252 / 6
            let bugun = takvim.isDateInToday(gun.date)
            let ad = Self.gunAdlari[takvim.component(.weekday, from: gun.date)] ?? ""
            ctx.draw(
                Text(ad)
                    .font(.system(size: 10, weight: bugun ? .bold : .regular))
                    .foregroundStyle(bugun ? OzetRenk.tumu : Color(hex: "#6E523C")),
                at: CGPoint(x: cx, y: 200)
            )
        }
    }

    private func cicek(_ c: inout GraphicsContext, i: Int, cx: Double, deger: Double, sc: Double) {
        let h = deger * sc
        let y = taban - h
        let sapma = i % 2 == 1 ? 3.0 : -3.0
        var sap = Path()
        sap.move(to: CGPoint(x: cx, y: taban))
        sap.addCurve(to: CGPoint(x: cx, y: y),
                     control1: CGPoint(x: cx + sapma, y: taban - h * 0.35),
                     control2: CGPoint(x: cx - sapma, y: taban - h * 0.7))
        var yaprak = Path()
        yaprak.move(to: CGPoint(x: cx - 1, y: taban))
        yaprak.addQuadCurve(to: CGPoint(x: cx - 11, y: taban - Double(14 + i % 3 * 3)), control: CGPoint(x: cx - 7, y: taban - 10))
        yaprak.move(to: CGPoint(x: cx + 1, y: taban))
        yaprak.addQuadCurve(to: CGPoint(x: cx + 12, y: taban - Double(12 + i % 2 * 4)), control: CGPoint(x: cx + 6, y: taban - 9))
        c.stroke(sap, with: .color(Color(hex: "#5E6E48")), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        c.stroke(yaprak, with: .color(Color(hex: "#7C8B5E")), style: StrokeStyle(lineWidth: 1, lineCap: .round))

        let acik = OzetBicim.cicekAcikligi(deger: deger, hedef: hedef)
        if acik > 0 {
            let yayilma = 7 + 27 * acik, boy = 8 + 7 * acik, kivrim = 4.5 * acik * acik, en = 1.6 + 1.4 * acik
            var tac = Path(), damar = Path()
            for k in 0..<7 {
                let a = (-90 + Double(k - 3) * yayilma) * .pi / 180
                let dx = cos(a), dy = sin(a), nx = -dy, ny = dx
                let uc = CGPoint(x: cx + dx * boy + nx, y: y + dy * boy + ny)
                let geri = CGPoint(x: uc.x - dx * (1 + 2 * acik) - nx * kivrim,
                                   y: uc.y - dy * (1 + 2 * acik) - ny * kivrim + 2.5 * acik)
                tac.move(to: CGPoint(x: cx, y: y))
                tac.addQuadCurve(to: uc, control: CGPoint(x: cx + dx * boy * 0.55 + nx * en, y: y + dy * boy * 0.55 + ny * en))
                tac.addQuadCurve(to: geri, control: CGPoint(x: uc.x + dx * 2.5 * acik - nx * 2.5 * acik,
                                                            y: uc.y + dy * 2.5 * acik - ny * 2.5 * acik))
                tac.addQuadCurve(to: CGPoint(x: cx, y: y), control: CGPoint(x: cx + dx * boy * 0.47 - nx * en * 0.55,
                                                                         y: y + dy * boy * 0.47 - ny * en * 0.55))
                tac.closeSubpath()
                damar.move(to: CGPoint(x: cx + dx * 2, y: y + dy * 2))
                damar.addQuadCurve(to: CGPoint(x: cx + dx * (boy - 2), y: y + dy * (boy - 2)),
                                   control: CGPoint(x: cx + dx * boy * 0.55 + nx * 1.2, y: y + dy * boy * 0.55 + ny * 1.2))
            }
            c.fill(tac, with: .color(Color(hex: "#A8322A")))
            if acik < 0.5 {
                var canak = Path()
                canak.move(to: CGPoint(x: cx, y: y + 2))
                for p in [(-3.5, -3.0), (-1.5, -2.0), (0, -4.5), (1.5, -2.0), (3.5, -3.0)] {
                    canak.addLine(to: CGPoint(x: cx + p.0, y: y + p.1))
                }
                canak.closeSubpath()
                c.fill(canak, with: .color(Color(hex: "#6E7E50")))
            }
            c.stroke(tac, with: .color(Color(hex: "#6E1E18")), lineWidth: 0.45)
            c.stroke(damar, with: .color(Color(hex: "#7E2620")), lineWidth: 0.4)

            let ercik = 27 * max(0, (acik - 0.45) / 0.55)
            if ercik > 2 {
                var telcik = Path(), bas = Path()
                for k in 0..<6 {
                    let a = (-90 + (Double(k) - 2.5) * (6 + 16 * acik)) * .pi / 180
                    let dx = cos(a), dy = sin(a), bukum = (k < 3 ? -5.0 : 5.0) * acik
                    let son = CGPoint(x: cx + dx * ercik + bukum * 0.6, y: y + dy * ercik - 2 * acik)
                    telcik.move(to: CGPoint(x: cx, y: y))
                    telcik.addQuadCurve(to: son, control: CGPoint(x: cx + dx * ercik * 0.55 + bukum, y: y + dy * ercik * 0.55))
                    if acik > 0.6 { bas.addEllipse(in: CGRect(x: son.x - 1.6, y: son.y - 0.9, width: 3.2, height: 1.8)) }
                }
                c.stroke(telcik, with: .color(Color(hex: "#B8403A")), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                c.fill(bas, with: .color(Color(hex: "#5E1A14")))
            }
        } else {
            var tohum = Path()
            tohum.move(to: CGPoint(x: cx, y: y - 9))
            tohum.addCurve(to: CGPoint(x: cx, y: y + 1), control1: CGPoint(x: cx + 3.6, y: y - 6), control2: CGPoint(x: cx + 3.4, y: y - 1))
            tohum.addCurve(to: CGPoint(x: cx, y: y - 9), control1: CGPoint(x: cx - 3.4, y: y - 1), control2: CGPoint(x: cx - 3.6, y: y - 6))
            tohum.closeSubpath()
            var cizgi = Path()
            cizgi.move(to: CGPoint(x: cx, y: y - 8))
            cizgi.addQuadCurve(to: CGPoint(x: cx, y: y), control: CGPoint(x: cx + 1, y: y - 4))
            c.fill(tohum, with: .color(Color(hex: "#7A7448")))
            c.stroke(tohum, with: .color(Color(hex: "#4E4A2E")), lineWidth: 0.5)
            c.stroke(cizgi, with: .color(Color(hex: "#5E5A36")), lineWidth: 0.5)
        }
    }
}
