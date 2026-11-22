import SwiftUI
import AVFoundation

/// Uygulama içi arama ekranı (kilit ekranında ve arka planda CallKit'in sistem ekranı görünür).
struct CallView: View {
    @Environment(CallManager.self) private var manager

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Color.ftAccentLight)
                    .accessibilityHidden(true)
                Text(manager.partnerName)
                    .font(.title.bold())
                    .lineLimit(1)
                Text(manager.statusText)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(Color.ftTextSecondary)
                    .contentTransition(.numericText())
                if let quality = manager.quality, manager.phase.connectedSince != nil {
                    CallQualityIndicator(quality: quality, relayed: manager.usingRelay)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer()

            if case .ringing(.incoming) = manager.phase {
                incomingControls
            } else {
                activeControls
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color.ftAccent.opacity(0.55), Color.ftBackground], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        .task {
            // Süre göstergesi saniyede bir tazelenir.
            while !Task.isCancelled {
                manager.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var incomingControls: some View {
        HStack {
            CallButton(title: "Reddet", systemImage: "phone.down.fill", tint: Color.ftDanger, isOn: true) {
                Haptics.impact()
                manager.hangUp()
            }
            Spacer()
            CallButton(title: "Cevapla", systemImage: "phone.fill", tint: Color.ftSuccess, isOn: true) {
                Haptics.success()
                manager.answer()
            }
        }
        .padding(.horizontal, 24)
    }

    private var activeControls: some View {
        VStack(spacing: 28) {
            HStack(spacing: 22) {
                CallButton(title: manager.isMuted ? "Sesi aç" : "Sessiz", systemImage: manager.isMuted ? "mic.slash.fill" : "mic.fill",
                           tint: .white, isOn: manager.isMuted) {
                    Haptics.selection()
                    manager.toggleMute()
                }
                CallButton(title: "Hoparlör", systemImage: manager.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                           tint: .white, isOn: manager.isSpeakerOn) {
                    Haptics.selection()
                    manager.toggleSpeaker()
                }
                CallButton(title: manager.isOnHold ? "Devam et" : "Beklet", systemImage: manager.isOnHold ? "play.fill" : "pause.fill",
                           tint: .white, isOn: manager.isOnHold) {
                    Haptics.selection()
                    manager.toggleHold()
                }
                .disabled(manager.phase.connectedSince == nil)
                .opacity(manager.phase.connectedSince == nil ? 0.4 : 1)
            }
            CallButton(title: "Kapat", systemImage: "phone.down.fill", tint: Color.ftDanger, isOn: true) {
                Haptics.impact()
                manager.hangUp()
            }
            .disabled(!manager.phase.isActive)
        }
    }
}

struct CallButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(isOn && tint == .white ? Color.ftBackground : .white)
                    .frame(width: 70, height: 70)
                    .background(isOn ? tint : Color.white.opacity(0.18), in: Circle())
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn && tint == .white ? .isSelected : [])
    }
}

/// Üç çubuklu bağlantı kalitesi göstergesi.
struct CallQualityIndicator: View {
    let quality: CallQuality
    let relayed: Bool

    private var color: Color {
        switch quality {
        case .good: return Color.ftSuccess
        case .fair: return Color.ftWarning
        case .poor: return Color.ftDanger
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(index < quality.bars ? color : Color.white.opacity(0.2))
                        .frame(width: 5, height: CGFloat(6 + index * 5))
                }
            }
            Text(quality.label + (relayed ? " · aktarma sunucusu" : ""))
                .font(.footnote)
                .foregroundStyle(Color.ftTextSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quality.label)
    }
}

enum CallPermissions {
    /// Mikrofon izni (WebRTC kendisi de ister; önce sorarak reddedildiyse aramayı başlatmayız).
    static func microphone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

/// Sohbetten arama başlatma (araç çubuğu ve "Geri ara").
@MainActor
enum CallLauncher {
    static func call(_ chat: ChatViewModel) {
        let manager = CallManager.shared
        guard chat.kind == .partner, let room = chat.room, let other = chat.otherMemberID else { return }
        let name = chat.partnerName
        Task {
            guard await CallPermissions.microphone() else {
                manager.errorMessage = "Arama için mikrofon izni gerekiyor. Ayarlar → FarvaTrack → Mikrofon."
                Haptics.error()
                return
            }
            Haptics.impact()
            await manager.startCall(chatID: room.id, calleeID: other, calleeName: name)
        }
    }
}
