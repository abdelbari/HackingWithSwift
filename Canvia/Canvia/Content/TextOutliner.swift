// Text as vector outlines.
//
// Needed because Canvia's twelve font personalities map to faces that ship
// with iOS — Didot, Rockwell, Snell Roundhand, Futura Condensed ExtraBold —
// and none of them exist on the machine a designer opens an exported file on.
// An SVG carrying <text> would render there in whatever the browser
// substitutes, which is to say: not the design. Outlines carry the letterforms
// themselves, so the file looks the same everywhere and stays vector.
//
// The layout is CoreText's, in the element's own box, so it matches what the
// canvas draws: same attributes from FontLibrary, same wrap width, same line
// height. What it deliberately does not carry is the text effects — a neon
// glow or a splice is a raster or a stroke on top of these outlines, and
// belongs to whoever draws them, not to the geometry.

import CoreGraphics
import CoreText
import UIKit

enum TextOutliner {

    /// Every glyph of `el`, as one path in the element's own coordinate space:
    /// origin at its top-left, y increasing downward, which is the space SVG
    /// and the canvas both use.
    /// Below this the arc is indistinguishable from a straight line, and the
    /// radius it implies is large enough to lose precision.
    static let straightBelowDegrees = 1.0

    static func path(for el: Element) -> CGPath? {
        ink(for: el)?.joined
    }

    /// The same glyphs, whole and apart by the colour each word is set in
    /// (see Spans): nil for the element's own, which comes first when it is
    /// there. One part, in nil, when no word has a colour of its own.
    static func inkedPaths(for el: Element) -> (whole: CGPath, parts: [InkedPath])? {
        guard let ink = ink(for: el), let whole = ink.joined else { return nil }
        return (whole, ink.parts)
    }

    /// Glyphs in one colour.
    struct InkedPath {
        /// "#rrggbb", or nil for the element's own colour.
        var color: String?
        var path: CGPath
    }

    private static func ink(for el: Element) -> Ink? {
        if el.vertical == true {
            return verticalInk(for: el)
        }
        if let data = el.textPath, !data.isEmpty {
            return pathTextInk(for: el, data: data)
        }
        if let degrees = el.curve, abs(degrees) >= straightBelowDegrees {
            return curvedInk(for: el, degrees: degrees)
        }
        return straightInk(for: el)
    }

    /// Glyph outlines as they are gathered: all together, and apart by the
    /// colour each was set in — with the underlines and strikes, which are
    /// joined to the letters at the end.
    private final class Ink {
        let all = CGMutablePath()
        let allRules = CGMutablePath()
        private var glyphs: [(color: String?, path: CGMutablePath)] = []
        private var rules: [(color: String?, path: CGMutablePath)] = []

        var isEmpty: Bool { all.isEmpty }

        func add(_ glyph: CGPath, transform: CGAffineTransform, color: String?) {
            all.addPath(glyph, transform: transform)
            Self.part(color, in: &glyphs).addPath(glyph, transform: transform)
        }

        func addRule(_ rect: CGRect, color: String?) {
            allRules.addRect(rect)
            Self.part(color, in: &rules).addRect(rect)
        }

        private static func part(_ color: String?, in parts: inout [(color: String?, path: CGMutablePath)]) -> CGMutablePath {
            if let found = parts.first(where: { $0.color == color }) { return found.path }
            let path = CGMutablePath()
            parts.append((color: color, path: path))
            return path
        }

        /// Everything, as one path.
        var joined: CGPath? {
            if all.isEmpty { return nil }
            return allRules.isEmpty ? all : all.union(allRules)
        }

        /// By colour, the element's own first.
        var parts: [InkedPath] {
            let colours = (glyphs.map(\.color) + rules.map(\.color)).reduce(into: [String?]()) { seen, colour in
                if !seen.contains(colour) { seen.append(colour) }
            }
            let ordered = colours.filter { $0 == nil } + colours.filter { $0 != nil }
            return ordered.compactMap { colour -> InkedPath? in
                let letters = glyphs.first { $0.color == colour }?.path
                let rule = rules.first { $0.color == colour }?.path
                switch (letters, rule) {
                case let (letters?, rule?): return InkedPath(color: colour, path: letters.union(rule))
                case let (letters?, nil): return InkedPath(color: colour, path: letters)
                case let (nil, rule?): return InkedPath(color: colour, path: rule)
                case (nil, nil): return nil
                }
            }
        }

        /// The same outlines moved by `transform`.
        func transformed(_ transform: CGAffineTransform) -> Ink {
            let out = Ink()
            out.all.addPath(all, transform: transform)
            out.allRules.addPath(allRules, transform: transform)
            for part in glyphs { Self.part(part.color, in: &out.glyphs).addPath(part.path, transform: transform) }
            for part in rules { Self.part(part.color, in: &out.rules).addPath(part.path, transform: transform) }
            return out
        }
    }

    /// The span colour a run of glyphs was set in, or nil for the element's.
    private static func colour(of run: CTRun) -> String? {
        let attributes = CTRunGetAttributes(run) as? [String: Any]
        return attributes?[Spans.colourKey.rawValue] as? String
    }

    /// Whether the text is drawn as glyph outlines on a curve or a path
    /// rather than as straight lines.
    static func followsAPath(_ el: Element) -> Bool {
        if el.vertical == true { return true }
        if let data = el.textPath, !data.isEmpty { return true }
        return el.curve.map { abs($0) >= straightBelowDegrees } ?? false
    }

    /// Glyphs set along `data`, scaled into the element's box, each by its
    /// centre at its share of the path's length; the text is centred on the
    /// path when it is shorter than the path and runs off the end when it is
    /// longer, so a box that is too small says so rather than squeezing.
    static func pathText(for el: Element, data: String) -> CGPath? {
        pathTextInk(for: el, data: data)?.joined
    }

    private static func pathTextInk(for el: Element, data: String) -> Ink? {
        guard let attributed = flatLine(for: el), el.w > 0, el.h > 0 else { return nil }
        let walker = PathWalker(SVGPath.scaledPath(data, to: CGSize(width: el.w, height: el.h)))
        guard walker.length > 1 else { return nil }

        let line = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        guard width > 0.5, let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return nil }
        let start = max(0, (walker.length - width) / 2)
        let declared = FontLibrary.uiFont(family: el.fontFamily, size: el.fontSize ?? 42,
                                          weight: el.fontWeight ?? 400, italic: el.italic ?? false)

        let ink = Ink()
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attributes = CTRunGetAttributes(run) as? [String: Any]
            let uiFont = attributes?[kCTFontAttributeName as String] as? UIFont ?? declared
            let font = CTFontCreateWithName(uiFont.fontName as CFString, uiFont.pointSize, nil)
            let tint = colour(of: run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            let range = CFRange(location: 0, length: count)
            CTRunGetGlyphs(run, range, &glyphs)
            CTRunGetPositions(run, range, &positions)
            CTRunGetAdvances(run, range, &advances)
            for i in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
                let centre = start + Double(positions[i].x) + Double(advances[i].width) / 2
                let here = walker.locate(centre)
                let transform = CGAffineTransform(translationX: here.point.x, y: here.point.y)
                    .rotated(by: here.angle)
                    .translatedBy(x: -advances[i].width / 2, y: 0)
                    .scaledBy(x: 1, y: -1)
                ink.add(glyph, transform: transform, color: tint)
            }
        }
        return ink.isEmpty ? nil : ink
    }

    /// The words on one line, for a curve or a path: the lines joined by
    /// spaces and the ends trimmed, in the box's type and the colours set on
    /// words — never their sizes, which a curve does not take.
    private static func flatLine(for el: Element) -> NSAttributedString? {
        let joined = FontLibrary.displayText(for: el)
            .components(separatedBy: "\n")
            .joined(separator: " ")
        let flat = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return nil }
        let attributed = NSMutableAttributedString(string: flat, attributes: FontLibrary.attributes(for: el))
        let colours = FontLibrary.displayColours(for: el)
        if !colours.isEmpty {
            // Moved back by the spaces trimmed from the start.
            let lead = (joined as NSString).range(of: flat).location
            FontLibrary.colourWords(attributed, colours, shift: -lead)
        }
        return attributed
    }

    /// Vertical writing: each character upright, stacked down a column at
    /// the line height, columns filling from the right edge leftward and a
    /// new column at every newline or when the box runs out. Latin letters
    /// stack upright too, the way a shop sign does.
    static func verticalPath(for el: Element) -> CGPath? {
        verticalInk(for: el)?.joined
    }

    private static func verticalInk(for el: Element) -> Ink? {
        let text = FontLibrary.displayText(for: el)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, el.w > 0, el.h > 0 else { return nil }
        let size = el.fontSize ?? 42
        let step = size * (el.lineHeight ?? 1.25)
        let columnWidth = size * 1.3
        let attrs = FontLibrary.attributes(for: el)
        let declared = FontLibrary.uiFont(family: el.fontFamily, size: size,
                                          weight: el.fontWeight ?? 400, italic: el.italic ?? false)
        // Each character with where it is in the text, for its colour.
        let colours = FontLibrary.displayColours(for: el)
        func colour(at offset: Int) -> String? {
            colours.first { $0.start <= offset && offset < $0.end }?.color
        }
        // Columns: split at newlines, then at the box's height.
        let perColumn = max(1, Int(el.h / step))
        var columns: [[(char: Character, color: String?)]] = []
        var offset = 0
        for paragraph in text.components(separatedBy: "\n") {
            var chars: [(char: Character, color: String?)] = []
            for ch in paragraph {
                chars.append((char: ch, color: colour(at: offset)))
                offset += String(ch).utf16.count
            }
            offset += 1
            if chars.isEmpty { columns.append([]); continue }
            var i = 0
            while i < chars.count {
                columns.append(Array(chars[i..<min(i + perColumn, chars.count)]))
                i += perColumn
            }
        }
        // Columns run from the right; the block is centred across the box.
        let blockWidth = Double(columns.count) * columnWidth
        let rightEdge = el.w / 2 + blockWidth / 2
        let ink = Ink()
        for (c, column) in columns.enumerated() {
            let centreX = rightEdge - (Double(c) + 0.5) * columnWidth
            let columnHeight = Double(column.count) * step
            let top: Double
            switch el.vAlign ?? "top" {
            case "middle": top = (el.h - columnHeight) / 2
            case "bottom": top = el.h - columnHeight
            default: top = 0
            }
            for (r, entry) in column.enumerated() where entry.char != " " {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(entry.char), attributes: attrs))
                var ascent: CGFloat = 0, descent: CGFloat = 0
                let advance = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
                guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }
                // The glyph's centre at the column's centre, its baseline so
                // the letter is centred in its step.
                let baselineY = top + Double(r) * step + (step + Double(ascent) - Double(descent)) / 2
                for run in runs {
                    let count = CTRunGetGlyphCount(run)
                    guard count > 0 else { continue }
                    let attributes = CTRunGetAttributes(run) as? [String: Any]
                    let uiFont = attributes?[kCTFontAttributeName as String] as? UIFont ?? declared
                    let font = CTFontCreateWithName(uiFont.fontName as CFString, uiFont.pointSize, nil)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                    CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                    for i in 0..<count {
                        guard let glyph = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
                        let transform = CGAffineTransform(translationX: centreX - advance / 2 + positions[i].x, y: baselineY)
                            .scaledBy(x: 1, y: -1)
                        ink.add(glyph, transform: transform, color: entry.color)
                    }
                }
            }
        }
        return ink.isEmpty ? nil : ink
    }

    private static func straightInk(for el: Element) -> Ink? {
        let text = FontLibrary.displayText(for: el)
        guard !text.isEmpty, el.w > 0, el.h > 0 else { return nil }

        // With the inline styles, so a bold word outlines as bold glyphs.
        let attributed = FontLibrary.attributedString(for: el)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        // Never shorter than the text needs: CoreText drops any line that
        // does not fit the frame, and an element whose height is a frame
        // behind its text (mid-edit, or measured for a curve it no longer
        // has) would outline as nothing at all.
        let height = max(el.h, FontLibrary.measuredHeight(for: el))
        let box = CGPath(rect: CGRect(x: 0, y: 0, width: el.w, height: height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), box, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return nil }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        // Whatever face the element asked for, used when a run does not
        // report its own — never as a substitute for one that does, because a
        // run CoreText created by fallback (Japanese inside a Latin face, say)
        // carries glyph ids that only its own font can trace.
        let declared = FontLibrary.uiFont(family: el.fontFamily,
                                          size: el.fontSize ?? 42,
                                          weight: el.fontWeight ?? 400,
                                          italic: el.italic ?? false)

        let ink = Ink()
        for (index, line) in lines.enumerated() {
            let lineOrigin = origins[index]
            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }
            for run in runs {
                appendGlyphs(of: run, lineOrigin: lineOrigin, boxHeight: el.h,
                             fallback: declared, to: ink)
                appendRules(of: run, lineOrigin: lineOrigin, boxHeight: el.h,
                            fallback: declared, to: ink)
            }
        }
        // Underlines and strikethroughs are kept, as the canvas draws them
        // and as the Android twin's outlines keep them: a struck-out price
        // is not a price. Joined to the letters, so a rule crossing one
        // never cuts a hole through it.
        return ink.isEmpty ? nil : ink
    }

    /// The underline and strikethrough a run carries, as filled bars under
    /// and through its letters, at the face's own underline position and
    /// thickness — the strike halfway up the lower-case letters.
    private static func appendRules(of run: CTRun, lineOrigin: CGPoint, boxHeight: Double,
                                    fallback: UIFont, to ink: Ink) {
        let count = CTRunGetGlyphCount(run)
        guard count > 0 else { return }
        let attributes = CTRunGetAttributes(run) as? [String: Any] ?? [:]
        let underlined = (attributes[NSAttributedString.Key.underlineStyle.rawValue] as? Int ?? 0) != 0
        let struck = (attributes[NSAttributedString.Key.strikethroughStyle.rawValue] as? Int ?? 0) != 0
        guard underlined || struck else { return }
        let uiFont = attributes[kCTFontAttributeName as String] as? UIFont ?? fallback
        let font = CTFontCreateWithName(uiFont.fontName as CFString, uiFont.pointSize, nil)
        var first = CGPoint.zero
        CTRunGetPositions(run, CFRange(location: 0, length: 1), &first)
        let width = CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil)
        guard width > 0 else { return }
        let x = Double(lineOrigin.x + first.x)
        let baseline = boxHeight - Double(lineOrigin.y + first.y)
        let thickness = max(1, Double(CTFontGetUnderlineThickness(font)))
        let tint = colour(of: run)
        if underlined {
            // The position is below the baseline, negative in CoreText's
            // y-up space, and names the rule's centre.
            let centre = baseline - Double(CTFontGetUnderlinePosition(font))
            ink.addRule(CGRect(x: x, y: centre - thickness / 2, width: width, height: thickness), color: tint)
        }
        if struck {
            let centre = baseline - Double(CTFontGetXHeight(font)) / 2
            ink.addRule(CGRect(x: x, y: centre - thickness / 2, width: width, height: thickness), color: tint)
        }
    }

    private static func appendGlyphs(of run: CTRun, lineOrigin: CGPoint, boxHeight: Double,
                                     fallback: UIFont, to ink: Ink) {
        let count = CTRunGetGlyphCount(run)
        guard count > 0 else { return }
        let attributes = CTRunGetAttributes(run) as? [String: Any]
        let uiFont = attributes?[kCTFontAttributeName as String] as? UIFont ?? fallback
        // Rebuilt by name rather than cast: UIFont and CTFont are bridged, but
        // rebuilding is expressible in plain Swift and a font of the same face
        // at the same size traces identical outlines.
        let font = CTFontCreateWithName(uiFont.fontName as CFString, uiFont.pointSize, nil)

        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        let range = CFRange(location: 0, length: count)
        CTRunGetGlyphs(run, range, &glyphs)
        CTRunGetPositions(run, range, &positions)
        let tint = colour(of: run)

        for i in 0..<count {
            guard let glyph = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
            // CoreText places glyphs in a y-up space whose origin is the
            // frame's bottom-left; the element's space is y-down from its
            // top-left. Translate to the glyph's pen position, then flip.
            let x = lineOrigin.x + positions[i].x
            let y = boxHeight - (lineOrigin.y + positions[i].y)
            let transform = CGAffineTransform(translationX: x, y: y).scaledBy(x: 1, y: -1)
            ink.add(glyph, transform: transform, color: tint)
        }
    }

    // MARK: curved

    /// Glyphs laid along an arc spanning `degrees`, centred in the element's
    /// box. A single line always: wrapping and an arc are contradictory, and a
    /// curved headline is what this is for.
    ///
    /// The whole layout is one circle. The text's own advance width fixes the
    /// radius — span the same width over a wider angle and the circle gets
    /// tighter — so the letters stay their natural size and only their
    /// baseline bends, which is what makes it read as type on a curve rather
    /// than as type that has been squashed.
    static func curvedPath(for el: Element, degrees: Double) -> CGPath? {
        curvedInk(for: el, degrees: degrees)?.joined
    }

    private static func curvedInk(for el: Element, degrees: Double) -> Ink? {
        guard let attributed = flatLine(for: el), el.w > 0, el.h > 0 else { return nil }

        let line = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        guard width > 0.5, let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return nil }

        let theta = degrees * .pi / 180
        let radius = width / theta
        let declared = FontLibrary.uiFont(family: el.fontFamily,
                                          size: el.fontSize ?? 42,
                                          weight: el.fontWeight ?? 400,
                                          italic: el.italic ?? false)

        let ink = Ink()
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attributes = CTRunGetAttributes(run) as? [String: Any]
            let uiFont = attributes?[kCTFontAttributeName as String] as? UIFont ?? declared
            let font = CTFontCreateWithName(uiFont.fontName as CFString, uiFont.pointSize, nil)
            let tint = colour(of: run)

            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            let range = CFRange(location: 0, length: count)
            CTRunGetGlyphs(run, range, &glyphs)
            CTRunGetPositions(run, range, &positions)
            CTRunGetAdvances(run, range, &advances)

            for i in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
                // Place each glyph by its own centre rather than its left edge,
                // so wide and narrow letters sit evenly around the arc instead
                // of drifting anticlockwise as the line goes on.
                let centreAdvance = positions[i].x + advances[i].width / 2
                let angle = (centreAdvance / width - 0.5) * theta
                let point = CGPoint(x: radius * sin(angle), y: radius * (1 - cos(angle)))
                let transform = CGAffineTransform(translationX: point.x, y: point.y)
                    .rotated(by: angle)
                    .translatedBy(x: -advances[i].width / 2, y: 0)
                    .scaledBy(x: 1, y: -1)
                ink.add(glyph, transform: transform, color: tint)
            }
        }
        guard !ink.isEmpty else { return nil }

        // Centre the arc in the element's box. Its own bounds are the only
        // honest anchor: where the apex lands depends on the angle, and a
        // fixed offset would slide the text off a steeply curved element.
        let bounds = ink.all.boundingBoxOfPath
        let centring = CGAffineTransform(
            translationX: (el.w - bounds.width) / 2 - bounds.minX,
            y: (el.h - bounds.height) / 2 - bounds.minY)
        return ink.transformed(centring)
    }

    /// The box a curved element needs. Bending a line of text makes it both
    /// narrower and much taller, and nothing else in the app can work that
    /// out — the straight measurement would clip the arc away.
    static func curvedSize(for el: Element, degrees: Double) -> CGSize? {
        var probe = el
        // Measure in a box large enough that the centring above cannot clamp
        // anything, then read the ink's own extent.
        probe.w = max(el.w, 1)
        probe.h = max(el.w, 1) * 4
        probe.curve = degrees
        guard let path = curvedPath(for: probe, degrees: degrees) else { return nil }
        let bounds = path.boundingBoxOfPath
        return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    /// SVG path data for a CGPath. Coordinates are rounded to `precision`
    /// decimals — at two, a coordinate is accurate to a hundredth of a page
    /// pixel, which is far below anything a printer or a screen resolves, and
    /// it keeps a page of outlined text from running to megabytes.
    static func svgPathData(_ path: CGPath, precision: Int = 2) -> String {
        let scale = pow(10.0, Double(precision))
        func num(_ v: CGFloat) -> String {
            let rounded = (Double(v) * scale).rounded() / scale
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }
        func point(_ p: CGPoint) -> String { "\(num(p.x)) \(num(p.y))" }

        var d = ""
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                d += "M\(point(element.points[0]))"
            case .addLineToPoint:
                d += "L\(point(element.points[0]))"
            case .addQuadCurveToPoint:
                d += "Q\(point(element.points[0])) \(point(element.points[1]))"
            case .addCurveToPoint:
                d += "C\(point(element.points[0])) \(point(element.points[1])) \(point(element.points[2]))"
            case .closeSubpath:
                d += "Z"
            @unknown default:
                break
            }
        }
        return d
    }
}
