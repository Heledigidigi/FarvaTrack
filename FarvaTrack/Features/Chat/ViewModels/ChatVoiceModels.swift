import Foundation
import AVFoundation
import Observation
import UIKit

// MARK: - Kayıt

/// Basılı tut = kaydet, sola kaydır = iptal, yukarı kaydır = kilitle.
@MainActor
@Observable
final class ChatVoiceRecorderModel {
    enum Phase: Equatable {
        case idle
        /// Parmak basılı, kayıt sürüyor.
        case recording
        /// Kilitlendi: parmak kalksa da kayıt sürer.
        case locked
    }

    static let cancelDistance: CGFloat = 110
    static let lockDistance: CGFloat = 90
    /// Bundan kısa kayıtlar gönderilmez (yanlışlıkla dokunma).
    static let minimumDuration: TimeInterval = 0.6
    static let maximumDuration: TimeInterval = 15 * 60
    /// Canlı dalga formunun örnekleme aralığı.
    static let sampleInterval: Duration = .milliseconds(50)

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = []
    /// 0…1: iptal / kilit eşiğine ne kadar yaklaşıldı (arayüzdeki ipuçları için).
    private(set) var cancelProgress: Double = 0
    private(set) var lockProgress: Double = 0
    /// Kısa dokunuş ya da izin hatası gibi kullanıcıya gösterilecek ipucu.
    var hint: String?

    /// En uzun süreye ulaşınca kayıt kendiliğinden biter ve gönderilir.
    var onAutoFinish: ((RecordedVoice) -> Void)?

    private let recorder: VoiceRecording
    private let session: AudioSessionControlling
    private let directory: URL
    private var fileURL: URL?
    private var meterTask: Task<Void, Never>?
    /// İzin sorulurken parmak kalkarsa kayıt başlamasın.
    private var pressActive = false

    init(
        recorder: VoiceRecording = VoiceRecorder(),
        session: AudioSessionControlling = ChatAudioSession.shared,
        directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("ChatVoice", isDirectory: true)
    ) {
        self.recorder = recorder
        self.session = session
        self.directory = directory
    }

    var isActive: Bool { phase != .idle }

    /// Parmak mikrofona bastığında.
    @discardableResult
    func begin() async -> Bool {
        guard phase == .idle else { return false }
        pressActive = true
        hint = nil
        guard await session.requestRecordPermission() else {
            pressActive = false
            hint = "Mikrofon izni yok. Ayarlar > FarvaTrack > Mikrofon'dan açabilirsin."
            return false
        }
        // İzin penceresi açıkken parmak kalktıysa başlatma.
        guard pressActive, phase == .idle else { return false }
        do {
            try session.activateForRecording()
            let url = directory.appendingPathComponent("\(UUID().uuidString).m4a")
            try recorder.start(at: url)
            fileURL = url
            levels = []
            elapsed = 0
            cancelProgress = 0
            lockProgress = 0
            phase = .recording
            startMetering()
            return true
        } catch {
            session.deactivate()
            hint = AppError.map(error).errorDescription
            return false
        }
    }

    /// Canlı dalga formu için bir örnek alır (zamanlayıcı ve testler çağırır).
    func sample() {
        guard isActive else { return }
        levels.append(VoiceWaveform.level(fromDecibels: recorder.currentPower()))
        elapsed = recorder.currentTime
        if elapsed >= Self.maximumDuration, let voice = finish() {
            onAutoFinish?(voice)
        }
    }

    /// Parmak sürüklendikçe: sola → iptal, yukarı → kilit.
    func dragChanged(_ translation: CGSize) {
        guard phase == .recording else { return }
        cancelProgress = min(1, max(0, Double(-translation.width / Self.cancelDistance)))
        lockProgress = min(1, max(0, Double(-translation.height / Self.lockDistance)))
        if translation.width <= -Self.cancelDistance {
            cancel()
        } else if translation.height <= -Self.lockDistance {
            phase = .locked
            cancelProgress = 0
            lockProgress = 1
        }
    }

    /// Parmak kalktığında: kilitli değilse kayıt biter ve gönderilecek ses döner.
    func release() -> RecordedVoice? {
        pressActive = false
        switch phase {
        case .recording: return finish()
        case .locked, .idle: return nil
        }
    }

    /// Kilitli kayıtta "Gönder".
    func finish() -> RecordedVoice? {
        guard isActive, let url = fileURL else { return nil }
        // Son örnek (otomatik bitirme denetimi olmadan; aksi halde kendini çağırırdı).
        levels.append(VoiceWaveform.level(fromDecibels: recorder.currentPower()))
        let duration = recorder.stop()
        let bars = VoiceWaveform.bars(from: levels)
        stopMetering()
        session.deactivate()
        resetState()
        guard duration >= Self.minimumDuration else {
            try? FileManager.default.removeItem(at: url)
            hint = "Kaydetmek için basılı tut"
            return nil
        }
        return RecordedVoice(fileURL: url, duration: duration, waveform: bars)
    }

    /// Kaydı bırakır ve dosyayı siler.
    func cancel() {
        pressActive = false
        guard isActive else { return }
        recorder.cancel()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        stopMetering()
        session.deactivate()
        resetState()
    }

    private func resetState() {
        phase = .idle
        fileURL = nil
        cancelProgress = 0
        lockProgress = 0
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.sampleInterval)
                guard !Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
    }
}

// MARK: - Oynatma

/// Sohbetteki sesli mesajları tek tek çalar; hız, ilerleme ve kulaklık/ahize geçişlerini yönetir.
@MainActor
@Observable
final class ChatAudioPlayer {
    private(set) var currentID: String?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: VoiceRate
    /// Telefon kulağa yakın: ahizeden çalıyor.
    private(set) var usingEarpiece = false
    var errorMessage: String?

    /// Bir mesaj ilk kez çalmaya başladığında (dinlendi bilgisi için).
    var onStartedPlaying: ((String) -> Void)?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    private let session: AudioSessionControlling
    private let proximity: ProximityMonitoring
    private let makeEngine: (URL) throws -> AudioPlaybackEngine
    private let defaults: UserDefaults
    @ObservationIgnored private var engine: AudioPlaybackEngine?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let notificationCenter: NotificationCenter

    private static let rateKey = "chat.voiceRate"

    init(
        session: AudioSessionControlling = ChatAudioSession.shared,
        proximity: ProximityMonitoring = DeviceProximityMonitor(),
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        makeEngine: @escaping (URL) throws -> AudioPlaybackEngine = { try AVAudioPlaybackEngine(url: $0) }
    ) {
        self.session = session
        self.proximity = proximity
        self.defaults = defaults
        self.makeEngine = makeEngine
        self.notificationCenter = notificationCenter
        self.rate = VoiceRate(rawValue: defaults.float(forKey: Self.rateKey)) ?? .normal

        observers = [
            notificationCenter.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
                MainActor.assumeIsolated { self?.handleRouteChange(reason) }
            },
            notificationCenter.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let began = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
                MainActor.assumeIsolated { self?.handleInterruption(began: began) }
            },
            notificationCenter.addObserver(forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleProximityChange() }
            }
        ]
    }

    deinit {
        observers.forEach { notificationCenter.removeObserver($0) }
    }

    func isCurrent(_ id: String) -> Bool { currentID == id }

    /// Oynat / duraklat. Başka bir mesaj çalıyorsa o durur.
    func toggle(id: String, url: URL) {
        if currentID == id, engine != nil {
            isPlaying ? pause() : resume()
            return
        }
        guard load(id: id, url: url) else { return }
        resume()
    }

    /// `fraction` (0…1) konumuna atlar; mesaj henüz yüklenmediyse duraklatılmış olarak yükler.
    func seek(id: String, url: URL, to fraction: Double) {
        if currentID != id || engine == nil {
            guard load(id: id, url: url) else { return }
        }
        guard let engine else { return }
        engine.currentTime = min(max(fraction, 0), 1) * engine.duration
        tick()
    }

    func cycleRate() {
        rate = rate.next
        defaults.set(rate.rawValue, forKey: Self.rateKey)
        engine?.rate = rate.rawValue
    }

    func pause() {
        engine?.pause()
        isPlaying = false
        stopTicker()
        proximity.setEnabled(false)
        tick()
    }

    func stop() {
        stopEngine(releaseSession: true)
    }

    /// Mesajlar arası geçişte oturum bırakılmaz (arka plandaki müzik bir anlığına devreye girmesin).
    private func stopEngine(releaseSession: Bool) {
        let hadEngine = engine != nil
        engine?.stop()
        engine = nil
        isPlaying = false
        currentID = nil
        currentTime = 0
        duration = 0
        stopTicker()
        proximity.setEnabled(false)
        usingEarpiece = false
        if releaseSession, hadEngine { session.deactivate() }
    }

    /// İlerlemeyi motordan okur (zamanlayıcı ve testler çağırır).
    func tick() {
        guard let engine else { return }
        currentTime = engine.currentTime
        duration = engine.duration
    }

    // MARK: Yardımcılar

    @discardableResult
    private func load(id: String, url: URL) -> Bool {
        stopEngine(releaseSession: false)
        do {
            let engine = try makeEngine(url)
            engine.rate = rate.rawValue
            engine.onFinish = { [weak self] in
                Task { @MainActor in self?.handleFinish() }
            }
            self.engine = engine
            currentID = id
            duration = engine.duration
            currentTime = 0
            return true
        } catch {
            errorMessage = "Sesli mesaj çalınamadı."
            return false
        }
    }

    private func resume() {
        guard let engine, let id = currentID else { return }
        do {
            let near = proximity.isNear && !session.isExternalOutputConnected
            try session.activateForPlayback(useEarpiece: near)
            usingEarpiece = near
        } catch {
            // Oturum ayarlanamasa da varsayılan çıkıştan çalmayı dene.
        }
        // Sondan yeniden başlatılırsa baştan çalsın.
        if engine.duration > 0, engine.currentTime >= engine.duration - 0.05 { engine.currentTime = 0 }
        engine.rate = rate.rawValue
        guard engine.play() else {
            errorMessage = "Sesli mesaj çalınamadı."
            return
        }
        isPlaying = true
        // Kulaklık yoksa yakınlık sensörü açılır: kulağa götürünce ahizeye geçer.
        proximity.setEnabled(!session.isExternalOutputConnected)
        startTicker()
        onStartedPlaying?(id)
    }

    func handleFinish() {
        engine?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTicker()
        proximity.setEnabled(false)
        usingEarpiece = false
        session.deactivate()
    }

    func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason?) {
        switch reason {
        case .oldDeviceUnavailable:
            // Kulaklık çıkarıldı: sesin aniden hoparlörden yüksek çıkmaması için duraklat.
            if isPlaying { pause() }
        case .newDeviceAvailable:
            // Kulaklık takıldı: ahizedeysek normal çalmaya geç, yakınlık sensörü gereksiz.
            if usingEarpiece {
                try? session.activateForPlayback(useEarpiece: false)
                usingEarpiece = false
            }
            if isPlaying { proximity.setEnabled(false) }
        default:
            break
        }
    }

    func handleInterruption(began: Bool) {
        // Gelen arama vb.: duraklat; kullanıcı kendisi devam ettirir.
        if began, isPlaying { pause() }
    }

    func handleProximityChange() {
        guard isPlaying, !session.isExternalOutputConnected else { return }
        let near = proximity.isNear
        guard near != usingEarpiece else { return }
        do {
            try session.activateForPlayback(useEarpiece: near)
            usingEarpiece = near
        } catch {}
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
