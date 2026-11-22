import Foundation
import AVFoundation
import CallKit
import PushKit

// MARK: - Sistem arama ekranı (CallKit)

/// CallKit'ten gelen kullanıcı eylemleri (sistem ekranı, kilit ekranı, kulaklık düğmesi).
@MainActor
protocol CallSystemDelegate: AnyObject {
    func callSystemDidAnswer(_ uuid: UUID) async
    func callSystemDidEnd(_ uuid: UUID)
    func callSystemDidSetMuted(_ muted: Bool, uuid: UUID)
    func callSystemDidSetHeld(_ held: Bool, uuid: UUID)
    func callSystemDidActivateAudio(_ session: AVAudioSession)
    func callSystemDidDeactivateAudio(_ session: AVAudioSession)
    func callSystemDidReset()
}

/// Testlerde sahte uygulamayla değiştirilir.
@MainActor
protocol CallSystemUI: AnyObject {
    var delegate: CallSystemDelegate? { get set }
    func reportIncoming(uuid: UUID, callerName: String) async throws
    func startOutgoing(uuid: UUID, calleeName: String) async throws
    func reportOutgoingConnecting(uuid: UUID)
    func reportConnected(uuid: UUID)
    /// Arama başka yerde bitti (karşı taraf kapattı, cevapsız…).
    func reportEnded(uuid: UUID, reason: CallEndReason)
    /// Uygulama içinden: sistem ekranıyla eşzamanlı kalsın diye işlem (transaction) olarak istenir.
    func requestEnd(uuid: UUID)
    func requestMute(_ muted: Bool, uuid: UUID)
    func requestHold(_ held: Bool, uuid: UUID)
}

@MainActor
final class CallKitSystem: NSObject, CallSystemUI {
    weak var delegate: CallSystemDelegate?
    private let provider: CXProvider
    private let controller = CXCallController()

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = true
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    private func update(name: String) -> CXCallUpdate {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: name)
        update.localizedCallerName = name
        update.hasVideo = false
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        return update
    }

    func reportIncoming(uuid: UUID, callerName: String) async throws {
        try await provider.reportNewIncomingCall(with: uuid, update: update(name: callerName))
    }

    func startOutgoing(uuid: UUID, calleeName: String) async throws {
        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: calleeName))
        action.isVideo = false
        try await controller.request(CXTransaction(action: action))
        provider.reportCall(with: uuid, updated: update(name: calleeName))
    }

    func reportOutgoingConnecting(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: .now)
    }

    func reportConnected(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, connectedAt: .now)
    }

    func reportEnded(uuid: UUID, reason: CallEndReason) {
        let mapped: CXCallEndedReason
        switch reason {
        case .missed, .declined, .busy: mapped = .unanswered
        case .failed: mapped = .failed
        case .remoteEnded, .hungUp: mapped = .remoteEnded
        }
        provider.reportCall(with: uuid, endedAt: .now, reason: mapped)
    }

    func requestEnd(uuid: UUID) {
        controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { _ in }
    }

    func requestMute(_ muted: Bool, uuid: UUID) {
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: muted))) { _ in }
    }

    func requestHold(_ held: Bool, uuid: UUID) {
        controller.request(CXTransaction(action: CXSetHeldCallAction(call: uuid, onHold: held))) { _ in }
    }
}

extension CallKitSystem: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in self.delegate?.callSystemDidReset() }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let uuid = action.callUUID
        Task { @MainActor in
            await self.delegate?.callSystemDidAnswer(uuid)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let uuid = action.callUUID
        Task { @MainActor in
            self.delegate?.callSystemDidEnd(uuid)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        let uuid = action.callUUID
        let muted = action.isMuted
        Task { @MainActor in
            self.delegate?.callSystemDidSetMuted(muted, uuid: uuid)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        let uuid = action.callUUID
        let held = action.isOnHold
        Task { @MainActor in
            self.delegate?.callSystemDidSetHeld(held, uuid: uuid)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Task { @MainActor in self.delegate?.callSystemDidActivateAudio(audioSession) }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in self.delegate?.callSystemDidDeactivateAudio(audioSession) }
    }
}

// MARK: - VoIP push (PushKit)

/// Kilit ekranında çalan arama için VoIP push kaydı. `VOIP_PUSH` build ayarı (Info.plist `FTVoIPPushEnabled`)
/// YES değilse hiç kaydolunmaz: ücretsiz imzada uygulama yalnızca açıkken arama alır.
final class VoIPPushRegistrar: NSObject, PKPushRegistryDelegate {
    static let shared = VoIPPushRegistrar()

    static var isEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "FTVoIPPushEnabled") as? String)?.uppercased() == "YES"
    }

    private var registry: PKPushRegistry?

    func start() {
        guard Self.isEnabled, registry == nil else { return }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        Task { await PushManager.shared.voipTokenReceived(token) }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        Task { await PushManager.shared.voipTokenReceived(nil) }
    }

    /// iOS kuralı: her VoIP push'ta hemen CallKit'e gelen arama bildirilmeli.
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        let data = payload.dictionaryPayload
        let callID = data["callId"] as? String ?? ""
        let chatID = data["chatId"] as? String ?? ""
        let callerName = data["callerName"] as? String ?? "FarvaTrack"
        Task { @MainActor in
            await CallManager.shared.handleVoIPPush(callID: callID, chatID: chatID, callerName: callerName)
            completion()
        }
    }
}
