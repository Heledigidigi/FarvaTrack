import SwiftUI

/// Alışveriş listesi: seçilen günlerin malzemeleri birleştirilir, reyonlara göre gruplanır.
struct DietShoppingView: View {
    @Environment(\.dismiss) private var dismiss
    let program: DietProgram

    enum Range: Int, CaseIterable, Identifiable {
        case tomorrow, week, tenDays, twoWeeks, custom
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .tomorrow: return "Yarın"
            case .week: return "7 gün"
            case .tenDays: return "10 gün"
            case .twoWeeks: return "2 hafta"
            case .custom: return "Özel"
            }
        }
    }

    @State private var range: Range = .week
    @State private var customStart = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var customEnd = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var states: [String: DietShoppingState] = [:]

    private var store: DietShoppingStore { DietShoppingStore(defaults: .standard, programID: program.id) }

    private var dates: (Date, Date) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        func plus(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days - 1, to: tomorrow) ?? tomorrow }
        switch range {
        case .tomorrow: return (tomorrow, tomorrow)
        case .week: return (tomorrow, plus(7))
        case .tenDays: return (tomorrow, plus(10))
        case .twoWeeks: return (tomorrow, plus(14))
        case .custom: return (min(customStart, customEnd), max(customStart, customEnd))
        }
    }

    private var items: [DietShoppingItem] { DietShopping.items(program: program, from: dates.0, to: dates.1) }
    private var doneCount: Int { items.filter { (states[$0.id] ?? .none) != .none }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Aralık", selection: $range) {
                        ForEach(Range.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if range == .custom {
                        DatePicker("Başlangıç", selection: $customStart, displayedComponents: .date)
                        DatePicker("Bitiş", selection: $customEnd, displayedComponents: .date)
                    }
                    Text("\(DietFormat.shortDate(dates.0)) – \(DietFormat.shortDate(dates.1)) · \(doneCount) / \(items.count) tamam")
                        .font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
                .environment(\.locale, DietFormat.locale)

                if items.isEmpty {
                    ContentUnavailableView("Bu aralıkta program günü yok", systemImage: "cart")
                }
                ForEach(DietShoppingCategory.allCases) { category in
                    let group = items.filter { $0.category == category }
                    if !group.isEmpty {
                        Section(category.title) {
                            ForEach(group) { item in row(item) }
                        }
                    }
                }
                Section {
                    Text("Dokun: alındı · tekrar dokun: evde var (sonraki listede de çizili gelir) · bir daha: sıfırla")
                        .font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .ftScreenBackground()
            .navigationTitle("Alışveriş listesi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: DietShopping.text(items: items, states: states,
                                                      title: "\(program.name) · \(DietFormat.shortDate(dates.0)) – \(DietFormat.shortDate(dates.1))")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Listeyi paylaş")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Yeni alışveriş (alınanları sıfırla)") {
                        store.resetBought()
                        states = store.load()
                        Haptics.selection()
                    }
                    .font(.footnote)
                }
            }
            .onAppear { states = store.load() }
        }
    }

    private func row(_ item: DietShoppingItem) -> some View {
        let state = states[item.id] ?? .none
        return Button {
            Haptics.selection()
            states[item.id] = state.next
            store.save(states)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(state == .bought ? Color.ftSuccess : (state == .atHome ? Color.ftSubtle(0.2) : Color.clear))
                    RoundedRectangle(cornerRadius: 7).strokeBorder(state == .none ? Color.ftTextSecondary : Color.clear, lineWidth: 1.5)
                    if state == .bought { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                    if state == .atHome { Image(systemName: "house.fill").font(.caption2).foregroundStyle(Color.ftText) }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.food.name).font(.subheadline).strikethrough(state != .none).foregroundStyle(state == .none ? Color.ftText : Color.ftTextSecondary)
                    Text(state == .atHome ? "evde var" : item.detailText).font(.caption).foregroundStyle(Color.ftTextSecondary).lineLimit(1)
                }
                Spacer()
                Text(item.quantityText).font(.subheadline.weight(.semibold).monospacedDigit())
                    .strikethrough(state != .none)
                    .foregroundStyle(state == .none ? Color.ftText : Color.ftTextSecondary)
            }
        }
        .listRowBackground(Color.ftCard)
        .accessibilityLabel("\(item.food.name), \(item.quantityText)\(state == .bought ? ", alındı" : state == .atHome ? ", evde var" : "")")
    }
}
