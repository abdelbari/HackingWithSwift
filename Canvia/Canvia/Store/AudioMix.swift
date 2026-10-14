// Everything heard in the video: each clip's own sound on its page, and the
// design's audio tracks under the film. The plan is pure — the same numbers
// as the Android twin's, from the same table of tests — and Soundtrack.mux
// runs it through AVFoundation on the finished MP4; PageSound plays each
// track's span (AudioMix.span) in Play and Present.
//
// A clip sounds while its page plays: its trimmed window laid from the
// page's start, again and again when it loops, never past the page's last
// frame. A clip at another speed is heard at that speed, its pitch kept: its
// window takes its length over the speed on the page's clock. Its own fades
// (`clipFades`) rise from where it is first heard on its page and fall to
// where it is last heard there, by the same rule as a track's. A muted or
// silent clip is not in the mix; nor is a clip behind a page or filling a
// shape, or a GIF, which is a photo. A clip with its own timing
// (ElementTiming) is heard only while it shows: what it would play then,
// from the page's start, cut to its window, as its picture is. Hidden pages
// are not in the film, so their clips are not either.
//
// A track sounds from its `start` in the film: its trimmed window once, or
// round and round to the film's end when it loops, never past that end — so
// one that starts after the film is over is not heard at all. Its gain
// rises from nothing over its fade in and falls to nothing over its fade
// out, at the end of what it plays. A fade is heard only on a track that
// sounds for more than twice its length, as the old soundtrack's one-second
// fade was, so the old soundtrack's track plays exactly as it did.

import Foundation

enum AudioMix {

    /// A clip on a page that may sound: `source` is its id, as
    /// `Segment.source` names it; `timing`, its element's own time on the
    /// page, outside which it is silent, as it is unseen.
    struct Clip: Equatable {
        var source: String
        var playback: ClipPlayback
        var timing: ElementTiming? = nil
    }

    /// One stretch of one source's sound: from `sourceStart` seconds into
    /// the file, laid at `at` seconds into the video for `duration` seconds,
    /// at `gain` — rising from nothing across `fadeIn` and falling to
    /// nothing across `fadeOut`, when it has them — played at `speed`, so
    /// it takes `duration` × `speed` seconds of the file.
    struct Segment: Equatable {
        var source: String, sourceStart: Double, at: Double, duration: Double
        var gain: Double
        var fadeOut: ClosedRange<Double>? = nil
        var fadeIn: ClosedRange<Double>? = nil
        var speed: Double = 1

        var end: Double { at + duration }
        /// How much of the file it plays, in seconds.
        var sourceDuration: Double { duration * speed }

        /// How loud it is `t` seconds into the video.
        func gainAt(_ t: Double) -> Double {
            AudioMix.envelope(t, gain: gain, fadeIn: fadeIn, fadeOut: fadeOut)
        }
    }

    /// Where one track sounds in the film: `from`...`to` seconds of its
    /// file, laid from `at` until `until` seconds into the film — round
    /// again from `from` when it loops — at `gain`, with its fades in film
    /// seconds.
    struct Span: Equatable {
        var source: String
        var from: Double, to: Double
        var at: Double, until: Double
        var loop: Bool
        var gain: Double
        var fadeIn: ClosedRange<Double>?
        var fadeOut: ClosedRange<Double>?

        /// How loud it is `t` seconds into the film.
        func gainAt(_ t: Double) -> Double {
            AudioMix.envelope(t, gain: gain, fadeIn: fadeIn, fadeOut: fadeOut)
        }

        /// The stretches it lays: its window from `at`, again and again
        /// when it loops, the last cut short at `until`; none for a span
        /// with no end.
        var segments: [Segment] {
            let length = to - from
            guard length > 0.01, until.isFinite else { return [] }
            var out: [Segment] = []
            var t = at
            while t < until - 0.001 {
                let stretch = min(length, until - t)
                out.append(Segment(source: source, sourceStart: from, at: t, duration: stretch, gain: gain,
                                   fadeOut: fadeOut, fadeIn: fadeIn))
                t += stretch
                if !loop { break }
            }
            return out
        }
    }

    /// `gain` at `t`, rising linearly from nothing across `fadeIn` and
    /// falling linearly to nothing across `fadeOut`.
    static func envelope(_ t: Double, gain: Double, fadeIn: ClosedRange<Double>?,
                         fadeOut: ClosedRange<Double>?) -> Double {
        var g = gain
        if let fade = fadeIn, t < fade.upperBound {
            g *= t <= fade.lowerBound ? 0 : (t - fade.lowerBound) / (fade.upperBound - fade.lowerBound)
        }
        if let fade = fadeOut, t > fade.lowerBound {
            g *= t >= fade.upperBound ? 0 : (fade.upperBound - t) / (fade.upperBound - fade.lowerBound)
        }
        return g
    }

    /// Where `track` sounds in a film `film` seconds long, its file being
    /// `duration` seconds: nil when it is not heard — silent, of no known
    /// length, trimmed to nothing, or starting once the film is over. Its
    /// window is the trim kept within the file; it plays once from `start`
    /// (never before the film's start), or loops to the film's end. Each
    /// fade, kept to AudioTrack.fadeRange, is heard only when the track
    /// sounds for more than twice its length. A `film` with no end — a talk
    /// in Present — loops a track for as long as it runs, with no fade out
    /// for one that loops.
    static func span(of track: AudioTrack, duration: Double?, film: Double) -> Span? {
        guard let source = track.audioId, let duration, duration > 0.01 else { return nil }
        let gain = min(max(track.volume, 0), 1)
        let from = min(max(track.trimStart, 0), duration)
        let to = min(track.trimEnd ?? duration, duration)
        let at = max(track.start, 0)
        guard gain > 0, to - from > 0.01, at < film - 0.001 else { return nil }
        let until = track.loop ? film : min(at + (to - from), film)
        let fades = self.fades(fadeIn: track.fadeIn, fadeOut: track.fadeOut, heard: at, until: until)
        return Span(source: source, from: from, to: to, at: at, until: until, loop: track.loop,
                    gain: gain, fadeIn: fades.fadeIn, fadeOut: fades.fadeOut)
    }

    /// Fades of `fadeIn` and `fadeOut` seconds over sound heard from `heard`
    /// until `until`: each kept to AudioTrack.fadeRange, and heard only when
    /// the sound lasts more than twice its length — a track's rule and a
    /// clip's alike. Sound with no end has no fade out.
    static func fades(fadeIn: Double, fadeOut: Double, heard: Double,
                      until: Double) -> (fadeIn: ClosedRange<Double>?, fadeOut: ClosedRange<Double>?) {
        let sounds = until - heard
        func fade(_ seconds: Double) -> Double? {
            let f = min(max(seconds, AudioTrack.fadeRange.lowerBound), AudioTrack.fadeRange.upperBound)
            return f > 0 && sounds > f * 2 ? f : nil
        }
        let fadeIn = fade(fadeIn).map { heard...(heard + $0) }
        let fadeOut = until.isFinite ? fade(fadeOut).map { (until - $0)...until } : nil
        return (fadeIn, fadeOut)
    }

    /// Where a clip playing `playback` is heard on its page, in seconds on
    /// the page's clock, its window being `window` seconds of its file: from
    /// its timing's start until the first of its timing's end, the page's
    /// end (`page`, none for a page with no end) and — played once — the end
    /// of its window at its speed. Nil when that is nothing.
    static func clipHeard(_ playback: ClipPlayback, window: Double, timing: ElementTiming?,
                          page: Double?) -> ClosedRange<Double>? {
        let from = max(timing?.start ?? 0, 0)
        var until = min(timing?.end ?? .infinity, page ?? .infinity)
        if !playback.loop { until = min(until, window / playback.playbackSpeed) }
        return until - from > 0.001 ? from...until : nil
    }

    /// A clip's fades on its page, on the page's clock: rising from where it
    /// is first heard and falling to where it is last heard (`clipHeard`),
    /// once a page however often it goes round — by the rule a track's are
    /// (`fades`), as the Android twin lays them.
    static func clipFades(_ playback: ClipPlayback,
                          heard: ClosedRange<Double>) -> (fadeIn: ClosedRange<Double>?, fadeOut: ClosedRange<Double>?) {
        fades(fadeIn: playback.fadeIn, fadeOut: playback.fadeOut, heard: heard.lowerBound, until: heard.upperBound)
    }

    /// The film's length in seconds: the shown pages, as the video plays
    /// them.
    static func filmLength(design: Design) -> Double {
        let settings = MovieExporter.Settings(design.motion)
        let end = MovieExporter.timeline(design: design, settings: settings).last?.end ?? 0
        return Double(end) / Double(max(settings.fps, 1))
    }

    /// The clips on `page` that are heard while it plays — its own photos
    /// and the master's behind it showing a clip, in drawing order, each
    /// with its timing.
    static func clips(design: Design, page: Page) -> [Clip] {
        design.drawnElements(on: page).compactMap { el -> Clip? in
            guard el.type == .image, let src = el.src, let parts = VideoStore.split(src) else { return nil }
            let playback = el.clip ?? ClipPlayback()
            let timing = el.timing.flatMap { ElementTiming.kept($0) }
            return playback.sounds ? Clip(source: parts.id, playback: playback, timing: timing) : nil
        }
    }

    /// Where page `index` starts in the film, in seconds — the music's
    /// place when that page plays: after the shown pages before it, which
    /// for a hidden page is where it would be.
    static func pageStart(design: Design, index: Int) -> Double {
        let settings = MovieExporter.Settings(design.motion)
        let before = design.visiblePageIndices.filter { $0 < index }
        let end = MovieExporter.timeline(design: design, pages: before, settings: settings).last?.end ?? 0
        return Double(end) / Double(max(settings.fps, 1))
    }

    /// The pages a voice-over started on page `index` plays over, in turn:
    /// the shown pages from there to the film's end. A hidden page is in no
    /// film, so the take starts on the next shown page, where pageStart
    /// lays it; with none after it, the page plays alone.
    static func playedThrough(design: Design, index: Int) -> [Int] {
        let after = design.visiblePageIndices.filter { $0 >= index }
        return after.isEmpty ? [index] : after
    }

    /// The mix of a film laid out as `timeline` at `fps`: for each of its
    /// pages, the clips in `clipsByPage` at the same place, each as long as
    /// `clipDurations` says by source — a clip whose length is not known has
    /// no sound to lay — then each of `tracks` in order, as long as
    /// `trackDurations` says by AudioStore id (see `span`).
    static func plan(timeline: [MovieExporter.Timing], fps: Int, clipsByPage: [[Clip]],
                     clipDurations: [String: Double], tracks: [AudioTrack] = [],
                     trackDurations: [String: Double] = [:]) -> [Segment] {
        let rate = Double(max(fps, 1))
        var out: [Segment] = []
        for (index, timing) in timeline.enumerated() {
            let pageStart = Double(timing.start) / rate
            let pageEnd = Double(timing.end) / rate
            let clips = index < clipsByPage.count ? clipsByPage[index] : []
            for clip in clips {
                let playback = clip.playback
                guard playback.sounds, let duration = clipDurations[clip.source] else { continue }
                // The window clipTime plays: the trim, within the file,
                // taking its length over its speed on the page.
                let start = max(0, playback.start)
                let end = min(playback.end ?? duration, duration)
                let pace = playback.playbackSpeed
                let length = (end - start) / pace
                guard end - start > 0.01 else { continue }
                let gain = min(max(playback.volume, 0), 1)
                // Where its timing lets it be heard: from its start until its
                // end, on the page's clock.
                let heardFrom = pageStart + (clip.timing?.start ?? 0)
                let heardUntil = clip.timing?.end.map { min(pageEnd, pageStart + $0) } ?? pageEnd
                var laid: [Segment] = []
                var at = pageStart
                while at < pageEnd - 0.001 {
                    let stretch = min(length, pageEnd - at)
                    let from = max(at, heardFrom)
                    let to = min(at + stretch, heardUntil)
                    if to - from > 0.001 {
                        laid.append(Segment(source: clip.source, sourceStart: start + (from - at) * pace, at: from,
                                            duration: to - from, gain: gain, speed: pace))
                    }
                    at += stretch
                    // Played once, it is silent while its last frame holds.
                    if !playback.loop { break }
                }
                // Its fades over all it lays on the page, once.
                if let first = laid.first, let last = laid.last {
                    let fades = clipFades(playback, heard: first.at...last.end)
                    for i in laid.indices {
                        laid[i].fadeIn = fades.fadeIn
                        laid[i].fadeOut = fades.fadeOut
                    }
                }
                out += laid
            }
        }
        let film = Double(timeline.last?.end ?? 0) / rate
        for track in tracks {
            let duration = track.audioId.flatMap { trackDurations[$0] }
            if let laid = span(of: track, duration: duration, film: film) { out += laid.segments }
        }
        return out
    }
}
