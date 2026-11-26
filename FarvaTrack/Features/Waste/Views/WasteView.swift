import SwiftUI
import SwiftData

/// Kaka ekranı (klasik tasarım): Ritim widget'ındaki kum kabı kedisi (dokun = +1, geri alınabilir),
/// son 7 günün pati izleri ya da aylık takvim (önceki aylara gidilebilir) ve bugünün saatleri.
/// Sağ üstteki göz, ana ekrandaki widget'ta kediyi gizler (gizli mod).
struct WasteView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(WasteViewModel.self) private var viewModel

    @State private var gizli = SharedStore.wasteSecret
    @State private var not: String?
    @State private var notGorevi: Task<Void, Never>?

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    var body: some View {
        Group {
            if let user = auth.currentUser {
                KakaIcerigi(ownerID: user.id, viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .klasikEkran("Kaka") {
            Button {
                gizli.toggle()
                SharedStore.wasteSecret = gizli
                Haptics.selection()
                goster(gizli ? "Widget’ta gizli mod açık" : "Widget’ta gizli mod kapalı")
            } label: {
                GizliModSimgesi(gizli: gizli).frame(width: 26, height: 26)
            }
            .accessibilityLabel("Widget’ta gizli mod")
            .accessibilityValue(gizli ? "Açık" : "Kapalı")
        }
        .overlay(alignment: .top) {
            if let not {
                Text(not)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ftText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#F2E6CC"), in: RoundedRectangle(cornerRadius: 2))
                    .shadow(color: OzetRenk.golge.opacity(0.3), radius: 1, x: 1, y: 2)
                    .shadow(color: OzetRenk.golge.opacity(0.32), radius: 7, x: 4, y: 9)
                    .rotationEffect(.degrees(-0.6))
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .offset(y: -8)))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeOut(duration: 0.25), value: not)
        .alert("Bir sorun oluştu", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.handleForeground() }
    }

    private func goster(_ metin: String) {
        notGorevi?.cancel()
        not = metin
        notGorevi = Task {
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { not = nil }
        }
    }
}

/// Açık göz = gizli mod kapalı; üstü çizili göz = açık.
struct GizliModSimgesi: View {
    let gizli: Bool
    var body: some View {
        Canvas { ctx, boyut in
            let s = boyut.width / 26
            ctx.scaleBy(x: s, y: s)
            var goz = Path()
            goz.move(to: CGPoint(x: 3, y: 13))
            goz.addCurve(to: CGPoint(x: 13, y: 6), control1: CGPoint(x: 6.5, y: 7.5), control2: CGPoint(x: 9.5, y: 6))
            goz.addCurve(to: CGPoint(x: 23, y: 13), control1: CGPoint(x: 16.5, y: 6), control2: CGPoint(x: 19.5, y: 7.5))
            goz.addCurve(to: CGPoint(x: 13, y: 20), control1: CGPoint(x: 19.5, y: 18.5), control2: CGPoint(x: 16.5, y: 20))
            goz.addCurve(to: CGPoint(x: 3, y: 13), control1: CGPoint(x: 9.5, y: 20), control2: CGPoint(x: 6.5, y: 18.5))
            let st = StrokeStyle(lineWidth: 1.7 / s, lineCap: .round, lineJoin: .round)
            ctx.stroke(goz, with: .color(KlasikRenk.vurgu), style: st)
            if gizli {
                var c = Path()
                c.move(to: CGPoint(x: 5, y: 21)); c.addLine(to: CGPoint(x: 21, y: 5))
                ctx.stroke(c, with: .color(KlasikRenk.vurgu), style: st)
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: 9.6, y: 9.6, width: 6.8, height: 6.8)), with: .color(KlasikRenk.vurgu))
            }
        }
    }
}

enum KakaRenk {
    static let kahve = Color(hex: "#8A5A3A")
}

// MARK: - İçerik

private struct KakaIcerigi: View {
    @Query private var kayitlar: [WasteEntry]
    let viewModel: WasteViewModel

    @State private var aylik = false
    @State private var ay = 0
    @State private var zipla = 0
    @State private var silinecek: UUID?

    init(ownerID: String, viewModel: WasteViewModel) {
        _kayitlar = Query(filter: #Predicate<WasteEntry> { $0.ownerID == ownerID }, sort: \.date, order: .reverse)
        self.viewModel = viewModel
    }

    private var takvim: Calendar { .current }

    private func sayilar() -> [Date: Int] {
        var s: [Date: Int] = [:]
        for k in kayitlar { s[takvim.startOfDay(for: k.date), default: 0] += 1 }
        return s
    }

    var body: some View {
        let s = sayilar()
        let bugun = kayitlar.filter { takvim.isDateInToday($0.date) }.sorted { $0.date < $1.date }
        let gunler = aylik ? ayinGunleri() : sonYediGun()
        let degerler = gunler.map { s[$0] ?? 0 }
        let kayitli = degerler.filter { $0 > 0 }.count
        let ort = degerler.isEmpty ? 0 : Double(degerler.reduce(0, +)) / Double(degerler.count)

        ScrollView {
            VStack(spacing: 0) {
                if !SharedStore.isSharedContainerAvailable {
                    WidgetSyncNotice().padding(.bottom, 8)
                }
                Button(action: ekle) {
                    LitterBoxArt(count: bugun.count)
                        .frame(width: 200, height: 200)
                        .keyframeAnimator(initialValue: 1.0, trigger: zipla) { icerik, o in
                            icerik.scaleEffect(x: 2 - o, y: o, anchor: .bottom)
                        } keyframes: { _ in
                            KeyframeTrack {
                                SpringKeyframe(0.9, duration: 0.12)
                                SpringKeyframe(1.05, duration: 0.18)
                                SpringKeyframe(1.0, duration: 0.3)
                            }
                        }
                        .contentShape(Circle().inset(by: 8))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .accessibilityLabel("Kayıt ekle, bugün \(bugun.count) kez")

                durumSatiri(bugun)
                    .frame(minHeight: 34)
                    .padding(.top, 2)

                UcluMetrik(ogeler: [
                    .init(deger: ort.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR"))), ad: "Günlük ortalama"),
                    .init(deger: "\(degerler.max() ?? 0)", ad: "En fazla"),
                    .init(deger: "\(kayitli)", birim: "/ \(degerler.count)", ad: "Kayıtlı gün")
                ])
                .padding(.top, 16)

                HStack {
                    if aylik { ayGezgini } else { BolumBasligi(metin: "Geçmiş") }
                    Spacer()
                    KlasikSekmeler(secenekler: [(false, "7 gün"), (true, "Aylık")],
                                   secili: Binding(get: { aylik }, set: { aylik = $0; ay = 0 }))
                }
                .frame(minHeight: 32)
                .padding(.top, 20)
                .padding(.bottom, 8)

                if aylik {
                    AylikPatiler(ayBasi: ayBasi(), sayilar: s)
                        .gesture(DragGesture(minimumDistance: 30).onEnded { d in
                            if d.translation.width > 50, oncekiAyVar { withAnimation { ay -= 1 } }
                            if d.translation.width < -50, ay < 0 { withAnimation { ay += 1 } }
                        })
                } else {
                    YediGunPatileri(gunler: gunler, degerler: degerler)
                }

                if !bugun.isEmpty {
                    BolumBasligi(metin: "Bugün").padding(.top, 16).padding(.bottom, 4)
                    FlowCipler(kayitlar: bugun, silinecek: $silinecek) { viewModel.delete($0) }
                }
            }
            .padding(.horizontal, Constants.Layout.screenPadding)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.lastAddedID)
    }

    private func ekle() {
        do {
            _ = try viewModel.add()
            silinecek = nil
            zipla += 1
            Haptics.impact(.light)
        } catch {
            viewModel.errorMessage = AppError.map(error).errorDescription
        }
    }

    @ViewBuilder
    private func durumSatiri(_ bugun: [WasteEntry]) -> some View {
        if viewModel.lastAddedID != nil {
            HStack(spacing: 6) {
                Text("Kayıt eklendi")
                Button("Geri al") { viewModel.undo() }
                    .fontWeight(.bold)
                    .foregroundStyle(KlasikRenk.vurgu)
            }
            .font(.system(size: 19))
            .foregroundStyle(Color.ftText)
            .transition(.opacity)
        } else if let son = bugun.last {
            (Text("\(bugun.count)").font(.system(size: 26, weight: .bold)) + Text(" kez").font(.system(size: 19))
             + Text(" · son \(son.date.formatted(date: .omitted, time: .shortened))").font(.system(size: 19)).foregroundColor(Color.ftTextSecondary))
                .foregroundStyle(Color.ftText)
                .monospacedDigit()
        } else {
            Text("bugün henüz yok").font(.system(size: 19)).foregroundStyle(Color.ftTextSecondary)
        }
    }

    // MARK: Günler

    private func sonYediGun() -> [Date] {
        let b = takvim.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { takvim.date(byAdding: .day, value: -$0, to: b) }
    }

    private func ayBasi() -> Date {
        let b = takvim.dateInterval(of: .month, for: .now)?.start ?? .now
        return takvim.date(byAdding: .month, value: ay, to: b) ?? b
    }

    private func ayinGunleri() -> [Date] {
        let bas = ayBasi()
        let bugun = takvim.startOfDay(for: .now)
        let n = takvim.range(of: .day, in: .month, for: bas)?.count ?? 30
        return (0..<n).compactMap { takvim.date(byAdding: .day, value: $0, to: bas) }.filter { $0 <= bugun }
    }

    private var oncekiAyVar: Bool {
        guard let enEski = kayitlar.last?.date else { return false }
        return takvim.startOfDay(for: enEski) < ayBasi()
    }

    private var ayGezgini: some View {
        let a = ayBasi()
        let yil = takvim.component(.year, from: a) != takvim.component(.year, from: .now)
        return HStack(spacing: 2) {
            Button { withAnimation { ay -= 1 } } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: 32)
            }
            .disabled(!oncekiAyVar)
            .accessibilityLabel("Önceki ay")
            Text(KlasikTarih.aylar[takvim.component(.month, from: a) - 1] + (yil ? " \(takvim.component(.year, from: a))" : ""))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ftText)
                .frame(minWidth: 74)
            Button { withAnimation { ay += 1 } } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: 32)
            }
            .disabled(ay >= 0)
            .accessibilityLabel("Sonraki ay")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(KlasikRenk.vurgu)
    }
}

// MARK: - Pati izi

enum PatiIzi {
    /// Merkezi (0,0) olan pati izi: taban + dört parmak.
    static func yol(olcek s: CGFloat = 1) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: -4.6 * s, y: (2 - 3.8) * s, width: 9.2 * s, height: 7.6 * s))
        for (x, y) in [(-4.6, -3.4), (-1.6, -5.6), (1.6, -5.6), (4.6, -3.4)] as [(CGFloat, CGFloat)] {
            p.addEllipse(in: CGRect(x: (x - 1.8) * s, y: (y - 1.8) * s, width: 3.6 * s, height: 3.6 * s))
        }
        return p
    }

    static func ciz(_ ctx: inout GraphicsContext, at p: CGPoint, aci: Double, olcek: CGFloat, renk: Color) {
        var k = ctx
        k.translateBy(x: p.x, y: p.y)
        k.rotate(by: .degrees(aci))
        k.fill(yol(olcek: olcek), with: .color(renk))
    }
}

/// Son 7 gün: her kayıt üst üste binen bir pati izi.
private struct YediGunPatileri: View {
    let gunler: [Date]
    let degerler: [Int]

    var body: some View {
        Canvas { ctx, boyut in
            let w = boyut.width / CGFloat(max(gunler.count, 1)), sc: CGFloat = 1.15
            for (i, v) in degerler.enumerated() {
                let cx = CGFloat(i) * w + w / 2
                let son = i == degerler.count - 1
                if v == 0 {
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 1.4, y: 96.6, width: 2.8, height: 2.8)), with: .color(KlasikRenk.bosNokta))
                }
                for p in 0..<min(v, 4) {
                    PatiIzi.ciz(&ctx, at: CGPoint(x: cx + (p % 2 == 1 ? 3.5 : -3.5), y: 96 - CGFloat(p) * 24 * sc),
                                aci: p % 2 == 1 ? 14 : -10, olcek: sc, renk: son ? KakaRenk.kahve : KakaRenk.kahve.opacity(0.55))
                }
                if v > 4 {
                    ctx.draw(Text("+\(v - 4)").font(.system(size: 9, weight: .semibold)).foregroundStyle(KakaRenk.kahve),
                             at: CGPoint(x: cx, y: 96 - 4 * 24 * sc + 4))
                }
                ctx.draw(Text(son ? "Bugün" : KlasikTarih.gunKisa(gunler[i])).font(.system(size: 10, weight: son ? .bold : .regular))
                    .foregroundStyle(son ? KlasikRenk.vurgu : Color(hex: "#6E523C")), at: CGPoint(x: cx, y: 118))
            }
        }
        .frame(height: 124)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Son 7 gün: \(degerler.map(String.init).joined(separator: ", "))")
    }
}

/// Aylık takvim: her günün altında o günkü sayı kadar pati (en fazla 4).
private struct AylikPatiler: View {
    let ayBasi: Date
    let sayilar: [Date: Int]

    var body: some View {
        let t = Calendar.current
        let n = t.range(of: .day, in: .month, for: ayBasi)?.count ?? 30
        let ilk = (t.component(.weekday, from: ayBasi) + 5) % 7
        let satir = Int(ceil(Double(ilk + n) / 7))
        let bugun = t.startOfDay(for: .now)
        Canvas { ctx, boyut in
            let w = boyut.width / 7, yuk: CGFloat = 30
            for (i, g) in KlasikTarih.gunler.enumerated() {
                ctx.draw(Text(g).font(.system(size: 9.5)).foregroundStyle(KlasikRenk.eksen), at: CGPoint(x: CGFloat(i) * w + w / 2, y: 6))
            }
            for d in 1...n {
                guard let gun = t.date(byAdding: .day, value: d - 1, to: ayBasi) else { continue }
                let k = ilk + d - 1
                let x = CGFloat(k % 7) * w, y = 18 + CGFloat(k / 7) * yuk
                let buGun = gun == bugun, gelecek = gun > bugun
                let v = gelecek ? nil : (sayilar[gun] ?? 0)
                ctx.draw(Text("\(d)").font(.system(size: 9.5, weight: buGun ? .bold : .regular))
                    .foregroundStyle(buGun ? KlasikRenk.vurgu : (gelecek ? KlasikRenk.eksen.opacity(0.45) : KlasikRenk.eksen)),
                         at: CGPoint(x: x + w / 2, y: y + 5))
                if let v {
                    if v == 0 {
                        ctx.fill(Path(ellipseIn: CGRect(x: x + w / 2 - 1.6, y: y + 20.4, width: 3.2, height: 3.2)), with: .color(KlasikRenk.bosNokta))
                    }
                    let m = min(v, 4)
                    for p in 0..<m {
                        PatiIzi.ciz(&ctx, at: CGPoint(x: x + w / 2 + (CGFloat(p) - CGFloat(m - 1) / 2) * 9, y: y + 22),
                                    aci: p % 2 == 1 ? 12 : -12, olcek: 0.55, renk: buGun ? KakaRenk.kahve : KakaRenk.kahve.opacity(0.6))
                    }
                }
            }
        }
        .frame(height: CGFloat(satir) * 30 + 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aylık takvim")
    }
}

/// Bugünün saatleri: dokununca "Sil", bir daha dokununca silinir.
private struct FlowCipler: View {
    let kayitlar: [WasteEntry]
    @Binding var silinecek: UUID?
    let sil: (WasteEntry) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(kayitlar) { k in
                let s = silinecek == k.id
                Button {
                    if s { sil(k); silinecek = nil; Haptics.impact(.light) } else { silinecek = k.id }
                } label: {
                    Text(s ? "Sil" : k.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 14, weight: s ? .bold : .regular).monospacedDigit())
                        .foregroundStyle(s ? Color(hex: "#F7EEDC") : Color(hex: "#5A3E2A"))
                        .frame(minWidth: 58, minHeight: 34)
                        .padding(.horizontal, 6)
                        .background {
                            if s { Capsule().fill(KlasikRenk.vurgu) } else { Capsule().stroke(KakaRenk.kahve.opacity(0.4), lineWidth: 1) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(k.date.formatted(date: .omitted, time: .shortened))
                .accessibilityHint(s ? "Silmek için tekrar dokun" : "Silmek için iki kez dokun")
            }
        }
    }
}
