// A clip played by hand while presenting, as on the Android twin's
// Videos.presentTime: a tap on a clip in Present shows Play/Pause and a
// scrubber across its trimmed part, and a clip whose Autoplay is off
// (ClipPlayback.autoplay) waits on its first frame — its trim's `start` —
// until it is played. What the presenter did to a clip is an Override:
// {state: playing | paused, anchor: the moment in the file it was played
// or paused at, in seconds, at: the page's moment then}; with none, a clip
// plays on the page's clock as it always did, or waits when its Autoplay is
// off. The rules both phones keep are here and tested (PresentClipsTests,
// the Android twin's VideosTest); Present draws and hears them.

import CoreGraphics
import Foundation

enum Videos {

    /// What the presenter did to one clip on the page up.
    struct Override: Equatable {
        enum HandState: String { case playing, paused }
        var state: HandState
        /// The moment in the file it was played or paused at, in seconds.
        var anchor: Double
        /// The page's moment then, in seconds since it came up.
        var at: Double
    }

    /// How long the controls stay up after the last touch, in seconds.
    static let controlsSeconds = 3.0
    /// The least a control is across, in points.
    static let target: CGFloat = 44

    /// The moment in the file clip `el` shows `pageMoment` seconds into its
    /// page in Present, for a file `duration` long when that is known. No
    /// override: the page's clock as VideoStore.clipTime has it — or its
    /// trim's start, for a clip whose Autoplay is off. Played by hand: on
    /// from its anchor since then, at its speed, round again or held at its
    /// end as its loop says. Paused: its anchor.
    static func presentTime(_ el: Element, pageMoment: Double, override: Override?, duration: Double?) -> Double {
        let clip = el.clip ?? ClipPlayback()
        guard let override else {
            return clip.autoplay ? VideoStore.clipTime(pageMoment, clip: clip, duration: duration) : max(0, clip.start)
        }
        let start = max(0, clip.start)
        var local = max(0, override.anchor - start) / clip.playbackSpeed
        if override.state == .playing { local += max(0, pageMoment - override.at) }
        return VideoStore.clipTime(local, clip: clip, duration: duration)
    }

    /// Whether clip `el` is moving: played by hand, or on its own with
    /// Autoplay on and nothing done to it.
    static func moves(_ el: Element, override: Override?) -> Bool {
        guard let override else { return el.clip?.autoplay ?? true }
        return override.state == .playing
    }

    /// The trimmed part of clip `el`, a file `duration` long, in seconds:
    /// its start to its end, or the file's when it has none; nil when that
    /// is not known yet, or too short to scrub.
    static func trimRange(_ el: Element, duration: Double?) -> ClosedRange<Double>? {
        let clip = el.clip ?? ClipPlayback()
        let start = max(0, clip.start)
        guard let end = [clip.end, duration].compactMap({ $0 }).min(), end - start > ClipPlayback.minLength else {
            return nil
        }
        return start...end
    }

    /// Whether clip `el`, played by hand (`override`), is still playing
    /// `pageMoment` seconds into its page — which holds the deck's autoplay
    /// on the page. A clip that loops, or whose end is not known, plays on;
    /// one that does not loop has stopped once it is within 0.05 s of its
    /// end (its trim's, else its file's, the nearer), where presentTime
    /// holds it on its last frame. Paused, or untouched: not held. The rule
    /// both phones keep (the Android twin's Videos.holding).
    static func holding(_ el: Element, override: Override?, pageMoment: Double, duration: Double?) -> Bool {
        guard let override, override.state == .playing else { return false }
        let clip = el.clip ?? ClipPlayback()
        if clip.loop { return true }
        guard let end = [clip.end, duration].compactMap({ $0 }).min() else { return true }
        let now = presentTime(el, pageMoment: pageMoment, override: override, duration: duration)
        return now < end - 0.05
    }

    /// Whether clip `el` is moving in Present: untouched, as its Autoplay
    /// says; touched, while it is `holding` — so a clip played to its end
    /// shows Play again, and plays from its start.
    static func moving(_ el: Element, override: Override?, pageMoment: Double, duration: Double?) -> Bool {
        guard override != nil else { return el.clip?.autoplay ?? true }
        return holding(el, override: override, pageMoment: pageMoment, duration: duration)
    }

    /// Play or Pause tapped on clip `el` at `pageMoment`: a moving clip
    /// pauses where it is; a still one plays on from there — from its start
    /// again when it does not loop and has come to its end, so a clip can
    /// be played again without leaving the page.
    static func toggled(_ el: Element, override: Override?, pageMoment: Double, duration: Double?) -> Override {
        let now = presentTime(el, pageMoment: pageMoment, override: override, duration: duration)
        if moving(el, override: override, pageMoment: pageMoment, duration: duration) {
            return Override(state: .paused, anchor: now, at: pageMoment)
        }
        let clip = el.clip ?? ClipPlayback()
        var from = now
        if !clip.loop, let range = trimRange(el, duration: duration), now >= range.upperBound - 0.05 {
            from = range.lowerBound
        }
        return Override(state: .playing, anchor: from, at: pageMoment)
    }

    /// The scrubber dragged to `seconds` in the file at `pageMoment`: the
    /// clip there, within its trimmed part, playing on or paused as it was.
    static func scrubbed(_ el: Element, to seconds: Double, override: Override?, pageMoment: Double,
                         duration: Double?) -> Override {
        let kept = trimRange(el, duration: duration).map { min(max(seconds, $0.lowerBound), $0.upperBound) } ?? max(0, seconds)
        let on = moving(el, override: override, pageMoment: pageMoment, duration: duration)
        return Override(state: on ? .playing : .paused, anchor: kept, at: pageMoment)
    }

    /// Whether any of the page's `clips` is played by hand and still
    /// playing `pageMoment` seconds in (`holding`), each a file as long as
    /// `durations` says by element id when known — which holds the deck's
    /// autoplay on it.
    static func playingByHand(_ overrides: [String: Override], clips: [Element], pageMoment: Double,
                              durations: [String: Double]) -> Bool {
        clips.contains { el in
            holding(el, override: overrides[el.id], pageMoment: pageMoment, duration: durations[el.id])
        }
    }

    /// The clip at `point` among `elements` as drawn, the front one first;
    /// nil where there is none.
    static func clip(at point: CGPoint, in elements: [Element]) -> Element? {
        elements.reversed().first { VideoStore.isVideo($0.src) && Geometry.hits($0, point: point) }
    }

    /// The clips of `page` heard in Present with `overrides`, each with how
    /// many seconds after the page came up its own clock reads nought: a
    /// clip behind the page and one playing by itself at 0, as AudioMix
    /// .clips hears them; one played by hand from its anchor, shifted so its
    /// sound meets its picture, its timing left out — it was asked for —
    /// and a paused clip, or one waiting with its Autoplay off, not at all.
    static func heard(design: Design, page: Page, overrides: [String: Override]) -> [(clip: AudioMix.Clip, shift: Double)] {
        var out: [(clip: AudioMix.Clip, shift: Double)] = []
        if let bg = page.backgroundClip, bg.playback.sounds, let parts = VideoStore.split(bg.src) {
            out.append((AudioMix.Clip(source: parts.id, playback: bg.playback), 0))
        }
        for el in design.drawnElements(on: page) {
            guard el.type == .image, let src = el.src, let parts = VideoStore.split(src) else { continue }
            let playback = el.clip ?? ClipPlayback()
            guard playback.sounds else { continue }
            guard let override = overrides[el.id] else {
                guard playback.autoplay else { continue }
                let timing = el.timing.flatMap { ElementTiming.kept($0) }
                out.append((AudioMix.Clip(source: parts.id, playback: playback, timing: timing), 0))
                continue
            }
            guard override.state == .playing else { continue }
            let shift = override.at - max(0, override.anchor - max(0, playback.start)) / playback.playbackSpeed
            out.append((AudioMix.Clip(source: parts.id, playback: playback), shift))
        }
        return out
    }

    /// Whether any clip in `design` has its Autoplay off: the video and the
    /// GIF play it from its start as its page plays all the same, and the
    /// export sheet says so (`exportNote`).
    static func anyWaiting(_ design: Design) -> Bool {
        design.pages.contains { page in
            page.elements.contains { VideoStore.isVideo($0.src) && $0.clip?.autoplay == false }
        }
    }

    static var exportNote: String { tr("Videos that don't autoplay play by themselves in a video or GIF.") }

    /// What VoiceOver offers on a clip in Present: "Play video, <alt text>"
    /// — "Pause video, …" while it moves — or the words alone when it has
    /// no description, as the Android twin's clipAction says them.
    static func spokenAction(_ el: Element, moving: Bool) -> String {
        guard let alt = el.altText?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty else {
            return moving ? tr("Pause video") : tr("Play video")
        }
        return moving ? tr("Pause video, %@", alt) : tr("Play video, %@", alt)
    }
}
