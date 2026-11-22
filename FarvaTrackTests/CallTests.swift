import XCTest
import AVFoundation
@testable import FarvaTrack

// MARK: - Saf mantık

final class CallModelTests: XCTestCase {
    private let sdp = [
        "v=0",
        "m=audio 9 UDP/TLS/RTP/SAVPF 103 111 9 0",
        "a=rtpmap:103 ISAC/16000",
        "a=rtpmap:111 opus/48000/2",
        "a=fmtp:111 minptime=10;useinbandfec=1;maxaveragebitrate=20000",
        "a=rtpmap:9 G722/8000",
        ""
    ].joined(separator: "\r\n")

    func testOpusIsPreferredWithHighBitrate() {
        let tuned = CallAudioTuning.tune(sdp)
        XCTAssertTrue(tuned.contains("m=audio 9 UDP/TLS/RTP/SAVPF 111 103 9 0"), "Opus en önde")
        let fmtp = tuned.components(separatedBy: "\r\n").first { $0.hasPrefix("a=fmtp:111 ") } ?? ""
        XCTAssertTrue(fmtp.contains("maxaveragebitrate=64000"))
        XCTAssertFalse(fmtp.contains("maxaveragebitrate=20000"), "eski değer değişir")
        XCTAssertTrue(fmtp.contains("useinbandfec=1"))
        XCTAssertTrue(fmtp.contains("usedtx=0"))
        XCTAssertEqual(fmtp.components(separatedBy: "minptime").count, 2, "parametre tekrarlanmaz")
        XCTAssertEqual(CallAudioTuning.tune(tuned), tuned, "iki kez uygulamak aynı sonucu verir")
        XCTAssertTrue(tuned.hasSuffix("\r\n"), "satır sonları korunur")
    }

    func testFmtpIsAddedWhenMissingAndNonOpusSdpUntouched() {
        let bare = "m=audio 9 RTP/SAVPF 0 111\na=rtpmap:111 opus/48000/2\n"
        let tuned = CallAudioTuning.tune(bare)
        XCTAssertTrue(tuned.contains("a=rtpmap:111 opus/48000/2\na=fmtp:111 minptime=10;useinbandfec=1;usedtx=0;stereo=0;maxaveragebitrate=64000"))
        XCTAssertTrue(tuned.hasPrefix("m=audio 9 RTP/SAVPF 111 0"))
        let pcmu = "m=audio 9 RTP/SAVPF 0\na=rtpmap:0 PCMU/8000\n"
        XCTAssertEqual(CallAudioTuning.tune(pcmu), pcmu)
    }

    func testStateMachine() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(CallStateMachine.next(.ringing(.outgoing), .remoteStatus(.accepted)), .connecting)
        XCTAssertEqual(CallStateMachine.next(.ringing(.outgoing), .remoteStatus(.declined)), .ended(.declined))
        XCTAssertEqual(CallStateMachine.next(.ringing(.outgoing), .remoteStatus(.busy)), .ended(.busy))
        XCTAssertEqual(CallStateMachine.next(.ringing(.outgoing), .ringTimeout), .ended(.missed))
        XCTAssertEqual(CallStateMachine.next(.ringing(.outgoing), .hangUp), .ended(.missed), "çalarken vazgeçmek cevapsızdır")
        XCTAssertEqual(CallStateMachine.next(.ringing(.incoming), .hangUp), .ended(.declined))
        XCTAssertEqual(CallStateMachine.next(.ringing(.incoming), .answered), .connecting)
        XCTAssertEqual(CallStateMachine.next(.connecting, .mediaConnected(now)), .connected(since: now))
        XCTAssertEqual(CallStateMachine.next(.connected(since: now), .mediaInterrupted), .reconnecting(since: now))
        XCTAssertEqual(CallStateMachine.next(.reconnecting(since: now), .mediaConnected(now.addingTimeInterval(9))), .connected(since: now),
                       "süre yeniden bağlanmada sıfırlanmaz")
        XCTAssertEqual(CallStateMachine.next(.reconnecting(since: now), .connectFailed), .ended(.failed))
        XCTAssertEqual(CallStateMachine.next(.connected(since: now), .hangUp), .ended(.hungUp))
        XCTAssertEqual(CallStateMachine.next(.connected(since: now), .remoteStatus(.ended)), .ended(.remoteEnded))
        XCTAssertEqual(CallStateMachine.next(.idle, .hangUp), .idle)
        XCTAssertEqual(CallStateMachine.next(.ended(.missed), .mediaConnected(now)), .ended(.missed))
    }

    func testQualityAndStats() {
        XCTAssertEqual(CallQuality.evaluate(CallStatsSample(roundTripTime: 0.08, packetLoss: 0.005, jitter: 0.01)), .good)
        XCTAssertEqual(CallQuality.evaluate(CallStatsSample(roundTripTime: 0.35, packetLoss: 0, jitter: 0)), .fair)
        XCTAssertEqual(CallQuality.evaluate(CallStatsSample(roundTripTime: 0.1, packetLoss: 0.12, jitter: 0)), .poor)
        XCTAssertEqual(CallQuality.evaluate(CallStatsSample()), .good)
        XCTAssertEqual(CallQuality.poor.bars, 1)

        let sample = CallStatsParser.sample(from: [
            (id: "L1", type: "local-candidate", values: ["candidateType": "relay" as NSString]),
            (id: "P1", type: "candidate-pair", values: ["state": "succeeded" as NSString, "nominated": NSNumber(value: true),
                                                         "currentRoundTripTime": NSNumber(value: 0.12), "localCandidateId": "L1" as NSString]),
            (id: "R1", type: "inbound-rtp", values: ["jitter": NSNumber(value: 0.02), "packetsLost": NSNumber(value: 5),
                                                     "packetsReceived": NSNumber(value: 95)]),
            (id: "P2", type: "candidate-pair", values: ["state": "failed" as NSString, "currentRoundTripTime": NSNumber(value: 9)])
        ])
        XCTAssertEqual(sample.roundTripTime, 0.12)
        XCTAssertEqual(sample.jitter, 0.02)
        XCTAssertEqual(sample.packetLoss ?? 0, 0.05, accuracy: 0.0001)
        XCTAssertTrue(sample.usingRelay)
    }

    func testCallInfoFormattingAndFields() {
        XCTAssertEqual(CallFormat.duration(7), "0:07")
        XCTAssertEqual(CallFormat.duration(154), "2:34")
        XCTAssertEqual(CallFormat.duration(3725), "1:02:05")
        let answered = ChatCallInfo(callID: "c1", outcome: .answered, duration: 154)
        XCTAssertEqual(CallFormat.summary(answered, isMine: true), "📞 Sesli arama · 2:34")
        let missed = ChatCallInfo(callID: "c2", outcome: .missed, duration: 0)
        XCTAssertEqual(CallFormat.summary(missed, isMine: false), "📞 Cevapsız arama")
        XCTAssertEqual(CallFormat.summary(missed, isMine: true), "📞 Cevaplanmayan arama")
        XCTAssertEqual(ChatCallInfo.outcome(for: .hungUp, connected: true), .answered)
        XCTAssertEqual(ChatCallInfo.outcome(for: .declined, connected: false), .declined)
        XCTAssertEqual(ChatCallInfo.outcome(for: .hungUp, connected: false), .missed)

        XCTAssertEqual(ChatCallFields.decode(ChatCallFields.encode(answered)), answered)
        XCTAssertNil(ChatCallFields.decode(["callId": "", "outcome": "missed"]))
        XCTAssertNil(ChatCallFields.decode(["callId": "x", "outcome": "bilinmeyen"]))

        let message = ChatMessageDTO(id: "call-c1", senderID: "a", type: .call, text: "", createdAt: .now, call: answered)
        let fields = ChatFirestoreMapper.newMessageFields(message)
        XCTAssertEqual(fields["type"] as? String, "call")
        XCTAssertEqual(ChatCallFields.decode(fields["call"]), answered)
        let item = ChatMessageItem(message: message, isMine: false, status: nil, myReaction: nil, canEdit: false)
        XCTAssertEqual(item.displayText, "📞 Sesli arama · 2:34")
    }

    func testIceServerDecodingAcceptsStringOrArray() throws {
        let json = #"{"iceServers":[{"urls":"stun:a:3478"},{"urls":["turn:b:3478","turns:b:443"],"username":"u","credential":"p"}]}"#
        struct Wrapper: Decodable { var iceServers: [IceServer] }
        let servers = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8)).iceServers
        XCTAssertEqual(servers[0].urls, ["stun:a:3478"])
        XCTAssertEqual(servers[1], IceServer(urls: ["turn:b:3478", "turns:b:443"], username: "u", credential: "p"))
        XCTAssertFalse(IceServer.fallback.isEmpty)
    }
}

// MARK: - Sahteler

final class FakeSignaling: CallSignaling {
    private(set) var created: [CallDocument] = []
    private(set) var offers: [(SessionDescription, Int)] = []
    private(set) var answers: [(SessionDescription, Int)] = []
    private(set) var statuses: [(CallSignalStatus, String)] = []
    private(set) var candidates: [CallCandidate] = []
    var fetchResult: CallDocument?
    var callHandler: (@MainActor (CallDocument?) -> Void)?
    var candidateHandler: (@MainActor ([CallCandidate]) -> Void)?
    var incomingHandler: (@MainActor ([CallDocument]) -> Void)?

    func createCall(_ call: CallDocument) async throws { mockLock.withLock { created.append(call) } }
    func updateOffer(_ offer: SessionDescription, version: Int, chatID: String, callID: String) async throws {
        mockLock.withLock { offers.append((offer, version)) }
    }
    func answer(_ answer: SessionDescription, version: Int, chatID: String, callID: String, at: Date) async throws {
        mockLock.withLock { answers.append((answer, version)) }
    }
    func setStatus(_ status: CallSignalStatus, chatID: String, callID: String, by userID: String, at: Date) async throws {
        mockLock.withLock { statuses.append((status, callID)) }
    }
    func addCandidate(_ candidate: CallCandidate, chatID: String, callID: String) async throws {
        mockLock.withLock { candidates.append(candidate) }
    }
    func observeCall(chatID: String, callID: String, onChange: @escaping @MainActor (CallDocument?) -> Void) -> ChatSubscription {
        callHandler = onChange
        return .none
    }
    func observeCandidates(chatID: String, callID: String, excluding userID: String,
                           onChange: @escaping @MainActor ([CallCandidate]) -> Void) -> ChatSubscription {
        candidateHandler = onChange
        return .none
    }
    func observeIncoming(chatID: String, userID: String, onChange: @escaping @MainActor ([CallDocument]) -> Void) -> ChatSubscription {
        incomingHandler = onChange
        return .none
    }
    func fetchCall(chatID: String, callID: String) async throws -> CallDocument? { fetchResult }
}

final class FakeEngine: CallMediaEngine {
    var onLocalCandidate: ((LocalIceCandidate) -> Void)?
    var onConnectionChange: ((CallMediaConnection) -> Void)?
    private(set) var preparedServers: [IceServer] = []
    private(set) var offers: [Bool] = []
    private(set) var answeredOffers: [String] = []
    private(set) var remoteAnswers: [String] = []
    private(set) var remoteCandidates: [String] = []
    private(set) var muted = false
    private(set) var held = false
    private(set) var closed = false
    var statsSample = CallStatsSample(roundTripTime: 0.05, packetLoss: 0, jitter: 0.005)

    func prepare(iceServers: [IceServer]) throws { preparedServers = iceServers }
    func makeOffer(iceRestart: Bool) async throws -> SessionDescription {
        offers.append(iceRestart)
        return SessionDescription(kind: .offer, sdp: "offer-\(offers.count)")
    }
    func makeAnswer(for offer: SessionDescription) async throws -> SessionDescription {
        answeredOffers.append(offer.sdp)
        return SessionDescription(kind: .answer, sdp: "answer-\(answeredOffers.count)")
    }
    func setRemoteAnswer(_ answer: SessionDescription) async throws { remoteAnswers.append(answer.sdp) }
    func addRemoteCandidate(_ candidate: CallCandidate) async { remoteCandidates.append(candidate.candidate) }
    func setMuted(_ muted: Bool) { self.muted = muted }
    func setOnHold(_ onHold: Bool) { held = onHold }
    func audioSessionActivated(_ session: AVAudioSession) {}
    func audioSessionDeactivated(_ session: AVAudioSession) {}
    func stats() async -> CallStatsSample { statsSample }
    func close() { closed = true }
}

@MainActor
final class FakeCallSystem: CallSystemUI {
    weak var delegate: CallSystemDelegate?
    private(set) var events: [String] = []
    var rejectIncoming = false

    func reportIncoming(uuid: UUID, callerName: String) async throws {
        if rejectIncoming { throw AppError.notAuthorized }
        events.append("incoming:\(callerName)")
    }
    func startOutgoing(uuid: UUID, calleeName: String) async throws { events.append("outgoing:\(calleeName)") }
    func reportOutgoingConnecting(uuid: UUID) { events.append("connecting") }
    func reportConnected(uuid: UUID) { events.append("connected") }
    func reportEnded(uuid: UUID, reason: CallEndReason) { events.append("ended:\(reason)") }
    // CallKit işlemi hemen onaylanmış gibi.
    func requestEnd(uuid: UUID) { delegate?.callSystemDidEnd(uuid) }
    func requestMute(_ muted: Bool, uuid: UUID) { delegate?.callSystemDidSetMuted(muted, uuid: uuid) }
    func requestHold(_ held: Bool, uuid: UUID) { delegate?.callSystemDidSetHeld(held, uuid: uuid) }
}

final class FakeCallServer: CallServerProviding {
    private(set) var rings: [String] = []
    func iceServers() async throws -> [IceServer] { [IceServer(urls: ["turn:t:3478"], username: "u", credential: "p")] }
    func ring(chatID: String, callID: String) async throws { mockLock.withLock { rings.append("\(chatID)/\(callID)") } }
}

final class FakeNetwork: NetworkChangeMonitoring {
    var onChange: (() -> Void)?
    private(set) var started = 0
    func start() { started += 1 }
    func stop() {}
}

final class FakeRouting: CallAudioRouting {
    private(set) var speaker: [Bool] = []
    func setSpeaker(_ on: Bool) { speaker.append(on) }
}

// MARK: - Arama akışı

@MainActor
final class CallManagerTests: XCTestCase {
    private var signaling: FakeSignaling!
    private var engine: FakeEngine!
    private var system: FakeCallSystem!
    private var server: FakeCallServer!
    private var chat: MockChatSync!
    private var notifier: MockNotifier!
    private var network: FakeNetwork!
    private var routing: FakeRouting!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var user = (id: "a", name: "Ali")
    private var counter = 0

    override func setUp() async throws {
        try await super.setUp()
        signaling = FakeSignaling()
        engine = FakeEngine()
        system = FakeCallSystem()
        server = FakeCallServer()
        chat = MockChatSync()
        notifier = MockNotifier()
        network = FakeNetwork()
        routing = FakeRouting()
        counter = 0
    }

    override func tearDown() async throws {
        await settleTasks()
        try await super.tearDown()
    }

    private func makeManager() -> CallManager {
        CallManager(signaling: signaling, makeEngine: { [unowned self] in self.engine }, system: system, server: server,
                    chatSync: chat, notifier: notifier, audioRouting: routing, network: network,
                    clock: { [unowned self] in self.now },
                    makeID: { [unowned self] in
                        self.counter += 1
                        return "id\(self.counter)"
                    },
                    // Zamanlayıcılar kendiliğinden dolmaz; testler zaman aşımlarını doğrudan tetikler.
                    sleep: { _ in try await Task.sleep(nanoseconds: 3_600_000_000_000) },
                    currentUser: { [unowned self] in self.user })
    }

    private func doc(_ id: String = "id1", status: CallSignalStatus, caller: String = "a", callee: String = "b",
                     answer: SessionDescription? = nil, offerVersion: Int = 1, answerVersion: Int = 0, endedBy: String? = nil) -> CallDocument {
        CallDocument(id: id, chatID: "a_b", callerID: caller, calleeID: callee, status: status,
                     offer: SessionDescription(kind: .offer, sdp: "offer-\(offerVersion)"), answer: answer,
                     offerVersion: offerVersion, answerVersion: answerVersion, createdAt: now,
                     answeredAt: nil, endedAt: nil, endedBy: endedBy)
    }

    private func candidate(_ text: String, from: String = "b") -> CallCandidate {
        CallCandidate(id: text, from: from, candidate: text, sdpMid: "0", sdpMLineIndex: 0, offerVersion: 1)
    }

    func testOutgoingCallFullFlowWritesAnsweredCallRow() async throws {
        let sut = makeManager()
        await sut.startCall(chatID: "a_b", calleeID: "b", calleeName: "Elif")
        XCTAssertEqual(sut.phase, .ringing(.outgoing))
        XCTAssertEqual(system.events, ["outgoing:Elif"])
        let created = try XCTUnwrap(signaling.created.first)
        XCTAssertEqual(created.status, .ringing)
        XCTAssertEqual(created.callerID, "a")
        XCTAssertEqual(created.calleeID, "b")
        XCTAssertEqual(created.offer?.sdp, "offer-1")
        XCTAssertEqual(engine.preparedServers.first?.urls, ["turn:t:3478"], "TURN sunucudan gelir")
        await settleTasks()
        XCTAssertEqual(server.rings, ["a_b/id1"], "karşı taraf çaldırılır")

        // Yerel aday gönderilir; erken gelen uzak aday yanıt gelene kadar bekletilir.
        engine.onLocalCandidate?(LocalIceCandidate(candidate: "local-1", sdpMid: "0", sdpMLineIndex: 0))
        await sut.receive([candidate("remote-1")])
        await settleTasks()
        XCTAssertEqual(signaling.candidates.map(\.from), ["a"])
        XCTAssertTrue(engine.remoteCandidates.isEmpty)

        await sut.handleRemote(doc(status: .accepted, answer: SessionDescription(kind: .answer, sdp: "answer-1"), answerVersion: 1))
        XCTAssertEqual(sut.phase, .connecting)
        XCTAssertEqual(engine.remoteAnswers, ["answer-1"])
        XCTAssertEqual(engine.remoteCandidates, ["remote-1"])
        XCTAssertTrue(system.events.contains("connecting"))

        sut.mediaChanged(.connected)
        XCTAssertEqual(sut.phase, .connected(since: now))
        XCTAssertTrue(system.events.contains("connected"))

        now = now.addingTimeInterval(154)
        sut.tick()
        XCTAssertEqual(sut.statusText, "2:34")
        sut.hangUp()
        for _ in 0..<3 { await settleTasks() }
        XCTAssertEqual(sut.phase, .ended(.hungUp))
        XCTAssertEqual(signaling.statuses.map(\.0), [.ended])
        XCTAssertTrue(engine.closed)
        let row = try XCTUnwrap(chat.sent.first)
        XCTAssertEqual(row.id, "call-id1", "aynı arama için tek satır")
        XCTAssertEqual(row.type, .call)
        XCTAssertEqual(row.call, ChatCallInfo(callID: "id1", outcome: .answered, duration: 154))
        XCTAssertEqual(notifier.calls, ["a_b/call-id1"])
    }

    func testUnansweredOutgoingCallBecomesMissed() async throws {
        let sut = makeManager()
        await sut.startCall(chatID: "a_b", calleeID: "b", calleeName: "Elif")
        sut.handleRingTimeout(callID: "id1")
        for _ in 0..<3 { await settleTasks() }
        XCTAssertEqual(sut.phase, .ended(.missed))
        XCTAssertEqual(signaling.statuses.map(\.0), [.missed])
        XCTAssertTrue(system.events.contains("ended:missed"))
        XCTAssertEqual(chat.sent.first?.call?.outcome, .missed)
        XCTAssertEqual(chat.sent.first?.call?.duration, 0)
    }

    func testDeclinedAndBusyComeFromCallee() async throws {
        let sut = makeManager()
        await sut.startCall(chatID: "a_b", calleeID: "b", calleeName: "Elif")
        await sut.handleRemote(doc(status: .declined, endedBy: "b"))
        for _ in 0..<3 { await settleTasks() }
        XCTAssertEqual(sut.phase, .ended(.declined))
        XCTAssertTrue(signaling.statuses.isEmpty, "karşı taraf yazdı; tekrar yazılmaz")
        XCTAssertEqual(chat.sent.first?.call?.outcome, .declined)
        XCTAssertTrue(system.events.contains("ended:declined"))
    }

    func testIncomingCallAnswerAndRemoteHangUp() async throws {
        user = (id: "b", name: "Elif")
        let sut = makeManager()
        sut.watch(chatID: "a_b", partnerName: "Ali")
        signaling.incomingHandler?([doc(status: .ringing)])
        for _ in 0..<2 { await settleTasks() }
        XCTAssertEqual(sut.phase, .ringing(.incoming))
        XCTAssertEqual(system.events, ["incoming:Ali"])
        XCTAssertEqual(sut.partnerName, "Ali")

        sut.answer()
        for _ in 0..<2 { await settleTasks() }
        XCTAssertEqual(sut.phase, .connecting)
        XCTAssertEqual(engine.answeredOffers, ["offer-1"])
        XCTAssertEqual(signaling.answers.map(\.1), [1])
        await sut.receive([candidate("remote-x", from: "a")])
        XCTAssertEqual(engine.remoteCandidates, ["remote-x"], "teklif uygulandıktan sonra aday hemen eklenir")

        sut.mediaChanged(.connected)
        await sut.handleRemote(doc(status: .ended, answerVersion: 1, endedBy: "a"))
        for _ in 0..<3 { await settleTasks() }
        XCTAssertEqual(sut.phase, .ended(.remoteEnded))
        XCTAssertTrue(system.events.contains("ended:remoteEnded"))
        XCTAssertTrue(chat.sent.isEmpty, "arama satırını yalnızca arayan yazar")
    }

    func testDecliningIncomingCallAndOldCallsAreIgnored() async throws {
        user = (id: "b", name: "Elif")
        let sut = makeManager()
        sut.watch(chatID: "a_b", partnerName: "Ali")
        var stale = doc("old", status: .ringing)
        stale.createdAt = now.addingTimeInterval(-600)
        signaling.incomingHandler?([stale])
        await settleTasks()
        XCTAssertEqual(sut.phase, .idle, "süresi geçmiş arama çalmaz")

        signaling.incomingHandler?([doc(status: .ringing)])
        for _ in 0..<2 { await settleTasks() }
        sut.hangUp()
        for _ in 0..<3 { await settleTasks() }
        XCTAssertEqual(sut.phase, .ended(.declined))
        XCTAssertEqual(signaling.statuses.map(\.0), [.declined])

        // Aynı arama dinleyiciden tekrar gelse de yeniden çalmaz.
        signaling.incomingHandler?([doc(status: .ringing)])
        await settleTasks()
        XCTAssertEqual(system.events.filter { $0.hasPrefix("incoming") }.count, 1)
    }

    func testSecondIncomingCallGetsBusy() async throws {
        let sut = makeManager()
        await sut.startCall(chatID: "a_b", calleeID: "b", calleeName: "Elif")
        sut.watch(chatID: "a_b", partnerName: "Elif")
        signaling.incomingHandler?([doc("other", status: .ringing, caller: "b", callee: "a")])
        await settleTasks()
        XCTAssertEqual(signaling.statuses.map(\.0), [.busy])
        XCTAssertEqual(signaling.statuses.first?.1, "other")
        XCTAssertEqual(sut.phase, .ringing(.outgoing), "süren arama etkilenmez")
    }

    func testNetworkChangeRestartsIceAndKeepsDuration() async throws {
        let sut = makeManager()
        await sut.startCall(chatID: "a_b", calleeID: "b", calleeName: "Elif")
        await sut.handleRemote(doc(status: .accepted, answer: SessionDescription(kind: .answer, sdp: "answer-1"), answerVersion: 1))
        sut.mediaChanged(.connected)
        let since = now

        now = now.addingTimeInterval(30)
        sut.mediaChanged(.failed)
        XCTAssertEqual(sut.phase, .reconnecting(since: since))
        XCTAssertEqual(sut.statusText, "Yeniden bağlanıyor…")
        for _ in 0..<3 { await settleTasks() }
        XCTAssertEqual(engine.offers, [false, true], "ICE yeniden başlatılır")
        XCTAssertEqual(signaling.offers.map(\.1), [2])

        await sut.handleRemote(doc(status: .accepted, answer: SessionDescription(kind: .answer, sdp: "answer-2"), offerVersion: 2, answerVersion: 2))
        XCTAssertEqual(engine.remoteAnswers, ["answer-1", "answer-2"])
        sut.mediaChanged(.connected)
        XCTAssertEqual(sut.phase, .connected(since: since))
        XCTAssertGreaterThan(network.started, 0, "ağ değişimi izlenir")
    }

    func testCalleeAnswersRestartedOffer() async throws {
        user = (id: "b", name: "Elif")
        let sut = makeManager()
        sut.watch(chatID: "a_b", partnerName: "Ali")
        signaling.incomingHandler?([doc(status: .ringing)])
        for _ in 0..<2 { await settleTasks() }
        sut.answer()
        for _ in 0..<2 { await settleTasks() }
        await sut.handleRemote(doc(status: .accepted, offerVersion: 2, answerVersion: 1))
        XCTAssertEqual(engine.answeredOffers, ["offer-1", "offer-2"])
        XCTAssertEqual(signaling.answers.map(\.1), [1, 2])
    }

    func testMuteHoldSpeakerAndQuality() async throws {
        let sut = makeManager()
        await sut.startCall(chatID: "a_b", calleeID: "b", calleeName: "Elif")
        await sut.handleRemote(doc(status: .accepted, answer: SessionDescription(kind: .answer, sdp: "answer-1"), answerVersion: 1))
        sut.mediaChanged(.connected)

        sut.toggleMute()
        XCTAssertTrue(sut.isMuted)
        XCTAssertTrue(engine.muted)
        sut.toggleHold()
        XCTAssertTrue(sut.isOnHold)
        XCTAssertTrue(engine.held)
        XCTAssertTrue(sut.statusText.hasPrefix("Beklemede"))
        sut.toggleSpeaker()
        XCTAssertEqual(routing.speaker, [true])
        for _ in 0..<3 { await settleTasks() }
        XCTAssertEqual(sut.quality, .good)
    }

    func testVoIPPushPresentsRingingCallOrEndsStaleOne() async throws {
        user = (id: "b", name: "Elif")
        let sut = makeManager()
        signaling.fetchResult = doc(status: .ended)
        await sut.handleVoIPPush(callID: "id1", chatID: "a_b", callerName: "Ali")
        XCTAssertEqual(system.events, ["incoming:Ali", "ended:missed"], "iOS kuralı: her VoIP push CallKit'e bildirilir")
        XCTAssertEqual(sut.phase, .idle)

        signaling.fetchResult = doc("id2", status: .ringing)
        await sut.handleVoIPPush(callID: "id2", chatID: "a_b", callerName: "Ali")
        XCTAssertEqual(sut.phase, .ringing(.incoming))
        XCTAssertEqual(system.events.filter { $0 == "incoming:Ali" }.count, 2, "ikinci kez bildirilmez")
    }
}
