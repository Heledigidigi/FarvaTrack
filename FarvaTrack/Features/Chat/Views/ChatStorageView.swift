import SwiftUI

/// Ayarlar → Sohbet → Bulut depolaması.
struct ChatStorageView: View {
    @State private var viewModel = ChatStorageViewModel()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Kullanılan")
                        Spacer()
                        if viewModel.isLoading && viewModel.usage == nil {
                            ProgressView()
                        } else {
                            Text(viewModel.usageText).foregroundStyle(Color.ftTextSecondary)
                        }
                    }
                    ProgressView(value: viewModel.usage?.fraction ?? 0)
                        .tint((viewModel.usage?.fraction ?? 0) > 0.85 ? Color.ftWarning : Color.ftAccentLight)
                        .accessibilityLabel("Bulut depolaması")
                        .accessibilityValue(viewModel.usageText)
                    if let originals = viewModel.originalsText {
                        Text(originals).font(.footnote).foregroundStyle(Color.ftTextSecondary)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Fotoğraf ve videoların orijalleri karşı taraf aldıktan 60 gün sonra buluttan kaldırılır. Alan 9 GB'ı geçerse en eskilerden başlanır. Sohbetteki önizlemeler, sesli mesajlar ve sticker'lar kalır; orijaller her iki cihazda da durur.")
            }
            .listRowBackground(Color.ftCard)

            Section {
                Button {
                    Haptics.impact(.light)
                    Task { await viewModel.cleanNow() }
                } label: {
                    HStack {
                        Label("Eski orijalleri şimdi temizle", systemImage: "sparkles")
                        if viewModel.isCleaning {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isCleaning)
            } footer: {
                if let message = viewModel.resultMessage ?? viewModel.errorMessage {
                    Text(message)
                }
            }
            .listRowBackground(Color.ftCard)
        }
        .scrollContentBackground(.hidden)
        .ftScreenBackground()
        .navigationTitle("Bulut depolaması")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }
}
