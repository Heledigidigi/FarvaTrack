import SwiftUI
import UIKit
import Photos
import AVFoundation

// MARK: - Yazma alanının altındaki paneller

/// Klavyenin yerini alan paneller: sticker ve galeri. Klavye ↔ panel geçişinde yazma alanı yerinden oynamaz.
enum ChatInputPanel: Equatable {
    case none, stickers, gallery
}

/// Panellerin yerleşimi (saf, testli).
///
/// Yazma alanının alt kenarı her zaman `max(klavye, panel)` yüksekliğindedir: klavye inerken altından aynı
/// yükseklikte panel çıkar; klavye çıkarken panelin üstüne gelir. Bu yüzden ne klavye ne panel için
/// ayrı bir "içeri gir" animasyonu gerekir.
enum ChatPanelLayout {
    /// Klavye hiç açılmadıysa tahmin (klasik iPhone klavyesi, öneri çubuğu ve ev çubuğu dahil).
    static let defaultKeyboardHeight: CGFloat = 336
    static let keyboardHeightKey = "chat.keyboardHeight"

    /// Yazma alanının ekranın altından yüksekliği: klavye, panel ve ev çubuğundan hangisi yüksekse.
    /// Klavye inerken panel açıksa değer değişmez (yazma alanı kıpırdamaz); klavye panelin üstüne çıkarken de öyle.
    static func lift(panel: ChatInputPanel, keyboardHeight: CGFloat, keyboardOverlap: CGFloat, homeInset: CGFloat) -> CGFloat {
        max(keyboardOverlap, panel == .none ? 0 : keyboardHeight, homeInset)
    }

    /// Panel yüksekliği: panel açılırken yakalanan klavye yüksekliği, yoksa saklanan klavye yüksekliği.
    static func panelHeight(captured: CGFloat?, stored: CGFloat) -> CGFloat {
        if let captured, captured > 150 { return captured }
        return stored
    }

    /// Panel açılırken klavye tam açıksa yüksekliği yakalanır (inerken/kapalıyken yakalanmaz).
    static func capture(keyboardOverlap: CGFloat) -> CGFloat? {
        keyboardOverlap > 150 ? keyboardOverlap : nil
    }

    /// Görünüm pencerenin altına kadar uzanmıyorsa (ör. gizli sekme çubuğunun payı) ölçüler bu kadar azaltılır.
    static func visibleLift(_ value: CGFloat, bottomGap: CGFloat) -> CGFloat {
        max(0, value - max(0, bottomGap))
    }

    /// Görünümün alt kenarından pencerenin altına kalan pay (yarım noktadan küçükse sıfır).
    static func bottomGap(viewMaxY: CGFloat, windowHeight: CGFloat?) -> CGFloat {
        guard let windowHeight, windowHeight > 0 else { return 0 }
        let gap = windowHeight - viewMaxY
        return gap > 0.5 ? gap : 0
    }

    @MainActor
    static func keyWindowHeight() -> CGFloat? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.bounds.height
    }

    /// Klavyenin kendi hareketine çok yakın yay (UIKit klavye eğrisi).
    static let keyboardAnimation = Animation.interpolatingSpring(mass: 3, stiffness: 1000, damping: 500, initialVelocity: 0)

    /// Galeri büyütülürken panel yüksekliği; parmak bırakılınca nereye oturacağı.
    enum GallerySnap: Equatable { case collapsed, expanded, closed }

    static func gallerySnap(height: CGFloat, predictedHeight: CGFloat, collapsed: CGFloat, expanded: CGFloat) -> GallerySnap {
        let target = predictedHeight
        if target < collapsed * 0.6 { return .closed }
        if target > collapsed + (expanded - collapsed) * 0.4 { return .expanded }
        return .collapsed
    }
}

/// Klavye yüksekliğini öğrenir ve saklar; panel her zaman son görülen klavye yüksekliğinde açılır.
@MainActor @Observable
final class ChatKeyboardObserver {
    private(set) var isVisible = false
    /// Ekranın altından ölçülen klavye yüksekliği (ev çubuğu dahil).
    private(set) var height: CGFloat
    /// Klavye tamamen açıldığında (panel o zaman kaldırılır).
    @ObservationIgnored var onDidShow: (() -> Void)?

    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.double(forKey: ChatPanelLayout.keyboardHeightKey)
        height = saved > 150 ? saved : ChatPanelLayout.defaultKeyboardHeight
    }

    func start() {
        guard tokens.isEmpty else { return }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            MainActor.assumeIsolated { self?.update(endFrame: frame) }
        })
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isVisible = false }
        })
        tokens.append(center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDidShow?() }
        })
    }

    func stop() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens = []
    }

    private func update(endFrame: CGRect?) {
        guard let endFrame else { return }
        let screen = UIScreen.main.bounds.height
        let overlap = max(0, screen - endFrame.minY)
        // Donanım klavyesindeki küçük çubuk ya da kapanış (ekran dışı) yüksekliği saklanmaz.
        if overlap > 150 {
            isVisible = true
            if abs(overlap - height) > 0.5 {
                height = overlap
                defaults.set(Double(overlap), forKey: ChatPanelLayout.keyboardHeightKey)
            }
        } else if overlap < 1 {
            isVisible = false
        }
    }
}

// MARK: - Klavyenin gerçek konumu

/// Klavyenin ekranın altından yüksekliğini bildirir.
/// - Açılma/kapanma: sistemin klavye bildirimlerinden (son konum + animasyonlu olduğu bilgisi).
/// - Parmakla aşağı çekip kapatma: ana görünüm denetleyicisinin `keyboardLayoutGuide`'ına bağlı görünmez bir
///   ölçer her karede bildirir (yalnızca animasyonsuz değişimler alınır; animasyonluları bildirimler verir).
struct ChatKeyboardTracker: UIViewRepresentable {
    /// `overlap`: klavyenin ekranın altından yüksekliği; `animated`: sistem animasyonuyla mı; `homeInset`: ev çubuğu.
    let onChange: (_ overlap: CGFloat, _ animated: Bool, _ homeInset: CGFloat) -> Void

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        uiView.onChange = onChange
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Void) {
        uiView.detach()
    }

    final class AnchorView: UIView {
        var onChange: ((CGFloat, Bool, CGFloat) -> Void)?
        private var probe: ProbeView?
        private var tokens: [NSObjectProtocol] = []
        /// Bildirimlere göre klavye açık mı (ölçer yalnızca açıkken dinlenir).
        private var keyboardShown = false

        private var homeInset: CGFloat { window?.safeAreaInsets.bottom ?? 0 }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else {
                detach()
                return
            }
            if tokens.isEmpty { observeNotifications() }
            attachProbe(in: window)
            let inset = homeInset
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.keyboardShown else { return }
                self.onChange?(0, false, inset)
            }
        }

        private func observeNotifications() {
            let center = NotificationCenter.default
            for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
                tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated { self?.handle(note) }
                })
            }
        }

        private func handle(_ note: Notification) {
            guard let window else { return }
            let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
            var overlap: CGFloat = 0
            if note.name != UIResponder.keyboardWillHideNotification,
               let screenFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
                let frame = window.convert(screenFrame, from: nil)
                overlap = max(0, window.bounds.maxY - frame.minY)
            }
            keyboardShown = overlap > 1
            onChange?(overlap, duration > 0, homeInset)
        }

        private func attachProbe(in window: UIWindow) {
            guard let host = window.rootViewController?.view else { return }
            if probe?.superview === host { return }
            probe?.removeFromSuperview()
            let probe = ProbeView()
            probe.isUserInteractionEnabled = false
            probe.alpha = 0
            probe.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(probe)
            host.keyboardLayoutGuide.usesBottomSafeArea = false
            NSLayoutConstraint.activate([
                probe.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                probe.widthAnchor.constraint(equalToConstant: 1),
                probe.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                probe.topAnchor.constraint(equalTo: host.keyboardLayoutGuide.topAnchor)
            ])
            probe.onLayout = { [weak self] height, animated in
                // Parmakla kapatma: animasyonsuz, kare kare.
                guard let self, self.keyboardShown, !animated else { return }
                self.onChange?(height, false, self.homeInset)
            }
            self.probe = probe
        }

        func detach() {
            probe?.removeFromSuperview()
            probe = nil
            for token in tokens { NotificationCenter.default.removeObserver(token) }
            tokens = []
        }
    }

    final class ProbeView: UIView {
        var onLayout: ((CGFloat, Bool) -> Void)?
        private var lastHeight: CGFloat = -1

        override func layoutSubviews() {
            super.layoutSubviews()
            let height = bounds.height
            guard abs(height - lastHeight) > 0.25 else { return }
            lastHeight = height
            onLayout?(height, UIView.inheritedAnimationDuration > 0)
        }
    }
}

// MARK: - Galeri paneli

/// Klavye yüksekliğinde açılan son fotoğraf/videolar ızgarası (WhatsApp gibi). Üstteki tutamaçtan yukarı
/// çekilince büyür, aşağı çekilince kapanır. Seçilenlerin orijinal dosyası gönderilir.
struct ChatGalleryPanel: View {
    /// Kapalı (klavye) yüksekliği ve tam ekrana yakın yüksekliği.
    let collapsedHeight: CGFloat
    let expandedHeight: CGFloat
    let bottomInset: CGFloat
    @Binding var isExpanded: Bool
    let onSend: ([PickedMedia]) -> Void
    let onCamera: () -> Void
    let onSystemPicker: () -> Void
    let onClose: () -> Void

    @State private var library = ChatGalleryLibrary()
    /// İlk hücredeki canlı kamera önizlemesi (Telegram gibi).
    @State private var cameraPreview = GalleryCameraPreview()
    /// Basılı tutulan öğenin büyük önizlemesi (Instagram gibi).
    @State private var previewItem: GalleryPreviewItem?
    @State private var selection: [String] = []
    @State private var dragHeight: CGFloat?
    @State private var isExporting = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    private var baseHeight: CGFloat { isExpanded ? expandedHeight : collapsedHeight }
    private var height: CGFloat { dragHeight ?? baseHeight }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Color.ftChrome)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: isExpanded || dragHeight != nil ? 16 : 0,
                                          topTrailingRadius: isExpanded || dragHeight != nil ? 16 : 0,
                                          style: .continuous))
        .overlay(alignment: .bottom) {
            if !selection.isEmpty { sendBar }
        }
        .task { await library.load() }
        .task { await cameraPreview.start() }
        .onDisappear {
            library.stopCaching()
            cameraPreview.stop()
        }
        .fullScreenCover(item: $previewItem) { item in
            GalleryAssetPreview(asset: item.asset, library: library) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { previewItem = nil }
            }
            .presentationBackground(.clear)
        }
    }

    // MARK: Tutamaç ve başlık (yukarı çekince büyür)

    private var header: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.ftSubtle(0.35))
                .frame(width: 38, height: 5)
                .padding(.top, 6)
            HStack {
                Button {
                    Haptics.selection()
                    onSystemPicker()
                } label: {
                    Label("Albümler", systemImage: "rectangle.stack")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.ftAccentLight)
                .accessibilityHint("Sistemin fotoğraf seçicisini açar")
                Spacer()
                Text(isExpanded ? "Galeri" : "Son öğeler")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    if isExpanded {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { isExpanded = false }
                    } else {
                        onClose()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(Color.ftCardElevated, in: Circle())
                }
                .foregroundStyle(Color.ftText)
                .accessibilityLabel(isExpanded ? "Galeriyi küçült" : "Galeriyi kapat")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(resizeGesture)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isExpanded ? "Galeriyi küçült" : "Galeriyi büyüt") {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { isExpanded.toggle() }
        }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                let proposed = baseHeight - value.translation.height
                // Sınırların ötesinde direnç.
                if proposed > expandedHeight {
                    dragHeight = expandedHeight + (proposed - expandedHeight) * 0.2
                } else {
                    dragHeight = max(collapsedHeight * 0.35, proposed)
                }
            }
            .onEnded { value in
                let predicted = baseHeight - value.predictedEndTranslation.height
                let snap = ChatPanelLayout.gallerySnap(height: dragHeight ?? baseHeight, predictedHeight: predicted,
                                                       collapsed: collapsedHeight, expanded: expandedHeight)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    dragHeight = nil
                    switch snap {
                    case .expanded: isExpanded = true
                    case .collapsed: isExpanded = false
                    case .closed: isExpanded = false
                    }
                }
                if snap == .closed { onClose() }
                if snap == .expanded { Haptics.selection() }
            }
    }

    // MARK: İçerik

    @ViewBuilder
    private var content: some View {
        switch library.access {
        case .unknown:
            ProgressView().tint(Color.ftAccentLight).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied:
            VStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundStyle(Color.ftTextSecondary)
                    .accessibilityHidden(true)
                Text("Galerini burada göstermek için Fotoğraflar erişimi gerekiyor.")
                    .font(.footnote)
                    .foregroundStyle(Color.ftTextSecondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Ayarları aç") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.bordered)
                    Button("Fotoğraf seç", action: onSystemPicker)
                        .buttonStyle(.borderedProminent)
                }
                .tint(Color.ftAccentLight)
                .font(.footnote.weight(.semibold))
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .authorized, .limited:
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    cameraCell
                    ForEach(library.assets, id: \.localIdentifier) { asset in
                        ChatGalleryCell(
                            asset: asset,
                            library: library,
                            selectionIndex: selection.firstIndex(of: asset.localIdentifier).map { $0 + 1 }
                        )
                        .onTapGesture { toggle(asset) }
                        // Basılı tut: büyük önizleme (bırakınca açık kalır; dışarı dokun ya da kaydır → kapanır).
                        .onLongPressGesture(minimumDuration: 0.3) { openPreview(asset) }
                    }
                }
                .padding(.bottom, selection.isEmpty ? bottomInset : bottomInset + 64)
                if library.access == .limited {
                    Text("Yalnızca izin verdiğin fotoğraflar gösteriliyor. Diğerleri için Albümler'i kullan.")
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(12)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var cameraCell: some View {
        Button {
            Haptics.impact(.light)
            // Kamera ekranı kendi oturumunu açar; önizleme oturumu önce kapatılır.
            cameraPreview.stop()
            onCamera()
        } label: {
            Color.ftCardElevated
                .aspectRatio(1, contentMode: .fill)
                .overlay {
                    if cameraPreview.isRunning {
                        CameraPreviewLayer(session: cameraPreview.session)
                            .allowsHitTesting(false)
                    }
                }
                .clipped()
                .overlay {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundStyle(cameraPreview.isRunning ? Color.white : Color.ftAccentLight)
                        .shadow(color: .black.opacity(cameraPreview.isRunning ? 0.4 : 0), radius: 3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kamera")
        .accessibilityHint("Kamerayı açar")
    }

    private func openPreview(_ asset: PHAsset) {
        Haptics.impact(.medium)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { previewItem = GalleryPreviewItem(asset: asset) }
    }

    private var sendBar: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.selection()
                selection.removeAll()
            } label: {
                Text("Temizle").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.ftTextSecondary)
            Spacer()
            Button {
                send()
            } label: {
                HStack(spacing: 8) {
                    if isExporting {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text("Gönder (\(selection.count))")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.ftAccent, in: Capsule())
            }
            .disabled(isExporting)
            .accessibilityLabel("\(selection.count) öğeyi gönder")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, max(10, bottomInset))
        .background(Color.ftChrome.opacity(0.97))
    }

    private func toggle(_ asset: PHAsset) {
        Haptics.selection()
        if let index = selection.firstIndex(of: asset.localIdentifier) {
            selection.remove(at: index)
        } else if selection.count < 10 {
            selection.append(asset.localIdentifier)
        }
    }

    private func send() {
        let ids = selection
        isExporting = true
        Task {
            let picked = await library.export(ids)
            isExporting = false
            guard !picked.isEmpty else { return }
            selection.removeAll()
            Haptics.impact(.medium)
            onSend(picked)
        }
    }
}

/// Izgaradaki tek öğe: küçük resim, video süresi ve seçim sırası.
private struct ChatGalleryCell: View {
    let asset: PHAsset
    let library: ChatGalleryLibrary
    let selectionIndex: Int?
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Color.ftCardElevated
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 1.5)
                        .background(Circle().fill(selectionIndex == nil ? Color.black.opacity(0.2) : Color.ftAccent))
                    if let selectionIndex {
                        Text("\(selectionIndex)").font(.caption2.bold()).foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(6)
            }
            .overlay {
                if selectionIndex != nil {
                    Rectangle().fill(Color.white.opacity(0.12)).allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onAppear {
                requestID = library.requestThumbnail(for: asset) { image = $0 }
            }
            .onDisappear {
                if let requestID { library.cancel(requestID) }
                requestID = nil
            }
            .accessibilityElement()
            .accessibilityLabel(asset.mediaType == .video ? "Video" : "Fotoğraf")
            .accessibilityValue(selectionIndex.map { "Seçildi, \($0). sırada" } ?? "")
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Fotoğraf arşivi

/// Galeri panelinin veri kaynağı: izin, son öğeler, küçük resimler ve orijinal dosyanın dışa aktarımı.
@MainActor @Observable
final class ChatGalleryLibrary {
    enum Access: Equatable { case unknown, authorized, limited, denied }

    private(set) var access: Access = .unknown
    private(set) var assets: [PHAsset] = []

    private let manager = PHCachingImageManager()
    private let thumbnailSize: CGSize = {
        let side = UIScreen.main.bounds.width / 3 * UIScreen.main.scale
        return CGSize(width: side, height: side)
    }()

    /// Panelde en fazla bu kadar son öğe gösterilir; daha eskileri için sistem seçicisi.
    static let limit = 600

    func load() async {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        switch status {
        case .authorized: access = .authorized
        case .limited: access = .limited
        default:
            access = .denied
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.fetchLimit = Self.limit
        let result = PHAsset.fetchAssets(with: options)
        var items: [PHAsset] = []
        items.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in items.append(asset) }
        assets = items
    }

    func requestThumbnail(for asset: PHAsset, handler: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return manager.requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFill, options: options) { image, _ in
            DispatchQueue.main.async { handler(image) }
        }
    }

    /// Önizleme için büyük görüntü (önce hızlı küçük, sonra yüksek kalite gelir).
    func requestLargeImage(for asset: PHAsset, handler: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let side = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale
        return manager.requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                    contentMode: .aspectFit, options: options) { image, _ in
            DispatchQueue.main.async { handler(image) }
        }
    }

    func cancel(_ id: PHImageRequestID) {
        manager.cancelImageRequest(id)
    }

    func stopCaching() {
        manager.stopCachingImagesForAllAssets()
    }

    /// Seçilenlerin orijinal dosyaları (HEIC/HEVC korunur; düzenlenmiş fotoğrafta düzenlenmiş hali) geçici klasöre.
    func export(_ identifiers: [String]) async -> [PickedMedia] {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        var picked: [PickedMedia] = []
        for id in identifiers {
            guard let asset = byID[id], let media = await Self.exportOriginal(asset) else { continue }
            picked.append(media)
        }
        return picked
    }

    private static func exportOriginal(_ asset: PHAsset) async -> PickedMedia? {
        let kind: ChatMediaKind = asset.mediaType == .video ? .video : .image
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred: [PHAssetResourceType] = kind == .video ? [.fullSizeVideo, .video] : [.fullSizePhoto, .photo]
        guard let resource = preferred.lazy.compactMap({ type in resources.first { $0.type == type } }).first else { return nil }
        var ext = (resource.originalFilename as NSString).pathExtension.lowercased()
        if ext.isEmpty { ext = kind == .video ? "mov" : "jpg" }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChatPicked", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
            return PickedMedia(fileURL: url, kind: kind)
        } catch {
            return nil
        }
    }
}

// MARK: - Galeri: canlı kamera hücresi

/// Galerinin ilk hücresindeki canlı kamera görüntüsü. İzin önceden verilmişse panel açılınca başlar;
/// izin hiç sorulmadıysa sormaz (hücreye dokununca kamera ekranı sorar). Panel kapanınca durur.
@MainActor @Observable
final class GalleryCameraPreview {
    private(set) var isRunning = false
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "farvatrack.chat.gallery.camera")
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var wantsRunning = false

    func start() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        wantsRunning = true
        if !configured {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            // Küçük hücre için düşük çözünürlük yeterli (pil ve ısınma).
            if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            configured = true
        }
        let session = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
        // Bu arada panel kapandıysa hemen durdur.
        if wantsRunning {
            isRunning = true
        } else {
            queue.async { if session.isRunning { session.stopRunning() } }
        }
    }

    func stop() {
        wantsRunning = false
        isRunning = false
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }
}

// MARK: - Galeri: basılı tutunca büyük önizleme

struct GalleryPreviewItem: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

/// Instagram'daki gibi: fotoğraf ekranın ortasında büyür, arka plan bulanıklaşır.
/// Görselin dışına dokunmak ya da herhangi bir yöne kaydırmak kapatır.
struct GalleryAssetPreview: View {
    let asset: PHAsset
    let library: ChatGalleryLibrary
    let onClose: () -> Void

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var appeared = false
    @State private var drag: CGSize = .zero
    @State private var closing = false

    /// Bu kadar kaydırınca kapanır.
    static let dismissDistance: CGFloat = 70

    private var aspect: CGFloat {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 1 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }

    private var dragProgress: CGFloat {
        min(1, hypot(drag.width, drag.height) / 240)
    }

    private var backdropOpacity: Double {
        guard appeared, !closing else { return 0 }
        return 1 - Double(dragProgress) * 0.6
    }

    private var imageScale: CGFloat {
        let base: CGFloat = appeared && !closing ? 1 : 0.82
        return base * (1 - dragProgress * 0.15)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Dışarı dokununca kapanır.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.25))
                    .opacity(backdropOpacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityLabel("Önizlemeyi kapat")
                    .accessibilityAddTraits(.isButton)

                let maxWidth = proxy.size.width * 0.92
                let maxHeight = proxy.size.height * 0.78
                let width = min(maxWidth, maxHeight * aspect)
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Color.ftCardElevated.overlay { ProgressView() }
                    }
                }
                .frame(width: width, height: width / aspect)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if asset.mediaType == .video {
                        Label(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)), systemImage: "video.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(10)
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                .scaleEffect(imageScale)
                .opacity(appeared && !closing ? 1 : 0)
                .offset(drag)
                .accessibilityLabel(asset.mediaType == .video ? "Video önizlemesi" : "Fotoğraf önizlemesi")
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        let predicted = hypot(value.predictedEndTranslation.width, value.predictedEndTranslation.height)
                        if distance > Self.dismissDistance || predicted > Self.dismissDistance * 2.5 {
                            close()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = .zero }
                        }
                    }
            )
        }
        .accessibilityAction(.escape) { close() }
        .onAppear {
            requestID = library.requestLargeImage(for: asset) { image = $0 ?? image }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { appeared = true }
        }
        .onDisappear {
            if let requestID { library.cancel(requestID) }
        }
    }

    private func close() {
        guard !closing else { return }
        Haptics.selection()
        withAnimation(.easeOut(duration: 0.18)) { closing = true }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            onClose()
        }
    }
}
