// Speaking a text element: the words arrive as they are recognised and
// land in the selected text, so a caption can be said rather than typed.
// On-device where the system allows it; the keyboard's own microphone is
// always there too.

import AVFoundation
import Foundation
import Observation
import Speech

@Observable
final class Dictation {

    static let shared = Dictation()

    var isListening = false
    var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()

    /// Whether this device and locale can recognise speech at all.
    static var isAvailable: Bool { SFSpeechRecognizer()?.isAvailable ?? false }

    /// The dictated words appended to what was there, one space apart.
    static func merge(_ existing: String, _ spoken: String) -> String {
        let base = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return base }
        return base.isEmpty ? words : base + " " + words
    }

    /// Starts listening; `onText` gets the transcript so far and whether it
    /// is final. Asks for the speech and microphone permissions first.
    func start(onText: @escaping (String, Bool) -> Void) {
        guard !isListening else { return }
        error = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            guard status == .authorized else {
                DispatchQueue.main.async { self.error = "Speech recognition is not allowed. You can turn it on in Settings." }
                return
            }
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    guard granted else { self.error = "The microphone is not allowed. You can turn it on in Settings."; return }
                    self.begin(onText: onText)
                }
            }
        }
    }

    private func begin(onText: @escaping (String, Bool) -> Void) {
        guard let recognizer, recognizer.isAvailable else { error = "Speech recognition is not available right now."; return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "The microphone could not be started."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { self.error = "The microphone could not be started."; return }
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, err in
            if let result {
                onText(result.bestTranscription.formattedString, result.isFinal)
                if result.isFinal { DispatchQueue.main.async { self?.stop() } }
            }
            if err != nil { DispatchQueue.main.async { self?.stop() } }
        }
    }

    func stop() {
        guard isListening || engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
