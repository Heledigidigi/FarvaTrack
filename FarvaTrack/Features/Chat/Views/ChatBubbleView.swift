import SwiftUI

/// Tek mesaj baloncuğu; uzun basınca yanıtla / tepki / kopyala / düzenle / sil menüsü.
struct ChatBubbleView: View {
    let item: ChatMessageItem
    let currentUserID: String
    let partnerName: String
    let isHighlighted: Bool
    let onReply: () -> Void
    let onReact: (String) -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDeleteForMe: () -> Void
    let onDeleteForEveryone: () -> Void
    let onRetry: () -> Void
    let onOpenQuote: (String) -> Void
    var onOpenMedia: () -> Void = {}
    var onCancelUpload: () -> Void = {}
    var onLoadThumbnail: () async -> Void = {}
    /// Sticker mesajı (8E).
    var onLoadSticker: () async -> Void = {}
    var onSaveSticker: () -> Void = {}
    /// Sesli mesaj: çalar (8C).
    var player: ChatAudioPlayer?
    var onLoadAudio: () async throws -> URL = { throw AppError.storage("Ses yok") }
    var onToggleAudio: () -> Void = {}
    /// Gönderenin baloncuk stili (8F); `nil` = varsayılan.
    var bubbleStyle: BubbleStyle?
    var bubbleAssets: BubbleAssets = .empty
    var bubbleCacheOwner: String = ""
    /// Arama satırı (8H): geri ara. `nil` = gösterilmez (ör. not sohbeti).
    var onCallBack: (() -> Void)?
    /// Uzun bas → Bilgi (gönderildi / iletildi / görüldü).
    var onInfo: () -> Void = {}
    /// Alıntılanan mesaj fotoğraf/video/sticker ise küçük resmi (cihazda varsa).
    var quoteThumbnail: URL?

    private var message: ChatMessageDTO { item.message }

    /// Stil yalnızca metin ve sesli mesajlarda uygulanır (fotoğraf, video, sticker kendi görünümünü korur).
    private var appliedStyle: BubbleStyle? {
        guard let bubbleStyle, !message.deleted, message.media == nil, message.sticker == nil else { return nil }
        // Çizimli baloncuk (Kutu Kedi) yalnızca metin mesajlarında; sesli mesaj ve arama satırı kendi görünümünde kalır.
        if bubbleStyle.art != nil, message.audio != nil || message.call != nil { return nil }
        return bubbleStyle
    }

    private var contentInsets: EdgeInsets {
        if let style = appliedStyle {
            let padding = BubbleLayout.contentPadding(for: style, mirrored: !item.isMine)
            return EdgeInsets(top: padding.top, leading: padding.leading, bottom: padding.bottom, trailing: padding.trailing)
        }
        // Sticker ve fotoğraf/video baloncuksuz, kenarlıksız.
        if isSticker || isBorderlessMedia { return EdgeInsets() }
        return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if let style = appliedStyle {
            BubbleBackgroundView(style: style, assets: bubbleAssets, mirrored: !item.isMine, cacheOwner: bubbleCacheOwner)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(bubbleColor)
        }
    }
    private var canCopy: Bool { !message.deleted && message.type == .text }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if item.isMine { Spacer(minLength: 48) }

            VStack(alignment: item.isMine ? .trailing : .leading, spacing: 2) {
                bubble
                if !item.reactionSummary.isEmpty {
                    reactions
                }
            }

            if !item.isMine { Spacer(minLength: 48) }
        }
        .padding(.top, item.reactionSummary.isEmpty ? 2 : 4)
    }

    // MARK: Baloncuk

    private var bubble: some View {
        // Genişlik içeriğe göre; saat satırı sağa yaslı.
        VStack(alignment: .trailing, spacing: 6) {
            if let reply = message.replyTo, !message.deleted {
                quote(reply)
            }

            if let call = message.call, !message.deleted {
                callRow(call)
            } else if let diet = message.diet, !message.deleted {
                DietChatCard(info: diet, isMine: item.isMine)
            } else if isBorderlessMedia, let media = message.media {
                ChatMediaBubbleContent(
                    item: item, media: media,
                    onOpen: { item.status == .failed ? onRetry() : onOpenMedia() },
                    onCancelUpload: onCancelUpload, onLoadThumbnail: onLoadThumbnail
                )
                .overlay(alignment: .bottomTrailing) {
                    if hasFooter, caption == nil {
                        footer(floating: true).padding(6)
                    }
                }
                if let caption {
                    // Fotoğrafın altına yazılan açıklama: küçük baloncuk.
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(caption)
                            .font(.body)
                            .foregroundStyle(defaultInk)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if hasFooter { footer(floating: false) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(item.isMine ? Color.ftAccent : Color.ftCardElevated,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(width: 250)
                }
            } else if let sticker = message.sticker, !message.deleted {
                ChatStickerBubbleContent(item: item, sticker: sticker, onLoad: onLoadSticker)
            } else if let audio = message.audio, !message.deleted, let player {
                ChatVoiceBubbleContent(item: item, audio: audio, player: player, onLoad: onLoadAudio, onToggle: onToggleAudio)
            } else {
                messageText
            }

            if hasFooter, !isBorderlessMedia, !isCatBox {
                footer(floating: isSticker)
            } else if isCatBox, message.editedAt != nil {
                // Kutu Kedi: durum tiki kedinin dışında; "düzenlendi" yazısı metnin altında kalır.
                Text("düzenlendi")
                    .font(.caption2)
                    .foregroundStyle(contentColor.opacity(0.6))
            }
        }
        .frame(minWidth: appliedStyle.flatMap(BubbleLayout.minimumContentSize(for:))?.width,
               minHeight: appliedStyle.flatMap(BubbleLayout.minimumContentSize(for:))?.height)
        .padding(contentInsets)
        .background { bubbleBackground }
        .overlay(alignment: item.isMine ? .bottomTrailing : .bottomLeading) {
            if isCatBox, let status = item.status, !message.deleted {
                let offset = CatBoxGeometry.statusMarkOffset
                CatBoxStatusMark(status: status)
                    .frame(width: CatBoxStatusMark.size.width, height: CatBoxStatusMark.size.height)
                    .offset(x: item.isMine ? CatBoxStatusMark.size.width / 2 - offset.width : offset.width - CatBoxStatusMark.size.width / 2,
                            y: CatBoxStatusMark.size.height / 2 - offset.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.ftAccentLight, lineWidth: isHighlighted ? 2 : 0)
        )
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: ChatBubbleFramePreference.self,
                                       value: [item.id: geometry.frame(in: .global)])
            }
        )
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu { menu }
        .onTapGesture {
            if item.status == .failed { onRetry() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityActions { accessibilityActionList }
    }

    private var accessibilityHintText: String {
        if item.status == .failed { return "Tekrar göndermek için iki kez dokun" }
        if message.media != nil, !message.deleted, !item.isUploading { return "Açmak için eylemler menüsünden Aç'ı seç" }
        if message.audio != nil, !message.deleted, !item.isUploading { return "Çalmak için eylemler menüsünden Oynat'ı seç" }
        return "Seçenekler için eylemler menüsünü kullan"
    }

    /// Sohbetteki arama geçmişi satırı: yön, sonuç, süre ve geri ara.
    private func callRow(_ call: ChatCallInfo) -> some View {
        let missed = call.outcome != .answered
        return HStack(spacing: 10) {
            Image(systemName: item.isMine ? "phone.arrow.up.right.fill" : (missed ? "phone.arrow.down.left.fill" : "phone.arrow.down.left.fill"))
                .foregroundStyle(missed && !item.isMine ? Color.ftDanger : defaultInk)
                .font(.body)
                .accessibilityHidden(true)
            Text(item.displayText)
                .font(.body)
                .foregroundStyle(defaultInk)
            if let onCallBack {
                Button {
                    Haptics.impact(.light)
                    onCallBack()
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.footnote.bold())
                        .padding(7)
                        .background(defaultInk.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Geri ara")
            }
        }
    }

    private var messageText: some View {
            Text(item.displayText)
                .font(.body)
                .italic(message.deleted || message.type != .text)
                .foregroundStyle(message.deleted ? defaultInk.opacity(0.6) : (appliedStyle.map { Color(hex: $0.textColorHex) } ?? defaultInk))
                .multilineTextAlignment(.leading)
                .frame(alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
    }

    /// Baloncuk içindeki yazı rengi (açık renkli çizimli baloncukta koyu).
    private var contentColor: Color {
        appliedStyle.map { Color(hex: $0.textColorHex) } ?? defaultInk
    }

    /// Varsayılan baloncukta yazı rengi: giden (vurgu zemin) beyaz, gelen ve silinen tema yazı rengi.
    private var defaultInk: Color {
        item.isMine && !message.deleted ? .white : Color.ftText
    }

    /// Açık zeminli çizimli baloncuk: alıntı ve okundu işareti koyu/bordo çizilir.
    private var isLightBubble: Bool { appliedStyle?.art != nil }

    /// Kutu Kedi baloncuğu: durum tiki baloncuğun dışında, sağ alt köşede.
    private var isCatBox: Bool { appliedStyle?.art == .catBox }

    /// Sticker baloncuksuz gösterilir.
    private var isSticker: Bool { message.sticker != nil && !message.deleted }

    /// Fotoğraf ve video da baloncuksuz: kenarlık ve arka plan yok, durum simgesi fotoğrafın köşesinde.
    private var isBorderlessMedia: Bool { message.media != nil && !message.deleted }

    /// Saat baloncukta yazmaz (sohbeti sola kaydırınca görünür); "düzenlendi" ve gönderim durumu kalır.
    private var hasFooter: Bool {
        (message.editedAt != nil && !message.deleted) || (item.status != nil && !message.deleted)
    }

    private var bubbleColor: Color {
        if isSticker || isBorderlessMedia { return .clear }
        if message.deleted { return Color.ftCard }
        return item.isMine ? Color.ftAccent : Color.ftCardElevated
    }

    private func quote(_ reply: ChatReplyReference) -> some View {
        Button {
            onOpenQuote(reply.messageID)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLightBubble ? Color(hex: "#800020") : Color.ftAccentLight)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(for: reply.senderID))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isLightBubble ? Color(hex: "#800020") : Color.ftAccentLight)
                    if let text = quoteText(reply) {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(contentColor.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                if let quoteThumbnail {
                    CachedImageView(url: quoteThumbnail)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            .padding(6)
            .background(Color.black.opacity(isLightBubble ? 0.08 : 0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Alıntı metni: küçük resim varken "📷 Fotoğraf" yazılmaz, yalnızca açıklama (varsa).
    private func quoteText(_ reply: ChatReplyReference) -> String? {
        guard quoteThumbnail != nil, reply.type.isMedia || reply.type == .sticker else {
            return reply.preview.isEmpty ? reply.type.placeholder : reply.preview
        }
        let placeholder = reply.type.placeholder
        var text = reply.preview
        for prefix in ["📷 ", "🎬 "] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || reply.preview == placeholder ? nil : text
    }

    /// Fotoğrafın altındaki açıklama (yoksa `nil`).
    private var caption: String? {
        guard isBorderlessMedia else { return nil }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : message.text
    }

    private func footer(floating: Bool) -> some View {
        HStack(spacing: 4) {
            if message.editedAt != nil, !message.deleted {
                Text("düzenlendi")
            }
            if let status = item.status, !message.deleted {
                Image(systemName: status.systemImage)
                    .foregroundStyle(statusColor(status))
            }
        }
        .font(.caption2)
        .foregroundStyle(floating ? Color.white.opacity(0.9) : contentColor.opacity(0.65))
        .padding(.horizontal, floating ? 7 : 0)
        .padding(.vertical, floating ? 3 : 0)
        // Baloncuksuz içerikte (sticker, fotoğraf) okunabilsin diye küçük kapsül.
        .background(floating ? Color.black.opacity(0.45) : .clear, in: Capsule())
    }

    private func statusColor(_ status: ChatMessageStatus) -> Color {
        switch status {
        case .failed: return Color.ftDanger
        case .read: return isLightBubble ? Color(hex: "#800020") : Color.ftWater
        case .sending, .delivered: return contentColor.opacity(0.65)
        }
    }

    private var reactions: some View {
        HStack(spacing: 4) {
            ForEach(item.reactionSummary, id: \.emoji) { reaction in
                Button {
                    onReact(reaction.emoji)
                } label: {
                    HStack(spacing: 2) {
                        Text(reaction.emoji)
                        if reaction.count > 1 {
                            Text("\(reaction.count)").font(.caption2.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        reaction.emoji == item.myReaction ? Color.ftAccent.opacity(0.6) : Color.ftCard,
                        in: Capsule()
                    )
                    .overlay(Capsule().strokeBorder(Color.ftBackground, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reaction.emoji == item.myReaction ? "Tepkin \(reaction.emoji), kaldırmak için dokun" : "Tepki \(reaction.emoji)")
            }
        }
        .padding(.top, -8)
        .padding(.horizontal, 8)
    }

    // MARK: Menü

    @ViewBuilder
    private var menu: some View {
        if !message.deleted {
            if message.media != nil, !item.isUploading, item.status != .failed {
                Button { onOpenMedia() } label: { Label("Aç", systemImage: "arrow.up.left.and.arrow.down.right") }
            }
            if item.isUploading {
                Button(role: .destructive) { onCancelUpload() } label: { Label("Gönderimi iptal et", systemImage: "xmark.circle") }
            }
            if message.sticker != nil, !item.isMine {
                Button { onSaveSticker() } label: { Label("Kütüphaneme kaydet", systemImage: "square.and.arrow.down") }
            }
            if message.call != nil, let onCallBack {
                Button { onCallBack() } label: { Label("Geri ara", systemImage: "phone.fill") }
            }
            Button { onReply() } label: { Label("Yanıtla", systemImage: "arrowshape.turn.up.left") }

            Menu {
                ForEach(ChatLimits.quickReactions, id: \.self) { emoji in
                    Button { onReact(emoji) } label: {
                        Text(emoji == item.myReaction ? "\(emoji) (kaldır)" : emoji)
                    }
                }
            } label: {
                Label("Tepki ver", systemImage: "face.smiling")
            }

            if canCopy {
                Button { onCopy() } label: { Label("Kopyala", systemImage: "doc.on.doc") }
            }
            if item.canEdit {
                Button { onEdit() } label: { Label("Düzenle", systemImage: "pencil") }
            }
            if item.status == .failed {
                Button { onRetry() } label: { Label("Tekrar gönder", systemImage: "arrow.clockwise") }
            }
            Button { onInfo() } label: { Label("Bilgi", systemImage: "info.circle") }
        }

        Divider()

        Button(role: .destructive) { onDeleteForMe() } label: {
            Label("Benden sil", systemImage: "trash")
        }
        if item.isMine, !message.deleted {
            Button(role: .destructive) { onDeleteForEveryone() } label: {
                Label("Herkesten sil", systemImage: "trash.slash")
            }
        }
    }

    @ViewBuilder
    private var accessibilityActionList: some View {
        if !message.deleted {
            if message.media != nil, !item.isUploading, item.status != .failed {
                Button("Aç", action: onOpenMedia)
            }
            if message.audio != nil, !item.isUploading, item.status != .failed {
                Button(player?.isCurrent(item.id) == true && player?.isPlaying == true ? "Duraklat" : "Oynat", action: onToggleAudio)
                if player?.isCurrent(item.id) == true, let player {
                    Button("Hızı değiştir, şu an \(player.rate.title)") { player.cycleRate() }
                }
            }
            if item.isUploading { Button("Gönderimi iptal et", action: onCancelUpload) }
            if message.sticker != nil, !item.isMine { Button("Kütüphaneme kaydet", action: onSaveSticker) }
            Button("Yanıtla", action: onReply)
            ForEach(ChatLimits.quickReactions, id: \.self) { emoji in
                Button("\(emoji) tepkisi ver") { onReact(emoji) }
            }
            if canCopy { Button("Kopyala", action: onCopy) }
            if item.canEdit { Button("Düzenle", action: onEdit) }
            if item.status == .failed { Button("Tekrar gönder", action: onRetry) }
            Button("Bilgi", action: onInfo)
        }
        Button("Benden sil", action: onDeleteForMe)
        if item.isMine, !message.deleted {
            Button("Herkesten sil", action: onDeleteForEveryone)
        }
    }

    // MARK: VoiceOver

    private func name(for senderID: String) -> String {
        senderID == currentUserID ? "Sen" : partnerName
    }

    private var accessibilityText: String {
        var parts = [item.isMine ? "Sen" : partnerName]
        if let reply = message.replyTo, !message.deleted {
            parts.append("\(name(for: reply.senderID)) kişisine yanıt: \(reply.preview)")
        }
        if message.sticker != nil, !message.deleted {
            parts.append(item.isUploading ? "Sticker, gönderiliyor" : "Sticker")
        } else if let audio = message.audio, !message.deleted {
            var description = "Sesli mesaj, \(audio.formattedDuration)"
            if item.isUploading { description += ", gönderiliyor" }
            if item.isMine, item.isListened { description += ", dinlendi" }
            if !item.isMine, !item.isListened { description += ", dinlenmedi" }
            parts.append(description)
        } else if let media = message.media, !message.deleted {
            var description = message.type == .video ? "Video" : "Fotoğraf"
            if let duration = media.formattedDuration { description += ", \(duration)" }
            if item.isUploading {
                description += item.uploadProgress.map { ", yükleniyor yüzde \(Int($0 * 100))" } ?? ", hazırlanıyor"
            } else if !item.isMine, media.status == .uploading {
                description += ", gönderiliyor"
            }
            parts.append(description)
        } else {
            parts.append(item.displayText)
        }
        if message.editedAt != nil, !message.deleted { parts.append("düzenlendi") }
        parts.append(message.createdAt.formatted(date: .omitted, time: .shortened))
        if let status = item.status, !message.deleted { parts.append(status.accessibilityText) }
        let reactionText = item.reactionSummary.map { $0.count > 1 ? "\($0.emoji) \($0.count)" : $0.emoji }
        if !reactionText.isEmpty { parts.append("tepkiler: " + reactionText.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Yazma alanı

struct ChatComposer: View {
    @Bindable var viewModel: ChatViewModel
    var focused: FocusState<Bool>.Binding
    /// Açık panelin düğmesi klavye simgesine döner (dokununca klavyeye geçilir).
    var activePanel: ChatInputPanel = .none
    var onGallery: () -> Void = {}
    var onCamera: () -> Void = {}
    var onStickers: () -> Void = {}
    var recorder: ChatVoiceRecorderModel?
    var onVoice: (RecordedVoice) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 6) {
            if let reply = viewModel.replyingTo {
                // Fotoğraf/video/sticker yanıtında "Fotoğraf" yazmaz; küçük resmi gösterilir (açıklama varsa o yazar).
                let visual = ChatReplyVisual(item: reply)
                contextBar(
                    icon: "arrowshape.turn.up.left.fill",
                    title: reply.isMine ? "Kendi mesajına yanıt" : "\(viewModel.partnerName) kişisine yanıt",
                    text: visual.text,
                    thumbnail: visual.thumbnailURL,
                    isVideo: reply.message.type == .video
                )
            } else if let editing = viewModel.editing {
                contextBar(icon: "pencil", title: "Mesajı düzenle", text: editing.message.text)
            }

            HStack(alignment: .bottom, spacing: 8) {
                if let recorder, recorder.isActive {
                    // Kayıt sürerken yazı alanının yerinde süre ve canlı dalga formu.
                    VoiceRecordingBar(recorder: recorder)
                } else {
                if viewModel.editing == nil {
                    Button(action: onGallery) {
                        Image(systemName: activePanel == .gallery ? "keyboard" : "photo.on.rectangle.angled")
                            .font(.system(size: 22))
                            .frame(width: 36, height: 40)
                    }
                    .foregroundStyle(Color.ftAccentLight)
                    .accessibilityLabel(activePanel == .gallery ? "Klavyeye dön" : "Galeri")
                    .accessibilityHint(activePanel == .gallery ? "" : "Son fotoğraf ve videoları klavyenin yerinde gösterir")

                    Button(action: onStickers) {
                        Image(systemName: activePanel == .stickers ? "keyboard" : "face.smiling")
                            .font(.system(size: 22))
                            .frame(width: 32, height: 40)
                    }
                    .foregroundStyle(Color.ftAccentLight)
                    .accessibilityLabel(activePanel == .stickers ? "Klavyeye dön" : "Sticker'larım")
                    .accessibilityHint(activePanel == .stickers ? "" : "Sticker panelini klavyenin yerinde açar")
                }

                TextField("Mesaj", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused(focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onChange(of: viewModel.draft) { _, _ in viewModel.draftChanged() }
                    .accessibilityLabel("Mesaj yaz")

                if viewModel.editing == nil, viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // WhatsApp gibi: yazı yokken kamera, yazınca gönder düğmesi.
                    Button {
                        Haptics.impact(.light)
                        onCamera()
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22))
                            .frame(width: 36, height: 40)
                    }
                    .foregroundStyle(Color.ftAccentLight)
                    .accessibilityLabel("Kamera")
                    .accessibilityHint("Fotoğraf çek ya da video kaydet")
                }
                }

                if viewModel.editing == nil, viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let recorder {
                    // Mikrofon düğmesi hep aynı yerde kalır: kayıt sürerken hareket kesilmesin.
                    VoiceMicButton(recorder: recorder, onVoice: onVoice)
                } else if viewModel.editing != nil || !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    viewModel.send()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: viewModel.editing == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(viewModel.canSend ? Color.ftAccentLight : Color.ftTextSecondary)
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel(viewModel.editing == nil ? "Gönder" : "Düzenlemeyi kaydet")
                }
            }

            if viewModel.draftIsTooLong {
                Text("Mesaj çok uzun: en fazla \(ChatLimits.maxTextLength) karakter.")
                    .font(.caption)
                    .foregroundStyle(Color.ftDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ftChrome.ignoresSafeArea(edges: .bottom))
    }

    private func contextBar(icon: String, title: String, text: String, thumbnail: URL? = nil, isVideo: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.ftAccentLight)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ftAccentLight)
                if !text.isEmpty {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let thumbnail {
                CachedImageView(url: thumbnail)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        if isVideo {
                            Image(systemName: "play.fill").font(.caption2).foregroundStyle(.white).shadow(radius: 2)
                        }
                    }
                    .accessibilityLabel(isVideo ? "Video" : "Fotoğraf")
            }
            Button {
                viewModel.cancelComposerContext()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.ftTextSecondary)
            }
            .accessibilityLabel("Vazgeç")
        }
        .padding(8)
        .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Yanıtta görsel önizleme

/// Yanıtlanan fotoğraf/video/sticker için küçük resim ve (varsa) açıklama.
struct ChatReplyVisual {
    let thumbnailURL: URL?
    let text: String

    init(item: ChatMessageItem) {
        let message = item.message
        if message.media != nil, !message.deleted {
            thumbnailURL = item.localThumbnailURL
            let caption = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = caption.isEmpty ? (item.localThumbnailURL == nil ? message.type.placeholder : "") : caption
        } else if message.sticker != nil, !message.deleted, let url = item.localOriginalURL {
            thumbnailURL = url
            text = ""
        } else {
            thumbnailURL = nil
            text = item.displayText
        }
    }
}
