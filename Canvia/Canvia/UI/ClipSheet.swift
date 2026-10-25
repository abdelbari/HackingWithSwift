// A clip's trim, speed, loop and sound.
//
// The part of the file a clip plays, how fast, whether it goes round again,
// how loud and how its sound fades in and out — kept on the element, the
// file left as it is, so a trim can always be taken back out. The trim is a
// trimmer bar over the clip's frames (TrimmerBar): dragging a handle shows
// the frame there on the canvas, and letting go plays the first second and
// a half of the new trim. Each change is one undo step: a slider's or a
// handle's when it is let go, not one for every frame of the drag. The
// Android twin's PhotoPanel Clip section sets the same `clip` object.

import SwiftUI

struct ClipSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    /// The clip's length, read off the main thread when the sheet opens;
    /// nil until it is, 0 for one that cannot be read.
    @State private var length: Double?
    /// The clip's frames for the trimmer bar, once read.
    @State private var frames: [UIImage] = []
    /// Where the Volume and fade sliders are while dragged; written when let
    /// go.
    @State private var draftVolume: Double?
    @State private var draftFadeIn: Double?
    @State private var draftFadeOut: Double?
    /// The Captions sheet, over this one.
    @State private var captioning = false

    private var element: Element? {
        guard let el = store.singleSelection, VideoStore.isVideo(el.src) else { return nil }
        return el
    }

    private var clipId: String? { element?.src.flatMap { VideoStore.split($0)?.id } }

    var body: some View {
        NavigationStack {
            Form {
                if let el = element {
                    let clip = el.clip ?? ClipPlayback()
                    trimSection(el, clip)
                    playSection(clip)
                    soundSection(clip)
                    EnhanceVoiceRow(on: clip.enhance, source: clipId.map { VideoStore.prefix + $0 },
                                    range: Self.heard(clip, length: length), volume: clip.volume) { on in
                        write { $0.enhance = on }
                    }
                    fadeSection(clip)
                    captionsSection(el, clip)
                    actionSection
                }
            }
            .navigationTitle("Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        // Check accessibility's Add captions: this clip's captions, at once.
        .onAppear {
            guard let asked = store.captionsAsked, asked.hasPrefix(VideoStore.prefix) else { return }
            store.captionsAsked = nil
            guard asked == clipId.map({ VideoStore.src($0, at: nil) }) else { return }
            // Once this sheet is up, so the captions can come up over it.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                captioning = true
            }
        }
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .task(id: clipId) { await readClip() }
        .onDisappear {
            store.clipScrub = nil
            Audition.shared.stop()
        }
    }

    /// The clip's length, off the main thread, then its frames.
    private func readClip() async {
        frames = []
        guard let id = clipId else { return }
        let read = await Task.detached(priority: .userInitiated) { VideoStore.duration(of: id) ?? 0 }.value
        length = read
        guard read > 0 else { return }
        frames = await Filmstrip.frames(of: id, length: read)
    }

    /// The trimmer bar over the clip's frames, the trim kept
    /// `ClipPlayback.minLength` long at least. A clip whose length cannot be
    /// read, or is no longer than that, has none, as on the Android twin.
    @ViewBuilder
    private func trimSection(_ el: Element, _ clip: ClipPlayback) -> some View {
        if let length, length > ClipPlayback.minLength {
            Section {
                TrimmerBar(length: length, start: min(max(0, clip.start), length),
                           end: min(clip.end ?? length, length), minLength: ClipPlayback.minLength,
                           scrub: { t in store.clipScrub = t.map { Trimming.Scrub(elementId: el.id, time: $0) } },
                           commit: { start, end in commitTrim(start, end, length: length) }) {
                    FilmstripView(frames: frames)
                }
                .padding(.vertical, 4)
            }
        } else if length == nil {
            Section { ProgressView() }
        }
    }

    /// Speed, from a quarter to twice as fast, Loop, and Autoplay — off, the
    /// clip waits for Play in Present (Videos); the MP4 and GIF play it
    /// either way.
    private func playSection(_ clip: ClipPlayback) -> some View {
        Section {
            Picker("Speed", selection: Binding(
                get: { clip.speed },
                set: { v in write { $0.speed = v } })) {
                ForEach(ClipPlayback.speeds, id: \.self) { speed in
                    Text(Self.speedLabel(speed)).tag(speed)
                }
            }
            .pickerStyle(.menu)
            Toggle("Loop", isOn: Binding(
                get: { clip.loop },
                set: { on in write { $0.loop = on } }))
            Toggle("Autoplay", isOn: Binding(
                get: { clip.autoplay },
                set: { on in write { $0.autoplay = on } }))
        } footer: {
            if !clip.autoplay {
                Text("When presenting, it waits for a tap on Play.")
            }
        }
    }

    /// The clip's own sound as its page plays, at any speed: Volume, held
    /// here while dragged and written once on release — VoiceOver's swipes a
    /// tenth at a time — and Mute.
    private func soundSection(_ clip: ClipPlayback) -> some View {
        let stored = min(max(clip.volume, 0), 1)
        let percent = Self.percentLabel(draftVolume ?? stored)
        return Section {
            HStack {
                Text("Volume")
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { draftVolume ?? stored }, set: { draftVolume = $0 }), in: 0...1,
                       onEditingChanged: { editing in if !editing { commitVolume(stored) } })
                .accessibilityLabel("Volume")
                .accessibilityValue(percent)
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 0.1 : -0.1
                    write { $0.volume = min(1, max(0, ((stored + step) * 10).rounded() / 10)) }
                }
                Text(percent)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Toggle("Mute", isOn: Binding(
                get: { clip.muted },
                set: { on in write { $0.muted = on } }))
        }
    }

    /// Fade in and Fade out on the clip's own sound, 0 to 5 seconds in
    /// half seconds, as a track's fades are heard (AudioMix.clipFades).
    private func fadeSection(_ clip: ClipPlayback) -> some View {
        let range = ClipPlayback.fadeRange
        func kept(_ v: Double) -> Double { min(max(v, range.lowerBound), range.upperBound) }
        let label: (Double) -> String = { AudioTracks.secondsLabel(Self.halves($0)) }
        return Section {
            StepSlider(label: tr("Fade in"), stored: kept(clip.fadeIn), range: range, step: 0.5,
                       draft: $draftFadeIn, readout: label) { v in
                write { $0.fadeIn = Self.halves(v) }
            }
            StepSlider(label: tr("Fade out"), stored: kept(clip.fadeOut), range: range, step: 0.5,
                       draft: $draftFadeOut, readout: label) { v in
                write { $0.fadeOut = Self.halves(v) }
            }
        }
    }

    /// The words said in the clip, timed to the page through its trim and
    /// speed (Captions.retimed): the Captions sheet, over this one.
    private func captionsSection(_ el: Element, _ clip: ClipPlayback) -> some View {
        Section {
            Button {
                captioning = true
            } label: {
                Label("Captions", systemImage: "captions.bubble")
            }
            .sheet(isPresented: $captioning) {
                if let id = clipId {
                    CaptionsSheet(store: store, source: VideoStore.src(id, at: nil),
                                  audio: { VideoStore.url(for: id) },
                                  range: Self.heard(clip, length: length),
                                  toPage: { Captions.retimed($0, from: ClipPlayback(), to: clip) })
                }
            }
        }
    }

    /// The part of the clip's file its trim plays, within its `length`;
    /// nil while the length is not known.
    static func heard(_ clip: ClipPlayback, length: Double?) -> ClosedRange<Double>? {
        guard let length, length > 0 else { return nil }
        let start = min(max(0, clip.start), length)
        let end = min(max(clip.end ?? length, start), length)
        return start...end
    }

    private var actionSection: some View {
        Section {
            Button("Fit page to clip") { store.fitPageToClip() }
                .disabled((length ?? 0) <= ClipPlayback.minLength)
            // The clip's sound as a track of its own, moved and trimmed in
            // Audio; the clip is muted.
            Button {
                if let el = element { store.detachAudio(el.id) }
            } label: {
                Label("Detach audio", systemImage: "waveform.badge.minus")
            }
            .disabled(element?.clip?.muted == true)
            Button { store.playPreview() } label: {
                Label("Play", systemImage: "play.circle")
            }
        }
    }

    /// A volume as the Clip sheet shows it: "0%" to "100%".
    static func percentLabel(_ volume: Double) -> String {
        "\(Int((min(max(volume, 0), 1) * 100).rounded()))%"
    }

    /// The volume dragged to, written as one step, kept to the hundredth
    /// the readout shows; nothing when it was let go where it was.
    private func commitVolume(_ stored: Double) {
        guard let volume = draftVolume else { return }
        draftVolume = nil
        let kept = (min(max(volume, 0), 1) * 100).rounded() / 100
        if kept != stored { write { $0.volume = kept } }
    }

    /// The trim let go at, written as one step — to a tenth of a second,
    /// an end at the file's own end kept as none — and the first second and
    /// a half of it played.
    private func commitTrim(_ start: Double, _ end: Double, length: Double) {
        let s = Self.tenths(start)
        let e = Self.tenths(end)
        write { next in
            next.start = s
            next.end = e >= length - 0.05 ? nil : e
        }
        // Heard as it plays: not at all when it is silent, else at its
        // volume and speed.
        let playback = element?.clip ?? ClipPlayback()
        if playback.sounds, let id = clipId, let url = VideoStore.url(for: id) {
            Audition.shared.play(url, Trimming.auditioned(start: s, end: min(e, length)),
                                 volume: playback.volume, speed: playback.playbackSpeed)
        }
    }

    /// The selected clip's playback changed by `change`, as one undo step.
    private func write(_ change: (inout ClipPlayback) -> Void) {
        guard let el = element else { return }
        var clip = el.clip ?? ClipPlayback()
        change(&clip)
        store.setClip(clip)
    }

    private static func tenths(_ seconds: Double) -> Double { (seconds * 10).rounded() / 10 }

    /// Seconds to the half second a fade steps by.
    static func halves(_ seconds: Double) -> Double { (seconds * 2).rounded() / 2 }

    /// "0.25×", "0.5×", "1×", "1.25×", "2×": the speed with no trailing
    /// zeros.
    static func speedLabel(_ speed: Double) -> String {
        var text = String(format: "%.2f", speed)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "×"
    }
}
