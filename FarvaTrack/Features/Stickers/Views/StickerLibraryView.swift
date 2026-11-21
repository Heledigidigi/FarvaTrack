import SwiftUI
import PhotosUI

/// Kişisel sticker kütüphanesi: yeni sticker oluşturma, listeleme, silme. İki cihaz arasında senkron.
/// (Sohbette gönderme ve serbest yerleştirme Aşama 8E'de.)
struct StickerLibraryView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var library: StickerLibraryViewModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var editorInput: EditorInput?
    @State private var isLoadingPhoto = false
    @State private var pendingDelete: StickerItem?

    struct EditorInput: Identifiable {
        let id = UUID()
        let data: Data
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    /// Sohbetteki sticker paneliyle aynı kütüphane modeli paylaşılabilir.
    init(library: StickerLibraryViewModel = StickerLibraryViewModel()) {
        _library = State(initialValue: library)
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.stickers.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(library.stickers) { sticker in
                                cell(sticker)
                            }
                        }
                        .padding(Constants.Layout.screenPadding)
                    }
                }
            }
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle("Sticker'larım")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        if isLoadingPhoto { ProgressView() } else { Image(systemName: "plus") }
                    }
                    .accessibilityLabel("Fotoğraftan yeni sticker oluştur")
                }
                ToolbarItem(placement: .status) {
                    if library.isSyncing {
                        Label("Eşitleniyor", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                isLoadingPhoto = true
                Task {
                    defer {
                        isLoadingPhoto = false
                        pickerItem = nil
                    }
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        editorInput = EditorInput(data: data)
                    } else {
                        library.errorMessage = "Fotoğraf açılamadı."
                    }
                }
            }
            .fullScreenCover(item: $editorInput) { input in
                StickerEditorView(imageData: input.data) { result in
                    do {
                        try library.add(result)
                    } catch {
                        library.errorMessage = AppError.map(error).errorDescription
                    }
                }
            }
            .confirmationDialog("Sticker silinsin mi?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { sticker in
                Button("Sil", role: .destructive) {
                    library.delete(sticker.id)
                    Haptics.impact(.medium)
                }
                Button("Vazgeç", role: .cancel) {}
            } message: { _ in
                Text("Sticker iki cihazından da kaldırılır.")
            }
            .alert("Bir sorun oluştu", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(library.errorMessage ?? "")
            }
        }
        .task(id: auth.currentUser?.id) {
            guard let userID = auth.currentUser?.id else { return }
            library.configure(context: modelContext, userID: userID)
            await library.syncAll()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "face.smiling.inverse")
                .font(.system(size: 48))
                .foregroundStyle(Color.ftAccentLight)
                .accessibilityHidden(true)
            Text("Henüz sticker yok")
                .font(.title3.bold())
            Text("Bir fotoğraf seç; arka planı cihazında otomatik kaldırılır, sonra silgi ve onar fırçasıyla düzeltip yazı ve emoji ekleyebilirsin.")
                .font(.subheadline)
                .foregroundStyle(Color.ftTextSecondary)
                .multilineTextAlignment(.center)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Fotoğraf seç", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(PrimaryButtonStyle(isLoading: isLoadingPhoto))
            .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cell(_ sticker: StickerItem) -> some View {
        ZStack(alignment: .topTrailing) {
            CachedImageView(url: sticker.fileURL, contentMode: .fit)
                .padding(8)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !sticker.isSynced {
                Image(systemName: "icloud.slash")
                    .font(.caption2)
                    .padding(5)
                    .foregroundStyle(Color.ftTextSecondary)
                    .accessibilityLabel("Henüz eşitlenmedi")
            }
        }
        .contextMenu {
            Button(role: .destructive) { pendingDelete = sticker } label: { Label("Sil", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sticker.isSynced ? "Sticker" : "Sticker, henüz eşitlenmedi")
        .accessibilityAction(named: "Sil") { pendingDelete = sticker }
    }
}
