// The editor's timeline as pure functions of time: where each shown page's
// block sits, what a dragged edge sets the hold to, how a page splits at the
// playhead — its holds, and where its clips pick up — and when an element
// with a timing of its own shows. The Android twin has the same functions
// with the same numbers (Timeline), and both phones test the same rows.

import Foundation

/// When an element shows within its page: from `start` seconds into the
/// page until `end`, nil being the page's end. Written as the element's
/// `timing` object, with the Android twin's keys; no key at all is the
/// whole page, and so is a timing from 0 with no end, which is never kept.
/// Played by Present, Play and the video and GIF; a still export and the
/// editor at rest show the element whatever its timing.
struct ElementTiming: Codable, Equatable {
    var start: Double = 0
    var end: Double?

    private enum CodingKeys: String, CodingKey { case start, end }

    init(start: Double = 0, end: Double? = nil) {
        self.start = start
        self.end = end
    }

    /// Leniently, as a clip is read: a start that is missing or cannot be
    /// read is 0, never below it; an end that cannot be read is none.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let start = (try? c.decodeIfPresent(Double.self, forKey: .start)) ?? 0
        self.start = start.isFinite ? max(0, start) : 0
        end = (try? c.decodeIfPresent(Double.self, forKey: .end)).flatMap { $0.isFinite ? $0 : nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start)
        try c.encodeIfPresent(end, forKey: .end)
    }

    /// Shown for the whole page: what no timing at all means.
    var isWholePage: Bool { start <= 0 && end == nil }

    /// Whether an element timed `timing` shows `t` seconds into its page:
    /// from its start, up to its end — gone at the end itself, where an exit
    /// timed to it is over — and always with no timing.
    static func shows(_ timing: ElementTiming?, at t: Double) -> Bool {
        guard let timing else { return true }
        if t < timing.start { return false }
        if let end = timing.end, t >= end { return false }
        return true
    }

    /// Kept only when it is not the whole page.
    static func kept(_ timing: ElementTiming) -> ElementTiming? {
        timing.isWholePage ? nil : timing
    }

    /// "Show from playhead": shown from `t` (to the tenth), an end at or
    /// before it dropped.
    static func showing(_ timing: ElementTiming?, from t: Double) -> ElementTiming? {
        let at = Timeline.tenth(max(0, t))
        var out = timing ?? ElementTiming()
        out.start = at
        if let end = out.end, end <= at { out.end = nil }
        return kept(out)
    }

    /// "Hide from playhead": gone from `t` (to the tenth), a start at or
    /// after it going back to the page's start. Nothing changes at the
    /// page's very start, which would hide the element all through it.
    static func hiding(_ timing: ElementTiming?, from t: Double) -> ElementTiming? {
        let at = Timeline.tenth(t)
        guard at > 0 else { return timing }
        var out = timing ?? ElementTiming()
        out.end = at
        if out.start >= at { out.start = 0 }
        return kept(out)
    }
}

enum Timeline {

    /// One page's block: from `x`, `width` across, in points.
    struct Block: Equatable {
        var x: Double
        var width: Double
    }

    /// The shortest a split leaves either page, in seconds.
    static let splitMargin = 0.5

    /// `seconds` to the nearest tenth, which is what the timeline snaps to.
    static func tenth(_ seconds: Double) -> Double {
        (seconds * 10).rounded() / 10
    }

    /// How long `page` holds: its own hold, else the document's.
    static func hold(of page: Page, in design: Design) -> Double {
        page.holdSeconds ?? design.motion?.secondsPerPage ?? MotionSettings().secondsPerPage
    }

    /// The pages the timeline shows, by index — those not hidden, as the
    /// video plays them — and how long each holds.
    static func pages(of design: Design) -> [(index: Int, hold: Double)] {
        design.visiblePageIndices.map { (index: $0, hold: hold(of: design.pages[$0], in: design)) }
    }

    /// The blocks for pages holding `holds` seconds at `scale` points a
    /// second: side by side from 0 with no gap, each as wide as its hold.
    static func blocks(holds: [Double], scale: Double) -> [Block] {
        var x = 0.0
        return holds.map { hold in
            defer { x += hold * scale }
            return Block(x: x, width: hold * scale)
        }
    }

    /// The hold a block's right edge sets, dragged `dx` points from where
    /// it stood at `hold` seconds, at `scale` points a second: to the
    /// nearest tenth, kept to MotionSettings.pageHoldRange (0.5...60). At
    /// no scale at all, the hold as it stood.
    static func draggedHold(_ hold: Double, by dx: Double, scale: Double) -> Double {
        let seconds = scale > 0 ? tenth(hold + dx / scale) : tenth(hold)
        return min(max(seconds, MotionSettings.pageHoldRange.lowerBound), MotionSettings.pageHoldRange.upperBound)
    }

    /// Which of pages holding `holds` seconds the moment `t` seconds into
    /// the film falls on, and how far into it: a page owns its start, not
    /// its end; before the film is its first page's start, and past it its
    /// last page's end. Not rounded: what is done at a moment rounds it
    /// then (Show and Hide from playhead, Split page), as on Android.
    static func locate(_ t: Double, holds: [Double]) -> (page: Int, time: Double) {
        guard !holds.isEmpty else { return (0, 0) }
        var start = 0.0
        for (i, hold) in holds.enumerated() {
            if t < start + hold || i == holds.count - 1 {
                return (i, min(max(t - start, 0), hold))
            }
            start += hold
        }
        return (holds.count - 1, holds[holds.count - 1])
    }

    /// The holds of a page `hold` seconds long split at `t`: the cut to the
    /// nearest tenth, and the rest, also to the tenth; nil when either would
    /// be under `splitMargin`.
    static func splitHolds(hold: Double, at t: Double) -> (first: Double, second: Double)? {
        let first = tenth(t)
        let second = tenth(hold - first)
        guard first >= splitMargin - 1e-9, second >= splitMargin - 1e-9 else { return nil }
        return (first, second)
    }

    /// Where a clip starts on the second page of a split `t` seconds in, so
    /// it goes on from where the first page left it: the moment playback
    /// shows `t` seconds into the page (VideoStore.clipTime) — `t` times its
    /// speed further on, round again within its trim when it loops, held a
    /// hundredth short of its end when it does not, straight on when no end
    /// is known. To the hundredth, as the Android twin's splitClip.
    static func advancedClipStart(_ clip: ClipPlayback, by t: Double, duration: Double?) -> Double {
        (VideoStore.clipTime(t, clip: clip, duration: duration) * 100).rounded() / 100
    }

    /// An element's timing on the second page of a split `t` seconds in:
    /// the same moments, `t` earlier, none before the page's start. One
    /// whose end came before the cut never shows there (0 to 0).
    static func shiftedTiming(_ timing: ElementTiming?, by t: Double) -> ElementTiming? {
        guard let timing else { return nil }
        let start = tenth(max(0, timing.start - t))
        let end = timing.end.map { tenth(max(0, $0 - t)) }
        return ElementTiming.kept(ElementTiming(start: start, end: end))
    }

    /// Whether an element timed `timing` keeps its entrance on the second
    /// page of a split at `cut`: when it comes in at the cut or after, so
    /// its entrance plays there, where the film shows it come in. The
    /// Android twin's entranceStaysAfter, row for row.
    static func entranceStaysAfter(_ timing: ElementTiming?, cut: Double) -> Bool {
        (timing?.start ?? 0) >= cut - 1e-9
    }

    /// Whether an element timed `timing` keeps its exit on the first page
    /// of a split at `cut`: when its timing ends at the cut or before, so
    /// its exit plays out there. The Android twin's exitStaysBefore, row
    /// for row.
    static func exitStaysBefore(_ timing: ElementTiming?, cut: Double) -> Bool {
        guard let end = timing?.end else { return false }
        return end <= cut + 1e-9
    }

    /// `page`, `hold` seconds long, split at `t` into two pages that play
    /// as it did: nil when `t` is within `splitMargin` of either end.
    ///
    /// The first keeps the page's id and its elements', holds for the cut,
    /// and gives way to the second with a cut — no transition, so a clip
    /// runs on unbroken — its exits dropped, but not one timed to end before
    /// the cut (`exitStaysBefore`). The second is a copy with new ids,
    /// holding for the rest, with the page's transition; each clip on it
    /// picks up where the first left it (`duration` gives a clip's file
    /// length by VideoStore id), its entrances dropped — loops, which are
    /// not entrances, kept on both, and so is one timed to start after the
    /// cut (`entranceStaysAfter`) — its exits kept, and its timings moved
    /// earlier by the cut. Both keep every element; a caption box's cues
    /// are cut between the halves (Captions.cut).
    static func split(_ page: Page, at t: Double, hold: Double,
                      duration: (String) -> Double?) -> (first: Page, second: Page)? {
        guard let holds = splitHolds(hold: hold, at: t) else { return nil }
        var first = page
        first.holdSeconds = holds.first
        first.transition = "cut"
        first.transitionSeconds = nil
        for i in first.elements.indices {
            if !exitStaysBefore(first.elements[i].timing, cut: holds.first) { first.elements[i].exitAnimation = nil }
            // Its captions end at the cut; the rest go to the second half.
            if var captions = first.elements[i].captions {
                captions.cues = Captions.cut(captions.cues, at: holds.first).first
                first.elements[i] = Captions.on(first.elements[i], captions)
            }
        }
        var second = Copies.of(page)
        second.holdSeconds = holds.second
        for i in second.elements.indices {
            var el = second.elements[i]
            if el.animation?.loops != true, !entranceStaysAfter(el.timing, cut: holds.first) { el.animation = nil }
            el.timing = shiftedTiming(el.timing, by: holds.first)
            if let src = el.src, let parts = VideoStore.split(src) {
                var clip = el.clip ?? ClipPlayback()
                clip.start = advancedClipStart(clip, by: holds.first, duration: duration(parts.id))
                el.clip = clip.isDefault ? nil : clip
            }
            if var captions = el.captions {
                captions.cues = Captions.cut(captions.cues, at: holds.first).second
                el = Captions.on(el, captions)
            }
            second.elements[i] = el
        }
        return (first, second)
    }

    /// An element's entrance, exit and timing at the clock's moment: none of
    /// it outside its timing; its entrance counted from its timing's start;
    /// with a timing's end, its exit over at that end or the page's,
    /// whichever comes first — played on the page's own clock — else by the
    /// page's hold, on `exitTime` where Present holds exits back. The
    /// Android twin's Timeline.motion.
    static func motion(of el: Element, time: Double, hold: Double, exitTime: Double?,
                       text: String?) -> ElementAnimation.State {
        guard ElementTiming.shows(el.timing, at: time) else {
            var hidden = ElementAnimation.State()
            hidden.opacity = 0
            return hidden
        }
        let size = max(el.w, el.h)
        let start = el.timing?.start ?? 0
        let entrance = el.animation?.state(at: time - start, text: text, size: size) ?? .settled
        guard let exit = el.exitAnimation else { return entrance }
        if let end = el.timing?.end {
            // exitState is over `delay` before the hold it is given.
            let over = min(end, hold) + exit.delay
            return entrance.combined(with: exit.exitState(at: time, hold: over, size: size))
        }
        return entrance.combined(with: exit.exitState(at: exitTime ?? time, hold: hold, size: size))
    }
}
