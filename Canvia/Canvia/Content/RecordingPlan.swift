// A recorded talk laid against its pages, on both phones by one rule
// (Tests/Fixtures/recording-plan.json, the Android twin's RecordingPlan):
// which page is up at a moment, the spans as they are captured, the film
// the MP4 is made of, and where the camera bubble sits.

import CoreGraphics
import Foundation

enum RecordingPlan {

    /// The music's level under the voice: the design's tracks at this share
    /// of their own volume for the whole talk.
    static let duck = 0.3

    /// The camera bubble's distance from the video's edges, as a share of
    /// its shorter side.
    static let bubbleMargin = 0.04

    /// A span shorter than this, in seconds, a page skipped past, is left
    /// out of what is kept.
    static let minSpan = 0.05

    /// The frame rate a talk's film is made at on both phones, whatever the
    /// design's own motion says; its holds are rounded to it.
    static let fps = 30

    /// A rounded bubble's corner radius, as a share of its side.
    static let roundedRadius = 0.2

    /// The longest a page of the film holds: a longer span is split, as a
    /// page's own hold is kept to it (MovieExporter.timeline).
    static let maxHold = 60.0

    /// The page up `t` seconds into the talk: the span holding it, from its
    /// start up to but not including its end; before the first, the first,
    /// and at or past the end, the last. Nil for a talk with no pages.
    static func pageAt(_ recording: Recording, _ t: Double) -> RecordingSpan? {
        let spans = recording.pages
        guard let first = spans.first else { return nil }
        if t < first.start { return first }
        if let holding = spans.first(where: { t >= $0.start && t < $0.end }) { return holding }
        return spans.last(where: { $0.start <= t }) ?? spans.last
    }

    /// The spans as a talk is given: begun with the first page at 0, each
    /// turn to another page at the talk's own seconds — paused time not
    /// counted — and finished at its end. A turn to the page already up
    /// changes nothing; a span shorter than `minSpan` is dropped, the next
    /// starting where it did, so the spans always meet end to start.
    struct Capture {
        private var spans: [RecordingSpan] = []
        private(set) var current: String
        private var from = 0.0

        init(firstPage: String) { current = firstPage }

        mutating func turn(to pageId: String, at: Double) {
            guard pageId != current else { return }
            close(at)
            current = pageId
        }

        private mutating func close(_ at: Double) {
            if at - from >= RecordingPlan.minSpan {
                spans.append(RecordingSpan(pageId: current, start: from, end: at))
                from = at
            }
        }

        /// The spans, the last ending at `at`.
        mutating func finish(at: Double) -> [RecordingSpan] {
            close(at)
            // A last span too short to keep is the one before running on.
            if let last = spans.last, last.end < at { spans[spans.count - 1].end = at }
            return spans
        }
    }

    /// The design as the talk's film: a page for each span — split in two
    /// or more past `maxHold` — in the talk's order, each held for its
    /// span's frames at `fps`, counted from the talk's start so no rounding
    /// builds up, cut from one to the next; and the voice under it as a
    /// track, the design's own tracks `duck`ed beneath. A span whose page
    /// has gone shows the page before it, or the first.
    static func film(_ design: Design, _ recording: Recording, fps: Int) -> Design {
        let rate = Double(max(fps, 1))
        func frame(_ t: Double) -> Double { (t * rate + 0.5).rounded(.down) }
        var pages: [Page] = []
        var last = design.pages.first
        for span in recording.pages {
            guard let page = design.pages.first(where: { $0.id == span.pageId }) ?? last else { continue }
            last = page
            var from = span.start
            while span.end - from > 1e-9 {
                let to = min(span.end, from + maxHold)
                let hold = (frame(to) - frame(from)) / rate
                if hold > 0 {
                    var shown = page
                    shown.id = UID.make("page")
                    shown.hidden = nil
                    shown.holdSeconds = hold
                    shown.transition = "cut"
                    pages.append(shown)
                }
                from = to
            }
        }
        var filmed = design
        filmed.pages = pages.isEmpty ? Array(design.pages.prefix(1)) : pages
        var tracks = design.audioTracks.map { track -> AudioTrack in
            var ducked = track
            ducked.volume = track.volume * duck
            return ducked
        }
        tracks.append(AudioTrack(id: recording.id, src: AudioTrack.src(recording.audio), volume: 1,
                                 name: AudioTracks.firstVoiceOver))
        filmed.audioTracks = tracks
        return filmed
    }

    /// The film's holds, in seconds, page by page — what the fixture lists.
    static func holds(_ design: Design, _ recording: Recording, fps: Int) -> [Double] {
        film(design, recording, fps: fps).pages.map { $0.holdSeconds ?? 0 }
    }

    /// Where the camera bubble sits in a `width` × `height` video, top-left
    /// origin: a square `size` of the shorter side across, `bubbleMargin`
    /// of it from the two edges of its corner.
    static func bubbleRect(_ bubble: RecordingBubble, width: Double, height: Double) -> CGRect {
        let short = min(width, height)
        let d = bubble.size * short
        let m = bubbleMargin * short
        let left = bubble.corner.hasSuffix("Left")
        let top = bubble.corner.hasPrefix("top")
        return CGRect(x: left ? m : width - m - d, y: top ? m : height - m - d, width: d, height: d)
    }

    /// The corner radius of a bubble `side` across: half of it for a
    /// circle, `roundedRadius` of it for "rounded".
    static func bubbleRadius(_ bubble: RecordingBubble, side: Double) -> Double {
        bubble.shape == "rounded" ? side * roundedRadius : side / 2
    }
}
