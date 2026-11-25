import SwiftUI
import UIKit
import PhotosUI

// MARK: - Durum etiketi

struct DietStatusChip: View {
    let status: DietMealStatus?
    var missed = false
    var thirdPerson = false
    var filled = false

    private var title: String {
        guard let status else { return missed ? "İşaretlenmedi" : "Bekliyor" }
        return thirdPerson ? status.thirdPersonTitle : status.title
    }

    static func color(_ status: DietMealStatus?, missed: Bool = false) -> Color {
        switch status {
        case .eaten: return Color.ftSuccess
        case .changed: return Color.ftWarning
        case .skipped: return Color.ftDanger
        default: return missed ? Color.ftDanger.opacity(0.7) : Color.ftTextSecondary
        }
    }

    private var icon: String {
        switch status {
        case .eaten: return "checkmark"
        case .changed: return "arrow.triangle.2.circlepath"
        case .skipped: return "xmark"
        default: return missed ? "exclamationmark" : "clock"
        }
    }

    var body: some View {
        let tint = Self.color(status, missed: missed)
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(filled ? Color.white : tint)
            .background(filled ? tint : tint.opacity(0.15), in: Capsule())
            .accessibilityLabel(title)
    }
}

// MARK: - Makro çubuğu

/// Protein / karbonhidrat / yağ enerji paylarını gösteren yatay çubuk.
struct DietMacroBar: View {
    let nutrition: DietNutrition
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(MacroKind.allCases) { kind in
                    Rectangle()
                        .fill(kind.color)
                        .frame(width: geometry.size.width * nutrition.energyShare(of: kind))
                }
            }
        }
        .frame(height: height)
        .background(Color.ftSubtle(0.12))
        .clipShape(Capsule())
        .accessibilityLabel(nutrition.shareText)
    }
}

/// "P 45 g · %36" sütunları.
struct DietMacroColumns: View {
    let nutrition: DietNutrition
    var target: DietNutrition?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(MacroKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.caption.weight(.semibold)).foregroundStyle(kind.color)
                    if let target {
                        Text("\(Int(nutrition.grams(of: kind).rounded())) / \(Int(target.grams(of: kind).rounded())) g")
                            .font(.caption).foregroundStyle(Color.ftText)
                        ProgressView(value: min(1, target.grams(of: kind) > 0 ? nutrition.grams(of: kind) / target.grams(of: kind) : 0))
                            .tint(kind.color)
                    } else {
                        Text("\(Int(nutrition.grams(of: kind).rounded())) g · %\(Int((nutrition.energyShare(of: kind) * 100).rounded()))")
                            .font(.caption).foregroundStyle(Color.ftText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Gün gezgini

struct DietDayNavigator: View {
    let date: Date
    let subtitle: String?
    var canGoBack = true
    var canGoForward = true
    let onShift: (Int) -> Void

    var body: some View {
        HStack {
            Button { onShift(-1) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
            }
            .disabled(!canGoBack)
            .accessibilityLabel("Önceki gün")
            Spacer()
            VStack(spacing: 1) {
                Text(DietFormat.dayTitle(date)).font(.headline).foregroundStyle(Color.ftText)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Color.ftTextSecondary) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { onShift(1) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Sonraki gün")
        }
        .tint(Color.ftAccentLight)
    }
}

// MARK: - Fotoğraf

/// Öğün fotoğrafı: yerelde yoksa medya sunucusundan indirilir.
struct DietPhotoView: View {
    @Environment(DietStore.self) private var store
    let path: String?
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if path == nil || failed {
                ZStack {
                    Color.ftSubtle(0.08)
                    VStack(spacing: 4) {
                        Image(systemName: "camera").font(.title3)
                        Text("fotoğraf yok").font(.caption2)
                    }
                    .foregroundStyle(Color.ftTextSecondary)
                }
            } else {
                ZStack {
                    Color.ftSubtle(0.08)
                    ProgressView()
                }
            }
        }
        .task(id: path) {
            image = nil
            failed = false
            guard let path else { return }
            if let url = await store.loadPhoto(path), let loaded = UIImage(contentsOfFile: url.path) {
                image = loaded
            } else {
                failed = true
            }
        }
        .accessibilityLabel(path == nil ? "Fotoğraf yok" : "Öğün fotoğrafı")
    }
}

/// Tam ekran fotoğraf: iki parmakla yakınlaştır, iki kez dokun, sürükleyerek gez. Paylaş ve indir sağ üstte.
struct DietPhotoFullScreen: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let path: String
    let title: String
    @State private var url: URL?
    private let saver = PhotoLibrarySaver()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url {
                ZoomableImage(url: url)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
            VStack {
                HStack(spacing: 10) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                    .accessibilityLabel("Kapat")
                    Spacer()
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    if let url {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up").font(.body.weight(.semibold))
                                .frame(width: 40, height: 40)
                                .background(.white.opacity(0.15), in: Circle())
                        }
                        .accessibilityLabel("Paylaş")
                        Button { save(url) } label: {
                            Image(systemName: "arrow.down.to.line").font(.body.weight(.semibold))
                                .frame(width: 40, height: 40)
                                .background(.white.opacity(0.15), in: Circle())
                        }
                        .accessibilityLabel("Fotoğrafı indir")
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                Spacer()
                Text("İki parmakla yakınlaştır · iki kez dokun")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 12)
            }
            if let toast = store.toast {
                VStack { Spacer(); DietToastView(text: toast).padding(.bottom, 44) }
            }
        }
        .statusBarHidden()
        .task { url = await store.loadPhoto(path) }
    }

    private func save(_ url: URL) {
        Task {
            do {
                try await saver.save(fileURL: url, isVideo: false)
                store.showToast("Fotoğraflar'a kaydedildi")
                Haptics.success()
            } catch {
                store.present(error)
            }
        }
    }
}

struct DietToastView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(Color.white)
            .background(Color.black.opacity(0.75), in: Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Kamera / galeri

/// Tabak fotoğrafı: kamera (yoksa galeri).
struct DietCameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: DietCameraPicker
        init(_ parent: DietCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Yiyecek seçici

struct DietFoodPicker: View {
    @Environment(\.dismiss) private var dismiss
    let foods: [FoodTemplate]
    var title = "Yiyecek seç"
    let onPick: (DietFood) -> Void
    @State private var query = ""

    private var results: [FoodTemplate] { FoodIndex(foods: foods).search(query, limit: 60) }

    var body: some View {
        NavigationStack {
            List(results) { food in
                Button {
                    Haptics.selection()
                    onPick(DietFood(template: food))
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).foregroundStyle(Color.ftText)
                            Text(food.servingLabel).font(.caption).foregroundStyle(Color.ftTextSecondary)
                        }
                        Spacer()
                        Text("\(Int(food.calories.rounded())) kcal").font(.caption.weight(.semibold)).foregroundStyle(Color.ftCalories)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Yiyecek ara")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView("Bulunamadı", systemImage: "magnifyingglass",
                                           description: Text("Beslenme → + ile özel yiyecek ekleyebilirsin."))
                }
            }
        }
    }
}

// MARK: - Porsiyon düzenleyici

/// Yiyecek + miktar + ölçü; "≈ 75 g" ve kalori canlı.
struct DietPortionEditor: View {
    @Binding var portion: DietPortion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(portion.food.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ftText)
                Spacer()
                Text("\(portion.nutrition.kcal) kcal").font(.caption.weight(.semibold)).foregroundStyle(Color.ftCalories)
            }
            HStack(spacing: 10) {
                TextField("Miktar", value: $portion.amount, format: .number.precision(.fractionLength(0...2)).locale(DietFormat.locale))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 84)
                    .accessibilityLabel("Miktar")
                Picker("Ölçü", selection: $portion.unit) {
                    ForEach(unitOptions) { unit in Text(unit.title).tag(unit) }
                }
                .pickerStyle(.menu)
                .tint(Color.ftAccentLight)
                if let hint = portion.gramsHint {
                    Text(hint).font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
                Spacer(minLength: 0)
            }
            Text(portion.nutrition.macroText).font(.caption).foregroundStyle(Color.ftTextSecondary)
        }
    }

    private var unitOptions: [DietUnit] {
        let suggested = portion.food.suggestedUnits
        return suggested + DietUnit.allCases.filter { !suggested.contains($0) }
    }
}

// MARK: - Yorumlar

struct DietCommentList: View {
    @Environment(DietStore.self) private var store
    let programID: String
    let targetID: String
    var canWrite = true
    @State private var draft = ""

    private var comments: [DietComment] { store.comments(programID: programID, targetID: targetID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(comments) { comment in
                HStack(alignment: .top, spacing: 6) {
                    Text(comment.authorID == store.userID ? "Sen:" : "\(comment.authorName):")
                        .font(.caption.weight(.bold)).foregroundStyle(Color.ftAccentLight)
                    Text([comment.reaction, comment.text.isEmpty ? nil : comment.text].compactMap { $0 }.joined(separator: " "))
                        .font(.caption).foregroundStyle(Color.ftText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.ftAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    if comment.authorID == store.userID || store.program(id: programID)?.ownerID == store.userID {
                        Button("Sil", role: .destructive) { Task { await store.deleteComment(comment) } }
                    }
                }
            }
            if canWrite {
                HStack(spacing: 6) {
                    TextField("Yorum yaz…", text: $draft)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit(send)
                    ForEach(DietComment.reactions.prefix(2), id: \.self) { reaction in
                        Button(reaction) {
                            Task { await store.addComment(programID: programID, targetID: targetID, text: "", reaction: reaction) }
                        }
                        .accessibilityLabel("\(reaction) tepkisi bırak")
                    }
                    if !draft.trimmed.isEmpty {
                        Button(action: send) { Image(systemName: "paperplane.fill") }
                            .tint(Color.ftAccentLight)
                            .accessibilityLabel("Yorumu gönder")
                    }
                }
            }
        }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await store.addComment(programID: programID, targetID: targetID, text: text, reaction: nil) }
    }
}

// MARK: - Bölüm başlığı

struct DietSectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased(with: DietFormat.locale))
            .font(.caption.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(Color.ftTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
