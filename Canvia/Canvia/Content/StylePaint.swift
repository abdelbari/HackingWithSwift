// Copy style, as Canva's paint roller does it: the look of one thing poured
// onto another with a tap. Between two things of a kind the whole style goes
// across (DesignStore.apply). Between kinds only what both have: opacity,
// shadow and blend, and the colour carried to where the other kind keeps
// it — a text's colour becomes a shape's fill and the reverse, a line's
// colour a shape's outline or a text's colour, a photo's border colour and
// dashes a shape's outline colour and dashes (each keeps its own width). The Android twin's
// ElementStyle, with the same test rows.

import Foundation

enum StylePaint {

    /// What the paint-mode chip at the top of the canvas says.
    static let chip = "Tap something to paste the style"

    /// `el` with `style`, copied from an element of kind `source`, painted
    /// on. Between kinds, a colour the source has no value for leaves the
    /// target's as it was; a shape's fill goes to a text only when it is a
    /// solid colour (to the text's colour) or a gradient (to its textFill),
    /// and a text's gradient goes to a shape as its fill — only a gradient:
    /// any other paint in the letters leaves the text's colour to fill it.
    static func pasted(_ style: DesignStore.Style, from source: ElementType, onto el: Element) -> Element {
        var out = el
        guard source != el.type else {
            DesignStore.apply(style, to: &out)
            return out
        }
        out.opacity = style.opacity
        out.shadow = style.shadow
        out.blendMode = style.blendMode
        switch (source, el.type) {
        case (.text, .shape):
            if let gradient = style.textFill, gradient.kind == "gradient" {
                out.fill = gradient
            } else if let colour = style.color {
                out.fill = .solid(colour)
            }
        case (.shape, .text):
            guard let fill = style.fill else { break }
            if fill.kind == "solid", let colour = fill.color {
                out.color = colour
                out.textFill = nil
            } else if fill.kind == "gradient" {
                out.textFill = fill
            }
        case (.line, .shape):
            if let colour = style.color { out.stroke = colour }
        case (.image, .shape), (.shape, .image):
            // A border's look goes with it: its colour and its dashes (each
            // keeps its own width).
            if let colour = style.stroke { out.stroke = colour }
            out.dash = BorderDash.kept(style.dash)
        case (.shape, .line):
            if let colour = style.stroke { out.color = colour }
        case (.line, .text):
            if let colour = style.color {
                out.color = colour
                out.textFill = nil
            }
        case (.text, .line):
            if let colour = style.color { out.color = colour }
        default:
            break
        }
        return out
    }
}
