// Everything heard in the video: each clip's own sound on its page, and the
// design's music under the whole film. The plan is pure — the same numbers
// as the Android twin's, from the same table of tests — and Soundtrack.mux
// runs it through AVFoundation on the finished MP4.
//
// A clip sounds while its page plays: its trimmed window laid from the
// page's start, again and again when it loops, never past the page's last
// frame. A muted or silent clip, or one playing at another speed, is not in
// the mix; nor is a clip behind a page or filling a shape, or a GIF, which
// is a photo. Hidden pages are not in the film, so their clips are not
// either. The music follows Soundtrack.plan, its fade and all.

import Foundation

enum AudioMix {

    /// A clip on a page that may sound: `source` is its id, as
    /// `Segment.source` names it.
    struct Clip: Equatable {
        var source: String
        var playback: ClipPlayback
    }

    /// The design's music: its id, its length in seconds and its volume.
    struct Music: Equatable {
        var source: String
        var duration: Double
        var volume: Double
    }

    /// One stretch of one source's sound: from `sourceStart` seconds into
    /// the file, laid at `at` seconds into the video for `duration` seconds,
    /// at `gain` — falling to nothing across `fadeOut` when it has one.
    struct Segment: Equatable {
        var source: String, sourceStart: Double, at: Double, duration: Double
        var gain: Double
        var fadeOut: ClosedRange<Double>? = nil

        var end: Double { at + duration }

        /// How loud it is `t` seconds into the video.
        func gainAt(_ t: Double) -> Double {
            guard let fade = fadeOut, t > fade.lowerBound else { return gain }
            guard t < fade.upperBound else { return 0 }
            return gain * (fade.upperBound - t) / (fade.upperBound - fade.lowerBound)
        }
    }

    /// The clips on `page` that are heard while it plays — its own photos
    /// and the master's behind it showing a clip, in drawing order.
    static func clips(design: Design, page: Page) -> [Clip] {
        (design.masterElements(behind: page) + page.elements).compactMap { el -> Clip? in
            guard el.type == .image, let src = el.src, let parts = VideoStore.split(src) else { return nil }
            let playback = el.clip ?? ClipPlayback()
            return playback.sounds ? Clip(source: parts.id, playback: playback) : nil
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

    /// The mix of a film laid out as `timeline` at `fps`: for each of its
    /// pages, the clips in `clipsByPage` at the same place, each as long as
    /// `clipDurations` says by source — a clip whose length is not known has
    /// no sound to lay — then the `soundtrack`, if any, under the whole film.
    static func plan(timeline: [MovieExporter.Timing], fps: Int, clipsByPage: [[Clip]],
                     clipDurations: [String: Double], soundtrack: Music?) -> [Segment] {
        let rate = Double(max(fps, 1))
        var out: [Segment] = []
        for (index, timing) in timeline.enumerated() {
            let pageStart = Double(timing.start) / rate
            let pageEnd = Double(timing.end) / rate
            let clips = index < clipsByPage.count ? clipsByPage[index] : []
            for clip in clips {
                let playback = clip.playback
                guard playback.sounds, let duration = clipDurations[clip.source] else { continue }
                // The window clipTime plays: the trim, within the file.
                let start = max(0, playback.start)
                let end = min(playback.end ?? duration, duration)
                let length = end - start
                guard length > 0.01 else { continue }
                let gain = min(max(playback.volume, 0), 1)
                var at = pageStart
                while at < pageEnd - 0.001 {
                    let stretch = min(length, pageEnd - at)
                    out.append(Segment(source: clip.source, sourceStart: start, at: at, duration: stretch, gain: gain))
                    at += stretch
                    // Played once, it is silent while its last frame holds.
                    if !playback.loop { break }
                }
            }
        }
        if let soundtrack {
            let film = Double(timeline.last?.end ?? 0) / rate
            let music = Soundtrack.plan(audioDuration: soundtrack.duration, videoDuration: film)
            let gain = min(max(soundtrack.volume, 0), 1)
            if gain > 0 {
                for s in music.segments {
                    out.append(Segment(source: soundtrack.source, sourceStart: s.sourceStart, at: s.at,
                                       duration: s.duration, gain: gain, fadeOut: music.fadeOut))
                }
            }
        }
        return out
    }
}
