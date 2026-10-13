// Where linked words are: a link on chosen words (see Spans) is clickable in
// the exported PDF and SVG and opened by a tap in Present only over those
// words, so each line they are set on is a rectangle of its own — from the
// first linked letter on the line to the last, the line's height — found in
// the same CoreText layout the words are outlined from. A link that wraps
// over two lines is two rectangles, on both phones.
//
// Only straight lines: words round a curve, along a path or down a column are
// drawn from outlines that carry no link, and are reached through the
// element's own link, if it has one.

import CoreGraphics
import CoreText
import UIKit

enum WordLinks {

    /// Each line of linked words in `el` with its link, in the box's own
    /// space — its top-left the origin, y down — as the canvas sets them: at
    /// the size a fitted box draws, from where a vertically aligned box
    /// starts its words.
    static func rects(for el: Element) -> [(rect: CGRect, url: String)] {
        guard el.type == .text, el.w > 0, !TextOutliner.followsAPath(el),
              el.liveSpans.contains(where: { $0.link != nil }) else { return [] }
        var drawn = el
        if el.fitText == true { drawn.fontSize = FontLibrary.fittingFontSize(for: el) }
        let top = SVGExporter.textTop(el)
        return lineRects(FontLibrary.attributedString(for: drawn), width: el.w).map { entry in
            (rect: entry.rect.offsetBy(dx: 0, dy: CGFloat(top)), url: entry.url)
        }
    }

    /// The lines of `text` set `width` wide, and on each the stretch of
    /// letters carrying a link (Spans.linkKey), spaces at its end left off.
    static func lineRects(_ text: NSAttributedString, width: Double) -> [(rect: CGRect, url: String)] {
        guard text.length > 0, width > 0 else { return [] }
        let tall: CGFloat = 100_000
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: CGFloat(width), height: tall), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return [] }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let string = text.string as NSString
        var out: [(rect: CGRect, url: String)] = []
        for (i, line) in lines.enumerated() {
            let range = CTLineGetStringRange(line)
            guard range.length > 0 else { continue }
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            // CoreText's y runs up from the frame's foot; the box's down.
            let baseline = tall - origins[i].y
            let span = NSRange(location: range.location, length: range.length)
            text.enumerateAttribute(Spans.linkKey, in: span) { value, part, _ in
                guard let url = value as? String else { return }
                var end = NSMaxRange(part)
                while end > part.location, isSpace(string.character(at: end - 1)) { end -= 1 }
                guard end > part.location else { return }
                let a = CTLineGetOffsetForStringIndex(line, part.location, nil)
                let b = CTLineGetOffsetForStringIndex(line, end, nil)
                let left = origins[i].x + min(a, b), right = origins[i].x + max(a, b)
                guard right > left else { return }
                out.append((rect: CGRect(x: left, y: baseline - ascent, width: right - left, height: ascent + descent),
                            url: url))
            }
        }
        return out
    }

    private static func isSpace(_ unit: unichar) -> Bool {
        unit == 32 || unit == 10 || unit == 9 || unit == 13 || unit == 0x2028 || unit == 0x2029
    }

    /// The same rectangles on the page: each turned and flipped with the
    /// box, as the rectangle that holds it.
    static func areas(of el: Element) -> [(rect: CGRect, url: String)] {
        rects(for: el).map { entry -> (rect: CGRect, url: String) in
            let corners = [CGPoint(x: entry.rect.minX, y: entry.rect.minY),
                           CGPoint(x: entry.rect.maxX, y: entry.rect.minY),
                           CGPoint(x: entry.rect.maxX, y: entry.rect.maxY),
                           CGPoint(x: entry.rect.minX, y: entry.rect.maxY)].map { onPage($0, of: el) }
            let xs = corners.map(\.x), ys = corners.map(\.y)
            let rect = CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0,
                              width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
            return (rect: rect, url: entry.url)
        }
    }

    /// The link of the words under page point `point` in `el`, if any.
    static func link(in el: Element, at point: CGPoint) -> String? {
        let found = rects(for: el)
        guard !found.isEmpty else { return nil }
        let local = inBox(point, of: el)
        return found.last { $0.rect.contains(local) }?.url
    }

    /// A point in the box's own space on the page.
    private static func onPage(_ p: CGPoint, of el: Element) -> CGPoint {
        let x = el.flipH ? el.w - Double(p.x) : Double(p.x)
        let y = el.flipV ? el.h - Double(p.y) : Double(p.y)
        let page = CGPoint(x: el.x + x, y: el.y + y)
        return el.rotation == 0 ? page : Geometry.rotate(page, around: el.center, degrees: el.rotation)
    }

    /// A point on the page in the box's own space.
    private static func inBox(_ p: CGPoint, of el: Element) -> CGPoint {
        let upright = el.rotation == 0 ? p : Geometry.rotate(p, around: el.center, degrees: -el.rotation)
        let x = Double(upright.x) - el.x, y = Double(upright.y) - el.y
        return CGPoint(x: el.flipH ? el.w - x : x, y: el.flipV ? el.h - y : y)
    }
}
