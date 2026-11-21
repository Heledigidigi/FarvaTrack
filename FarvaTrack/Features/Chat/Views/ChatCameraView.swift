import SwiftUI
import AVFoundation
import AVKit

// MARK: - Kamera denetleyicisi

/// AVFoundation oturumu: fotoğraf (HEVC/HEIC destekleniyorsa) ve video (.mov) çekimi.
@MainActor
@Observable
final class ChatCameraModel: NSObject {
    enum FlashMode: CaseIterable {
        case off, on, auto

        var systemImage: String {
            switch self {
            case .off: return "bolt.slash.fill"
            case .on: return "bolt.fill"
            case .auto: return "bolt.badge.automatic.fill"
            }
        }

        var accessibilityText: String {
            switch self {
            case .off: return "Flaş kapalı"
            case .on: return "Flaş açık"
            case .auto: return "Flaş otomatik"
            }
        }

        var next: FlashMode {
            switch self {
            case .off: return .auto
            case .auto: return .on
            case .on: return .off
            }
        }
    }

    enum State: Equatable {
        case idle, unavailable(String), ready, recording
    }

    private(set) var state: State = .idle
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var recordingStarted: Date?
    var flash: FlashMode = .off
    /// Çekilen dosya (önizleme ekranına geçilir).
    private(set) var captured: PickedMedia?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    /// Son fotoğraf HEVC (HEIC) olarak mı istendi.
    private var photoIsHEVC = false
    private let sessionQueue = DispatchQueue(label: "farvatrack.chat.camera")

    /// Videoda en fazla süre.
    static let maxVideoDuration: TimeInterval = 3 * 60

    func start() async {
        guard state == .idle || state == .ready else { return }
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            state = .unavailable("Kamera izni verilmedi. Ayarlar > FarvaTrack > Kamera'dan açabilirsin.")
            return
        }
        // Mikrofon izni yalnızca videodaki ses için; reddedilirse sessiz video çekilir.
        let hasMicrophone = await AVCaptureDevice.requestAccess(for: .audio)
        do {
            try configure(position: position, withAudio: hasMicrophone)
            let session = session
            sessionQueue.async { session.startRunning() }
            state = .ready
        } catch {
            state = .unavailable("Bu cihazda kamera kullanılamıyor.")
        }
    }

    func stop() {
        let session = session
        sessionQueue.async { if session.isRunning { session.stopRunning() } }
        if state == .recording { movieOutput.stopRecording() }
    }

    private func configure(position: AVCaptureDevice.Position, withAudio: Bool) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        if let videoInput { session.removeInput(videoInput) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw AppError.invalidInput("Kamera bulunamadı.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw AppError.invalidInput("Kamera açılamadı.") }
        session.addInput(input)
        videoInput = input

        if withAudio, !session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }),
           let mic = AVCaptureDevice.default(for: .audio), let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            movieOutput.maxRecordedDuration = CMTime(seconds: Self.maxVideoDuration, preferredTimescale: 600)
        }
        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = position == .front }
            // HEVC destekleniyorsa kayıt HEVC olur (kalite kaybı olmadan daha küçük dosya).
            if movieOutput.availableVideoCodecTypes.contains(.hevc) {
                movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
            }
        }
        if let connection = photoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = position == .front
        }
    }

    var isFlashAvailable: Bool {
        videoInput?.device.hasFlash ?? false
    }

    func switchCamera() {
        guard state == .ready else { return }
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        let hasAudio = session.inputs.contains { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }
        do {
            try configure(position: newPosition, withAudio: hasAudio)
            position = newPosition
        } catch {
            try? configure(position: position, withAudio: hasAudio)
        }
    }

    // MARK: Fotoğraf

    func capturePhoto() {
        guard state == .ready else { return }
        let settings: AVCapturePhotoSettings
        photoIsHEVC = photoOutput.availablePhotoCodecTypes.contains(.hevc)
        if photoIsHEVC {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        if isFlashAvailable, photoOutput.supportedFlashModes.contains(flash.captureMode) {
            settings.flashMode = flash.captureMode
        }
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    fileprivate func finishPhoto(data: Data?) {
        guard let data else { return }
        let url = Self.temporaryURL(ext: photoIsHEVC ? "heic" : "jpg")
        do {
            try data.write(to: url)
            captured = PickedMedia(fileURL: url, kind: .image)
        } catch {
            state = .unavailable("Fotoğraf kaydedilemedi.")
        }
    }

    // MARK: Video

    func startRecording() {
        guard state == .ready, !movieOutput.isRecording else { return }
        setTorch(flash == .on)
        let url = Self.temporaryURL(ext: "mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        state = .recording
        recordingStarted = .now
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    fileprivate func finishRecording(url: URL, error: Error?) {
        setTorch(false)
        state = .ready
        recordingStarted = nil
        // Süre sınırına ulaşınca da "hata" gelir ama dosya geçerlidir.
        let reachedLimit = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
        guard error == nil || reachedLimit, FileManager.default.fileExists(atPath: url.path) else { return }
        captured = PickedMedia(fileURL: url, kind: .video)
    }

    private func setTorch(_ on: Bool) {
        guard let device = videoInput?.device, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    /// Önizlemeden "Yeniden çek".
    func discardCapture() {
        if let captured { try? FileManager.default.removeItem(at: captured.fileURL) }
        captured = nil
    }

    /// Gönderildi: dosya artık gönderim sırasına aittir.
    func releaseCapture() {
        captured = nil
    }

    private static func temporaryURL(ext: String) -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChatPicked", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }
}

private extension ChatCameraModel.FlashMode {
    var captureMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .on: return .on
        case .auto: return .auto
        }
    }
}

extension ChatCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        Task { @MainActor in self.finishPhoto(data: data) }
    }
}

extension ChatCameraModel: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in self.finishRecording(url: outputFileURL, error: error) }
    }
}

// MARK: - Kamera önizleme katmanı

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Kamera ekranı

struct ChatCameraView: View {
    let onSend: (PickedMedia, ChatMediaQuality) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera = ChatCameraModel()
    @State private var isPressing = false
    @State private var quality: ChatMediaQuality = .original

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let captured = camera.captured {
                review(captured)
            } else {
                capture
            }
        }
        .statusBarHidden()
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    // MARK: Çekim

    private var capture: some View {
        ZStack {
            switch camera.state {
            case .unavailable(let message):
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(Color.ftTextSecondary)
                    Text(message).multilineTextAlignment(.center).foregroundStyle(.white)
                }
                .padding(32)
            default:
                CameraPreviewLayer(session: camera.session)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.title2.weight(.semibold))
                    }
                    .accessibilityLabel("Kamerayı kapat")
                    Spacer()
                    if camera.state == .recording, let started = camera.recordingStarted {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            let seconds = Int(context.date.timeIntervalSince(started))
                            Label(String(format: "%d:%02d", seconds / 60, seconds % 60), systemImage: "record.circle")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.ftDanger, in: Capsule())
                        }
                        .accessibilityLabel("Kaydediliyor")
                    }
                    Spacer()
                    if camera.isFlashAvailable {
                        Button {
                            camera.flash = camera.flash.next
                            Haptics.selection()
                        } label: {
                            Image(systemName: camera.flash.systemImage).font(.title2)
                        }
                        .accessibilityLabel(camera.flash.accessibilityText)
                        .accessibilityHint("Değiştirmek için dokun")
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                Text("Fotoğraf için dokun, video için basılı tut")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .opacity(camera.state == .ready ? 1 : 0)

                HStack {
                    Color.clear.frame(width: 52, height: 52)
                    Spacer()
                    shutter
                    Spacer()
                    Button {
                        camera.switchCamera()
                        Haptics.selection()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                            .font(.title2)
                            .frame(width: 52, height: 52)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    .foregroundStyle(.white)
                    .disabled(camera.state != .ready)
                    .accessibilityLabel(camera.position == .back ? "Ön kameraya geç" : "Arka kameraya geç")
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
    }

    private var shutter: some View {
        let recording = camera.state == .recording
        return ZStack {
            Circle().stroke(.white, lineWidth: 5).frame(width: 78, height: 78)
            Circle()
                .fill(recording ? Color.ftDanger : .white)
                .frame(width: recording ? 40 : 64, height: recording ? 40 : 64)
                .animation(.spring(response: 0.3), value: recording)
        }
        .scaleEffect(isPressing ? 1.12 : 1)
        .animation(.spring(response: 0.25), value: isPressing)
        .contentShape(Circle())
        // Dokun: fotoğraf. Basılı tut (0,35 sn): video; bırakınca biter.
        .onTapGesture {
            guard camera.state == .ready else { return }
            Haptics.impact(.light)
            camera.capturePhoto()
        }
        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 60) {
            Haptics.impact(.medium)
            camera.startRecording()
        } onPressingChanged: { pressing in
            isPressing = pressing
            if !pressing, camera.state == .recording {
                camera.stopRecording()
                Haptics.impact(.light)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(recording ? "Kaydı durdur" : "Deklanşör")
        .accessibilityHint("Fotoğraf için dokun, video için basılı tut")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Fotoğraf çek") { camera.capturePhoto() }
        .accessibilityAction(named: recording ? "Videoyu bitir" : "Video kaydet") {
            recording ? camera.stopRecording() : camera.startRecording()
        }
    }

    // MARK: Önizleme → gönder

    private func review(_ media: PickedMedia) -> some View {
        VStack(spacing: 0) {
            Group {
                if media.kind == .video {
                    LoopingVideoPlayer(url: media.fileURL)
                } else {
                    CachedImageView(url: media.fileURL, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            VStack(spacing: 14) {
                Picker("Kalite", selection: $quality) {
                    ForEach(ChatMediaQuality.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Gönderim kalitesi")

                HStack(spacing: 12) {
                    Button {
                        camera.discardCapture()
                    } label: {
                        Label("Yeniden çek", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button {
                        Haptics.impact(.medium)
                        camera.releaseCapture()
                        onSend(media, quality)
                        dismiss()
                    } label: {
                        Label("Gönder", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ftAccent)
                }
            }
            .padding(20)
            .background(Color.ftCard)
        }
    }
}

/// Kamerada çekilen videonun sessiz döngülü önizlemesi.
struct LoopingVideoPlayer: View {
    let url: URL
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let queue = AVQueuePlayer()
                looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                player = queue
                queue.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
                looper = nil
            }
            .accessibilityLabel("Çekilen video")
    }
}
