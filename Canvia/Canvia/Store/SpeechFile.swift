// Text to speech made into a file: the words read offline by one of the
// phone's voices (AVSpeechSynthesizer.write), a sentence-cut piece at a time
// (Narration.utterances), the pieces' sound written one after another into
// a .caf, then made AAC in an .m4a as the audio export makes one, and kept
// in AudioStore as an upload. Preview speaks the same words aloud with the
// same voice, speed and pitch.

import AVFoundation
import Foundation

final class SpeechFile {

    static let shared = SpeechFile()

    /// Why the words did not become a file.
    enum Failure: Error {
        /// The phone has no voice for the app's language.
        case noVoice
        /// The voice gave back no sound for the words.
        case unread
        /// The sound could not be written or kept.
        case unkept
    }

    private let speaker = AVSpeechSynthesizer()
    /// The one that writes, apart from the one that previews, so a preview
    /// never cuts a file short.
    private let writer = AVSpeechSynthesizer()

    // MARK: voices

    /// Every voice on the phone, by its identifier, name and language.
    static func installedVoices() -> [Narration.Voice] {
        AVSpeechSynthesisVoice.speechVoices().map {
            Narration.Voice(id: $0.identifier, name: $0.name, language: $0.language)
        }
    }

    /// The voices offered in the app's language (Narration.voicesFor).
    static func voicesForApp() -> [Narration.Voice] {
        Narration.voicesFor(installedVoices(), language: AppLanguage.current())
    }

    /// The voice `spec` names, else the first offered in the app's
    /// language; nil when there is none.
    static func voice(for spec: Narration.Spec) -> AVSpeechSynthesisVoice? {
        if !spec.voice.isEmpty, let named = AVSpeechSynthesisVoice(identifier: spec.voice) { return named }
        return voicesForApp().first.flatMap { AVSpeechSynthesisVoice(identifier: $0.id) }
    }

    /// One piece of the words as the voice is handed it: the speed a share
    /// of the default rate — twice the voice's own at the most it takes —
    /// and the pitch as it is, both within what AVSpeechUtterance allows.
    static func utterance(_ text: String, spec: Narration.Spec, voice: AVSpeechSynthesisVoice) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let rate = Float(Narration.clamped(spec.rate)) * AVSpeechUtteranceDefaultSpeechRate
        utterance.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = Float(Narration.clamped(spec.pitch))
        return utterance
    }

    // MARK: preview

    /// `spec` read aloud now, from the start; anything previewing stops.
    func preview(_ spec: Narration.Spec) throws {
        stopPreview()
        guard let voice = Self.voice(for: spec) else { throw Failure.noVoice }
        for piece in Narration.utterances(spec.text) {
            speaker.speak(Self.utterance(piece, spec: spec, voice: voice))
        }
    }

    func stopPreview() {
        if speaker.isSpeaking { speaker.stopSpeaking(at: .immediate) }
    }

    // MARK: the file

    /// `spec` read into a new AAC file in AudioStore, named `name` there,
    /// and its id; the temporary files are taken away either way.
    func make(_ spec: Narration.Spec, name: String) async throws -> String {
        guard let voice = Self.voice(for: spec) else { throw Failure.noVoice }
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: raw) }
        var file: AVAudioFile?
        for piece in Narration.utterances(spec.text) {
            try await write(Self.utterance(piece, spec: spec, voice: voice), into: &file, at: raw)
        }
        guard file != nil else { throw Failure.unread }
        // Cancelled while the last piece was read: nothing is kept.
        try Task.checkCancellation()
        // Closed before it is read: an AVAudioFile writes its header as it
        // goes away.
        file = nil
        let aac = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: aac) }
        try await Self.encode(raw, to: aac)
        guard let id = AudioStore.store(aac, name: name) else { throw Failure.unkept }
        return id
    }

    /// One utterance's sound appended to `file` — opened at `url` on its
    /// first buffer, in the voice's own format — until the voice hands back
    /// an empty buffer, its end. A voice that never does — none is handed
    /// back on an error — is stopped after its time (Narration.writeTimeout)
    /// and the words taken as unread; cancelled, it stops at once.
    private func write(_ utterance: AVSpeechUtterance, into file: inout AVAudioFile?, at url: URL) async throws {
        let heard = Heard()
        let limit = Narration.writeTimeout(utterance.speechString)
        let clock = Task {
            try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
            heard.finish(whole: false)
        }
        defer { clock.cancel() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                heard.wait(continuation)
                // Handed back on the voice's own thread, so tied to no actor.
                writer.write(utterance) { @Sendable buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    if pcm.frameLength == 0 {
                        heard.finish(whole: true)
                    } else {
                        heard.append(pcm)
                    }
                }
            }
        } onCancel: {
            heard.finish(whole: false)
        }
        guard heard.whole else {
            writer.stopSpeaking(at: .immediate)
            try Task.checkCancellation()
            throw Failure.unread
        }
        for pcm in heard.buffers {
            do {
                if file == nil {
                    file = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                           commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
                }
                try file?.write(from: pcm)
            } catch {
                throw Failure.unkept
            }
        }
    }

    /// `source` as AAC in an .m4a at `url`, as the audio export writes one.
    private static func encode(_ source: URL, to url: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.unkept
        }
        session.outputURL = url
        session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else { throw Failure.unkept }
    }

    /// The sound a voice hands back for one utterance, and its end — once
    /// only: the voice may hand back more than one empty buffer, and the
    /// clock or a cancel may end it first. `whole` when the voice's own end
    /// came first.
    private final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private var ended = false
        private var waiting: CheckedContinuation<Void, Never>?
        private var kept: [AVAudioPCMBuffer] = []

        var buffers: [AVAudioPCMBuffer] {
            lock.lock()
            defer { lock.unlock() }
            return kept
        }

        var whole: Bool {
            lock.lock()
            defer { lock.unlock() }
            return ended
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock()
            if !done { kept.append(buffer) }
            lock.unlock()
        }

        /// `continuation` resumed at the end — at once when it has come.
        func wait(_ continuation: CheckedContinuation<Void, Never>) {
            lock.lock()
            if done {
                lock.unlock()
                continuation.resume()
                return
            }
            waiting = continuation
            lock.unlock()
        }

        func finish(whole: Bool) {
            lock.lock()
            guard !done else {
                lock.unlock()
                return
            }
            done = true
            ended = whole
            let resume = waiting
            waiting = nil
            lock.unlock()
            resume?.resume()
        }
    }
}
