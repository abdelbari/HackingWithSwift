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
//
// A clip or a track with Enhance voice on is read from its enhanced sound
// (VoiceEnhance, AudioStore.enhancedURL): its stretches name their source
// with ".enh" after it (`enhancedSource`), which the mix finds that file by.
// A track that is a clip's detached sound names the clip, "video:<id>", and
// is read from the clip's file.

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

    /// What a stretch of `source`'s enhanced sound names its source.
    static func enhancedSource(_ source: String) -> String { source + ".enh" }

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
    /// A clip playing behind the page (BackgroundClip) is heard first, for
    /// the whole page, as the Android twin's mix hears it.
    static func clips(design: Design, page: Page) -> [Clip] {
        var behind: [Clip] = []
        if let bg = page.backgroundClip, bg.playback.sounds, let parts = VideoStore.split(bg.src) {
            behind.append(Clip(source: parts.id, playback: bg.playback))
        }
        return behind + design.drawnElements(on: page).compactMap { el -> Clip? in
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

    /// Whether `track` is a recorded voice-over: named as a recording is
    /// when it becomes a track — "Voice-over" or "Voice-over 2" …, in
    /// English as the Android twin names it, or in the app's language as
    /// AudioTracks.voiceOverName names it here — as the audio panel tells
    /// one by its mic.
    static func isVoiceOver(_ track: AudioTrack) -> Bool {
        track.name.hasPrefix("Voice-over") || track.name.hasPrefix(AudioTracks.firstVoiceOver)
    }

    /// The mix the MP4 of `pages` of `design` carries, at `settings`: their
    /// timeline, each page's clips and every track, by `plan` — clips as
    /// long as `clipDurations` says by source, songs as `trackDurations`
    /// says by their store id.
    static func filmPlan(design: Design, pages: [Int], settings: MovieExporter.Settings,
                         clipDurations: [String: Double], trackDurations: [String: Double]) -> [Segment] {
        plan(timeline: MovieExporter.timeline(design: design, pages: pages, settings: settings), fps: settings.fps,
             clipsByPage: pages.map { clips(design: design, page: design.pages[$0]) },
             clipDurations: clipDurations, tracks: design.audioTracks, trackDurations: trackDurations)
    }

    /// The audio download's mix ("m4a"): the MP4's own (`filmPlan`) — the
    /// same timeline, fades, speeds, volumes and beat sync — less the
    /// voice-overs (`isVoiceOver`) without `voice`, and less every clip's
    /// own sound and every clip's detached sound (a "video:" track) without
    /// `clipSound`. With both on it is the film's, segment for segment. The
    /// Android twin's AudioMix.audioPlan, with the shared fixture
    /// audio-download.json.
    static func audioPlan(design: Design, pages: [Int], settings: MovieExporter.Settings,
                          clipDurations: [String: Double], trackDurations: [String: Double],
                          voice: Bool, clipSound: Bool) -> [Segment] {
        let tracks = design.audioTracks.filter {
            (voice || !isVoiceOver($0)) && (clipSound || !AudioTrack.isClipSound($0.src))
        }
        return plan(timeline: MovieExporter.timeline(design: design, pages: pages, settings: settings),
                    fps: settings.fps,
                    clipsByPage: pages.map { clipSound ? clips(design: design, page: design.pages[$0]) : [] },
                    clipDurations: clipDurations, tracks: tracks, trackDurations: trackDurations)
    }

    /// Whether `segments` are heard at all: one at least that lasts and is
    /// not silent — what the File type picker offers Audio (M4A) for.
    static func audible(_ segments: [Segment]) -> Bool {
        segments.contains { $0.duration > 0.001 && $0.gain > 0 }
    }

    /// How long the audio download of `pages` runs at `settings` — the
    /// design's own motion settings — in seconds: their timeline's whole
    /// length, silence and all, as the MP4's.
    static func seconds(design: Design, pages: [Int], settings: MovieExporter.Settings) -> Double {
        let end = MovieExporter.timeline(design: design, pages: pages, settings: settings).last?.end ?? 0
        return Double(end) / Double(max(settings.fps, 1))
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
                let source = playback.enhance ? enhancedSource(clip.source) : clip.source
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
                        laid.append(Segment(source: source, sourceStart: start + (from - at) * pace, at: from,
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
            guard let laid = span(of: track, duration: duration, film: film) else { continue }
            out += laid.segments.map { segment -> Segment in
                var heard = segment
                if track.enhance { heard.source = enhancedSource(segment.source) }
                return heard
            }
        }
        return out
    }
}
