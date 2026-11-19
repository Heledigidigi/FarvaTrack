import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var showSignOutDialog = false
    @State private var unsyncedCount = 0

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section("Genel") {
                NavigationLink {
                    RemindersView()
                } label: {
                    Label("Hatırlatıcılar", systemImage: "bell.badge")
                }
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: url) {
                        Label("Bildirim izinleri", systemImage: "bell")
                    }
                }
                if let url = URL(string: "x-apple-health://") {
                    Link(destination: url) {
                        Label("Sağlık verisi izinleri", systemImage: "heart.text.square")
                    }
                }
            }
            .listRowBackground(Color.ftCard)

            Section("Hakkında") {
                LabeledContent("Sürüm", value: version)
                if let url = URL(string: Constants.Links.privacyPolicy) {
                    Link("Gizlilik Politikası", destination: url)
                }
                if let url = URL(string: Constants.Links.termsOfUse) {
                    Link("Kullanım Koşulları", destination: url)
                }
            }
            .listRowBackground(Color.ftCard)

            Section {
                Button {
                    if let id = auth.currentUser?.id {
                        unsyncedCount = LocalDataCleaner.unsyncedCount(userID: id, context: modelContext)
                    }
                    showSignOutDialog = true
                } label: {
                    Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .listRowBackground(Color.ftCard)

            Section {
                NavigationLink {
                    DeleteAccountView()
                } label: {
                    Label("Hesabı Sil", systemImage: "trash")
                        .foregroundStyle(Color.ftDanger)
                }
            } footer: {
                Text("Hesabın ve tüm verilerin kalıcı olarak silinir.")
            }
            .listRowBackground(Color.ftCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Ayarlar")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Çıkış yapmak istiyor musun?", isPresented: $showSignOutDialog, titleVisibility: .visible) {
            Button("Çıkış Yap") { auth.signOut() }
            Button("Çıkış Yap ve Bu Cihazdaki Verileri Sil", role: .destructive) { signOutAndWipe() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(unsyncedCount > 0
                 ? "Buluta henüz yüklenmemiş \(unsyncedCount) kaydın var. Cihaz verilerini silersen bu kayıtlar kaybolur."
                 : "Verilerin hesabında kalır; tekrar giriş yapınca geri gelir.")
        }
    }

    private func signOutAndWipe() {
        if let id = auth.currentUser?.id {
            LocalDataCleaner.wipe(userID: id, context: modelContext)
        }
        auth.signOut()
    }
}

// MARK: - Hesabı sil
struct DeleteAccountView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = AccountDeletionViewModel()

    private var confirmedBinding: Binding<Bool> {
        Binding(get: { viewModel.confirmed }, set: { viewModel.confirmed = $0 })
    }

    private var passwordBinding: Binding<String> {
        Binding(get: { viewModel.password }, set: { viewModel.password = $0 })
    }

    private var failureBinding: Binding<Bool> {
        Binding(get: { viewModel.hasFailure }, set: { viewModel.hasFailure = $0 })
    }

    var body: some View {
        Form {
            Section {
                Label("Bu işlem geri alınamaz", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.ftDanger)
                Text("Hesabın ve ona bağlı tüm veriler (antrenmanlar, beslenme, su, uyku, kilo ve ölçüler, rozetler, profil fotoğrafı) sunucudan ve bu cihazdan kalıcı olarak silinir. İşlem için internet bağlantısı gerekir.")
                    .font(.subheadline)
                    .foregroundStyle(Color.ftTextSecondary)
            }

            Section {
                Toggle("Ne sildiğimi anlıyorum", isOn: confirmedBinding)
            }

            if viewModel.usesApple {
                Section {
                    SignInWithAppleButton(.continue) { request in
                        viewModel.configureAppleRequest(request)
                    } onCompletion: { result in
                        Task { await viewModel.deleteWithApple(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: Constants.Layout.fieldHeight)
                    .disabled(!viewModel.confirmed || viewModel.isWorking)
                    .opacity(viewModel.confirmed ? 1 : 0.5)
                } header: {
                    Text("Apple ile doğrula")
                } footer: {
                    Text("Güvenliğin için kimliğini Apple ile yeniden doğrulaman gerekir.")
                }
            }

            if viewModel.usesPassword {
                Section {
                    SecureField("Şifren", text: passwordBinding)
                        .textContentType(.password)
                    Button(role: .destructive) {
                        Task { await viewModel.deleteWithPassword() }
                    } label: {
                        Text("Hesabımı Kalıcı Olarak Sil")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!viewModel.canSubmitPassword)
                } header: {
                    Text("Şifreni gir")
                } footer: {
                    Text("Güvenliğin için şifreni yeniden girmen gerekir.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Hesabı Sil")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { progressOverlay }
        .interactiveDismissDisabled(viewModel.isWorking)
        .navigationBarBackButtonHidden(viewModel.isWorking)
        .alert("Hesap silinemedi", isPresented: failureBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.failureMessage ?? "")
        }
        .onChange(of: auth.currentUser, initial: true) { _, user in
            if let user { viewModel.configure(user: user, context: modelContext) }
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if case .working(let text) = viewModel.phase {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text(text)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Text("Lütfen uygulamayı kapatma.")
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                .padding(24)
                .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }
}