import SwiftUI
import SwiftData

/// İstatistikler (klasik tasarım): Hafta / Ay; rozetler satırı; Program Uyumu ve her metrik aynı kalıpta:
/// başlık + önceki döneme göre değişim, aynı boyda fırça sütunlu gün grafiği, altında aynı düzende üç sayı.
struct StatisticsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = StatisticsViewModel()

    private var donem: Binding<StatsPeriod> {
        Binding(get: { viewModel.period == .year ? .month : viewModel.period }, set: { viewModel.setPeriod($0) })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                KlasikSekmeler(secenekler: [(StatsPeriod.week, "Hafta"), (.month, "Ay")], secili: donem)
                    .scaleEffect(1.12)
                    .padding(.top, 2)

                NavigationLink {
                    BadgesView(badges: viewModel.badges)
                } label: {
                    RozetSatiri(rozetler: viewModel.badges)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                FircaAyirici(tohum: 698).padding(.top, 4)

                let liste = bloklar()
                if liste.isEmpty && !viewModel.isLoading {
                    Text("Bu dönemde henüz veri yok.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ftTextSecondary)
                        .padding(.top, 40)
                }
                ForEach(Array(liste.enumerated()), id: \.offset) { i, blok in
                    if i > 0 { FircaAyirici(tohum: 700 + i).padding(.vertical, 20) } else { Color.clear.frame(height: 22) }
                    blok
                }
            }
            .padding(.horizontal, Constants.Layout.screenPadding)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            if let user = auth.currentUser { await viewModel.load(context: modelContext, user: user) }
        }
        .overlay {
            if viewModel.isLoading && viewModel.cards.isEmpty { ProgressView() }
        }
        .klasikEkran("İstatistikler")
        .task(id: auth.currentUser?.id) {
            if viewModel.period == .year { viewModel.setPeriod(.month) }
            if let user = auth.currentUser { await viewModel.load(context: modelContext, user: user) }
        }
    }

    private func bloklar() -> [AnyView] {
        var b: [AnyView] = []
        let gun = viewModel.period == .week ? 7 : 30
        if viewModel.programName != nil, !viewModel.programGunleri.isEmpty {
            b.append(AnyView(ProgramUyumBlogu(gunler: Array(viewModel.programGunleri.suffix(gun)), onceki: Array(viewModel.programGunleri.dropLast(gun).suffix(gun)),
                                              seri: AdherenceCalculator.completeWeekStreak(viewModel.adherence))))
        }
        for kart in viewModel.cards {
            b.append(AnyView(MetrikBlogu(kart: kart)))
        }
        return b
    }
}

// MARK: - Rozet satırı

private struct RozetSatiri: View {
    let rozetler: [BadgeStatus]

    var body: some View {
        let kazanilan = rozetler.filter(\.isEarned)
        HStack(spacing: 12) {
            HStack(spacing: -10) {
                ForEach(Array(kazanilan.prefix(5).enumerated()), id: \.offset) { i, r in
                    Image(systemName: r.badge.systemImage)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "#8E6E2E"))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color(hex: "#F3E3BE")))
                        .overlay(Circle().stroke(Color(hex: "#C9A961"), lineWidth: 1))
                        .murekkepGolgesi(hafif: true)
                        .zIndex(Double(10 - i))
                }
            }
            .padding(.leading, kazanilan.isEmpty ? 0 : 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rozetler").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.ftText)
                Text("\(kazanilan.count) / \(rozetler.count) kazanıldı").font(.system(size: 13)).foregroundStyle(Color.ftTextSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(KlasikRenk.soluk)
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rozetler, \(kazanilan.count) / \(rozetler.count) kazanıldı")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Ortak blok

/// Başlık satırı: fırça noktası + ad, sağda değişim.
private struct BlokBasligi: View {
    let ad: String
    let renk: Color
    var degisim: Double?
    var dususIyi = false

    var body: some View {
        HStack(spacing: 8) {
            FircaSutunSekli(tohum: 5).fill(renk.opacity(0.85)).frame(width: 10, height: 10)
            Text(ad).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ftText)
            Spacer()
            if let d = degisim, abs(d) >= 1 {
                let iyi = dususIyi ? d < 0 : d > 0
                Text("\(d > 0 ? "▲" : "▼") %\(abs(d) < 10 ? abs(d).formatted(.number.precision(.fractionLength(0...1))) : "\(Int(abs(d).rounded()))")")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(iyi ? KlasikRenk.yesil : KlasikRenk.vurgu)
                    .accessibilityLabel("Önceki döneme göre yüzde \(Int(abs(d).rounded())) \(d > 0 ? "artış" : "azalış")")
            }
        }
        .padding(.bottom, 10)
    }
}

/// Tek tip gün grafiği: aynı boy, aynı sütun genişliği, aynı eksen ve hedef çizgisi.
private struct GunSutunlari: View {
    enum Sutun { case bos, dolu(Double, tutan: Bool), plan(yapildi: Bool) }
    let gunler: [Date]
    let sutunlar: [Sutun]
    let renk: Color
    var hedef: Double?
    var taban: Double = 0
    var tavan: Double = 1

    var body: some View {
        Canvas { ctx, boyut in
            let W = boyut.width, H = boyut.height, alt: CGFloat = 16, ust: CGFloat = 6
            let n = max(sutunlar.count, 1)
            let w = W / CGFloat(n), bw: CGFloat = n <= 7 ? 18 : 6, zemin = H - alt
            let y: (Double) -> CGFloat = { ust + CGFloat(1 - ($0 - taban) / max(tavan - taban, 0.0001)) * (zemin - ust) }

            ctx.fill(Firca.duz(CGPoint(x: 0, y: zemin + 0.5), CGPoint(x: W, y: zemin + 0.5), Firca.Ayar(w: 0.7, tohum: 3)),
                     with: .color(KlasikRenk.soluk.opacity(0.35)))
            if let hedef {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y(hedef)))
                p.addLine(to: CGPoint(x: W, y: y(hedef)))
                ctx.stroke(p, with: .color(KlasikRenk.hedefCizgisi), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, dash: [1, 4]))
            }
            var g = ctx
            g.addFilter(.shadow(color: OzetRenk.golge.opacity(0.36), radius: 3, x: 2, y: 5))
            for (i, s) in sutunlar.enumerated() {
                let x = CGFloat(i) * w + w / 2 - bw / 2
                let son = i == n - 1
                switch s {
                case .bos:
                    ctx.fill(Path(ellipseIn: CGRect(x: x + bw / 2 - 1.3, y: zemin - 4.3, width: 2.6, height: 2.6)), with: .color(KlasikRenk.bosNokta))
                case .dolu(let v, let tutan):
                    let yy = min(y(v), zemin - 3)
                    g.fill(Firca.sutun(CGRect(x: x, y: yy, width: bw, height: zemin - yy), tohum: 200 + i),
                           with: .color(renk.opacity(son ? 0.92 : (tutan ? 0.62 : 0.32))))
                case .plan(let yapildi):
                    let r = CGRect(x: x, y: ust + 10, width: bw, height: zemin - ust - 10)
                    if yapildi {
                        g.fill(Firca.sutun(r, tohum: 500 + i), with: .color(renk.opacity(son ? 0.92 : 0.62)))
                    } else {
                        ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0), cornerRadius: bw / 2 - 0.5),
                                   with: .color(renk.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
            }
            // Eksen
            let t = Calendar.current
            for (i, d) in gunler.enumerated() {
                let son = i == gunler.count - 1
                let ad: String
                if gunler.count <= 7 {
                    ad = son ? "Bugün" : KlasikTarih.gunKisa(d)
                } else if son {
                    ad = "Bugün"
                } else if (gunler.count - 1 - i) % 7 == 0 {
                    ad = "\(t.component(.day, from: d)) \(KlasikTarih.ayKisa(d))"
                } else { continue }
                let metin = Text(ad).font(.system(size: 9.5, weight: son ? .bold : .regular)).foregroundStyle(son ? KlasikRenk.vurgu : KlasikRenk.eksen)
                let x = CGFloat(i) * w + w / 2
                if son && gunler.count > 7 {
                    ctx.draw(metin, at: CGPoint(x: x + w / 2, y: H - 6), anchor: .trailing)
                } else {
                    ctx.draw(metin, at: CGPoint(x: x, y: H - 6))
                }
            }
        }
        .frame(height: 112)
    }
}

// MARK: - Program uyumu

private struct ProgramUyumBlogu: View {
    let gunler: [ProgramGunu]
    let onceki: [ProgramGunu]
    let seri: Int

    private func oran(_ g: [ProgramGunu]) -> Double? {
        let plan = g.filter(\.planli).count
        return plan == 0 ? nil : Double(g.filter { $0.planli && $0.yapildi }.count) / Double(plan) * 100
    }

    var body: some View {
        let renk = KlasikRenk.yesil
        let planli = gunler.filter(\.planli).count
        let yapilan = gunler.filter { $0.planli && $0.yapildi }.count
        let bu = oran(gunler), once = oran(onceki)
        VStack(spacing: 0) {
            BlokBasligi(ad: "Program Uyumu", renk: renk, degisim: bu.flatMap { b in once.map { b - $0 } })
            GunSutunlari(gunler: gunler.map(\.date),
                         sutunlar: gunler.map { g in g.planli || g.yapildi ? .plan(yapildi: g.yapildi) : .bos },
                         renk: renk)
            UcluMetrik(ogeler: [
                .init(deger: bu.map { "%\(Int($0.rounded()))" } ?? "—", ad: "Uyum"),
                .init(deger: "\(seri)", birim: "hafta", ad: "Seri"),
                .init(deger: "\(yapilan)", birim: "/ \(planli) gün", ad: "Yapılan")
            ])
            .padding(.top, 12)
        }
    }
}

// MARK: - Metrik

private struct MetrikBlogu: View {
    let kart: MetricCard

    private var m: StatMetric { kart.metric }

    private var renk: Color {
        switch m {
        case .steps: return Color(hex: "#A8584C")
        case .calories: return Color(hex: "#C27A3A")
        case .water: return Color(hex: "#6E8E92")
        case .sleep: return Color(hex: "#6E5A80")
        case .workout: return Color(hex: "#4E6A4A")
        case .weight: return Color(hex: "#8A6E52")
        }
    }

    private func bicim(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(m.fractionDigits)).locale(Locale(identifier: "tr_TR")))
    }

    var body: some View {
        let gunler = kart.chart
        let degerler = gunler.map(\.value)
        let kayitli = degerler.filter { $0 > 0 }
        let n = gunler.count
        let hedef = m == .weight ? nil : kart.goal
        let tutar: (Double) -> Bool = { v in hedef.map { v >= $0 } ?? (v > 0) }
        let taban = m == .weight ? floor((kayitli.min() ?? 1) - 1) : 0
        let tavan = m == .weight ? (kayitli.max() ?? 1) + 0.4 : max(kayitli.max() ?? 1, hedef ?? 0) * 1.08
        let ikinciAd: String = {
            switch m {
            case .calories: return "En yüksek"
            case .sleep, .workout: return "En uzun"
            case .weight: return "En düşük"
            default: return "En iyi"
            }
        }()
        let ikinci = m == .weight ? kayitli.min() : kayitli.max()
        let ucuncu: UcluMetrik.Oge = {
            switch m {
            case .workout: return .init(deger: "\(kayitli.count)", birim: "/ \(n) gün", ad: "Aktif gün")
            case .weight: return .init(deger: "\(kayitli.count)", birim: "/ \(n) gün", ad: "Tartılan gün")
            default: return .init(deger: "\(kayitli.filter(tutar).count)", birim: "/ \(n) gün", ad: "Hedefte")
            }
        }()

        VStack(spacing: 0) {
            BlokBasligi(ad: m.title, renk: renk, degisim: kart.summary.changePercent, dususIyi: m == .calories || m == .weight)
            GunSutunlari(gunler: gunler.map(\.date),
                         sutunlar: degerler.map { $0 > 0 ? .dolu($0, tutan: tutar($0)) : .bos },
                         renk: renk, hedef: hedef, taban: taban, tavan: tavan)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(m.title) grafiği, \(kayitli.count) günlük kayıt")
            UcluMetrik(ogeler: [
                .init(deger: kart.summary.average.map(bicim) ?? "—", birim: m.unit, ad: "Ortalama"),
                .init(deger: ikinci.map(bicim) ?? "—", birim: m.unit, ad: ikinciAd),
                ucuncu
            ])
            .padding(.top, 12)
        }
    }
}
