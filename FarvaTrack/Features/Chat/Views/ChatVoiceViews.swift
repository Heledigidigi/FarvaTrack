import SwiftUI

// MARK: - Dalga formu

/// 0…1 arası çubuklar; `progress` kadarı vurgu rengiyle çizilir.
struct VoiceWaveformView: View {
    let levels: [Float]
    var progress: Double = 0
    var activeColor: Color = .white
    var inactiveColor: Color = .white.opacity(0.4)

    var body: some View {
        Canvas { context, size in
            guard !levels.isEmpty else { return }
            let gap: CGFloat = 2
            let barWidth = max(1.5, (size.width - gap * CGFloat(levels.count - 1)) / CGFloat(levels.count))
            for (index, level) in levels.enumerated() {
                let height = max(3, CGFloat(level) * size.height)
                let x = CGFloat(index) * (barWidth + gap)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                let played = (Double(index) + 0.5) / Double(levels.count) <= progress
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(played ? activeColor : inactiveColor))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Mikrofon düğmesi

/// Basılı tut = kaydet, sola kaydır = iptal, yukarı kaydır = kilitle; kilitliyken gönder düğmesine dönüşür.
struct VoiceMicButton: View {
    let recorder: ChatVoiceRecorderModel
    let onVoice: (RecordedVoice) -> Void
    @State private var pressing = false

    var body: some View {
        Group {
            if recorder.phase == .locked {
                Button {
                    if let voice = recorder.finish() {
                        Haptics.impact(.light)
                        onVoice(voice)
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.ftAccentLight)
                }
                .accessibilityLabel("Sesli mesajı gönder")
            } else {
                micBody
            }
        }
        .overlay(alignment: .bottom) {
            if recorder.phase == .recording {
                lockHint
                    .offset(y: -56 - CGFloat(recorder.lockProgress) * 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.25), value: recorder.phase)
    }

    private var micBody: some View {
        let recording = recorder.phase == .recording
        return Image(systemName: "mic.fill")
            .font(.system(size: recording ? 26 : 22))
            .foregroundStyle(recording ? .white : Color.ftAccentLight)
            .frame(width: recording ? 56 : 36, height: recording ? 56 : 40)
            .background {
                if recording { Circle().fill(Color.ftAccent) }
            }
            .offset(x: recording ? -CGFloat(recorder.cancelProgress) * 40 : 0)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !pressing {
                            pressing = true
                            Task {
                                if await recorder.begin() { Haptics.impact(.medium) }
                            }
                        }
                        let wasRecording = recorder.phase == .recording
                        recorder.dragChanged(value.translation)
                        if wasRecording, recorder.phase == .idle { Haptics.impact(.rigid) }
                        if wasRecording, recorder.phase == .locked { Haptics.selection() }
                    }
                    .onEnded { _ in
                        pressing = false
                        if let voice = recorder.release() {
                            Haptics.impact(.light)
                            onVoice(voice)
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Sesli mesaj kaydet")
            .accessibilityHint("Kaydetmek için basılı tut. VoiceOver ile iki kez dokunarak kilitli kayıt başlatılır.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                // VoiceOver'da basılı tutmak zor: doğrudan kilitli kayıt.
                Task {
                    if await recorder.begin() {
                        recorder.dragChanged(CGSize(width: 0, height: -ChatVoiceRecorderModel.lockDistance))
                    }
                }
            }
    }

    private var lockHint: some View {
        VStack(spacing: 4) {
            Image(systemName: recorder.lockProgress > 0.9 ? "lock.fill" : "lock.open.fill")
            Image(systemName: "chevron.up")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(Color.ftCardElevated, in: Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - Kayıt çubuğu (yazı alanının yerine)

struct VoiceRecordingBar: View {
    let recorder: ChatVoiceRecorderModel
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            if recorder.phase == .locked {
                Button {
                    recorder.cancel()
                    Haptics.impact(.rigid)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.ftDanger)
                        .frame(width: 36, height: 40)
                }
                .accessibilityLabel("Kaydı sil")
            } else {
                Circle()
                    .fill(Color.ftDanger)
                    .frame(width: 10, height: 10)
                    .opacity(pulse ? 0.25 : 1)
                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: pulse)
                    .onAppear { pulse = true }
                    .accessibilityHidden(true)
            }

            Text(VoiceFormat.time(recorder.elapsed))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityLabel("Kayıt süresi \(VoiceFormat.time(recorder.elapsed))")

            if recorder.phase == .locked {
                VoiceWaveformView(levels: VoiceWaveform.recent(recorder.levels, count: 40), progress: 1, activeColor: Color.ftAccentLight)
                    .frame(height: 26)
            } else {
                VoiceWaveformView(levels: VoiceWaveform.recent(recorder.levels, count: 18), progress: 1, activeColor: Color.ftAccentLight)
                    .frame(width: 70, height: 24)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                    Text("İptal için kaydır")
                }
                .font(.footnote)
                .foregroundStyle(Color.ftTextSecondary)
                .opacity(1 - recorder.cancelProgress * 0.8)
                .offset(x: -CGFloat(recorder.cancelProgress) * 30)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(recorder.phase == .locked ? "Kilitli kayıt sürüyor" : "Kayıt sürüyor")
    }
}

// MARK: - Mesajdaki sesli mesaj

struct ChatVoiceBubbleContent: View {
    let item: ChatMessageItem
    let audio: ChatAudio
    let player: ChatAudioPlayer
    let onLoad: () async throws -> URL
    let onToggle: () -> Void

    @State private var fileURL: URL?
    @State private var isLoading = false

    private var isCurrent: Bool { player.isCurrent(item.id) }
    private var isPlaying: Bool { isCurrent && player.isPlaying }
    private var levels: [Float] { audio.waveform.map { Float($0) / 255 } }
    private var progress: Double { isCurrent ? player.progress : 0 }

    var body: some View {
        HStack(spacing: 10) {
            playButton

            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { proxy in
                    VoiceWaveformView(
                        levels: levels,
                        progress: progress,
                        activeColor: item.isMine ? .white : Color.ftAccentLight,
                        inactiveColor: .white.opacity(0.35)
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                seek(to: Double(value.location.x / max(proxy.size.width, 1)))
                            }
                    )
                }
                .frame(height: 28)

                HStack(spacing: 6) {
                    Text(VoiceFormat.time(isCurrent && player.currentTime > 0 ? player.currentTime : audio.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                    if !item.isMine, !item.isListened {
                        // Dinlenmemiş sesli mesaj.
                        Circle().fill(Color.ftWater).frame(width: 6, height: 6)
                    }
                    Spacer(minLength: 0)
                    if isCurrent {
                        Button {
                            player.cycleRate()
                            Haptics.selection()
                        } label: {
                            Text(player.rate.title)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }
            }

            Image(systemName: "mic.fill")
                .font(.system(size: 14))
                .foregroundStyle(item.isListened ? Color.ftWater : .white.opacity(0.55))
                .accessibilityHidden(true)
        }
        .frame(width: 236)
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var playButton: some View {
        ZStack {
            Circle().fill(.white.opacity(0.18)).frame(width: 40, height: 40)
            if item.isUploading {
                if let value = item.uploadProgress {
                    Circle()
                        .trim(from: 0, to: max(0.03, value))
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 34, height: 34)
                } else {
                    ProgressView().tint(.white)
                }
            } else if isLoading {
                ProgressView().tint(.white)
            } else {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: isPlaying ? 0 : 1.5)
            }
        }
        .contentShape(Circle())
        .onTapGesture {
            guard !item.isUploading, !isLoading else { return }
            Haptics.impact(.light)
            onToggle()
        }
    }

    private func seek(to fraction: Double) {
        guard !item.isUploading else { return }
        if let fileURL {
            player.seek(id: item.id, url: fileURL, to: fraction)
            return
        }
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            if let url = try? await onLoad() {
                fileURL = url
                player.seek(id: item.id, url: url, to: fraction)
            }
        }
    }
}
