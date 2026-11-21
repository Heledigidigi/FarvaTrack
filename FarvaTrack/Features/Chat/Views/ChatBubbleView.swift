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

            Text(item.displayText)
                .font(.body)
                .italic(message.deleted || message.type != .text)
                .foregroundStyle(message.deleted ? Color.white.opacity(0.6) : .white)
                .multilineTextAlignment(.leading)
                .frame(alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        .accessibilityHint(item.status == .failed ? "Tekrar göndermek için iki kez dokun" : "Seçenekler için eylemler menüsünü kullan")
        .accessibilityActions { accessibilityActionList }
    }

    private var bubbleColor: Color {
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
        parts.append(item.displayText)
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
                TextField("Mesaj", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused(focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onChange(of: viewModel.draft) { _, _ in viewModel.draftChanged() }
                    .accessibilityLabel("Mesaj yaz")

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
