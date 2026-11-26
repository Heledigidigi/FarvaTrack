import SwiftUI

// Özet'ten açılan ekranların (Adım, Su, Uyku, Kilo, Kaka, İstatistik) ortak parçaları.
// Kart yok: çizimler doğrudan kâğıt zeminde, `murekkepGolgesi()` ile gölgeli.
// Önizleme: https://claude.ai/artifact/PC1Mi5cJVdGqWfKX3hTJyR

enum KlasikRenk {
    static let murekkep = Color(hex: "#3E2A1C")
    static let ikincil = Color(hex: "#7A5C44")
    static let soluk = Color(hex: "#8A7458")
    static let vurgu = Color(hex: "#A23A2E")
    static let kontur = Color(hex: "#6B4E36")
    static let eksen = Color(hex: "#8A6E52")
    static let hedefCizgisi = Color(hex: "#B49870")
    static let bosNokta = Color(hex: "#C9AE80")
    static let yesil = Color(hex: "#4E6A4A")
}

// MARK: - Ekran iskeleti

extension View {
    /// Kâğıt zeminli, ortada başlıklı, sağ üstte isteğe bağlı düğmeli ekran.
    /// Sistem gezinme çubuğu kalır (kenardan kaydırarak geri dönülsün diye), yalnızca saydamdır.
    func klasikEkran<Sag: View>(_ baslik: String, @ViewBuilder sag: () -> Sag) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ftScreenBackground()
            .navigationTitle(baslik)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { sag() } }
            .tint(KlasikRenk.vurgu)
    }

    func klasikEkran(_ baslik: String) -> some View {
        klasikEkran(baslik) { EmptyView() }
    }
}

/// Sağ üstteki ayar (sürgü) simgesi.
struct AyarSimgesi: View {
    var body: some View {
        Canvas { ctx, _ in
            for y in [7.0, 12.0, 17.0] {
                var p = Path()
                p.move(to: CGPoint(x: 4, y: y))
                p.addLine(to: CGPoint(x: 20, y: y))
                ctx.stroke(p, with: .color(KlasikRenk.vurgu), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            for (x, y) in [(15.0, 7.0), (8.5, 12.0), (13.0, 17.0)] {
                let d = Path(ellipseIn: CGRect(x: x - 2.2, y: y - 2.2, width: 4.4, height: 4.4))
                ctx.fill(d, with: .color(Color(hex: "#EFE2C6")))
                ctx.stroke(d, with: .color(KlasikRenk.vurgu), lineWidth: 1.6)
            }
        }
        .frame(width: 24, height: 24)
    }
}

struct AyarDugmesi: View {
    let etiket: String
    let eylem: () -> Void
    var body: some View {
        Button(action: eylem) { AyarSimgesi() }
            .accessibilityLabel(etiket)
    }
}

/// Sağ üstteki "+" (kayıt ekle) simgesi.
struct EkleDugmesi: View {
    let etiket: String
    let eylem: () -> Void
    var body: some View {
        Button(action: eylem) {
            Image(systemName: "plus").font(.system(size: 17, weight: .medium)).foregroundStyle(KlasikRenk.vurgu)
        }
        .accessibilityLabel(etiket)
    }
}

// MARK: - Metin parçaları

struct BolumBasligi: View {
    let metin: String
    var body: some View {
        Text(metin)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.ftText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// "6.240 adım" gibi: değer kalın, birim küçük ve ikincil.
struct DegerBirim: View {
    let deger: String
    var birim: String = ""
    var boy: CGFloat = 19
    var body: some View {
        (Text(deger).font(.system(size: boy, weight: .bold)).foregroundColor(Color.ftText)
         + Text(birim.isEmpty ? "" : " \(birim)").font(.system(size: 12, weight: .medium)).foregroundColor(Color.ftTextSecondary))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Üç sütunlu sayı satırı (değer + birim, altında ad).
struct UcluMetrik: View {
    struct Oge: Identifiable {
        let id = UUID()
        var deger: String
        var birim: String = ""
        var ad: String
        var simge: AnyView? = nil
    }
    let ogeler: [Oge]
    var boy: CGFloat = 17

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(ogeler) { o in
                VStack(spacing: 3) {
                    if let s = o.simge { s.frame(height: 28).padding(.bottom, 3) }
                    DegerBirim(deger: o.deger, birim: o.birim, boy: boy)
                    Text(o.ad).font(.system(size: 12)).foregroundStyle(Color.ftTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(o.ad): \(o.deger) \(o.birim)")
            }
        }
    }
}

/// Altı çizili küçük sekmeler (7 gün / Aylık, Hafta / Ay…).
struct KlasikSekmeler<Deger: Hashable>: View {
    let secenekler: [(Deger, String)]
    @Binding var secili: Deger
    var renk: Color = KlasikRenk.yesil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(secenekler, id: \.0) { s in
                let acik = s.0 == secili
                Button {
                    guard !acik else { return }
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.2)) { secili = s.0 }
                } label: {
                    Text(s.1)
                        .font(.system(size: 13, weight: acik ? .bold : .regular))
                        .foregroundStyle(acik ? Color.ftText : KlasikRenk.eksen)
                        .frame(minWidth: 36, minHeight: 32)
                        .padding(.horizontal, 4)
                        .overlay(alignment: .bottom) {
                            if acik {
                                Capsule().fill(renk).frame(height: 1.5).padding(.horizontal, 10).padding(.bottom, 4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(acik ? [.isSelected] : [])
            }
        }
    }
}

/// İnce fırça ayırıcı.
struct FircaAyirici: View {
    var tohum = 1
    var body: some View {
        FircaCizgiSekli(kalinlik: 0.8, tohum: tohum)
            .fill(KlasikRenk.soluk.opacity(0.45))
            .frame(height: 4)
            .accessibilityHidden(true)
    }
}

// MARK: - Ayar sayfası

/// Alttan açılan kâğıt ayar sayfası: Vazgeç · başlık · Kaydet.
struct KlasikAyarSayfasi<Icerik: View>: View {
    let baslik: String
    var kaydetEtkin = true
    var kaydetYazisi = "Kaydet"
    let kaydet: () -> Void
    @ViewBuilder var icerik: () -> Icerik
    @Environment(\.dismiss) private var kapat

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Vazgeç") { kapat() }
                    .frame(minWidth: 70, alignment: .leading)
                Spacer()
                Text(baslik).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ftText)
                Spacer()
                Button(kaydetYazisi) {
                    kaydet()
                    kapat()
                }
                .fontWeight(.semibold)
                .disabled(!kaydetEtkin)
                .frame(minWidth: 70, alignment: .trailing)
            }
            .font(.system(size: 17))
            .foregroundStyle(KlasikRenk.vurgu)
            .padding(.horizontal, 20)
            .frame(height: 58)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { icerik() }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .tint(KlasikRenk.vurgu)
        .presentationDragIndicator(.visible)
        .presentationBackground { ThemeBackground() }
    }
}

struct AyarSatiri<Sag: View>: View {
    let baslik: String
    @ViewBuilder var sag: () -> Sag
    var body: some View {
        HStack {
            Text(baslik).foregroundStyle(Color.ftText)
            Spacer(minLength: 12)
            sag()
        }
        .font(.system(size: 16))
        .frame(minHeight: 46)
    }
}

struct AyarBolumu: View {
    let metin: String
    var body: some View {
        Text(metin)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.ftText)
            .padding(.top, 24)
            .padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Elle çizilmiş küçük ± düğmesi; basılı tutunca hızlanarak tekrarlar.
struct MinikDugme: View {
    let arti: Bool
    var tohum = 201
    let eylem: () -> Void
    @State private var gorev: Task<Void, Never>?
    @State private var basili = false

    var body: some View {
        ZStack {
            FircaCemberSekli(kalinlik: 1, tohum: tohum).fill(KlasikRenk.kontur)
            FircaCizgiSekli(kalinlik: 1.4, tohum: tohum).fill(KlasikRenk.murekkep).frame(width: 10, height: 4)
            if arti {
                FircaCizgiSekli(kalinlik: 1.4, tohum: tohum + 1).fill(KlasikRenk.murekkep).frame(width: 10, height: 4).rotationEffect(.degrees(90))
            }
        }
        .frame(width: 26, height: 26)
        .frame(width: 36, height: 44)
        .contentShape(Rectangle())
        .scaleEffect(basili ? 0.88 : 1)
        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 30, perform: {}, onPressingChanged: { b in
            basili = b
            gorev?.cancel()
            guard b else { return }
            eylem()
            Haptics.selection()
            gorev = Task { @MainActor in
                var aralik = 0.4
                while true {
                    do { try await Task.sleep(for: .seconds(aralik)) } catch { return }
                    eylem()
                    aralik = max(0.06, aralik * 0.8)
                }
            }
        })
        .accessibilityElement()
        .accessibilityLabel(arti ? "Artır" : "Azalt")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { eylem() }
    }
}

/// "Günlük hedef  ⊖ 8.000 adım ⊕" satırı.
struct HedefSatiri: View {
    var baslik = "Günlük hedef"
    let deger: String
    let birim: String
    let azalt: () -> Void
    let artir: () -> Void

    var body: some View {
        AyarSatiri(baslik: baslik) {
            HStack(spacing: 2) {
                MinikDugme(arti: false, eylem: azalt)
                (Text(deger).font(.system(size: 17, weight: .bold)).foregroundColor(Color.ftText)
                 + Text(" \(birim)").font(.system(size: 16)).foregroundColor(Color.ftTextSecondary))
                    .monospacedDigit()
                    .frame(minWidth: 96)
                    .contentTransition(.numericText())
                MinikDugme(arti: true, tohum: 204, eylem: artir)
            }
            .padding(.trailing, -6)
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(deger) \(birim)")
            .accessibilityAdjustableAction { yon in
                switch yon {
                case .increment: artir()
                case .decrement: azalt()
                @unknown default: break
                }
            }
        }
    }
}

/// Sağda değeri, yanında küçük oku olan seçici satırı.
struct AyarSecimSatiri<Deger: Hashable>: View {
    let baslik: String
    let secenekler: [(Deger, String)]
    @Binding var secili: Deger

    var body: some View {
        AyarSatiri(baslik: baslik) {
            Menu {
                Picker(baslik, selection: $secili) {
                    ForEach(secenekler, id: \.0) { Text($0.1).tag($0.0) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(secenekler.first { $0.0 == secili }?.1 ?? "").foregroundStyle(Color.ftText)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(KlasikRenk.soluk)
                }
            }
        }
    }
}

/// Altı fırça çizgili sayı girişi.
struct AyarSayiGirisi: View {
    let baslik: String
    @Binding var deger: Int?
    var renk: Color = Color(hex: "#A8584C")
    var genislik: CGFloat = 86

    var body: some View {
        AyarSatiri(baslik: baslik) {
            TextField("0", value: $deger, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 19, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.ftText)
                .frame(width: genislik)
                .overlay(alignment: .bottom) {
                    FircaCizgiSekli(kalinlik: 1, tohum: 231).fill(renk).frame(height: 4).offset(y: 6)
                }
                .accessibilityLabel(baslik)
        }
    }
}

// MARK: - Grafik yardımcıları

/// Gün kısaltmaları (Pazartesi = 0).
enum KlasikTarih {
    static let gunler = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]
    static let aylar = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]

    static func gunKisa(_ tarih: Date, takvim: Calendar = .current) -> String {
        gunler[(takvim.component(.weekday, from: tarih) + 5) % 7]
    }

    static func ayKisa(_ tarih: Date, takvim: Calendar = .current) -> String {
        String(aylar[takvim.component(.month, from: tarih) - 1].prefix(3))
    }
}

/// Gün ekseni etiketi: bugün vurgulu.
struct EksenEtiketi: View {
    let metin: String
    var bugun = false
    var body: some View {
        Text(metin)
            .font(.system(size: 10, weight: bugun ? .bold : .regular))
            .foregroundStyle(bugun ? KlasikRenk.vurgu : KlasikRenk.eksen)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Fırça halkası (büyük gösterge)

/// İlerleme kadar çekilmiş fırça halkası; ilerleme değişince akarak uzar.
struct EnsoSekli: Shape {
    var ilerleme: Double
    var kalinlik: Double = 7
    var tohum = 1

    var animatableData: Double {
        get { ilerleme }
        set { ilerleme = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2 - CGFloat(kalinlik) - 4
        return Firca.halka(merkez: CGPoint(x: rect.midX, y: rect.midY), r: r, ilerleme: ilerleme,
                           o: Firca.Ayar(w: kalinlik, tohum: tohum))
    }
}

/// Soluk kılavuz çember + fırça halkası.
struct EnsoGosterge: View {
    let ilerleme: Double
    var renk: Color = Color(hex: "#A8584C")
    var boy: CGFloat = 214
    var kalinlik: Double = 7

    var body: some View {
        ZStack {
            Circle()
                .stroke(KlasikRenk.soluk.opacity(0.22), lineWidth: 0.5)
                .padding(CGFloat(kalinlik) + 4)
            EnsoSekli(ilerleme: ilerleme, kalinlik: kalinlik)
                .fill(renk.opacity(0.85))
                .murekkepGolgesi(hafif: true)
        }
        .frame(width: boy, height: boy)
        .accessibilityHidden(true)
    }
}
