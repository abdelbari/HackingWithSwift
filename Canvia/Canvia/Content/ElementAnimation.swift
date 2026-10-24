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
//
// Round 32 adds, at parity with the Android twin: a recorded motion path
// ("path", Animate's Create) — its points, `path` as [dx, dy, t] each, page
// units from the element's resting centre, played along a Catmull-Rom curve
// when `smooth`, turned to face the way it goes when `orient`, at `speed`;
// a photo's motion over its page (photoZoom, photoPan), which moves its
// crop rather than its frame; more ways in (wipe, breathe, drift, tumble,
// and baseline for text); and a graphic drawing itself on (draw) or
// twinkling (twinkle). A build that does not know a kind fades it in.

import Foundation

struct ElementAnimation: Codable, Equatable {
    /// "grow" | "fade" | "rise" | "pop" | "slideLeft" | "slideRight" | a text kind (textKindOrder) | a loop
    /// and the rest of `kinds`, or "path"
    var kind: String = "fade"
    /// Seconds after the page starts.
    var delay: Double = 0
    var duration: Double = 0.6
    /// For text: "letter", "word" or "line" — what moves as one; nil is the
    /// kind's own (defaultBy).
    var by: String?
    /// A path's points, in the order they were recorded; written only on a
    /// path, with the three below.
    var path: [MotionPath.Point]?
    /// A path played as a smooth curve through its points, else straight
    /// from one to the next.
    var smooth: Bool = true
    /// Turned to face the way the path goes.
    var orient: Bool = false
    /// How much faster than recorded a path plays, MotionPath.speeds.
    var speed: Double = 1

    /// The kinds Animate offers, in its order; a path is recorded instead,
    /// by Create.
    static let kinds: [String] = [grow, "fade", "rise", "pop", "slideLeft", "slideRight", "wipe", "breathe", "drift"]
        + textKindOrder
        + [photoZoom, photoPan, draw, "pulse", "wiggle", "bounce", "spin", twinkle]
    /// A recorded motion path (Animate's Create).
    static let pathKind = "path"
    /// A graphic's line drawing itself on, and its sparkles twinkling.
    static let draw = "draw"
    static let twinkle = "twinkle"
    /// How long a graphic takes to draw itself on, all its paths.
    static let drawDuration = 1.2
    /// How far apart a twinkling graphic's paths start.
    static let twinkleStagger = 0.15
    /// Type rising into its box from its baseline.
    static let baseline = "baseline"
    /// A photo's slow zoom and pan over its page.
    static let photoZoom = "photoZoom"
    static let photoPan = "photoPan"
    static let photoKinds: Set<String> = [photoZoom, photoPan]
    /// A chart's entrance, its parts growing from their baseline.
    static let grow = "grow"
    /// How long after each other a chart's series start to grow, and how
    /// long a chart takes, delay aside, when Grow is picked.
    static let growStagger = 0.08
    static let growDuration = 1.0
    /// The text-only kinds, in the order both phones offer them.
    static let textKindOrder: [String] = ["typewriter", "words", "letterPop", "lineRise", baseline,
                                "ascend", "shift", "merge", "block", "burst", "bounceIn", "roll", "skate",
                                "spread", "clarify", "tumble", "writeOn"]
    static let textKinds = Set(textKindOrder)
    /// The kinds that move each unit of the words on its own (unitFrames),
    /// rather than cut the words to those shown so far.
    static let unitKinds: Set<String> = ["ascend", "shift", "merge", "block", "burst", "bounceIn", "roll", "skate",
                                         "spread", "clarify", "tumble", "writeOn"]
    /// The text kinds that are also an entrance for anything that is not
    /// text, moving it whole: Tumble — on text its letters, words or lines
    /// tumble in one by one (unitFrames); on anything else the whole
    /// element (state). The Android twin's ANY_ELEMENT_KINDS.
    static let anyElementKinds: Set<String> = ["tumble"]
    /// Whether `kind` moves only text, passing over anything else.
    static func textOnly(_ kind: String?) -> Bool {
        guard let kind else { return false }
        return textKinds.contains(kind) && !anyElementKinds.contains(kind)
    }
    /// Whether what moves is text: `el`'s type when it is given, else
    /// whether there is `text` — how a kind of anyElementKinds knows to
    /// move units or the whole.
    static func onText(_ text: String?, _ el: Element?) -> Bool {
        if let el { return el.type == .text }
        return text != nil
    }
    /// What a text kind can move as one, in the order the Animate by row
    /// lists them.
    static let unitChoices = ["letter", "word", "line"]
    /// Loops never settle: a sticker that keeps moving for as long as the
    /// page is shown.
    static let loopKinds: Set<String> = ["pulse", "wiggle", "bounce", "spin", twinkle]
    static let loopPeriod = 1.2

    var loops: Bool { Self.loopKinds.contains(kind) }

    /// How long it takes, delay aside: a path as fast as its speed.
    var playedFor: Double {
        kind == Self.pathKind ? duration / min(max(speed, MotionPath.minSpeed), MotionPath.maxSpeed) : duration
    }

    /// Whether it moves for its page's whole hold: a photo's motion.
    var drifts: Bool { Self.photoKinds.contains(kind) }

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
        case "wipe": return tr("Wipe")
        case "breathe": return tr("Breathe")
        case "drift": return tr("Drift")
        case "baseline": return tr("Baseline")
        case "photoZoom": return tr("Photo zoom")
        case "photoPan": return tr("Photo pan")
        case "draw": return tr("Draw")
        case "twinkle": return tr("Twinkle (loop)")
        case "path": return tr("Custom path")
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
        /// Drawn only within its resting box, as a line of type rising from
        /// its baseline is.
        var clipped = false
        /// The share of its outline drawn on (draw): each of its paths in
        /// turn, by `drawn`.
        var draw: Double = 1
        /// A photo's picture enlarged this much more inside its frame, and
        /// its crop's across share (photoZoom, photoPan); nil keeps its own.
        var cropZoom: Double = 1
        var cropX: Double?
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
            s.clipped = clipped || exit.clipped
            s.draw *= exit.draw
            s.cropZoom *= exit.cropZoom
            s.cropX = cropX ?? exit.cropX
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
    /// grows; anything else that grows fades in. A photo's motion runs over
    /// the page's `hold`, from the delay to the page's end, and moves only a
    /// photo or a clip. A path plays at its speed, straight through rather
    /// than eased, as it was recorded; a draw-on at an even pace, as a pen
    /// moves.
    func state(at t: Double, text: String? = nil, size: Double = 100, el: Element? = nil,
               hold: Double? = nil) -> State {
        if loops { return loopState(at: t) }
        if Self.photoKinds.contains(kind) { return photoState(at: t, el: el, hold: hold) }
        if kind == Self.pathKind, let points = path, points.count >= 2 {
            let q = Self.linear(t, delay: delay, duration: playedFor)
            if q >= 1 { return .settled }
            let moved = Self.pathState(self, q)
            return el.map { Self.inOwnSpace(moved, $0) } ?? moved
        }
        if kind == Self.draw {
            let q = Self.linear(t, delay: delay, duration: duration)
            if q >= 1 { return .settled }
            var s = State()
            s.draw = q
            return s
        }
        let p = progress(at: t)
        if p >= 1 { return .settled }
        if kind == Self.grow, let el { return growState(at: t, el) }
        var s = State()
        switch kind {
        case "wipe":
            s.reveal = p
        case "breathe":
            s.opacity = p
            s.scale = 0.9 + 0.1 * p
        case "drift":
            s.opacity = p
            s.offset = CGSize(width: (1 - p) * size * 0.2, height: 0)
        case "tumble" where Self.onText(text, el):
            // Tumble on text moves its units, drawn so by the canvas; on
            // anything else, the whole element (anyElementKinds).
            s.unitClock = UnitClock(animation: self, time: t)
        case "tumble":
            s.opacity = min(1, p * 2)
            s.rotation = -90 * (1 - p)
            s.scale = 0.5 + 0.5 * p
        case "baseline":
            // Up from below its own baseline, seen only within its box.
            s.offset = CGSize(width: 0, height: (1 - p) * (el?.h ?? size))
            s.clipped = true
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
    /// A draw-on or a twinkle goes on as Add puts a moving graphic on
    /// (`motioned`); a photo's motion passes over all but photos and clips.
    static func applied(_ elements: [Element], kind: String?) -> [Element] {
        if let kind, kind == draw || kind == twinkle { return motioned(elements, kind: kind) }
        var n = 0
        var charts: [String: Double] = [:]
        return elements.map { el in
            var out = el
            guard let kind else {
                out.animation = nil
                return out
            }
            if textOnly(kind) && el.type != .text { return el }
            if photoKinds.contains(kind) && el.type != .image { return el }
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
            // What a text kind moves by is kept as it changes to another
            // text kind, as the Android twin keeps it.
            out.animation = ElementAnimation(kind: kind, delay: Double(n) * 0.15, duration: 0.6,
                                             by: textKinds.contains(kind) ? el.animation?.by : nil)
            n += 1
            return out
        }
    }

    /// `elements` — a graphic's paths, in their order — given `kind`
    /// together: draw draws them on one after another over drawDuration,
    /// each for its share of their whole length (`lengthOf`, `drawSpans`);
    /// twinkle starts each twinkleStagger after the one before; any other
    /// kind is given to each with no delay, so they move as one. Times to a
    /// hundredth of a second, as on the Android twin.
    static func motioned(_ elements: [Element], kind: String) -> [Element] {
        switch kind {
        case draw:
            let spans = drawSpans(elements.map(lengthOf), total: drawDuration)
            return elements.enumerated().map { i, el in
                var out = el
                out.animation = ElementAnimation(kind: draw, delay: spans[i].delay, duration: spans[i].duration)
                return out
            }
        case twinkle:
            return elements.enumerated().map { i, el in
                var out = el
                out.animation = ElementAnimation(kind: twinkle, delay: hundredth(Double(i) * twinkleStagger), duration: 0.6)
                return out
            }
        default:
            return elements.map { el in
                var out = el
                out.animation = ElementAnimation(kind: kind, delay: 0, duration: 0.6)
                return out
            }
        }
    }

    /// Each of paths `lengths` long as a delay and a duration within
    /// `total` seconds, drawn in order, each for its share of their whole
    /// length — to a hundredth; all of nothing long share it evenly.
    static func drawSpans(_ lengths: [Double], total: Double) -> [(delay: Double, duration: Double)] {
        let sum = lengths.reduce(0) { $0 + max(0, $1) }
        var before = 0.0
        return lengths.enumerated().map { i, raw in
            let len = max(0, raw)
            let start = sum > 0 ? before / sum : Double(i) / Double(lengths.count)
            let share = sum > 0 ? len / sum : 1 / Double(lengths.count)
            before += len
            return (delay: hundredth(start * total), duration: hundredth(share * total))
        }
    }

    /// How much of each of paths `lengths` long is drawn `p` (0…1) of the
    /// way through a draw-on: in order, each for its share of the whole, so
    /// the pen moves at one pace — 0 before its turn, 1 after. The same rule
    /// draws an element's own subpaths in turn. All of nothing long: none
    /// until the end, then all.
    static func drawn(_ lengths: [Double], p: Double) -> [Double] {
        let sum = lengths.reduce(0) { $0 + max(0, $1) }
        guard sum > 0 else { return lengths.map { _ in p >= 1 ? 1 : 0 } }
        let reach = min(max(p, 0), 1) * sum
        var before = 0.0
        return lengths.map { raw in
            let len = max(0, raw)
            let f = len <= 0 ? (reach >= before ? 1.0 : 0.0) : min(max((reach - before) / len, 0), 1)
            before += len
            return f
        }
    }

    /// How long an element's outline is on the page: its own path's
    /// (`pathData`, each curve as 16 straight steps) stretched to its box,
    /// else its box's edge.
    static func lengthOf(_ el: Element) -> Double {
        guard let d = el.pathData else { return 2 * (el.w + el.h) }
        return SVGPath.subpathLengths(d, sx: el.w / 100, sy: el.h / 100).reduce(0, +)
    }

    /// Where a path has the element `p` (0…1) of the way through, from its
    /// resting centre, page units: on a Catmull-Rom curve through its points
    /// when smooth, else straight from one to the next — the two points
    /// round p by their t, and how far between. Turned to face the way it
    /// goes when it orients, in degrees (0 rightwards, clockwise as the
    /// page's y runs down); not turned while it stands still. The Android
    /// twin's pathState, row for row (motion.json).
    static func pathState(_ anim: ElementAnimation, _ p: Double) -> State {
        let pts = anim.path ?? []
        var s = State()
        guard let first = pts.first else { return s }
        guard pts.count >= 2 else {
            s.offset = CGSize(width: first.dx, height: first.dy)
            return s
        }
        let q = min(max(p, 0), 1)
        var i = 0
        while i < pts.count - 2 && q >= pts[i + 1].t { i += 1 }
        let a = pts[i], b = pts[i + 1]
        let span = b.t - a.t
        let u = span <= 0 ? 1 : min(max((q - a.t) / span, 0), 1)
        let x: Double, y: Double, tx: Double, ty: Double
        if anim.smooth {
            let p0 = pts[max(0, i - 1)], p3 = pts[min(pts.count - 1, i + 2)]
            x = catmullRom(p0.dx, a.dx, b.dx, p3.dx, u)
            y = catmullRom(p0.dy, a.dy, b.dy, p3.dy, u)
            tx = catmullRomSlope(p0.dx, a.dx, b.dx, p3.dx, u)
            ty = catmullRomSlope(p0.dy, a.dy, b.dy, p3.dy, u)
        } else {
            x = a.dx + (b.dx - a.dx) * u
            y = a.dy + (b.dy - a.dy) * u
            tx = b.dx - a.dx
            ty = b.dy - a.dy
        }
        s.offset = CGSize(width: x, height: y)
        if anim.orient && (abs(tx) > 1e-9 || abs(ty) > 1e-9) {
            s.rotation = atan2(ty, tx) * 180 / .pi
        }
        return s
    }

    /// A Catmull-Rom curve's value between v1 and v2, `u` of the way.
    private static func catmullRom(_ v0: Double, _ v1: Double, _ v2: Double, _ v3: Double, _ u: Double) -> Double {
        let c1 = -v0 + v2
        let c2 = 2 * v0 - 5 * v1 + 4 * v2 - v3
        let c3 = -v0 + 3 * v1 - 3 * v2 + v3
        return 0.5 * (2 * v1 + c1 * u + c2 * u * u + c3 * u * u * u)
    }

    /// Its slope there.
    private static func catmullRomSlope(_ v0: Double, _ v1: Double, _ v2: Double, _ v3: Double, _ u: Double) -> Double {
        let c1 = -v0 + v2
        let c2 = 2 * v0 - 5 * v1 + 4 * v2 - v3
        let c3 = -v0 + 3 * v1 - 3 * v2 + v3
        return 0.5 * (c1 + 2 * c2 * u + 3 * c3 * u * u)
    }

    /// A move on the page as `el`'s own: its flips and turn undone, as the
    /// canvas moves an element along itself before turning it — so a path
    /// goes where it was drawn, whatever the element's turn.
    static func inOwnSpace(_ state: State, _ el: Element) -> State {
        let turn = el.rotation * .pi / 180
        let dx = Double(state.offset.width), dy = Double(state.offset.height)
        let x = dx * cos(turn) + dy * sin(turn)
        let y = -dx * sin(turn) + dy * cos(turn)
        var s = state
        s.offset = CGSize(width: el.flipH ? -x : x, height: el.flipV ? -y : y)
        return s
    }

    /// A photo's motion `t` seconds into a page of `hold` seconds, straight
    /// through from its delay to the page's end (its own duration for a page
    /// of no known hold): photoZoom enlarges the picture in its frame from 1
    /// to 1.15 times; photoPan enlarges it 1.1 times and slides the view
    /// across it from its left edge to its right (cropX 0 to 1). The frame
    /// stays where it is. Anything but a photo or a clip stays still.
    private func photoState(at t: Double, el: Element?, hold: Double?) -> State {
        guard let el, el.type == .image else { return .settled }
        let span = hold.map { $0 - delay } ?? duration
        let f = Self.linear(t, delay: delay, duration: span > 0 ? span : 0)
        var s = State()
        if kind == Self.photoZoom {
            s.cropZoom = 1 + 0.15 * f
        } else {
            s.cropZoom = 1.1
            s.cropX = f
        }
        return s
    }

    /// 0 before `delay`, 1 from `duration` after it, straight between; with
    /// no duration, 1 from the delay.
    private static func linear(_ t: Double, delay: Double, duration: Double) -> Double {
        guard duration > 0 else { return t >= delay ? 1 : 0 }
        return min(max((t - delay) / duration, 0), 1)
    }

    /// Whether `kind` moves only a photo or a clip.
    static func forPhotos(_ kind: String) -> Bool { photoKinds.contains(kind) }

    static func hundredth(_ v: Double) -> Double { (v * 100 + 0.5).rounded(.down) / 100 }

    /// When the element is fully in; a loop is never in.
    var end: Double { loops ? .infinity : delay + playedFor }

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

    /// One unit's look at a moment: the stretch of the plain words it is
    /// (UTF-16 offsets, start up to end, as the Android twin's), how far it
    /// is moved across and down, its scale about its centre, its turn in
    /// degrees, its opacity, its blur, and the share of it shown from its
    /// left (a Write on's stroke) — all in design units. Block's clip runs
    /// 0 to 2: under 1 a bar in the text's colour covers its first clip
    /// share, the letters hidden; from 1 the letters show and the bar covers
    /// from clip − 1 to its end; 2 is at rest.
    struct UnitFrame: Equatable {
        var start: Int
        var end: Int
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
        return animation.frames(units(RichText.strip(el.text ?? ""), by: animation.unit), at: t, size: el.fontSize ?? 42)
    }

    /// Whether a unit is drawn as it stands: unmoved, whole and opaque.
    func atRest(_ f: UnitFrame) -> Bool {
        f.dx == 0 && f.dy == 0 && f.scale == 1 && f.rotation == 0 && f.alpha >= 1 && f.blur == 0
            && f.clip == (kind == "block" ? 2 : 1)
    }

    /// `units` (UTF-16 ranges of the plain words) `t` seconds into the page,
    /// for type `size` high, as a unit kind (unitKinds) has them — the rule
    /// both phones share, over the same frame tables
    /// (Fixtures/unit-frames.json). With n units, each starts
    /// stagger = duration × 0.6 / n after the one before, from the delay,
    /// and moves for duration × 0.4, so the last is in by the end; its
    /// progress q is 0…1 over that, e = 1 − (1 − q)³ and r = 1 − e. With i
    /// the unit's place and c = i − (n − 1) / 2:
    ///  - ascend: dy 0.5 r size, alpha e; shift: dx 0.5 r size, alpha e;
    ///  - merge: dx r size from the left (even i) or right (odd i), alpha e;
    ///  - block: clip 2q — the bar wipes on, then off with the letters under
    ///    it (UnitFrame) — alpha 0 until clip reaches 1;
    ///  - burst: scale 2 − e, alpha e;
    ///  - bounceIn: dy −(1 − bounce(q)) size, alpha min(1, 2q);
    ///  - roll: dx 0.5 r size, rotation 90 r, alpha e;
    ///  - skate: dx r size, rotation −15 r, alpha e;
    ///  - spread: dx 0.5 c r size, alpha e;
    ///  - clarify: blur 0.25 r size, alpha e;
    ///  - tumble: dy −0.5 r size, rotation −180 r, scale 0.5 + 0.5e, alpha e;
    ///  - writeOn: clip q, alpha 1 once begun.
    /// At q = 1 a unit is at rest (block's clip 2).
    func frames(_ units: [NSRange], at t: Double, size: Double) -> [UnitFrame] {
        let n = units.count
        guard n > 0 else { return [] }
        let stagger = duration * 0.6 / Double(n)
        let span = duration * 0.4
        return units.enumerated().map { i, unit in
            let begin = delay + Double(i) * stagger
            let q = span > 0 ? min(max((t - begin) / span, 0), 1) : (t >= begin ? 1 : 0)
            return frame(UnitFrame(start: unit.location, end: NSMaxRange(unit)), q: q, i: i, n: n, size: size)
        }
    }

    private func frame(_ rest: UnitFrame, q: Double, i: Int, n: Int, size: Double) -> UnitFrame {
        var f = rest
        guard q < 1 else {
            if kind == "block" { f.clip = 2 }
            return f
        }
        let e = 1 - pow(1 - q, 3)
        let r = 1 - e
        let c = Double(i) - Double(n - 1) / 2
        f.alpha = e
        switch kind {
        case "ascend": f.dy = 0.5 * r * size
        case "shift": f.dx = 0.5 * r * size
        case "merge": f.dx = (i % 2 == 0 ? -1 : 1) * r * size
        case "block":
            f.clip = 2 * q
            f.alpha = f.clip >= 1 ? 1 : 0
        case "burst": f.scale = 2 - e
        case "bounceIn":
            f.dy = -(1 - Self.bounce(q)) * size
            f.alpha = min(1, 2 * q)
        case "roll":
            f.dx = 0.5 * r * size
            f.rotation = 90 * r
        case "skate":
            f.dx = r * size
            f.rotation = -15 * r
        case "spread": f.dx = 0.5 * c * r * size
        case "clarify": f.blur = 0.25 * r * size
        case "tumble":
            f.dy = -0.5 * r * size
            f.rotation = -180 * r
            f.scale = 0.5 + 0.5 * e
        case "writeOn":
            f.clip = q
            f.alpha = q > 0 ? 1 : 0
        default:
            f.alpha = 1
        }
        return f
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
        case "twinkle":
            s.scale = 1 + 0.15 * wave
            s.opacity = 0.7 + 0.3 * wave
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

extension ElementAnimation {

    private enum CodingKeys: String, CodingKey { case kind, delay, duration, by, path, smooth, orient, speed }

    /// Leniently, as the Android twin reads it: a missing kind is a fade, a
    /// missing delay none, a missing duration 0.6 s, a `by` that is not one
    /// of unitChoices none; a path's point that is not three numbers is
    /// passed over.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "fade"
        delay = (try? c.decodeIfPresent(Double.self, forKey: .delay)) ?? 0
        duration = (try? c.decodeIfPresent(Double.self, forKey: .duration)) ?? 0.6
        by = (try? c.decodeIfPresent(String.self, forKey: .by)).flatMap { Self.unitChoices.contains($0) ? $0 : nil }
        guard kind == Self.pathKind else { return }
        path = (try? c.decodeIfPresent([MotionPath.Reading].self, forKey: .path))?.compactMap(\.point)
        smooth = (try? c.decodeIfPresent(Bool.self, forKey: .smooth)) ?? true
        orient = (try? c.decodeIfPresent(Bool.self, forKey: .orient)) ?? false
        speed = (try? c.decodeIfPresent(Double.self, forKey: .speed)) ?? 1
    }

    /// Every field — `by` only when set — a path's own only on a path, all
    /// of them there.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(delay, forKey: .delay)
        try c.encode(duration, forKey: .duration)
        try c.encodeIfPresent(by, forKey: .by)
        guard kind == Self.pathKind else { return }
        try c.encode((path ?? []).map { [$0.dx, $0.dy, $0.t] }, forKey: .path)
        try c.encode(smooth, forKey: .smooth)
        try c.encode(orient, forKey: .orient)
        try c.encode(speed, forKey: .speed)
    }
}
