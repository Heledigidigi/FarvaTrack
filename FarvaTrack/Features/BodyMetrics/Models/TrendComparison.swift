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

// MARK: - Grafiğin son hali (ölçü başına saklanır)

/// Kullanıcı bir ölçünün grafiğinden çıkınca aralık, gösterim ve karşılaştırılan seriler korunur;
/// aynı ölçüye tekrar girince grafik bıraktığı gibi açılır.
struct MeasureTrendState: Equatable {
    var range: TrendRange = .sixMonths
    var mode: TrendMode = .value
    var compared: [TrendSeries] = []

    static func key(for measure: BodyMeasure) -> String { "measureTrend.\(measure.rawValue)" }

    /// "6A|value|weight,arm"
    var encoded: String {
        "\(range.rawValue)|\(mode.rawValue)|\(compared.map(\.id).joined(separator: ","))"
    }

    /// Bozuk ya da eski kayıtta bilinmeyen parçalar atlanır; ana ölçü karşılaştırmalardan çıkarılır.
    init(encoded: String?, primary: BodyMeasure) {
        guard let encoded else { return }
        let parts = encoded.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if let first = parts.first, let range = TrendRange(rawValue: first) { self.range = range }
        if parts.count > 1, let mode = TrendMode(rawValue: parts[1]) { self.mode = mode }
        if parts.count > 2 {
            var seen = Set<TrendSeries>()
            compared = parts[2].split(separator: ",").compactMap { id in
                TrendSeries.all.first { $0.id == String(id) }
            }.filter { $0 != .measure(primary) && seen.insert($0).inserted }
        }
    }

    init(range: TrendRange = .sixMonths, mode: TrendMode = .value, compared: [TrendSeries] = []) {
        self.range = range
        self.mode = mode
        self.compared = compared
    }

    static func load(_ primary: BodyMeasure, defaults: UserDefaults = .standard) -> MeasureTrendState {
        MeasureTrendState(encoded: defaults.string(forKey: key(for: primary)), primary: primary)
    }

    func save(_ primary: BodyMeasure, defaults: UserDefaults = .standard) {
        defaults.set(encoded, forKey: Self.key(for: primary))
    }
}
