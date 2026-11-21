import Foundation

/// Grafikte gösterilebilen seri: bir vücut ölçüsü veya kilo.
enum TrendSeries: Hashable, Identifiable {
    case measure(BodyMeasure)
    case weight

    var id: String {
        switch self {
        case .measure(let measure): return measure.rawValue
        case .weight: return "weight"
        }
    }

    var title: String {
        switch self {
        case .measure(let measure): return measure.title
        case .weight: return "Kilo"
        }
    }

    var unit: String {
        switch self {
        case .measure: return "cm"
        case .weight: return "kg"
        }
    }

    static var all: [TrendSeries] { BodyMeasure.allCases.map(TrendSeries.measure) + [.weight] }
}

enum TrendRange: String, CaseIterable, Identifiable {
    case threeMonths = "3A", sixMonths = "6A", year = "1Y", all = "Tümü"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .year: return 365
        case .all: return nil
        }
    }
}

/// Mutlak değer (yalnızca aynı birimli seriler) ya da başlangıca göre yüzde değişim (farklı birimler birlikte).
enum TrendMode: String, CaseIterable, Identifiable {
    case value, percent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .value: return "Değer"
        case .percent: return "% Değişim"
        }
    }
}

struct TrendPoint: Identifiable, Equatable {
    let series: TrendSeries
    let date: Date
    /// Grafikte çizilen değer (moda göre cm/kg ya da %).
    let plotted: Double
    /// Ölçülen gerçek değer (ipucu ve tablo için).
    let raw: Double

    var id: String { "\(series.id)-\(date.timeIntervalSince1970)" }
}

struct TrendSummary: Equatable {
    let first: Double
    let last: Double
    let minimum: Double
    let maximum: Double
    let count: Int

    var change: Double { last - first }
    var percentChange: Double? { first != 0 ? (last - first) / first * 100 : nil }
}

enum TrendComparison {
    /// Seçilen serilerin hepsi cm ise mutlak değer gösterilebilir; kilo eklenince yüzde moduna geçilir.
    static func allowedModes(for series: [TrendSeries]) -> [TrendMode] {
        Set(series.map(\.unit)).count > 1 ? [.percent] : TrendMode.allCases
    }

    /// Ham (tarih, değer) listesini aralığa göre süzer, sıralar ve moda göre çizim değerine çevirir.
    /// Yüzde modunda her seri kendi aralık içindeki ilk ölçümüne göre hesaplanır.
    static func points(
        series: TrendSeries,
        samples: [(date: Date, value: Double)],
        range: TrendRange,
        mode: TrendMode,
        now: Date = .now
    ) -> [TrendPoint] {
        let start = range.days.map { now.addingTimeInterval(-Double($0) * 86_400) } ?? .distantPast
        let sorted = samples.filter { $0.date >= start && $0.date <= now }.sorted { $0.date < $1.date }
        guard let base = sorted.first?.value else { return [] }
        return sorted.map { sample in
            let plotted: Double
            switch mode {
            case .value: plotted = sample.value
            case .percent: plotted = base != 0 ? (sample.value - base) / base * 100 : 0
            }
            return TrendPoint(series: series, date: sample.date, plotted: plotted, raw: sample.value)
        }
    }

    static func summary(_ points: [TrendPoint]) -> TrendSummary? {
        guard let first = points.first, let last = points.last else { return nil }
        let values = points.map(\.raw)
        return TrendSummary(
            first: first.raw, last: last.raw,
            minimum: values.min() ?? first.raw, maximum: values.max() ?? first.raw,
            count: points.count
        )
    }
}
