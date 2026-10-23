// Automatic captions, from the phone's own speech recognition — on the
// device, never sent anywhere: SFSpeechURLRecognitionRequest with
// requiresOnDeviceRecognition, where the recogniser supports it. The part
// of the clip or voice-over heard is written out as an m4a first
// (AVAssetExportSession), the words come back timed from its start, and
// Captions.fromWords groups them into cues. Where the phone cannot, the
// sheet says so and offers an .srt or typing instead — the Android twin's
// CaptionsRecognizer, the same words.

import AVFoundation
import Foundation
import Speech

enum CaptionSpeech {

    static let unavailableNote = tr("Automatic captions aren't available on this phone — import an .srt file or type them")
    static let unreadableNote = tr("Couldn't read the sound.")
    static let nothingHeardNote = tr("No speech was heard.")
    static let workingNote = tr("Generating captions…")

    enum SpeechFailure: LocalizedError {
        case unavailable
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unavailable: return CaptionSpeech.unavailableNote
            case .unreadable: return CaptionSpeech.unreadableNote
            }
        }
    }

    /// Whether this phone can caption a clip by itself: a recogniser for
    /// `language` (the design's, BCP-47) or the phone's own that works on
    /// the device.
    static func isAvailable(language: String? = nil) -> Bool {
        recognizer(language: language)?.supportsOnDeviceRecognition == true
    }

    /// The recogniser for `language` when the phone has one, else its own.
    private static func recognizer(language: String?) -> SFSpeechRecognizer? {
        language.flatMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) } ?? SFSpeechRecognizer()
    }

    /// The cues for the words said in `audio` between `from` and `to`
    /// seconds, timed from `from` — or why there are none. Asks for the
    /// speech permission first.
    static func transcribe(_ audio: URL, from: Double, to: Double, language: String? = nil) async throws -> [CaptionCue] {
        guard let recognizer = recognizer(language: language), recognizer.supportsOnDeviceRecognition else {
            throw SpeechFailure.unavailable
        }
        guard await authorised() else { throw SpeechFailure.unavailable }
        guard to - from > 0.05 else { return [] }
        let heard = try await extract(audio, from: from, to: to)
        defer { try? FileManager.default.removeItem(at: heard) }
        let words = try await listen(recognizer, to: heard)
        return Captions.fromWords(words)
    }

    private static func authorised() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    /// `audio`'s sound from `from` to `to` seconds as an m4a of its own in
    /// the temporary directory.
    static func extract(_ audio: URL, from: Double, to: Double) async throws -> URL {
        let asset = AVURLAsset(url: audio)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SpeechFailure.unreadable
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("captions-\(UUID().uuidString).m4a")
        session.outputURL = out
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(start: CMTime(seconds: max(0, from), preferredTimescale: 600),
                                        end: CMTime(seconds: max(from, to), preferredTimescale: 600))
        await session.export()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: out)
            throw SpeechFailure.unreadable
        }
        return out
    }

    /// The words `recognizer` hears in the file at `url`, each timed from
    /// the file's start, on the device.
    private static func listen(_ recognizer: SFSpeechRecognizer, to url: URL) async throws -> [Captions.Word] {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let words = result.bestTranscription.segments.map {
                        Captions.Word(start: $0.timestamp, text: $0.substring)
                    }
                    once.run { continuation.resume(returning: words) }
                } else if error != nil {
                    // Silence is no failure: there are no words.
                    once.run { continuation.resume(returning: []) }
                }
            }
        }
    }

    /// Runs its closure the first time only: a task's handler may be
    /// called again after its final result.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func run(_ work: () -> Void) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { work() }
        }
    }
}
