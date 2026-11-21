import SwiftUI

/// Fotoğraftan sticker: otomatik arka plan kaldırma, silgi/onar fırçası, kontur, yazı ve emoji.
struct StickerEditorView: View {
    let imageData: Data
    let onSave: (StickerRenderResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = StickerEditorViewModel()
    @State private var imageFrame: CGRect = .zero
    @State private var touchPoint: CGPoint?
    @State private var showTextPrompt = false
    @State private var newText = ""
    @State private var showEmojiPicker = false
    @State private var draggingOverlay: UUID?
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let notice = viewModel.notice {
                    Label(notice, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.ftTextSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.ftCard)
                }
                canvasArea
                controls
            }
            .background(Color.ftBackground.ignoresSafeArea())
            .navigationTitle("Sticker oluştur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        if viewModel.canUndo { confirmDiscard = true } else { close() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .fontWeight(.semibold)
                        .disabled(viewModel.phase != .editing)
                }
            }
            .confirmationDialog("Değişiklikler kaybolacak", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Sticker'ı at", role: .destructive, action: close)
                Button("Düzenlemeye devam et", role: .cancel) {}
            }
            .alert("Yazı ekle", isPresented: $showTextPrompt) {
                TextField("Yazı", text: $newText)
                Button("Ekle") {
                    viewModel.addOverlay(.text(String(newText.prefix(40))))
                    newText = ""
                    Haptics.impact(.light)
                }
                Button("Vazgeç", role: .cancel) { newText = "" }
            }
            .alert("Bir sorun oluştu", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(isPresented: $showEmojiPicker) {
                emojiPicker
            }
        }
        .task { await viewModel.load(imageData: imageData) }
        .onDisappear { viewModel.cancelBackgroundWork() }
    }

    // MARK: Tuval

    private var canvasArea: some View {
        ZStack {
            CheckerboardBackground()

            switch viewModel.phase {
            case .idle, .processing:
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Arka plan cihazında kaldırılıyor…")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .padding(20)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
            case .editing, .saving:
                StickerCanvas(
                    image: viewModel.preview,
                    pixelSize: viewModel.pixelSize,
                    brushEnabled: viewModel.tool.brushMode != nil,
                    onBrushBegan: brushBegan,
                    onBrushMoved: brushMoved,
                    onBrushEnded: {
                        touchPoint = nil
                        viewModel.endStroke()
                    },
                    onBrushCancelled: {
                        touchPoint = nil
                        viewModel.cancelStroke()
                    },
                    onImageFrameChanged: { imageFrame = $0 }
                )
                .accessibilityLabel("Sticker tuvali")
                .accessibilityHint("Silmek ya da onarmak için tek parmakla çiz. Yakınlaştırmak için iki parmağını kullan.")

                overlayLayer
                brushCursor
                magnifier
                finalPreviewCard

                if viewModel.phase == .saving {
                    Color.black.opacity(0.35)
                    ProgressView("Kaydediliyor…").tint(.white).foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var brushRadiusPixels: Double {
        StickerGeometry.pixelRadius(forDiameter: viewModel.brushDiameter, imageFrame: imageFrame, pixelSize: viewModel.pixelSize)
    }

    private func imagePoint(for touch: CGPoint) -> CGPoint {
        StickerGeometry.imagePoint(fromView: StickerGeometry.brushPoint(forTouch: touch), imageFrame: imageFrame, pixelSize: viewModel.pixelSize)
    }

    private func brushBegan(_ touch: CGPoint) {
        touchPoint = touch
        viewModel.selectedOverlayID = nil
        viewModel.beginStroke(at: imagePoint(for: touch), radius: brushRadiusPixels)
        Haptics.selection()
    }

    private func brushMoved(_ touch: CGPoint) {
        touchPoint = touch
        viewModel.continueStroke(to: imagePoint(for: touch), radius: brushRadiusPixels)
    }

    /// Fırça dairesi parmağın biraz üstünde; parmakla arasında ince bir çizgi.
    @ViewBuilder
    private var brushCursor: some View {
        if let touchPoint {
            let brush = StickerGeometry.brushPoint(forTouch: touchPoint)
            ZStack {
                Path { path in
                    path.move(to: touchPoint)
                    path.addLine(to: CGPoint(x: brush.x, y: brush.y + viewModel.brushDiameter / 2))
                }
                .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Circle()
                    .strokeBorder(viewModel.tool == .erase ? Color.ftDanger : Color.ftSuccess, lineWidth: 2)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .frame(width: viewModel.brushDiameter, height: viewModel.brushDiameter)
                    .position(brush)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var magnifier: some View {
        if let touchPoint, let preview = viewModel.preview {
            let brush = StickerGeometry.brushPoint(forTouch: touchPoint)
            // Fırça sol üstteyse büyüteç sağ üste geçer.
            let leading = !(brush.x < StickerMagnifier.side + 40 && brush.y < StickerMagnifier.side + 40)
            VStack {
                HStack {
                    if !leading { Spacer() }
                    StickerMagnifier(image: preview, center: imagePoint(for: touchPoint), radius: brushRadiusPixels)
                    if leading { Spacer() }
                }
                Spacer()
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var finalPreviewCard: some View {
        if let final = viewModel.finalPreview, touchPoint == nil {
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        CheckerboardBackground(square: 6)
                        Image(decorative: final, scale: 1).resizable().scaledToFit().padding(4)
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    .accessibilityElement()
                    .accessibilityLabel("Son hal önizlemesi")
                }
                Spacer()
            }
            .padding(12)
            .allowsHitTesting(false)
        }
    }

    /// Yazı ve emojiler: tuvalin yakınlaştırmasıyla birlikte hareket eder; sürüklenerek taşınır.
    private var overlayLayer: some View {
        ForEach(viewModel.overlays) { overlay in
            let selected = viewModel.selectedOverlayID == overlay.id
            Text(overlay.text)
                .font(.system(size: max(8, overlay.fontSize(forImageWidth: imageFrame.width)), weight: .heavy, design: .rounded))
                .foregroundStyle(overlay.kind == .text ? Color(hex: overlay.colorHex) : .white)
                .shadow(color: overlay.kind == .text ? .black.opacity(0.45) : .clear, radius: 2)
                .fixedSize()
                .padding(4)
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .position(
                    x: imageFrame.minX + overlay.center.x * imageFrame.width,
                    y: imageFrame.minY + overlay.center.y * imageFrame.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if draggingOverlay != overlay.id {
                                draggingOverlay = overlay.id
                                viewModel.selectedOverlayID = overlay.id
                                viewModel.beginOverlayChange()
                            }
                            guard imageFrame.width > 0 else { return }
                            viewModel.updateOverlay(overlay.id, center: CGPoint(
                                x: (value.location.x - imageFrame.minX) / imageFrame.width,
                                y: (value.location.y - imageFrame.minY) / imageFrame.height
                            ))
                        }
                        .onEnded { _ in
                            draggingOverlay = nil
                            viewModel.endOverlayChange()
                        }
                )
                .onTapGesture {
                    viewModel.selectedOverlayID = selected ? nil : overlay.id
                    Haptics.selection()
                }
                .accessibilityLabel(overlay.kind == .text ? "Yazı: \(overlay.text)" : "Emoji \(overlay.text)")
                .accessibilityHint("Seçmek için dokun, taşımak için sürükle")
                .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    // MARK: Denetimler

    private var controls: some View {
        VStack(spacing: 12) {
            if let overlay = viewModel.selectedOverlay {
                overlayControls(overlay)
            } else {
                brushControls
            }

            HStack(spacing: 14) {
                Button { viewModel.undo(); Haptics.selection() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!viewModel.canUndo)
                    .accessibilityLabel("Geri al")
                Button { viewModel.redo(); Haptics.selection() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!viewModel.canRedo)
                    .accessibilityLabel("İleri al")

                Menu {
                    if viewModel.hasAutomaticMask {
                        Button { viewModel.resetMask(toAutomatic: true) } label: { Label("Otomatik kesime dön", systemImage: "wand.and.stars") }
                    }
                    Button { viewModel.resetMask(toAutomatic: false) } label: { Label("Fotoğrafın tamamı", systemImage: "photo") }
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .accessibilityLabel("Kesimi sıfırla")

                Spacer()

                Button { showTextPrompt = true } label: { Label("Yazı", systemImage: "textformat") }
                    .accessibilityLabel("Yazı ekle")
                Button { showEmojiPicker = true } label: { Label("Emoji", systemImage: "face.smiling") }
                    .accessibilityLabel("Emoji ekle")
            }
            .font(.body.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .tint(Color.ftAccentLight)

            HStack(spacing: 10) {
                Toggle(isOn: $viewModel.options.outlineEnabled) {
                    Label("Beyaz kontur", systemImage: "circle.dashed")
                        .font(.subheadline.weight(.semibold))
                }
                .toggleStyle(.switch)
                .tint(Color.ftAccent)
                .fixedSize()

                if viewModel.options.outlineEnabled {
                    Slider(value: $viewModel.options.outlineWidth, in: StickerRenderOptions.outlineRange, step: 1)
                        .tint(Color.ftAccentLight)
                        .accessibilityLabel("Kontur kalınlığı")
                        .accessibilityValue("\(Int(viewModel.options.outlineWidth)) piksel")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.ftCard.ignoresSafeArea(edges: .bottom))
        .disabled(viewModel.phase != .editing)
    }

    private var brushControls: some View {
        VStack(spacing: 8) {
            Picker("Araç", selection: $viewModel.tool) {
                ForEach(StickerTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.systemImage).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Araç")

            if viewModel.tool.brushMode != nil {
                labeledSlider("Boyut", systemImage: "circle.circle", value: $viewModel.brushDiameter,
                              range: StickerEditorViewModel.brushDiameterRange, valueText: "\(Int(viewModel.brushDiameter)) pt")
                labeledSlider("Yumuşaklık", systemImage: "circle.lefthalf.filled", value: $viewModel.softness,
                              range: 0...1, valueText: "%\(Int(viewModel.softness * 100))")
            } else {
                Text("Tek parmakla kaydır, iki parmakla yakınlaştır. İki parmakla iki kez dokun: sığdır.")
                    .font(.footnote)
                    .foregroundStyle(Color.ftTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func overlayControls(_ overlay: StickerOverlay) -> some View {
        VStack(spacing: 8) {
            labeledSlider("Boyut", systemImage: "textformat.size",
                          value: Binding(get: { overlay.relativeSize }, set: { viewModel.updateOverlay(overlay.id, relativeSize: $0) }),
                          range: 0.03...0.45, valueText: "%\(Int(overlay.relativeSize * 100))",
                          onEditingChanged: { editing in editing ? viewModel.beginOverlayChange() : viewModel.endOverlayChange() })
            HStack(spacing: 10) {
                if overlay.kind == .text {
                    ForEach(StickerOverlay.colors, id: \.self) { hex in
                        Button {
                            viewModel.beginOverlayChange()
                            viewModel.updateOverlay(overlay.id, colorHex: hex)
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.white, lineWidth: overlay.colorHex == hex ? 3 : 1))
                        }
                        .accessibilityLabel("Renk \(hex)")
                        .accessibilityAddTraits(overlay.colorHex == hex ? .isSelected : [])
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    viewModel.removeOverlay(overlay.id)
                    Haptics.impact(.medium)
                } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Katmanı sil")
                Button("Bitti") { viewModel.selectedOverlayID = nil }
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .tint(Color.ftAccentLight)
        }
    }

    private func labeledSlider(_ title: String, systemImage: String, value: Binding<Double>, range: ClosedRange<Double>,
                               valueText: String, onEditingChanged: @escaping (Bool) -> Void = { _ in }) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(Color.ftTextSecondary)
                .accessibilityHidden(true)
            Slider(value: value, in: range, onEditingChanged: onEditingChanged)
                .tint(Color.ftAccentLight)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.ftTextSecondary)
                .frame(width: 46, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var emojiPicker: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(StickerOverlay.emojis, id: \.self) { emoji in
                        Button {
                            viewModel.addOverlay(.emoji(emoji))
                            showEmojiPicker = false
                            Haptics.impact(.light)
                        } label: {
                            Text(emoji).font(.system(size: 36))
                        }
                        .accessibilityLabel("\(emoji) ekle")
                    }
                }
                .padding()
            }
            .navigationTitle("Emoji ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { showEmojiPicker = false } }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Kaydet

    private func save() {
        Task {
            do {
                let result = try await viewModel.render()
                Haptics.success()
                onSave(result)
                close()
            } catch {
                Haptics.error()
                viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Sticker kaydedilemedi."
            }
        }
    }

    private func close() {
        viewModel.cancelBackgroundWork()
        dismiss()
    }
}
