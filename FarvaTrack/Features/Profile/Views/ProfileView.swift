import SwiftUI

/// Sade profil ekranı. Profil düzenleme, ayarlar ve hesap silme son aşamada eklenecek.
struct ProfileView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var showSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                if let user = auth.currentUser {
                    Section {
                        HStack(spacing: 14) {
                            AvatarView(name: user.displayName, photoURL: user.photoURL)
                                .frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName.isEmpty ? "Kullanıcı" : user.displayName)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.ftTextSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                    .listRowBackground(Color.ftCard)

                    Section("Günlük hedeflerin") {
                        goalRow("Kalori", "flame.fill", "\(user.dailyCalorieGoal) kcal", Color.ftCalories)
                        goalRow("Su", "drop.fill", "\(user.dailyWaterGoalMl) ml", Color.ftWater)
                        goalRow("Adım", "figure.walk", user.dailyStepGoal.formatted(), Color.ftAccentLight)
                        goalRow("Uyku", "moon.stars.fill", "\(user.sleepGoalHours.formatted()) saat", Color.ftSleep)
                    }
                    .listRowBackground(Color.ftCard)
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirmation = true
                    } label: {
                        Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                .listRowBackground(Color.ftCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle("Profil")
            .confirmationDialog("Çıkış yapmak istiyor musun?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Çıkış Yap", role: .destructive) { auth.signOut() }
                Button("Vazgeç", role: .cancel) {}
            }
        }
    }

    private func goalRow(_ title: String, _ systemImage: String, _ value: String, _ tint: Color) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            Spacer()
            Text(value)
                .foregroundStyle(Color.ftTextSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
