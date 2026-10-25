// Live captions in Present: the phone's speech recogniser listening to the
// presenter — on the device where it can (requiresOnDeviceRecognition),
// partial results shown as they come, started again every
// LiveCaptionLines.restartSeconds, as one task stops after about a minute —
// and the band that shows the words over the slide for the audience, on the
// phone and the attached display alike (PresentStage). Its button opens a
// menu: the switch, the text size and where the band sits, kept as the
// "presentCaptions" preference. A refused microphone or recogniser, or a
// phone that cannot listen, says so in Dictation's words, with Open
// Settings, and turns the captions off — the same on both phones, so the
// next talk does not ask again. The Android twin's LiveCaptions.

import AVFoundation
import Observation
import Speech
import SwiftUI

/// Live captions' ears: `text` is what the stretch of speech now going has
/// said, `heardAt` when it last changed; a refusal sets `refused` and stops.
@MainActor
@Observable
final class LiveCaptioner {
    private(set) var text = ""
    private(set) var heardAt: Date?
    /// Why it stopped, when the microphone or the recogniser was refused.
    var refused: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    /// The request listening now, which the microphone's tap feeds from the
    /// audio thread.
    @ObservationIgnored private let feed = LiveCaptionFeed()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var restart: Task<Void, Never>?
    @ObservationIgnored private var running = false
    /// Stretches in a row that ended in an error other than silence with
    /// nothing heard: a recogniser that keeps failing is refused, as the
    /// Android twin refuses one, not asked again four times a second.
    @ObservationIgnored private var failures = 0

    /// Listening in `language` (BCP-47) when the phone recognises it, else
    /// its own; asks for the speech and microphone permissions first.
    func start(language: String?) {
        guard !running else { return }
        running = true
        refused = nil
        failures = 0
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                guard status == .authorized else {
                    return self.refuse(tr("Speech recognition is not allowed. You can turn it on in Settings."))
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor [weak self] in
                        guard let self, self.running else { return }
                        guard granted else {
                            return self.refuse(tr("The microphone is not allowed. You can turn it on in Settings."))
                        }
                        self.listen(language: language)
                    }
                }
            }
        }
    }

    func stop() {
        running = false
        restart?.cancel()
        restart = nil
        endTask()
        text = ""
        heardAt = nil
        guard LiveCaptionFeed.listening else { return }
        LiveCaptionFeed.listening = false
        // The presentation's sound has the phone again.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(PageSound.presentationHolds ? .playback : .ambient)
    }

    private func refuse(_ why: String) {
        stop()
        refused = why
    }

    private func listen(language: String?) {
        let own = language.flatMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
        guard let recognizer = own ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            return refuse(tr("Speech recognition is not available right now."))
        }
        self.recognizer = recognizer
        // Recording beside the slides' own sound, which plays on.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return refuse(tr("The microphone could not be started."))
        }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let feed = self.feed
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            feed.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { return refuse(tr("The microphone could not be started.")) }
        LiveCaptionFeed.listening = true
        begin()
    }

    /// A new stretch of listening: a fresh request and task, started again
    /// every restartSeconds, or when the last one ends.
    private func begin() {
        guard running, let recognizer else { return }
        // The recogniser gone meanwhile: listening again would only fail.
        guard recognizer.isAvailable else { return refuse(tr("Speech recognition is not available right now.")) }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        feed.set(request)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let said = result?.bestTranscription.formattedString
            let ended = result?.isFinal == true || error != nil
            let failed = error.map { !LiveCaptioner.isSilence($0 as NSError) } ?? false
            Task { @MainActor [weak self] in
                // A task let go of — cancelled as the next began — says no more.
                guard let self, self.running, self.request === request else { return }
                if let said, !said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.text = said
                    self.heardAt = Date()
                    self.failures = 0
                }
                guard ended else { return }
                if failed, self.failures + 1 >= LiveCaptioner.failureLimit {
                    return self.refuse(tr("Speech recognition is not available right now."))
                }
                self.failures = failed ? self.failures + 1 : 0
                // Silence, a busy recogniser: listen again in a moment.
                try? await Task.sleep(for: .seconds(LiveCaptionLines.relistenSeconds))
                if self.request === request { self.again() }
            }
        }
        restart?.cancel()
        restart = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(LiveCaptionLines.restartSeconds))
            guard !Task.isCancelled else { return }
            self?.again()
        }
    }

    /// Errors in a row, with nothing heard, after which listening stops.
    nonisolated static let failureLimit = 3

    /// Whether `error` is only silence, or a task let go of: listened for
    /// again however often it comes, as Android's NO_MATCH and
    /// SPEECH_TIMEOUT are.
    nonisolated static func isSilence(_ error: NSError) -> Bool {
        if error.domain == "kAFAssistantErrorDomain" { return [203, 216, 301, 1110].contains(error.code) }
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }

    /// The task now going ended, and another begun.
    private func again() {
        guard running else { return }
        feed.set(nil)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        begin()
    }

    private func endTask() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        feed.set(nil)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
    }
}

/// The request the microphone's buffers go to, set on the main thread and
/// read on the audio thread, under a lock.
final class LiveCaptionFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    /// Whether live captions have the microphone, which the presentation's
    /// sound then leaves alone (PageSound).
    static var listening = false

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let now = request
        lock.unlock()
        now?.append(buffer)
    }
}

/// The captions over the slide, on the phone and the display alike: the
/// last two lines heard (LiveCaptionLines.wrap), white on a band of black at
/// LiveCaptionLines.bandAlpha, at the bottom or the top as set, gone
/// LiveCaptionLines.hideSeconds after the last word. For the audience:
/// VoiceOver is told nothing of it.
struct LiveCaptionBand: View {
    let text: String
    let heardAt: Date?
    let settings: LiveCaptionLines.Settings
    let size: CGSize
    @State private var showing = false

    var body: some View {
        let lines = LiveCaptionLines.wrap(text, maxChars: LiveCaptionLines.lineChars(settings.size))
        let type = min(size.width, size.height) * LiveCaptionLines.textShare(settings.size)
        let top = settings.position == LiveCaptionLines.top
        VStack {
            if !top { Spacer(minLength: 0) }
            if showing && !lines.isEmpty {
                Text(verbatim: lines.joined(separator: "\n"))
                    .font(.system(size: max(type, 12), weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(LiveCaptionLines.bandAlpha), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
            if top { Spacer(minLength: 0) }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: heardAt) {
            guard heardAt != nil else {
                showing = false
                return
            }
            showing = true
            try? await Task.sleep(for: .seconds(LiveCaptionLines.hideSeconds))
            guard !Task.isCancelled else { return }
            showing = false
        }
    }
}

/// Present's Live captions button: its menu has the switch, the text size
/// and where the band sits, kept as the "presentCaptions" preference.
struct LiveCaptionsButton: View {
    @Binding var settings: LiveCaptionLines.Settings

    var body: some View {
        Menu {
            Toggle("Live captions", isOn: $settings.on)
            Picker(tr("Text size: %@", LiveCaptionLines.name(settings.size)), selection: $settings.size) {
                ForEach(LiveCaptionLines.sizes, id: \.self) { Text(LiveCaptionLines.name($0)).tag($0) }
            }
            Picker(tr("Position: %@", LiveCaptionLines.name(settings.position)), selection: $settings.position) {
                ForEach(LiveCaptionLines.positions, id: \.self) { Text(LiveCaptionLines.name($0)).tag($0) }
            }
        } label: {
            Image(systemName: settings.on ? "captions.bubble.fill" : "captions.bubble")
                .opacity(settings.on ? 1 : 0.6)
                .padding(10)
        }
        .accessibilityLabel("Live captions")
        .accessibilityValue(settings.on ? tr("On") : tr("Off"))
    }
}

/// Live captions for a talk: the setting kept as the "presentCaptions"
/// preference (`pref`), the ears listening while it is on and Present is in
/// front — in the design's language, as its clip captions are heard — and
/// what they hear handed to the session, which both screens draw. A refusal,
/// or a phone that cannot listen, says so, with Open Settings, and turns
/// them off, as the Android twin's PresentScreen does.
struct LiveCaptionsHost: ViewModifier {
    let session: PresentSession
    let captioner: LiveCaptioner
    @Binding var pref: String
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .onChange(of: pref, initial: true) { _, _ in update() }
            .onChange(of: scenePhase) { _, _ in update() }
            .onChange(of: captioner.refused) { _, _ in update() }
            .onChange(of: captioner.heardAt) { _, at in
                session.captionText = captioner.text
                session.captionHeardAt = at
            }
            .onDisappear { captioner.stop() }
            .alert("Live captions", isPresented: refusedBinding) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(captioner.refused ?? "")
            }
    }

    private var refusedBinding: Binding<Bool> {
        Binding(get: { captioner.refused != nil }, set: { if !$0 { captioner.refused = nil } })
    }

    @MainActor
    private func update() {
        var settings = LiveCaptionLines.Settings.decoded(pref)
        if captioner.refused != nil, settings.on {
            settings.on = false
            pref = settings.encoded()
        }
        session.captions = settings.on ? settings : nil
        if settings.on && scenePhase != .background {
            captioner.start(language: session.design.language)
        } else {
            captioner.stop()
            session.captionText = ""
            session.captionHeardAt = nil
        }
    }
}
