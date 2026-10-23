// The design's audio: every track under the film, listed with where it
// starts and how long it plays, and more added — music from Files or from
// your uploads, or a voice-over recorded over the design as it plays. A
// track opens to its start, trim, volume, fades, loop and Delete, each
// change one undo step, a slider's or a trim handle's when it is let go. Its
// trim is a trimmer bar over its waveform (TrimmerBar): letting a handle go
// plays the first second and a half of the new trim, and Play trimmed part
// plays all of it. The Android twin's Audio panel sets the same `audio`
// array.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AudioSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Each track's music's length in seconds, by AudioStore id, read as
    /// the sheet opens.
    @State private var lengths: [String: Double] = [:]
    @State private var importing = false
    @State private var refused = false
    @State private var micRefused = false
    /// A voice-over under way: counting down, then recording.
    @State private var recording = false
    @State private var detent: PresentationDetent = .medium

    private var tracks: [AudioTrack] { store.design.audioTracks }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Audio")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { id in
                    AudioTrackView(store: store, trackId: id)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        if !recording { Button("Done") { dismiss() } }
                    }
                }
        }
        .presentationDetents(sheetDetents, selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled(recording)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            bringIn(result)
        }
        .task(id: tracks.compactMap(\.audioId)) { await readLengths() }
        .alert("That file isn't music this phone can play", isPresented: $refused) {
            Button("OK", role: .cancel) {}
        }
        .alert(Self.micRefusedTitle, isPresented: $micRefused) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.micRefusedMessage)
        }
    }

    /// Said when the microphone is not allowed.
    static var micRefusedTitle: String { tr("Microphone access is off") }
    static var micRefusedMessage: String {
        tr("Canvia records a voice-over with the microphone. You can allow it in Settings, under Canvia.")
    }

    @ViewBuilder
    private var content: some View {
        if recording {
            VoiceOverPanel(store: store) { recording = false }
        } else {
            List {
                tracksSection
                addSection
            }
        }
    }

    private var tracksSection: some View {
        Section {
            if tracks.isEmpty {
                Text(Self.emptyNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(tracks) { track in
                NavigationLink(value: track.id) { trackRow(track) }
            }
            .onDelete { offsets in
                let ids = offsets.map { tracks[$0].id }
                for id in ids { store.removeAudioTrack(id) }
            }
        } header: {
            Text("Tracks")
        }
    }

    /// What the list says before there is anything in it.
    static var emptyNote: String { tr("No audio yet. Add music or record a voice-over to hear it under the video.") }

    /// A track by its name, with where it starts and how long it plays.
    private func trackRow(_ track: AudioTrack) -> some View {
        let duration = track.audioId.flatMap { lengths[$0] }
        return HStack(spacing: 12) {
            Image(systemName: "waveform")
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentSubtle))
            VStack(alignment: .leading, spacing: 2) {
                Text(AudioTracks.name(of: track))
                    .lineLimit(1)
                Text(AudioTracks.summary(of: track, duration: duration, missing: AudioTracks.isMissing(track)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var addSection: some View {
        Section("Add") {
            Button { importing = true } label: {
                Label("Music from Files…", systemImage: "folder")
            }
            musicMenu
            Button { startRecording() } label: {
                Label("Record voice-over", systemImage: "mic")
            }
            if !tracks.isEmpty { playButton }
        }
    }

    /// The page played with the tracks under it, as Present plays them;
    /// again, to stop — as on Android.
    private var playButton: some View {
        let playing = store.previewTime != nil
        return Button { if playing { store.stopPreview() } else { store.playPreview() } } label: {
            Label(playing ? tr("Stop") : tr("Play this page"), systemImage: playing ? "stop.circle" : "play.circle")
        }
    }

    /// Music brought in before, by its own name, to add again.
    @ViewBuilder
    private var musicMenu: some View {
        let music = Uploads.all(.audio).map(\.id)
        if !music.isEmpty {
            Menu {
                ForEach(music, id: \.self) { id in
                    Button(AudioStore.label(for: id)) { add(id) }
                }
            } label: {
                Label("Your music", systemImage: "music.note.list")
            }
        }
    }

    /// Music `id` as a new track from the film's start, said.
    private func add(_ id: String) {
        store.addAudioTrack(id)
        store.buzz(.confirm)
        store.announce(tr("Added %@", AudioStore.label(for: id)))
    }

    /// A file picked in Files: kept among your uploads and added as a track
    /// when it is music this phone plays; turned away, and said, when not.
    private func bringIn(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let id = AudioStore.store(url) else {
            refused = true
            return
        }
        Task {
            guard let seconds = await AudioStore.duration(of: id), seconds > 0 else {
                AudioStore.delete(id)
                refused = true
                return
            }
            Uploads.record(id, kind: .audio)
            lengths[id] = seconds
            add(id)
        }
    }

    /// The microphone asked for, then the countdown; a refusal says how to
    /// allow it.
    private func startRecording() {
        Task {
            guard await VoiceRecorder.requestPermission() else {
                micRefused = true
                return
            }
            store.stopPreview()
            detent = .medium
            recording = true
        }
    }

    private func readLengths() async {
        for id in Set(tracks.compactMap(\.audioId)) where lengths[id] == nil {
            if let seconds = await AudioStore.duration(of: id) { lengths[id] = seconds }
        }
    }
}

// MARK: - one track

/// One track's start, loop, trim, volume and fades, and Delete.
struct AudioTrackView: View {
    @Bindable var store: DesignStore
    let trackId: String
    @Environment(\.dismiss) private var dismiss
    /// The music's length, read as the view opens; nil until it is, 0 for
    /// music that cannot be read.
    @State private var length: Double?
    /// The music's waveform for the trimmer bar, once read.
    @State private var peaks: [Float] = []
    /// Where each slider is while it is dragged; written when let go.
    @State private var draftStart: Double?
    @State private var draftVolume: Double?
    @State private var draftFadeIn: Double?
    @State private var draftFadeOut: Double?
    /// The Captions sheet, over this one.
    @State private var captioning = false

    private var track: AudioTrack? { store.design.audioTracks.first { $0.id == trackId } }

    var body: some View {
        Form {
            if let track = self.track {
                placeSection(track)
                trimSection(track)
                levelSection(track)
                captionsSection(track)
                Section {
                    Button(role: .destructive) { delete() } label: {
                        Label("Delete track", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(track.map(AudioTracks.name(of:)) ?? tr("Track"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: track?.audioId) {
            peaks = []
            guard let id = track?.audioId else { return }
            length = await AudioStore.duration(of: id) ?? 0
            peaks = await Peaks.of(id) ?? []
        }
        .onDisappear { Audition.shared.stop() }
    }

    /// The words said in the track, timed to this page: from where the
    /// track starts in the film, less where the page does.
    private func captionsSection(_ track: AudioTrack) -> some View {
        let offset = track.start - track.trimStart - store.pageStartSeconds
        return Section {
            Button {
                captioning = true
            } label: {
                Label("Captions", systemImage: "captions.bubble")
            }
            .sheet(isPresented: $captioning) {
                CaptionsSheet(store: store, source: AudioTrack.src(track.id),
                              audio: { AudioStore.url(for: track.audioId) },
                              range: Self.heard(track, length: length),
                              toPage: { cues in
                                  cues.map { CaptionCue(start: max(0, $0.start + offset), end: $0.end + offset, text: $0.text) }
                                      .filter { $0.end > $0.start }
                              })
            }
        }
    }

    /// The part of the track's music its trim plays, within its `length`;
    /// nil while the length is not known.
    static func heard(_ track: AudioTrack, length: Double?) -> ClosedRange<Double>? {
        guard let length, length > 0 else { return nil }
        let start = min(max(0, track.trimStart), length)
        let end = min(max(track.trimEnd ?? length, start), length)
        return start...end
    }

    /// Where it starts, over the film's length, and whether it goes round
    /// to the end.
    private func placeSection(_ track: AudioTrack) -> some View {
        let film = AudioMix.filmLength(design: store.design)
        let here = AudioStore.url(for: track.audioId) != nil
        return Section {
            slider(tr("Starts at"), stored: max(track.start, 0), in: 0...max(film, track.start, 0.1), step: 0.5,
                   draft: $draftStart, readout: VideoStore.timeLabel) { v in
                write { $0.start = AudioTracks.tenths(v) }
            }
            Toggle("Loop to the end", isOn: Binding(
                get: { track.loop },
                set: { on in write { $0.loop = on } }))
        } footer: {
            if track.start >= film {
                Text("It starts after the video ends, so it isn't heard.")
            } else if !here {
                Text("This music was chosen on another phone. Add it again here to hear it.")
            }
        }
    }

    /// The trimmer bar over the music's waveform, the trim kept
    /// AudioTrack.minLength long at least, as a clip's is; and the trimmed
    /// part played.
    @ViewBuilder
    private func trimSection(_ track: AudioTrack) -> some View {
        if let length, length > AudioTrack.minLength {
            let start = min(max(0, track.trimStart), length)
            let end = min(track.trimEnd ?? length, length)
            Section {
                TrimmerBar(length: length, start: start, end: end, minLength: AudioTrack.minLength,
                           commit: { s, e in commitTrim(s, e, length: length) }) {
                    WaveformView(peaks: peaks)
                }
                .padding(.vertical, 4)
                Button { audition(start...max(start, end)) } label: {
                    Label("Play trimmed part", systemImage: "play.circle")
                }
            }
        } else if length == nil {
            Section { ProgressView() }
        }
    }

    /// `range` seconds of the track's music, heard once at its volume.
    private func audition(_ range: ClosedRange<Double>) {
        guard let track, let url = AudioStore.url(for: track.audioId) else { return }
        Audition.shared.play(url, range, volume: track.volume)
    }

    private func levelSection(_ track: AudioTrack) -> some View {
        Section {
            slider(tr("Volume"), stored: min(max(track.volume, 0), 1), in: 0...1, step: 0.1,
                   draft: $draftVolume, readout: ClipSheet.percentLabel) { v in
                write { $0.volume = (min(max(v, 0), 1) * 100).rounded() / 100 }
            }
            slider(tr("Fade in"), stored: fade(track.fadeIn), in: AudioTrack.fadeRange, step: 0.5,
                   draft: $draftFadeIn, readout: AudioTracks.secondsLabel) { v in
                write { $0.fadeIn = AudioTracks.tenths(v) }
            }
            slider(tr("Fade out"), stored: fade(track.fadeOut), in: AudioTrack.fadeRange, step: 0.5,
                   draft: $draftFadeOut, readout: AudioTracks.secondsLabel) { v in
                write { $0.fadeOut = AudioTracks.tenths(v) }
            }
        }
    }

    private func fade(_ seconds: Double) -> Double {
        min(max(seconds, AudioTrack.fadeRange.lowerBound), AudioTrack.fadeRange.upperBound)
    }

    /// A slider over `range` (see StepSlider).
    private func slider(_ label: String, stored: Double, in range: ClosedRange<Double>, step: Double,
                        draft: Binding<Double?>, readout: @escaping (Double) -> String,
                        write: @escaping (Double) -> Void) -> some View {
        StepSlider(label: label, stored: stored, range: range, step: step, draft: draft, readout: readout,
                   write: write)
    }

    /// The trim let go at, written as one step — to a tenth of a second, an
    /// end at the file's own end kept as none — and the first second and a
    /// half of it played.
    private func commitTrim(_ start: Double, _ end: Double, length: Double) {
        let s = AudioTracks.tenths(start)
        let e = AudioTracks.tenths(end)
        write { next in
            next.trimStart = s
            next.trimEnd = e >= length - 0.05 ? nil : e
        }
        audition(Trimming.auditioned(start: s, end: min(e, length)))
    }

    /// The track changed by `change`, as one undo step.
    private func write(_ change: (inout AudioTrack) -> Void) {
        store.updateAudioTrack(trackId, change)
    }

    private func delete() {
        store.removeAudioTrack(trackId)
        store.buzz(.confirm)
        store.announce(tr("Deleted the track"))
        dismiss()
    }
}

// MARK: - a slider

/// A slider over `range` showing `stored`, held in `draft` while it is
/// dragged and handed to `write` once when let go — one undo step — and a
/// `step` at a time by VoiceOver's swipes; its name before it and `readout`
/// after. A track's sliders and a clip's fades.
struct StepSlider: View {
    let label: String
    let stored: Double
    let range: ClosedRange<Double>
    let step: Double
    @Binding var draft: Double?
    let readout: (Double) -> String
    let write: (Double) -> Void

    var body: some View {
        let shown = readout(draft ?? stored)
        HStack {
            Text(label)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { draft ?? stored }, set: { draft = $0 }), in: range,
                   onEditingChanged: { editing in
                       guard !editing, let v = draft else { return }
                       draft = nil
                       if v != stored { write(v) }
                   })
            .accessibilityLabel(label)
            .accessibilityValue(shown)
            .accessibilityAdjustableAction { direction in
                let next = stored + (direction == .increment ? step : -step)
                write(min(range.upperBound, max(range.lowerBound, next)))
            }
            Text(shown)
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - voice-over

/// A voice-over as it happens: 3, 2, 1, then the design plays from the
/// start of the page on screen while the microphone records, with its level
/// and the time so far, until Stop or the film's end. The recording becomes
/// one of your music uploads and a track from where that page starts.
struct VoiceOverPanel: View {
    @Bindable var store: DesignStore
    var onDone: () -> Void
    private let recorder = VoiceRecorder.shared
    @State private var count = 3
    /// When the recording began; nil while counting down.
    @State private var started: Date?
    /// Where the page it began on starts in the film: where its track goes.
    @State private var startsAt = 0.0
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            if failed {
                failure
            } else if let started {
                live(since: started)
            } else {
                countdown
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task { await run() }
        // Gone mid-recording — the editor closed — what was said is kept.
        .onDisappear { if recorder.isRecording { finish() } }
    }

    private var countdown: some View {
        VStack(spacing: 12) {
            Text("\(count)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Recording in \(count)")
            Text("The design plays from the start of this page as you speak.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel", role: .cancel) { onDone() }
        }
    }

    private func live(since: Date) -> some View {
        VStack(spacing: 14) {
            Label("Recording", systemImage: "record.circle")
                .foregroundStyle(.red)
            TimelineView(.periodic(from: since, by: 0.1)) { context in
                Text(VideoStore.timeLabel(context.date.timeIntervalSince(since)))
                    .font(.title2.monospacedDigit())
            }
            meter(recorder.level)
            Button(role: .destructive) { finish() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var failure: some View {
        VStack(spacing: 12) {
            Text("The microphone could not be started.")
            Button("OK") { onDone() }
        }
    }

    /// How loud the microphone is now, as a bar.
    private func meter(_ level: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule().fill(Theme.accent).frame(width: geo.size.width * level)
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("Microphone level")
        .accessibilityValue(ClipSheet.percentLabel(level))
    }

    /// Three seconds counted down, then the microphone on and the design
    /// playing; the film's end stops it, as Stop does.
    private func run() async {
        for n in [3, 2, 1] {
            count = n
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
        }
        startsAt = AudioMix.pageStart(design: store.design, index: store.pageIndex)
        guard recorder.start() else {
            failed = true
            return
        }
        started = Date()
        store.playThrough { finish() }
    }

    /// The recording stopped and kept: a music upload, and a track from
    /// where its page starts, as one undo step. Too short to keep, or not
    /// kept, it is said.
    private func finish() {
        guard recorder.isRecording else { return }
        // Stopped first: the play's end calls back here, and finds it done.
        let taken = recorder.stop()
        store.stopPreview()
        guard let file = taken else {
            store.announce(tr("Nothing was recorded"), undoable: false)
            onDone()
            return
        }
        defer { try? FileManager.default.removeItem(at: file) }
        let name = AudioTracks.voiceOverName(after: store.design.audioTracks)
        guard let id = AudioStore.store(file, name: name) else {
            store.buzz(.reject)
            store.announce(tr("Couldn't keep that recording"), undoable: false)
            onDone()
            return
        }
        Uploads.record(id, kind: .audio)
        store.addAudioTrack(id, start: startsAt, name: name)
        store.buzz(.confirm)
        store.announce(tr("Added %@", name))
        onDone()
    }
}
