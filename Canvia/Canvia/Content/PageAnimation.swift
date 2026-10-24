// An animation for a whole page — Animate with nothing selected: every
// element on it arriving, leaving, or both, one after another — the Android
// twin's PageAnimation. Kept in the page's own `pageAnimation`, {kind, mode},
// and turned into each element's own entrance and exit only as the page
// plays (`resolved`), so it is never written into the elements and goes
// when it is taken off.

import Foundation

struct PageAnimation: Codable, Equatable {
    /// "rise" | "fade" | "pan" | "breathe" | "tumble" | "stomp", kept as
    /// written so a kind from a newer build survives a save here.
    var kind: String = "rise"
    /// "enter" | "exit" | "both".
    var mode: String = PageAnimation.enter

    static let enter = "enter"
    static let exit = "exit"
    static let both = "both"
    static let modes = [enter, exit, both]

    static let kinds = ["rise", "fade", "pan", "breathe", "tumble", "stomp"]

    /// How far apart the elements start, in the page's layer order.
    static let stagger = 0.08
    /// How long each element takes.
    static let duration = 0.6

    init(kind: String = "rise", mode: String = PageAnimation.enter) {
        self.kind = kind
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey { case kind, mode }

    /// A kind that is not text is none at all (the decode fails, and the
    /// page reads with no animation); a missing or unknown mode is Enter.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        let mode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? Self.enter
        self.mode = Self.modes.contains(mode) ? mode : Self.enter
    }

    /// Whether the elements arrive by it, and whether they leave.
    var enters: Bool { mode != Self.exit }
    var exits: Bool { mode == Self.exit || mode == Self.both }

    /// The element kind each page kind gives every element: rise rises,
    /// fade fades, pan slides in from the right (slideLeft), breathe
    /// breathes, tumble tumbles, and stomp pops. A page kind this build does
    /// not know fades.
    static func elementKind(_ kind: String) -> String {
        switch kind {
        case "rise": return "rise"
        case "pan": return "slideLeft"
        case "breathe": return "breathe"
        case "tumble": return "tumble"
        case "stomp": return "pop"
        default: return "fade"
        }
    }

    static func name(_ kind: String) -> String {
        switch kind {
        case "rise": return tr("Rise")
        case "fade": return tr("Fade")
        case "pan": return tr("Pan")
        case "breathe": return tr("Breathe")
        case "tumble": return tr("Tumble")
        case "stomp": return tr("Stomp")
        default: return kind
        }
    }

    /// When the elements move — "Enter" and "Exit" as an animation's, not a
    /// key's or a menu's.
    static func modeName(_ mode: String) -> String {
        switch mode {
        case Self.exit: return tr("Exit", context: "animation")
        case Self.both: return tr("Both")
        default: return tr("Enter", context: "animation")
        }
    }

    /// `elements` — a page's own, in its layer order, bottom first — as
    /// `animation` has them play: the n-th (counting every one) arriving
    /// stagger × n seconds in, and leaving stagger × n seconds before the
    /// page ends, so the first in is the last out, each for `duration`. An
    /// element's own entrance, or its own exit, is kept over the page's.
    /// Nothing changes for none.
    static func resolved(_ elements: [Element], _ animation: PageAnimation?) -> [Element] {
        guard let animation else { return elements }
        let kind = elementKind(animation.kind)
        return elements.enumerated().map { n, el in
            let delay = (Double(n) * stagger * 1000).rounded() / 1000
            var out = el
            if animation.enters && out.animation == nil {
                out.animation = ElementAnimation(kind: kind, delay: delay, duration: duration)
            }
            if animation.exits && out.exitAnimation == nil {
                out.exitAnimation = ElementAnimation(kind: kind, delay: delay, duration: duration)
            }
            return out
        }
    }

    /// `page` with its animation played into its elements (`resolved`).
    static func playing(_ page: Page) -> Page {
        guard let animation = page.pageAnimation else { return page }
        var out = page
        out.elements = resolved(page.elements, animation)
        return out
    }
}
