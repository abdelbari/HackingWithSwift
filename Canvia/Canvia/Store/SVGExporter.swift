// SVG export: a design as scalable vector markup.
//
// The point of this format is handing a design to something else — Illustrator,
// Figma, Inkscape, a printer's workflow — with the geometry intact rather than
// as a picture of itself. So each kind of element is exported as whatever
// keeps it editable there:
//
//   shapes and lines   real paths and strokes, from the same 100x100 library
//                      geometry the canvas draws
//   text               glyph outlines, not <text>. Canvia's faces ship with
//                      iOS and do not exist on the machine opening the file,
//                      so <text> would render in whatever a browser
//                      substitutes — which is to say, not the design. A
//                      shape's words too, in its text-safe box
//   images, stickers   embedded bitmaps, rendered through the very views the
//                      canvas uses, so crop, filter, corner radius and emoji
//                      colour come out exactly as they look in the editor
//
// Baking images through their own views is deliberate. The alternative —
// mapping crop and filters onto SVG's own primitives — is a second
// implementation of the same semantics, and the two drift.

import CoreGraphics
import SwiftUI
import UIKit

enum SVGExporter {

    /// How much of an embedded bitmap to keep. 2x the element's size on the
    /// page is enough for print at the sizes this app produces, and keeps a
    /// photo-heavy page from becoming a 40 MB text file.
    static let bitmapScale: CGFloat = 2

    @MainActor
    static func svg(design: Design, page: Page) -> String {
        var defs: [String] = []
        var body: [String] = []

        body.append(backgroundMarkup(design: design, page: page, defs: &defs))
        let number = (design.pages.firstIndex { $0.id == page.id } ?? 0) + 1
        let drawn = design.masterElements(behind: page) + page.elements
        for (index, el) in drawn.enumerated() {
            var resolved = el
            if ShapeText.carriesWords(el) {
                resolved.fillPageTokens(number: number, count: design.pages.count)
            }
            body.append(elementGroup(resolved, index: index, defs: &defs))
        }

        let size = design.size(for: page)
        let header = "<svg xmlns=\"http://www.w3.org/2000/svg\" " +
            "xmlns:xlink=\"http://www.w3.org/1999/xlink\" " +
            "width=\"\(num(size.width))\" height=\"\(num(size.height))\" " +
            "viewBox=\"0 0 \(num(size.width)) \(num(size.height))\">"
        let defsBlock = defs.isEmpty ? "" : "<defs>\(defs.joined())</defs>"
        return header + defsBlock + body.joined() + "</svg>"
    }

    // MARK: elements

    @MainActor
    private static func elementGroup(_ el: Element, index: Int, defs: inout [String]) -> String {
        var transforms: [String] = []
        let cx = el.x + el.w / 2, cy = el.y + el.h / 2
        if el.rotation != 0 {
            transforms.append("rotate(\(num(el.rotation)) \(num(cx)) \(num(cy)))")
        }
        if el.flipH || el.flipV {
            transforms.append("translate(\(num(cx)) \(num(cy))) " +
                              "scale(\(el.flipH ? -1 : 1) \(el.flipV ? -1 : 1)) " +
                              "translate(\(num(-cx)) \(num(-cy)))")
        }
        var attributes = ""
        if !transforms.isEmpty { attributes += " transform=\"\(transforms.joined(separator: " "))\"" }
        if el.opacity < 1 { attributes += " opacity=\"\(num(el.opacity))\"" }
        attributes += BlendModes.svgStyle(el.blendMode)
        if let shadow = el.shadow {
            let id = "shadow\(index)"
            defs.append(shadowDef(id: id, shadow: shadow, element: el))
            attributes += " filter=\"url(#\(id))\""
        }
        // An alt text becomes the group's title, which is what screen readers
        // and browsers read for an SVG element.
        let title = el.altText.map { "<title>\(escape($0))</title>" } ?? ""
        let group = "<g\(attributes)>\(title)\(markup(el, index: index, defs: &defs))</g>"
        // A link wraps the element, so a browser follows it on a click —
        // one of the kinds a link is, never a script or a file.
        guard let link = Links.followable(el.link) else { return group }
        let href = escape(link)
        return "<a href=\"\(href)\" xlink:href=\"\(href)\">\(group)</a>"
    }

    /// feDropShadow, which every current renderer supports. stdDeviation is
    /// half the blur radius: SwiftUI's radius is the full extent of the blur,
    /// SVG's is the Gaussian sigma, and half is the conventional match.
    ///
    /// The filter region is the element's box in its own space, widened by
    /// the shadow's reach (three deviations, plus its offset, plus an
    /// arrowhead past a line's box) and never by less than 64 — not a share
    /// of the box, which for a flat line has no height at all (a filter with
    /// no room draws nothing), and for a heading is too little for its glow.
    static func shadowDef(id: String, shadow: Shadow, element el: Element) -> String {
        let ends: Double = el.type == .line ? arrowSize(el.thickness ?? 4) : 0
        let pad: Double = max(64, shadow.blur * 1.5 + max(abs(shadow.offsetX), abs(shadow.offsetY)) + ends)
        return "<filter id=\"\(id)\" filterUnits=\"userSpaceOnUse\" x=\"\(num(el.x - pad))\" y=\"\(num(el.y - pad))\" " +
        "width=\"\(num(el.w + 2 * pad))\" height=\"\(num(el.h + 2 * pad))\">" +
        "<feDropShadow dx=\"\(num(shadow.offsetX))\" dy=\"\(num(shadow.offsetY))\" " +
        "stdDeviation=\"\(num(shadow.blur / 2))\" flood-color=\"\(escape(shadow.color))\" " +
        "flood-opacity=\"\(num(shadow.opacity))\"/></filter>"
    }

    @MainActor
    private static func markup(_ el: Element, index: Int, defs: inout [String]) -> String {
        switch el.type {
        case .shape:
            // The shape without its words, which a shape sent as a picture
            // would otherwise bake in, and then the words as outlines.
            var bare = el
            bare.text = nil
            return shapeMarkup(bare, index: index, defs: &defs) + shapeWordsMarkup(el, index: index, defs: &defs)
        case .text: return textMarkup(el, index: index, defs: &defs)
        case .line: return lineMarkup(el)
        case .image, .sticker: return bitmapMarkup(el)
        }
    }

    @MainActor
    private static func shapeMarkup(_ el: Element, index: Int, defs: inout [String]) -> String {
        // A pattern or photo fill has no vector equivalent worth the bytes;
        // it ships as the same bitmap the canvas shows.
        if let kind = el.fill?.kind, kind == "pattern" || kind == "image" {
            return bitmapMarkup(el)
        }
        // SVG has no conic gradient either; an angular fill ships as pixels.
        if el.fill?.kind == "gradient", el.fill?.gradientKind == "angular" {
            return bitmapMarkup(el)
        }
        // At the element's own size, placed at its corner: the library draws
        // in a 100-unit box, and scaling that box onto the element in the
        // file would stretch the outline with it — a non-scaling stroke is no
        // cure, since it keeps its width on the screen rather than the page,
        // and a program that ignores it stretches the width by the box.
        let definition = ContentLibrary.shape(for: el)
        let d: String
        if definition.rectLike == true, let corners = el.corners, corners.count == 4,
           corners.contains(where: { $0 > 0 }), el.w > 0, el.h > 0 {
            // Per-corner radii: the exact path, at the element's size.
            let path = LibraryShape.roundedRect(CGRect(x: 0, y: 0, width: el.w, height: el.h), corners: corners)
            d = TextOutliner.svgPathData(path)
        } else if definition.rectLike == true, let radius = el.radius, radius > 0, el.w > 0, el.h > 0 {
            // Clamped once, to half the shorter side, as the canvas does: a
            // pill resized shorter keeps round ends rather than oval ones.
            d = roundedRectPath(width: el.w, height: el.h, radius: min(radius, el.w / 2, el.h / 2))
        } else {
            // The library's path, or a drawn one, read as the canvas reads
            // it (arcs as cubics) and taken across by each side.
            d = TextOutliner.svgPathData(SVGPath.scaledPath(definition.path, to: CGSize(width: el.w, height: el.h)))
        }

        let fill = el.fill ?? .solid("#8b5cf6")
        let paint: String
        if fill.kind == "gradient", let stops = fill.stops, !stops.isEmpty {
            let id = "grad\(index)"
            defs.append(gradientDef(id: id, paint: fill, left: 0, top: 0, width: el.w, height: el.h))
            paint = "url(#\(id))"
        } else if fill.kind == "none" {
            paint = "none"
        } else {
            paint = escape(fill.color ?? "#8b5cf6")
        }

        var stroke = ""
        if let color = el.stroke, let width = el.strokeWidth, width > 0 {
            stroke = " stroke=\"\(escape(color))\" stroke-width=\"\(num(width))\"" +
                     " stroke-linejoin=\"round\" stroke-linecap=\"round\""
        }

        return "<g transform=\"translate(\(num(el.x)) \(num(el.y)))\">" +
               "<path d=\"\(d)\" fill=\"\(paint)\"\(stroke)/></g>"
    }

    /// A `width` x `height` rectangle with round corners of `radius`.
    private static func roundedRectPath(width w: Double, height h: Double, radius r: Double) -> String {
        let arc = "A\(num(r)),\(num(r)) 0 0 1"
        return "M\(num(r)),0H\(num(w - r))\(arc) \(num(w)),\(num(r))" +
        "V\(num(h - r))\(arc) \(num(w - r)),\(num(h))" +
        "H\(num(r))\(arc) 0,\(num(h - r))" +
        "V\(num(r))\(arc) \(num(r)),0Z"
    }

    private static func textMarkup(_ el: Element, index: Int, defs: inout [String]) -> String {
        // Straight lines as the canvas sets them: at the size that fits a
        // fitted box, and from where a vertically aligned box starts them —
        // which is also where gradient letters are painted from.
        let top = min(max(textTop(el), 0), el.h)
        var drawn = el
        if el.fitText == true, !TextOutliner.followsAPath(el) {
            drawn.fontSize = FontLibrary.fittingFontSize(for: el)
        }
        guard let outlines = TextOutliner.inkedPaths(for: drawn) else { return "" }
        var shift = CGAffineTransform(translationX: 0, y: CGFloat(top))
        func data(_ outline: CGPath) -> String {
            TextOutliner.svgPathData(top > 0 ? (outline.copy(using: &shift) ?? outline) : outline)
        }
        let d = data(outlines.whole)
        guard !d.isEmpty else { return "" }
        let gradient = el.textFill?.kind == "gradient" && !(el.textFill?.stops ?? []).isEmpty
        if !gradient, outlines.parts.contains(where: { $0.color != nil }) {
            // Words in colours of their own: a path for each colour.
            let paths = outlines.parts.map { part in
                "<path d=\"\(data(part.path))\" fill=\"\(escape(part.color ?? el.color ?? "#1f2430"))\" fill-rule=\"nonzero\"/>"
            }
            return "<g transform=\"translate(\(num(el.x)) \(num(el.y)))\">" + paths.joined() + "</g>"
        }
        let paint: String
        if let fill = el.textFill, fill.kind == "gradient", let stops = fill.stops, !stops.isEmpty {
            // userSpaceOnUse over the text's part of the box rather than the
            // path's bounding box: the letters' own box is smaller than the
            // element and varies with the text, and the canvas paints the
            // gradient from where the words start down to the box's foot.
            let id = "textgrad\(index)"
            defs.append(gradientDef(id: id, paint: fill, left: 0, top: top, width: el.w,
                                    height: el.h - top, circular: true))
            paint = "url(#\(id))"
        } else {
            paint = escape(el.color ?? "#1f2430")
        }
        return "<g transform=\"translate(\(num(el.x)) \(num(el.y)))\">" +
               "<path d=\"\(d)\" fill=\"\(paint)\" fill-rule=\"nonzero\"/></g>"
    }

    /// A shape's words as glyph outlines, set in its text-safe box as the
    /// canvas sets them, and turned back inside the group's flip about that
    /// box, so they read the right way round in a flipped shape.
    private static func shapeWordsMarkup(_ el: Element, index: Int, defs: inout [String]) -> String {
        guard ShapeText.words(of: el) != nil else { return "" }
        let words = ShapeText.textElement(for: el)
        let outline = textMarkup(words, index: index, defs: &defs)
        guard !outline.isEmpty, el.flipH || el.flipV else { return outline }
        let cx = words.x + words.w / 2, cy = words.y + words.h / 2
        return "<g transform=\"translate(\(num(cx)) \(num(cy))) " +
               "scale(\(el.flipH ? -1 : 1) \(el.flipV ? -1 : 1)) " +
               "translate(\(num(-cx)) \(num(-cy)))\">\(outline)</g>"
    }

    /// How far past a text box's top its lines start, as the canvas sets
    /// them: vertically aligned in the box at the size it is drawn at. None
    /// for text round a curve, along a path or down a column.
    static func textTop(_ el: Element) -> Double {
        if TextOutliner.followsAPath(el) { return 0 }
        var drawn = el
        if el.fitText == true { drawn.fontSize = FontLibrary.fittingFontSize(for: el) }
        let slack: Double = max(0, el.h - FontLibrary.measuredHeight(for: drawn))
        switch el.vAlign {
        case "middle": return slack / 2
        case "bottom": return slack
        default: return 0
        }
    }

    /// A line's arrowhead length for its thickness, as LineElementView draws it.
    static func arrowSize(_ thickness: Double) -> Double { max(thickness * 3, 10) }

    /// A line as LineElementView draws it: round-capped, dashed 3:2 or dotted
    /// every 2.2 of its thickness, stopping short of an arrowhead whose tip
    /// is the line's end, and dots a thickness in from the ends.
    private static func lineMarkup(_ el: Element) -> String {
        let y = el.y + el.h / 2
        let t: Double = max(el.thickness ?? 4, 0.5)
        let arrow = arrowSize(t)
        let x1: Double = el.x + (el.startCap == "arrow" ? arrow * 0.9 : 0)
        let x2: Double = el.x + el.w - (el.endCap == "arrow" ? arrow * 0.9 : 0)
        var dash = ""
        switch el.dash {
        case "dashed": dash = " stroke-dasharray=\"\(num(t * 3)) \(num(t * 2))\""
        case "dotted": dash = " stroke-dasharray=\"0 \(num(t * 2.2))\""
        default: dash = ""
        }
        let stroke = escape(el.color ?? "#1f2430")
        var markup = "<line x1=\"\(num(x1))\" y1=\"\(num(y))\" " +
                     "x2=\"\(num(x2))\" y2=\"\(num(y))\" " +
                     "stroke=\"\(stroke)\" stroke-width=\"\(num(t))\" stroke-linecap=\"round\"\(dash)/>"
        markup += capMarkup(el.startCap, x: el.x, y: y, atStart: true, thickness: t, color: stroke)
        markup += capMarkup(el.endCap, x: el.x + el.w, y: y, atStart: false, thickness: t, color: stroke)
        return markup
    }

    private static func capMarkup(_ cap: String?, x: Double, y: Double, atStart: Bool,
                                  thickness t: Double, color: String) -> String {
        switch cap {
        case "arrow":
            let arrow = arrowSize(t)
            let back: Double = x + (atStart ? arrow : -arrow)
            return "<path d=\"M\(num(x)) \(num(y))" +
                   "L\(num(back)) \(num(y - arrow * 0.6))" +
                   "L\(num(back)) \(num(y + arrow * 0.6))Z\" fill=\"\(color)\"/>"
        case "dot":
            let cx: Double = x + (atStart ? t : -t)
            return "<circle cx=\"\(num(cx))\" cy=\"\(num(y))\" " +
                   "r=\"\(num(max(t * 1.4, 5)))\" fill=\"\(color)\"/>"
        default:
            return ""
        }
    }

    /// Images and stickers travel as bitmaps, rendered through the same views
    /// the canvas draws, so crop, filter, corner radius and emoji colour are
    /// whatever the editor showed rather than a second interpretation of it —
    /// with room round it for what the canvas draws past the box
    /// (`overflow`), or half a border would be cut away.
    @MainActor
    private static func bitmapMarkup(_ el: Element) -> String {
        guard el.w > 0, el.h > 0 else { return "" }
        var upright = el
        // The group already carries rotation, flip, opacity, the shadow and
        // the blend; baking them into the bitmap as well would apply each of
        // them twice — a shadow under the shadow.
        upright.rotation = 0
        upright.flipH = false
        upright.flipV = false
        upright.opacity = 1
        upright.shadow = nil
        upright.blendMode = nil
        upright.x = 0
        upright.y = 0

        let pad = overflow(el)
        let renderer = ImageRenderer(content: ElementView(element: upright).padding(CGFloat(pad)))
        renderer.scale = bitmapScale
        renderer.isOpaque = false
        guard let image = renderer.uiImage, let data = image.pngData() else { return "" }
        let uri = "data:image/png;base64," + data.base64EncodedString()
        return "<image x=\"\(num(el.x - pad))\" y=\"\(num(el.y - pad))\" " +
               "width=\"\(num(el.w + 2 * pad))\" height=\"\(num(el.h + 2 * pad))\" " +
               "preserveAspectRatio=\"none\" xlink:href=\"\(uri)\"/>"
    }

    /// How far past its box the canvas draws an element that goes out as a
    /// picture: half its border, which is centred on the frame, and for a
    /// shape or a photo in a shaped frame the 3.5% a few library outlines
    /// lean past their box by — as the Android twin pads the same pictures.
    static func overflow(_ el: Element) -> Double {
        guard el.type == .shape || el.type == .image else { return 0 }
        var border = 0.0
        if el.stroke != nil, let width = el.strokeWidth, width > 0 { border = width / 2 }
        let lean = (el.type == .shape || el.maskShapeId != nil) ? max(el.w, el.h) * 0.035 : 0
        return border + lean
    }

    // MARK: background

    @MainActor
    private static func backgroundMarkup(design: Design, page: Page, defs: inout [String]) -> String {
        let size = design.size(for: page)
        switch page.background {
        case .color(let hex):
            return "<rect width=\"\(num(size.width))\" height=\"\(num(size.height))\" " +
                   "fill=\"\(escape(hex))\"/>"
        case .gradient(let paint) where paint.gradientKind != "angular":
            defs.append(gradientDef(id: "bg", paint: paint, left: 0, top: 0,
                                    width: size.width, height: size.height))
            return "<rect width=\"\(num(size.width))\" height=\"\(num(size.height))\" " +
                   "fill=\"url(#bg)\"/>"
        // SVG has no conic gradient, so an angular background ships as the
        // pixels the canvas draws, as a picture background does.
        case .gradient, .image:
            let renderer = ImageRenderer(content: PageBackgroundView(design: design, page: page))
            renderer.scale = bitmapScale
            renderer.isOpaque = true
            guard let image = renderer.uiImage, let data = image.jpegData(compressionQuality: 0.9) else {
                return "<rect width=\"\(num(size.width))\" height=\"\(num(size.height))\" fill=\"#ffffff\"/>"
            }
            let uri = "data:image/jpeg;base64," + data.base64EncodedString()
            return "<image x=\"0\" y=\"0\" width=\"\(num(size.width))\" " +
                   "height=\"\(num(size.height))\" preserveAspectRatio=\"none\" " +
                   "xlink:href=\"\(uri)\"/>"
        }
    }

    /// A gradient as the canvas paints it over the box at (`left`, `top`),
    /// `width` x `height`, in the space of whatever it fills: linear along
    /// the CSS angle the model stores (0 degrees up, 90 to the right) from
    /// one side of the box to the other, as a SwiftUI LinearGradient's unit
    /// points land on the box — its bands square to that line on the page,
    /// not in a unit square stretched onto the box; radial from the centre
    /// out to the ellipse through the four sides, as EllipticalGradient
    /// draws it, or with `circular` — letters — to the circle through the
    /// longer side, where an angular fill is painted linear too.
    static func gradientDef(id: String, paint: Paint, left: Double, top: Double,
                            width: Double, height: Double, circular: Bool = false) -> String {
        let stops = (paint.stops ?? []).map {
            "<stop offset=\"\(num($0.offset))\" stop-color=\"\(escape($0.color))\"/>"
        }.joined()
        if paint.gradientKind == "radial" {
            let cx = num(left + width / 2), cy = num(top + height / 2)
            if circular {
                return "<radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(cx)\" cy=\"\(cy)\" " +
                       "r=\"\(num(max(width, height) / 2))\">\(stops)</radialGradient>"
            }
            return "<radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" cx=\"0\" cy=\"0\" r=\"1\" " +
                   "gradientTransform=\"translate(\(cx) \(cy)) scale(\(num(width / 2)) \(num(height / 2)))\">" +
                   "\(stops)</radialGradient>"
        }
        let pts = paint.unitPoints
        let x1: Double = left + width * Double(pts.start.x), y1: Double = top + height * Double(pts.start.y)
        let x2: Double = left + width * Double(pts.end.x), y2: Double = top + height * Double(pts.end.y)
        return "<linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" " +
               "x1=\"\(num(x1))\" y1=\"\(num(y1))\" x2=\"\(num(x2))\" y2=\"\(num(y2))\">\(stops)</linearGradient>"
    }

    // MARK: helpers

    /// Five decimals: enough that a coordinate on a 4000px page is exact to
    /// well under a pixel, without writing 1.0000000000000002 into the file.
    static func num(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 100_000).rounded() / 100_000
        if rounded == rounded.rounded() && abs(rounded) < 1e15 { return String(Int(rounded)) }
        return String(rounded)
    }

    /// Text made safe inside markup and inside a quoted attribute — and first
    /// rid of what XML cannot hold at all, escaped or not: control characters
    /// but tab and the line ends (a pasted soft line break is U+000B), and
    /// U+FFFE and U+FFFF. One of those anywhere and no reader opens the file.
    static func escape(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let v: UInt32 = scalar.value
            if v == 0x9 || v == 0xA || v == 0xD || (v >= 0x20 && v != 0xFFFE && v != 0xFFFF) {
                kept.append(scalar)
            }
        }
        return String(kept).replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// Just the page's background, for baking an image background into a bitmap
/// without the elements on top of it.
private struct PageBackgroundView: View {
    let design: Design
    let page: Page

    var body: some View {
        Group {
            if case .image(let src) = page.background, let ui = PhotoLibrary.resolve(src) {
                Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
            } else if case .gradient(let paint) = page.background {
                paint.fillView()
            } else {
                Color.white
            }
        }
        .frame(width: design.size(for: page).width, height: design.size(for: page).height)
        .clipped()
    }
}
