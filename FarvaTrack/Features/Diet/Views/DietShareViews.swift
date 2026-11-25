import SwiftUI

// MARK: - Arkadaş seç ve gönder

struct DietShareSheet: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let programID: String
    @State private var sending: String?

    private var rooms: [ChatRoomDTO] {
        guard let userID = store.userID else { return [] }
        return ChatRoomListCache(defaults: .standard).load(userID: userID)
            .filter { $0.members.contains(userID) && $0.members.contains { $0 != userID } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rooms) { room in
                        let friend = room.members.first { $0 != store.userID } ?? ""
                        Button {
                            sending = room.id
                            Task {
                                await store.share(programID, with: room)
                                sending = nil
                                dismiss()
                            }
                        } label: {
                            HStack {
                                AvatarView(name: room.names[friend] ?? "Arkadaş", photoURL: room.photos[friend])
                                    .frame(width: 36, height: 36)
                                Text(room.names[friend] ?? "Arkadaş").foregroundStyle(Color.ftText)
                                Spacer()
                                if sending == room.id { ProgressView() } else { Image(systemName: "paperplane").foregroundStyle(Color.ftAccentLight) }
                            }
                        }
                        .disabled(sending != nil)
                    }
                } footer: {
                    Text("Program sohbete kart olarak gider. Arkadaşın kabul edince kendi kopyası olur; sonraki değişikliklerin ona gitmez. Takibini görmen için kabul ederken izin vermesi gerekir.")
                }
                if rooms.isEmpty {
                    ContentUnavailableView("Arkadaş yok", systemImage: "person.2",
                                           description: Text("Sohbet sekmesinden arkadaş ekleyince programı gönderebilirsin."))
                }
            }
            .navigationTitle("Sohbette paylaş")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } } }
        }
    }
}

// MARK: - Sohbetteki program kartı

struct DietChatCard: View {
    @Environment(DietStore.self) private var store
    let info: ChatDietInfo
    let isMine: Bool
    @State private var offer: DietOffer?
    @State private var showOffer = false

    private var statusText: String? {
        switch offer?.status {
        case .accepted: return isMine ? "Kabul edildi" : "Programlarına eklendi"
        case .declined: return "Reddedildi"
        default: return isMine ? "Gönderildi · kabul edince kopyası onda olur" : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DİYET PROGRAMI")
                .font(.caption2.weight(.bold)).tracking(0.6)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isMine ? Color.white : Color.ftText)
                .background(isMine ? Color.ftAccent : Color.ftSubtle(0.12))
            VStack(alignment: .leading, spacing: 6) {
                Text(info.name).font(.headline).foregroundStyle(Color.ftText)
                Text(info.summary).font(.caption).foregroundStyle(Color.ftTextSecondary)
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle().fill(MacroKind.protein.color).frame(width: geometry.size.width * Double(info.proteinShare) / 100)
                        Rectangle().fill(MacroKind.carbs.color).frame(width: geometry.size.width * Double(info.carbsShare) / 100)
                        Rectangle().fill(MacroKind.fat.color)
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
                Text("P %\(info.proteinShare) · K %\(info.carbsShare) · Y %\(info.fatShare)\(info.alternatives > 0 ? " · \(info.alternatives) değişim" : "")")
                    .font(.caption2).foregroundStyle(Color.ftTextSecondary)
                if !isMine, offer?.status != .accepted, offer?.status != .declined {
                    Button { showOffer = true } label: {
                        Text("Önizle ve kabul et").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ftAccent)
                    .padding(.top, 4)
                }
                if let statusText {
                    Text(statusText).font(.caption2).foregroundStyle(Color.ftTextSecondary)
                }
            }
            .padding(12)
        }
        .frame(width: 250)
        .background(Color.ftCardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: info.offerID) { offer = await store.fetchOffer(info.offerID) }
        .sheet(isPresented: $showOffer) {
            DietOfferSheet(offerID: info.offerID) { offer = $0 }
        }
    }
}

// MARK: - Teklifi kabul

struct DietOfferSheet: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let offerID: String
    let onDecided: (DietOffer) -> Void
    @State private var offer: DietOffer?
    @State private var loading = true
    @State private var start = Date.now
    @State private var end: DietEndBehavior = .stop
    @State private var allowViewer = true
    @State private var previewDay = 0
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Group {
                if let offer {
                    form(offer)
                } else if loading {
                    ProgressView()
                } else {
                    ContentUnavailableView("Program bulunamadı", systemImage: "doc.questionmark",
                                           description: Text("Gönderen programı geri çekmiş olabilir."))
                }
            }
            .navigationTitle("Diyet programı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .task {
                offer = await store.fetchOffer(offerID)
                loading = false
            }
        }
    }

    private func form(_ offer: DietOffer) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(offer.name).font(.title3.bold())
                    Text("\(offer.fromName) gönderdi · \(offer.plan.dayCount) gün · ort. \(DietFormat.kcal(offer.plan.averageNutrition.calories)) kcal")
                        .font(.caption).foregroundStyle(Color.ftTextSecondary)
                    DietMacroBar(nutrition: offer.plan.averageNutrition)
                }
            }
            Section("Önizleme") {
                Picker("Gün", selection: $previewDay) {
                    ForEach(offer.plan.days.indices, id: \.self) { Text("Gün \($0 + 1)").tag($0) }
                }
                if let day = offer.plan.day(previewDay) {
                    ForEach(day.sortedMeals) { meal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(meal.name) · \(meal.timeText) · \(meal.nutrition.kcal) kcal").font(.subheadline.weight(.semibold))
                            Text(meal.summaryText).font(.caption).foregroundStyle(Color.ftTextSecondary)
                        }
                    }
                }
            }
            Section {
                DatePicker("Başlangıç", selection: $start, displayedComponents: .date)
                    .environment(\.locale, DietFormat.locale)
                Picker("Bitince", selection: $end) {
                    ForEach(DietEndBehavior.allCases) { Text($0.title).tag($0) }
                }
                Toggle("\(offer.fromName) takibimi görebilsin", isOn: $allowViewer)
            } footer: {
                Text("İzin verirsen öğünlerin, fotoğrafların, notların, makro analizin, ekstraların, kilon ve ölçülerin \(offer.fromName) kişisine görünür; yorum yapabilir, değişiklik önerebilir (sen onaylamadan programa girmez). İzni Program → ayarlar'dan istediğin zaman kapatabilirsin.")
            }
            if offer.status == .pending {
                Section {
                    Button {
                        saving = true
                        Task {
                            do {
                                _ = try await store.accept(offer, startDate: start, endBehavior: end, allowViewer: allowViewer)
                                var decided = offer
                                decided.status = .accepted
                                onDecided(decided)
                                dismiss()
                            } catch { store.present(error) }
                            saving = false
                        }
                    } label: {
                        HStack { Spacer(); if saving { ProgressView() } else { Text("Kabul et").bold() }; Spacer() }
                    }
                    .disabled(saving)
                    Button("Reddet", role: .destructive) {
                        Task {
                            await store.decline(offer)
                            var decided = offer
                            decided.status = .declined
                            onDecided(decided)
                            dismiss()
                        }
                    }
                }
            } else {
                Section { Text(offer.status == .accepted ? "Bu program kabul edildi." : "Bu program reddedildi.").foregroundStyle(Color.ftTextSecondary) }
            }
        }
    }
}

// MARK: - Benimle paylaşılan programlar (inceleme)

struct DietReviewListView: View {
    @Environment(DietStore.self) private var store

    var body: some View {
        List {
            if store.sharedPrograms.isEmpty {
                ContentUnavailableView("Henüz yok", systemImage: "eye",
                                       description: Text("Sohbetten program gönderdiğin bir arkadaşın kabul ederken izin verirse takibini burada görürsün."))
            }
            ForEach(store.sharedPrograms) { program in
                NavigationLink {
                    DietReviewView(programID: program.id)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(program.ownerName ?? "Arkadaşın").font(.headline)
                        Text("\(program.name) · \(program.programDay(on: .now).map { "Gün \($0) / \(program.dayCount)" } ?? DietFormat.shortDate(program.startDate))")
                            .font(.caption).foregroundStyle(Color.ftTextSecondary)
                    }
                }
                .listRowBackground(Color.ftCard)
            }
        }
        .scrollContentBackground(.hidden)
        .ftScreenBackground()
        .navigationTitle("Takip ettiklerim")
        .task { await store.refreshSocial() }
        .refreshable { await store.refreshSocial() }
    }
}

/// Programı gönderen kişinin gördüğü ekran: günlük, analiz, kilo ve ölçü.
struct DietReviewView: View {
    @Environment(DietStore.self) private var store
    let programID: String

    enum Tab: String, CaseIterable, Identifiable {
        case daily, analysis, body
        var id: String { rawValue }
        var title: String {
            switch self {
            case .daily: return "Günlük"
            case .analysis: return "Analiz"
            case .body: return "Kilo ve ölçü"
            }
        }
    }

    @State private var tab: Tab = .daily
    @State private var date = Date.now
    @State private var loaded = false
    @State private var showSuggest = false
    @State private var showReport = false
    @State private var photo: DietPhotoTarget?

    private var program: DietProgram? { store.program(id: programID) }

    var body: some View {
        ScrollView {
            if let program {
                VStack(spacing: 12) {
                    header(program)
                    Picker("Bölüm", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch tab {
                    case .daily: daily(program)
                    case .analysis: DietAnalysisView(program: program)
                    case .body: bodyMetrics(program)
                    }
                    HStack(spacing: 8) {
                        Button { showSuggest = true } label: {
                            Text("Programda değişiklik öner").font(.subheadline.bold()).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Color.ftAccent)
                        Button { showReport = true } label: {
                            Text("Rapor").font(.subheadline.bold()).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(Color.ftAccentLight)
                    }
                }
                .padding(16)
            } else if !loaded {
                ProgressView().padding(.top, 60)
            } else {
                ContentUnavailableView("Erişim yok", systemImage: "eye.slash", description: Text("Takibini paylaşma izni kapatılmış olabilir."))
            }
        }
        .ftScreenBackground()
        .navigationTitle(program?.ownerName ?? "Takip")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadShared(programID: programID)
            loaded = true
        }
        .refreshable { await store.loadShared(programID: programID) }
        .sheet(isPresented: $showSuggest) { DietEditorView(programID: programID, startDay: max(0, (program?.programDay(on: .now) ?? 1) - 1), suggestionMode: true) }
        .fullScreenCover(isPresented: $showReport) { if let program { DietReportView(program: program) } }
        .fullScreenCover(item: $photo) { target in DietPhotoFullScreen(path: target.path, title: target.title) }
    }

    private func header(_ program: DietProgram) -> some View {
        let week = store.summary(for: program, from: Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now, to: .now)
        let today = store.summary(for: program, from: .now, to: .now).days.first
        let weight = DietAnalysis.weightChange(program.metrics)
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(program.name) · \(program.programDay(on: .now).map { "Gün \($0) / \(program.dayCount)" } ?? "program dışı")")
                .font(.caption).foregroundStyle(Color.ftTextSecondary)
            HStack(spacing: 8) {
                tile(week.adherencePercent.map { "%\($0)" } ?? "—", "hafta uyumu", Color.ftSuccess)
                tile(todayEaten(today), "/ \(todayPlanned(today)) kcal", Color.ftText)
                tile(weightText(weight), "programda", Color.ftText)
            }
        }
    }

    private func todayEaten(_ day: DietDaySummary?) -> String { day.map { DietFormat.kcal($0.eaten.calories) } ?? "—" }
    private func todayPlanned(_ day: DietDaySummary?) -> String { day.map { DietFormat.kcal($0.planned.calories) } ?? "—" }

    private func weightText(_ weight: (first: Double, last: Double)?) -> String {
        guard let weight else { return "—" }
        let change = weight.last - weight.first
        return (change >= 0 ? "+" : "") + DietFormat.number(change) + " kg"
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func daily(_ program: DietProgram) -> some View {
        DietDayNavigator(date: date, subtitle: program.programDay(on: date).map { "Gün \($0)" },
                         canGoForward: !Calendar.current.isDateInToday(date)) { offset in
            date = Calendar.current.date(byAdding: .day, value: offset, to: date) ?? date
        }
        if let summary = store.summary(for: program, from: date, to: date).days.first, summary.programDay != nil {
            ForEach(summary.meals) { snapshot in reviewMeal(program, snapshot) }
            if let note = summary.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Günün notu").font(.headline)
                    if !note.text.isEmpty { Text(note.text).font(.subheadline) }
                    if !note.tags.isEmpty { DietTagRow(tags: note.tags, selected: Set(note.tags)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle(padding: 14)
            }
        } else {
            Text("Bu gün programın dışında.").foregroundStyle(Color.ftTextSecondary).padding(.vertical, 30)
        }
    }

    private func reviewMeal(_ program: DietProgram, _ snapshot: DietMealSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    if let path = snapshot.log?.photoPath {
                        photo = DietPhotoTarget(path: path, title: "\(snapshot.meal.name) · \(snapshot.meal.timeText)")
                    }
                } label: {
                    DietPhotoView(path: snapshot.log?.photoPath)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(snapshot.log?.photoPath == nil)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("\(snapshot.meal.name) · \(snapshot.log.map { $0.loggedAt.formatted(date: .omitted, time: .shortened) } ?? snapshot.meal.timeText)")
                            .font(.subheadline.bold())
                        Spacer()
                        DietStatusChip(status: snapshot.status, missed: snapshot.isMissed, thirdPerson: true)
                    }
                    if snapshot.status == .changed, let swaps = snapshot.log?.swaps, !swaps.isEmpty {
                        Text(swaps.joined(separator: " · ")).font(.caption.weight(.semibold)).foregroundStyle(Color.ftWarning)
                    }
                    Text(snapshot.status == nil || snapshot.status == .skipped ? "Plan: \(snapshot.meal.summaryText)" : (snapshot.log?.eatenSummary ?? ""))
                        .font(.caption).foregroundStyle(Color.ftTextSecondary).lineLimit(2)
                    if snapshot.status == .eaten || snapshot.status == .changed {
                        Text("\(snapshot.eatenNutrition.kcal) kcal · plan \(snapshot.meal.nutrition.kcal)").font(.caption2).foregroundStyle(Color.ftTextSecondary)
                    }
                    if let note = snapshot.log?.note, !note.isEmpty {
                        Text("“\(note)”").font(.caption.italic())
                    }
                }
            }
            if let log = snapshot.log {
                DietCommentList(programID: program.id, targetID: log.id)
            }
        }
        .cardStyle(padding: 12)
    }

    private func bodyMetrics(_ program: DietProgram) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let metrics = program.metrics, !metrics.weights.isEmpty || !metrics.measurements.isEmpty {
                if !metrics.weights.isEmpty {
                    Text("Kilo").font(.headline)
                    ForEach(metrics.weights.sorted { $0.date > $1.date }, id: \.self) { point in
                        HStack {
                            Text(DietFormat.shortDate(point.date))
                            Spacer()
                            Text("\(DietFormat.number(point.value)) kg").bold()
                        }
                        .font(.subheadline)
                    }
                }
                if !metrics.measurements.isEmpty {
                    Text("Ölçüler (ilk → son)").font(.headline).padding(.top, 6)
                    ForEach(metrics.measurements.keys.sorted(), id: \.self) { name in
                        let points = metrics.measurements[name] ?? []
                        HStack {
                            Text(name)
                            Spacer()
                            Text(points.map { "\(DietFormat.number($0.value)) cm" }.joined(separator: " → ")).bold()
                        }
                        .font(.subheadline)
                    }
                }
                Text("Son güncelleme \(metrics.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Color.ftTextSecondary)
            } else {
                Text("Program süresinde kilo ya da ölçü girilmemiş.").foregroundStyle(Color.ftTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
    }
}

struct DietPhotoTarget: Identifiable {
    var path: String
    var title: String
    var id: String { path }
}
