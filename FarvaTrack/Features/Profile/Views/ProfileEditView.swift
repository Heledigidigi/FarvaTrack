import SwiftUI
import PhotosUI

struct ProfileEditView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = ProfileViewModel()
    @State private var draft: ProfileDraft?
    @State private var original: ProfileDraft?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showRemovePhotoConfirmation = false
    @State private var showRecalcDialog = false
    @State private var errorText: String?

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorText != nil || viewModel.hasError }, set: { if !$0 { errorText = nil; viewModel.hasError = false } })
    }

    private var hasChanges: Bool { draft != original }

    var body: some View {
        Form {
            if let user = auth.currentUser {
                photoSection(user)
            }

            if draft != nil {
                Section("Kişisel bilgiler") {
                    TextField("Ad Soyad", text: binding(\.displayName))
                        .textContentType(.name)

                    DatePicker(
                        "Doğum tarihi",
                        selection: binding(\.birthDate),
                        in: birthDateRange,
                        displayedComponents: .date
                    )
                    .environment(\.locale, Locale(identifier: "tr_TR"))

                    Picker("Cinsiyet", selection: binding(\.gender)) {
                        Text("Seçilmedi").tag(Gender?.none)
                        ForEach(Gender.allCases) { Text($0.title).tag(Gender?.some($0)) }
                    }

                    HStack {
                        Text("Boy")
                        Spacer()
                        TextField("170", value: binding(\.heightCm), format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("cm").foregroundStyle(Color.ftTextSecondary)
                    }
                }

                Section {
                    Picker("Aktivite düzeyi", selection: binding(\.activityLevel)) {
                        ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Hedef", selection: binding(\.goal)) {
                        ForEach(FitnessGoal.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Hedefler")
                } footer: {
                    Text("Bu bilgiler günlük kalori, su ve adım hedeflerinin hesabında kullanılır. Kilo, Kilo ekranından güncellenir.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Profili Düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") { save() }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Bitti") { hideKeyboard() }
            }
        }
        .confirmationDialog("Fotoğraf kaldırılsın mı?", isPresented: $showRemovePhotoConfirmation, titleVisibility: .visible) {
            Button("Kaldır", role: .destructive) { Task { await viewModel.removePhoto() } }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog("Hedeflerini yeniden hesaplayalım mı?", isPresented: $showRecalcDialog, titleVisibility: .visible) {
            Button("Yeniden Hesapla") {
                Task {
                    await viewModel.acceptRecalculation()
                    dismiss()
                }
            }
            Button("Şimdi değil", role: .cancel) {
                viewModel.dismissRecalculation()
                dismiss()
            }
        } message: {
            Text("Profil bilgilerin değişti. Günlük kalori, su ve uyku hedeflerin yeni bilgilerine göre güncellenebilir.")
        }
        .alert("Bir sorun oluştu", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorText ?? viewModel.errorMessage ?? "")
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await viewModel.uploadPhoto(data)
                } else {
                    errorText = "Fotoğraf okunamadı."
                }
                pickerItem = nil
            }
        }
        .onChange(of: auth.currentUser, initial: true) { _, user in
            guard let user else { return }
            viewModel.configure(user: user) { updated in await auth.updateUser(updated) }
            if draft == nil {
                let initial = ProfileDraft(user: user)
                draft = initial
                original = initial
            }
        }
    }

    // MARK: - Bölümler
    private func photoSection(_ user: AppUser) -> some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    ZStack {
                        AvatarView(name: user.displayName, photoURL: user.photoURL)
                            .frame(width: 96, height: 96)
                        if viewModel.isUploadingPhoto {
                            Circle().fill(.black.opacity(0.5)).frame(width: 96, height: 96)
                            ProgressView().tint(.white)
                        }
                    }

                    HStack(spacing: 20) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label(user.photoURL == nil ? "Fotoğraf Ekle" : "Değiştir", systemImage: "photo")
                                .font(.subheadline.weight(.semibold))
                        }
                        .disabled(viewModel.isUploadingPhoto)

                        if user.photoURL != nil {
                            Button(role: .destructive) {
                                showRemovePhotoConfirmation = true
                            } label: {
                                Label("Kaldır", systemImage: "trash")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                            .disabled(viewModel.isUploadingPhoto)
                        }
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private var birthDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let oldest = calendar.date(byAdding: .year, value: -Constants.Validation.maxAge, to: .now) ?? .distantPast
        let youngest = calendar.date(byAdding: .year, value: -Constants.Validation.minAge, to: .now) ?? .now
        return oldest...youngest
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ProfileDraft, Value>) -> Binding<Value> {
        Binding(
            get: { draft![keyPath: keyPath] },
            set: { draft?[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Kaydet
    private func save() {
        guard let draft else { return }
        hideKeyboard()
        Task {
            do {
                try await viewModel.save(draft)
                original = draft
                if viewModel.recalcOffer != nil {
                    showRecalcDialog = true
                } else {
                    dismiss()
                }
            } catch {
                errorText = AppError.map(error).errorDescription
                Haptics.error()
            }
        }
    }
}