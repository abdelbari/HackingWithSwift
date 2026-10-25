// Where linked words are: a link on chosen words (see Spans) is clickable in
// the exported PDF and SVG and opened by a tap in Present only over those
// words, so each word is a rectangle of its own — from its first letter to
// its last, the height of the line it is on — found in the same CoreText
// layout the words are outlined from. A word is a run with no space or line
// break in it, so the spaces between linked words are not clickable, and a
// link that wraps over two lines is a rectangle on each, as the Android
// twin's WordLinks.rects cuts them.
//
// Words round a curve, along a path or down a column are found letter by
// letter where the outliner set them (TextPaths.glyphPlacements): each word
// the box round its letters' turned quads, which is what a tap, the PDF and
// the SVG take — a warp's words are reached through the element's own link,
// if it has one. A drop cap's body is laid out as it is
// drawn — without the letter, round the cap's corner — and the letter itself
// is not a link's, as on the Android twin.

import CoreGraphics
import CoreText
import UIKit

enum WordLinks {

    /// Each linked word in `el` with its link, in the box's own
    /// space — its top-left the origin, y down — as the canvas sets them: at
    /// the size a fitted box draws, from where a vertically aligned box
    /// starts its words.
    static func rects(for el: Element) -> [(rect: CGRect, url: String)] {
        guard el.type == .text, el.w > 0, el.liveSpans.contains(where: { $0.link != nil }) else { return [] }
        if TextOutliner.followsAPath(el) {
            return quads(for: el).map { (rect: bounds(of: $0.quads), url: $0.url) }
        }
        var drawn = el
        if el.fitText == true { drawn.fontSize = FontLibrary.fittingFontSize(for: el) }
        let top = SVGExporter.textTop(el)
        var text = FontLibrary.attributedString(for: drawn)
        var notch: CGSize?
        // A drop cap, as ElementView.drawDropCap sets it: the body past the
        // letter, framed round the cap's corner.
        if TextEffect.from(el.effect) == .none, let layout = FontLibrary.dropCapLayout(for: drawn) {
            text = FontLibrary.dropCapText(for: drawn, layout).body
            notch = layout.capRect.size
        }
        return wordRects(text, width: el.w, notch: notch).map { entry in
            (rect: entry.rect.offsetBy(dx: 0, dy: CGFloat(top)), url: entry.url)
        }
    }

    /// The lines of `text` set `width` wide, and on each every word of the
    /// letters carrying a link (Spans.linkKey): one rectangle a word, from
    /// where it starts on its line to where it ends (either way round, for
    /// right to left), as tall as the line.
    static func wordRects(_ text: NSAttributedString, width: Double) -> [(rect: CGRect, url: String)] {
        wordRects(text, width: width, notch: nil)
    }

    /// As above, with a `notch` — a drop cap's corner, cut from the
    /// top-left — that the first lines wrap beside.
    static func wordRects(_ text: NSAttributedString, width: Double, notch: CGSize?) -> [(rect: CGRect, url: String)] {
        guard text.length > 0, width > 0 else { return [] }
        let tall: CGFloat = 100_000
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: CGFloat(width), height: tall))
        var options: CFDictionary?
        if let notch {
            path.addRect(CGRect(x: 0, y: tall - notch.height, width: notch.width, height: notch.height))
            options = [kCTFramePathFillRuleAttributeName: CTFramePathFillRule.evenOdd.rawValue] as CFDictionary
        }
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, options)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return [] }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let string = text.string as NSString
        var out: [(rect: CGRect, url: String)] = []
        for (index, line) in lines.enumerated() {
            let range = CTLineGetStringRange(line)
            guard range.length > 0 else { continue }
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            // CoreText's y runs up from the frame's foot; the box's down.
            let origin = origins[index]
            let top = tall - origin.y - ascent
            let span = NSRange(location: range.location, length: range.length)
            text.enumerateAttribute(Spans.linkKey, in: span) { value, part, _ in
                guard let url = value as? String else { return }
                let end = NSMaxRange(part)
                var start = part.location
                while start < end {
                    if isSpace(string.character(at: start)) {
                        start += 1
                        continue
                    }
                    var stop = start
                    while stop < end, !isSpace(string.character(at: stop)) { stop += 1 }
                    let a = CTLineGetOffsetForStringIndex(line, start, nil)
                    let b = CTLineGetOffsetForStringIndex(line, stop, nil)
                    if abs(b - a) > 0 {
                        out.append((rect: CGRect(x: origin.x + min(a, b), y: top,
                                                 width: abs(b - a), height: ascent + descent),
                                    url: url))
                    }
                    start = stop
                }
            }
        }
        return out
    }

    /// Each linked word of bent words with its link: its letters' quads
    /// (TextPaths.GlyphPlacement.quad), a word being the letters of a link
    /// with no space between them; none for straight or warped words.
    static func quads(for el: Element) -> [(quads: [[CGPoint]], url: String)] {
        let placed = TextPaths.glyphPlacements(el)
        guard !placed.isEmpty else { return [] }
        let plain = RichText.strip(el.text ?? "") as NSString
        var out: [(quads: [[CGPoint]], url: String)] = []
        for span in el.liveSpans {
            guard let url = span.link else { continue }
            var word: [[CGPoint]] = []
            var last = -1
            for glyph in placed where glyph.index >= span.start && glyph.index < span.end {
                let spaced = glyph.index < plain.length && isSpace(plain.character(at: glyph.index))
                // A space, or a gap in the letters (a line's break), ends a word.
                if spaced || (last >= 0 && glyph.index > last + 1 && !word.isEmpty) {
                    if !word.isEmpty { out.append((quads: word, url: url)) }
                    word = []
                }
                last = glyph.index
                if !spaced { word.append(glyph.quad) }
            }
            if !word.isEmpty { out.append((quads: word, url: url)) }
        }
        return out
    }

    /// The upright box round `quads`.
    static func bounds(of quads: [[CGPoint]]) -> CGRect {
        let points = quads.flatMap { $0 }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .null }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// What splits linked words, as Kotlin's Char.isWhitespace has it on the
    /// Android twin: a space, line or paragraph separator of any kind, or a
    /// control from tab to carriage return or U+001C to U+001F.
    private static func isSpace(_ unit: unichar) -> Bool {
        if (0x09...0x0D).contains(unit) || (0x1C...0x1F).contains(unit) { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return true
        default:
            return false
        }
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
    static func inBox(_ p: CGPoint, of el: Element) -> CGPoint {
        let upright = el.rotation == 0 ? p : Geometry.rotate(p, around: el.center, degrees: -el.rotation)
        let x = Double(upright.x) - el.x, y = Double(upright.y) - el.y
        return CGPoint(x: el.flipH ? el.w - x : x, y: el.flipV ? el.h - y : y)
    }
}
