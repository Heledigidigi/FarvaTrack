import SwiftUI

/// Henüz eklenmemiş modüller için geçici ekran (sonraki aşamalarda kaldırılacak).
struct ComingSoonView: View {
    let title: String
    let systemImage: String
    var message = "Bu bölüm bir sonraki aşamada ekleniyor."

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 52))
                .foregroundStyle(Color.ftAccentLight)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .combine)
    }
}
