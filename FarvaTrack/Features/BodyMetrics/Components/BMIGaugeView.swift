import SwiftUI

/// 15–40 aralığında renkli BMI çubuğu ve işaretçi.
struct BMIGaugeView: View {
    let bmi: Double

    private static let lower = 15.0
    private static let upper = 40.0
    private static let segments: [(end: Double, color: Color)] = [
        (18.5, .ftWater),
        (25, .ftSuccess),
        (30, .ftWarning),
        (40, .ftDanger)
    ]

    private var position: Double {
        (min(max(bmi, Self.lower), Self.upper) - Self.lower) / (Self.upper - Self.lower)
    }

    private var category: BMICategory { BMICategory(bmi: bmi) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("BMI").font(.headline)
                Spacer()
                Text(bmi.formatted(.number.precision(.fractionLength(1))))
                    .font(.title2.bold().monospacedDigit())
                Text(category.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ftTextSecondary)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(Array(Self.segments.enumerated()), id: \.offset) { index, segment in
                            let start = index == 0 ? Self.lower : Self.segments[index - 1].end
                            segment.color
                                .frame(width: max(0, (segment.end - start) / (Self.upper - Self.lower) * width - 2))
                        }
                    }
                    .frame(height: 10)
                    .clipShape(Capsule())

                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .offset(x: position * width - 9)
                }
                .frame(height: 18)
            }
            .frame(height: 18)

            HStack {
                Text("18,5")
                Spacer()
                Text("25")
                Spacer()
                Text("30")
            }
            .font(.caption2)
            .foregroundStyle(Color.ftTextSecondary)
            .padding(.horizontal, 40)

            Text("BMI kas kütlesini ayırt etmez; genel bir göstergedir.")
                .font(.caption2)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vücut kitle indeksi \(bmi.formatted(.number.precision(.fractionLength(1)))), \(category.title)")
    }
}
