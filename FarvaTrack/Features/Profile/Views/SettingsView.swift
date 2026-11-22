import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @AppStorage(ChatMediaPreferences.autoSaveKey) private var autoSaveChatMedia = true
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            if let user = auth.currentUser {
                Section("Hesap") {
                    HStack {
                        Text("E-posta")
                        Spacer()
                        Text(user.email).foregroundStyle(Color.ftTextSecondary).lineLimit(1)
                    }
                    if auth.usesPasswordSignIn {
                        Button {
                            auth.email = user.email
                            Task { await auth.sendPasswordReset() }
                        } label: {
                            Label("Şifre sıfırlama bağlantısı gönder", systemImage: "key.fill")
                        }
                        .disabled(auth.isWorking)
                    }
                }
                .listRowBackground(Color.ftCard)

                Section("Bildirimler") {
                    NavigationLink {
                        RemindersView()
                    } label: {
                        Label("Hatırlatıcılar", systemImage: "bell.badge.fill")
                    }
                }
                .listRowBackground(Color.ftCard)

                Section {
                    Toggle(isOn: Binding(get: { !PushManager.shared.muted }, set: { PushManager.shared.muted = !$0 })) {
                        Label("Sohbet bildirimleri", systemImage: "bell.badge")
                    }
                    .tint(Color.ftAccent)
                    .accessibilityHint(PushManager.shared.statusText)
                    Toggle(isOn: $autoSaveChatMedia) {
                        Label("Gelen fotoğraf ve videoları Fotoğraflar'a kaydet", systemImage: "photo.on.rectangle.angled")
                    }
                    .tint(Color.ftAccent)
                    NavigationLink {
                        ChatStorageView()
                    } label: {
                        Label("Bulut depolaması", systemImage: "externaldrive.fill.badge.icloud")
                    }
                } header: {
                    Text("Sohbet")
                } footer: {
                    Text("\(PushManager.shared.statusText) Fotoğraf kaydetme açıkken karşı taraftan gelen fotoğraf ve videolar orijal kalitesinde Fotoğraflar'a eklenir.")
                }
                .listRowBackground(Color.ftCard)

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Dışa aktarılan dosyayı paylaş", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            export(user)
                        } label: {
                            Label("Verilerimi dışa aktar (JSON)", systemImage: "arrow.down.doc.fill")
                        }
                    }
                } header: {
                    Text("Veriler")
                } footer: {
                    Text(exportError ?? "Antrenman, beslenme, su, uyku, kilo, ölçü ve sayaç kayıtlarının tamamı tek bir dosyaya yazılır.")
                }
                .listRowBackground(Color.ftCard)

                Section {
                    NavigationLink {
                        DeleteAccountView()
                    } label: {
                        Label("Hesabı sil", systemImage: "trash.fill")
                            .foregroundStyle(Color.ftDanger)
                    }
                }
                .listRowBackground(Color.ftCard)
            }

            Section("Hakkında") {
                HStack {
                    Text("Sürüm")
                    Spacer()
                    Text(appVersion).monospacedDigit().foregroundStyle(Color.ftTextSecondary)
                }
                Text("FarvaTrack sağlık verilerini genel takip amacıyla gösterir; tıbbi teşhis veya tedavi yerine geçmez.")
                    .font(.footnote)
                    .foregroundStyle(Color.ftTextSecondary)
            }
            .listRowBackground(Color.ftCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Ayarlar")
    }

    private func export(_ user: AppUser) {
        do {
            exportURL = try DataExporter.writeFile(user: user, context: modelContext)
            exportError = nil
            Haptics.success()
        } catch {
            exportError = "Dışa aktarılamadı: \(error.localizedDescription)"
            Haptics.error()
        }
    }
}

// MARK: - Hesap silme
struct DeleteAccountView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var password = ""
    @State private var understood = false
    @State private var showConfirmation = false

    private var canDelete: Bool {
        understood && !auth.isWorking && (!auth.usesPasswordSignIn || !password.isEmpty)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Bu işlem geri alınamaz", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(Color.ftDanger)
                    Text("Hesabınla birlikte şunlar kalıcı olarak silinir:")
                    Text("• Profilin ve profil fotoğrafın\n• Antrenman, beslenme, su, uyku, kilo ve ölçü kayıtların\n• Biyolojik atık sayacı kayıtların\n• Özel yiyecek ve egzersizlerin, favorilerin")
                        .font(.subheadline)
                        .foregroundStyle(Color.ftTextSecondary)
                    Text("İstersen önce Ayarlar → Verilerimi dışa aktar ile bir kopyasını alabilirsin.")
                        .font(.footnote)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                .padding(.vertical, 4)
            }

            if auth.usesPasswordSignIn {
                Section("Kimliğini doğrula") {
                    SecureField("Şifren", text: $password)
                        .textContentType(.password)
                }
            }

            Section {
                Toggle("Verilerimin geri alınamayacak şekilde silineceğini anlıyorum", isOn: $understood)
            }

            Section {
                Button(role: .destructive) {
                    showConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if auth.isWorking { ProgressView() } else { Text("Hesabımı Kalıcı Olarak Sil").bold() }
                        Spacer()
                    }
                }
                .disabled(!canDelete)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Hesabı Sil")
        .confirmationDialog("Hesabın ve tüm verilerin silinecek.", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                Task {
                    let deleted = await auth.deleteAccount(password: password)
                    if !deleted { password = "" }
                }
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}
