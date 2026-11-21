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

struct WasteView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(WasteViewModel.self) private var viewModel

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.hasError }, set: { viewModel.hasError = $0 })
    }

    var body: some View {
        Group {
            if let user = auth.currentUser {
                WasteContent(ownerID: user.id, viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Biyolojik Atık")
        .toolbar {
            if auth.currentUser?.isAdmin == true {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        WasteAdminView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "person.2.fill")
                    }
                    .accessibilityLabel("Tüm kullanıcılar")
                }
            }
        }
        .alert("Bir sorun oluştu", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.handleForeground() }
    }
}

// MARK: - İçerik
private struct WasteContent: View {
    @Query private var entries: [WasteEntry]
    let viewModel: WasteViewModel

    @State private var range: WasteRange = .week

    init(ownerID: String, viewModel: WasteViewModel) {
        let since = Calendar.current.date(byAdding: .day, value: -95, to: Date.now.startOfDay) ?? .distantPast
        _entries = Query(
            filter: #Predicate<WasteEntry> { $0.ownerID == ownerID && $0.date >= since },
            sort: \.date,
            order: .reverse
        )
        self.viewModel = viewModel
    }

    var body: some View {
        let dates = entries.map(\.date)
        let series = WasteAnalyzer.dailyCounts(dates: dates, days: range.rawValue)
        let stats = WasteAnalyzer.stats(series)
        let today = entries.filter { Calendar.current.isDateInToday($0.date) }

        List {
            if !SharedStore.isSharedContainerAvailable {
                Section { WidgetSyncNotice() }
            }
            Section {
                counter(today: today.count)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Aralık", selection: $range) {
                        ForEach(WasteRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if stats.activeDays > 0 {
                        ChartView(data: series, tint: Color.ftWaste, unit: "kez", xAxisStyle: range.axisStyle)
                            .frame(height: 170)
                        HStack {
                            metric("Ortalama", stats.average.formatted(.number.precision(.fractionLength(1))))
                            metric("En fazla", "\(stats.maximum)")
                            metric("Kayıtlı gün", "\(stats.activeDays)")
                        }
                    } else {
                        Text("Bu aralıkta kayıt yok.")
                            .font(.subheadline)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.ftCard)
            } header: {
                Text("Geçmiş")
            }

            if stats.activeDays > 0 {
                Section("Günlük Tablo") {
                    ForEach(series.reversed().filter { $0.value > 0 }) { item in
                        HStack {
                            Text(item.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "tr_TR"))))
                            Spacer()
                            Text("\(Int(item.value)) kez").monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .listRowBackground(Color.ftCard)
                    }
                }
            }

            Section("Bugünkü Kayıtlar") {
                if today.isEmpty {
                    Text("Bugün henüz kayıt yok.")
                        .foregroundStyle(Color.ftTextSecondary)
                        .listRowBackground(Color.ftCard)
                }
                ForEach(today) { entry in
                    Label(entry.date.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        .listRowBackground(Color.ftCard)
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.delete(entry)
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .bottom) { undoToast }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.lastAddedID)
    }

    private func counter(today: Int) -> some View {
        VStack(spacing: 14) {
            Text("Bugün")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ftTextSecondary)
            Text("\(today)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: today)

            Button {
                do {
                    try viewModel.add()
                } catch {
                    viewModel.errorMessage = AppError.map(error).errorDescription
                    Haptics.error()
                }
            } label: {
                Label("Kaydet", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.ftWaste.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bir kayıt ekle")
            .accessibilityHint("Bugünkü sayıyı bir artırır")
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.ftCard, in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bugün \(today) kayıt")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var undoToast: some View {
        if viewModel.lastAddedID != nil {
            HStack {
                Text("Kayıt eklendi")
                Spacer()
                Button("Geri al") { viewModel.undo() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.ftWaste)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.ftCardElevated, in: Capsule())
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
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
        .background(Color.ftBackground.ignoresSafeArea())
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
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle(user.displayName.isEmpty ? user.email : user.displayName)
    }
}
