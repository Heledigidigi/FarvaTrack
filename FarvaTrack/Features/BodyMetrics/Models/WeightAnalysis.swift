import Foundation

struct WeightPoint: Equatable, Identifiable {
    let date: Date
    let weightKg: Double
    var id: Date { date }
}

enum BMICategory: Equatable {
    case underweight, normal, overweight, obese

    var title: String {
        switch self {
        case .underweight: return "Normalin altı"
        case .normal: return "Normal"
        case .overweight: return "Normalin üstü"
        case .obese: return "Obezite aralığı"
        }
    }

    init(bmi: Double) {
        switch bmi {
        case ..<18.5: self = .underweight
        case ..<25: self = .normal
        case ..<30: self = .overweight
        default: self = .obese
        }
    }
}

enum WeightGoalValidation: Equatable {
    case ok
    case outOfRange
    /// 18 yaş altında kilo verme hedefi yok.
    case minorWeightLoss
    /// Hedef BMI 18,5'in altında.
    case belowHealthyBMI(minimumKg: Double)

    var message: String? {
        switch self {
        case .ok: return nil
        case .outOfRange: return "Hedef kilo \(Int(WeightAnalyzer.validRange.lowerBound))–\(Int(WeightAnalyzer.validRange.upperBound)) kg arasında olmalı."
        case .minorWeightLoss: return "18 yaşından küçükler için kilo verme hedefi belirlenemez. Hedefini korumak veya bir uzmana danışmak daha uygun."
        case .belowHealthyBMI(let minimum):
            return "Bu hedef sağlıklı aralığın altında kalıyor. Boyuna göre en az \(minimum.formatted(.number.precision(.fractionLength(1)))) kg seçebilirsin."
        }
    }
}

enum WeightAnalyzer {
    static let validRange = 25.0...350.0
    static let minimumHealthyBMI = 18.5

    static func isValid(_ kg: Double) -> Bool { validRange.contains(kg) }

    // MARK: BMI
    static func bmi(weightKg: Double, heightCm: Double) -> Double? {
        guard heightCm > 0, weightKg > 0 else { return nil }
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }

    /// BMI 18,5–24,9 aralığına karşılık gelen kilo aralığı.
    static func healthyRange(heightCm: Double) -> ClosedRange<Double>? {
        guard heightCm > 0 else { return nil }
        let m2 = (heightCm / 100) * (heightCm / 100)
        return (18.5 * m2)...(24.9 * m2)
    }

    static func minimumHealthyWeight(heightCm: Double) -> Double? {
        guard heightCm > 0 else { return nil }
        let m2 = (heightCm / 100) * (heightCm / 100)
        // Bir ondalığa yukarı yuvarla ki önerilen değer gerçekten 18,5'in altında kalmasın.
        return (minimumHealthyBMI * m2 * 10).rounded(.up) / 10
    }

    // MARK: Hedef doğrulama
    static func validateGoal(targetKg: Double, currentKg: Double?, heightCm: Double?, age: Int?) -> WeightGoalValidation {
        guard isValid(targetKg) else { return .outOfRange }
        if let age, age < 18, let currentKg, targetKg < currentKg {
            return .minorWeightLoss
        }
        if let heightCm, let bmi = bmi(weightKg: targetKg, heightCm: heightCm), bmi < minimumHealthyBMI,
           let minimum = minimumHealthyWeight(heightCm: heightCm) {
            return .belowHealthyBMI(minimumKg: minimum)
        }
        return .ok
    }

    // MARK: Trend
    /// Her nokta için kendisi dahil önceki `windowDays` gündeki tartıların ortalaması (tartı dalgalanmasını yumuşatır).
    static func movingAverage(_ points: [WeightPoint], windowDays: Int = 7) -> [WeightPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        return sorted.map { point in
            let start = point.date.addingTimeInterval(-Double(windowDays) * 86_400)
            let window = sorted.filter { $0.date > start && $0.date <= point.date }
            let average = window.reduce(0) { $0 + $1.weightKg } / Double(window.count)
            return WeightPoint(date: point.date, weightKg: average)
        }
    }

    /// Son `days` gün içindeki ilk ve son tartı farkı (kg). En az iki tartı gerekir.
    static func change(_ points: [WeightPoint], days: Int, now: Date = .now) -> Double? {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        let window = points.filter { $0.date >= start && $0.date <= now }.sorted { $0.date < $1.date }
        guard let first = window.first, let last = window.last, window.count >= 2 else { return nil }
        return last.weightKg - first.weightKg
    }

    /// Başlangıçtan hedefe ilerleme oranı (0…1). Hedefe ters yönde gidildiyse 0.
    static func goalProgress(start: Double, current: Double, target: Double) -> Double {
        let total = target - start
        guard abs(total) > 0.05 else { return 1 }
        return min(max((current - start) / total, 0), 1)
    }

    /// Haftalık ortalama değişim (kg/hafta), en az 14 günlük veriyle doğrusal regresyon.
    static func weeklyRate(_ points: [WeightPoint]) -> Double? {
        let sorted = points.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last,
              last.date.timeIntervalSince(first.date) >= 14 * 86_400, sorted.count >= 3 else { return nil }

        let xs = sorted.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = sorted.map(\.weightKg)
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator * 7
    }

    /// Mevcut hızla hedefe yaklaşık kaç hafta kaldığı. Hız hedef yönünde değilse veya çok yavaşsa `nil`.
    static func weeksToGoal(current: Double, target: Double, weeklyRate: Double?) -> Int? {
        guard let weeklyRate, abs(weeklyRate) >= 0.05 else { return nil }
        let remaining = target - current
        guard abs(remaining) > 0.1, remaining.sign == weeklyRate.sign else { return nil }
        let weeks = remaining / weeklyRate
        return weeks < 260 ? Int(weeks.rounded(.up)) : nil
    }

    static func kgText(_ value: Double, signed: Bool = false) -> String {
        let text = abs(value).formatted(.number.precision(.fractionLength(1)))
        guard signed else { return "\(value.formatted(.number.precision(.fractionLength(1)))) kg" }
        if abs(value) < 0.05 { return "0,0 kg" }
        return "\(value > 0 ? "+" : "−")\(text) kg"
    }
}
