import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    var unit: String = ""
    let systemImage: String
    var tint: Color = Color.ftAccentLight
    var progress: Double?
    var subtitle: String?
    var showsChevron = false

    private var clampedProgress: Double {
        min(max(progress ?? 0, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.18), in: Circle())

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ftTextSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.ftTextSecondary.opacity(0.6))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title.bold().monospacedDigit())
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.footnote)
                        .foregroundStyle(Color.ftTextSecondary)
                }
            }

            if progress != nil {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(tint)
                                .frame(width: geometry.size.width * clampedProgress)
                        }
                    }
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: clampedProgress)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.ftTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) \(unit)")
        .accessibilityValue(accessibilityValueText)
    }

    private var accessibilityValueText: String {
        var parts: [String] = []
        if progress != nil { parts.append("hedefin yüzde \(Int(clampedProgress * 100))") }
        if let subtitle { parts.append(subtitle) }
        return parts.joined(separator: ", ")
    }
}
