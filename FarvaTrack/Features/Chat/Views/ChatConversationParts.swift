import SwiftUI
import UIKit

// MARK: - Sola kaydırınca saatler (Instagram gibi)

/// Sola kaydırma miktarı → baloncukların kayması (saf, testli). Belli bir yerden sonra direnç gösterir.
enum ChatTimeReveal {
    /// Saatlerin göründüğü genişlik.
    static let width: CGFloat = 64

    static func offset(forTranslation translation: CGFloat) -> CGFloat {
        guard translation < 0 else { return 0 }
        if translation >= -width { return translation }
        return -width + (translation + width) * 0.2
    }

    /// 0 (gizli) … 1 (tamamen görünür).
    static func progress(_ offset: CGFloat) -> Double {
        Double(min(max(-offset / width, 0), 1))
    }
}

/// Kaydırarak yanıtlama (saf, testli): kendi mesajını sola, karşı tarafınkini sağa çek.
enum ChatSwipeReply {
    /// Bu kadar çekilince bırakıldığında yanıtlanır.
    static let threshold: CGFloat = 56
    static let maximum: CGFloat = 84

    /// Parmağın yatay hareketi → baloncuğun kayması (yanlış yöne gitmez, sınırdan sonra direnç gösterir).
    static func offset(forTranslation translation: CGFloat, isMine: Bool) -> CGFloat {
        let raw = isMine ? min(0, translation) : max(0, translation)
        let magnitude = abs(raw)
        let resisted = magnitude <= threshold ? magnitude : threshold + (magnitude - threshold) * 0.35
        let clamped = min(resisted, maximum)
        return isMine ? -clamped : clamped
    }

    static func isTriggered(_ offset: CGFloat) -> Bool { abs(offset) >= threshold }

    static func progress(_ offset: CGFloat) -> Double { Double(min(abs(offset) / threshold, 1)) }
}

/// Baloncukların (yalnızca baloncuk; satırın tamamı değil) pencere (`.global`) koordinatındaki çerçeveleri.
/// Pencere koordinatı UIKit hareketinin konumuyla birebir aynıdır; kaydırma payı ya da üst çubuk farkı olmaz.
struct ChatBubbleFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Sohbetin kaydırma görünümüne yatay çekme hareketi ekler (sola: saatler ya da kendi mesajını yanıtla;
/// sağa: karşı tarafın mesajını yanıtla). Dikey kaydırma ve uzun basma menüsü bozulmaz: hareket yalnızca
/// belirgin biçimde yatay başlarsa ve `shouldBegin` izin verirse tanınır. Konumlar pencere koordinatındadır.
struct ChatHorizontalPanAttacher: UIViewRepresentable {
    var isEnabled: Bool
    /// Görünen alandaki başlangıç noktası ve hız (x > 0 sağa) → hareket başlasın mı.
    var shouldBegin: (CGPoint, CGPoint) -> Bool = { _, velocity in velocity.x < 0 }
    /// `true` dönerse hareket sürdükçe dikey kaydırma kilitlenir (baloncuğu yanıt için çekerken liste oynamasın).
    var onBegan: (CGPoint, CGPoint) -> Bool = { _, _ in false }
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeUIView(context: Context) -> AttachView {
        let view = AttachView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: AttachView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ uiView: AttachView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class AttachView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var candidate = superview
            while let view = candidate, !(view is UIScrollView) { candidate = view.superview }
            if let scrollView = candidate as? UIScrollView { coordinator?.attach(to: scrollView) }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ChatHorizontalPanAttacher
        private var recognizer: UIPanGestureRecognizer?
        private weak var scrollView: UIScrollView?

        init(parent: ChatHorizontalPanAttacher) {
            self.parent = parent
        }

        func attach(to scrollView: UIScrollView) {
            guard self.scrollView !== scrollView else { return }
            detach()
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.delegate = self
            pan.cancelsTouchesInView = false
            scrollView.addGestureRecognizer(pan)
            recognizer = pan
            self.scrollView = scrollView
        }

        func detach() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            scrollView = nil
        }

        /// Pencere koordinatındaki konum (SwiftUI `.global` ile aynı).
        private func visibleLocation(_ gesture: UIGestureRecognizer) -> CGPoint {
            gesture.location(in: nil)
        }

        @objc private func handle(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                if parent.onBegan(visibleLocation(gesture), gesture.velocity(in: gesture.view)) {
                    scrollView?.isScrollEnabled = false
                }
            case .changed:
                parent.onChanged(gesture.translation(in: gesture.view).x)
            case .ended, .cancelled, .failed:
                scrollView?.isScrollEnabled = true
                parent.onEnded()
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.isEnabled, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            guard abs(velocity.x) > abs(velocity.y) * 1.5 else { return false }
            return parent.shouldBegin(visibleLocation(pan), velocity)
        }

        /// Yatay çekerken liste dikeyde de az da olsa kayabilir (Instagram'daki gibi); uzun basma menüsü de çalışır.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Satırın sağında, sola kaydırınca beliren saat.
struct ChatRevealedTime: View {
    let date: Date
    let offset: CGFloat

    var body: some View {
        Text(ChatDateText.time(date))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Color.ftTextSecondary)
            .fixedSize()
            .frame(width: ChatTimeReveal.width - 8, alignment: .trailing)
            // Dinlenirken ekranın dışında; kaydırdıkça içeri girer.
            .offset(x: ChatTimeReveal.width + 4 + offset)
            .opacity(ChatTimeReveal.progress(offset))
            .accessibilityHidden(true)
    }
}

// MARK: - Mesaj bilgisi

/// Uzun bas → Bilgi: WhatsApp'taki gibi gönderildi / iletildi / görüldü zamanları.
struct ChatMessageInfoSheet: View {
    let item: ChatMessageItem
    let info: ChatMessageInfo
    let partnerName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        if item.isMine { Spacer(minLength: 40) }
                        Text(preview)
                            .font(.body)
                            .foregroundStyle(.white)
                            .lineLimit(6)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(item.isMine ? Color.ftAccent : Color.ftCardElevated,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        if !item.isMine { Spacer(minLength: 40) }
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("Mesaj: \(preview)")
                }

                Section {
                    ForEach(info.rows, id: \.title) { row in
                        HStack(spacing: 12) {
                            Image(systemName: row.systemImage)
                                .foregroundStyle(row.date == nil ? Color.ftTextSecondary : Color.ftAccentLight)
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            Text(row.title)
                            Spacer()
                            Text(row.date.map { ChatDateText.full($0, now: .now) } ?? "—")
                                .monospacedDigit()
                                .foregroundStyle(Color.ftTextSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    if item.isMine, item.message.readAt == nil {
                        Text("\(partnerName) mesajı açtığında görüldü zamanı burada yazar.")
                    }
                }
                .listRowBackground(Color.ftCard)
            }
            .scrollContentBackground(.hidden)
            .ftScreenBackground()
            .navigationTitle("Mesaj bilgisi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var preview: String {
        let text = item.displayText
        return text.isEmpty ? item.message.type.placeholder : text
    }
}

// MARK: - Konuşmada bul çubuğu

/// Altta açılan arama çubuğu: yazdıkça sohbette taranır, sağdaki oklarla eşleşen baloncuklar arasında gezilir.
struct ChatFindBar: View {
    @Environment(\.chatTint) private var tint
    @Bindable var viewModel: ChatViewModel
    var focused: FocusState<Bool>.Binding
    let onOlder: () -> Void
    let onNewer: () -> Void
    let onDone: () -> Void

    private var hasQuery: Bool { !viewModel.findQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(tint.secondary)
                    .accessibilityHidden(true)
                TextField("Sohbette ara", text: $viewModel.findQuery)
                    .focused(focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(onOlder)
                    .accessibilityLabel("Sohbette ara")
                if hasQuery {
                    Text(viewModel.find.count == 0 ? "Yok" : viewModel.find.positionText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(tint.secondary)
                        .accessibilityLabel(viewModel.find.count == 0 ? "Sonuç yok" : "\(viewModel.find.count) sonuçtan \(viewModel.find.positionText.split(separator: "/").first ?? "")")
                    Button { viewModel.findQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(tint.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Aramayı temizle")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(tint.field, in: RoundedRectangle(cornerRadius: tint.corner, style: .continuous))

            Button(action: onOlder) {
                Image(systemName: "chevron.up").font(.body.weight(.semibold)).frame(width: 30, height: 36)
            }
            .disabled(!viewModel.find.canGoOlder)
            .accessibilityLabel("Önceki (daha eski) sonuç")

            Button(action: onNewer) {
                Image(systemName: "chevron.down").font(.body.weight(.semibold)).frame(width: 30, height: 36)
            }
            .disabled(!viewModel.find.canGoNewer)
            .accessibilityLabel("Sonraki (daha yeni) sonuç")

            Button("Bitti", action: onDone)
                .font(.subheadline.weight(.semibold))
        }
        .tint(tint.icon)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(tint.text)
        .background(ChatChromeBackground().ignoresSafeArea(edges: .bottom))
        .chatTintScheme()
    }
}
