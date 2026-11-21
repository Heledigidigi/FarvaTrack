import SwiftUI

struct ProfileView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var showSignOutConfirmation = false
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            List {
                if let user = auth.currentUser {
                    Section {
                        Button {
                            showEditor = true
                        } label: {
                            header(user)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Profili düzenle")
                    }
                    .listRowBackground(Color.ftCard)

                    Section {
                        goalRow("Kalori", "flame.fill", "\(user.dailyCalorieGoal.formatted()) kcal", Color.ftCalories)
                        goalRow("Su", "drop.fill", "\(user.dailyWaterGoalMl.formatted()) ml", Color.ftWater)
                        goalRow("Adım", "figure.walk", user.dailyStepGoal.formatted(), Color.ftAccentLight)
                        goalRow("Uyku", "moon.stars.fill", "\(user.sleepGoalHours.formatted()) saat", Color.ftSleep)
                        Button {
                            showEditor = true
                        } label: {
                            Label("Profili ve hedefleri düzenle", systemImage: "pencil")
                        }
                    } header: {
                        Text("Günlük hedeflerin")
                    }
                    .listRowBackground(Color.ftCard)
                }

                Section {
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        Label("İstatistikler ve Rozetler", systemImage: "chart.xyaxis.line")
                    }
                    NavigationLink {
                        RemindersView()
                    } label: {
                        Label("Hatırlatıcılar", systemImage: "bell.badge.fill")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Ayarlar", systemImage: "gearshape.fill")
                    }
                }
                .listRowBackground(Color.ftCard)

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
            .sheet(isPresented: $showEditor) {
                EditProfileView()
            }
            .authAlerts()
            .confirmationDialog("Çıkış yapmak istiyor musun?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Çıkış Yap", role: .destructive) { auth.signOut() }
                Button("Vazgeç", role: .cancel) {}
            }
        }
    }

    private func header(_ user: AppUser) -> some View {
        HStack(spacing: 14) {
            AvatarView(name: user.displayName, photoURL: user.photoURL)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(user.displayName.isEmpty ? "Kullanıcı" : user.displayName)
                        .font(.headline)
                    if user.isAdmin {
                        Text("Yönetici")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.ftAccent, in: Capsule())
                    }
                }
                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(Color.ftTextSecondary)
                if let details = details(user) {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.ftTextSecondary.opacity(0.6))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func details(_ user: AppUser) -> String? {
        var parts: [String] = []
        if let age = user.age { parts.append("\(age) yaş") }
        if let height = user.heightCm { parts.append("\(Int(height)) cm") }
        if let weight = user.weightKg { parts.append(WeightAnalyzer.kgText(weight)) }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
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
