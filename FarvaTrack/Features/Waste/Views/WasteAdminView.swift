import SwiftUI
import SwiftData

enum WasteRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week: return "7 gün"
        case .month: return "30 gün"
        case .quarter: return "90 gün"
        }
    }

    var axisStyle: ChartView.XAxisStyle { self == .week ? .weekday : .dayOfMonth }
}

// MARK: - Yönetici görünümü (yalnızca günlük sayılar)
struct WasteAdminView: View {
    let viewModel: WasteViewModel

    var body: some View {
        List {
            if let error = viewModel.adminError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.ftWarning)
                        .listRowBackground(Color.ftCard)
                }
            }

            Section {
                if viewModel.adminUsers.isEmpty && !viewModel.isLoadingAdmin {
                    Text("Gösterilecek kullanıcı yok.")
                        .foregroundStyle(Color.ftTextSecondary)
                        .listRowBackground(Color.ftCard)
                }
                ForEach(viewModel.adminUsers) { user in
                    let stats = WasteAnalyzer.stats(WasteAnalyzer.dailyCounts(daily: user.days, days: 30))
                    NavigationLink {
                        WasteUserDetailView(user: user)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName.isEmpty ? user.email : user.displayName)
                                    .font(.subheadline.weight(.medium))
                                Text("30 gün ort. \(stats.average.formatted(.number.precision(.fractionLength(1))))")
                                    .font(.caption)
                                    .foregroundStyle(Color.ftTextSecondary)
                            }
                            Spacer()
                            Text("Bugün \(stats.today)")
                                .font(.subheadline.monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .listRowBackground(Color.ftCard)
                }
            } footer: {
                Text("Yalnızca günlük toplamlar görünür; kayıtların saatleri kullanıcıya özeldir.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ftScreenBackground()
        .navigationTitle("Tüm Kullanıcılar")
        .overlay {
            if viewModel.isLoadingAdmin && viewModel.adminUsers.isEmpty { ProgressView() }
        }
        .refreshable { await viewModel.loadAdminOverview() }
        .task { await viewModel.loadAdminOverview() }
    }
}

struct WasteUserDetailView: View {
    let user: WasteUserSummary
    @State private var range: WasteRange = .month

    var body: some View {
        let series = WasteAnalyzer.dailyCounts(daily: user.days, days: range.rawValue)
        let stats = WasteAnalyzer.stats(series)

        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Aralık", selection: $range) {
                        ForEach(WasteRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ChartView(data: series, tint: Color.ftWaste, unit: "kez", xAxisStyle: range.axisStyle)
                        .frame(height: 180)
                    Text("Ortalama \(stats.average.formatted(.number.precision(.fractionLength(1)))) • En fazla \(stats.maximum) • \(stats.activeDays) kayıtlı gün")
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.ftCard)
            }

            Section("Günlük Tablo") {
                ForEach(series.reversed()) { item in
                    HStack {
                        Text(item.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "tr_TR"))))
                        Spacer()
                        Text("\(Int(item.value))").monospacedDigit()
                    }
                    .foregroundStyle(item.value > 0 ? Color.white : Color.ftTextSecondary)
                    .accessibilityElement(children: .combine)
                    .listRowBackground(Color.ftCard)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ftScreenBackground()
        .navigationTitle(user.displayName.isEmpty ? user.email : user.displayName)
    }
}
