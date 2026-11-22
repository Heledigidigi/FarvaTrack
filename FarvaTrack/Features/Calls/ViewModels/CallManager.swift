import Foundation
import AVFoundation
import Network
import Observation
import FirebaseAuth

// MARK: - Ağ değişimi

/// Wi-Fi ↔ hücresel geçişi gibi ağ değişimleri (yeniden bağlanma için). Testlerde sahte.
protocol NetworkChangeMonitoring: AnyObject {
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
}

final class LiveNetworkMonitor: NetworkChangeMonitoring {
    var onChange: (() -> Void)?
    private var monitor: NWPathMonitor?
    private var lastSignature: String?

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = "\(path.status)|" + path.availableInterfaces.map { "\($0.type)" }.joined(separator: ",")
            DispatchQueue.main.async {
                guard let self else { return }
                defer { self.lastSignature = signature }
                // İlk değer başlangıç durumudur; yalnızca sonraki değişiklikler bildirilir.
                if let last = self.lastSignature, last != signature, path.status == .satisfied { self.onChange?() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "farva.network"))
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        lastSignature = nil
    }
}

// MARK: - Arama yöneticisi

/// İki kişi arasında WebRTC sesli arama (8H). Sinyalleşme Firestore'da, sistem ekranı CallKit,
/// kilitliyken gelen arama PushKit (build ayarıyla). Yalnızca arayan, arama bitince sohbete arama satırı yazar.
@MainActor @Observable
final class CallManager {
    static let shared = CallManager()

    // MARK: Durum
    private(set) var phase: CallPhase = .idle
    private(set) var call: CallDocument?
    private(set) var partnerName = ""
    private(set) var isMuted = false
    private(set) var isSpeakerOn = false
    private(set) var isOnHold = false
    private(set) var quality: CallQuality?
    private(set) var usingRelay = false
    /// Süre göstergesi için (saniyede bir tazelenir).
    private(set) var now = Date()
    var errorMessage: String?

    var direction: CallDirection? {
        guard let call, let userID else { return nil }
        return call.callerID == userID ? .outgoing : .incoming
    }

    var duration: TimeInterval {
        guard let since = phase.connectedSince else { return 0 }
        return max(0, now.timeIntervalSince(since))
    }

    var statusText: String {
        switch phase {
        case .idle: return ""
        case .ringing(.outgoing): return "Çalıyor…"
        case .ringing(.incoming): return "Gelen arama"
        case .connecting: return "Bağlanıyor…"
        case .connected: return isOnHold ? "Beklemede · \(CallFormat.duration(duration))" : CallFormat.duration(duration)
        case .reconnecting: return "Yeniden bağlanıyor…"
        case .ended(let reason):
            switch reason {
            case .declined: return "Arama reddedildi"
            case .busy: return "Hat meşgul"
            case .missed: return "Cevap yok"
            case .failed: return "Bağlantı kurulamadı"
            case .hungUp, .remoteEnded: return "Arama bitti"
            }
        }
    }

    /// Arama ekranı gösterilsin mi.
    var isPresenting: Bool {
        switch phase {
        case .idle: return false
        default: return true
        }
    }

    // MARK: Bağımlılıklar
    @ObservationIgnored private let signaling: CallSignaling
    @ObservationIgnored private let makeEngine: () -> CallMediaEngine
    @ObservationIgnored private let system: CallSystemUI
    @ObservationIgnored private let server: CallServerProviding?
    @ObservationIgnored private let chatSync: ChatSyncing
    @ObservationIgnored private let notifier: ChatNotifying?
    @ObservationIgnored private let audioRouting: CallAudioRouting
    @ObservationIgnored private let network: NetworkChangeMonitoring
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let makeID: () -> String
    @ObservationIgnored private let sleep: (TimeInterval) async throws -> Void
    @ObservationIgnored private let currentUser: () -> (id: String, name: String)?

    // MARK: İç durum
    @ObservationIgnored private var engine: CallMediaEngine?
    @ObservationIgnored private(set) var uuid: UUID?
    @ObservationIgnored private var callSubscription: ChatSubscription?
    @ObservationIgnored private var candidateSubscription: ChatSubscription?
    @ObservationIgnored private var incomingSubscription: ChatSubscription?
    @ObservationIgnored private var watchedChatID: String?
    @ObservationIgnored private var watchedPartnerName = ""
    @ObservationIgnored private var remoteDescriptionReady = false
    @ObservationIgnored private var pendingCandidates: [CallCandidate] = []
    @ObservationIgnored private var appliedAnswerVersion = 0
    @ObservationIgnored private var appliedOfferVersion = 0
    @ObservationIgnored private var currentOfferVersion = 1
    @ObservationIgnored private var timers: [Task<Void, Never>] = []
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    /// Sonlanan aramalar yeniden çalmasın.
    @ObservationIgnored private var handledCallIDs: Set<String> = []
    private var userID: String? { currentUser()?.id }

    init(signaling: CallSignaling = CallSignalingService(),
         makeEngine: @escaping () -> CallMediaEngine = { CallEngines.make() },
         system: CallSystemUI? = nil,
         server: CallServerProviding? = MediaServerClient(),
         chatSync: ChatSyncing = ChatService(),
         notifier: ChatNotifying? = MediaServerClient(),
         audioRouting: CallAudioRouting = LiveCallAudioRouting(),
         network: NetworkChangeMonitoring = LiveNetworkMonitor(),
         clock: @escaping () -> Date = { .now },
         makeID: @escaping () -> String = { UUID().uuidString },
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         currentUser: @escaping () -> (id: String, name: String)? = {
             guard FirebaseBootstrap.isConfigured, let user = Auth.auth().currentUser else { return nil }
             return (user.uid, user.displayName ?? "")
         }) {
        self.signaling = signaling
        self.makeEngine = makeEngine
        // CallKit sağlayıcısı ana aktörde oluşturulur (varsayılan değer ifadesinde değil).
        self.system = system ?? CallKitSystem()
        self.server = server
        self.chatSync = chatSync
        self.notifier = notifier
        self.audioRouting = audioRouting
        self.network = network
        self.clock = clock
        self.makeID = makeID
        self.sleep = sleep
        self.currentUser = currentUser
        self.system.delegate = self
        network.onChange = { [weak self] in self?.networkChanged() }
    }

    // MARK: Gelen aramaları dinleme

    /// Karşılıklı sohbet odası hazır olunca: bu kullanıcıyı arayan çalan aramalar dinlenir (uygulama açıkken).
    func watch(chatID: String?, partnerName: String) {
        watchedPartnerName = partnerName
        guard watchedChatID != chatID else { return }
        incomingSubscription?.cancel()
        incomingSubscription = nil
        watchedChatID = chatID
        guard let chatID, let userID else { return }
        incomingSubscription = signaling.observeIncoming(chatID: chatID, userID: userID) { [weak self] calls in
            self?.handleIncoming(calls)
        }
    }

    func handleIncoming(_ calls: [CallDocument]) {
        for call in calls where call.status == .ringing && !handledCallIDs.contains(call.id) {
            // Eski (çalma süresi geçmiş) kayıtlar çalmaz.
            guard clock().timeIntervalSince(call.createdAt) < CallLimits.ringTimeout + 15 else { continue }
            if phase.isActive {
                if self.call?.id != call.id {
                    handledCallIDs.insert(call.id)
                    Task { try? await signaling.setStatus(.busy, chatID: call.chatID, callID: call.id, by: call.calleeID, at: clock()) }
                }
                continue
            }
            Task { await presentIncoming(call, callerName: watchedPartnerName, alreadyReported: false) }
        }
    }

    /// PushKit: uygulama kapalı / kilitliyken gelen arama. iOS hemen CallKit'e bildirilmesini ister.
    func handleVoIPPush(callID: String, chatID: String, callerName: String) async {
        let uuid = UUID()
        try? await system.reportIncoming(uuid: uuid, callerName: callerName)
        guard !callID.isEmpty, !chatID.isEmpty, !phase.isActive, !handledCallIDs.contains(callID),
              let call = try? await signaling.fetchCall(chatID: chatID, callID: callID), call.status == .ringing else {
            system.reportEnded(uuid: uuid, reason: .missed)
            return
        }
        self.uuid = uuid
        await presentIncoming(call, callerName: callerName, alreadyReported: true)
    }

    private func presentIncoming(_ call: CallDocument, callerName: String, alreadyReported: Bool) async {
        guard !phase.isActive, !handledCallIDs.contains(call.id) else { return }
        handledCallIDs.insert(call.id)
        reset(keepingUUID: alreadyReported)
        self.call = call
        partnerName = callerName.isEmpty ? "FarvaTrack" : callerName
        phase = .ringing(.incoming)
        if !alreadyReported {
            let uuid = UUID()
            self.uuid = uuid
            do {
                try await system.reportIncoming(uuid: uuid, callerName: partnerName)
            } catch {
                // Rahatsız Etmeyin vb. nedenlerle sistem reddettiyse arama cevapsız kalır.
                phase = .idle
                self.call = nil
                return
            }
        }
        observeCall(call)
        schedule(after: CallLimits.ringTimeout) { [weak self] in self?.handleRingTimeout(callID: call.id) }
    }

    // MARK: Giden arama

    func startCall(chatID: String, calleeID: String, calleeName: String) async {
        guard !phase.isActive, let user = currentUser() else { return }
        reset(keepingUUID: false)
        let callID = makeID()
        let uuid = UUID()
        self.uuid = uuid
        partnerName = calleeName
        phase = .ringing(.outgoing)
        handledCallIDs.insert(callID)
        var document = CallDocument(id: callID, chatID: chatID, callerID: user.id, calleeID: calleeID, status: .ringing,
                                    offer: nil, answer: nil, offerVersion: 1, answerVersion: 0, createdAt: clock(),
                                    answeredAt: nil, endedAt: nil, endedBy: nil)
        call = document
        do {
            try await system.startOutgoing(uuid: uuid, calleeName: calleeName)
            let engine = try await prepareEngine()
            let offer = try await engine.makeOffer(iceRestart: false)
            document.offer = offer
            call = document
            try await signaling.createCall(document)
            observeCall(document)
            Task { [server] in try? await server?.ring(chatID: chatID, callID: callID) }
            schedule(after: CallLimits.ringTimeout) { [weak self] in self?.handleRingTimeout(callID: callID) }
        } catch {
            errorMessage = AppError.map(error).errorDescription
            await finish(.failed, writeStatus: false)
        }
    }

    // MARK: Cevap / ret / kapatma (uygulama içi düğmeler CallKit üzerinden geçer)

    func answer() {
        guard case .ringing(.incoming) = phase, let uuid else { return }
        Task { await callSystemDidAnswer(uuid) }
    }

    func hangUp() {
        guard phase.isActive, let uuid else { return }
        system.requestEnd(uuid: uuid)
    }

    func toggleMute() {
        guard let uuid, phase.isActive else { return }
        system.requestMute(!isMuted, uuid: uuid)
    }

    func toggleHold() {
        guard let uuid, phase.connectedSince != nil else { return }
        system.requestHold(!isOnHold, uuid: uuid)
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        audioRouting.setSpeaker(isSpeakerOn)
    }

    func tick() {
        now = clock()
    }

    // MARK: Sinyalleşme

    private func observeCall(_ call: CallDocument) {
        guard let userID else { return }
        callSubscription?.cancel()
        callSubscription = signaling.observeCall(chatID: call.chatID, callID: call.id) { [weak self] document in
            guard let self, let document else { return }
            Task { await self.handleRemote(document) }
        }
        candidateSubscription?.cancel()
        candidateSubscription = signaling.observeCandidates(chatID: call.chatID, callID: call.id, excluding: userID) { [weak self] candidates in
            guard let self else { return }
            Task { await self.receive(candidates) }
        }
    }

    func handleRemote(_ document: CallDocument) async {
        guard let current = call, current.id == document.id, let userID, phase.isActive else { return }
        call = document

        if document.status.isFinal {
            // Karşı taraf bitirdi / reddetti / meşgul.
            let reason: CallEndReason
            switch document.status {
            case .declined: reason = .declined
            case .busy: reason = .busy
            case .missed: reason = .missed
            case .failed: reason = .failed
            default: reason = phase.connectedSince == nil ? .missed : .remoteEnded
            }
            if document.endedBy != userID {
                if let uuid { system.reportEnded(uuid: uuid, reason: reason) }
                await finish(reason, writeStatus: false)
            }
            return
        }

        if document.callerID == userID {
            // Arayan: yeni yanıt geldiyse uygula.
            if let answer = document.answer, document.answerVersion > appliedAnswerVersion, let engine {
                appliedAnswerVersion = document.answerVersion
                if case .ringing = phase {
                    phase = CallStateMachine.next(phase, .remoteStatus(.accepted))
                    if let uuid { system.reportOutgoingConnecting(uuid: uuid) }
                    schedule(after: CallLimits.connectTimeout) { [weak self] in self?.handleConnectTimeout(callID: document.id) }
                }
                do {
                    try await engine.setRemoteAnswer(answer)
                    remoteDescriptionReady = true
                    await flushCandidates()
                } catch {
                    errorMessage = AppError.map(error).errorDescription
                }
            }
        } else if document.answerVersion > 0, document.offerVersion > appliedOfferVersion, let offer = document.offer, let engine {
            // Aranan: arayan ağ değişince ICE'ı yeniden başlattı; yeni teklife yanıt verilir.
            appliedOfferVersion = document.offerVersion
            do {
                let answer = try await engine.makeAnswer(for: offer)
                try await signaling.answer(answer, version: document.offerVersion, chatID: document.chatID, callID: document.id, at: clock())
            } catch {
                errorMessage = AppError.map(error).errorDescription
            }
        }
    }

    func receive(_ candidates: [CallCandidate]) async {
        guard phase.isActive else { return }
        pendingCandidates.append(contentsOf: candidates)
        if remoteDescriptionReady { await flushCandidates() }
    }

    private func flushCandidates() async {
        guard let engine else { return }
        let candidates = pendingCandidates
        pendingCandidates = []
        for candidate in candidates { await engine.addRemoteCandidate(candidate) }
    }

    private func prepareEngine() async throws -> CallMediaEngine {
        let servers = (try? await server?.iceServers()) ?? IceServer.fallback
        let engine = makeEngine()
        engine.onLocalCandidate = { [weak self] candidate in self?.sendLocal(candidate) }
        engine.onConnectionChange = { [weak self] state in self?.mediaChanged(state) }
        try engine.prepare(iceServers: servers)
        engine.setMuted(isMuted)
        self.engine = engine
        network.start()
        return engine
    }

    private func sendLocal(_ candidate: LocalIceCandidate) {
        guard let call, let userID else { return }
        let item = CallCandidate(id: makeID(), from: userID, candidate: candidate.candidate, sdpMid: candidate.sdpMid,
                                 sdpMLineIndex: candidate.sdpMLineIndex, offerVersion: currentOfferVersion)
        Task { try? await signaling.addCandidate(item, chatID: call.chatID, callID: call.id) }
    }

    // MARK: Medya bağlantısı ve yeniden bağlanma

    func mediaChanged(_ state: CallMediaConnection) {
        switch state {
        case .connected:
            guard phase.isActive else { return }
            let wasConnected = phase.connectedSince != nil
            phase = CallStateMachine.next(phase, .mediaConnected(clock()))
            restartTask?.cancel()
            restartTask = nil
            if !wasConnected, let uuid {
                system.reportConnected(uuid: uuid)
                startStats()
            }
        case .disconnected:
            guard phase.connectedSince != nil else { return }
            phase = CallStateMachine.next(phase, .mediaInterrupted)
            // Kısa kopmalar kendiliğinden düzelir; düzelmezse ICE yeniden başlatılır.
            scheduleRestart(after: 2)
        case .failed:
            if phase.connectedSince != nil {
                phase = CallStateMachine.next(phase, .mediaInterrupted)
                scheduleRestart(after: 0)
            }
        case .connecting, .closed:
            break
        }
    }

    /// Ağ değişti (Wi-Fi ↔ hücresel): bağlantı sürerken arayan ICE'ı yeniden başlatır.
    func networkChanged() {
        guard phase.connectedSince != nil || phase == .connecting else { return }
        scheduleRestart(after: 0)
    }

    private func scheduleRestart(after delay: TimeInterval) {
        guard restartTask == nil, let call else { return }
        let callID = call.id
        restartTask = Task { [weak self] in
            guard let self else { return }
            if delay > 0 { try? await self.sleep(delay) }
            guard !Task.isCancelled, self.call?.id == callID else { return }
            await self.restartIce()
            // Yeniden bağlanma süresi dolarsa arama biter.
            try? await self.sleep(CallLimits.reconnectTimeout)
            guard !Task.isCancelled, self.call?.id == callID else { return }
            if case .reconnecting = self.phase { await self.failConnection() }
            self.restartTask = nil
        }
    }

    func restartIce() async {
        guard let call, let userID, call.callerID == userID, let engine else { return }
        do {
            currentOfferVersion = call.offerVersion + 1
            let offer = try await engine.makeOffer(iceRestart: true)
            try await signaling.updateOffer(offer, version: currentOfferVersion, chatID: call.chatID, callID: call.id)
            self.call?.offer = offer
            self.call?.offerVersion = currentOfferVersion
        } catch {
            errorMessage = AppError.map(error).errorDescription
        }
    }

    private func failConnection() async {
        if let uuid { system.reportEnded(uuid: uuid, reason: .failed) }
        await finish(.failed, writeStatus: true)
    }

    private func startStats() {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.phase.isActive {
                if let engine = self.engine {
                    let sample = await engine.stats()
                    self.quality = CallQuality.evaluate(sample)
                    self.usingRelay = sample.usingRelay
                }
                self.tick()
                try? await self.sleep(CallLimits.statsInterval)
            }
        }
    }

    // MARK: Zaman aşımları

    func handleRingTimeout(callID: String) {
        guard call?.id == callID, case .ringing = phase else { return }
        if let uuid { system.reportEnded(uuid: uuid, reason: .missed) }
        Task { await finish(.missed, writeStatus: direction == .outgoing) }
    }

    func handleConnectTimeout(callID: String) {
        guard call?.id == callID, phase == .connecting else { return }
        Task { await failConnection() }
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let task = Task { [weak self] in
            guard let self else { return }
            try? await self.sleep(delay)
            guard !Task.isCancelled else { return }
            action()
        }
        timers.append(task)
    }

    // MARK: Bitiş

    /// Aramayı kapatır; `writeStatus` ise son durum sunucuya yazılır. Arayan sohbete arama satırını yazar.
    func finish(_ reason: CallEndReason, writeStatus: Bool) async {
        guard phase.isActive, let call, let userID else { return }
        let connectedSince = phase.connectedSince
        let duration = connectedSince.map { max(0, clock().timeIntervalSince($0)) } ?? 0
        phase = .ended(reason)
        cleanUp()

        if writeStatus {
            let status: CallSignalStatus
            switch reason {
            case .declined: status = .declined
            case .busy: status = .busy
            case .missed: status = .missed
            case .failed: status = .failed
            case .hungUp, .remoteEnded: status = connectedSince == nil ? (call.callerID == userID ? .missed : .declined) : .ended
            }
            try? await signaling.setStatus(status, chatID: call.chatID, callID: call.id, by: userID, at: clock())
        }

        if call.callerID == userID {
            let info = ChatCallInfo(callID: call.id, outcome: ChatCallInfo.outcome(for: reason, connected: connectedSince != nil),
                                    duration: duration.rounded())
            let message = ChatMessageDTO(id: "call-\(call.id)", senderID: userID, type: .call, text: "",
                                         createdAt: call.createdAt, call: info)
            if (try? await chatSync.sendMessage(message, chatID: call.chatID)) != nil {
                try? await notifier?.notify(chatID: call.chatID, messageID: message.id)
            }
        }

        // Kısa süre "Arama bitti" gösterilir, sonra ekran kapanır.
        let endedCallID = call.id
        schedule(after: 1.5) { [weak self] in
            guard let self, self.call?.id == endedCallID, case .ended = self.phase else { return }
            self.phase = .idle
            self.call = nil
        }
    }

    private func cleanUp() {
        timers.forEach { $0.cancel() }
        timers = []
        restartTask?.cancel()
        restartTask = nil
        statsTask?.cancel()
        statsTask = nil
        callSubscription?.cancel()
        callSubscription = nil
        candidateSubscription?.cancel()
        candidateSubscription = nil
        engine?.close()
        engine = nil
        network.stop()
        if isSpeakerOn { audioRouting.setSpeaker(false) }
    }

    private func reset(keepingUUID: Bool) {
        cleanUp()
        if !keepingUUID { uuid = nil }
        call = nil
        isMuted = false
        isSpeakerOn = false
        isOnHold = false
        quality = nil
        usingRelay = false
        remoteDescriptionReady = false
        pendingCandidates = []
        appliedAnswerVersion = 0
        appliedOfferVersion = 0
        currentOfferVersion = 1
        errorMessage = nil
    }

    /// Oturum kapanınca.
    func stop() {
        if phase.isActive, let uuid { system.reportEnded(uuid: uuid, reason: .hungUp) }
        cleanUp()
        incomingSubscription?.cancel()
        incomingSubscription = nil
        watchedChatID = nil
        phase = .idle
        call = nil
    }
}

// MARK: - CallKit eylemleri

extension CallManager: CallSystemDelegate {
    func callSystemDidAnswer(_ uuid: UUID) async {
        guard uuid == self.uuid, case .ringing(.incoming) = phase, let call, let offer = call.offer else { return }
        phase = CallStateMachine.next(phase, .answered)
        do {
            let engine = try await prepareEngine()
            appliedOfferVersion = call.offerVersion
            let answer = try await engine.makeAnswer(for: offer)
            remoteDescriptionReady = true
            try await signaling.answer(answer, version: call.offerVersion, chatID: call.chatID, callID: call.id, at: clock())
            await flushCandidates()
            schedule(after: CallLimits.connectTimeout) { [weak self] in self?.handleConnectTimeout(callID: call.id) }
        } catch {
            errorMessage = AppError.map(error).errorDescription
            system.reportEnded(uuid: uuid, reason: .failed)
            await finish(.failed, writeStatus: true)
        }
    }

    func callSystemDidEnd(_ uuid: UUID) {
        guard uuid == self.uuid, phase.isActive else { return }
        let reason = CallStateMachine.next(phase, .hangUp)
        guard case .ended(let endReason) = reason else { return }
        Task { await finish(endReason, writeStatus: true) }
    }

    func callSystemDidSetMuted(_ muted: Bool, uuid: UUID) {
        guard uuid == self.uuid else { return }
        isMuted = muted
        engine?.setMuted(muted)
    }

    func callSystemDidSetHeld(_ held: Bool, uuid: UUID) {
        guard uuid == self.uuid else { return }
        isOnHold = held
        engine?.setOnHold(held)
    }

    func callSystemDidActivateAudio(_ session: AVAudioSession) {
        engine?.audioSessionActivated(session)
        if isSpeakerOn { audioRouting.setSpeaker(true) }
    }

    func callSystemDidDeactivateAudio(_ session: AVAudioSession) {
        engine?.audioSessionDeactivated(session)
    }

    func callSystemDidReset() {
        guard phase.isActive else { return }
        Task { await finish(.failed, writeStatus: true) }
    }
}
