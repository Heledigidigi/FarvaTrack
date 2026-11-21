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

    private var message: ChatMessageDTO { item.message }
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

            if let sticker = message.sticker, !message.deleted {
                ChatStickerBubbleContent(item: item, sticker: sticker, onLoad: onLoadSticker)
            } else if let audio = message.audio, !message.deleted, let player {
                ChatVoiceBubbleContent(item: item, audio: audio, player: player, onLoad: onLoadAudio, onToggle: onToggleAudio)
            } else if let media = message.media, !message.deleted {
                ChatMediaBubbleContent(
                    item: item, media: media,
                    onOpen: { item.status == .failed ? onRetry() : onOpenMedia() },
                    onCancelUpload: onCancelUpload, onLoadThumbnail: onLoadThumbnail
                )
            } else {
                messageText
            }

            footer
        }
        .padding(.horizontal, isSticker ? 0 : (message.media != nil && !message.deleted ? 4 : 12))
        .padding(.vertical, isSticker ? 0 : (message.media != nil && !message.deleted ? 4 : 8))
        .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.ftAccentLight, lineWidth: isHighlighted ? 2 : 0)
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

    private var messageText: some View {
            Text(item.displayText)
                .font(.body)
                .italic(message.deleted || message.type != .text)
                .foregroundStyle(message.deleted ? Color.white.opacity(0.6) : .white)
                .multilineTextAlignment(.leading)
                .frame(alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
    }

    /// Sticker baloncuksuz gösterilir.
    private var isSticker: Bool { message.sticker != nil && !message.deleted }

    private var bubbleColor: Color {
        if isSticker { return .clear }
        if message.deleted { return Color.ftCard }
        return item.isMine ? Color.ftAccent : Color.ftCardElevated
    }

    private func quote(_ reply: ChatReplyReference) -> some View {
        Button {
            onOpenQuote(reply.messageID)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.ftAccentLight)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(for: reply.senderID))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.ftAccentLight)
                    Text(reply.preview.isEmpty ? reply.type.placeholder : reply.preview)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if message.editedAt != nil, !message.deleted {
                Text("düzenlendi")
            }
            Text(message.createdAt.formatted(date: .omitted, time: .shortened))
            if let status = item.status, !message.deleted {
                Image(systemName: status.systemImage)
                    .foregroundStyle(statusColor(status))
            }
        }
        .font(.caption2)
        .foregroundStyle(Color.white.opacity(0.65))
        .padding(.horizontal, message.media != nil && !message.deleted ? 6 : (isSticker ? 7 : 0))
        .padding(.vertical, isSticker ? 2 : 0)
        .padding(.bottom, message.media != nil && !message.deleted ? 2 : 0)
        // Sticker baloncuksuz: saat okunabilsin diye küçük kapsül.
        .background(isSticker ? Color.black.opacity(0.4) : .clear, in: Capsule())
    }

    private func statusColor(_ status: ChatMessageStatus) -> Color {
        switch status {
        case .failed: return Color.ftDanger
        case .read: return Color.ftWater
        case .sending, .delivered: return Color.white.opacity(0.65)
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
    var onGallery: () -> Void = {}
    var onCamera: () -> Void = {}
    var onStickers: () -> Void = {}
    var recorder: ChatVoiceRecorderModel?
    var onVoice: (RecordedVoice) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 6) {
            if let reply = viewModel.replyingTo {
                contextBar(
                    icon: "arrowshape.turn.up.left.fill",
                    title: reply.isMine ? "Kendi mesajına yanıt" : "\(viewModel.partnerName) kişisine yanıt",
                    text: reply.displayText
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
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 22))
                            .frame(width: 36, height: 40)
                    }
                    .foregroundStyle(Color.ftAccentLight)
                    .accessibilityLabel("Galeriden fotoğraf veya video seç")

                    Button(action: onStickers) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 22))
                            .frame(width: 32, height: 40)
                    }
                    .foregroundStyle(Color.ftAccentLight)
                    .accessibilityLabel("Sticker'larım")
                    .accessibilityHint("Fotoğraftan sticker oluştur")
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
        .background(Color.ftCard.ignoresSafeArea(edges: .bottom))
    }

    private func contextBar(icon: String, title: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.ftAccentLight)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ftAccentLight)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Color.ftTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
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
