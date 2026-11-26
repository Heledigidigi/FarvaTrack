import SwiftUI

/// Adım ekranı (klasik tasarım): fırça halkası, kalan cümlesi, üç simgeli sayı ve son 7 günün çiçekleri.
/// Hedef, elle giriş ve Apple Sağlık bağlantısı sağ üstteki ayar sayfasında.
struct StepsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = StepsViewModel()
    @State private var ayarAcik = false

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    var body: some View {
        ScrollView {
            icerik
                .padding(.horizontal, Constants.Layout.screenPadding)
                .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .klasikEkran("Adımlar") {
            AyarDugmesi(etiket: "Adım ayarları") { ayarAcik = true }
        }
        .sheet(isPresented: $ayarAcik) {
            AdimAyarSayfasi(viewModel: viewModel)
        }
        .task {
            if let user = auth.currentUser { viewModel.attach(context: modelContext, userID: user.id) }
            await viewModel.start()
            await viewModel.syncManual()
        }
        .onChange(of: auth.currentUser, initial: true) { _, user in
            if let user { viewModel.configure(user: user) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await viewModel.start() }   // gün değişimi veya izin sonrası dönüş
            case .background: viewModel.stop()
            default: break
            }
        }
        .onDisappear { viewModel.stop() }
        .sensoryFeedback(.success, trigger: viewModel.isTodayGoalReached) { old, new in !old && new }
        .alert("Bir sorun oluştu", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var icerik: some View {
        let s = viewModel.stats(for: .day)
        return VStack(spacing: 0) {
            ZStack {
                EnsoGosterge(ilerleme: viewModel.access == .loading ? 0 : s.progress)
                    .animation(.easeOut(duration: 1.1), value: s.progress)
                VStack(spacing: 2) {
                    Text(s.steps.formatted())
                        .font(.system(size: 40, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Color.ftText)
                    Text("/ \(s.goal.formatted()) adım")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ftTextSecondary)
                }
            }
            .padding(.top, 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bugün \(s.steps) adım, hedef \(s.goal)")
            .accessibilityValue("yüzde \(Int(min(s.progress, 9.99) * 100))")

            kalanCumlesi(s)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "#4A3324"))
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            if viewModel.isTodayManual {
                Text("Bugünkü sayı elle girildi")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ftTextSecondary)
                    .padding(.top, 4)
            }

            UcluMetrik(ogeler: [
                .init(deger: s.distanceKm.formatted(.number.precision(.fractionLength(1))), birim: "km", ad: "Mesafe",
                      simge: AnyView(AdimSimgesi(tur: .harita))),
                .init(deger: s.calories.formatted(), birim: "kcal", ad: s.caloriesAreEstimated ? "Kalori · tahmini" : "Kalori",
                      simge: AnyView(AdimSimgesi(tur: .alev))),
                .init(deger: s.remaining.formatted(), birim: "adım", ad: "Kalan",
                      simge: AnyView(AdimSimgesi(tur: .zirve)))
            ], boy: 19)
            .padding(.top, 28)

            BolumBasligi(metin: "Son 7 Gün")
                .padding(.top, 28)
            BuyuyenCicekler(gunler: viewModel.chartData(for: .day), hedef: Double(viewModel.dailyGoal))
                .padding(.horizontal, -1)
                .padding(.top, -6)
        }
    }

    private func kalanCumlesi(_ s: StepPeriodStats) -> Text {
        if s.remaining <= 0 {
            return Text("Hedefini ") + Text("tamamladın").bold() + Text(", bugünlük yeter")
        }
        return Text("Hedefini tamamlamana ") + Text(s.remaining.formatted()).bold() + Text(" adım kaldı")
    }
}

// MARK: - Simgeler (harita, mum alevi, zirvedeki bayrak)

struct AdimSimgesi: View {
    enum Tur { case harita, alev, zirve }
    let tur: Tur

    var body: some View {
        Canvas { ctx, boyut in
            let s = 0.8
            ctx.translateBy(x: boyut.width / 2 - 17 * s, y: boyut.height / 2 - 17 * s)
            ctx.scaleBy(x: s, y: s)
            let cizgi = StrokeStyle(lineWidth: 1.3 / s, lineCap: .round, lineJoin: .round)
            let renk = GraphicsContext.Shading.color(Color(hex: "#8A3E34"))
            for (yol, kesik) in Self.yollar(tur) {
                var st = cizgi
                if kesik { st.dash = [1.2, 2.6] }
                ctx.stroke(yol, with: renk, style: st)
            }
        }
        .frame(width: 34, height: 28)
        .murekkepGolgesi(hafif: true)
        .accessibilityHidden(true)
    }

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static func yollar(_ tur: Tur) -> [(Path, Bool)] {
        switch tur {
        case .harita:
            var a = Path()
            a.move(to: p(4.5, 9)); a.addLine(to: p(12, 6)); a.addLine(to: p(22, 9)); a.addLine(to: p(29.5, 6))
            a.addLine(to: p(29.5, 25)); a.addLine(to: p(22, 28)); a.addLine(to: p(12, 25)); a.addLine(to: p(4.5, 28)); a.closeSubpath()
            var b = Path()
            b.move(to: p(12, 6)); b.addLine(to: p(12, 25)); b.move(to: p(22, 9)); b.addLine(to: p(22, 28))
            var c = Path()
            c.move(to: p(7.5, 22))
            c.addCurve(to: p(17.5, 15), control1: p(10.5, 16), control2: p(14.5, 20))
            c.addCurve(to: p(26, 10.5), control1: p(19.5, 12), control2: p(23.5, 14))
            return [(a, false), (b, false), (c, true)]
        case .alev:
            var a = Path()
            a.move(to: p(17, 3.5))
            a.addCurve(to: p(24, 15), control1: p(18.4, 8), control2: p(22.6, 10.4))
            a.addCurve(to: p(17, 26.5), control1: p(25.6, 20.2), control2: p(22.4, 26.5))
            a.addCurve(to: p(10.2, 16.4), control1: p(11.4, 26.5), control2: p(8.6, 21.4))
            a.addCurve(to: p(14, 9.4), control1: p(11.2, 13.2), control2: p(13.4, 12.4))
            a.addCurve(to: p(15.8, 14), control1: p(15.6, 10.8), control2: p(16, 12.4))
            a.addCurve(to: p(17, 3.5), control1: p(17.4, 11.8), control2: p(17.6, 7.6))
            a.closeSubpath()
            var b = Path()
            b.move(to: p(17, 16))
            b.addCurve(to: p(19.6, 21.2), control1: p(18.6, 18), control2: p(19.6, 19.4))
            b.addCurve(to: p(17, 23.8), control1: p(19.6, 22.64), control2: p(18.44, 23.8))
            b.addCurve(to: p(14.4, 21.2), control1: p(15.56, 23.8), control2: p(14.4, 22.64))
            b.addCurve(to: p(17, 16), control1: p(14.4, 19.6), control2: p(15.4, 18.2))
            b.closeSubpath()
            return [(a, false), (b, false)]
        case .zirve:
            var a = Path()
            a.move(to: p(3.5, 29.5)); a.addLine(to: p(13.5, 14)); a.addLine(to: p(18.5, 21)); a.addLine(to: p(22.2, 16))
            a.addLine(to: p(30.5, 29.5)); a.closeSubpath()
            var b = Path()
            b.move(to: p(13.5, 14)); b.addLine(to: p(13.5, 3.5))
            var c = Path()
            c.move(to: p(13.5, 4)); c.addLine(to: p(20.5, 4)); c.addLine(to: p(18.6, 6.5)); c.addLine(to: p(20.5, 9)); c.addLine(to: p(13.5, 9))
            return [(a, false), (b, false), (c, false)]
        }
    }
}

// MARK: - Ayar sayfası

private struct AdimAyarSayfasi: View {
    let viewModel: StepsViewModel
    @Environment(AuthViewModel.self) private var auth

    @State private var hedef = Constants.Defaults.stepGoal
    @State private var gun = Calendar.current.startOfDay(for: .now)
    @State private var elle: Int?
    @State private var hata: String?

    private var gunler: [(Date, String)] {
        let takvim = Calendar.current
        let bugun = takvim.startOfDay(for: .now)
        return (0..<7).compactMap { i -> (Date, String)? in
            guard let d = takvim.date(byAdding: .day, value: -i, to: bugun) else { return nil }
            let ad = i == 0 ? "Bugün" : i == 1 ? "Dün" : d.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "tr_TR"))).capitalized
            return (d, ad)
        }
    }

    private func gununDegeri(_ d: Date) -> Int? {
        if let m = viewModel.manualValue(for: d) { return m }
        return viewModel.days.first { Calendar.current.isDate($0.date, inSameDayAs: d) }?.steps
    }

    var body: some View {
        KlasikAyarSayfasi(baslik: "Adım Ayarları", kaydet: kaydet) {
            HedefSatiri(deger: hedef.formatted(), birim: "adım",
                        azalt: { hedef = max(1_000, hedef - 500) },
                        artir: { hedef = min(50_000, hedef + 500) })

            AyarBolumu(metin: "Elle giriş")
            AyarSecimSatiri(baslik: "Gün", secenekler: gunler, secili: $gun)
            FircaAyirici(tohum: 221)
            AyarSayiGirisi(baslik: "Adım sayısı", deger: $elle)
            if viewModel.manualValue(for: gun) != nil {
                Button("Elle girilen değeri sil", role: .destructive) {
                    viewModel.deleteManual(for: gun)
                    elle = gununDegeri(gun)
                }
                .font(.system(size: 14))
                .padding(.top, 6)
            }

            AyarBolumu(metin: "Apple Sağlık")
            AyarSatiri(baslik: "Durum") {
                Text(durum.0).foregroundStyle(durum.1)
            }
            if viewModel.access == .needsPermission {
                Button("Sağlık’a Bağlan") { Task { await viewModel.requestAccess() } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KlasikRenk.vurgu)
                    .frame(minHeight: 44)
            }
            if let sorun = viewModel.healthIssue {
                Text(sorun).font(.system(size: 13)).foregroundStyle(Color.ftTextSecondary).padding(.top, 4)
            }
        }
        .onAppear {
            hedef = viewModel.dailyGoal
            elle = gununDegeri(gun)
        }
        .onChange(of: gun) { _, d in elle = gununDegeri(d) }
        .alert("Kaydedilemedi", isPresented: Binding(get: { hata != nil }, set: { if !$0 { hata = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(hata ?? "")
        }
    }

    private var durum: (String, Color) {
        switch viewModel.access {
        case .ready: return viewModel.healthIssue == nil ? ("Bağlı", KlasikRenk.yesil) : ("Okunamıyor", KlasikRenk.vurgu)
        case .needsPermission: return ("Bağlı değil", Color.ftTextSecondary)
        case .unavailable: return ("Bu cihazda yok", Color.ftTextSecondary)
        case .loading: return ("…", Color.ftTextSecondary)
        }
    }

    private func kaydet() {
        if hedef != viewModel.dailyGoal, var user = auth.currentUser {
            user.dailyStepGoal = hedef
            Task { await auth.updateUser(user) }
        }
        if let elle, elle != gununDegeri(gun) {
            do {
                try viewModel.saveManual(steps: elle, for: gun)
                Haptics.success()
            } catch {
                hata = AppError.map(error).errorDescription
                Haptics.error()
            }
        }
    }
}
