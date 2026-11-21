import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ProfileDraft?
    @State private var photoItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let user = auth.currentUser, draft != nil {
                    form(user: user)
                } else {
                    ProgressView()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle("Profili Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { Task { await save() } }
                        .disabled(isSaving || draft == nil)
                }
            }
            .alert("Kaydedilemedi", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(localError ?? "")
            }
            .onAppear {
                if draft == nil, let user = auth.currentUser { draft = ProfileDraft(user: user) }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await upload(item) }
            }
        }
    }

    // MARK: - Form
    @ViewBuilder
    private func form(user: AppUser) -> some View {
        let binding = Binding<ProfileDraft>(get: { draft ?? ProfileDraft(user: user) }, set: { draft = $0 })
        let current = binding.wrappedValue

        Form {
            Section {
                HStack(spacing: 16) {
                    AvatarView(name: current.displayName, photoURL: user.photoURL)
                        .frame(width: 72, height: 72)
                        .overlay {
                            if auth.isWorking { ProgressView().tint(.white) }
                        }
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Fotoğraf seç", systemImage: "photo")
                        }
                        if user.photoURL != nil {
                            Button("Fotoğrafı kaldır", role: .destructive) {
                                Task {
                                    await auth.removeProfilePhoto()
                                    _ = takeAuthError()
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Kişisel") {
                TextField("Ad Soyad", text: binding.displayName)
                    .textContentType(.name)
                DatePicker(
                    "Doğum tarihi",
                    selection: Binding(
                        get: { current.birthDate ?? Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now },
                        set: { binding.wrappedValue.birthDate = $0 }
                    ),
                    in: ...Date.now,
                    displayedComponents: .date
                )
                Picker("Cinsiyet", selection: binding.gender) {
                    Text("Belirtilmedi").tag(Gender?.none)
                    ForEach(Gender.allCases) { Text($0.title).tag(Gender?.some($0)) }
                }
                Stepper(value: Binding(
                    get: { current.heightCm ?? 170 },
                    set: { binding.wrappedValue.heightCm = $0 }
                ), in: ProfileDraft.heightRange, step: 1) {
                    valueRow("Boy", current.heightCm.map { "\(Int($0)) cm" } ?? "—")
                }
            }

            Section {
                Picker("Hedef", selection: binding.goal) {
                    ForEach(FitnessGoal.allCases) { goal in
                        Text(goal.title).tag(goal)
                    }
                }
                Picker("Aktivite", selection: binding.activity) {
                    ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Hedef ve aktivite")
            } footer: {
                if current.isMinor() {
                    Text("18 yaşından küçükler için kilo verme hedefi seçilemez.")
                }
            }

            Section {
                Stepper(value: binding.dailyCalorieGoal, in: ProfileDraft.calorieRange, step: 50) {
                    valueRow("Kalori", "\(current.dailyCalorieGoal.formatted()) kcal")
                }
                Stepper(value: binding.dailyWaterGoalMl, in: ProfileDraft.waterRange, step: 100) {
                    valueRow("Su", "\(current.dailyWaterGoalMl.formatted()) ml")
                }
                Stepper(value: binding.dailyStepGoal, in: ProfileDraft.stepRange, step: 500) {
                    valueRow("Adım", current.dailyStepGoal.formatted())
                }
                Stepper(value: binding.sleepGoalHours, in: ProfileDraft.sleepRange, step: 0.5) {
                    valueRow("Uyku", "\(current.sleepGoalHours.formatted()) saat")
                }

                if let recommendation = current.recommendation(weightKg: user.weightKg) {
                    Button {
                        Haptics.selection()
                        binding.wrappedValue.applyRecommendation(recommendation)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Önerilen hedefleri uygula", systemImage: "wand.and.stars")
                            Text("\(recommendation.calorieGoal.formatted()) kcal • \(recommendation.waterGoalMl.formatted()) ml • \(recommendation.stepGoal.formatted()) adım • \(recommendation.sleepHours.formatted()) sa")
                                .font(.caption)
                                .foregroundStyle(Color.ftTextSecondary)
                        }
                    }
                }
            } header: {
                Text("Günlük hedefler")
            } footer: {
                Text("Öneriler boy, kilo, yaş ve aktiviteye göre genel formüllerle hesaplanır; kişisel bir tavsiye değildir. Kilonu Kilo ekranından güncelleyebilirsin.")
            }
        }
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(Color.ftTextSecondary)
        }
    }

    // MARK: - Aksiyonlar
    private func save() async {
        guard let draft, let user = auth.currentUser else { return }
        if let error = draft.validationError() {
            localError = error
            Haptics.error()
            return
        }
        isSaving = true
        defer { isSaving = false }
        await auth.updateUser(draft.applied(to: user))
        if !takeAuthError() { dismiss() }
    }

    /// Hata ana ekranda değil bu sayfada gösterilsin (sayfa açıkken üst görünüm uyarı gösteremez).
    private func takeAuthError() -> Bool {
        guard let message = auth.errorMessage else { return false }
        localError = message
        auth.errorMessage = nil
        return true
    }

    private func upload(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = ImageCompressor.squareJPEG(from: data) else {
            localError = "Fotoğraf okunamadı."
            return
        }
        await auth.updateProfilePhoto(jpeg)
        _ = takeAuthError()
    }
}

/// Profil fotoğrafını kare kırpıp küçültür (Storage maliyeti ve yükleme süresi için).
enum ImageCompressor {
    static func squareJPEG(from data: Data, side: CGFloat = 512, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let length = min(image.size.width, image.size.height)
        guard length > 0 else { return nil }
        let scale = side / length
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: size))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
