import SwiftUI

struct ProfileView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        NavigationStack {
            List {
                if let user = auth.currentUser {
                    Section {
                        header(user)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    Section {
                        summary(user)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    Section("Günlük hedeflerin") {
                        goalRow("Kalori", "flame.fill", "\(user.dailyCalorieGoal) kcal", Color.ftCalories)
                        goalRow("Su", "drop.fill", "\(user.dailyWaterGoalMl) ml", Color.ftWater)
                        goalRow("Adım", "figure.walk", user.dailyStepGoal.formatted(), Color.ftAccentLight)
                        goalRow("Uyku", "moon.stars.fill", "\(user.sleepGoalHours.formatted()) saat", Color.ftSleep)
                    }
                    .listRowBackground(Color.ftCard)

                    Section {
                        NavigationLink {
                            ProfileEditView()
                        } label: {
                            Label("Profili Düzenle", systemImage: "person.crop.circle")
                        }
                        NavigationLink {
                            WeightView()
                        } label: {
                            Label("Kilo ve Ölçüler", systemImage: "scalemass")
                        }
                        NavigationLink {
                            RemindersView()
                        } label: {
                            Label("Hatırlatıcılar", systemImage: "bell.badge")
                        }
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Ayarlar", systemImage: "gearshape")
                        }
                    }
                    .listRowBackground(Color.ftCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle("Profil")
        }
    }

    private func header(_ user: AppUser) -> some View {
        VStack(spacing: 10) {
            AvatarView(name: user.displayName, photoURL: user.photoURL)
                .frame(width: 96, height: 96)

            Text(user.displayName.isEmpty ? "Kullanıcı" : user.displayName)
                .font(.title2.bold())
            Text(user.email)
                .font(.subheadline)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func summary(_ user: AppUser) -> some View {
        HStack(spacing: 12) {
            tile("Yaş", user.age.map { "\($0)" } ?? "—", "yaş")
            tile("Boy", user.heightCm.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—", "cm")
            tile("Kilo", user.weightKg.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—", "kg")
        }
    }

    private func tile(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(unit)
                .font(.caption)
                .foregroundStyle(Color.ftTextSecondary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 14)
        .accessibilityElement(children: .combine)
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