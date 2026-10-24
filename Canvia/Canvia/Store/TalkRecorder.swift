// Present and record's capture: the microphone, and the front camera when
// it is on, through one AVCaptureSession, each written by an AVAssetWriter —
// the voice as AAC in an .m4a (44.1 kHz, one channel, as VoiceRecorder
// writes it), the camera as H.264 in an .mp4, upright and mirrored as the
// presenter sees themselves. Pausing drops what comes in and takes the gap
// out of both files' clocks, so a talk paused for a minute plays on without
// a minute of silence. A call or another app taking the microphone pauses
// it (`onInterrupted`). The Android twin records the same with Camera2 and
// MediaRecorder.

import AVFoundation
import SwiftUI
import UIKit

final class TalkRecorder: NSObject, @unchecked Sendable,
    AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    enum Problem: Error {
        case microphone
        case writer
    }

    let session = AVCaptureSession()
    /// Called on the main queue when the talk is interrupted, to pause it.
    var onInterrupted: (() -> Void)?

    private let queue = DispatchQueue(label: "canvia.talk.capture")
    private let audioOutput = AVCaptureAudioDataOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var cameraInput: AVCaptureDeviceInput?
    private var observers: [NSObjectProtocol] = []

    // Touched on `queue` only.
    private var audioWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var videoWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var cameraURL: URL?
    private var recording = false
    private var paused = false
    private var resuming = false
    private var offset = CMTime.zero
    private var lastTime: CMTime?
    private var audioStarted = false
    private var videoStarted = false

    /// The voice's file settings: AAC in MPEG-4, 44.1 kHz, mono.
    static let audioSettings: [String: Any] = VoiceRecorder.settings

    // MARK: setting up

    /// The microphone — `microphone`, a port of the audio session, or the
    /// phone's own — and the front camera when `camera`, into the session.
    func configure(camera: Bool, microphone: AVAudioSessionPortDescription?) throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
        try audio.setActive(true)
        try? audio.setPreferredInput(microphone)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.automaticallyConfiguresApplicationAudioSession = false
        session.usesApplicationAudioSession = true
        session.sessionPreset = .medium
        guard let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) else {
            throw Problem.microphone
        }
        session.addInput(input)
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
            audioOutput.setSampleBufferDelegate(self, queue: queue)
        }
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: queue)
        }
        attachCamera(camera)
        watchInterruptions()
    }

    /// The front camera on or off; off, the talk is the voice alone.
    func setCamera(_ on: Bool) {
        session.beginConfiguration()
        attachCamera(on)
        session.commitConfiguration()
    }

    private func attachCamera(_ on: Bool) {
        if let cameraInput {
            session.removeInput(cameraInput)
            self.cameraInput = nil
        }
        guard on, let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: front), session.canAddInput(input) else { return }
        session.addInput(input)
        cameraInput = input
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }

    var hasCamera: Bool { cameraInput != nil }

    func startPreview() {
        let session = self.session
        queue.async { if !session.isRunning { session.startRunning() } }
    }

    // MARK: recording

    /// Starts writing the voice to `audioURL`, and the camera, when it is
    /// on, to `cameraURL`.
    func begin(audioURL: URL, cameraURL: URL) throws {
        try? FileManager.default.removeItem(at: audioURL)
        try? FileManager.default.removeItem(at: cameraURL)
        let writer = try AVAssetWriter(outputURL: audioURL, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw Problem.writer }
        writer.add(input)
        guard writer.startWriting() else { throw Problem.writer }
        let camera = hasCamera
        queue.sync {
            audioWriter = writer
            audioInput = input
            self.cameraURL = camera ? cameraURL : nil
            videoWriter = nil
            videoInput = nil
            offset = .zero
            lastTime = nil
            audioStarted = false
            videoStarted = false
            paused = false
            resuming = false
            recording = true
        }
    }

    func pause() { queue.async { self.paused = true } }

    func resume() {
        queue.async {
            self.paused = false
            self.resuming = true
        }
    }

    /// Stops, and hands back the voice's file and the camera's — each nil
    /// when nothing of it was written.
    func finish() async -> (audio: URL?, camera: URL?) {
        let parts: (AVAssetWriter?, AVAssetWriterInput?, Bool, AVAssetWriter?, AVAssetWriterInput?, Bool) = queue.sync {
            recording = false
            return (audioWriter, audioInput, audioStarted, videoWriter, videoInput, videoStarted)
        }
        var audioURL: URL?
        var cameraURL: URL?
        if let writer = parts.0 {
            if parts.2 {
                parts.1?.markAsFinished()
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    writer.finishWriting { done.resume() }
                }
                if writer.status == .completed { audioURL = writer.outputURL }
            } else {
                writer.cancelWriting()
            }
        }
        if let writer = parts.3 {
            if parts.5 {
                parts.4?.markAsFinished()
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    writer.finishWriting { done.resume() }
                }
                if writer.status == .completed { cameraURL = writer.outputURL }
            } else {
                writer.cancelWriting()
            }
        }
        stop()
        return (audioURL, cameraURL)
    }

    /// Stops and throws away whatever was recorded.
    func cancel() {
        let writers: [AVAssetWriter] = queue.sync {
            recording = false
            return [audioWriter, videoWriter].compactMap { $0 }
        }
        for writer in writers {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: writer.outputURL)
        }
        stop()
    }

    /// The camera and microphone let go, and other apps told.
    func stop() {
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func watchInterruptions() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let interrupted: (Notification) -> Void = { [weak self] _ in self?.onInterrupted?() }
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session,
                                            queue: .main, using: interrupted))
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue { self?.onInterrupted?() }
        })
    }

    // MARK: samples

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard recording, !paused else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        // The gap a pause left, taken out of the clock from here on.
        if resuming, let last = lastTime {
            offset = CMTimeAdd(offset, CMTimeSubtract(time, last))
            resuming = false
        }
        lastTime = time
        guard let buffer = Self.retimed(sampleBuffer, by: offset) else { return }
        let at = CMSampleBufferGetPresentationTimeStamp(buffer)
        if output === audioOutput {
            guard let writer = audioWriter, let input = audioInput else { return }
            if !audioStarted {
                writer.startSession(atSourceTime: at)
                audioStarted = true
            }
            if input.isReadyForMoreMediaData { input.append(buffer) }
        } else if output === videoOutput {
            guard let input = videoInput(for: sampleBuffer), let writer = videoWriter else { return }
            if !videoStarted {
                writer.startSession(atSourceTime: at)
                videoStarted = true
            }
            if input.isReadyForMoreMediaData { input.append(buffer) }
        }
    }

    /// The camera's writer, made from the first frame's size.
    private func videoInput(for sample: CMSampleBuffer) -> AVAssetWriterInput? {
        if let videoInput { return videoInput }
        guard let url = cameraURL, let pixels = CMSampleBufferGetImageBuffer(sample),
              let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: CVPixelBufferGetWidth(pixels),
            AVVideoHeightKey: CVPixelBufferGetHeight(pixels),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        videoWriter = writer
        videoInput = input
        return input
    }

    /// `buffer` moved `offset` earlier.
    private static func retimed(_ buffer: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        guard offset != .zero else { return buffer }
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return buffer }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        for i in timing.indices {
            timing[i].presentationTimeStamp = CMTimeSubtract(timing[i].presentationTimeStamp, offset)
            if timing[i].decodeTimeStamp.isValid {
                timing[i].decodeTimeStamp = CMTimeSubtract(timing[i].decodeTimeStamp, offset)
            }
        }
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: buffer, sampleTimingEntryCount: count,
                                              sampleTimingArray: &timing, sampleBufferOut: &out)
        return out
    }

    // MARK: permission

    /// Asks for the microphone and, when wanted, the camera — the system
    /// asks only the first time — and says which may be used.
    static func requestAccess(camera: Bool) async -> (microphone: Bool, camera: Bool) {
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard camera else { return (mic, false) }
        let cam = await AVCaptureDevice.requestAccess(for: .video)
        return (mic, cam)
    }

    /// The microphones the phone has now: its own, a headset, AirPods.
    static var microphones: [AVAudioSessionPortDescription] {
        AVAudioSession.sharedInstance().availableInputs ?? []
    }
}

/// The front camera as the presenter sees it.
struct TalkCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview?.session = session
        view.preview?.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}
