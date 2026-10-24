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

    /// What a test draws in place of this phone's own type engine and
    /// views, as the Android twin's tests hand its SvgWriter a Renderer:
    /// each text's letters as fixed path data, in its ink, and each
    /// element sent as a picture as fixed PNG bytes. With them the shared
    /// golden web page (website.html) compares byte for byte on both
    /// phones, the pictures' bytes aside; glyph outlines are each phone's
    /// own and never compared.
    struct StandIns {
        var letters: (Element) -> String
        var picture: (Element) -> Data
    }

    /// With `aria`, as a web page holds it (HTMLExporter): each element
    /// with alt text a group a screen reader reads as one picture, by its
    /// words — role="img" and aria-label.
    /// A link to a page goes to that page's section among `anchors` (by
    /// page id, "#page-N"); with none — an SVG of its own — nowhere.
    @MainActor
    static func svg(design: Design, page: Page, aria: Bool = false, anchors: [String: Int] = [:], moving: Bool = false) -> String {
        svg(design: design, page: page, aria: aria, standIns: nil, anchors: anchors, moving: moving)
    }

    /// `svg(design:page:aria:)`, drawn with a test's `standIns` when given.
    @MainActor
    /// With `moving`, for the web page: a graphic drawing itself on or
    /// twinkling plays as CSS (`moving(_:_:)`); anywhere else it is still,
    /// its drawing finished.
    static func svg(design: Design, page: Page, aria: Bool, standIns: StandIns?,
                    anchors: [String: Int] = [:], moving: Bool = false) -> String {
        var defs: [String] = []
        var body: [String] = []

        body.append(backgroundMarkup(design: design, page: page, defs: &defs))
        let number = (design.pages.firstIndex { $0.id == page.id } ?? 0) + 1
        let drawn = design.drawnElements(on: page)
        var parts: [(el: Element?, part: String)] = []
        for (index, el) in drawn.enumerated() {
            var resolved = el
            if ShapeText.carriesWords(el) {
                resolved.fillPageTokens(number: number, count: design.pages.count)
            }
            let group = elementGroup(resolved, index: index, aria: aria, standIns: standIns, anchors: anchors,
                                     defs: &defs)
            parts.append((el: el as Element?, part: moving ? Self.moving(group, el) : group))
        }
        // Groups, nested ones too, as <g> round their members (Groups.nested).
        body += Groups.nested(parts) { _, _, inner in "<g>" + inner.joined() + "</g>" }

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
    private static func elementGroup(_ el: Element, index: Int, aria: Bool = false, standIns: StandIns? = nil,
                                     anchors: [String: Int] = [:], defs: inout [String]) -> String {
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
        // A styled shadow is its own path, blurred, under the element in
        // its group; a drop shadow is a filter on the group. Text casts the
        // drop shadow whatever its style (ShadowShapes.cast).
        var cast = ""
        if let shadow = ShadowShapes.cast(el) {
            let id = "shadow\(index)"
            if let path = ShadowShapes.path(for: shadow, w: el.w, h: el.h) {
                cast = styledShadowMarkup(path, id: id, shadow: shadow, element: el, defs: &defs)
            } else if !ShadowShapes.isStyled(shadow) {
                defs.append(shadowDef(id: id, shadow: shadow, element: el))
                attributes += " filter=\"url(#\(id))\""
            }
        }
        if aria, let alt = el.altText?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty {
            attributes += " role=\"img\" aria-label=\"\(escape(alt))\""
        }
        // An alt text becomes the group's title, which is what screen readers
        // and browsers read for an SVG element.
        let title = el.altText.map { "<title>\(escape($0))</title>" } ?? ""
        var inner = markup(el, index: index, standIns: standIns, defs: &defs)
        // A cropped graphic (GraphicClip): its markup cut to the crop, in
        // its own box, inside the group's flip and turn.
        if let crop = GraphicClip.ownRect(el) {
            let id = "crop\(index)"
            defs.append("<clipPath id=\"\(id)\"><rect x=\"\(num(el.x + Double(crop.minX)))\" "
                        + "y=\"\(num(el.y + Double(crop.minY)))\" width=\"\(num(Double(crop.width)))\" "
                        + "height=\"\(num(Double(crop.height)))\"/></clipPath>")
            inner = "<g clip-path=\"url(#\(id))\">\(inner)</g>"
        }
        let group = "<g\(attributes)>\(title)\(cast)\(inner)</g>"
        let words = wordLinksMarkup(el, transforms: transforms, anchors: anchors)
        // A link wraps the element, so a browser follows it on a click —
        // one of the kinds a link is, never a script or a file.
        guard let link = href(el.link, anchors: anchors) else { return group + words }
        let escaped = escape(link)
        return "<a href=\"\(escaped)\" xlink:href=\"\(escaped)\">\(group)</a>" + words
    }

    /// Where a link goes: an address (Links.followable), or — on the web
    /// page, a page among those it holds (`anchors`, by page id) — that
    /// page's section, "#page-N". Nil for anything else, a dangling page
    /// link among them.
    static func href(_ link: String?, anchors: [String: Int]) -> String? {
        if let url = Links.followable(link) { return url }
        guard let id = Links.pageId(link), let n = anchors[id] else { return nil }
        return "#page-\(n)"
    }

    /// Linked words (WordLinks): each word of them a clear rectangle in an
    /// <a>, laid over the element in its turn and flip — beside its group,
    /// not inside its own link, which an <a> cannot hold — so a browser
    /// follows the words' link over them and the element's elsewhere.
    private static func wordLinksMarkup(_ el: Element, transforms: [String], anchors pages: [String: Int]) -> String {
        let anchors = WordLinks.rects(for: el).compactMap { entry -> String? in
            guard let url = href(entry.url, anchors: pages) else { return nil }
            let escaped = escape(url)
            let r = entry.rect
            let box = "x=\"\(num(el.x + Double(r.minX)))\" y=\"\(num(el.y + Double(r.minY)))\" " +
                "width=\"\(num(Double(r.width)))\" height=\"\(num(Double(r.height)))\""
            return "<a href=\"\(escaped)\" xlink:href=\"\(escaped)\"><rect \(box) fill=\"#000000\" fill-opacity=\"0\"/></a>"
        }
        guard !anchors.isEmpty else { return "" }
        let transform = transforms.isEmpty ? "" : " transform=\"\(transforms.joined(separator: " "))\""
        return "<g\(transform)>" + anchors.joined() + "</g>"
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
        let ends: Double = el.type == .line ? arrowSize(el.thickness ?? 4) + LineRoutes.bow(el) : 0
        let pad: Double = max(64, shadow.blur * 1.5 + max(abs(shadow.offsetX), abs(shadow.offsetY)) + ends)
        return "<filter id=\"\(id)\" filterUnits=\"userSpaceOnUse\" x=\"\(num(el.x - pad))\" y=\"\(num(el.y - pad))\" " +
        "width=\"\(num(el.w + 2 * pad))\" height=\"\(num(el.h + 2 * pad))\">" +
        "<feDropShadow dx=\"\(num(shadow.offsetX))\" dy=\"\(num(shadow.offsetY))\" " +
        "stdDeviation=\"\(num(shadow.blur / 2))\" flood-color=\"\(escape(shadow.color))\" " +
        "flood-opacity=\"\(num(shadow.opacity))\"/></filter>"
    }

    /// A styled shadow (ShadowShapes) as a <path> in the shadow's colour and
    /// opacity at the element's place and the shadow's offset, blurred by
    /// an feGaussianBlur filter of its own — none for a backdrop, which is
    /// not blurred — with room round the element for its reach.
    static func styledShadowMarkup(_ path: CGPath, id: String, shadow: Shadow, element el: Element,
                                   defs: inout [String]) -> String {
        let blur = ShadowShapes.blur(of: shadow)
        var filter = ""
        if blur > 0 {
            let pad: Double = max(64, blur * 1.5 + max(abs(shadow.offsetX), abs(shadow.offsetY))
                                      + ShadowShapes.reach(of: shadow, w: el.w, h: el.h))
            defs.append("<filter id=\"\(id)\" filterUnits=\"userSpaceOnUse\" x=\"\(num(el.x - pad))\" " +
                        "y=\"\(num(el.y - pad))\" width=\"\(num(el.w + 2 * pad))\" height=\"\(num(el.h + 2 * pad))\">" +
                        "<feGaussianBlur stdDeviation=\"\(num(blur / 2))\"/></filter>")
            filter = " filter=\"url(#\(id))\""
        }
        let d = pathData(path, dx: el.x + shadow.offsetX, dy: el.y + shadow.offsetY)
        return "<path d=\"\(d)\" fill=\"\(escape(shadow.color))\" fill-opacity=\"\(num(shadow.opacity))\"\(filter)/>"
    }

    /// `path` as SVG path data, moved by `dx`, `dy`.
    static func pathData(_ path: CGPath, dx: Double, dy: Double) -> String {
        var out = ""
        func point(_ p: CGPoint) -> String { "\(num(Double(p.x) + dx)) \(num(Double(p.y) + dy))" }
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: out += "M\(point(points[0]))"
            case .addLineToPoint: out += "L\(point(points[0]))"
            case .addQuadCurveToPoint: out += "Q\(point(points[0])) \(point(points[1]))"
            case .addCurveToPoint: out += "C\(point(points[0])) \(point(points[1])) \(point(points[2]))"
            case .closeSubpath: out += "Z"
            @unknown default: break
            }
        }
        return out
    }

    @MainActor
    private static func markup(_ el: Element, index: Int, standIns: StandIns? = nil, defs: inout [String]) -> String {
        switch el.type {
        case .shape:
            // The shape without its words, which a shape sent as a picture
            // would otherwise bake in, and then the words as outlines.
            var bare = el
            bare.text = nil
            let shape = shapeMarkup(bare, index: index, defs: &defs)
            return shape + shapeWordsMarkup(el, index: index, standIns: standIns, defs: &defs)
        case .text: return textMarkup(el, index: index, standIns: standIns, defs: &defs)
        case .line: return lineMarkup(el)
        case .image:
            if let code = CodeGenerator.vector(el) {
                return codeMarkup(el, code) + logoMarkup(el, code, standIns: standIns)
            }
            if let code = Barcodes.vector(el) {
                // Its words outlined as any text's are.
                let words = Barcodes.captionElement(el, code, onPage: false).map { caption -> String in
                    var placed = caption
                    placed.x += el.x
                    placed.y += el.y
                    return textMarkup(placed, index: index, standIns: standIns, defs: &defs)
                } ?? ""
                return barcodeMarkup(el, code) + words
            }
            return bitmapMarkup(el, standIns: standIns)
        case .sticker: return bitmapMarkup(el, standIns: standIns)
        }
    }

    /// A QR code as rectangles (CodeGenerator.vector): its background,
    /// unless it has none, then one path of its dark modules in its colour,
    /// each run along a row a rectangle, at the edges' own places so rows
    /// meet with no seam — as the Android twin writes it.
    static func codeMarkup(_ el: Element, _ code: CodeGenerator.Vector) -> String {
        func rect(_ r: CGRect) -> String {
            "M\(num(el.x + Double(r.minX))) \(num(el.y + Double(r.minY)))H\(num(el.x + Double(r.maxX)))" +
                "V\(num(el.y + Double(r.maxY)))H\(num(el.x + Double(r.minX)))Z"
        }
        var out = ""
        if let paper = code.style.background, let box = code.background {
            out += "<path d=\"\(rect(box))\" fill=\"\(escape(paper))\"/>"
        }
        if !code.modules.isEmpty {
            let d = code.modules.map(rect).joined()
            out += "<path d=\"\(d)\" fill=\"\(escape(code.style.color))\" shape-rendering=\"crispEdges\"/>"
        }
        // A styled code's dots and eyes, one outline even-odd so the eyes'
        // rings stay open (CodeGenerator.outline).
        if !code.marks.isEmpty {
            let d = CodeGenerator.svgData(code.marks)
            out += "<path transform=\"translate(\(num(el.x)) \(num(el.y)))\" d=\"\(d)\" fill-rule=\"evenodd\" " +
                "fill=\"\(escape(code.style.color))\"/>"
        }
        if let pad = code.logoPad {
            out += "<path d=\"\(rect(pad))\" fill=\"\(escape(code.style.background ?? CodeGenerator.defaultBackground))\"/>"
        }
        return out
    }

    /// A code's logo over its pad, as the picture it is.
    @MainActor
    private static func logoMarkup(_ el: Element, _ code: CodeGenerator.Vector, standIns: StandIns? = nil) -> String {
        guard let src = code.style.logo, let box = CodeGenerator.logoBox(code.logoPad) else { return "" }
        var logo = Element.image(src, w: box.width, h: box.height)
        logo.x = el.x + box.minX
        logo.y = el.y + box.minY
        logo.radius = 0
        logo.cropFit = true
        return bitmapMarkup(logo, standIns: standIns)
    }

    /// A barcode as rectangles (Barcodes.vector): its background, unless it
    /// has none, then one path of its bars in its colour — as the Android
    /// twin writes it; its words follow, outlined.
    static func barcodeMarkup(_ el: Element, _ code: Barcodes.Drawing) -> String {
        func rect(_ r: CGRect) -> String {
            "M\(num(el.x + Double(r.minX))) \(num(el.y + Double(r.minY)))H\(num(el.x + Double(r.maxX)))" +
                "V\(num(el.y + Double(r.maxY)))H\(num(el.x + Double(r.minX)))Z"
        }
        var out = ""
        if let paper = code.style.background, let box = code.background {
            out += "<path d=\"\(rect(box))\" fill=\"\(escape(paper))\"/>"
        }
        if !code.bars.isEmpty {
            let d = code.bars.map(rect).joined()
            out += "<path d=\"\(d)\" fill=\"\(escape(code.style.color))\" shape-rendering=\"crispEdges\"/>"
        }
        return out
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
                     " stroke-linejoin=\"round\"" + borderDash(el.dash, width: width)
        }
        // Even-odd only when asked for: nonzero is SVG's own default.
        let rule = el.fillRule == "evenodd" ? " fill-rule=\"evenodd\"" : ""

        return "<g transform=\"translate(\(num(el.x)) \(num(el.y)))\">" +
               "<path d=\"\(d)\" fill=\"\(paint)\"\(rule)\(stroke)/></g>"
    }

    /// A border's ends and, when it is dashed or dotted, its pattern and
    /// where the pattern starts, as BorderDash measures them.
    static func borderDash(_ dash: String?, width: Double) -> String {
        let cap = " stroke-linecap=\"\(BorderDash.roundCaps(dash) ? "round" : "butt")\""
        guard let intervals = BorderDash.intervals(dash, width: width) else { return cap }
        let array = intervals.map(num).joined(separator: " ")
        return cap + " stroke-dasharray=\"\(array)\" stroke-dashoffset=\"\(num(BorderDash.phase(dash, width: width)))\""
    }

    /// A `width` x `height` rectangle with round corners of `radius`.
    private static func roundedRectPath(width w: Double, height h: Double, radius r: Double) -> String {
        let arc = "A\(num(r)),\(num(r)) 0 0 1"
        return "M\(num(r)),0H\(num(w - r))\(arc) \(num(w)),\(num(r))" +
        "V\(num(h - r))\(arc) \(num(w - r)),\(num(h))" +
        "H\(num(r))\(arc) 0,\(num(h - r))" +
        "V\(num(r))\(arc) \(num(r)),0Z"
    }

    private static func textMarkup(_ el: Element, index: Int, standIns: StandIns? = nil, defs: inout [String]) -> String {
        // Straight lines as the canvas sets them: at the size that fits a
        // fitted box, and from where a vertically aligned box starts them —
        // which is also where gradient letters are painted from.
        let top = min(max(textTop(el), 0), el.h)
        var drawn = el
        if el.fitText == true, !TextOutliner.followsAPath(el) {
            drawn.fontSize = FontLibrary.fittingFontSize(for: el)
        }
        // A test's stand-in letters, else this phone's own glyphs.
        let outlines = standIns == nil ? TextOutliner.inkedPaths(for: drawn) : nil
        guard standIns != nil || outlines != nil else { return "" }
        var shift = CGAffineTransform(translationX: 0, y: CGFloat(top))
        func data(_ outline: CGPath) -> String {
            TextOutliner.svgPathData(top > 0 ? (outline.copy(using: &shift) ?? outline) : outline)
        }
        let d = standIns?.letters(drawn) ?? outlines.map { data($0.whole) } ?? ""
        guard !d.isEmpty else { return "" }
        let gradient = el.textFill?.kind == "gradient" && !(el.textFill?.stops ?? []).isEmpty
        // Marks behind chosen words, before the letters, so under them.
        let marks = standIns == nil ? highlightMarkup(drawn, top: top) : ""
        // Outline's stroke as a pass of its own under every fill, as the
        // canvas strokes all the letters before it fills any.
        let stroke = outlinedStroke(drawn)
        let ring = stroke.isEmpty ? "" : "<path d=\"\(d)\" fill=\"none\"\(stroke)/>"
        // Letters full of a photo: their outlines as a clipPath, and the
        // picture inside it where PhotoFills.window puts it — where the
        // effect lets the photo through; else the letters in its average
        // colour (ink). Word colours are not drawn: the photo colours
        // every word, as a gradient does. The Android twin's photoText.
        if let fill = el.textFill, fill.isPhoto, TextEffect.from(el.effect).takesPhoto, let src = fill.src,
           let photo = PhotoFills.stored(src) {
            let window = PhotoFills.window(imageW: Double(photo.size.width), imageH: Double(photo.size.height),
                                           boxW: el.w, boxH: el.h, paint: fill)
            let clip = "<clipPath id=\"textclip\(index)\"><path d=\"\(d)\"/></clipPath>"
            let place = "x=\"\(num(window.minX))\" y=\"\(num(window.minY))\" width=\"\(num(window.width))\" height=\"\(num(window.height))\""
            let picture = "<image clip-path=\"url(#textclip\(index))\" \(place) preserveAspectRatio=\"none\" " +
                "xlink:href=\"data:image/\(photo.type);base64,\(photo.data.base64EncodedString())\"/>"
            return "<g transform=\"translate(\(num(el.x)) \(num(el.y)))\">" + marks + ring + clip + picture + "</g>"
        }
        let ink = textInk(el)
        if !gradient, el.textFill?.isPhoto != true, let parts = outlines?.parts, parts.contains(where: { $0.color != nil }) {
            // Words in colours of their own: a path for each colour.
            let paths = parts.map { part in
                "<path d=\"\(data(part.path))\" fill=\"\(escape(part.color ?? ink))\" fill-rule=\"nonzero\"/>"
            }
            return "<g transform=\"translate(\(num(el.x)) \(num(el.y)))\">" + marks + ring + paths.joined() + "</g>"
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
            paint = escape(ink)
        }
        return "<g transform=\"translate(\(num(el.x)) \(num(el.y)))\">" + marks + ring +
               "<path d=\"\(d)\" fill=\"\(paint)\" fill-rule=\"nonzero\"/></g>"
    }

    /// The marks behind highlighted words (TextHighlights), as rounded
    /// rects in the box's space, a see-through marker as a fill-opacity.
    static func highlightMarkup(_ drawn: Element, top: Double) -> String {
        guard !TextOutliner.followsAPath(drawn) else { return "" }
        return TextHighlights.rects(for: drawn, width: drawn.w, top: top).map { mark in
            let paint = TextHighlights.split(mark.color)
            let opacity = paint.alpha < 1 ? " fill-opacity=\"\(num(paint.alpha))\"" : ""
            let corner = min(mark.radius, mark.w / 2, mark.h / 2)
            return "<rect x=\"\(num(mark.x))\" y=\"\(num(mark.y))\" width=\"\(num(mark.w))\" " +
                "height=\"\(num(mark.h))\" rx=\"\(num(corner))\" fill=\"\(escape(paint.color))\"\(opacity)/>"
        }.joined()
    }

    /// The ink text is written in: its colour, or for letters full of a
    /// photo that cannot show it, the photo's average.
    static func textInk(_ el: Element) -> String {
        if let fill = el.textFill, fill.isPhoto, let src = fill.src, let average = PhotoPalette.averageColour(src) {
            return average
        }
        return el.color ?? "#1f2430"
    }

    /// Outline's stroke round the letters as path attributes, for a pass
    /// drawn before the fill so the letters keep their full width; nothing
    /// for any other effect, or at no thickness.
    static func outlinedStroke(_ el: Element) -> String {
        guard TextEffect.from(el.effect) == .outlined else { return "" }
        let fx = TextEffect.resolve(el.effect, fontSize: el.fontSize ?? 42, ink: el.color ?? "#1f2430")
        guard fx.stroke > 0 else { return "" }
        return " stroke=\"\(escape(fx.color))\" stroke-width=\"\(num(fx.stroke))\"" +
            " stroke-linejoin=\"round\""
    }

    /// A shape's words as glyph outlines, set in its text-safe box as the
    /// canvas sets them, and turned back inside the group's flip about that
    /// box, so they read the right way round in a flipped shape.
    private static func shapeWordsMarkup(_ el: Element, index: Int, standIns: StandIns? = nil,
                                         defs: inout [String]) -> String {
        guard ShapeText.words(of: el) != nil else { return "" }
        let words = ShapeText.textElement(for: el)
        let outline = textMarkup(words, index: index, standIns: standIns, defs: &defs)
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
        if LineRoutes.keepsLevel(el) { return routeMarkup(el) }
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

    /// An elbowed or curved line (LineRoutes) as one path along its route
    /// — its corners round, a curve a quadratic — dashed and capped as a
    /// straight one is, each end's arrowhead or dot pointing along its
    /// segment. As the Android twin writes it.
    private static func routeMarkup(_ el: Element) -> String {
        let t: Double = max(el.thickness ?? 4, 0.5)
        let route = LineRoutes.route(el)
        let points = LineRoutes.trimmed(route, startBack: LineRoutes.strokeBack(el, cap: el.startCap),
                                        endBack: LineRoutes.strokeBack(el, cap: el.endCap))
        func at(_ p: CGPoint) -> String { "\(num(el.x + Double(p.x))) \(num(el.y + Double(p.y)))" }
        var d = "M\(at(points[0]))"
        if route.curved && points.count == 3 {
            d += "Q\(at(points[1])) \(at(points[2]))"
        } else {
            for p in points.dropFirst() { d += "L\(at(p))" }
        }
        var dash = ""
        switch el.dash {
        case "dashed": dash = " stroke-dasharray=\"\(num(t * 3)) \(num(t * 2))\""
        case "dotted": dash = " stroke-dasharray=\"0 \(num(t * 2.2))\""
        default: dash = ""
        }
        let stroke = escape(el.color ?? "#1f2430")
        func cap(_ kind: String?, tip: CGPoint, angle: Double) -> String {
            switch kind {
            case "arrow":
                let head = LineRoutes.arrowhead(tip: tip, angle: angle, size: LineRoutes.arrowSize(t))
                return "<path d=\"M\(at(head[0]))L\(at(head[1]))L\(at(head[2]))Z\" fill=\"\(stroke)\"/>"
            case "dot":
                let c = LineRoutes.dotCentre(tip: tip, angle: angle, t: t)
                return "<circle cx=\"\(num(el.x + Double(c.x)))\" cy=\"\(num(el.y + Double(c.y)))\" " +
                    "r=\"\(num(LineRoutes.dotRadius(t)))\" fill=\"\(stroke)\"/>"
            default:
                return ""
            }
        }
        let path = "<path d=\"\(d)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(num(t))\" " +
            "stroke-linecap=\"round\" stroke-linejoin=\"round\"\(dash)/>"
        return path + cap(el.startCap, tip: route.start, angle: route.startAngle)
            + cap(el.endCap, tip: route.end, angle: route.endAngle)
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
    private static func bitmapMarkup(_ el: Element, standIns: StandIns? = nil) -> String {
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
        let png: Data?
        if let standIns {
            png = standIns.picture(el)
        } else {
            let renderer = ImageRenderer(content: ElementView(element: upright).padding(CGFloat(pad)))
            renderer.scale = bitmapScale
            renderer.isOpaque = false
            png = renderer.uiImage?.pngData()
        }
        guard let data = png else { return "" }
        let uri = "data:image/png;base64," + data.base64EncodedString()
        return "<image x=\"\(num(el.x - pad))\" y=\"\(num(el.y - pad))\" " +
               "width=\"\(num(el.w + 2 * pad))\" height=\"\(num(el.h + 2 * pad))\" " +
               "preserveAspectRatio=\"none\" xlink:href=\"\(uri)\"/>"
    }

    /// How far past its box the canvas draws an element that goes out as a
    /// picture: half its border, which is centred on the frame, for a
    /// shape or a photo in a shaped frame the 3.5% a few library outlines
    /// lean past their box by, and a photo's outline or glow — as the
    /// Android twin pads the same pictures.
    static func overflow(_ el: Element) -> Double {
        guard el.type == .shape || el.type == .image else { return 0 }
        var border = 0.0
        if el.stroke != nil, let width = el.strokeWidth, width > 0 { border = width / 2 }
        let lean = (el.type == .shape || el.maskShapeId != nil) ? max(el.w, el.h) * 0.035 : 0
        let edge = el.type == .image ? PhotoEffects.reach(el.edge) : 0
        return border + lean + edge
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
    /// An element's markup that draws itself on or twinkles on a web page:
    /// a draw-on revealed from its left over its time, after its delay
    /// (cv-draw), a twinkle pulsing round from its delay (cv-twinkle); any
    /// other as it is. The keyframes are HTMLExporter.motionCSS.
    static func moving(_ group: String, _ el: Element) -> String {
        guard let anim = el.animation else { return group }
        let delay = num(anim.delay)
        switch anim.kind {
        case ElementAnimation.draw:
            return "<g style=\"animation:cv-draw \(num(max(anim.duration, 0.01)))s linear \(delay)s both\">" + group + "</g>"
        case ElementAnimation.twinkle:
            let style = "transform-box:fill-box;transform-origin:center;"
                + "animation:cv-twinkle \(num(ElementAnimation.loopPeriod))s ease-in-out \(delay)s infinite"
            return "<g style=\"" + style + "\">" + group + "</g>"
        default:
            return group
        }
    }

    /// Whether `page` has a graphic that moves on a web page.
    static func moves(_ design: Design, page: Page) -> Bool {
        design.drawnElements(on: page).contains {
            $0.animation?.kind == ElementAnimation.draw || $0.animation?.kind == ElementAnimation.twinkle
        }
    }

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
/// without the elements on top of it — here and in a PowerPoint slide.
struct PageBackgroundView: View {
    let design: Design
    let page: Page

    var body: some View {
        Group {
            if case .color = page.background {
                Color.white
            } else {
                // A photo laid over the design's bleed too, so the trim
                // shows the crop the canvas and the PDFs show.
                PageBackgroundFill(background: page.background, size: design.size(for: page),
                                   cover: Bleed.of(design))
            }
        }
        .frame(width: design.size(for: page).width, height: design.size(for: page).height)
        .clipped()
    }
}
