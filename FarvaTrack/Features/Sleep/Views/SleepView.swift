import SwiftUI
import SwiftData

/// Uyku ekranı (klasik tasarım): gerçek 3B ay (uykuya göre önünden geçen yuvarlak çekilir),
/// günün toplamı ve kalitesi, ortalama/düzen/borç, yatış önerisi ve haftanın gece şeritleri.
/// Aya dokununca o günün uykuları (gece + şekerlemeler) kadranda düzenlenir.
struct SleepView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = SleepViewModel()
    @State private var duzenle: UykuDuzenleme?
    @State private var ayarAcik = false

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    var body: some View {
        Group {
            if let user = auth.currentUser {
                UykuIcerigi(ownerID: user.id, viewModel: viewModel, duzenle: { duzenle = $0 })
            } else {
                ProgressView()
            }
        }
        .klasikEkran("Uyku") {
            EkleDugmesi(etiket: "Uyku ekle") {
                Haptics.impact(.light)
                duzenle = UykuDuzenleme(gun: Calendar.current.startOfDay(for: .now), yeniEkle: true)
            }
            AyarDugmesi(etiket: "Uyku ayarları") { ayarAcik = true }
        }
        .sheet(item: $duzenle) { hedef in
            if let user = auth.currentUser {
                UykuKayitSayfasi(ownerID: user.id, gun: hedef.gun, yeniEkle: hedef.yeniEkle, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $ayarAcik) {
            UykuAyarSayfasi(viewModel: viewModel) { yeniHedef in
                guard var user = auth.currentUser else { return }
                user.sleepGoalHours = yeniHedef
                Task { await auth.updateUser(user) }
            }
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
        }
    }
}

struct UykuDuzenleme: Identifiable {
    let gun: Date
    var yeniEkle = false
    let id = UUID()
}

/// Bir günün uykuları: gece (en fazla bir) + şekerlemeler.
struct GunUykusu {
    var gece: SleepEntry?
    var sekerlemeler: [SleepEntry]
    var hepsi: [SleepEntry] { (gece.map { [$0] } ?? []) + sekerlemeler }
    var toplamDakika: Int { hepsi.reduce(0) { $0 + Int(($1.durationHours * 60).rounded()) } }

    static func grupla(_ kayitlar: [SleepEntry], gun: Date, takvim: Calendar = .current) -> GunUykusu {
        let o = kayitlar.filter { takvim.isDate($0.day, inSameDayAs: gun) }
        return GunUykusu(gece: o.filter { !$0.isNap }.max { $0.updatedAt < $1.updatedAt },
                         sekerlemeler: o.filter(\.isNap).sorted { $0.bedtime < $1.bedtime })
    }
}

// MARK: - İçerik

private struct UykuIcerigi: View {
    @Query private var kayitlar: [SleepEntry]
    let viewModel: SleepViewModel
    let duzenle: (UykuDuzenleme) -> Void

    @State private var secili = Calendar.current.startOfDay(for: .now)
    @State private var oneriSirasi = 0

    init(ownerID: String, viewModel: SleepViewModel, duzenle: @escaping (UykuDuzenleme) -> Void) {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date.now.startOfDay) ?? .distantPast
        _kayitlar = Query(filter: #Predicate<SleepEntry> { $0.ownerID == ownerID && $0.day >= since }, sort: \.day, order: .reverse)
        self.viewModel = viewModel
        self.duzenle = duzenle
    }

    private var takvim: Calendar { .current }
    private var gunler: [Date] {
        let bugun = takvim.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { takvim.date(byAdding: .day, value: -$0, to: bugun) }
    }
    private var hedefDk: Int { Int((viewModel.goalHours * 60).rounded()) }

    var body: some View {
        let gun = GunUykusu.grupla(kayitlar, gun: secili)
        let toplam = gun.toplamDakika
        let oran = hedefDk > 0 ? Double(toplam) / Double(hedefDk) : 0
        let haftalik = gunler.map { GunUykusu.grupla(kayitlar, gun: $0) }
        let kayitli = haftalik.filter { $0.toplamDakika > 0 }
        let ortalama = kayitli.isEmpty ? nil : kayitli.reduce(0) { $0 + $1.toplamDakika } / kayitli.count
        let borc = kayitli.reduce(0) { $0 + max(0, hedefDk - $1.toplamDakika) }
        let duzen = SleepAnalyzer.regularity(records: kayitlar.filter { !$0.isNap }.map(\.record))

        ScrollView {
            VStack(spacing: 0) {
                Button { duzenle(UykuDuzenleme(gun: secili)) } label: {
                    UykuAyi(oran: oran)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityLabel("\(gunAdi(secili)) uykularını düzenle")

                sureBasligi(toplam)
                    .padding(.top, 14)
                Text(altSatir(gun, toplam: toplam, oran: oran))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ftTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                if let gece = gun.gece {
                    UykuYildizlari(deger: gece.quality) { q in
                        _ = try? viewModel.save(bedtime: gece.bedtime, wakeTime: gece.wakeTime, quality: q, editing: gece)
                    }
                    .padding(.top, 6)
                }

                UcluMetrik(ogeler: [
                    .init(deger: ortalama.map(UykuBicim.sure) ?? "—", ad: "Ortalama"),
                    .init(deger: duzen.map { "\($0.score)" } ?? "—", birim: duzen == nil ? "" : "/ 100", ad: "Düzen"),
                    .init(deger: kayitli.isEmpty ? "—" : (borc > 0 ? UykuBicim.sure(borc) : "Yok"), ad: "Uyku borcu")
                ])
                .padding(.top, 16)

                oneri
                    .padding(.top, 20)

                BolumBasligi(metin: "Bu Hafta").padding(.top, 26).padding(.bottom, 10)
                GeceSeritleri(
                    satirlar: zip(gunler, haftalik).map { d, g in
                        GeceSeritleri.Satir(id: d, ad: takvim.isDateInToday(d) ? "Bugün" : KlasikTarih.gunKisa(d),
                                            uykular: g.hepsi.map { e in eksen(e) })
                    },
                    secili: secili,
                    ortYatis: duzen.map { ortEksen($0.averageBedtimeMinutes) },
                    ortUyanis: duzen.map { ortEksen($0.averageWakeMinutes) + 1_440 }
                ) { d in
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.25)) { secili = d }
                }
            }
            .padding(.horizontal, Constants.Layout.screenPadding)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func gunAdi(_ d: Date) -> String {
        takvim.isDateInToday(d) ? "Bugün" : takvim.isDateInYesterday(d) ? "Dün" : KlasikTarih.gunKisa(d)
    }

    private func sureBasligi(_ dk: Int) -> some View {
        let h = dk / 60, m = dk % 60
        let buyuk = Font.system(size: 40, weight: .bold), kucuk = Font.system(size: 17)
        var t = Text("")
        if dk == 0 {
            t = Text("—").font(buyuk)
        } else if h == 0 {
            t = Text("\(m)").font(buyuk) + Text(" dk").font(kucuk)
        } else {
            t = Text("\(h)").font(buyuk) + Text(" sa").font(kucuk)
            if m > 0 { t = t + Text(" \(m)").font(buyuk) + Text(" dk").font(kucuk) }
        }
        return t.foregroundStyle(Color.ftText).monospacedDigit().contentTransition(.numericText())
    }

    private func altSatir(_ g: GunUykusu, toplam: Int, oran: Double) -> String {
        guard toplam > 0 else { return "\(gunAdi(secili)) · henüz kayıt yok, aya dokun" }
        var s = gunAdi(secili)
        if let gece = g.gece {
            s += " · \(UykuBicim.saat(SleepAnalyzer.minutesOfDay(gece.bedtime))) – \(UykuBicim.saat(SleepAnalyzer.minutesOfDay(gece.wakeTime)))"
            if !g.sekerlemeler.isEmpty { s += " + \(g.sekerlemeler.count) şekerleme" }
        } else {
            s += " · \(g.sekerlemeler.count) şekerleme"
        }
        return s + " · hedef %\(Int((oran * 100).rounded()))"
    }

    /// Kaydı şerit eksenine çevirir: gece 18:00'den önceki yatışlar ertesi güne kayar.
    private func eksen(_ e: SleepEntry) -> (Int, Int, Bool) {
        let yat = SleepAnalyzer.minutesOfDay(e.bedtime)
        let dk = Int((e.durationHours * 60).rounded())
        let bas = e.isNap ? yat + 1_440 : (yat < 18 * 60 ? yat + 1_440 : yat)
        return (bas, bas + dk, e.isNap)
    }

    private func ortEksen(_ m: Int) -> Int { m < 18 * 60 ? m + 1_440 : m }

    // MARK: Yatış önerisi

    private var oneri: some View {
        let oneriler = viewModel.suggestions
        let onerilen = oneriler.firstIndex { $0.isRecommended } ?? 0
        let i = oneriler.isEmpty ? 0 : (onerilen + oneriSirasi) % oneriler.count
        return Group {
            if oneriler.indices.contains(i) {
                let o = oneriler[i], diger = oneriler[(i + 1) % oneriler.count]
                HStack(spacing: 8) {
                    Image(systemName: "moon.fill").font(.system(size: 13)).foregroundStyle(UykuRenk.acik)
                    (Text("Bu akşam ") + Text(UykuBicim.saatEki(o.bedtimeMinutes)).bold() + Text(" yat")
                     + Text(" · \(o.cycles) döngü").foregroundColor(Color.ftTextSecondary))
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ftText)
                    Spacer()
                    if oneriler.count > 1 {
                        Button {
                            withAnimation { oneriSirasi += 1 }
                        } label: {
                            Text(UykuBicim.saat(diger.bedtimeMinutes))
                                .font(.system(size: 13).monospacedDigit())
                                .foregroundStyle(UykuRenk.koyu)
                                .overlay(alignment: .bottom) {
                                    Rectangle().stroke(style: StrokeStyle(lineWidth: 0.8, dash: [1, 2])).foregroundStyle(UykuRenk.koyu).frame(height: 0.8).offset(y: 3)
                                }
                                .frame(minHeight: 36)
                        }
                        .accessibilityLabel("\(UykuBicim.saat(diger.bedtimeMinutes)), \(diger.cycles) döngü önerisini göster")
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }
}

// MARK: - Kayıt sayfası (kadran)

private struct UykuKayitSayfasi: View {
    let ownerID: String
    let gun: Date
    let yeniEkle: Bool
    let viewModel: SleepViewModel

    private struct Taslak: Identifiable {
        let id = UUID()
        var kayit: SleepEntry?
        var sekerleme: Bool
        var yatis: Int
        var uyanis: Int
        var kalite: Int
    }

    @Environment(\.modelContext) private var context
    @State private var taslaklar: [Taslak] = []
    @State private var secili = 0
    @State private var silinenler: [SleepEntry] = []

    private var baslik: String {
        let t = Calendar.current
        if t.isDateInToday(gun) { return "Bugünün Uykuları" }
        if t.isDateInYesterday(gun) { return "Dünün Uykuları" }
        return "\(KlasikTarih.gunKisa(gun)) Uykuları"
    }

    var body: some View {
        KlasikAyarSayfasi(baslik: baslik, kaydet: kaydet) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(taslaklar.enumerated()), id: \.element.id) { k, t in
                        Button { secili = k } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.sekerleme ? "Şekerleme" : "Gece").font(.system(size: 12))
                                Text("\(UykuBicim.saat(t.yatis))–\(UykuBicim.saat(t.uyanis))").font(.system(size: 15, weight: .bold).monospacedDigit())
                            }
                            .foregroundStyle(k == secili ? Color(hex: "#F7EEDC") : Color.ftText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10).fill(k == secili ? UykuRenk.koyu : Color(hex: "#E5D6B8").opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(k == secili ? [.isSelected] : [])
                    }
                    Button(action: ekle) {
                        VStack(spacing: 1) {
                            Text("+").font(.system(size: 13))
                            Text("Ekle").font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(UykuRenk.koyu)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(UykuRenk.koyu.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Uyku ekle")
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            if taslaklar.indices.contains(secili) {
                UykuKadrani(yatis: $taslaklar[secili].yatis, uyanis: $taslaklar[secili].uyanis,
                            digerleri: taslaklar.enumerated().filter { $0.offset != secili }.map { ($0.element.yatis, $0.element.uyanis) })
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)

                HStack {
                    Label { Text("Yatış ") + Text(UykuBicim.saat(taslaklar[secili].yatis)).bold() } icon: {
                        Circle().fill(UykuRenk.koyu).frame(width: 8, height: 8)
                    }
                    Spacer()
                    Label { Text("Uyanış ") + Text(UykuBicim.saat(taslaklar[secili].uyanis)).bold() } icon: {
                        Circle().fill(UykuRenk.gunesIc).overlay(Circle().stroke(UykuRenk.gunes, lineWidth: 0.6)).frame(width: 8, height: 8)
                    }
                }
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(Color.ftText)
                .padding(.horizontal, 24)
                .padding(.top, 14)

                AyarSatiri(baslik: "Kalite") {
                    UykuYildizlari(deger: taslaklar[secili].kalite, boy: 20) { taslaklar[secili].kalite = $0 }
                }
                .padding(.top, 10)
                FircaAyirici(tohum: 451)
                AyarSatiri(baslik: "Günün toplamı") {
                    Text(UykuBicim.sure(taslaklar.reduce(0) { $0 + ((($1.uyanis - $1.yatis) % 1_440) + 1_440) % 1_440 }))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.ftText)
                }
                if taslaklar[secili].kayit != nil || taslaklar[secili].sekerleme {
                    Button("Bu uykuyu sil", role: .destructive, action: sil)
                        .font(.system(size: 15))
                        .padding(.top, 8)
                }
            }
        }
        .onAppear(perform: hazirla)
    }

    private func hazirla() {
        guard taslaklar.isEmpty else { return }
        let sahip = ownerID
        let gunKayitlari = (try? context.fetch(FetchDescriptor<SleepEntry>(predicate: #Predicate { $0.ownerID == sahip }))) ?? []
        let g = GunUykusu.grupla(gunKayitlari, gun: gun)
        let dk: (Date) -> Int = { SleepAnalyzer.minutesOfDay($0) }
        if let gece = g.gece {
            taslaklar.append(Taslak(kayit: gece, sekerleme: false, yatis: dk(gece.bedtime), uyanis: dk(gece.wakeTime), kalite: gece.quality))
        } else {
            let uyanis = viewModel.settings.targetWakeMinutes
            taslaklar.append(Taslak(kayit: nil, sekerleme: false, yatis: viewModel.recommendedBedtimeMinutes, uyanis: uyanis, kalite: 3))
        }
        for s in g.sekerlemeler {
            taslaklar.append(Taslak(kayit: s, sekerleme: true, yatis: dk(s.bedtime), uyanis: dk(s.wakeTime), kalite: s.quality))
        }
        if yeniEkle && g.gece != nil { ekle() }
    }

    private func ekle() {
        let son = taslaklar.last
        let bas = taslaklar.count <= 1 ? 14 * 60 : ((son?.uyanis ?? 12 * 60) + 120) % 1_440
        taslaklar.append(Taslak(kayit: nil, sekerleme: true, yatis: bas, uyanis: (bas + 30) % 1_440, kalite: 3))
        secili = taslaklar.count - 1
    }

    private func sil() {
        let t = taslaklar.remove(at: secili)
        if let k = t.kayit { silinenler.append(k) }
        if taslaklar.isEmpty {
            taslaklar.append(Taslak(kayit: nil, sekerleme: false, yatis: viewModel.recommendedBedtimeMinutes, uyanis: viewModel.settings.targetWakeMinutes, kalite: 3))
        }
        secili = 0
    }

    private func kaydet() {
        silinenler.forEach { viewModel.delete($0) }
        for t in taslaklar {
            let (yat, uyan) = SleepViewModel.resolve(bedtimeMinutes: t.yatis, wakeMinutes: t.uyanis, wakeDay: gun)
            do {
                _ = try viewModel.save(bedtime: yat, wakeTime: uyan, quality: t.kalite, editing: t.kayit, nap: t.sekerleme)
            } catch {
                viewModel.errorMessage = AppError.map(error).errorDescription
            }
        }
    }
}

// MARK: - Ayarlar

private struct UykuAyarSayfasi: View {
    let viewModel: SleepViewModel
    let hedefDegisti: (Double) -> Void

    @State private var hedefDk = 480
    @State private var taslak = SleepSettings()

    var body: some View {
        KlasikAyarSayfasi(baslik: "Uyku Ayarları", kaydet: kaydet) {
            HedefSatiri(deger: UykuBicim.sure(hedefDk), birim: "",
                        azalt: { hedefDk = max(Int(SleepViewModel.goalRange.lowerBound * 60), hedefDk - 15) },
                        artir: { hedefDk = min(Int(SleepViewModel.goalRange.upperBound * 60), hedefDk + 15) })
            FircaAyirici(tohum: 411)
            AyarSecimSatiri(baslik: "Uyanış saati", secenekler: (0...20).map { (300 + $0 * 15, UykuBicim.saat(300 + $0 * 15)) },
                            secili: $taslak.targetWakeMinutes)
            HStack {
                AyarBolumu(metin: "Yatış hatırlatıcısı")
                Spacer()
                Toggle("Yatış hatırlatıcısı", isOn: $taslak.reminderEnabled)
                    .labelsHidden()
                    .tint(UykuRenk.koyu)
            }
            AyarSecimSatiri(baslik: "Zaman", secenekler: [(0, "Tam saatinde"), (15, "15 dk önce"), (30, "30 dk önce"), (60, "1 saat önce")],
                            secili: $taslak.reminderLeadMinutes)
                .opacity(taslak.reminderEnabled ? 1 : 0.45)
                .disabled(!taslak.reminderEnabled)
        }
        .onAppear {
            hedefDk = Int((viewModel.goalHours * 60).rounded())
            taslak = viewModel.settings
            // Seçicide olmayan bir uyanış saati varsa en yakın çeyreğe yuvarla
            taslak.targetWakeMinutes = min(600, max(300, (taslak.targetWakeMinutes + 7) / 15 * 15))
        }
    }

    private func kaydet() {
        let saat = Double(hedefDk) / 60
        if abs(saat - viewModel.goalHours) > 0.001 { hedefDegisti(saat) }
        let yeni = taslak
        Task {
            let ok = await viewModel.applySettings(yeni)
            if !ok && yeni.reminderEnabled {
                viewModel.errorMessage = "Bildirim izni kapalı. Ayarlar > FarvaTrack > Bildirimler'den açabilirsin."
            }
        }
    }
}
