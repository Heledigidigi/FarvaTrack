import SwiftUI
import Charts

/// Tartı noktaları + 7 günlük hareketli ortalama çizgisi + isteğe bağlı hedef çizgisi.
struct TrendChartView: View {
    let points: [WeightPoint]
    var target: Double?
    var tint: Color = .ftWeight

    @State private var selectedDate: Date?

    private var trend: [WeightPoint] { WeightAnalyzer.movingAverage(points) }

    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.weightKg)
        if let target { values.append(target) }
        let low = (values.min() ?? 60) - 1.5
        let high = (values.max() ?? 80) + 1.5
        return low...high
    }

    private var selected: WeightPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                PointMark(x: .value("Tarih", point.date), y: .value("Kilo", point.weightKg))
                    .foregroundStyle(tint.opacity(0.45))
                    .symbolSize(30)
            }

            ForEach(trend) { point in
                LineMark(x: .value("Tarih", point.date), y: .value("Trend", point.weightKg))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .foregroundStyle(tint)
            }

            if let target {
                RuleMark(y: .value("Hedef", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.ftTextSecondary.opacity(0.7))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Hedef").font(.caption2).foregroundStyle(Color.ftTextSecondary)
                    }
            }

            if let selected {
                RuleMark(x: .value("Seçili", selected.date))
                    .foregroundStyle(Color.white.opacity(0.15))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(selected.date.shortDateString).font(.caption2).foregroundStyle(Color.ftTextSecondary)
                            Text(WeightAnalyzer.kgText(selected.weightKg)).font(.caption.bold().monospacedDigit())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Color.ftTextSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel().foregroundStyle(Color.ftTextSecondary)
            }
        }
        .environment(\.locale, Locale(identifier: "tr_TR"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kilo trend grafiği")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else { return "Veri yok" }
        return "\(points.count) tartı. İlk \(WeightAnalyzer.kgText(first.weightKg)), son \(WeightAnalyzer.kgText(last.weightKg))."
    }
}
