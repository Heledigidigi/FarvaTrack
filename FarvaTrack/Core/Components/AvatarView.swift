import SwiftUI

/// Profil fotoğrafı; yoksa baş harfler (o da yoksa kişi simgesi).
struct AvatarView: View {
    let name: String
    let photoURL: String?

    private var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.ftAccent, Color.ftAccentLight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            if let url = photoURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsView
                }
                .clipShape(Circle())
            } else {
                initialsView
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var initialsView: some View {
        if initials.isEmpty {
            Image(systemName: "person.fill").foregroundStyle(.white)
        } else {
            Text(initials)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
}
