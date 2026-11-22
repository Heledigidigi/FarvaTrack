import Foundation
import AVFoundation
#if canImport(WebRTC)
import WebRTC
#endif

// MARK: - Sözleşme

enum CallMediaConnection: Equatable {
    case connecting, connected, disconnected, failed, closed
}

struct LocalIceCandidate: Equatable {
    var candidate: String
    var sdpMid: String?
    var sdpMLineIndex: Int32
}

/// WebRTC eş bağlantısı (yalnızca ses). Testlerde sahte uygulamayla değiştirilir.
protocol CallMediaEngine: AnyObject {
    /// Yerel ICE adayı bulundu (ana iş parçacığında çağrılır).
    var onLocalCandidate: ((LocalIceCandidate) -> Void)? { get set }
    var onConnectionChange: ((CallMediaConnection) -> Void)? { get set }

    func prepare(iceServers: [IceServer]) throws
    func makeOffer(iceRestart: Bool) async throws -> SessionDescription
    func makeAnswer(for offer: SessionDescription) async throws -> SessionDescription
    func setRemoteAnswer(_ answer: SessionDescription) async throws
    func addRemoteCandidate(_ candidate: CallCandidate) async
    func setMuted(_ muted: Bool)
    /// Beklet: mikrofon ve karşı tarafın sesi kapanır.
    func setOnHold(_ onHold: Bool)
    func audioSessionActivated(_ session: AVAudioSession)
    func audioSessionDeactivated(_ session: AVAudioSession)
    func stats() async -> CallStatsSample
    func close()
}

/// Hoparlör / ahize geçişi. Bluetooth kulaklık bağlıysa iOS sesi oraya yönlendirir (CallKit ekranından da seçilir).
protocol CallAudioRouting: AnyObject {
    func setSpeaker(_ on: Bool)
}

final class LiveCallAudioRouting: CallAudioRouting {
    func setSpeaker(_ on: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.overrideOutputAudioPort(on ? .speaker : .none)
    }
}

/// WebRTC istatistik raporu (getStats) → kalite örneği. Saf, testli.
enum CallStatsParser {
    /// İstatistik raporundan gidiş-dönüş, kayıp ve titreşim.
    static func sample(from entries: [(id: String, type: String, values: [String: NSObject])]) -> CallStatsSample {
        var sample = CallStatsSample()
        var localRelay = Set<String>()
        for entry in entries where entry.type == "local-candidate" {
            if (entry.values["candidateType"] as? String) == "relay" { localRelay.insert(entry.id) }
        }
        for entry in entries {
            let values = entry.values
            switch entry.type {
            case "candidate-pair":
                guard (values["state"] as? String) == "succeeded", (values["nominated"] as? NSNumber)?.boolValue ?? true else { continue }
                if let rtt = (values["currentRoundTripTime"] as? NSNumber)?.doubleValue { sample.roundTripTime = rtt }
                if let local = values["localCandidateId"] as? String, localRelay.contains(local) { sample.usingRelay = true }
            case "remote-inbound-rtp":
                if let loss = (values["fractionLost"] as? NSNumber)?.doubleValue { sample.packetLoss = max(sample.packetLoss ?? 0, loss) }
                if sample.roundTripTime == nil, let rtt = (values["roundTripTime"] as? NSNumber)?.doubleValue { sample.roundTripTime = rtt }
            case "inbound-rtp":
                if let jitter = (values["jitter"] as? NSNumber)?.doubleValue { sample.jitter = jitter }
                if let lost = (values["packetsLost"] as? NSNumber)?.doubleValue,
                   let received = (values["packetsReceived"] as? NSNumber)?.doubleValue, lost + received > 0 {
                    sample.packetLoss = max(sample.packetLoss ?? 0, lost / (lost + received))
                }
            default:
                continue
            }
        }
        return sample
    }

}

#if canImport(WebRTC)

// MARK: - WebRTC

/// stasel/WebRTC ile tek ses izli eş bağlantısı. Opus (64 kbps, FEC), yankı/gürültü bastırma ve otomatik kazanç açık.
/// Ses oturumu CallKit'e devredilir: `useManualAudio` açık, CallKit oturumu etkinleştirince ses başlar.
final class WebRTCEngine: NSObject, CallMediaEngine {
    var onLocalCandidate: ((LocalIceCandidate) -> Void)?
    var onConnectionChange: ((CallMediaConnection) -> Void)?

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(),
                                        decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    private var peerConnection: RTCPeerConnection?
    private var audioTrack: RTCAudioTrack?
    private var isMuted = false
    private var isOnHold = false

    override init() {
        super.init()
        let session = RTCAudioSession.sharedInstance()
        session.useManualAudio = true
        session.isAudioEnabled = false
    }

    func prepare(iceServers: [IceServer]) throws {
        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        configuration.sdpSemantics = .unifiedPlan
        // Ağ değişince yeni adaylar sürekli toplanır (Wi-Fi ↔ hücresel geçişinde ICE yeniden başlatma için).
        configuration.continualGatheringPolicy = .gatherContinually
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.tcpCandidatePolicy = .enabled

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        let connection: RTCPeerConnection? = Self.factory.peerConnection(with: configuration, constraints: constraints, delegate: self)
        guard let connection else { throw AppError.unknown("Arama bağlantısı oluşturulamadı.") }

        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: [
            "googEchoCancellation": "true",
            "googNoiseSuppression": "true",
            "googAutoGainControl": "true",
            "googHighpassFilter": "true"
        ], optionalConstraints: nil)
        let source = Self.factory.audioSource(with: audioConstraints)
        let track = Self.factory.audioTrack(with: source, trackId: "farva-audio")
        connection.add(track, streamIds: ["farva-stream"])
        audioTrack = track
        peerConnection = connection
        configureAudioSession()
    }

    private func configureAudioSession() {
        let session = RTCAudioSession.sharedInstance()
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
        configuration.categoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
        session.lockForConfiguration()
        try? session.setConfiguration(configuration)
        session.unlockForConfiguration()
    }

    private var mediaConstraints: RTCMediaConstraints {
        RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "false"], optionalConstraints: nil)
    }

    func makeOffer(iceRestart: Bool) async throws -> SessionDescription {
        guard let peerConnection else { throw AppError.unknown("Arama hazır değil.") }
        var mandatory = ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "false"]
        if iceRestart { mandatory["IceRestart"] = "true" }
        let constraints = RTCMediaConstraints(mandatoryConstraints: mandatory, optionalConstraints: nil)
        let raw: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: constraints) { description, error in
                if let description { continuation.resume(returning: description) } else {
                    continuation.resume(throwing: error ?? AppError.unknown("Teklif oluşturulamadı."))
                }
            }
        }
        let tuned = RTCSessionDescription(type: .offer, sdp: CallAudioTuning.tune(raw.sdp))
        try await setLocal(tuned)
        return SessionDescription(kind: .offer, sdp: tuned.sdp)
    }

    func makeAnswer(for offer: SessionDescription) async throws -> SessionDescription {
        guard let peerConnection else { throw AppError.unknown("Arama hazır değil.") }
        try await setRemote(RTCSessionDescription(type: .offer, sdp: offer.sdp))
        let raw: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            peerConnection.answer(for: mediaConstraints) { description, error in
                if let description { continuation.resume(returning: description) } else {
                    continuation.resume(throwing: error ?? AppError.unknown("Yanıt oluşturulamadı."))
                }
            }
        }
        let tuned = RTCSessionDescription(type: .answer, sdp: CallAudioTuning.tune(raw.sdp))
        try await setLocal(tuned)
        return SessionDescription(kind: .answer, sdp: tuned.sdp)
    }

    func setRemoteAnswer(_ answer: SessionDescription) async throws {
        try await setRemote(RTCSessionDescription(type: .answer, sdp: answer.sdp))
    }

    private func setLocal(_ description: RTCSessionDescription) async throws {
        guard let peerConnection else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(description) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private func setRemote(_ description: RTCSessionDescription) async throws {
        guard let peerConnection else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(description) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func addRemoteCandidate(_ candidate: CallCandidate) async {
        guard let peerConnection else { return }
        let ice = RTCIceCandidate(sdp: candidate.candidate, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            peerConnection.add(ice) { _ in continuation.resume() }
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        audioTrack?.isEnabled = !(isMuted || isOnHold)
    }

    func setOnHold(_ onHold: Bool) {
        isOnHold = onHold
        audioTrack?.isEnabled = !(isMuted || isOnHold)
        peerConnection?.transceivers.forEach { transceiver in
            transceiver.receiver.track?.isEnabled = !onHold
        }
    }

    func audioSessionActivated(_ session: AVAudioSession) {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.audioSessionDidActivate(session)
        rtc.isAudioEnabled = true
    }

    func audioSessionDeactivated(_ session: AVAudioSession) {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.audioSessionDidDeactivate(session)
        rtc.isAudioEnabled = false
    }

    func stats() async -> CallStatsSample {
        guard let peerConnection else { return CallStatsSample() }
        let report: RTCStatisticsReport = await withCheckedContinuation { continuation in
            peerConnection.statistics { continuation.resume(returning: $0) }
        }
        return CallStatsParser.sample(from: report.statistics.values.map { (id: $0.id, type: $0.type, values: $0.values) })
    }

    func close() {
        peerConnection?.close()
        peerConnection = nil
        audioTrack = nil
    }

    private func emit(_ state: CallMediaConnection) {
        DispatchQueue.main.async { [weak self] in self?.onConnectionChange?(state) }
    }
}

extension WebRTCEngine: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed: emit(.connected)
        case .disconnected: emit(.disconnected)
        case .failed: emit(.failed)
        case .closed: emit(.closed)
        case .new, .checking: emit(.connecting)
        default: break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let local = LocalIceCandidate(candidate: candidate.sdp, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex)
        DispatchQueue.main.async { [weak self] in self?.onLocalCandidate?(local) }
    }
}

#endif

/// WebRTC paketi yoksa (yalnızca güvenlik ağı): arama başlatılamaz, uygulama çökmez.
final class UnavailableCallEngine: CallMediaEngine {
    var onLocalCandidate: ((LocalIceCandidate) -> Void)?
    var onConnectionChange: ((CallMediaConnection) -> Void)?
    private let error = AppError.unknown("Sesli arama bu derlemede desteklenmiyor.")
    func prepare(iceServers: [IceServer]) throws { throw error }
    func makeOffer(iceRestart: Bool) async throws -> SessionDescription { throw error }
    func makeAnswer(for offer: SessionDescription) async throws -> SessionDescription { throw error }
    func setRemoteAnswer(_ answer: SessionDescription) async throws { throw error }
    func addRemoteCandidate(_ candidate: CallCandidate) async {}
    func setMuted(_ muted: Bool) {}
    func setOnHold(_ onHold: Bool) {}
    func audioSessionActivated(_ session: AVAudioSession) {}
    func audioSessionDeactivated(_ session: AVAudioSession) {}
    func stats() async -> CallStatsSample { CallStatsSample() }
    func close() {}
}

enum CallEngines {
    static func make() -> CallMediaEngine {
        #if canImport(WebRTC)
        return WebRTCEngine()
        #else
        return UnavailableCallEngine()
        #endif
    }
}
