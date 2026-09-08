// Per-element entrance animation, as a document field with a pure evaluator.
//
// An element can arrive: fade in, rise from below, pop from small, slide in
// from a side, or — for text — reveal by letter or by word. The document
// stores what and when; `ElementAnimation.state(at:)` turns a time into an
// opacity, offset, scale and a count of visible characters, and the canvas
// preview, the video and the GIF all read that one function. Ken Burns is
// the same idea for a photo: a slow drift of its crop over the page's hold.

import Foundation

struct ElementAnimation: Codable, Equatable {
    /// "fade" | "rise" | "pop" | "slideLeft" | "slideRight" | "typewriter" | "words" | "letterPop" | "lineRise"
    var kind: String = "fade"
    /// Seconds after the page starts.
    var delay: Double = 0
    var duration: Double = 0.6

    static let kinds = ["fade", "rise", "pop", "slideLeft", "slideRight", "typewriter", "words", "letterPop", "lineRise",
                        "pulse", "wiggle", "bounce", "spin"]
    static let textKinds: Set<String> = ["typewriter", "words", "letterPop", "lineRise"]
    /// Loops never settle: a sticker that keeps moving for as long as the
    /// page is shown.
    static let loopKinds: Set<String> = ["pulse", "wiggle", "bounce", "spin"]
    static let loopPeriod = 1.2

    var loops: Bool { Self.loopKinds.contains(kind) }

    static func name(_ kind: String) -> String {
        switch kind {
        case "fade": return "Fade in"
        case "rise": return "Rise"
        case "pop": return "Pop"
        case "slideLeft": return "Slide from right"
        case "slideRight": return "Slide from left"
        case "typewriter": return "Typewriter"
        case "words": return "Word by word"
        case "letterPop": return "Letter pop"
        case "lineRise": return "Line rise"
        case "pulse": return "Pulse (loop)"
        case "wiggle": return "Wiggle (loop)"
        case "bounce": return "Bounce (loop)"
        case "spin": return "Spin (loop)"
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
        static let settled = State()
    }

    /// 0 before the delay, 1 after the duration, eased in between.
    func progress(at t: Double) -> Double {
        guard duration > 0 else { return t >= delay ? 1 : 0 }
        let raw = (t - delay) / duration
        let clamped = min(max(raw, 0), 1)
        // Ease-out cubic: arrives fast, settles gently.
        return 1 - pow(1 - clamped, 3)
    }

    func state(at t: Double, text: String? = nil, size: Double = 100) -> State {
        if loops { return loopState(at: t) }
        let p = progress(at: t)
        if p >= 1 { return .settled }
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

    /// When the element is fully in; a loop is never in.
    var end: Double { loops ? .infinity : delay + duration }

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
