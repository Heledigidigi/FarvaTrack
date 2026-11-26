import SwiftUI

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
