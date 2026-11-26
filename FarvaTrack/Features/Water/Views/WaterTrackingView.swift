import SwiftUI
import SwiftData
import WidgetKit

/// Su ekranı (klasik tasarım): widget'taki Damla maskotu (dokun = ekle, basılı tut = miktar seç),
/// telefonun eğimiyle dalgalanan su, son 7 günün tüpleri ve bugünkü kayıtlar.
/// Hedef, dokununca eklenecek miktar, maskot ve hatırlatıcılar sağ üstteki ayar sayfasında.
struct WaterTrackingView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(WaterViewModel.self) private var viewModel

    /// Özet'in gezinme yığınından açıldığında kendi `NavigationStack`'ini kurmaz.
    var embedsNavigation = true

    @State private var ayarAcik = false

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    var body: some View {
        OptionalNavigationStack(enabled: embedsNavigation) {
            Group {
                if let user = auth.currentUser {
                    SuIcerigi(ownerID: user.id, viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .klasikEkran("Su") {
                AyarDugmesi(etiket: "Su ayarları") { ayarAcik = true }
            }
            .onAppear { viewModel.reloadReminderSettings() }
            .sheet(isPresented: $ayarAcik) {
                SuAyarSayfasi(viewModel: viewModel) { yeniHedef in
                    guard var user = auth.currentUser else { return }
                    user.dailyWaterGoalMl = yeniHedef
                    Task { await auth.updateUser(user) }
                }
            }
            .alert("Bir sorun oluştu", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

// MARK: - Maskot seçimi

enum SuMaskotu {
    static let anahtar = "water.mascot"
    static let miktarAnahtari = "water.tapAmount"
    static let widget = "widget"

    /// Kayıtlı seçimden tema; "widget" ise ana ekrandaki Damla widget'ının teması (yoksa Krem).
    static func tema(_ secim: String, widgetTemasi: WaterThemeOption?) -> (DropTheme, WaterThemeOption) {
        let secenek = secim == widget ? (widgetTemasi ?? .krem) : (WaterThemeOption(rawValue: secim) ?? .krem)
        return (DropTheme.make(secenek), secenek)
    }

    /// Ana ekrandaki ilk Damla widget'ının teması.
    static func widgetTemasi() async -> WaterThemeOption? {
        await withCheckedContinuation { devam in
            WidgetCenter.shared.getCurrentConfigurations { sonuc in
                let tema = (try? sonuc.get())?.first { $0.kind == SharedStore.waterWidgetKind }?
                    .widgetConfigurationIntent(of: WaterWidgetConfig.self)?.theme
                devam.resume(returning: tema)
            }
        }
    }

    static let adlar: [WaterThemeOption: String] = [
        .krem: "Krem", .pamukPembe: "Pamuk pembe", .nane: "Nane", .lavanta: "Lavanta", .gece: "Gece", .bordo: "Bordo",
        .safak: "Şafak", .okyanus: "Okyanus", .lavantaSisi: "Lavanta sisi", .gunBatimi: "Gün batımı", .nostalji: "Nostalji", .kedi: "Kedi"
    ]
    static let sira: [WaterThemeOption] = [.krem, .pamukPembe, .nane, .lavanta, .gece, .bordo, .safak, .okyanus, .lavantaSisi, .gunBatimi, .nostalji, .kedi]
}

// MARK: - İçerik (@Query burada: son 7 gün)

private struct SuIcerigi: View {
    @Query private var entries: [WaterEntry]
    let viewModel: WaterViewModel

    @AppStorage(SuMaskotu.anahtar) private var maskot = SuMaskotu.widget
    @AppStorage(SuMaskotu.miktarAnahtari) private var dokunMiktar = 250
    @State private var widgetTemasi: WaterThemeOption?
    @State private var egim = SuEgimi()
    @State private var zipla = 0
    @State private var miktarMenusu = false
    @State private var silinecek: UUID?
    @State private var tumu = false
    @Environment(\.scenePhase) private var sahne

    init(ownerID: String, viewModel: WaterViewModel) {
        let since = Calendar.current.date(byAdding: .day, value: -6, to: Date.now.startOfDay) ?? .distantPast
        _entries = Query(filter: #Predicate<WaterEntry> { $0.ownerID == ownerID && $0.date >= since }, sort: \.date)
        self.viewModel = viewModel
    }

    private var bugunkuler: [WaterEntry] { entries.filter { Calendar.current.isDateInToday($0.date) } }

    var body: some View {
        let toplam = bugunkuler.reduce(0) { $0 + $1.amountMl }
        let hedef = viewModel.goalMl
        let secim = SuMaskotu.tema(maskot, widgetTemasi: widgetTemasi)
        let tema = secim.0, secenek = secim.1

        ScrollView {
            VStack(spacing: 0) {
                if !SharedStore.isSharedContainerAvailable {
                    WidgetSyncNotice().padding(.bottom, 8)
                }
                damla(toplam: toplam, hedef: hedef, tema: tema)

                (Text(toplam.formatted()).font(.system(size: 40, weight: .bold)).foregroundColor(Color.ftText)
                 + Text(" / \(hedef.formatted()) ml").font(.system(size: 15)).foregroundColor(Color.ftTextSecondary))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.top, 6)
                    .accessibilityLabel("Bugün \(toplam) mililitre, hedef \(hedef)")

                kalanSatiri(toplam: toplam, hedef: hedef)
                    .padding(.top, 10)

                if toplam >= 4_000 && Double(toplam) >= Double(hedef) * 1.5 {
                    Text("Bugün hedefinin çok üzerindesin; susamıyorsan ara verebilirsin.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ftWarning)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }

                BolumBasligi(metin: "Son 7 Gün").padding(.top, 26).padding(.bottom, 10)
                SuTupleri(gunler: WaterViewModel.dailyTotals(entries: entries), hedef: hedef,
                          egim: egim.aci, calkanti: egim.calkanti, nostalji: secenek == .nostalji)

                kayitlar
            }
            .padding(.horizontal, Constants.Layout.screenPadding)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .simultaneousGesture(TapGesture().onEnded { silinecek = nil })
        .overlay {
            if miktarMenusu {
                MiktarMenusu(kapat: { miktarMenusu = false }) { ml in
                    miktarMenusu = false
                    ekle(ml)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: miktarMenusu)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.undoToken)
        .sensoryFeedback(.success, trigger: toplam >= hedef) { old, new in !old && new }
        .task { widgetTemasi = await SuMaskotu.widgetTemasi() }
        .onAppear { egim.baslat() }
        .onDisappear { egim.durdur() }
        .onChange(of: sahne) { _, s in
            if s == .active { egim.baslat() } else { egim.durdur() }
        }
    }

    // MARK: Damla

    private func damla(toplam: Int, hedef: Int, tema: DropTheme) -> some View {
        let boy: CGFloat = 206, o = boy / 170
        let alan = tema.isCat ? CGRect(x: 44, y: 32, width: 82, height: 118) : CGRect(x: 48, y: 36, width: 74, height: 107)
        return CanliDamla(toplam: toplam, hedef: hedef, tema: tema, egim: egim.aci, calkanti: egim.calkanti, zipla: zipla)
            .frame(width: boy, height: boy)
            .overlay(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: alan.width * o, height: alan.height * o)
                    .offset(x: alan.minX * o, y: alan.minY * o)
                    .onTapGesture { ekle(dokunMiktar) }
                    .onLongPressGesture(minimumDuration: 0.46) {
                        Haptics.impact(.light)
                        miktarMenusu = true
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(tema.isCat ? "Kedi" : "Damla"), \(DropMood(total: toplam, goal: hedef).label)")
                    .accessibilityHint("Dokun: \(dokunMiktar) mililitre ekle. Basılı tut: miktar seç.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { ekle(dokunMiktar) }
                    .accessibilityAction(named: "Miktar seç") { miktarMenusu = true }
            }
            .frame(maxWidth: .infinity)
    }

    private func ekle(_ ml: Int) {
        do {
            try viewModel.add(amountMl: ml)
            zipla += 1
            Haptics.impact(.light)
        } catch {
            viewModel.errorMessage = AppError.map(error).errorDescription
        }
    }

    @ViewBuilder
    private func kalanSatiri(toplam: Int, hedef: Int) -> some View {
        Group {
            if let fis = viewModel.undoToken {
                HStack(spacing: 6) {
                    Text("+\(fis.amountMl) ml eklendi")
                    Button("Geri al") { viewModel.undo() }
                        .fontWeight(.bold)
                        .foregroundStyle(KlasikRenk.vurgu)
                        .frame(minHeight: 32)
                }
                .transition(.opacity)
            } else if toplam < hedef {
                Text("Hedefini tamamlamana ") + Text((hedef - toplam).formatted()).bold() + Text(" ml kaldı")
            } else {
                Text("Hedefini ") + Text("tamamladın").bold()
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(Color(hex: "#4A3324"))
        .frame(minHeight: 32)
    }

    // MARK: Bugünkü kayıtlar

    private var kayitlar: some View {
        let hepsi = bugunkuler
        let gosterilen = tumu ? hepsi : Array(hepsi.suffix(6))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                BolumBasligi(metin: "Bugün")
                if hepsi.count > 6 {
                    Button(tumu ? "Daha az" : "Tümü (\(hepsi.count))") { withAnimation { tumu.toggle() } }
                        .font(.system(size: 13))
                        .foregroundStyle(KlasikRenk.vurgu)
                        .fixedSize()
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 6)

            if hepsi.isEmpty {
                Text("Henüz su yok. Damla susadı.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ftTextSecondary)
                    .padding(.top, 6)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 40), GridItem(.flexible())], spacing: 0) {
                    ForEach(gosterilen) { kayit in
                        kayitSatiri(kayit)
                    }
                }
            }
        }
    }

    private func kayitSatiri(_ kayit: WaterEntry) -> some View {
        let sil = silinecek == kayit.id
        return Button {
            if sil {
                viewModel.delete(kayit)
                silinecek = nil
                Haptics.impact(.light)
            } else {
                silinecek = kayit.id
            }
        } label: {
            VStack(spacing: 0) {
                HStack {
                    Text(kayit.date.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(Color.ftTextSecondary)
                    Spacer()
                    if sil {
                        Text("Sil").fontWeight(.bold).foregroundStyle(KlasikRenk.vurgu)
                    } else {
                        Text("\(kayit.amountMl) ml").fontWeight(.bold).foregroundStyle(Color.ftText)
                    }
                }
                .font(.system(size: 15).monospacedDigit())
                .frame(height: 44)
                FircaAyirici(tohum: kayit.amountMl)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kayit.date.formatted(date: .omitted, time: .shortened)), \(kayit.amountMl) mililitre")
        .accessibilityHint(sil ? "Silmek için tekrar dokun" : "Silmek için iki kez dokun")
    }
}

// MARK: - Basılı tutunca: miktar seç

private struct MiktarMenusu: View {
    let kapat: () -> Void
    let sec: (Int) -> Void
    @State private var ozel: Int?
    @State private var uyari = false

    var body: some View {
        ZStack {
            Color(hex: "#1E150E").opacity(0.25).ignoresSafeArea().onTapGesture(perform: kapat)
            VStack(spacing: 14) {
                Text("Ne kadar içtin?").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.ftText)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach([100, 150, 200, 250, 330, 500], id: \.self) { ml in
                        Button { sec(ml) } label: {
                            Text("\(ml)")
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.ftText)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Capsule().stroke(KlasikRenk.kontur.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(ml) mililitre")
                    }
                }
                HStack(spacing: 8) {
                    TextField("Başka", value: $ozel, format: .number)
                        .keyboardType(.numberPad)
                        .font(.system(size: 15).monospacedDigit())
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(Capsule().stroke(KlasikRenk.kontur.opacity(0.35), lineWidth: 1))
                        .accessibilityLabel("Özel miktar, mililitre")
                    Text("ml").foregroundStyle(Color.ftTextSecondary)
                    Button("Ekle") {
                        if let ozel, WaterViewModel.customRange.contains(ozel) { sec(ozel) } else { uyari = true }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(KlasikRenk.vurgu)
                }
                if uyari {
                    Text("\(WaterViewModel.customRange.lowerBound) ile \(WaterViewModel.customRange.upperBound.formatted()) ml arasında bir miktar yaz")
                        .font(.system(size: 12))
                        .foregroundStyle(KlasikRenk.vurgu)
                }
            }
            .padding(20)
            .frame(width: 300)
            .background(Color(hex: "#F4E8D0"), in: RoundedRectangle(cornerRadius: 4))
            .shadow(color: OzetRenk.golge.opacity(0.3), radius: 1, x: 1, y: 2)
            .shadow(color: OzetRenk.golge.opacity(0.32), radius: 14, x: 4, y: 9)
            .rotationEffect(.degrees(-0.6))
        }
    }
}

// MARK: - Ayar sayfası

private struct SuAyarSayfasi: View {
    let viewModel: WaterViewModel
    let hedefKaydet: (Int) -> Void

    @AppStorage(SuMaskotu.anahtar) private var maskot = SuMaskotu.widget
    @AppStorage(SuMaskotu.miktarAnahtari) private var dokunMiktar = 250
    @State private var hedef = 2_000
    @State private var miktar = 250
    @State private var secim = SuMaskotu.widget
    @State private var taslak = WaterReminderSettings()
    @State private var widgetTemasi: WaterThemeOption?

    var body: some View {
        KlasikAyarSayfasi(baslik: "Su Ayarları", kaydet: kaydet) {
            HedefSatiri(deger: hedef.formatted(), birim: "ml",
                        azalt: { hedef = max(WaterViewModel.goalRange.lowerBound, hedef - 100) },
                        artir: { hedef = min(WaterViewModel.goalRange.upperBound, hedef + 100) })
            FircaAyirici(tohum: 311)
            AyarSatiri(baslik: "Dokununca") {
                HStack(spacing: 0) {
                    ForEach([100, 150, 200, 250, 330, 500], id: \.self) { ml in
                        let acik = ml == miktar
                        Button { miktar = ml } label: {
                            Text("\(ml)")
                                .font(.system(size: 15, weight: acik ? .bold : .regular).monospacedDigit())
                                .foregroundStyle(acik ? Color.ftText : KlasikRenk.eksen)
                                .frame(minWidth: 34, minHeight: 40)
                                .overlay(alignment: .bottom) {
                                    if acik { FircaCizgiSekli(kalinlik: 1.6, tohum: ml).fill(Color(hex: "#6E8E92")).frame(width: 22, height: 4).offset(y: -4) }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(ml) mililitre")
                        .accessibilityAddTraits(acik ? [.isSelected] : [])
                    }
                    Text("ml").font(.system(size: 12)).foregroundStyle(Color.ftTextSecondary).padding(.leading, 2)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                AyarBolumu(metin: "Maskot")
                Spacer()
                Text(secim == SuMaskotu.widget
                     ? "Widget’la aynı · \(SuMaskotu.adlar[widgetTemasi ?? .krem] ?? "")"
                     : SuMaskotu.adlar[WaterThemeOption(rawValue: secim) ?? .krem] ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ftTextSecondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(42), spacing: 8), count: 7), alignment: .leading, spacing: 8) {
                maskotKutusu(SuMaskotu.widget, secenek: widgetTemasi ?? .krem, ad: "Widget’la aynı", rozet: true)
                ForEach(SuMaskotu.sira, id: \.self) { s in
                    maskotKutusu(s.rawValue, secenek: s, ad: SuMaskotu.adlar[s] ?? "")
                }
            }

            HStack {
                AyarBolumu(metin: "Hatırlatıcılar")
                Spacer()
                Toggle("Hatırlatıcılar", isOn: $taslak.isEnabled)
                    .labelsHidden()
                    .tint(Color(hex: "#6E8E92"))
            }
            Group {
                AyarSecimSatiri(baslik: "Sıklık", secenekler: [(60, "1 saatte bir"), (90, "1,5 saatte bir"), (120, "2 saatte bir"), (180, "3 saatte bir")],
                                secili: $taslak.intervalMinutes)
                FircaAyirici(tohum: 321)
                AyarSecimSatiri(baslik: "Başlangıç", secenekler: (5...12).map { ($0, String(format: "%02d:00", $0)) }, secili: $taslak.startHour)
                FircaAyirici(tohum: 322)
                AyarSecimSatiri(baslik: "Bitiş", secenekler: (18...23).map { ($0, String(format: "%02d:00", $0)) }, secili: $taslak.endHour)
            }
            .opacity(taslak.isEnabled ? 1 : 0.45)
            .disabled(!taslak.isEnabled)

        }
        .onAppear {
            hedef = viewModel.goalMl
            miktar = dokunMiktar
            secim = maskot
            taslak = viewModel.reminderSettings
        }
        .task { widgetTemasi = await SuMaskotu.widgetTemasi() }
    }

    private func maskotKutusu(_ anahtar: String, secenek: WaterThemeOption, ad: String, rozet: Bool = false) -> some View {
        let tema = DropTheme.make(secenek)
        let acik = secim == anahtar
        return Button { secim = anahtar } label: {
            ZStack(alignment: .topTrailing) {
                tema.fill.view
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        DropArt(total: 1400, goal: 2300, theme: tema).frame(width: 34, height: 34)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(acik ? KlasikRenk.vurgu : KlasikRenk.kontur.opacity(0.25), lineWidth: acik ? 2 : 0.8))
                if rozet {
                    Text("W").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 14, height: 14).background(KlasikRenk.vurgu, in: Circle()).offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ad)
        .accessibilityAddTraits(acik ? [.isSelected] : [])
    }

    private func kaydet() {
        if hedef != viewModel.goalMl { hedefKaydet(hedef) }
        dokunMiktar = miktar
        maskot = secim
        if taslak != viewModel.reminderSettings {
            let yeni = taslak
            Task {
                let ok = await viewModel.applyReminders(yeni)
                if !ok && yeni.isEnabled { viewModel.errorMessage = "Bildirim izni kapalı. Hatırlatıcı için iPhone Ayarları → FarvaTrack → Bildirimler bölümünden izin ver." }
            }
        }
    }
}

/// İstenirse içeriği kendi `NavigationStack`'ine sarar; başka bir yığının içinde açılırken sarmaz.
struct OptionalNavigationStack<Content: View>: View {
    let enabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if enabled {
            NavigationStack { content() }
        } else {
            content()
        }
    }
}
