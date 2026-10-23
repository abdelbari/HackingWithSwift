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

import Foundation

struct ElementAnimation: Codable, Equatable {
    /// "grow" | "fade" | "rise" | "pop" | "slideLeft" | "slideRight" | "typewriter" | "words" | "letterPop" | "lineRise"
    var kind: String = "fade"
    /// Seconds after the page starts.
    var delay: Double = 0
    var duration: Double = 0.6

    static let kinds = [grow, "fade", "rise", "pop", "slideLeft", "slideRight", "typewriter", "words", "letterPop", "lineRise",
                        "pulse", "wiggle", "bounce", "spin"]
    /// A chart's entrance, its parts growing from their baseline.
    static let grow = "grow"
    /// How long after each other a chart's series start to grow, and how
    /// long a chart takes, delay aside, when Grow is picked.
    static let growStagger = 0.08
    static let growDuration = 1.0
    static let textKinds: Set<String> = ["typewriter", "words", "letterPop", "lineRise"]
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
            let count = text?.count ?? 0
            let linear = min(max((t - delay) / max(duration, 0.001), 0), 1)
            switch kind {
            case "words":
                // Whole words appear at a time.
                let words = (text ?? "").split(separator: " ", omittingEmptySubsequences: false)
                let shown = Int((Double(words.count) * linear).rounded(.up))
                let prefix = words.prefix(shown).joined(separator: " ")
                s.visibleCharacters = prefix.count
            default:
                s.visibleCharacters = Int((Double(count) * linear).rounded(.up))
            }
            if kind == "lineRise" {
                s.offset = CGSize(width: 0, height: (1 - p) * size * 0.15)
                s.opacity = p
            }
        default: // fade
            s.opacity = p
        }
        return s
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
