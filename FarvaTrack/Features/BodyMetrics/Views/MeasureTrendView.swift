import SwiftUI
import SwiftData
import Charts

/// Bir ölçünün zaman içindeki değişimi; başka ölçüler ve kiloyla karşılaştırılabilir.
struct MeasureTrendView: View {
    @Query private var measurements: [MeasurementEntry]
    @Query private var weights: [WeightEntry]

    let primary: BodyMeasure
    @State private var compared: [TrendSeries] = []
    @State private var range: TrendRange = .sixMonths
    @State private var mode: TrendMode = .value
    @State private var selectedDate: Date?

    private static let palette: [Color] = [.ftWeight, .ftWater, .ftCalories, .ftSleep, .ftStats, .ftWaste, .ftAccentLight, .ftExercise]

    init(ownerID: String, primary: BodyMeasure) {
        _measurements = Query(filter: #Predicate<MeasurementEntry> { $0.ownerID == ownerID }, sort: \.date)
        _weights = Query(filter: #Predicate<WeightEntry> { $0.ownerID == ownerID }, sort: \.date)
        self.primary = primary
        // Grafik en son bırakıldığı gibi açılır (aralık, gösterim, karşılaştırmalar).
        let saved = MeasureTrendState.load(primary)
        _compared = State(initialValue: saved.compared)
        _range = State(initialValue: saved.range)
        _mode = State(initialValue: saved.mode)
    }

    private func persist() {
        MeasureTrendState(range: range, mode: mode, compared: compared).save(primary)
    }

    private var activeSeries: [TrendSeries] { [.measure(primary)] + compared }

    private var effectiveMode: TrendMode {
        TrendComparison.allowedModes(for: activeSeries).contains(mode) ? mode : .percent
    }

    private func samples(for series: TrendSeries) -> [(date: Date, value: Double)] {
        switch series {
        case .measure(let measure):
            return measurements.compactMap { entry in entry.value(for: measure).map { (entry.date, $0) } }
        case .weight:
            return weights.map { ($0.date, $0.weightKg) }
        }
    }

    private func color(for series: TrendSeries) -> Color {
        let index = TrendSeries.all.firstIndex(of: series) ?? 0
        return series == .measure(primary) ? .ftWeight : Self.palette[(index + 1) % Self.palette.count]
    }

    var body: some View {
        let mode = effectiveMode
        let allPoints = activeSeries.flatMap { TrendComparison.points(series: $0, samples: samples(for: $0), range: range, mode: mode) }
        let primaryPoints = allPoints.filter { $0.series == .measure(primary) }

        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Aralık", selection: $range) {
                        ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if TrendComparison.allowedModes(for: activeSeries).count > 1 {
                        Picker("Gösterim", selection: $mode) {
                            ForEach(TrendMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    if primaryPoints.count >= 2 {
                        chart(allPoints, mode: mode)
                            .frame(height: 240)
                    } else {
                        Text(primaryPoints.isEmpty ? "Bu aralıkta \(primary.title.lowercased()) ölçün yok." : "Grafik için en az iki ölçüm gerekiyor.")
                            .font(.subheadline)
                            .foregroundStyle(Color.ftTextSecondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }

                    if mode == .percent {
                        Text("Farklı birimler birlikte gösterildiği için her seri, aralıktaki ilk ölçümüne göre yüzde değişim olarak çizilir.")
                            .font(.caption2)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.ftCard)
            }

            Section {
                ForEach(activeSeries) { series in
                    summaryRow(series, points: allPoints.filter { $0.series == series })
                }
                Menu {
                    ForEach(TrendSeries.all.filter { !activeSeries.contains($0) }) { series in
                        Button(series.title) {
                            Haptics.selection()
                            compared.append(series)
                        }
                    }
                } label: {
                    Label("Karşılaştır: ölçü veya kilo ekle", systemImage: "plus.circle.fill")
                }
                .disabled(activeSeries.count >= TrendSeries.all.count)
            } header: {
                Text("Seriler")
            }
            .listRowBackground(Color.ftCard)

            Section("\(primary.title) geçmişi") {
                let history = Array(primaryPoints.reversed())
                ForEach(Array(history.enumerated()), id: \.element.id) { index, point in
                    let older = index + 1 < history.count ? history[index + 1] : nil
                    HStack {
                        Text(point.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "tr_TR"))))
                        Spacer()
                        if let older {
                            let diff = point.raw - older.raw
                            Text(abs(diff) < 0.05 ? "±0" : "\(diff > 0 ? "+" : "−")\(abs(diff).formatted(.number.precision(.fractionLength(0...1))))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.ftTextSecondary)
                        }
                        Text("\(point.raw.formatted(.number.precision(.fractionLength(0...1)))) cm")
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                if primaryPoints.isEmpty {
                    Text("Kayıt yok").foregroundStyle(Color.ftTextSecondary)
                }
            }
            .listRowBackground(Color.ftCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle(primary.title)
        .onChange(of: compared) { _, _ in
            if !TrendComparison.allowedModes(for: activeSeries).contains(self.mode) { self.mode = .percent }
            persist()
        }
        .onChange(of: range) { _, _ in persist() }
        .onChange(of: mode) { _, _ in persist() }
    }

    // MARK: - Grafik
    private func chart(_ points: [TrendPoint], mode: TrendMode) -> some View {
        let unit = mode == .percent ? "%" : "cm"
        let selected = selectedDate.flatMap { date in
            points.filter { $0.series == .measure(primary) }
                .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }

        return Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Tarih", point.date),
                    y: .value(unit, point.plotted),
                    series: .value("Seri", point.series.title)
                )
                .foregroundStyle(by: .value("Seri", point.series.title))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: point.series == .measure(primary) ? 3 : 2))

                PointMark(x: .value("Tarih", point.date), y: .value(unit, point.plotted))
                    .foregroundStyle(by: .value("Seri", point.series.title))
                    .symbolSize(point.series == .measure(primary) ? 40 : 20)
            }

            if mode == .percent {
                RuleMark(y: .value("Başlangıç", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.ftTextSecondary.opacity(0.5))
            }

            if let selected {
                RuleMark(x: .value("Seçili", selected.date))
                    .foregroundStyle(Color.white.opacity(0.15))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(for: selected.date, in: points)
                    }
            }
        }
        .chartForegroundStyleScale(domain: activeSeries.map(\.title), range: activeSeries.map(color(for:)))
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Color.ftTextSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(mode == .percent ? "%\(number.formatted(.number.precision(.fractionLength(0...1))))" : number.formatted(.number.precision(.fractionLength(0...1))))
                    }
                }
                .foregroundStyle(Color.ftTextSecondary)
            }
        }
        .environment(\.locale, Locale(identifier: "tr_TR"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(activeSeries.map(\.title).joined(separator: ", ")) grafiği")
    }

    /// Seçilen tarihe en yakın ölçümler (her seriden).
    private func tooltip(for date: Date, in points: [TrendPoint]) -> some View {
        let nearest = activeSeries.compactMap { series in
            points.filter { $0.series == series }.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "tr_TR"))))
                .font(.caption2)
                .foregroundStyle(Color.ftTextSecondary)
            ForEach(nearest) { point in
                Text("\(point.series.title): \(point.raw.formatted(.number.precision(.fractionLength(0...1)))) \(point.series.unit)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(color(for: point.series))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Seri satırı
    private func summaryRow(_ series: TrendSeries, points: [TrendPoint]) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color(for: series)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(series.title).font(.subheadline.weight(.medium))
                if let summary = TrendComparison.summary(points) {
                    Text("\(summary.first.formatted(.number.precision(.fractionLength(0...1)))) → \(summary.last.formatted(.number.precision(.fractionLength(0...1)))) \(series.unit) • \(summary.count) ölçüm")
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                } else {
                    Text("Bu aralıkta veri yok").font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
            }
            Spacer()
            if let summary = TrendComparison.summary(points), summary.count >= 2 {
                let change = summary.change
                Text("\(change >= 0 ? "+" : "−")\(abs(change).formatted(.number.precision(.fractionLength(0...1)))) \(series.unit)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            if series != .measure(primary) {
                Button {
                    compared.removeAll { $0 == series }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ftTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(series.title) serisini kaldır")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
