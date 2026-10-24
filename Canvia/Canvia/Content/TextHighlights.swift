// Marker colours behind chosen words (TextSpan.highlight), found on the lines
// the words are set on: each line framed by CoreText from the very string
// the canvas draws, its marks from Spans.highlightRects — a rounded
// rectangle over each highlighted run, the line's height, reaching
// 0.08 em past the words at each side. The canvas draws them under the
// letters and their effects, over a box-wide Highlight bar; SVG (and so
// HTML) writes them as rects before the letters, and the PDF draws them
// as the canvas does. The Android twin finds the same rects from its layout.

import Foundation
import UIKit
import CoreText

enum TextHighlights {

    /// The marks behind `el`'s words, as drawn — fitted type at the size it
    /// is drawn at — framed at `width`, its lines starting `top` down the
    /// box; none when no word is highlighted.
    static func rects(for el: Element, width: Double, top: Double) -> [Spans.HighlightRect] {
        guard el.liveSpans.contains(where: { $0.highlight != nil }) else { return [] }
        let attributed = FontLibrary.attributedString(for: el)
        let whole = NSRange(location: 0, length: attributed.length)
        var marks: [TextSpan] = []
        attributed.enumerateAttribute(Spans.highlightKey, in: whole) { value, range, _ in
            guard let hex = value as? String else { return }
            marks.append(TextSpan(start: range.location, end: NSMaxRange(range), highlight: hex))
        }
        guard !marks.isEmpty else { return [] }
        let em = el.fontSize ?? 42
        return lines(attributed, el: el, width: width, top: top).flatMap { line in
            Spans.highlightRects(marks, start: line.start, end: line.end, top: line.top, bottom: line.bottom,
                                 em: em, offset: line.x)
        }
    }

    /// One line of words as drawn: its letters `start..<end` of the drawn
    /// string — the break after it and the spaces it ends in left out —
    /// from `top` to `bottom`, and the x of the edge before each letter.
    struct LineBox {
        var start: Int
        var end: Int
        var top: Double
        var bottom: Double
        var x: (Int) -> Double
    }

    /// The lines `attributed` — `el`'s words as the canvas draws them —
    /// is set in at `width`, the first `top` down the box: each the pitch
    /// high, unless its paragraph has room for a larger word, with the
    /// paragraph spacing after each line break — as the box Highlight's
    /// bars are placed. What the marks behind words and text moving a unit
    /// at a time are laid on.
    static func lines(_ attributed: NSAttributedString, el: Element, width: Double, top: Double) -> [LineBox] {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 100000), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return [] }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let string = attributed.string as NSString
        let em = el.fontSize ?? 42
        let pitch = em * (el.lineHeight ?? 1.25)
        let gap = em * max(0, el.paragraphSpacing ?? 0)
        var lineTop = top
        var out: [LineBox] = []
        for (i, line) in lines.enumerated() {
            let range = CTLineGetStringRange(line)
            var end = range.location + range.length
            let endsParagraph = end >= string.length || (end > 0 && string.character(at: end - 1) == 10)
            let topY = lineTop
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let style = range.location < attributed.length
                ? attributed.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                : nil
            let room = max(pitch, Double(style?.maximumLineHeight ?? 0))
            let height = min(max(Double(ascent + descent + leading), pitch), room)
            lineTop += height
            if endsParagraph { lineTop += gap }
            while end > range.location, let last = UnicodeScalar(string.character(at: end - 1)),
                  CharacterSet.whitespacesAndNewlines.contains(last) {
                end -= 1
            }
            let x = Double(origins[i].x)
            out.append(LineBox(start: range.location, end: end, top: topY, bottom: topY + height) { index in
                x + Double(CTLineGetOffsetForStringIndex(line, index, nil))
            })
        }
        return out
    }

    /// `hex` ("#rrggbb" or "#rrggbbaa") as a colour and an opacity, for
    /// formats that write the two apart.
    static func split(_ hex: String) -> (color: String, alpha: Double) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 8, let value = UInt32(s, radix: 16) else { return ("#" + s, 1) }
        return ("#" + s.prefix(6), Double(value & 0xff) / 255)
    }

    /// The marks drawn into `cg`, in the box's space.
    static func draw(_ marks: [Spans.HighlightRect], in cg: CGContext) {
        for mark in marks {
            let bar = CGRect(x: mark.x, y: mark.y, width: mark.w, height: mark.h)
            cg.setFillColor(UIColor(hex: mark.color).cgColor)
            // CoreGraphics refuses a corner wider than half the bar.
            let radius = min(mark.radius, bar.width / 2, bar.height / 2)
            if radius > 0 {
                cg.addPath(CGPath(roundedRect: bar, cornerWidth: radius, cornerHeight: radius, transform: nil))
                cg.fillPath()
            } else {
                cg.fill(bar)
            }
        }
    }
}
