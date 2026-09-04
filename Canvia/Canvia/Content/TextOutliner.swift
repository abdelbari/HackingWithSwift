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
    static func path(for el: Element) -> CGPath? {
        let text = FontLibrary.displayText(for: el)
        guard !text.isEmpty, el.w > 0, el.h > 0 else { return nil }

        let attributed = NSAttributedString(string: text,
                                            attributes: FontLibrary.attributes(for: el))
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let box = CGPath(rect: CGRect(x: 0, y: 0, width: el.w, height: el.h), transform: nil)
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

        let combined = CGMutablePath()
        for (index, line) in lines.enumerated() {
            let lineOrigin = origins[index]
            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }
            for run in runs {
                appendGlyphs(of: run, lineOrigin: lineOrigin, boxHeight: el.h,
                             fallback: declared, to: combined)
            }
        }
        return combined.isEmpty ? nil : combined
    }

    private static func appendGlyphs(of run: CTRun, lineOrigin: CGPoint, boxHeight: Double,
                                     fallback: UIFont, to combined: CGMutablePath) {
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

        for i in 0..<count {
            guard let glyph = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
            // CoreText places glyphs in a y-up space whose origin is the
            // frame's bottom-left; the element's space is y-down from its
            // top-left. Translate to the glyph's pen position, then flip.
            let x = lineOrigin.x + positions[i].x
            let y = boxHeight - (lineOrigin.y + positions[i].y)
            let transform = CGAffineTransform(translationX: x, y: y).scaledBy(x: 1, y: -1)
            combined.addPath(glyph, transform: transform)
        }
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
