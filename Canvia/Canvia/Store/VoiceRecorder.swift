// A voice-over from the microphone: AAC in an .m4a file at 44.1 kHz, one
// channel, as the Android twin's MediaRecorder writes it, with the level
// read twenty times a second for the meter. The Audio sheet counts down,
// plays the design and keeps the file as an audio upload and a track.
//
// The recorder has the phone's sound while it records — PageSound and
// dictation leave it alone — and lets it go, and other apps know, when it
// stops.

import AVFoundation
import Foundation
import Observation

@Observable
final class VoiceRecorder {

    static let shared = VoiceRecorder()

    private(set) var isRecording = false
    /// How loud the microphone is now, 0...1, for the meter.
    private(set) var level = 0.0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meter: Task<Void, Never>?

    /// What the file is: AAC in MPEG-4, 44.1 kHz, mono.
    static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    /// The quietest a meter shows anything for, in decibels.
    static let meterFloor = -50.0

    /// A level in decibels (0 is full) as the meter shows it: nothing at
    /// `meterFloor` or below, full at 0, evenly between.
    static func meterLevel(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(max((decibels - meterFloor) / -meterFloor, 0), 1)
    }

    /// Asks for the microphone — the system asks only the first time — and
    /// says whether it may be used.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in done.resume(returning: granted) }
        }
    }

    /// Starts recording into a fresh file; false when the microphone could
    /// not be started, or is busy with dictation.
    func start() -> Bool {
        guard !isRecording, !Dictation.shared.isListening else { return false }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-over-\(UUID().uuidString).m4a")
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                try? FileManager.default.removeItem(at: url)
                letGo()
                return false
            }
            self.recorder = recorder
        } catch {
            letGo()
            return false
        }
        isRecording = true
        level = 0
        meter = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let recorder = self.recorder, !Task.isCancelled else { return }
                recorder.updateMeters()
                self.level = VoiceRecorder.meterLevel(decibels: Double(recorder.averagePower(forChannel: 0)))
            }
        }
        return true
    }

    /// Stops, and hands back the file recorded — the caller's to keep or
    /// remove — or nil when nothing was.
    func stop() -> URL? {
        guard let recorder else { return nil }
        let url = recorder.url
        let seconds = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        finish()
        guard seconds > AudioTrack.minLength else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    /// Stops and throws the recording away.
    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        self.recorder = nil
        finish()
    }

    private func finish() {
        meter?.cancel()
        meter = nil
        isRecording = false
        level = 0
        letGo()
    }

    private func letGo() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
