// Present and record: Canva's talking presentation. The studio first — the
// front camera's picture in its bubble, Camera on or off, and which
// microphone — then Start, a 3-2-1 count, and the pages as Present shows
// them with Back, Next, Pause and Finish, the page's notes under it for the
// presenter alone. Each page turn is timed on the talk's own clock, paused
// time left out (RecordingPlan.Capture). Finish keeps the voice and the
// camera with the design's media and hands back the recording. A refused
// microphone says so, with Settings; a call or another app pauses the talk.
// The Android twin's RecordStudio.

import AVFoundation
import SwiftUI

struct TalkStudio: View {
    let design: Design
    /// The recording kept, to be added to the design.
    var onDone: (Recording) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private enum Phase { case setup, countdown, live, saving }

    @State private var phase = Phase.setup
    @State private var recorder = TalkRecorder()
    @State private var cameraOn = true
    @State private var microphones: [AVAudioSessionPortDescription] = []
    @State private var microphone: String?
    @State private var micRefused = false
    @State private var problem: String?
    @State private var count = 3
    /// The page up, among those Present shows.
    @State private var place = 0
    @State private var paused = false
    @State private var capture = RecordingPlan.Capture(firstPage: "")
    @State private var startedAt = Date()
    @State private var pausedFor = 0.0
    @State private var pausedAt: Date?
    @State private var countTask: Task<Void, Never>?

    private var shown: [Int] { design.visiblePageIndices }

    private var page: Page? {
        guard shown.indices.contains(place) else { return design.pages.first }
        return design.pages[shown[place]]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                topBar
                stage
                if phase == .live || phase == .saving { notes }
                controls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            if phase == .countdown { countdown }
        }
        .preferredColorScheme(.dark)
        .task { await setUp() }
        .onDisappear {
            countTask?.cancel()
            if phase != .saving { recorder.cancel() }
        }
        .alert("Canvia needs the microphone to record your talk.", isPresented: $micRefused) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                dismiss()
            }
            Button("Cancel", role: .cancel) { dismiss() }
        }
    }

    // MARK: parts

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3) }
                .accessibilityLabel("Close")
                .disabled(phase == .saving)
            Spacer()
            Text(status)
                .font(.headline.monospacedDigit())
                .accessibilityAddTraits(.updatesFrequently)
            Spacer()
            Color.clear.frame(width: 24, height: 24)
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private var status: String {
        switch phase {
        case .setup: return tr("Present and record")
        case .countdown: return "\(count)"
        case .live: return paused ? tr("Paused") : tr("Recording")
        case .saving: return tr("Saving the recording")
        }
    }

    /// The page up, as large as there is room for, the camera in its bubble.
    private var stage: some View {
        GeometryReader { geo in
            if let page {
                let size = design.size(for: page)
                let scale = min(geo.size.width / max(size.width, 1), geo.size.height / max(size.height, 1))
                PageRenderView(design: design, page: page)
                    .environment(\.onScreen, true)
                    .scaleEffect(scale)
                    .frame(width: size.width * scale, height: size.height * scale)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .designDirection()
        .overlay(alignment: .bottomLeading) { cameraBubble }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Page %d of %d", place + 1, max(shown.count, 1)))
    }

    @ViewBuilder
    private var cameraBubble: some View {
        if cameraOn && recorder.hasCamera {
            TalkCameraPreview(session: recorder.session)
                .frame(width: 110, height: 110)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                .padding(8)
                .accessibilityLabel("Your camera")
        }
    }

    /// The page's notes, for the presenter alone.
    @ViewBuilder
    private var notes: some View {
        if let text = page?.notes, !text.isEmpty {
            ScrollView {
                Text(verbatim: text)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 90)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch phase {
        case .setup: setupControls
        case .countdown: EmptyView()
        case .live: liveControls
        case .saving: ProgressView().tint(.white)
        }
    }

    private var setupControls: some View {
        VStack(spacing: 12) {
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
            }
            Toggle("Camera", isOn: $cameraOn)
                .tint(Theme.accent)
                .onChange(of: cameraOn) { _, on in recorder.setCamera(on) }
            Picker("Microphone", selection: $microphone) {
                Text("Phone's microphone").tag(String?.none)
                ForEach(microphones, id: \.uid) { port in
                    Text(verbatim: port.portName).tag(Optional(port.uid))
                }
            }
            .pickerStyle(.menu)
            Button { startCountdown() } label: {
                Text("Start").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(micRefused)
        }
        .foregroundStyle(.white)
    }

    private var liveControls: some View {
        HStack(spacing: 16) {
            Button { turn(by: -1) } label: { Image(systemName: "chevron.backward").font(.title2) }
                .disabled(place == 0)
                .accessibilityLabel("Back")
            Button { togglePause() } label: {
                Label(paused ? tr("Resume") : tr("Pause"), systemImage: paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
            Button("Finish") { finish() }
                .buttonStyle(.borderedProminent)
            Button { turn(by: 1) } label: { Image(systemName: "chevron.forward").font(.title2) }
                .disabled(place >= shown.count - 1)
                .accessibilityLabel("Next")
        }
        .foregroundStyle(.white)
    }

    private var countdown: some View {
        Text(verbatim: "\(count)")
            .font(.system(size: 120, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
    }

    // MARK: actions

    @MainActor
    private func setUp() async {
        let access = await TalkRecorder.requestAccess(camera: true)
        guard access.microphone else {
            micRefused = true
            return
        }
        if !access.camera { cameraOn = false }
        do {
            try recorder.configure(camera: cameraOn, microphone: nil)
        } catch {
            problem = tr("Couldn't start recording. Another app may be using the microphone.")
            return
        }
        microphones = TalkRecorder.microphones
        recorder.onInterrupted = { if phase == .live && !paused { togglePause() } }
        recorder.startPreview()
    }

    private func startCountdown() {
        let port = microphones.first { $0.uid == microphone }
        try? AVAudioSession.sharedInstance().setPreferredInput(port)
        count = 3
        phase = .countdown
        countTask = Task { @MainActor in
            for n in [3, 2, 1] {
                count = n
                AccessibilityNotification.Announcement("\(n)").post()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            begin()
        }
    }

    @MainActor
    private func begin() {
        recorder.startPreview()
        let folder = FileManager.default.temporaryDirectory
        let audio = folder.appendingPathComponent("talk-\(UUID().uuidString).m4a")
        let camera = folder.appendingPathComponent("talk-\(UUID().uuidString).mp4")
        do {
            try recorder.begin(audioURL: audio, cameraURL: camera)
        } catch {
            problem = tr("Couldn't start recording. Another app may be using the microphone.")
            phase = .setup
            return
        }
        place = 0
        capture = RecordingPlan.Capture(firstPage: page?.id ?? "")
        startedAt = Date()
        pausedFor = 0
        pausedAt = nil
        paused = false
        phase = .live
    }

    /// The talk's own clock: seconds since Start, paused time left out.
    private func elapsed(_ now: Date = Date()) -> Double {
        let still = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(startedAt) - pausedFor - still)
    }

    private func turn(by step: Int) {
        let next = min(max(place + step, 0), max(shown.count - 1, 0))
        guard next != place else { return }
        place = next
        if let id = page?.id { capture.turn(to: id, at: elapsed()) }
    }

    private func togglePause() {
        if paused, let at = pausedAt {
            pausedFor += Date().timeIntervalSince(at)
            pausedAt = nil
            paused = false
            recorder.resume()
        } else if !paused {
            pausedAt = Date()
            paused = true
            recorder.pause()
        }
    }

    private func finish() {
        let end = elapsed()
        let spans = capture.finish(at: end)
        phase = .saving
        Task { @MainActor in
            let files = await recorder.finish()
            // A talk finished before any page was held long enough to keep
            // (RecordingPlan.minSpan) is nothing, as a voice that could not
            // be kept is — as the Android twin says it.
            guard !spans.isEmpty, let voice = files.audio,
                  let kept = Self.keep(voice: voice, camera: files.camera, spans: spans) else {
                problem = tr("Nothing was recorded")
                phase = .setup
                return
            }
            onDone(kept)
            dismiss()
        }
    }

    /// The files moved in with the design's media — the voice as music,
    /// the camera as a clip — under a new recording's id.
    static func keep(voice: URL, camera: URL?, spans: [RecordingSpan]) -> Recording? {
        let id = Recordings.newId()
        let audio = Recordings.audioFile(id)
        let fm = FileManager.default
        do {
            try fm.moveItem(at: voice, to: AudioStore.directory.appendingPathComponent(audio))
        } catch {
            return nil
        }
        var kept: String?
        if let camera {
            let file = Recordings.cameraFile(id)
            if (try? fm.moveItem(at: camera, to: VideoStore.directory.appendingPathComponent(file))) != nil { kept = file }
        }
        return Recording(id: id, createdAt: Date().timeIntervalSince1970 * 1000, audio: audio, camera: kept, pages: spans)
    }
}
