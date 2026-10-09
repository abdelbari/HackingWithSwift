// Words inside a shape: "SALE" in a starburst, a label on a button, a line
// in a speech bubble.
//
// Not a new element kind: a shape carries `text` and the text style keys a
// text box does (fontFamily, fontSize, fontWeight, italic, underline,
// uppercase, align, lineHeight, letterSpacing, color, vAlign), centred and
// middled when it says nothing, and the words are drawn after its fill and
// border, wrapped to a text-safe box inside it. Effects, curves and paths
// are a text box's; a shape's words are set straight. A design from before
// draws as it did, and an older build keeps the keys and draws none of them.
//
// The text-safe boxes are `ShapeTextInsets`, the Android twin's core table
// of the same name, number for number.

import Foundation
import UIKit

/// The part of a shape's 0…100 box its words are set in.
struct ShapeTextInset: Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

enum ShapeTextInsets {

    /// For path data, and for a shape this build does not know: 15% in.
    static let fallback = ShapeTextInset(x: 15, y: 15, w: 70, h: 70)

    /// Every shape in the library, by id. A rectangle 8% in, a circle at
    /// its inscribed square (14.6%), a triangle in its lower 55%, a diamond
    /// 25% in, the stars 30% in, a speech bubble in the body above its tail.
    static let table: [String: ShapeTextInset] = [
        "rect": ShapeTextInset(x: 8, y: 8, w: 84, h: 84),
        "circle": ShapeTextInset(x: 14.6, y: 14.6, w: 70.8, h: 70.8),
        "triangle": ShapeTextInset(x: 27.5, y: 45, w: 45, h: 55),
        "triangle-down": ShapeTextInset(x: 27.5, y: 0, w: 45, h: 55),
        "diamond": ShapeTextInset(x: 25, y: 25, w: 50, h: 50),
        "pentagon": ShapeTextInset(x: 20, y: 30, w: 60, h: 55),
        "hexagon": ShapeTextInset(x: 20, y: 15, w: 60, h: 70),
        "octagon": ShapeTextInset(x: 18, y: 18, w: 64, h: 64),
        "semicircle": ShapeTextInset(x: 20, y: 62, w: 60, h: 32),
        "quarter": ShapeTextInset(x: 5, y: 35, w: 60, h: 60),
        "parallelogram": ShapeTextInset(x: 25, y: 8, w: 50, h: 84),
        "trapezoid": ShapeTextInset(x: 20, y: 8, w: 60, h: 84),
        "star-5": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
        "star-4": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
        "star-6": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
        "star-8": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
        "seal": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
        "burst-16": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
        "arrow-right": ShapeTextInset(x: 8, y: 30, w: 72, h: 40),
        "arrow-left": ShapeTextInset(x: 20, y: 30, w: 72, h: 40),
        "arrow-up": ShapeTextInset(x: 30, y: 20, w: 40, h: 72),
        "arrow-down": ShapeTextInset(x: 30, y: 8, w: 40, h: 72),
        "arrow-double": ShapeTextInset(x: 20, y: 38, w: 60, h: 24),
        "chevron": ShapeTextInset(x: 30, y: 8, w: 40, h: 84),
        "speech": ShapeTextInset(x: 8, y: 8, w: 84, h: 54),
        "thought": ShapeTextInset(x: 14.6, y: 10.2, w: 70.8, h: 49.6),
        "ribbon": ShapeTextInset(x: 15, y: 24, w: 70, h: 52),
        "banner": ShapeTextInset(x: 8, y: 8, w: 84, h: 62),
        "tag": ShapeTextInset(x: 30, y: 20, w: 62, h: 60),
        "plaque": ShapeTextInset(x: 8, y: 22, w: 84, h: 56),
        "heart": ShapeTextInset(x: 20, y: 20, w: 60, h: 40),
        "cross": ShapeTextInset(x: 8, y: 35, w: 84, h: 30),
        "lightning": ShapeTextInset(x: 30, y: 40, w: 40, h: 18),
        "moon": ShapeTextInset(x: 10, y: 30, w: 35, h: 40),
        "drop": ShapeTextInset(x: 15, y: 50, w: 70, h: 35),
        "shield": ShapeTextInset(x: 15, y: 15, w: 70, h: 60),
        "blob-round": ShapeTextInset(x: 15, y: 15, w: 70, h: 70),
        "blob-elongated": ShapeTextInset(x: 15, y: 15, w: 70, h: 70),
        "blob-trilobe": ShapeTextInset(x: 15, y: 15, w: 70, h: 70),
        "blob-bean": ShapeTextInset(x: 15, y: 15, w: 70, h: 70),
        "sparkle-4pt": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
        "flower-6": ShapeTextInset(x: 25, y: 25, w: 50, h: 50),
        "squircle": ShapeTextInset(x: 12, y: 12, w: 76, h: 76),
        "scallop-12": ShapeTextInset(x: 18, y: 18, w: 64, h: 64),
    ]

    /// The text-safe box of a library shape; the fallback for one this
    /// build does not have.
    static func inset(for shapeId: String?) -> ShapeTextInset {
        table[shapeId ?? "rect"] ?? fallback
    }

    /// The element's: path data, which wins over its shapeId when it draws,
    /// takes the fallback.
    static func inset(of el: Element) -> ShapeTextInset {
        if let d = el.pathData, !d.isEmpty { return fallback }
        return inset(for: el.shapeId)
    }
}

enum ShapeText {

    /// The ink on a light fill, and on a dark one.
    static let darkInk = "#1f2430"
    static let lightInk = "#ffffff"

    /// Whether a shape takes words: any shape but a photo poured into one (a
    /// photo frame), a drawn stroke and a line drawn as a path with no fill
    /// (a line chart's), which are lines, not areas. Photos, frames, QR codes
    /// and lines are other kinds altogether.
    static func takesText(_ el: Element) -> Bool {
        guard el.type == .shape, el.fill?.kind != "image", !Freehand.isStroke(el) else { return false }
        if el.pathData?.isEmpty == false, el.stroke != nil, ContrastAudit.isFaint(el.fill?.color ?? "") {
            return false
        }
        return true
    }

    /// A text box, or a shape that takes words: what the text controls,
    /// find and replace and the rest reach.
    static func carriesWords(_ el: Element) -> Bool {
        el.type == .text || takesText(el)
    }

    /// The words a shape has to draw, style marks and all; nil when it has
    /// none, or cannot take any.
    static func words(of el: Element) -> String? {
        guard takesText(el), let text = el.text,
              !RichText.strip(text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    // MARK: the first words

    /// The type size words start at in a shape: 18% of its shorter side,
    /// from 12 to 72, whole.
    static func defaultFontSize(width: Double, height: Double) -> Double {
        min(max(min(width, height) * 0.18, 12), 72).rounded()
    }

    /// The ink that stands out on a fill, by the rule the highlight effect
    /// picks its bar by: dark on light, white on dark. A gradient is read by
    /// its first stop; a pattern, a photo or no fill as white.
    static func defaultInk(for fill: Paint?) -> String {
        let paint = fill ?? .solid("#8b5cf6")
        let colour: String
        switch paint.kind {
        case "solid": colour = paint.color ?? "#8b5cf6"
        case "gradient": colour = paint.stops?.first?.color ?? "#ffffff"
        default: colour = "#ffffff"
        }
        return UIColor(hex: colour).isLight ? darkInk : lightInk
    }

    /// The shape as its first words find it: the default face, a size from
    /// its box, centred and middled, in the ink that stands out on its fill.
    /// Only what it does not say already — a look chosen before the words
    /// came is kept.
    static func starting(_ el: Element) -> Element {
        var out = el
        if out.fontFamily == nil { out.fontFamily = "sans" }
        if out.fontSize == nil { out.fontSize = defaultFontSize(width: el.w, height: el.h) }
        if out.align == nil { out.align = "center" }
        if out.vAlign == nil { out.vAlign = "middle" }
        if out.color == nil { out.color = defaultInk(for: el.fill) }
        return out
    }

    /// The shape once typing in it is over with no words left: the words
    /// gone, and — when it had none before the typing — the look they were
    /// given then too, so a shape opened and left is the shape it was.
    static func withoutWords(_ el: Element, was before: Element?) -> Element {
        var out = el
        out.text = nil
        guard let before, (before.text ?? "").isEmpty else { return out }
        out.fontFamily = before.fontFamily
        out.fontSize = before.fontSize
        out.align = before.align
        out.vAlign = before.vAlign
        out.color = before.color
        return out
    }

    // MARK: layout

    /// The width a border takes off each side of the words' box.
    static func borderInset(_ el: Element) -> Double {
        guard el.stroke != nil, let width = el.strokeWidth, width > 0 else { return 0 }
        return width
    }

    /// Where the words are set, in the shape's own unflipped box: its
    /// text-safe part, in further by the border.
    static func box(for el: Element) -> CGRect {
        let inset = ShapeTextInsets.inset(of: el)
        let border = borderInset(el)
        let w = max(1, el.w * inset.w / 100 - 2 * border)
        let h = max(1, el.h * inset.h / 100 - 2 * border)
        return CGRect(x: el.w * inset.x / 100 + border, y: el.h * inset.y / 100 + border, width: w, height: h)
    }

    /// The same box where it shows on the page's side of the shape's flip:
    /// a flipped triangle's words sit in its wide end, the right way round.
    static func shownBox(for el: Element) -> CGRect {
        var b = box(for: el)
        if el.flipH { b.origin.x = CGFloat(el.w) - b.maxX }
        if el.flipV { b.origin.y = CGFloat(el.h) - b.maxY }
        return b
    }

    /// The words as a text box set in the shape's box, on the page — what
    /// the canvas draws, typing edits, and the SVG outlines. The shape's
    /// look where it has one, centred and middled where it has none.
    static func textElement(for el: Element) -> Element {
        let b = box(for: el)
        var t = Element()
        t.id = el.id
        t.type = .text
        t.text = el.text
        t.fontFamily = el.fontFamily
        t.fontSize = el.fontSize ?? defaultFontSize(width: el.w, height: el.h)
        t.fontWeight = el.fontWeight
        t.italic = el.italic
        t.underline = el.underline
        t.uppercase = el.uppercase
        t.align = el.align ?? "center"
        t.lineHeight = el.lineHeight
        t.letterSpacing = el.letterSpacing
        t.color = el.color ?? defaultInk(for: el.fill)
        t.vAlign = el.vAlign ?? "middle"
        t.x = el.x + Double(b.minX)
        t.y = el.y + Double(b.minY)
        t.w = Double(b.width)
        t.h = Double(b.height)
        return t
    }

    /// How tall a shape must be for words `wordsHeight` tall to fit its
    /// text-safe box, `insetHeight` percent of it less the border above and
    /// below: the height as it is when they fit, else grown down just enough
    /// that they do. Never less than it is — a shape grows for its words and
    /// is never shrunk for them.
    static func grownHeight(height: Double, insetHeight: Double, border: Double, wordsHeight: Double) -> Double {
        guard insetHeight > 0 else { return height }
        let room = height * insetHeight / 100 - 2 * border
        // Below a rounding error, words fit.
        guard wordsHeight > room + 1e-6 else { return height }
        return max(height, (wordsHeight + 2 * border) * 100 / insetHeight)
    }

    /// The shape's height for the words it has now, as typing leaves it.
    static func grownHeight(for el: Element) -> Double {
        guard words(of: el) != nil else { return el.h }
        let needed = FontLibrary.measuredHeight(for: textElement(for: el))
        return grownHeight(height: el.h, insetHeight: ShapeTextInsets.inset(of: el).h,
                           border: borderInset(el), wordsHeight: needed)
    }

    /// The box's height once its words or their type changed: a text box
    /// hugs them, a shape grows to hold them.
    static func heightForWords(_ el: Element) -> Double {
        el.type == .shape ? grownHeight(for: el) : FontLibrary.layoutHeight(for: el)
    }
}
