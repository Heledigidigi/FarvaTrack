import SwiftUI
import PencilKit

// MARK: - Önizleme baloncuğu

/// Editörde ve seçicide: verilen stil ve yazıyla örnek baloncuk.
struct BubblePreview: View {
    let style: BubbleStyle
    let assets: BubbleAssets
    let text: String
    var mirrored = false
    /// Editör: önbelleğe alınmaz (her değişiklikte yeniden çizilir).
    var cacheOwner: String?

    var body: some View {
        let padding = BubbleLayout.contentPadding(for: style, mirrored: mirrored)
        Text(text)
            .font(.body)
            .foregroundStyle(Color(hex: style.textColorHex))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: BubbleLayout.minimumContentSize(for: style)?.width,
                   minHeight: BubbleLayout.minimumContentSize(for: style)?.height)
            .padding(EdgeInsets(top: padding.top, leading: padding.leading, bottom: padding.bottom, trailing: padding.trailing))
            .background { BubbleBackgroundView(style: style, assets: assets, mirrored: mirrored, cacheOwner: cacheOwner) }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Seçici

struct BubblePickerView: View {
    let store: BubbleStyleStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: EditorInput?
    @State private var pendingDelete: BubbleStyle?

    struct EditorInput: Identifiable {
        let id = UUID()
        let style: BubbleStyle
        let isNew: Bool
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Seçtiğin baloncuk gönderdiğin mesajlarda karşı tarafa da aynen görünür.")
                        .font(.footnote)
                        .foregroundStyle(Color.ftTextSecondary)

                    LazyVGrid(columns: columns, spacing: 12) {
                        defaultCell
                        ForEach(store.presets) { style in cell(style) }
                    }

                    HStack {
                        Text("Benim baloncuklarım").font(.headline)
                        Spacer()
                        Button {
                            editing = EditorInput(style: BubblePresets.all[0], isNew: true)
                        } label: {
                            Label("Yeni", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.ftAccentLight)
                    }
                    if store.myStyles.isEmpty {
                        Text("Henüz kendi baloncuğun yok. Hazır bir baloncuğa uzun basıp \"Kopyasını düzenle\" diyebilir ya da sıfırdan tasarlayabilirsin.")
                            .font(.footnote)
                            .foregroundStyle(Color.ftTextSecondary)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.myStyles) { style in cell(style) }
                        }
                    }
                }
                .padding(Constants.Layout.screenPadding)
            }
            .ftScreenBackground()
            .navigationTitle("Baloncuklar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .sheet(item: $editing) { input in
                BubbleEditorView(initial: input.style, isNew: input.isNew, store: store)
            }
            .confirmationDialog("Baloncuk silinsin mi?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { style in
                Button("Sil", role: .destructive) {
                    store.delete(style.id)
                    Haptics.impact(.medium)
                }
                Button("Vazgeç", role: .cancel) {}
            } message: { _ in
                Text("Daha önce bu baloncukla gönderilen mesajlar varsayılan görünüme döner.")
            }
        }
    }

    private var defaultCell: some View {
        let selected = store.selectedID == nil
        return Button {
            store.select(nil)
            Haptics.selection()
        } label: {
            VStack(spacing: 8) {
                Text("Merhaba!")
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.ftAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
                Text("Varsayılan").font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Color.ftAccentLight : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Varsayılan baloncuk")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func cell(_ style: BubbleStyle) -> some View {
        let selected = store.selectedID == style.id
        let owner = style.isPreset ? "preset" : (store.userID ?? "")
        return Button {
            store.select(style.id)
            Haptics.selection()
        } label: {
            VStack(spacing: 8) {
                if style.art != nil {
                    // Çizimli baloncuk hücreye sığsın diye küçültülür.
                    BubblePreview(style: style, assets: store.assets(for: style, ownerID: owner), text: "Merhaba!", cacheOwner: owner)
                        .fixedSize()
                        .scaleEffect(0.68)
                        .frame(width: 150, height: 48)
                } else {
                    BubblePreview(style: style, assets: store.assets(for: style, ownerID: owner), text: "Merhaba!", cacheOwner: owner)
                }
                Text(style.name).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Color.ftAccentLight : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if style.art != nil {
                EmptyView()
            } else if style.isPreset {
                Button { editing = EditorInput(style: style, isNew: true) } label: { Label("Kopyasını düzenle", systemImage: "square.on.square") }
            } else {
                Button { editing = EditorInput(style: style, isNew: false) } label: { Label("Düzenle", systemImage: "pencil") }
                Button(role: .destructive) { pendingDelete = style } label: { Label("Sil", systemImage: "trash") }
            }
        }
        .accessibilityLabel("\(style.name) baloncuğu")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: style.isPreset ? "Kopyasını düzenle" : "Düzenle") {
            // Çizimli baloncuklar düzenleyicide değiştirilemez.
            guard style.art == nil else { return }
            editing = EditorInput(style: style, isNew: style.isPreset)
        }
    }
}

// MARK: - Editör

struct BubbleEditorView: View {
    let store: BubbleStyleStore
    let isNew: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: BubbleStyle
    @State private var drawing = PKDrawing()
    @State private var drawingImage: CGImage?
    @State private var stickerFiles: [String: URL] = [:]
    @State private var selectedDecorationID: String?
    @State private var showDrawing = false
    @State private var showEmoji = false
    @State private var showStickers = false
    @State private var showTextPrompt = false
    @State private var newText = ""
    @State private var stickerLibrary = StickerLibraryViewModel()

    private static let shortSample = "Selam! 👋"
    private static let longSample = "Bugünkü antrenman harikaydı, akşam yürüyüşe çıkalım mı? Hava da çok güzel görünüyor."

    @MainActor
    init(initial: BubbleStyle, isNew: Bool, store: BubbleStyleStore) {
        self.store = store
        self.isNew = isNew
        var start = initial
        if isNew {
            // Hazırdan başlayınca kopyası düzenlenir.
            start.id = ""
            start.version = 0
            start.name = initial.isPreset ? "\(initial.name) (kopya)" : initial.name
        }
        _draft = State(initialValue: start)
    }

    private var assets: BubbleAssets {
        BubbleAssets(drawing: drawingImage, stickerURLs: stickerFiles, drawingToken: "\(drawing.strokes.count)")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.ftBackground)
                Divider()
                Form {
                    nameSection
                    shapeSection
                    fillSection
                    borderSection
                    decorationSection
                    drawingSection
                    effectSection
                    sliceSection
                }
                .scrollContentBackground(.hidden)
                .background(Color.ftCard)
            }
            .navigationTitle(isNew ? "Yeni baloncuk" : "Baloncuğu düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet", action: save).fontWeight(.semibold) }
            }
            .sheet(isPresented: $showDrawing) {
                BubbleDrawingSheet(style: draft, drawing: $drawing)
            }
            .sheet(isPresented: $showEmoji) { emojiPicker }
            .sheet(isPresented: $showStickers) { stickerPicker }
            .alert("Yazı ekle", isPresented: $showTextPrompt) {
                TextField("Yazı", text: $newText)
                Button("Ekle") {
                    addDecoration(BubbleDecoration(id: BubbleAssetID.make(), kind: .text, text: String(newText.prefix(BubbleStyle.maxTextLength)),
                                                   assetID: nil, colorHex: "#FFFFFF", anchor: .topTrailing,
                                                   offset: CGSize(width: -6, height: -4), size: 22, rotation: 0))
                    newText = ""
                }
                Button("Vazgeç", role: .cancel) { newText = "" }
            }
            .alert("Bir sorun oluştu", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: { Text(store.errorMessage ?? "") }
        }
        .task {
            if !isNew {
                if let data = store.drawingData(for: draft.id), let saved = try? PKDrawing(data: data) { drawing = saved }
                stickerFiles = store.stickerFiles(for: draft)
            }
            renderDrawing()
            if let userID = store.userID { stickerLibrary.configure(context: modelContext, userID: userID) }
        }
        .onChange(of: drawing) { _, _ in renderDrawing() }
    }

    private func renderDrawing() {
        guard !drawing.strokes.isEmpty else {
            drawingImage = nil
            return
        }
        drawingImage = drawing.image(from: CGRect(origin: .zero, size: BubbleLayout.referenceSize), scale: BubbleArtRenderer.scale).cgImage
    }

    // MARK: Önizleme

    private var preview: some View {
        VStack(alignment: .trailing, spacing: 10) {
            BubblePreview(style: draft, assets: assets, text: Self.shortSample)
            BubblePreview(style: draft, assets: assets, text: Self.longSample)
                .frame(maxWidth: 280, alignment: .trailing)
            HStack {
                BubblePreview(style: draft, assets: assets, text: "Karşı tarafta böyle görünür", mirrored: true)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Canlı önizleme: kısa ve uzun mesaj")
    }

    // MARK: Bölümler

    private var nameSection: some View {
        Section("Ad") {
            TextField("Baloncuk adı", text: $draft.name)
        }
    }

    private var shapeSection: some View {
        Section("Şekil") {
            sliderRow("Köşe yarıçapı", value: $draft.shape.cornerRadius, range: BubbleShapeStyle.radiusRange, suffix: "pt")
            Picker("Kuyruk", selection: $draft.shape.tail) {
                ForEach(BubbleTail.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var fillSection: some View {
        Section("Dolgu") {
            Picker("Dolgu", selection: $draft.fill.kind) {
                ForEach(BubbleFill.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.fill.kind) { _, kind in
                if kind != .solid, draft.fill.colors.count < 2 { draft.fill.colors.append(BubblePalette.bordoLight) }
            }
            swatchRow("Renk 1", selection: colorBinding(0))
            if draft.fill.kind != .solid {
                swatchRow("Renk 2", selection: colorBinding(1))
            }
            if draft.fill.kind == .linear {
                sliderRow("Açı", value: $draft.fill.angle, range: 0...360, suffix: "°")
            }
            swatchRow("Yazı rengi", selection: $draft.textColorHex)
        }
    }

    private func colorBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { draft.fill.colors.indices.contains(index) ? draft.fill.colors[index] : BubblePalette.bordo },
            set: { value in
                while draft.fill.colors.count <= index { draft.fill.colors.append(value) }
                draft.fill.colors[index] = value
            }
        )
    }

    private var borderSection: some View {
        Section("Kenarlık") {
            Toggle("Kenarlık", isOn: Binding(
                get: { draft.border != nil },
                set: { draft.border = $0 ? BubbleBorder(colorHex: BubblePalette.gold, width: 1.5) : nil }
            ))
            .tint(Color.ftAccent)
            if draft.border != nil {
                swatchRow("Renk", selection: Binding(get: { draft.border?.colorHex ?? "#FFFFFF" }, set: { draft.border?.colorHex = $0 }))
                sliderRow("Kalınlık", value: Binding(get: { draft.border?.width ?? 1 }, set: { draft.border?.width = $0 }),
                          range: BubbleBorder.widthRange, suffix: "pt", step: 0.5)
            }
        }
    }

    private var decorationSection: some View {
        Section {
            HStack {
                Button { showEmoji = true } label: { Label("Emoji", systemImage: "face.smiling") }
                Spacer()
                Button { showTextPrompt = true } label: { Label("Yazı", systemImage: "textformat") }
                Spacer()
                Button { showStickers = true } label: { Label("Sticker", systemImage: "seal") }
            }
            .buttonStyle(.borderless)
            .disabled(draft.decorations.count >= BubbleStyle.maxDecorations)

            ForEach(draft.decorations) { decoration in
                decorationRow(decoration)
            }
        } header: {
            Text("Süslemeler")
        } footer: {
            Text("Süslemeler seçtiğin köşeye ya da kenara sabitlenir; mesaj uzayıp kısalsa da yerinde kalır, esnemez.")
        }
    }

    @ViewBuilder
    private func decorationRow(_ decoration: BubbleDecoration) -> some View {
        let expanded = selectedDecorationID == decoration.id
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { selectedDecorationID = expanded ? nil : decoration.id }
            } label: {
                HStack {
                    switch decoration.kind {
                    case .emoji: Text(decoration.text ?? "")
                    case .text: Text("\"\(decoration.text ?? "")\"").lineLimit(1)
                    case .sticker: StickerImage(url: decoration.assetID.flatMap { stickerFiles[$0] }).frame(width: 24, height: 24)
                    }
                    Text(decoration.anchor.title).foregroundStyle(Color.ftTextSecondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(Color.ftTextSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ayarları göstermek için dokun")

            if expanded, let index = draft.decorations.firstIndex(where: { $0.id == decoration.id }) {
                Picker("Sabitlendiği yer", selection: $draft.decorations[index].anchor) {
                    ForEach(BubbleAnchor.allCases) { Text($0.title).tag($0) }
                }
                sliderRow("Boyut", value: $draft.decorations[index].size, range: BubbleDecoration.sizeRange, suffix: "pt")
                sliderRow("Yatay kaydır", value: double($draft.decorations[index].offset.width),
                          range: -BubbleDecoration.offsetLimit...BubbleDecoration.offsetLimit, suffix: "pt")
                sliderRow("Dikey kaydır", value: double($draft.decorations[index].offset.height),
                          range: -BubbleDecoration.offsetLimit...BubbleDecoration.offsetLimit, suffix: "pt")
                sliderRow("Döndür", value: $draft.decorations[index].rotation, range: -180...180, suffix: "°")
                if decoration.kind == .text {
                    swatchRow("Renk", selection: Binding(get: { draft.decorations[index].colorHex ?? "#FFFFFF" },
                                                         set: { draft.decorations[index].colorHex = $0 }))
                }
                Button(role: .destructive) {
                    draft.decorations.removeAll { $0.id == decoration.id }
                    if let asset = decoration.assetID { stickerFiles.removeValue(forKey: asset) }
                    selectedDecorationID = nil
                } label: {
                    Label("Süslemeyi kaldır", systemImage: "trash")
                }
            }
        }
    }

    private var drawingSection: some View {
        Section {
            Button {
                showDrawing = true
            } label: {
                Label(drawing.strokes.isEmpty ? "Baloncuğa çiz" : "Çizimi düzenle", systemImage: "pencil.tip.crop.circle")
            }
            if !drawing.strokes.isEmpty {
                Button(role: .destructive) { drawing = PKDrawing() } label: { Label("Çizimi sil", systemImage: "trash") }
            }
        } header: {
            Text("El çizimi")
        } footer: {
            Text("Çizim baloncuğun parçasıdır: köşelerdeki çizgiler sabit kalır, kenarlardakiler mesajla birlikte esner.")
        }
    }

    private var effectSection: some View {
        Section {
            Picker("Efekt", selection: $draft.effect.kind) {
                ForEach(BubbleEffect.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if draft.effect.kind != .none {
                swatchRow("Renk", selection: $draft.effect.colorHex)
                sliderRow("Yoğunluk", value: $draft.effect.intensity, range: 0.1...1, suffix: "", step: 0.05, percent: true)
            }
        } header: {
            Text("Efekt")
        } footer: {
            if reduceMotion, draft.effect.kind != .none {
                Text("\"Hareketi azalt\" açık olduğu için efektler bu cihazda gösterilmez.")
            }
        }
    }

    private var sliceSection: some View {
        Section {
            BubbleSliceGuide(style: draft, assets: assets)
                .frame(height: BubbleLayout.referenceSize.height * 1.2)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.ftBackground)
            Toggle("Dilimleri elle ayarla", isOn: Binding(
                get: { draft.manualInsets != nil },
                set: { draft.manualInsets = $0 ? BubbleLayout.automaticInsets(for: draft) : nil }
            ))
            .tint(Color.ftAccent)
            if draft.manualInsets != nil {
                sliderRow("Üst", value: insetBinding(\.top), range: 0...50, suffix: "pt")
                sliderRow("Sol", value: insetBinding(\.leading), range: 0...80, suffix: "pt")
                sliderRow("Alt", value: insetBinding(\.bottom), range: 0...50, suffix: "pt")
                sliderRow("Sağ", value: insetBinding(\.trailing), range: 0...80, suffix: "pt")
            }
        } header: {
            Text("9-dilim")
        } footer: {
            Text("Kesikli çizgilerin dışındaki köşeler hiç esnemez; kenarlar tek yönde, orta iki yönde esner. Otomatik değerler köşe yarıçapı, kenarlık ve kuyruktan hesaplanır.")
        }
    }

    private func insetBinding(_ keyPath: WritableKeyPath<BubbleInsets, Double>) -> Binding<Double> {
        Binding(
            get: { draft.manualInsets?[keyPath: keyPath] ?? 0 },
            set: { value in
                var insets = draft.manualInsets ?? BubbleLayout.automaticInsets(for: draft)
                insets[keyPath: keyPath] = value
                draft.manualInsets = insets
            }
        )
    }

    // MARK: Ortak satırlar

    private func double(_ binding: Binding<CGFloat>) -> Binding<Double> {
        Binding(get: { Double(binding.wrappedValue) }, set: { binding.wrappedValue = CGFloat($0) })
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String,
                           step: Double = 1, percent: Bool = false) -> some View {
        let text = percent ? "%\(Int(value.wrappedValue * 100))" : "\(Int(value.wrappedValue.rounded()))\(suffix)"
        return HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .tint(Color.ftAccentLight)
                .accessibilityLabel(title)
                .accessibilityValue(text)
            Text(text).font(.caption.monospacedDigit()).foregroundStyle(Color.ftTextSecondary).frame(width: 46, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private func swatchRow(_ title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BubblePalette.swatches, id: \.self) { hex in
                        Button {
                            selection.wrappedValue = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(.white, lineWidth: selection.wrappedValue.caseInsensitiveCompare(hex) == .orderedSame ? 3 : 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title): \(hex)")
                        .accessibilityAddTraits(selection.wrappedValue.caseInsensitiveCompare(hex) == .orderedSame ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Süsleme ekleme

    private func addDecoration(_ decoration: BubbleDecoration) {
        guard draft.decorations.count < BubbleStyle.maxDecorations else { return }
        if decoration.kind != .sticker, (decoration.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty { return }
        draft.decorations.append(decoration)
        selectedDecorationID = decoration.id
        Haptics.impact(.light)
    }

    private var emojiPicker: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(StickerOverlay.emojis, id: \.self) { emoji in
                        Button {
                            addDecoration(BubbleDecoration(id: BubbleAssetID.make(), kind: .emoji, text: emoji, assetID: nil, colorHex: nil,
                                                           anchor: .topTrailing, offset: CGSize(width: -4, height: -2), size: 20, rotation: 0))
                            showEmoji = false
                        } label: { Text(emoji).font(.system(size: 34)) }
                        .accessibilityLabel("\(emoji) ekle")
                    }
                }
                .padding()
            }
            .navigationTitle("Emoji").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { showEmoji = false } } }
        }
        .presentationDetents([.medium])
    }

    private var stickerPicker: some View {
        NavigationStack {
            Group {
                if stickerLibrary.stickers.isEmpty {
                    Text("Sticker kütüphanen boş. Sohbetteki sticker panelinden fotoğraftan sticker oluşturabilirsin.")
                        .font(.footnote).foregroundStyle(Color.ftTextSecondary).padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 12) {
                            ForEach(stickerLibrary.stickers) { sticker in
                                Button {
                                    let asset = BubbleAssetID.make()
                                    stickerFiles[asset] = sticker.fileURL
                                    addDecoration(BubbleDecoration(id: BubbleAssetID.make(), kind: .sticker, text: nil, assetID: asset, colorHex: nil,
                                                                   anchor: .topLeading, offset: CGSize(width: 2, height: -4), size: 28, rotation: -10))
                                    showStickers = false
                                } label: {
                                    StickerImage(url: sticker.fileURL).frame(width: 64, height: 64)
                                }
                                .accessibilityLabel("Sticker ekle")
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Sticker").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { showStickers = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Kaydet

    private func save() {
        let png: Data? = drawing.strokes.isEmpty ? nil : drawingImage.flatMap { UIImage(cgImage: $0).pngData() }
        let used = Set(draft.decorations.compactMap(\.assetID))
        do {
            try store.save(draft, drawingPNG: png, drawingData: drawing.strokes.isEmpty ? nil : drawing.dataRepresentation(),
                           stickerFiles: stickerFiles.filter { used.contains($0.key) })
            Haptics.success()
            dismiss()
        } catch {
            store.errorMessage = AppError.map(error).errorDescription
            Haptics.error()
        }
    }
}

// MARK: - Dilim kılavuzu

/// Referans boyuttaki sanat ve üstünde kesikli dilim çizgileri.
struct BubbleSliceGuide: View {
    let style: BubbleStyle
    let assets: BubbleAssets

    var body: some View {
        let size = BubbleLayout.referenceSize
        let insets = BubbleLayout.insets(for: style)
        ZStack(alignment: .topLeading) {
            if let art = BubbleArtCache.uncachedArt(for: style, assets: assets, mirrored: false) {
                Image(decorative: art.image, scale: BubbleArtRenderer.scale)
            }
            Path { path in
                for x in [insets.leading, Double(size.width) - insets.trailing] {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in [insets.top, Double(size.height) - insets.bottom] {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement()
        .accessibilityLabel("Dilim çizgileri: üst \(Int(insets.top)), sol \(Int(insets.leading)), alt \(Int(insets.bottom)), sağ \(Int(insets.trailing)) nokta")
    }
}

// MARK: - Çizim (PencilKit)

struct BubbleDrawingSheet: View {
    let style: BubbleStyle
    @Binding var drawing: PKDrawing
    @Environment(\.dismiss) private var dismiss
    @State private var colorHex = "#FFFFFF"
    @State private var width: Double = 3
    @State private var erasing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                GeometryReader { proxy in
                    let size = BubbleLayout.referenceSize
                    let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
                    ZStack {
                        if let art = BubbleArtCache.uncachedArt(for: style, assets: .empty, mirrored: false) {
                            Image(decorative: art.image, scale: BubbleArtRenderer.scale)
                        }
                        // Tuval referans boyutta; büyütülerek gösterilir → çizim doğrudan sanat koordinatında.
                        BubbleCanvas(drawing: $drawing, tool: tool)
                    }
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(height: 260)
                .background(CheckerboardBackground(square: 10))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("Çizim tuvali")
                .accessibilityHint("Parmağınla baloncuğun üstüne çiz")

                HStack(spacing: 10) {
                    ForEach(["#FFFFFF", BubblePalette.gold, BubblePalette.rose, BubblePalette.bordoLight, "#111111"], id: \.self) { hex in
                        Button {
                            colorHex = hex
                            erasing = false
                        } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.white, lineWidth: !erasing && colorHex == hex ? 3 : 0.5))
                        }
                        .accessibilityLabel("Kalem rengi \(hex)")
                    }
                    Button { erasing.toggle() } label: {
                        Image(systemName: "eraser.fill").font(.title3)
                            .padding(6)
                            .background(erasing ? Color.ftAccent : Color.ftCardElevated, in: Circle())
                    }
                    .accessibilityLabel("Silgi")
                    .accessibilityAddTraits(erasing ? .isSelected : [])
                }
                HStack {
                    Text("Kalınlık")
                    Slider(value: $width, in: 1...10).tint(Color.ftAccentLight).accessibilityLabel("Kalem kalınlığı")
                }
                Button(role: .destructive) { drawing = PKDrawing() } label: { Label("Tümünü temizle", systemImage: "trash") }
                Spacer()
            }
            .padding()
            .ftScreenBackground()
            .navigationTitle("Baloncuğa çiz").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }

    private var tool: PKTool {
        erasing ? PKEraserTool(.vector) : PKInkingTool(.pen, color: UIColor(Color(hex: colorHex)), width: width)
    }
}

struct BubbleCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let tool: PKTool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawing = drawing
        canvas.tool = tool
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.tool = tool
        if canvas.drawing != drawing { canvas.drawing = drawing }
    }

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}
