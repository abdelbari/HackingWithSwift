// How one page gives way to the next, as a pure function of time.
//
// A transition is two layers — the page leaving and the page coming — each
// with an opacity, a sideways shift as a share of the page's width, a scale
// about the centre, and a clip: none, a strip from the left edge, or a
// circle from the centre. The video draws the layers into each frame of the
// overlap and Present animates them on screen, so a push or a wipe looks the
// same in both, and on the Android twin, which has the same function with
// the same numbers (PageTransitions.layers).

import Foundation

enum PageTransitions {

    /// What part of a page shows while it moves.
    enum Clip: Equatable {
        case none
        /// From the left edge to this share of the width.
        case rect(fromLeftFraction: Double)
        /// About the centre, this share of half the page's diagonal.
        case circle(radiusFraction: Double)
    }

    /// One page, as drawn at a moment of the transition.
    struct Layer: Equatable {
        var alpha: Double = 1
        /// Sideways, as a share of the width; negative is to the left.
        var dx: Double = 0
        var scale: Double = 1
        var clip: Clip = .none
    }

    /// The range a page's own transition length is kept to.
    static let secondsRange = 0.2...2.0

    /// The lengths the page sheet offers: nil is today's timings.
    static let lengths: [(name: String, seconds: Double?)] = [("Quick", 0.3), ("Normal", nil), ("Slow", 1.0)]

    /// How `page` gives way to the next: its own transition when this build
    /// knows it, else the design's — a fade, or a cut when its motion turns
    /// cross-fade off. Android's PageTiming.transitionOf.
    static func transitionKind(after page: Page, in design: Design) -> String {
        if let own = page.transition, MovieExporter.transitions.contains(own) { return own }
        return design.motion?.crossfade == false ? "cut" : "fade"
    }

    /// Ease-out cubic: arrives fast, settles gently.
    static func eased(_ t: Double) -> Double {
        let c = min(max(t, 0), 1)
        return 1 - pow(1 - c, 3)
    }

    /// The page leaving and the page coming, `t` (0…1) of the way through a
    /// transition of `kind`. Going back plays the forward transition from 1
    /// to 0 with the pages swapped: the page leaving is the later one, which
    /// the forward move brought in. An unknown kind is a fade.
    static func layers(_ kind: String, t: Double, forward: Bool) -> (outgoing: Layer, incoming: Layer) {
        guard forward else {
            let reversed = layers(kind, t: 1 - t, forward: true)
            return (reversed.incoming, reversed.outgoing)
        }
        let t = min(max(t, 0), 1)
        let e = eased(t)
        var incoming = Layer()
        var outgoing = Layer()
        switch kind {
        case "cut":
            incoming.alpha = t >= 1 ? 1 : 0
        case "slide":
            // The next page comes in from the right over this one.
            incoming.dx = 1 - e
        case "push":
            // Both move: this page out to the left, the next in from the right.
            outgoing.dx = -e
            incoming.dx = 1 - e
        case "wipe":
            incoming.clip = .rect(fromLeftFraction: e)
        case "circle":
            incoming.clip = .circle(radiusFraction: e)
        case "zoom":
            incoming.scale = 0.85 + 0.15 * e
            incoming.alpha = e
        default: // fade
            incoming.alpha = t
        }
        return (outgoing, incoming)
    }

    /// A page's own length, kept to the range; nil when it has none.
    static func seconds(_ own: Double?) -> Double? {
        own.map { min(max($0, secondsRange.lowerBound), secondsRange.upperBound) }
    }

    /// How long Present takes over `kind`: the page's own length, else a
    /// quarter of a second for a fade and half a second for the rest.
    static func presentSeconds(_ kind: String, own: Double?) -> Double {
        if let own = seconds(own) { return own }
        return kind == "fade" ? 0.25 : 0.5
    }

    /// Which of `lengths` a page's own length reads as: the nearest, or
    /// Normal when it has none.
    static func lengthName(_ own: Double?) -> String {
        guard let own else { return "Normal" }
        let timed = lengths.compactMap { choice in choice.seconds.map { (choice.name, $0) } }
        return timed.min { abs($0.1 - own) < abs($1.1 - own) }?.0 ?? "Normal"
    }
}
