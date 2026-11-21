import Foundation

// MARK: - Değer tipleri (SwiftData'dan bağımsız, kolay test edilir)
struct SleepRecord: Equatable {
    let day: Date
    let bedtime: Date
    let wakeTime: Date
    let quality: Int

    var durationHours: Double { wakeTime.timeIntervalSince(bedtime) / 3600 }
}

struct SleepWeekReport: Equatable {
    /// Son 7 gün, eskiden yeniye. Kaydı olmayan gün `nil`.
    var nights: [SleepRecord?]
    var averageHours: Double?
    var averageQuality: Double?
    var debtHours: Double
    var deltaMinutesVsPrevious: Int?
    var best: SleepRecord?
    var worst: SleepRecord?
    var durationChart: [DailyValue]
    var qualityChart: [DailyValue]

    var recorded: [SleepRecord] { nights.compactMap { $0 } }
}

struct SleepRegularity: Equatable {
    let score: Int
    let averageBedtimeMinutes: Int
    let averageWakeMinutes: Int

    var label: String {
        switch score {
        case 80...: return "Çok düzenli"
        case 60..<80: return "Düzenli"
        case 40..<60: return "Orta"
        default: return "Düzensiz"
        }
    }
}

struct BedtimeSuggestion: Identifiable, Equatable {
    let cycles: Int
    let bedtimeMinutes: Int
    let isRecommended: Bool

    var id: Int { cycles }
    var sleepHours: Double { Double(cycles) * 1.5 }
}

// MARK: - Analiz
enum SleepAnalyzer {
    static let minDurationHours = 0.5
    static let maxDurationHours = 20.0

    static func isValidDuration(_ hours: Double) -> Bool {
        (minDurationHours...maxDurationHours).contains(hours)
    }

    /// Kalite, eşitlikte süreye göre sıralama ölçütü.
    private static func rank(_ record: SleepRecord) -> Double {
        Double(record.quality) * 100 + record.durationHours
    }

    // MARK: Haftalık rapor
    static func report(
        records: [SleepRecord],
        endingOn end: Date,
        goalHours: Double,
        calendar: Calendar = .current
    ) -> SleepWeekReport {
        let today = calendar.startOfDay(for: end)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let byDay = Dictionary(
            records.map { (calendar.startOfDay(for: $0.day), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let nights = days.map { byDay[$0] }
        let recorded = nights.compactMap { $0 }

        let averageHours = mean(recorded.map(\.durationHours))
        let averageQuality = mean(recorded.map { Double($0.quality) })
        // Uyku borcu: kaydedilen gecelerde hedefin altında kalan sürelerin toplamı (negatif olmaz).
        let debt = max(0, recorded.reduce(0) { $0 + (goalHours - $1.durationHours) })

        let previousDays = (7..<14).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let previous = previousDays.compactMap { byDay[$0] }
        var delta: Int?
        if let averageHours, let previousAverage = mean(previous.map(\.durationHours)) {
            delta = Int(((averageHours - previousAverage) * 60).rounded())
        }

        let best = recorded.max { rank($0) < rank($1) }
        let worst = recorded.count >= 2 ? recorded.min { rank($0) < rank($1) } : nil

        return SleepWeekReport(
            nights: nights,
            averageHours: averageHours,
            averageQuality: averageQuality,
            debtHours: debt,
            deltaMinutesVsPrevious: delta,
            best: best,
            worst: worst,
            durationChart: days.map { DailyValue(date: $0, value: byDay[$0]?.durationHours ?? 0) },
            qualityChart: days.map { DailyValue(date: $0, value: Double(byDay[$0]?.quality ?? 0)) }
        )
    }

    static func summary(report: SleepWeekReport, goalHours: Double) -> String {
        guard let average = report.averageHours else {
            return "Bu hafta henüz uyku kaydın yok."
        }
        let diffMinutes = Int(((average - goalHours) * 60).rounded())
        var text = "Bu hafta ortalama \(durationText(hours: average)) uyudun"
        if abs(diffMinutes) < 15 {
            text += "; hedefine çok yakın."
        } else if diffMinutes < 0 {
            text += "; hedefinin \(durationText(hours: Double(-diffMinutes) / 60)) altında."
        } else {
            text += "; hedefinin \(durationText(hours: Double(diffMinutes) / 60)) üzerinde."
        }

        if let delta = report.deltaMinutesVsPrevious, abs(delta) >= 10 {
            text += " Geçen haftaya göre \(delta > 0 ? "+" : "−")\(abs(delta)) dk."
        }
        if report.recorded.count >= 2, let best = report.best {
            let weekday = best.day.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "tr_TR")))
            text += " En iyi gecen \(weekday) (\(durationText(hours: best.durationHours)), \(best.quality) yıldız)."
        }
        return text
    }

    // MARK: Düzen
    /// Son kayıtlardaki yatış ve uyanış saati sapmasına göre 0–100 skor. En az 3 kayıt gerekir.
    static func regularity(records: [SleepRecord], calendar: Calendar = .current, limit: Int = 14) -> SleepRegularity? {
        let recent = records.sorted { $0.day > $1.day }.prefix(limit)
        guard recent.count >= 3 else { return nil }

        let bedtimes = recent.map { Double(normalizedBedtime(minutesOfDay($0.bedtime, calendar))) }
        let wakes = recent.map { Double(minutesOfDay($0.wakeTime, calendar)) }

        let deviation = (standardDeviation(bedtimes) + standardDeviation(wakes)) / 2
        let score = Int((100 * max(0, 1 - deviation / 120)).rounded())

        return SleepRegularity(
            score: score,
            averageBedtimeMinutes: Int((mean(bedtimes) ?? 0).rounded()) % 1_440,
            averageWakeMinutes: Int((mean(wakes) ?? 0).rounded()) % 1_440
        )
    }

    static func minutesOfDay(_ date: Date, _ calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// 12:00'den önceki yatış saatleri ertesi güne taşınır; böylece 23:30 ile 00:30 arası 60 dk olur.
    static func normalizedBedtime(_ minutes: Int) -> Int {
        minutes < 12 * 60 ? minutes + 1_440 : minutes
    }

    // MARK: Biçimlendirme
    static func durationText(hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        let h = total / 60
        let m = total % 60
        if h == 0 { return "\(m) dk" }
        return m == 0 ? "\(h) sa" : "\(h) sa \(m) dk"
    }

    static func timeText(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: İstatistik yardımcıları
    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard let average = mean(values), values.count > 1 else { return 0 }
        let variance = values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(values.count)
        return variance.squareRoot()
    }
}

// MARK: - İdeal yatış saati
enum SleepPlanner {
    static let cycleMinutes = 90
    static let fallAsleepMinutes = 15

    /// Hedef uyanış saatine göre 4, 5 ve 6 döngülük yatış saatleri. Hedef süreye en yakın olan "önerilen"dir;
    /// eşitlikte daha uzun uyku tercih edilir.
    static func suggestions(wakeMinutes: Int, goalHours: Double) -> [BedtimeSuggestion] {
        let goalMinutes = goalHours * 60
        var recommended = 5
        var bestGap = Double.greatestFiniteMagnitude
        for cycles in (4...6).reversed() {
            let gap = abs(Double(cycles * cycleMinutes) - goalMinutes)
            if gap < bestGap {
                bestGap = gap
                recommended = cycles
            }
        }

        return (4...6).reversed().map { cycles in
            let raw = wakeMinutes - cycles * cycleMinutes - fallAsleepMinutes
            let bedtime = ((raw % 1_440) + 1_440) % 1_440
            return BedtimeSuggestion(cycles: cycles, bedtimeMinutes: bedtime, isRecommended: cycles == recommended)
        }
    }

    /// Hedef süreye en uygun döngü sayısının yatış saati (günün dakikası).
    static func recommendedBedtimeMinutes(wakeMinutes: Int, goalHours: Double) -> Int {
        suggestions(wakeMinutes: wakeMinutes, goalHours: goalHours)
            .first(where: \.isRecommended)?.bedtimeMinutes ?? 23 * 60
    }
}
