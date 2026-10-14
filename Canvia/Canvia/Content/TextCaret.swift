// Where a tap puts the caret as typing opens in a text box, as in Canva: a
// tap on the box already selected, or a double tap, types where the finger
// was — the double tap choosing the word there — rather than always at the
// end. Laid out as the field typed in shows the words (FontLibrary.
// typedAttributedString), whose markers take no room, then put among the
// stored markers as RichText.rawCaret puts a caret. The Android twin's core
// caretFor finds it from its own layout over the same test rows.

import CoreText
import UIKit

enum TextCaret {

    /// The caret, as a UTF-16 offset into `el`'s stored words, for a tap at
    /// `point` in the box's own space — its top-left the origin, y down,
    /// before its turn and flip — the vertical alignment's room above the
    /// words taken off: the nearest place between two letters on the line
    /// the tap is on, as CoreText finds it. Left-aligned "Hello world" at
    /// size 40: a tap at x 0 is 0, one past the end 11. nil for words round
    /// a curve, along a path or down a column, where typing opens with the
    /// caret at the end.
    static func caretFor(_ el: Element, at point: CGPoint) -> Int? {
        guard el.w > 0, !TextOutliner.followsAPath(el) else { return nil }
        let text = el.text ?? ""
        var drawn = el
        drawn.fontSize = FontLibrary.effectiveFontSize(for: el)
        drawn.fitText = nil
        let shown = FontLibrary.typedAttributedString(for: drawn)
        guard shown.length > 0 else { return RichText.rawCaret(0, in: text) }
        // Laid out as WordLinks lays out words, in CoreText: y runs up from
        // the frame's foot, the box's down.
        let tall: CGFloat = 100_000
        let framesetter = CTFramesetterCreateWithAttributedString(shown)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: CGFloat(el.w), height: tall), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else {
            return RichText.rawCaret(0, in: text)
        }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        // The line the tap is on: the first whose foot is below it, else
        // the last.
        let y = point.y - CGFloat(SVGExporter.textTop(el))
        var pick = lines.count - 1
        for (i, line) in lines.enumerated() {
            var descent: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, nil, &descent, nil)
            if y <= tall - origins[i].y + descent {
                pick = i
                break
            }
        }
        let line = lines[pick]
        let range = CTLineGetStringRange(line)
        var index = CTLineGetStringIndexForPosition(line, CGPoint(x: point.x - origins[pick].x, y: 0))
        if index == kCFNotFound { index = range.location }
        let words = shown.string as NSString
        index = min(max(index, 0), words.length)
        // Past the end of a line that goes on, the caret stays on it,
        // before its break, not at the start of the next.
        if pick < lines.count - 1, index == range.location + range.length, index > range.location {
            let last = words.substring(with: NSRange(location: index - 1, length: 1))
            if last.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { index -= 1 }
        }
        return RichText.rawCaret(index, in: text)
    }

    /// The caret for a tap at page point `point` on `el` — a text box, or a
    /// shape whose words sit in its text box, the right way round — or nil
    /// where typing opens with the caret at the end.
    static func caret(in el: Element, onPage point: CGPoint) -> Int? {
        guard el.type == .shape else { return caretFor(el, at: WordLinks.inBox(point, of: el)) }
        guard ShapeText.takesText(el) else { return nil }
        let upright = el.rotation == 0 ? point : Geometry.rotate(point, around: el.center, degrees: -el.rotation)
        let box = ShapeText.shownBox(for: el)
        let local = CGPoint(x: Double(upright.x) - el.x - Double(box.minX),
                            y: Double(upright.y) - el.y - Double(box.minY))
        return caretFor(ShapeText.textElement(for: el), at: local)
    }

    /// The word a double tap at `caret` — a UTF-16 offset into the stored
    /// `text` — chooses, as the stored choice of it (RichText.snapped): the
    /// word the caret is in, else the one it is just after; the caret alone
    /// where it is beside none.
    static func word(at caret: Int, in text: String) -> NSRange {
        let plain = RichText.strip(text) as NSString
        let at = RichText.plainCaret(caret, in: text)
        var found: NSRange?
        plain.enumerateSubstrings(in: NSRange(location: 0, length: plain.length),
                                  options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            if NSLocationInRange(at, range) {
                found = range
                stop.pointee = true
            } else if NSMaxRange(range) == at {
                found = range
            }
        }
        guard let found else { return NSRange(location: caret, length: 0) }
        return RichText.snapped(RichText.storedRange(of: found, in: text), in: text, was: nil)
    }
}
