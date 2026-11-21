import SwiftUI
import Charts

/// Günlük (veya aylık) değerler için yeniden kullanılabilir çubuk grafik (hedef çizgisi + dokunarak seçim).
struct ChartView: View {
    enum XAxisStyle { case weekday, dayOfMonth, monthOfYear }

    let data: [DailyValue]
    var goal: Double?
    var tint: Color = Color.ftAccentLight
    var unit: String = ""
    var xAxisStyle: XAxisStyle = .weekday
    var fractionDigits = 0
    /// Çubuk genişliği birimi: günlük için `.day`, aylık kovalar için `.month`.
    var barUnit: Calendar.Component = .day

    @State private var selectedDate: Date?

    private var granularity: Calendar.Component { barUnit == .month ? .month : .day }

    private var selectedItem: DailyValue? {
        guard let selectedDate else { return nil }
        return data.first { Calendar.current.isDate($0.date, equalTo: selectedDate, toGranularity: granularity) }
    }

    private var axisValues: AxisMarkValues {
        switch xAxisStyle {
        case .weekday: return .stride(by: .day)
        case .dayOfMonth: return .stride(by: .day, count: 5)
        case .monthOfYear: return .stride(by: .month)
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch xAxisStyle {
        case .weekday: return .dateTime.weekday(.abbreviated)
        case .dayOfMonth: return .dateTime.day()
        case .monthOfYear: return .dateTime.month(.narrow)
        }
    }

    var body: some View {
        Chart {
            ForEach(data) { item in
                BarMark(
                    x: .value("Tarih", item.date, unit: barUnit),
                    y: .value("Değer", item.value)
                )
                .cornerRadius(6)
                .foregroundStyle(barColor(for: item))
            }

            if let goal {
                RuleMark(y: .value("Hedef", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.ftTextSecondary.opacity(0.7))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Hedef")
                            .font(.caption2)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
            }

            if let selectedItem {
                RuleMark(x: .value("Seçili", selectedItem.date, unit: barUnit))
                    .foregroundStyle(Color.white.opacity(0.15))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        tooltip(for: selectedItem)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: axisValues) { _ in
                AxisValueLabel(format: axisFormat, centered: true)
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
        .animation(.easeInOut(duration: 0.25), value: selectedDate)
    }

    private func barColor(for item: DailyValue) -> Color {
        let base: Color = {
            if let goal, item.value >= goal { return Color.ftSuccess }
            return tint
        }()
        guard let selectedItem else { return base }
        return selectedItem.id == item.id ? base : base.opacity(0.35)
    }

    private func tooltip(for item: DailyValue) -> some View {
        VStack(spacing: 2) {
            Text(barUnit == .month
                 ? item.date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "tr_TR")))
                 : item.date.shortDateString)
                .font(.caption2)
                .foregroundStyle(Color.ftTextSecondary)
            Text("\(item.value.formatted(.number.precision(.fractionLength(fractionDigits)))) \(unit)")
                .font(.caption.bold().monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
