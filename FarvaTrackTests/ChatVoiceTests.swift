import XCTest
import SwiftData
import AVFoundation
@testable import FarvaTrack

// MARK: - Sahte ses bileşenleri

final class MockAudioSession: AudioSessionControlling {
    var permission = true
    /// Açıkken izin cevabı `answerPermission()` çağrılana kadar bekler.
    var holdPermission = false
    var external = false
    var failActivation = false
    private(set) var recordingActivations = 0
    private(set) var playbackActivations: [Bool] = []
    private(set) var deactivations = 0
    private var pendingPermission: CheckedContinuation<Bool, Never>?

    func requestRecordPermission() async -> Bool {
        if holdPermission {
            return await withCheckedContinuation { pendingPermission = $0 }
        }
        return permission
    }

    func answerPermission() {
        pendingPermission?.resume(returning: permission)
        pendingPermission = nil
    }

    var isWaitingForPermission: Bool { pendingPermission != nil }

    func activateForRecording() throws {
        if failActivation { throw AppError.unknown("oturum") }
        recordingActivations += 1
    }

    func activateForPlayback(useEarpiece: Bool) throws {
        playbackActivations.append(useEarpiece)
    }

    func deactivate() { deactivations += 1 }
    var isExternalOutputConnected: Bool { external }
}

final class MockVoiceRecorder: VoiceRecording {
    var power: Float = -20
    var time: TimeInterval = 0
    var failStart = false
    private(set) var startedURL: URL?
    private(set) var stopped = false
    private(set) var cancelled = false

    func start(at url: URL) throws {
        if failStart { throw AppError.invalidInput("Kayıt başlatılamadı.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("ses".utf8).write(to: url)
        startedURL = url
    }

    func currentPower() -> Float { power }
    var currentTime: TimeInterval { time }

    func stop() -> TimeInterval {
        stopped = true
        return time
    }

    func cancel() {
        cancelled = true
        if let startedURL { try? FileManager.default.removeItem(at: startedURL) }
    }
}

final class MockPlaybackEngine: AudioPlaybackEngine {
    var duration: TimeInterval
    var currentTime: TimeInterval = 0
    var rate: Float = 1
    private(set) var isPlaying = false
    var onFinish: (() -> Void)?
    var playSucceeds = true
    private(set) var stopped = false

    init(duration: TimeInterval) { self.duration = duration }

    func play() -> Bool {
        isPlaying = playSucceeds
        return playSucceeds
    }
    func pause() { isPlaying = false }
    func stop() {
        isPlaying = false
        stopped = true
    }
    func finish() {
        isPlaying = false
        currentTime = duration
        onFinish?()
    }
}

final class MockProximity: ProximityMonitoring {
    var isNear = false
    private(set) var enabledHistory: [Bool] = []
    var isEnabled: Bool { enabledHistory.last ?? false }
    func setEnabled(_ enabled: Bool) { enabledHistory.append(enabled) }
}

// MARK: - Model

final class ChatVoiceModelTests: XCTestCase {
    func testAudioFieldsRoundTrip() {
        let audio = ChatAudio(path: "chats/a_b/media/m1/voice.m4a", contentType: "audio/mp4", byteSize: 48_000,
                              duration: 7.25, waveform: [0, 12, 255, 128])
        XCTAssertEqual(ChatAudioFields.decode(ChatAudioFields.encode(audio)), audio)

        let server: [String: Any] = ["path": "p", "duration": NSNumber(value: 3), "waveform": [NSNumber(value: 300), NSNumber(value: -4), NSNumber(value: 9)]]
        let decoded = ChatAudioFields.decode(server)
        XCTAssertEqual(decoded?.waveform, [255, 0, 9], "taşan değerler sınırlanır")
        XCTAssertEqual(decoded?.contentType, "audio/mp4")
        XCTAssertNil(ChatAudioFields.decode(["duration": 3]))
        XCTAssertEqual(ChatAudioPath.voice(chatID: "a_b", messageID: "m1"), "chats/a_b/media/m1/voice.m4a")
        XCTAssertTrue(ChatMessageType.sendable.contains(.audio))
    }

    func testLevelFromDecibels() {
        XCTAssertEqual(VoiceWaveform.level(fromDecibels: -160), 0)
        XCTAssertEqual(VoiceWaveform.level(fromDecibels: -50), 0)
        XCTAssertEqual(VoiceWaveform.level(fromDecibels: 0), 1)
        XCTAssertEqual(VoiceWaveform.level(fromDecibels: .nan), 0)
        let quiet = VoiceWaveform.level(fromDecibels: -35)
        let loud = VoiceWaveform.level(fromDecibels: -10)
        XCTAssertGreaterThan(quiet, 0)
        XCTAssertGreaterThan(loud, quiet, "seviye desibelle artar")
        XCTAssertLessThan(loud, 1)
    }

    func testBarsUseSlicePeaks() {
        XCTAssertEqual(VoiceWaveform.bars(from: []), Array(repeating: 0, count: VoiceWaveform.barCount))
        XCTAssertEqual(VoiceWaveform.bars(from: [0, 1, 0.5, 0.25], count: 2), [255, 128])
        XCTAssertEqual(VoiceWaveform.bars(from: [1], count: 3), [255, 255, 255], "kısa kayıtta da sabit çubuk sayısı")
        XCTAssertEqual(VoiceWaveform.bars(from: Array(repeating: 0.5, count: 1_000)).count, VoiceWaveform.barCount)
        XCTAssertEqual(VoiceWaveform.recent([0.1, 0.2], count: 4), [0, 0, 0.1, 0.2])
        XCTAssertEqual(VoiceWaveform.recent([1, 2, 3, 4, 5], count: 2), [4, 5])
    }

    func testFormattingAndRates() {
        XCTAssertEqual(VoiceFormat.time(0), "0:00")
        XCTAssertEqual(VoiceFormat.time(65.9), "1:05")
        XCTAssertEqual(VoiceFormat.time(.infinity), "0:00")
        XCTAssertEqual(VoiceRate.normal.next, .fast)
        XCTAssertEqual(VoiceRate.fast.next, .double)
        XCTAssertEqual(VoiceRate.double.next, .normal)
        XCTAssertEqual(VoiceRate.allCases.map(\.title), ["1x", "1,5x", "2x"])
    }

    /// Kayıt ayarlarıyla gerçek bir AAC dosyası yazılır, geri okunur ve oynatıcıda açılır.
    func testRecorderSettingsProduce48kHzAACThatPlays() throws {
        let settings = VoiceRecorder.settings
        XCTAssertEqual(settings[AVFormatIDKey] as? Int, Int(kAudioFormatMPEG4AAC))
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 48_000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let format = file.processingFormat
            let frames = AVAudioFrameCount(format.sampleRate)  // 1 saniye
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            buffer.frameLength = frames
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            for index in 0..<Int(frames) {
                samples[index] = 0.3 * sinf(2 * .pi * 440 * Float(index) / Float(format.sampleRate))
            }
            try file.write(from: buffer)
        }

        let readBack = try AVAudioFile(forReading: url)
        XCTAssertEqual(readBack.fileFormat.sampleRate, 48_000)
        XCTAssertEqual(readBack.fileFormat.channelCount, 1)
        XCTAssertEqual(readBack.fileFormat.settings[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)

        let engine = try AVAudioPlaybackEngine(url: url)
        XCTAssertEqual(engine.duration, 1, accuracy: 0.1)
        engine.rate = 2
        XCTAssertEqual(engine.rate, 2, "hız ayarı açık")
        engine.currentTime = 0.5
        XCTAssertEqual(engine.currentTime, 0.5, accuracy: 0.05)
    }
}

// MARK: - Kayıt modeli

@MainActor
final class ChatVoiceRecorderModelTests: XCTestCase {
    private var recorder: MockVoiceRecorder!
    private var session: MockAudioSession!
    private var directory: URL!
    private var sut: ChatVoiceRecorderModel!

    override func setUp() async throws {
        try await super.setUp()
        recorder = MockVoiceRecorder()
        session = MockAudioSession()
        directory = makeTemporaryDirectory()
        sut = ChatVoiceRecorderModel(recorder: recorder, session: session, directory: directory)
    }

    override func tearDown() async throws {
        sut.cancel()
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    func testHoldRecordsAndReleaseSends() async throws {
        let started = await sut.begin()
        XCTAssertTrue(started)
        XCTAssertEqual(sut.phase, .recording)
        XCTAssertEqual(session.recordingActivations, 1)

        recorder.power = -10
        recorder.time = 1
        sut.sample()
        recorder.power = -40
        recorder.time = 2.4
        sut.sample()
        XCTAssertEqual(sut.levels.count, 2)
        XCTAssertEqual(sut.elapsed, 2.4)
        XCTAssertGreaterThan(sut.levels[0], sut.levels[1], "canlı dalga formu sese göre değişir")

        let voice = try XCTUnwrap(sut.release())
        XCTAssertEqual(voice.duration, 2.4)
        XCTAssertEqual(voice.waveform.count, VoiceWaveform.barCount)
        XCTAssertEqual(voice.fileURL, recorder.startedURL)
        XCTAssertEqual(voice.fileURL.pathExtension, "m4a")
        XCTAssertTrue(recorder.stopped)
        XCTAssertEqual(sut.phase, .idle)
        XCTAssertEqual(session.deactivations, 1, "kayıt bitince oturum bırakılır (müzik devam eder)")
    }

    func testSlideLeftCancels() async {
        await sut.begin()
        recorder.time = 3
        sut.dragChanged(CGSize(width: -60, height: 0))
        XCTAssertEqual(sut.phase, .recording)
        XCTAssertGreaterThan(sut.cancelProgress, 0.5)

        sut.dragChanged(CGSize(width: -ChatVoiceRecorderModel.cancelDistance - 1, height: 0))
        XCTAssertEqual(sut.phase, .idle)
        XCTAssertTrue(recorder.cancelled)
        XCTAssertNil(sut.release(), "iptalden sonra parmak kalkınca gönderilmez")
        let file = try? XCTUnwrap(recorder.startedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file?.path ?? "/yok"))
    }

    func testSlideUpLocksAndFinishSends() async throws {
        await sut.begin()
        sut.dragChanged(CGSize(width: 0, height: -ChatVoiceRecorderModel.lockDistance - 5))
        XCTAssertEqual(sut.phase, .locked)
        XCTAssertNil(sut.release(), "kilitliyken parmak kalksa da kayıt sürer")
        XCTAssertEqual(sut.phase, .locked)

        // Kilitliyken sola kaydırmak iptal etmez.
        sut.dragChanged(CGSize(width: -500, height: 0))
        XCTAssertEqual(sut.phase, .locked)

        recorder.time = 12
        let voice = try XCTUnwrap(sut.finish())
        XCTAssertEqual(voice.duration, 12)
        XCTAssertEqual(sut.phase, .idle)
    }

    func testTooShortRecordingIsDiscardedWithHint() async {
        await sut.begin()
        recorder.time = 0.2
        XCTAssertNil(sut.release())
        XCTAssertEqual(sut.hint, "Kaydetmek için basılı tut")
        XCTAssertFalse(FileManager.default.fileExists(atPath: recorder.startedURL?.path ?? "/yok"))
    }

    func testPermissionDeniedShowsHint() async {
        session.permission = false
        let started = await sut.begin()
        XCTAssertFalse(started)
        XCTAssertEqual(sut.phase, .idle)
        XCTAssertNil(recorder.startedURL)
        XCTAssertTrue(sut.hint?.contains("Mikrofon izni") ?? false)
    }

    func testReleasingDuringPermissionPromptDoesNotStart() async {
        session.holdPermission = true
        let task = Task { await sut.begin() }
        for _ in 0..<20 where !session.isWaitingForPermission { await Task.yield() }
        XCTAssertTrue(session.isWaitingForPermission)
        XCTAssertNil(sut.release())
        session.answerPermission()
        let started = await task.value
        XCTAssertFalse(started)
        XCTAssertNil(recorder.startedURL)
    }

    func testStartFailureShowsHint() async {
        recorder.failStart = true
        let started = await sut.begin()
        XCTAssertFalse(started)
        XCTAssertEqual(sut.hint, "Kayıt başlatılamadı.")
        XCTAssertEqual(session.deactivations, 1)
    }

    func testMaximumDurationAutoFinishes() async {
        var sent: RecordedVoice?
        sut.onAutoFinish = { sent = $0 }
        await sut.begin()
        recorder.time = ChatVoiceRecorderModel.maximumDuration
        sut.sample()
        XCTAssertEqual(sent?.duration, ChatVoiceRecorderModel.maximumDuration)
        XCTAssertEqual(sut.phase, .idle)
    }
}

// MARK: - Oynatıcı

@MainActor
final class ChatAudioPlayerTests: XCTestCase {
    private var session: MockAudioSession!
    private var proximity: MockProximity!
    private var engines: [MockPlaybackEngine] = []
    private var center: NotificationCenter!
    private var defaults: UserDefaults!
    private var started: [String] = []
    private var sut: ChatAudioPlayer!
    private let url = URL(fileURLWithPath: "/tmp/ses.m4a")

    override func setUp() async throws {
        try await super.setUp()
        session = MockAudioSession()
        proximity = MockProximity()
        center = NotificationCenter()
        defaults = makeTestDefaults("player.\(name)")
        engines = []
        started = []
        sut = makePlayer()
    }

    private func makePlayer() -> ChatAudioPlayer {
        let player = ChatAudioPlayer(session: session, proximity: proximity, defaults: defaults, notificationCenter: center) { [unowned self] _ in
            let engine = MockPlaybackEngine(duration: 10)
            self.engines.append(engine)
            return engine
        }
        player.onStartedPlaying = { [unowned self] in self.started.append($0) }
        return player
    }

    func testToggleLoadsPlaysPausesAndResumes() {
        sut.toggle(id: "m1", url: url)
        XCTAssertTrue(sut.isPlaying)
        XCTAssertEqual(sut.currentID, "m1")
        XCTAssertEqual(sut.duration, 10)
        XCTAssertEqual(started, ["m1"], "dinlendi bilgisi için bildirilir")
        XCTAssertEqual(session.playbackActivations, [false], "kulak yakın değilse hoparlör/kulaklık")
        XCTAssertTrue(proximity.isEnabled, "kulaklık yokken yakınlık sensörü açılır")

        sut.toggle(id: "m1", url: url)
        XCTAssertFalse(sut.isPlaying)
        XCTAssertFalse(proximity.isEnabled)
        sut.toggle(id: "m1", url: url)
        XCTAssertTrue(sut.isPlaying)
        XCTAssertEqual(engines.count, 1, "aynı mesaj yeniden yüklenmez")
    }

    func testPlayingAnotherMessageStopsTheFirst() {
        sut.toggle(id: "m1", url: url)
        sut.toggle(id: "m2", url: url)
        XCTAssertTrue(engines[0].stopped)
        XCTAssertEqual(sut.currentID, "m2")
        XCTAssertTrue(engines[1].isPlaying)
    }

    func testSeekUpdatesProgressAndLoadsPausedIfNeeded() {
        sut.seek(id: "m1", url: url, to: 0.25)
        XCTAssertEqual(sut.currentID, "m1")
        XCTAssertFalse(sut.isPlaying, "sürüklemek çalmayı başlatmaz")
        XCTAssertEqual(sut.currentTime, 2.5)
        XCTAssertEqual(sut.progress, 0.25)
        XCTAssertTrue(started.isEmpty)

        sut.seek(id: "m1", url: url, to: 1.7)
        XCTAssertEqual(sut.progress, 1, "sınırlar korunur")
    }

    func testRateCyclesAppliesAndPersists() {
        sut.toggle(id: "m1", url: url)
        XCTAssertEqual(engines[0].rate, 1)
        sut.cycleRate()
        XCTAssertEqual(sut.rate, .fast)
        XCTAssertEqual(engines[0].rate, 1.5)
        sut.cycleRate()
        XCTAssertEqual(engines[0].rate, 2)

        let second = makePlayer()
        XCTAssertEqual(second.rate, .double, "hız tercihi hatırlanır")
        second.toggle(id: "m2", url: url)
        XCTAssertEqual(engines.last?.rate, 2)
    }

    func testFinishResetsAndReleasesSession() async {
        sut.toggle(id: "m1", url: url)
        engines[0].finish()
        await settleTasks()
        XCTAssertFalse(sut.isPlaying)
        XCTAssertEqual(sut.currentTime, 0)
        XCTAssertEqual(session.deactivations, 1)
        XCTAssertFalse(proximity.isEnabled)

        sut.toggle(id: "m1", url: url)
        XCTAssertEqual(engines[0].currentTime, 0, "bittikten sonra baştan çalar")
        XCTAssertTrue(sut.isPlaying)
    }

    func testHeadphonesUnpluggedPauses() {
        sut.toggle(id: "m1", url: url)
        center.post(name: AVAudioSession.routeChangeNotification, object: nil,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        XCTAssertFalse(sut.isPlaying, "kulaklık çıkınca ses hoparlörden patlamaz")
    }

    func testInterruptionPauses() {
        sut.toggle(id: "m1", url: url)
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        XCTAssertFalse(sut.isPlaying)
    }

    func testProximitySwitchesToEarpieceAndBack() {
        sut.toggle(id: "m1", url: url)
        proximity.isNear = true
        center.post(name: UIDevice.proximityStateDidChangeNotification, object: nil)
        XCTAssertTrue(sut.usingEarpiece)
        XCTAssertEqual(session.playbackActivations.last, true)
        XCTAssertTrue(sut.isPlaying, "geçişte çalma kesilmez")

        // Kulaklık takılınca ahizeden çıkılır.
        session.external = true
        center.post(name: AVAudioSession.routeChangeNotification, object: nil,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])
        XCTAssertFalse(sut.usingEarpiece)
        XCTAssertEqual(session.playbackActivations.last, false)

        // Kulaklık varken yakınlık önemsizdir.
        proximity.isNear = false
        proximity.isNear = true
        sut.handleProximityChange()
        XCTAssertFalse(sut.usingEarpiece)
    }

    func testExternalOutputSkipsProximity() {
        session.external = true
        sut.toggle(id: "m1", url: url)
        XCTAssertFalse(proximity.isEnabled)
    }

    func testPlayFailureShowsError() {
        let player = ChatAudioPlayer(session: session, proximity: proximity, defaults: defaults, notificationCenter: center) { _ in
            let engine = MockPlaybackEngine(duration: 1)
            engine.playSucceeds = false
            return engine
        }
        player.toggle(id: "m1", url: url)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.errorMessage)

        let broken = ChatAudioPlayer(session: session, proximity: proximity, defaults: defaults, notificationCenter: center) { _ in
            throw AppError.storage("bozuk")
        }
        broken.toggle(id: "m1", url: url)
        XCTAssertNil(broken.currentID)
        XCTAssertNotNil(broken.errorMessage)
    }
}

// MARK: - ViewModel: sesli mesaj akışı

@MainActor
final class ChatVoiceViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var sync: MockChatSync!
    private var store: MockMediaStore!
    private var files: ChatMediaFiles!
    private var root: URL!
    private var sut: ChatViewModel!
    private var idCounter = 0
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let me = AppUser.makeNew(id: "me", email: "ben@ornek.com", displayName: "Ben")
    private var roomID: String { ChatID.make("me", "friend") }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: ChatMessageRecord.self, ChatPendingOperation.self, ChatPlacementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        sync = MockChatSync()
        store = MockMediaStore()
        root = makeTemporaryDirectory()
        files = ChatMediaFiles(persistentRoot: root.appendingPathComponent("support"), cacheRoot: root.appendingPathComponent("caches"))
        idCounter = 0
        sut = ChatViewModel(
            sync: sync, mediaStore: store, processor: MockMediaProcessor(), files: files,
            defaults: makeTestDefaults("voice.\(name)"),
            clock: { [unowned self] in self.now },
            makeID: { [unowned self] in
                self.idCounter += 1
                return "voice-\(self.idCounter)"
            }
        )
        sut.configure(context: container.mainContext, user: me)
        sync.roomHandler?(ChatRoomDTO(id: roomID, members: ChatID.sortedMembers("me", "friend"),
                                      names: ["friend": "Elif"], createdAt: now), false)
        await settle()
    }

    override func tearDown() async throws {
        await settleTasks()
        sut.reset()
        await settleTasks()
        sut = nil
        container = nil
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func settle() async {
        for _ in 0..<3 {
            await settleTasks()
            await sut.flushOutbox()
        }
    }

    private func recorded(duration: Double = 4.2) throws -> RecordedVoice {
        let url = root.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data(repeating: 7, count: 2_000).write(to: url)
        return RecordedVoice(fileURL: url, duration: duration, waveform: Array(repeating: 100, count: VoiceWaveform.barCount))
    }

    private func item(_ id: String) -> ChatMessageItem? { sut.messages.first { $0.id == id } }

    func testVoiceIsUploadedThenSentReady() async throws {
        var uploadsAtSend: [String] = []
        sync.onSend = { [unowned self] _ in uploadsAtSend = self.store.uploads.map(\.path) }
        let voice = try recorded()

        sut.sendVoice(voice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: voice.fileURL.path), "kayıt gönderim klasörüne taşınır")
        XCTAssertEqual(item("voice-1")?.status, .sending)
        XCTAssertEqual(item("voice-1")?.message.type, .audio)

        await settle()
        let path = ChatAudioPath.voice(chatID: roomID, messageID: "voice-1")
        XCTAssertEqual(uploadsAtSend, [path], "dosya mesajdan önce yüklenir: alıcı hemen çalabilir")
        XCTAssertEqual(store.uploads.first?.contentType, "audio/mp4")
        let sent = try XCTUnwrap(sync.sent.first)
        XCTAssertEqual(sent.audio?.duration, 4.2)
        XCTAssertEqual(sent.audio?.byteSize, 2_000)
        XCTAssertEqual(sent.audio?.waveform.count, VoiceWaveform.barCount)
        XCTAssertNil(sent.media)
        XCTAssertEqual(item("voice-1")?.status, .delivered)

        let local = try XCTUnwrap(item("voice-1")?.localOriginalURL)
        XCTAssertTrue(local.path.hasPrefix(files.cacheRoot.path))
        let playable = try await sut.loadAudio(for: item("voice-1")!)
        XCTAssertEqual(playable, local)
        XCTAssertTrue(store.downloads.isEmpty, "kendi sesimiz indirilmez")
    }

    func testOfflineVoiceWaitsAndSendsLater() async throws {
        let path = ChatAudioPath.voice(chatID: roomID, messageID: "voice-1")
        store.alwaysFail[path] = AppError.network
        sut.sendVoice(try recorded())
        await settle()
        XCTAssertEqual(item("voice-1")?.status, .sending)
        XCTAssertTrue(sync.sent.isEmpty)

        store.alwaysFail = [:]
        await sut.handleForeground()
        XCTAssertEqual(sync.sent.count, 1)
        XCTAssertEqual(item("voice-1")?.status, .delivered)
    }

    func testReplyAttachesToVoice() async throws {
        sync.messagesHandler?([ChatMessageDTO(id: "r1", senderID: "friend", text: "ses at", createdAt: now)])
        sut.beginReply(to: item("r1")!)
        sut.sendVoice(try recorded())
        await settle()
        XCTAssertEqual(sync.sent.first?.replyTo?.messageID, "r1")
    }

    private func remoteVoice(listenedAt: Date? = nil, sender: String = "friend", id: String = "rv") -> ChatMessageDTO {
        ChatMessageDTO(
            id: id, senderID: sender, type: .audio, text: "", createdAt: now,
            audio: ChatAudio(path: ChatAudioPath.voice(chatID: roomID, messageID: id), contentType: "audio/mp4",
                             byteSize: 30_000, duration: 9, waveform: [10, 200]),
            listenedAt: listenedAt
        )
    }

    func testRecipientDownloadsOnceAndMarksListened() async throws {
        sync.messagesHandler?([remoteVoice()])
        XCTAssertFalse(item("rv")?.isListened ?? true)

        let url = try await sut.loadAudio(for: item("rv")!)
        XCTAssertEqual(url.pathExtension, "m4a")
        _ = try await sut.loadAudio(for: item("rv")!)
        XCTAssertEqual(store.downloads.count, 1)

        sut.markListened("rv")
        await settle()
        XCTAssertEqual(sync.listens, ["rv"])
        XCTAssertEqual(sync.reads.flatMap { $0 }, ["rv"], "dinlenen mesaj okunmuş da sayılır")
        XCTAssertTrue(item("rv")?.isListened ?? false)

        sut.markListened("rv")
        await settle()
        XCTAssertEqual(sync.listens, ["rv"], "bir kez")

        // Bekleyen işlem yokken eski (dinlenmemiş) anlık görüntü yerel bilgiyi silmez mi?
        sync.messagesHandler?([remoteVoice(listenedAt: now)])
        XCTAssertTrue(item("rv")?.isListened ?? false)
    }

    func testOwnVoiceIsNotMarkedListenedBySender() async throws {
        sync.messagesHandler?([remoteVoice(sender: "me", id: "mine")])
        sut.markListened("mine")
        await settle()
        XCTAssertTrue(sync.listens.isEmpty)

        sync.messagesHandler?([remoteVoice(listenedAt: now, sender: "me", id: "mine")])
        XCTAssertTrue(item("mine")?.isListened ?? false, "gönderen karşı tarafın dinlediğini görür")
    }

    func testDeleteForEveryoneRemovesVoiceFile() async throws {
        sut.sendVoice(try recorded())
        await settle()
        let cached = try XCTUnwrap(item("voice-1")?.localOriginalURL)
        sut.deleteForEveryone(item("voice-1")!)
        await settle()
        XCTAssertEqual(store.deletedPaths, [ChatAudioPath.voice(chatID: roomID, messageID: "voice-1")])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cached.path))
        XCTAssertNil(item("voice-1")?.message.audio)
        XCTAssertEqual(item("voice-1")?.displayText, "Bu mesaj silindi")
    }
}
