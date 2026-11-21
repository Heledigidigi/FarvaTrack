import Foundation
import AVFoundation
import UIKit

// MARK: - Ses oturumu

/// AVAudioSession'ı kayıt ve oynatma için ayarlar; testlerde sahte uygulamayla değiştirilir.
protocol AudioSessionControlling: AnyObject {
    /// Mikrofon izni (gerekirse sorar).
    func requestRecordPermission() async -> Bool
    func activateForRecording() throws
    /// `useEarpiece`: telefon kulağa yakınken ahizeden çal.
    func activateForPlayback(useEarpiece: Bool) throws
    func deactivate()
    /// Kablolu/Bluetooth kulaklık ya da araba gibi harici bir çıkış bağlı mı.
    var isExternalOutputConnected: Bool { get }
}

final class ChatAudioSession: AudioSessionControlling {
    static let shared = ChatAudioSession()
    private var session: AVAudioSession { .sharedInstance() }

    func requestRecordPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func activateForRecording() throws {
        // Hoparlörden çalmaya devam eder (ahizeye düşmez); Bluetooth kulaklığın mikrofonu da kullanılabilir.
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        try? session.setPreferredSampleRate(VoiceRecorder.sampleRate)
        try session.setActive(true)
    }

    func activateForPlayback(useEarpiece: Bool) throws {
        if useEarpiece {
            // Telefon kulakta: ahize (alıcı). Kategori `.playAndRecord` + varsayılan çıkış.
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.overrideOutputAudioPort(.none)
        } else {
            // `.playback`: sessiz mod anahtarı açıkken de çalar (sesli mesaj bilerek başlatılır);
            // kulaklık takılıysa sistem oradan çalar.
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
        }
        try session.setActive(true)
    }

    func deactivate() {
        // Başka uygulamanın (müzik vb.) sesi kaldığı yerden devam etsin.
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    var isExternalOutputConnected: Bool {
        let external: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio, .airPlay, .usbAudio, .HDMI]
        return session.currentRoute.outputs.contains { external.contains($0.portType) }
    }
}

// MARK: - Kayıt

protocol VoiceRecording: AnyObject {
    /// Kaydı `url` konumuna başlatır.
    func start(at url: URL) throws
    /// Anlık ses seviyesi (dBFS).
    func currentPower() -> Float
    var currentTime: TimeInterval { get }
    /// Kaydı bitirir; süreyi döndürür.
    func stop() -> TimeInterval
    /// Kaydı bırakır, dosyayı siler.
    func cancel()
}

/// AVAudioRecorder: AAC (.m4a), 48 kHz, mono.
final class VoiceRecorder: NSObject, VoiceRecording {
    static let sampleRate: Double = 48_000
    static let bitRate = 64_000

    /// Kayıt ayarları (testlerde aynı ayarlarla dosya yazılıp doğrulanır).
    static var settings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }

    private var recorder: AVAudioRecorder?

    func start(at url: URL) throws {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw AppError.invalidInput("Kayıt başlatılamadı. Mikrofon başka bir uygulama tarafından kullanılıyor olabilir.")
        }
        self.recorder = recorder
    }

    func currentPower() -> Float {
        guard let recorder else { return -160 }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }

    var currentTime: TimeInterval { recorder?.currentTime ?? 0 }

    func stop() -> TimeInterval {
        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        return duration
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
    }
}

// MARK: - Oynatma

protocol AudioPlaybackEngine: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var rate: Float { get set }
    var isPlaying: Bool { get }
    /// Dosya sonuna gelince çağrılır.
    var onFinish: (() -> Void)? { get set }
    @discardableResult func play() -> Bool
    func pause()
    func stop()
}

/// AVAudioPlayer sarmalayıcısı; hız ayarı (`enableRate`) açıktır.
final class AVAudioPlaybackEngine: NSObject, AudioPlaybackEngine, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onFinish: (() -> Void)?

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.enableRate = true
        player.delegate = self
        player.prepareToPlay()
    }

    var duration: TimeInterval { player.duration }
    var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }
    var rate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }
    var isPlaying: Bool { player.isPlaying }

    func play() -> Bool { player.play() }
    func pause() { player.pause() }
    func stop() { player.stop() }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}

/// Telefonun kulağa yaklaştığını bildiren yakınlık sensörü (testlerde sahte).
protocol ProximityMonitoring: AnyObject {
    var isNear: Bool { get }
    func setEnabled(_ enabled: Bool)
}

final class DeviceProximityMonitor: ProximityMonitoring {
    var isNear: Bool { UIDevice.current.proximityState }

    func setEnabled(_ enabled: Bool) {
        UIDevice.current.isProximityMonitoringEnabled = enabled
    }
}
