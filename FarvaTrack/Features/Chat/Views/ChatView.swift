import SwiftUI

/// Sohbet sekmesinin kökü: eşleşme yoksa davet ekranı, varsa konuşma.
struct ChatView: View {
    @Environment(ChatViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Group {
                switch viewModel.phase {
                case .idle, .loading:
                    ProgressView("Sohbet yükleniyor…")
                        .tint(Color.ftAccentLight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unpaired:
                    ChatPairingView()
                case .ready:
                    ChatConversationView()
                }
            }
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle(viewModel.phase == .ready ? viewModel.partnerName : "Sohbet")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Bir sorun oluştu", isPresented: $viewModel.hasError) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .onAppear { viewModel.setVisible(true) }
        .onDisappear { viewModel.setVisible(false) }
        .task {
            // "Yazıyor…" ve düzenleme süresi gibi zamana bağlı bilgileri tazeler.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                viewModel.tick()
            }
        }
    }
}

// MARK: - Eşleşme

struct ChatPairingView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @FocusState private var codeFocused: Bool
    @State private var copied = false

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.ftAccentLight)
                        .accessibilityHidden(true)
                    Text("Özel sohbetini başlat")
                        .font(.title2.bold())
                    Text("Sohbet yalnızca iki kişi arasındadır. Biriniz davet kodu oluşturur, diğeriniz bu kodu girer; sohbeti yalnızca siz ikiniz görebilirsiniz.")
                        .font(.subheadline)
                        .foregroundStyle(Color.ftTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                inviteCard
                redeemCard(code: $viewModel.inviteCodeInput)
            }
            .padding(Constants.Layout.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Davet kodu oluştur", systemImage: "qrcode")
                .font(.headline)

            if let invite = viewModel.invite {
                Text(invite.code)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .kerning(6)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
                    .accessibilityLabel("Davet kodun: \(invite.code.map(String.init).joined(separator: " "))")

                Text("Kod \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened)) tarihine kadar geçerli. Karşı taraf kodu girince sohbet kendiliğinden açılır.")
                    .font(.footnote)
                    .foregroundStyle(Color.ftTextSecondary)

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = invite.code
                        copied = true
                        Haptics.success()
                    } label: {
                        Label(copied ? "Kopyalandı" : "Kopyala", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Davet kodunu panoya kopyalar")

                    ShareLink(item: "FarvaTrack sohbet davet kodum: \(invite.code)") {
                        Label("Paylaş", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .tint(Color.ftAccentLight)

                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Eşleşme bekleniyor…")
                        .font(.footnote)
                        .foregroundStyle(Color.ftTextSecondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Kodu sohbet edeceğin kişiye gönder. Kod 24 saat geçerlidir ve yalnızca bir kez kullanılabilir.")
                    .font(.footnote)
                    .foregroundStyle(Color.ftTextSecondary)
                Button("Kod oluştur") {
                    Haptics.impact(.light)
                    Task { await viewModel.createInvite() }
                }
                .buttonStyle(PrimaryButtonStyle(isLoading: viewModel.isWorking))
                .disabled(viewModel.isWorking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func redeemCard(code: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Kodun var mı?", systemImage: "key.fill")
                .font(.headline)

            TextField("Örn. K7P2QX", text: code)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFocused)
                .padding(.horizontal, 14)
                .frame(height: Constants.Layout.fieldHeight)
                .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .submitLabel(.join)
                .onSubmit(redeem)
                .accessibilityLabel("Davet kodu")
                .accessibilityHint("Karşı tarafın gönderdiği \(ChatInviteCode.length) karakterlik kodu yaz")

            Button("Eşleş", action: redeem)
                .buttonStyle(PrimaryButtonStyle(isLoading: viewModel.isWorking))
                .disabled(viewModel.isWorking || code.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func redeem() {
        codeFocused = false
        Task {
            if await viewModel.redeemInvite() {
                Haptics.success()
            } else {
                Haptics.error()
            }
        }
    }
}
