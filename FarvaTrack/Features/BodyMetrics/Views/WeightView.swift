import SwiftUI
import SwiftData

/// Kilo ekranı (klasik tasarım, "Tüyün yolu"): 7 günlük ortalamanın fırça çizgisi tüyün geçtiği yol,
/// tüy bugünkü noktada; sağda hedef zemini ve oraya noktalı yol. Altında değişimler, son tartılar, vücut ölçüleri.
/// Tartı eklemek sağ üstteki "+" ile (mezurayı kaydırarak), hedef/boy/hatırlatıcı ayar sayfasında.
struct WeightView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = BodyMetricsViewModel()
    @State private var tarti: TartiDuzenleme?
    @State private var ayarAcik = false

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    var body: some View {
        Group {
            if let user = auth.currentUser {
                KiloIcerigi(ownerID: user.id, viewModel: viewModel, duzenle: { tarti = TartiDuzenleme(kayit: $0) })
            } else {
                ProgressView()
            }
        }
        .klasikEkran("Kilo") {
            EkleDugmesi(etiket: "Tartı ekle") {
                Haptics.impact(.light)
                tarti = TartiDuzenleme(kayit: nil)
            }
            AyarDugmesi(etiket: "Kilo ayarları") { ayarAcik = true }
        }
        .sheet(item: $tarti) { hedef in
            TartiSayfasi(viewModel: viewModel, kayit: hedef.kayit, kaydedildi: syncProfileWeight)
        }
        .sheet(isPresented: $ayarAcik) {
            KiloAyarSayfasi(viewModel: viewModel)
        }
        .alert("Bir sorun oluştu", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: auth.currentUser, initial: true) { _, user in
            if let user { viewModel.configure(context: modelContext, user: user) }
        }
        .task(id: auth.currentUser?.id) {
            if let user = auth.currentUser { viewModel.configure(context: modelContext, user: user) }
            await viewModel.syncAll()
            syncProfileWeight()
        }
    }

    /// Profildeki kiloyu en son tartıyla eşitler (kalori ve su hedefleri buna göre hesaplanır).
    private func syncProfileWeight() {
        guard var user = auth.currentUser, let latest = viewModel.latestWeight() else { return }
        guard abs((user.weightKg ?? 0) - latest) >= 0.05 else { return }
        user.weightKg = latest
        Task { await auth.updateUser(user) }
    }
}

struct TartiDuzenleme: Identifiable {
    let kayit: WeightEntry?
    let id = UUID()
}

enum KiloRenk {
    static let yesil = Color(hex: "#4E6A4A")
    static let koyu = Color(hex: "#3A5236")
}

enum KiloBicim {
    static func kg(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR"))) }
    static func isaretli(_ v: Double) -> String {
        let m = kg(abs(v))
        return abs(v) < 0.05 ? m : (v > 0 ? "+" : "−") + m
    }
    static func gunOnce(_ d: Date) -> String {
        let t = Calendar.current
        if t.isDateInToday(d) { return "Bugün" }
        if t.isDateInYesterday(d) { return "Dün" }
        let g = t.dateComponents([.day], from: t.startOfDay(for: d), to: t.startOfDay(for: .now)).day ?? 0
        return "\(g) gün önce"
    }
}

// MARK: - İçerik

private struct KiloIcerigi: View {
    @Query private var kayitlar: [WeightEntry]
    @Query private var olculer: [MeasurementEntry]
    let viewModel: BodyMetricsViewModel
    let duzenle: (WeightEntry) -> Void

    @State private var aralik = 90

    init(ownerID: String, viewModel: BodyMetricsViewModel, duzenle: @escaping (WeightEntry) -> Void) {
        _kayitlar = Query(filter: #Predicate<WeightEntry> { $0.ownerID == ownerID }, sort: \.date, order: .reverse)
        _olculer = Query(filter: #Predicate<MeasurementEntry> { $0.ownerID == ownerID }, sort: \.date, order: .reverse)
        self.viewModel = viewModel
        self.duzenle = duzenle
    }

    var body: some View {
        let noktalar = kayitlar.map(\.point)
        let son = kayitlar.first

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let son {
                    (Text(KiloBicim.kg(son.weightKg)).font(.system(size: 44, weight: .bold)).foregroundColor(Color.ftText)
                     + Text(" kg").font(.system(size: 15)).foregroundColor(Color.ftTextSecondary))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    kalanSatiri(son.weightKg, noktalar: noktalar)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "#4A3324"))
                        .padding(.top, 4)
                } else {
                    Text("Henüz tartı yok")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ftText)
                }

                TuyunYolu(noktalar: noktalar, gun: aralik, hedef: viewModel.targetWeightKg)
                    .padding(.top, 6)

                HStack {
                    Spacer()
                    KlasikSekmeler(secenekler: [(30, "1A"), (90, "3A"), (180, "6A"), (365, "1Y")], secili: $aralik)
                }

                UcluMetrik(ogeler: [
                    .init(deger: WeightAnalyzer.change(noktalar, days: 7).map(KiloBicim.isaretli) ?? "—", birim: "kg", ad: "7 gün"),
                    .init(deger: WeightAnalyzer.change(noktalar, days: 30).map(KiloBicim.isaretli) ?? "—", birim: "kg", ad: "30 gün"),
                    .init(deger: son.flatMap { viewModel.bmi(for: $0.weightKg) }.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                          ad: son.flatMap { viewModel.bmi(for: $0.weightKg) }.map { "BMI · \(BMICategory(bmi: $0).title.lowercased(with: Locale(identifier: "tr_TR")))" } ?? "BMI")
                ])
                .padding(.top, 16)

                if !kayitlar.isEmpty {
                    BolumBasligi(metin: "Son tartılar").padding(.top, 22).padding(.bottom, 4)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 40), GridItem(.flexible())], spacing: 0) {
                        ForEach(kayitlar.prefix(4)) { k in
                            Button { duzenle(k) } label: {
                                VStack(spacing: 0) {
                                    HStack {
                                        Text(KiloBicim.gunOnce(k.date)).foregroundStyle(Color.ftTextSecondary)
                                        Spacer()
                                        Text("\(KiloBicim.kg(k.weightKg)) kg").fontWeight(.bold).foregroundStyle(Color.ftText)
                                    }
                                    .font(.system(size: 15).monospacedDigit())
                                    .frame(height: 44)
                                    FircaAyirici(tohum: Int(k.weightKg * 10))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(KiloBicim.gunOnce(k.date)), \(KiloBicim.kg(k.weightKg)) kilogram")
                            .accessibilityHint("Düzenle")
                        }
                    }
                }

                NavigationLink {
                    MeasurementsView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 10) {
                        MezuraSimgesi().frame(width: 22, height: 22)
                        Text("Vücut ölçüleri").font(.system(size: 16)).foregroundStyle(Color.ftText)
                        Spacer()
                        Text(olcuOzeti).font(.system(size: 13)).foregroundStyle(Color.ftTextSecondary)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(KlasikRenk.soluk)
                    }
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .padding(.horizontal, Constants.Layout.screenPadding)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private var olcuOzeti: String {
        var parca: [String] = []
        for o in [BodyMeasure.waist, .arm] {
            if let v = olculer.lazy.compactMap({ $0.value(for: o) }).first {
                parca.append("\(o.title) \(v.formatted(.number.precision(.fractionLength(0...1))))")
            }
        }
        return parca.joined(separator: " · ")
    }

    private func kalanSatiri(_ simdi: Double, noktalar: [WeightPoint]) -> Text {
        guard let hedef = viewModel.targetWeightKg else {
            return Text("Hedef kilo belirlenmedi").foregroundColor(Color.ftTextSecondary)
        }
        let kalan = abs(simdi - hedef)
        if kalan < 0.1 { return Text("Hedefine ") + Text("ulaştın").bold() }
        var t = Text("Hedefe ") + Text("\(KiloBicim.kg(kalan)) kg").bold() + Text(" kaldı")
        if let h = WeightAnalyzer.weeksToGoal(current: simdi, target: hedef, weeklyRate: WeightAnalyzer.weeklyRate(noktalar)) {
            t = t + Text(" · bu hızla ~\(h) hafta").foregroundColor(Color.ftTextSecondary)
        }
        return t
    }
}

// MARK: - Tüyün yolu

struct TuyunYolu: View {
    let noktalar: [WeightPoint]
    let gun: Int
    let hedef: Double?

    @Environment(\.accessibilityReduceMotion) private var hareketiAzalt

    var body: some View {
        let simdi = Date.now
        let gorunen = noktalar.filter { $0.date >= simdi.addingTimeInterval(-Double(gun) * 86_400) }.sorted { $0.date < $1.date }
        let ortalama = WeightAnalyzer.movingAverage(gorunen, windowDays: 7)

        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: hareketiAzalt)) { zaman in
            let t = hareketiAzalt ? 0 : zaman.date.timeIntervalSinceReferenceDate
            Canvas { ctx, boyut in
                ciz(&ctx, boyut: boyut, gorunen: gorunen, ortalama: ortalama, t: t, simdi: simdi)
            }
        }
        .frame(height: 250)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(erisim(gorunen))
    }

    private func erisim(_ g: [WeightPoint]) -> String {
        guard let ilk = g.first, let son = g.last else { return "Bu aralıkta tartı yok" }
        return "Kilo grafiği: \(KiloBicim.kg(ilk.weightKg)) kilodan \(KiloBicim.kg(son.weightKg)) kiloya."
    }

    private func ciz(_ ctx: inout GraphicsContext, boyut: CGSize, gorunen: [WeightPoint], ortalama: [WeightPoint], t: Double, simdi: Date) {
        guard gorunen.count >= 2 else {
            ctx.draw(Text("Grafik için en az iki tartı gerekli").font(.system(size: 13)).foregroundStyle(Color.ftTextSecondary),
                     at: CGPoint(x: boyut.width / 2, y: boyut.height / 2))
            return
        }
        let W = boyut.width, H = boyut.height, ust: CGFloat = 80, alt: CGFloat = 34, sol: CGFloat = 10, sag: CGFloat = 120
        let gunOnce: (Date) -> Double = { max(0, simdi.timeIntervalSince($0) / 86_400) }
        var degerler = gorunen.map(\.weightKg)
        if let hedef { degerler.append(hedef) }
        let mn = (degerler.min() ?? 0) - 0.4, mx = (degerler.max() ?? 1) + 0.4
        let gmax = max(gorunen.map { gunOnce($0.date) }.max() ?? 14, 14)
        let x: (Date) -> CGFloat = { sol + CGFloat(1 - gunOnce($0) / gmax) * (W - sol - sag) }
        let y: (Double) -> CGFloat = { ust + CGFloat((mx - $0) / (mx - mn)) * (H - ust - alt) }

        let yol = Firca.ornekle(ortalama.map { CGPoint(x: x($0.date), y: y($0.weightKg)) }, 4)
        guard let son = yol.last else { return }

        // Hedef: zemin çizgisi ve küçük çimen
        let hx = W - 20
        if let hedef {
            let hy = y(hedef)
            ctx.fill(Firca.duz(CGPoint(x: W - 70, y: hy + 14), CGPoint(x: W - 4, y: hy + 14), Firca.Ayar(w: 1.2, tohum: 8)),
                     with: .color(KlasikRenk.soluk.opacity(0.55)))
            var cimen = Path()
            for (dx, h) in [(58.0, 8.0), (48, 6), (30, 9), (18, 6)] {
                cimen.move(to: CGPoint(x: W - dx, y: hy + 14))
                cimen.addQuadCurve(to: CGPoint(x: W - dx + 1, y: hy + 14 - h), control: CGPoint(x: W - dx - 1.5, y: hy + 14 - h / 2))
            }
            ctx.stroke(cimen, with: .color(Color(hex: "#7C8B5E")), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            ctx.draw(Text("hedef \(KiloBicim.kg(hedef))").font(.system(size: 10)).foregroundStyle(Color(hex: "#6E523C")),
                     at: CGPoint(x: W - 4, y: hy + 28), anchor: .trailing)
            var gelecek = Path()
            gelecek.move(to: son)
            gelecek.addCurve(to: CGPoint(x: hx, y: hy + 6), control1: CGPoint(x: son.x + 18, y: son.y - 4), control2: CGPoint(x: hx - 30, y: hy - 4))
            ctx.stroke(gelecek, with: .color(Color(hex: "#A89A88")), style: StrokeStyle(lineWidth: 0.9, lineCap: .round, dash: [1, 5]))
        }

        // Geçmiş yol: rüzgâr çizgisi
        var golgeli = ctx
        golgeli.addFilter(.shadow(color: OzetRenk.golge.opacity(0.36), radius: 3, x: 2, y: 5))
        golgeli.fill(Firca.cizgi(yol, Firca.Ayar(w: 2.6, tohum: 64, giris: 0.1, cikis: 0.02, basinc: 0.3)), with: .color(KiloRenk.yesil.opacity(0.75)))
        for p in gorunen {
            ctx.fill(Path(ellipseIn: CGRect(x: x(p.date) - 1.4, y: y(p.weightKg) - 1.4, width: 2.8, height: 2.8)), with: .color(KlasikRenk.soluk.opacity(0.4)))
        }
        if let ilk = ortalama.first, let ilkTarti = gorunen.first {
            let g = Int(gunOnce(ilkTarti.date).rounded())
            ctx.draw(Text("\(g) gün önce · \(KiloBicim.kg(ilk.weightKg))").font(.system(size: 10)).foregroundStyle(Color(hex: "#6E523C")),
                     at: CGPoint(x: 10, y: y(ilk.weightKg) - 10), anchor: .leading)
        }

        // Tüy bugünkü noktada; ucu (62, 86) yola oturur ve hafifçe salınır
        let salinim = sin(t * 0.9) * 2.5
        var tuy = ctx
        tuy.addFilter(.shadow(color: OzetRenk.golge.opacity(0.42), radius: 1.5, x: 1.5, y: 2.5))
        tuy.translateBy(x: son.x, y: son.y)
        tuy.rotate(by: .degrees(salinim))
        tuy.scaleBy(x: 0.95, y: 0.95)
        tuy.translateBy(x: -62, y: -86)
        tuy.stroke(SuzulenTuy.tuy.kil, with: .color(Color(hex: "#9A8C7C")), lineWidth: 0.55)
        tuy.stroke(SuzulenTuy.tuy.sap, with: .color(Color(hex: "#6E5A48")), lineWidth: 1.1)
    }
}

/// Küçük mezura simgesi (vücut ölçüleri satırı).
struct MezuraSimgesi: View {
    var body: some View {
        Canvas { ctx, boyut in
            let s = boyut.width / 34
            ctx.scaleBy(x: s, y: s)
            var p = Path()
            p.addEllipse(in: CGRect(x: 4, y: 6, width: 18, height: 18))
            p.addEllipse(in: CGRect(x: 10, y: 12, width: 6, height: 6))
            p.move(to: CGPoint(x: 13, y: 24)); p.addLine(to: CGPoint(x: 31, y: 24)); p.addLine(to: CGPoint(x: 31, y: 18))
            for (xx, h) in [(17.0, 3.0), (21, 2), (25, 3), (29, 2)] {
                p.move(to: CGPoint(x: xx, y: 24)); p.addLine(to: CGPoint(x: xx, y: 24 - h))
            }
            ctx.stroke(p, with: .color(KiloRenk.koyu), style: StrokeStyle(lineWidth: 1.3 / s, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tartı ekle / düzenle (mezurayı kaydırarak)

/// Yatay mezura: sürükledikçe değer 0,1 adımla değişir; ortadaki kırmızı iğne seçili değeri gösterir.
struct MezuraCetveli: View {
    @Binding var deger: Double
    var aralik: ClosedRange<Double> = 30...200
    var adim = 0.1
    var nokta: CGFloat = 9
    var yukseklik: CGFloat = 64

    @State private var baslangic: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Canvas { ctx, boyut in
                let orta = w / 2
                let gorunur = Double(w / nokta) * adim / 2 + adim
                var v = ((deger - gorunur) / adim).rounded(.down) * adim
                while v <= deger + gorunur {
                    defer { v += adim }
                    guard aralik.contains(v) else { continue }
                    let i = Int((v / adim).rounded())
                    let x = orta + CGFloat((v - deger) / adim) * nokta
                    let tam = i % 10 == 0, yarim = i % 5 == 0
                    var c = Path()
                    c.move(to: CGPoint(x: x, y: 6))
                    c.addLine(to: CGPoint(x: x, y: 6 + (tam ? 30 : yarim ? 20 : 12)))
                    ctx.stroke(c, with: .color(Color(hex: "#5E4A2E")), lineWidth: tam ? 1.1 : 0.6)
                    if tam {
                        ctx.draw(Text("\(Int((v).rounded()))").font(.system(size: 12)).foregroundStyle(Color(hex: "#5E4A2E")),
                                 at: CGPoint(x: x, y: 50))
                    }
                }
                var igne = Path()
                igne.move(to: CGPoint(x: orta, y: 0))
                igne.addLine(to: CGPoint(x: orta, y: boyut.height))
                ctx.stroke(igne, with: .color(KlasikRenk.vurgu), lineWidth: 2)
                var uc = Path()
                uc.move(to: CGPoint(x: orta - 6, y: -3)); uc.addLine(to: CGPoint(x: orta + 6, y: -3)); uc.addLine(to: CGPoint(x: orta, y: 5)); uc.closeSubpath()
                ctx.fill(uc, with: .color(KlasikRenk.vurgu))
            }
            .background(
                LinearGradient(colors: [Color(hex: "#EFDFB4"), Color(hex: "#E5D2A0")], startPoint: .top, endPoint: .bottom)
                    .overlay(alignment: .top) { Rectangle().fill(Color(hex: "#B89A5E")).frame(height: 0.8) }
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: "#B89A5E")).frame(height: 0.8) }
                    .padding(.vertical, 2)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { d in
                        let bas = baslangic ?? deger
                        if baslangic == nil { baslangic = deger }
                        let yeni = min(aralik.upperBound, max(aralik.lowerBound, ((bas - Double(d.translation.width / nokta) * adim) / adim).rounded() * adim))
                        if abs(yeni - deger) >= adim / 2 { Haptics.selection() }
                        deger = yeni
                    }
                    .onEnded { _ in baslangic = nil }
            )
        }
        .frame(height: yukseklik)
        .accessibilityElement()
        .accessibilityLabel("Değer")
        .accessibilityValue(KiloBicim.kg(deger))
        .accessibilityAdjustableAction { yon in
            deger = min(aralik.upperBound, max(aralik.lowerBound, deger + (yon == .increment ? adim : -adim)))
        }
    }
}

private struct TartiSayfasi: View {
    let viewModel: BodyMetricsViewModel
    let kayit: WeightEntry?
    let kaydedildi: () -> Void

    @State private var deger = 70.0
    @State private var gun = Calendar.current.startOfDay(for: .now)
    @State private var oncekiSon: Double?
    @Environment(\.dismiss) private var kapat

    var body: some View {
        KlasikAyarSayfasi(baslik: kayit == nil ? "Tartı Ekle" : "Tartıyı Düzenle", kaydet: kaydet) {
            VStack(spacing: 4) {
                (Text(KiloBicim.kg(deger)).font(.system(size: 52, weight: .bold)).foregroundColor(Color.ftText)
                 + Text(" kg").font(.system(size: 15)).foregroundColor(Color.ftTextSecondary))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(farkMetni).font(.system(size: 13)).foregroundStyle(Color.ftTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)

            MezuraCetveli(deger: $deger)
                .padding(.horizontal, -20)
                .padding(.top, 18)

            if kayit == nil {
                AyarSecimSatiri(baslik: "Gün", secenekler: gunler, secili: $gun)
                    .padding(.top, 18)
            } else if let kayit {
                AyarSatiri(baslik: "Gün") {
                    Text(KiloBicim.gunOnce(kayit.date)).foregroundStyle(Color.ftText)
                }
                .padding(.top, 18)
                Button("Tartıyı sil", role: .destructive) {
                    viewModel.deleteWeight(kayit)
                    kaydedildi()
                    kapat()
                }
                .font(.system(size: 15))
                .padding(.top, 8)
            }
        }
        .onAppear {
            oncekiSon = viewModel.latestWeight()
            deger = kayit?.weightKg ?? oncekiSon ?? 70
        }
    }

    private var gunler: [(Date, String)] {
        let t = Calendar.current, b = t.startOfDay(for: .now)
        return (0..<7).compactMap { i in
            t.date(byAdding: .day, value: -i, to: b).map { ($0, i == 0 ? "Bugün" : i == 1 ? "Dün" : "\(i) gün önce") }
        }
    }

    private var farkMetni: String {
        guard let s = kayit == nil ? oncekiSon : kayit?.weightKg else { return " " }
        let f = deger - s
        if abs(f) < 0.05 { return kayit == nil ? "son tartıyla aynı" : "değişmedi" }
        return kayit == nil ? "son tartıdan \(KiloBicim.isaretli(f)) kg" : "önceki değerden \(KiloBicim.isaretli(f)) kg"
    }

    private func kaydet() {
        do {
            let t = Calendar.current
            let tarih: Date
            if let kayit { tarih = kayit.date } else if t.isDateInToday(gun) { tarih = .now } else { tarih = t.date(byAdding: .hour, value: 9, to: gun) ?? gun }
            _ = try viewModel.saveWeight((deger * 10).rounded() / 10, date: tarih, editing: kayit)
            Haptics.success()
            kaydedildi()
        } catch {
            viewModel.errorMessage = AppError.map(error).errorDescription
        }
    }
}

// MARK: - Ayarlar

private struct KiloAyarSayfasi: View {
    let viewModel: BodyMetricsViewModel
    @Environment(AuthViewModel.self) private var auth

    @State private var hedef: Double = 65
    @State private var hedefVar = true
    @State private var boy = 170
    @State private var hatir = WeighInReminderSettings()

    private static let haftaGunleri: [(Int, String)] = [(2, "Pazartesi"), (3, "Salı"), (4, "Çarşamba"), (5, "Perşembe"), (6, "Cuma"), (7, "Cumartesi"), (1, "Pazar")]
    private static let saatler: [(Int, String)] = (0...16).map { (360 + $0 * 30, UykuBicim.saat(360 + $0 * 30)) }

    private var saatBaglama: Binding<Int> {
        Binding(get: { hatir.hour * 60 + hatir.minute }, set: { hatir.hour = $0 / 60; hatir.minute = $0 % 60 })
    }

    private var kaydedilebilir: Bool { !hedefVar || dogrulama.message == nil }

    private var dogrulama: WeightGoalValidation {
        viewModel.validateGoal(hedef, currentKg: viewModel.latestWeight() ?? auth.currentUser?.weightKg)
    }

    var body: some View {
        KlasikAyarSayfasi(baslik: "Kilo Ayarları", kaydetEtkin: kaydedilebilir, kaydet: kaydet) {
            if hedefVar {
                HedefSatiri(baslik: "Hedef kilo", deger: KiloBicim.kg(hedef), birim: "kg",
                            azalt: { hedef = max(WeightAnalyzer.validRange.lowerBound, hedef - 0.5) },
                            artir: { hedef = min(WeightAnalyzer.validRange.upperBound, hedef + 0.5) })
                if let m = dogrulama.message {
                    Text(m).font(.system(size: 12)).foregroundStyle(Color.ftWarning).padding(.bottom, 6)
                }
            } else {
                AyarSatiri(baslik: "Hedef kilo") {
                    Button("Belirle") { hedefVar = true }.fontWeight(.semibold)
                }
            }
            FircaAyirici(tohum: 511)
            HedefSatiri(baslik: "Boy", deger: "\(boy)", birim: "cm",
                        azalt: { boy = max(120, boy - 1) }, artir: { boy = min(230, boy + 1) })
            if hedefVar && viewModel.targetWeightKg != nil {
                Button("Hedefi kaldır", role: .destructive) { hedefVar = false }
                    .font(.system(size: 14))
                    .padding(.top, 4)
            }

            HStack {
                AyarBolumu(metin: "Tartı hatırlatıcısı")
                Spacer()
                Toggle("Tartı hatırlatıcısı", isOn: $hatir.isEnabled).labelsHidden().tint(KiloRenk.yesil)
            }
            Group {
                AyarSecimSatiri(baslik: "Gün", secenekler: Self.haftaGunleri, secili: $hatir.weekday)
                FircaAyirici(tohum: 531)
                AyarSecimSatiri(baslik: "Saat", secenekler: Self.saatler, secili: saatBaglama)
            }
            .opacity(hatir.isEnabled ? 1 : 0.45)
            .disabled(!hatir.isEnabled)
        }
        .onAppear {
            hedefVar = viewModel.targetWeightKg != nil
            hedef = viewModel.targetWeightKg ?? viewModel.latestWeight() ?? auth.currentUser?.weightKg ?? 65
            boy = Int((viewModel.heightCm ?? auth.currentUser?.heightCm ?? 170).rounded())
            hatir = viewModel.reminderSettings
            hatir.minute = hatir.minute < 30 ? 0 : 30
            hatir.hour = min(14, max(6, hatir.hour))
        }
    }

    private func kaydet() {
        if var user = auth.currentUser {
            let yeniHedef: Double? = hedefVar ? hedef : nil
            var degisti = false
            if yeniHedef != viewModel.targetWeightKg {
                user.targetWeightKg = yeniHedef
                if user.startWeightKg == nil || yeniHedef == nil {
                    user.startWeightKg = yeniHedef == nil ? nil : (viewModel.latestWeight() ?? user.weightKg)
                }
                degisti = true
            }
            if Double(boy) != (user.heightCm ?? 0) {
                user.heightCm = Double(boy)
                degisti = true
            }
            if degisti { Task { await auth.updateUser(user) } }
        }
        if hatir != viewModel.reminderSettings {
            let yeni = hatir
            Task {
                let ok = await viewModel.applyReminder(yeni)
                if !ok && yeni.isEnabled { viewModel.errorMessage = "Bildirim izni kapalı. Ayarlar > FarvaTrack > Bildirimler'den açabilirsin." }
            }
        }
    }
}
