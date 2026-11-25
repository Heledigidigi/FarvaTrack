import SwiftUI
import Charts
import SwiftData

struct StatisticsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = StatisticsViewModel()

    var body: some View {
        List {
            Section {
                Picker("Dönem", selection: Binding(get: { viewModel.period }, set: { viewModel.setPeriod($0) })) {
                    ForEach(StatsPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                NavigationLink {
                    BadgesView(badges: viewModel.badges)
                } label: {
                    HStack {
                        Label("Rozetler", systemImage: "rosette")
                            .foregroundStyle(Color.ftStats)
                        Spacer()
                        Text("\(viewModel.earnedCount)/\(viewModel.badges.count)")
                            .monospacedDigit()
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                }
                .listRowBackground(Color.ftCard)
            }

            if let name = viewModel.programName, !viewModel.adherence.isEmpty {
                Section {
                    AdherenceCard(programName: name, weeks: viewModel.adherence)
                        .listRowBackground(Color.ftCard)
                }
            }

            if viewModel.cards.isEmpty && !viewModel.isLoading {
                Section {
                    Text("Bu dönemde henüz veri yok. Kayıt ekledikçe istatistiklerin burada görünecek.")
                        .foregroundStyle(Color.ftTextSecondary)
                        .listRowBackground(Color.ftCard)
                }
            }

            ForEach(viewModel.cards) { card in
                Section {
                    MetricCardView(card: card, period: viewModel.period)
                        .listRowBackground(Color.ftCard)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ftScreenBackground()
        .navigationTitle("İstatistikler")
        .overlay {
            if viewModel.isLoading && viewModel.cards.isEmpty { ProgressView() }
        }
        .task(id: auth.currentUser?.id) {
            if let user = auth.currentUser { await viewModel.load(context: modelContext, user: user) }
        }
        .refreshable {
            if let user = auth.currentUser { await viewModel.load(context: modelContext, user: user) }
        }
    }
}

private struct MetricCardView: View {
    let card: MetricCard
    let period: StatsPeriod

    private var metric: StatMetric { card.metric }
    private var summary: MetricSummary { card.summary }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(metric.fractionDigits)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(metric.title, systemImage: metric.systemImage)
                    .font(.headline)
                    .foregroundStyle(metric.tint)
                Spacer()
                if let change = summary.changePercent, abs(change) >= 1 {
                    Text("\(change > 0 ? "▲" : "▼") %\(Int(abs(change).rounded()))")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.ftTextSecondary)
                        .accessibilityLabel("Önceki döneme göre yüzde \(Int(abs(change).rounded())) \(change > 0 ? "artış" : "azalış")")
                }
            }

            ChartView(
                data: card.chart,
                goal: metric == .weight || period == .year ? nil : card.goal,
                tint: metric.tint,
                unit: metric.unit,
                xAxisStyle: period.axisStyle,
                fractionDigits: metric.fractionDigits,
                barUnit: period.barUnit
            )
            .frame(height: 160)

            HStack(spacing: 8) {
                stat(metric == .weight ? "Ortalama" : "Günlük ort.", summary.average.map { "\(format($0)) \(metric.unit)" } ?? "—")
                if metric == .weight {
                    stat("Ölçüm", "\(summary.recordedDays) gün")
                } else if let best = summary.best {
                    stat("En iyi", "\(format(best.value))")
                }
                if let goalDays = summary.goalDays {
                    stat("Hedef", "\(goalDays)/\(summary.recordedDays) gün")
                } else if metric == .workout {
                    stat("Toplam", "\(format(summary.total)) dk")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Program uyumu
private struct AdherenceCard: View {
    let programName: String
    let weeks: [WeekAdherence]

    private var visible: [WeekAdherence] { Array(weeks.suffix(8)) }

    var body: some View {
        let current = weeks.last
        let average = AdherenceCalculator.averagePercent(visible)
        let streak = AdherenceCalculator.completeWeekStreak(weeks)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Program Uyumu", systemImage: "calendar.badge.checkmark")
                    .font(.headline)
                    .foregroundStyle(Color.ftExercise)
                Spacer()
                Text(programName).font(.caption).foregroundStyle(Color.ftTextSecondary).lineLimit(1)
            }

            Chart(visible) { week in
                BarMark(
                    x: .value("Hafta", week.weekStart, unit: .weekOfYear),
                    y: .value("Uyum", week.ratio * 100)
                )
                .foregroundStyle(week.isComplete ? Color.ftSuccess : (week.isCurrent ? Color.ftExercise.opacity(0.5) : Color.ftExercise))
                .cornerRadius(4)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(Color.ftSubtle(0.06))
                    AxisValueLabel { Text("%\(value.as(Int.self) ?? 0)") }.foregroundStyle(Color.ftTextSecondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Color.ftTextSecondary)
                }
            }
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .frame(height: 130)
            .accessibilityLabel("Son \(visible.count) haftanın program uyumu")

            HStack(spacing: 8) {
                stat("Bu hafta", current.map { "\($0.done)/\($0.planned)" } ?? "—")
                stat("Ortalama", average.map { "%\($0)" } ?? "—")
                stat("Seri", "\(streak) hafta")
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold().monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rozetler
struct BadgesView: View {
    let badges: [BadgeStatus]

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(badges) { status in
                    BadgeTile(status: status)
                }
            }
            .padding(Constants.Layout.screenPadding)
        }
        .ftScreenBackground()
        .navigationTitle("Rozetler")
    }
}

private struct BadgeTile: View {
    let status: BadgeStatus

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(status.isEarned ? Color.ftStats.opacity(0.22) : Color.ftSubtle(0.06))
                Image(systemName: status.badge.systemImage)
                    .font(.title2)
                    .foregroundStyle(status.isEarned ? Color.ftStats : Color.ftTextSecondary.opacity(0.5))
            }
            .frame(width: 60, height: 60)

            Text(status.badge.title)
                .font(.subheadline.weight(.semibold))
            Text(status.badge.detail)
                .font(.caption2)
                .foregroundStyle(Color.ftTextSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)

            if status.isEarned {
                Label("Kazanıldı", systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.ftSuccess)
            } else {
                ProgressView(value: status.progress)
                    .tint(Color.ftStats)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.ftCard, in: RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous))
        .opacity(status.isEarned ? 1 : 0.85)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.badge.title). \(status.badge.detail)")
        .accessibilityValue(status.isEarned ? "Kazanıldı" : "Yüzde \(Int(status.progress * 100)) tamamlandı")
    }
}
