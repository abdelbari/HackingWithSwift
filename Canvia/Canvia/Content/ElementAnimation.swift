// Per-element entrance animation, as a document field with a pure evaluator.
//
// An element can arrive: fade in, rise from below, pop from small, slide in
// from a side, or — for text — reveal by letter or by word. The document
// stores what and when; `ElementAnimation.state(at:)` turns a time into an
// opacity, offset, scale and a count of visible characters, and the canvas
// preview, the video and the GIF all read that one function. Ken Burns is
// the same idea for a photo: a slow drift of its crop over the page's hold.
//
// An element can leave the same way, as its page ends: an exit is the same
// three fields under `exitAnimation`, its delay counted back from the end of
// the page, read by `exitState(at:hold:size:)` and combined with the
// entrance — at parity with the Android twin's ElementAnimation.exitState.
//
// A chart can grow in ("grow"): its columns rise from their foot, its bars
// from their left end, its slices and rings sweep round, its lines draw on
// left to right and its points pop, series after series, its words fading
// in at the end — the same maths as the Android twin's, from the part's
// chartPart. Any other element given it fades in, as a build without it
// plays it.
//
// Text can also move a unit at a time — by letter, word or line, as its
// `by` says ("letter", "word" or "line"; when it says none, a typewriter
// goes by letter and word by word by word, as they always have) — in
// Canva's text-only styles: ascend, shift, merge, block, burst, bounceIn,
// roll, skate, spread, clarify, tumble and writeOn. `unitFrames` gives each
// unit's place, size, turn, opacity, blur and the share of it shown at a
// moment, and the canvas draws each unit of the laid-out words so; leaving,
// the same frames play backwards (exitState). The Android twin's
// ElementAnimation.unitFrames, frame for frame.

import Foundation

struct ElementAnimation: Codable, Equatable {
    /// "grow" | "fade" | "rise" | "pop" | "slideLeft" | "slideRight" | a text kind (textKindOrder) | a loop
    var kind: String = "fade"
    /// Seconds after the page starts.
    var delay: Double = 0
    var duration: Double = 0.6
    /// For text: "letter", "word" or "line" — what moves as one; nil is the
    /// kind's own (defaultBy).
    var by: String?

    static let kinds: [String] = [grow, "fade", "rise", "pop", "slideLeft", "slideRight"] + textKindOrder
        + ["pulse", "wiggle", "bounce", "spin"]
    /// A chart's entrance, its parts growing from their baseline.
    static let grow = "grow"
    /// How long after each other a chart's series start to grow, and how
    /// long a chart takes, delay aside, when Grow is picked.
    static let growStagger = 0.08
    static let growDuration = 1.0
    /// The text-only kinds, in the order both phones offer them.
    static let textKindOrder: [String] = ["typewriter", "words", "letterPop", "lineRise",
                                "ascend", "shift", "merge", "block", "burst", "bounceIn", "roll", "skate",
                                "spread", "clarify", "tumble", "writeOn"]
    static let textKinds = Set(textKindOrder)
    /// The kinds that move each unit of the words on its own (unitFrames),
    /// rather than cut the words to those shown so far.
    static let unitKinds: Set<String> = ["ascend", "shift", "merge", "block", "burst", "bounceIn", "roll", "skate",
                                         "spread", "clarify", "tumble", "writeOn"]
    /// What a text kind can move as one, in the order the Animate by row
    /// lists them.
    static let unitChoices = ["letter", "word", "line"]
    /// Loops never settle: a sticker that keeps moving for as long as the
    /// page is shown.
    static let loopKinds: Set<String> = ["pulse", "wiggle", "bounce", "spin"]
    static let loopPeriod = 1.2

    var loops: Bool { Self.loopKinds.contains(kind) }

    /// How long one cycle of a loop takes, in seconds; nil for a move that
    /// settles. What Check accessibility measures for flashing.
    var period: Double? { loops ? Self.loopPeriod : nil }

    /// The ways out, in the order the Exit menu offers them. Any other kind
    /// leaves as a fade.
    static let exitKinds = ["fade", "rise", "pop", "slideLeft", "slideRight"]
    /// An exit's length when it is picked, and the gap between elements
    /// leaving together.
    static let exitDuration = 0.6
    static let exitStagger = 0.15
    /// The longest Present holds back for exits before the page turns.
    static let maxExitSpan = 2.0

    static func exitName(_ kind: String?) -> String {
        switch kind {
        case nil: return tr("No exit")
        case "rise": return tr("Rise")
        case "pop": return tr("Pop")
        case "slideLeft": return tr("Slide left")
        case "slideRight": return tr("Slide right")
        case let kind? where unitKinds.contains(kind): return name(kind)
        default: return tr("Fade")
        }
    }

    static func name(_ kind: String) -> String {
        switch kind {
        case "grow": return tr("Grow")
        case "fade": return tr("Fade in")
        case "rise": return tr("Rise")
        case "pop": return tr("Pop")
        case "slideLeft": return tr("Slide from right")
        case "slideRight": return tr("Slide from left")
        case "typewriter": return tr("Typewriter")
        case "words": return tr("Word by word")
        case "letterPop": return tr("Letter pop")
        case "lineRise": return tr("Line rise")
        case "ascend": return tr("Ascend")
        case "shift": return tr("Shift")
        case "merge": return tr("Merge")
        case "block": return tr("Block")
        case "burst": return tr("Burst")
        case "bounceIn": return tr("Bounce in")
        case "roll": return tr("Roll")
        case "skate": return tr("Skate")
        case "spread": return tr("Spread")
        case "clarify": return tr("Clarify")
        case "tumble": return tr("Tumble")
        case "writeOn": return tr("Write on")
        case "pulse": return tr("Pulse (loop)")
        case "wiggle": return tr("Wiggle (loop)")
        case "bounce": return tr("Bounce (loop)")
        case "spin": return tr("Spin (loop)")
        default: return kind
        }
    }

    /// What the element looks like `t` seconds into the page.
    struct State: Equatable {
        var opacity: Double = 1
        var offset: CGSize = .zero
        var scale: Double = 1
        /// Degrees, for the looping moves.
        var rotation: Double = 0
        /// For text reveals: how many characters are shown; nil is all.
        var visibleCharacters: Int?
        /// A chart part growing (grow): its width and height as shares of
        /// their own, about the point `anchorX`, `anchorY` of its box (0 its
        /// left or top, 1 its right or bottom) — a column from its foot, a
        /// bar from its left end.
        var scaleX: Double = 1
        var scaleY: Double = 1
        var anchorX: Double = 0.5
        var anchorY: Double = 0.5
        /// The share of its box shown from the left, a line drawing on.
        var reveal: Double = 1
        /// The share of its sweep a slice or ring is drawn to
        /// (DataGraphics.swept).
        var sweep: Double = 1
        /// Text moving a unit at a time (unitKinds): the move, and the
        /// moment of it the units are drawn at; nil draws the words whole.
        var unitClock: UnitClock?
        static let settled = State()

        /// Whether nothing of the element shows: grown from nothing, or
        /// swept or drawn on to none of it yet.
        var showsNothing: Bool { scaleX <= 0 || scaleY <= 0 || reveal <= 0 || sweep <= 0 }

        /// This state with an exit's on top: opacities and scales
        /// multiply, offsets and turns add; the characters shown are this
        /// one's, since only an entrance reveals text.
        func combined(with exit: State) -> State {
            var s = self
            s.opacity *= exit.opacity
            s.offset = CGSize(width: offset.width + exit.offset.width, height: offset.height + exit.offset.height)
            s.scale *= exit.scale
            s.rotation += exit.rotation
            s.scaleX *= exit.scaleX
            s.scaleY *= exit.scaleY
            if scaleX == 1 && scaleY == 1 {
                s.anchorX = exit.anchorX
                s.anchorY = exit.anchorY
            }
            s.reveal *= exit.reveal
            s.sweep *= exit.sweep
            s.unitClock = exit.unitClock ?? unitClock
            return s
        }
    }

    /// 0 before the delay, 1 after the duration, eased in between.
    func progress(at t: Double) -> Double {
        guard duration > 0 else { return t >= delay ? 1 : 0 }
        let raw = (t - delay) / duration
        let clamped = min(max(raw, 0), 1)
        // Ease-out cubic: arrives fast, settles gently.
        return 1 - pow(1 - clamped, 3)
    }

    /// `el` is the element moving: a grow needs it, the chart part it
    /// grows; anything else that grows fades in.
    func state(at t: Double, text: String? = nil, size: Double = 100, el: Element? = nil) -> State {
        if loops { return loopState(at: t) }
        let p = progress(at: t)
        if p >= 1 { return .settled }
        if kind == Self.grow, let el { return growState(at: t, el) }
        var s = State()
        switch kind {
        case "rise":
            s.opacity = p
            s.offset = CGSize(width: 0, height: (1 - p) * size * 0.3)
        case "pop":
            s.opacity = min(1, p * 2)
            s.scale = 0.4 + 0.6 * p
        case "slideLeft":
            s.opacity = min(1, p * 2)
            s.offset = CGSize(width: (1 - p) * size, height: 0)
        case "slideRight":
            s.opacity = min(1, p * 2)
            s.offset = CGSize(width: -(1 - p) * size, height: 0)
        case "typewriter", "words", "letterPop", "lineRise":
            let linear = min(max((t - delay) / max(duration, 0.001), 0), 1)
            s.visibleCharacters = Self.revealed(text ?? "", by: unit, share: linear)
            if kind == "lineRise" {
                s.offset = CGSize(width: 0, height: (1 - p) * size * 0.15)
                s.opacity = p
            }
        case _ where Self.unitKinds.contains(kind):
            // Each unit moves on its own, drawn so by the canvas.
            s.unitClock = UnitClock(animation: self, time: t)
        default: // fade
            s.opacity = p
        }
        return s
    }

    /// How many characters of `text` a reveal by `by` shows `share` of the
    /// way through: whole words at a time (split at spaces) by "word",
    /// whole lines by "line", else letters — rounded up, so the first
    /// shows as soon as it starts.
    static func revealed(_ text: String, by: String, share: Double) -> Int {
        switch by {
        case "word", "line":
            let parts = text.split(separator: by == "line" ? "\n" : " ", omittingEmptySubsequences: false)
            let shown = Int((Double(parts.count) * share).rounded(.up))
            return parts.prefix(shown).joined(separator: by == "line" ? "\n" : " ").count
        default:
            return Int((Double(text.count) * share).rounded(.up))
        }
    }

    /// A chart part `el` `t` seconds into its page as grow has it, the same
    /// on both phones. Its series parts ("series:<n>") start growStagger ×
    /// n seconds after the delay — at most 90% of the duration — and are in
    /// by its end, each eased as progress eases:
    /// - columns (and stacked) rise from their foot, scaleY from the bottom
    ///   edge — values are never below 0, so never from the top;
    /// - bars (stacked, and a progress bar) grow from their left end;
    /// - a pie's or a donut's slices, a progress ring's and a dial's arc
    ///   sweep round, drawn to the share of their sweep reached;
    /// - lines and areas draw on left to right, a box growing from the left
    ///   (reveal) — a line's points pop, as a scatter's and a bubble chart's
    ///   do, and a radar's outlines and a pictogram's icons;
    /// - a funnel's stages widen from their middle, a heat map's cells fade in.
    /// Labels, values, the legend and axis titles fade in over the last 30%
    /// of the duration; gridlines and axes fade in over all of it. A part of
    /// no chart fades in.
    private func growState(at t: Double, _ el: Element) -> State {
        var s = State()
        guard let spec = el.chart, let part = el.chartPart else {
            s.opacity = progress(at: t)
            return s
        }
        let linear = duration <= 0 ? (t >= delay ? 1.0 : 0.0) : min(max((t - delay) / duration, 0), 1)
        guard part.hasPrefix("series:") else {
            s.opacity = part == "grid" || part == "axis" ? progress(at: t) : min(max((linear - 0.7) / 0.3, 0), 1)
            return s
        }
        let n = Int(part.dropFirst("series:".count)) ?? 0
        let lag = min(Self.growStagger * Double(n), duration * 0.9)
        let q = ElementAnimation(kind: kind, delay: delay + lag, duration: duration - lag).progress(at: t)
        if q >= 1 { return .settled }
        // A kind this build does not know pops, as a scatter's points do.
        switch DataGraphics.ChartKind(rawValue: spec.kind) ?? .scatter {
        case .column, .stackedColumn:
            s.scaleY = q
            s.anchorY = 1
        case .bar, .stackedBar, .progressBar:
            s.scaleX = q
            s.anchorX = 0
        case .pie, .donut, .progressRing, .progressDial:
            s.sweep = q
        case .line, .area:
            if el.shapeId == "circle" {
                s.opacity = min(1, q * 2)
                s.scale = 0.4 + 0.6 * q
            } else {
                s.reveal = q
            }
        case .funnel:
            s.scaleX = q
        case .heatmap:
            s.opacity = q
        default:
            s.opacity = min(1, q * 2)
            s.scale = 0.4 + 0.6 * q
        }
        return s
    }

    /// Whether Grow is offered for `elements`: some of them are parts of a
    /// chart.
    static func canGrow(_ elements: [Element]) -> Bool {
        elements.contains { $0.chart != nil && $0.chartPart != nil }
    }

    /// `kind` as the entrance of each of `elements`, as the Android twin
    /// applies it: nil takes entrances away; a text kind passes over all
    /// but text; each other thing 0.15 s after the one before, for 0.6 s.
    /// Grow gives every part of a chart one delay and one duration
    /// (growDuration), its series staggered by the grow itself, each chart
    /// and each other thing 0.15 s after the one before.
    static func applied(_ elements: [Element], kind: String?) -> [Element] {
        var n = 0
        var charts: [String: Double] = [:]
        return elements.map { el in
            var out = el
            guard let kind else {
                out.animation = nil
                return out
            }
            if textKinds.contains(kind) && el.type != .text { return el }
            if kind == grow {
                var delay = Double(n) * 0.15
                if let chart = el.chart?.id, let shared = charts[chart] {
                    delay = shared
                } else {
                    if let chart = el.chart?.id { charts[chart] = delay }
                    n += 1
                }
                out.animation = ElementAnimation(kind: kind, delay: delay, duration: growDuration)
                return out
            }
            out.animation = ElementAnimation(kind: kind, delay: Double(n) * 0.15, duration: 0.6)
            n += 1
            return out
        }
    }

    /// When the element is fully in; a loop is never in.
    var end: Double { loops ? .infinity : delay + duration }

    /// As an exit: what the element looks like `t` seconds into a page held
    /// `hold` seconds. It is gone by `delay` seconds before the end, having
    /// taken `duration` to go — settled before that, eased in (q cubed)
    /// while it goes, so it leaves slowly and then quickly.
    func exitState(at t: Double, hold: Double, size: Double = 100) -> State {
        let end = hold - delay
        let begin = end - duration
        // Gone from its end, whatever its length — even none, or one
        // below nothing from a file — as Android has it.
        if t <= begin && t < end { return .settled }
        let q = duration > 0 ? min(max((t - begin) / duration, 0), 1) : 1
        let e = t >= end ? 1 : q * q * q
        var s = State()
        if Self.unitKinds.contains(kind) {
            // The entrance's frames played backwards: the moment as far
            // from the end of an entrance as this is into the exit.
            if t >= end {
                s.opacity = 0
            } else {
                let entrance = ElementAnimation(kind: kind, delay: 0, duration: duration, by: by)
                s.unitClock = UnitClock(animation: entrance, time: duration * (1 - q))
            }
            return s
        }
        switch kind {
        case "rise":
            s.opacity = 1 - e
            s.offset = CGSize(width: 0, height: -e * size * 0.3)
        case "pop":
            s.opacity = min(1, (1 - e) * 2)
            s.scale = 1 - 0.6 * e
        case "slideLeft":
            s.opacity = min(1, (1 - e) * 2)
            s.offset = CGSize(width: -e * size, height: 0)
        case "slideRight":
            s.opacity = min(1, (1 - e) * 2)
            s.offset = CGSize(width: e * size, height: 0)
        default: // fade
            s.opacity = 1 - e
        }
        if t >= end { s.opacity = 0 }
        return s
    }

    /// How long before the end of the page its exits begin: the latest
    /// `delay + duration` among the shown `elements`, at most `maxExitSpan`;
    /// 0 when none of them leaves — a hidden element leaves unseen, and one
    /// timed to go earlier leaves then, not as the page ends.
    static func exitSpan(_ elements: [Element]) -> Double {
        let leaving = elements.filter { !$0.isHidden && $0.timing?.end == nil }
        let span = leaving.compactMap { $0.exitAnimation.map { max(0, $0.delay + $0.duration) } }.max() ?? 0
        return min(span, maxExitSpan)
    }

    // MARK: text a unit at a time

    /// What moves as one when `by` says nothing: a word for Word by word, a
    /// line for Block, a letter for every other kind — so files from before
    /// `by` play as they did.
    static func defaultBy(_ kind: String) -> String {
        switch kind {
        case "words": return "word"
        case "block": return "line"
        default: return "letter"
        }
    }

    /// What this moves as one: its `by` when it is one of unitChoices, else
    /// the kind's own.
    var unit: String {
        if let by, Self.unitChoices.contains(by) { return by }
        return Self.defaultBy(kind)
    }

    /// The move a text is drawn at, and the moment of it, in seconds from
    /// its own start: what State carries to the canvas.
    struct UnitClock: Equatable {
        var animation: ElementAnimation
        var time: Double
    }

    /// One unit's look at a moment: when it starts and ends moving (seconds
    /// from the page's start, delay in), how far it is moved across and
    /// down, its scale about its centre, its turn in degrees, its opacity,
    /// its blur, and the share of it shown from its left (a Block's bar, a
    /// Write on's stroke) — all in design units.
    struct UnitFrame: Equatable {
        var start: Double
        var end: Double
        var dx: Double = 0
        var dy: Double = 0
        var scale: Double = 1
        var rotation: Double = 0
        var alpha: Double = 1
        var blur: Double = 0
        var clip: Double = 1
    }

    /// The units of `plain`, as UTF-16 ranges: each letter that is not a
    /// space by "letter"; each run of letters between spaces and line
    /// breaks by "word"; each line with letters in it — its spaces at
    /// either end left out — by "line", a line being what a line break
    /// ends, so both phones count the same lines whatever the box's width.
    static func units(_ plain: String, by: String) -> [NSRange] {
        var out: [NSRange] = []
        var offset = 0
        var run: (start: Int, end: Int)?
        let breaks: (Character) -> Bool = by == "line" ? { $0 == "\n" } : { $0.isWhitespace }
        for c in plain {
            let length = c.utf16.count
            if breaks(c) {
                if let r = run { out.append(NSRange(location: r.start, length: r.end - r.start)) }
                run = nil
            } else if by == "word" || by == "line" {
                if !c.isWhitespace {
                    run = (run?.start ?? offset, offset + length)
                }
            } else {
                out.append(NSRange(location: offset, length: length))
            }
            offset += length
        }
        if let r = run { out.append(NSRange(location: r.start, length: r.end - r.start)) }
        return out
    }

    /// Each unit of `el`'s words — RichText.strip(text), by its animation's
    /// unit — `t` seconds into its page, by `frames`; none for an element
    /// with no unit move.
    static func unitFrames(_ el: Element, at t: Double) -> [UnitFrame] {
        guard let animation = el.animation, unitKinds.contains(animation.kind) else { return [] }
        let count = units(RichText.strip(el.text ?? ""), by: animation.unit).count
        return animation.frames(count: count, at: t, size: el.fontSize ?? 42)
    }

    /// `count` units `t` seconds into the page, for type `size` high. Each
    /// starts stagger = duration × 0.6 / count after the one before, from
    /// the delay, and moves for duration × 0.4, so the last is in by the
    /// end; its progress q is 0…1 over that, and e = 1 − (1 − q)³ eases it
    /// out. With i the unit's place and n the count:
    ///  - ascend: up from 0.5 size below, alpha e;
    ///  - shift: in from 0.5 size to the right, alpha e;
    ///  - merge: in from a size to the left (even i) or right (odd i), alpha e;
    ///  - block: a bar in the text's colour wipes across it, clip min(1, 2q),
    ///    and the words show once it covers them, alpha 1 from q = 0.5;
    ///  - burst: from twice its size, scale 2 − e, alpha e;
    ///  - bounceIn: falls from a size above and bounces (easeOutBounce b),
    ///    dy −(1 − b) × size, alpha min(1, 2q);
    ///  - roll: in from 0.5 size to the right turning from 90°, alpha e;
    ///  - skate: in from a size to the right leaning −15°, alpha e;
    ///  - spread: from (i − (n − 1) / 2) × 0.5 size further from the middle
    ///    than its place, alpha e;
    ///  - clarify: from a blur of 0.25 size, alpha e;
    ///  - tumble: from 0.5 size above, turned −180° at half size, alpha e;
    ///  - writeOn: drawn on from its left, clip q, alpha 1 once begun;
    ///  - typewriter and words appear whole once begun; letterPop pops,
    ///    scale 0.4 + 0.6e, alpha min(1, 2q); lineRise rises from 0.5 size
    ///    below, alpha e.
    func frames(count n: Int, at t: Double, size: Double) -> [UnitFrame] {
        guard n > 0 else { return [] }
        let stagger = duration * 0.6 / Double(n)
        let span = duration * 0.4
        return (0..<n).map { i in
            let start = delay + Double(i) * stagger
            var f = UnitFrame(start: start, end: start + span)
            let q = span > 0 ? min(max((t - start) / span, 0), 1) : (t >= start ? 1 : 0)
            let e = 1 - pow(1 - q, 3)
            let rest = 1 - e
            switch kind {
            case "ascend", "lineRise":
                f.dy = rest * size * 0.5
                f.alpha = e
            case "shift":
                f.dx = rest * size * 0.5
                f.alpha = e
            case "merge":
                f.dx = (i % 2 == 0 ? -1 : 1) * rest * size
                f.alpha = e
            case "block":
                f.clip = min(1, 2 * q)
                f.alpha = q >= 0.5 ? 1 : 0
            case "burst":
                f.scale = 2 - e
                f.alpha = e
            case "bounceIn":
                f.dy = -(1 - Self.bounce(q)) * size
                f.alpha = min(1, 2 * q)
            case "roll":
                f.dx = rest * size * 0.5
                f.rotation = rest * 90
                f.alpha = e
            case "skate":
                f.dx = rest * size
                f.rotation = -rest * 15
                f.alpha = e
            case "spread":
                f.dx = (Double(i) - Double(n - 1) / 2) * rest * size * 0.5
                f.alpha = e
            case "clarify":
                f.blur = rest * size * 0.25
                f.alpha = e
            case "tumble":
                f.dy = -rest * size * 0.5
                f.rotation = -rest * 180
                f.scale = 0.5 + 0.5 * e
                f.alpha = e
            case "writeOn":
                f.clip = q
                f.alpha = q > 0 ? 1 : 0
            case "letterPop":
                f.scale = 0.4 + 0.6 * e
                f.alpha = min(1, 2 * q)
            default: // typewriter, words
                f.alpha = q > 0 ? 1 : 0
            }
            return f
        }
    }

    /// The standard ease-out bounce, 0 at 0 and 1 at 1.
    static func bounce(_ x: Double) -> Double {
        let n1 = 7.5625, d1 = 2.75
        if x < 1 / d1 { return n1 * x * x }
        if x < 2 / d1 {
            let y = x - 1.5 / d1
            return n1 * y * y + 0.75
        }
        if x < 2.5 / d1 {
            let y = x - 2.25 / d1
            return n1 * y * y + 0.9375
        }
        let y = x - 2.625 / d1
        return n1 * y * y + 0.984375
    }

    /// One cycle every `loopPeriod` seconds from the delay, at rest before it.
    private func loopState(at t: Double) -> State {
        guard t >= delay else { return .settled }
        let phase = ((t - delay) / Self.loopPeriod).truncatingRemainder(dividingBy: 1)
        let wave = sin(phase * 2 * .pi)
        var s = State()
        switch kind {
        case "pulse": s.scale = 1 + 0.08 * wave
        case "wiggle": s.rotation = 8 * wave
        case "bounce": s.offset = CGSize(width: 0, height: -abs(wave) * 12)
        case "spin": s.rotation = phase * 360
        default: break
        }
        return s
    }
}

/// Ken Burns: a slow drift of a photo's crop over the page.
struct KenBurns: Codable, Equatable {
    /// How far the crop zooms over the hold, as a multiplier on cropScale.
    var zoom: Double = 1.15
    /// Where the focus drifts to, in unit coordinates; nil keeps the focus.
    var toX: Double?
    var toY: Double?

    /// The element's crop at fraction `f` (0…1) of the page's hold.
    func crop(from el: Element, fraction f: Double) -> (scale: Double, x: Double, y: Double) {
        let p = min(max(f, 0), 1)
        let base = el.cropScale ?? 1
        let x0 = el.cropX ?? 0.5, y0 = el.cropY ?? 0.5
        return (base * (1 + (zoom - 1) * p),
                x0 + ((toX ?? x0) - x0) * p,
                y0 + ((toY ?? y0) - y0) * p)
    }
}
