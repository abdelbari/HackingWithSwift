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
//                      substitutes — which is to say, not the design
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
        for (index, el) in page.elements.enumerated() {
            body.append(elementGroup(el, index: index, defs: &defs))
        }

        let header = "<svg xmlns=\"http://www.w3.org/2000/svg\" " +
            "xmlns:xlink=\"http://www.w3.org/1999/xlink\" " +
            "width=\"\(num(design.width))\" height=\"\(num(design.height))\" " +
            "viewBox=\"0 0 \(num(design.width)) \(num(design.height))\">"
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
            defs.append(shadowDef(id: id, shadow: shadow))
            attributes += " filter=\"url(#\(id))\""
        }
        return "<g\(attributes)>\(markup(el, index: index, defs: &defs))</g>"
    }

    /// feDropShadow, which every current renderer supports. stdDeviation is
    /// half the blur radius: SwiftUI's radius is the full extent of the blur,
    /// SVG's is the Gaussian sigma, and half is the conventional match.
    ///
    /// The filter region is widened well past the element's box, because the
    /// default 10% margin clips a large soft shadow at a hard straight edge.
    private static func shadowDef(id: String, shadow: Shadow) -> String {
        "<filter id=\"\(id)\" x=\"-50%\" y=\"-50%\" width=\"200%\" height=\"200%\">" +
        "<feDropShadow dx=\"\(num(shadow.offsetX))\" dy=\"\(num(shadow.offsetY))\" " +
        "stdDeviation=\"\(num(shadow.blur / 2))\" flood-color=\"\(escape(shadow.color))\" " +
        "flood-opacity=\"\(num(shadow.opacity))\"/></filter>"
    }

    @MainActor
    private static func markup(_ el: Element, index: Int, defs: inout [String]) -> String {
        switch el.type {
        case .shape: return shapeMarkup(el, index: index, defs: &defs)
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
        let definition = ContentLibrary.shape(el.shapeId)
        var d = definition.path
        if definition.rectLike == true, let radius = el.radius, radius > 0, el.w > 0, el.h > 0 {
            // The library path is drawn in a 100x100 box and scaled onto the
            // element, so the corner radius has to be expressed in that box —
            // and separately per axis, or a wide box gets round corners on one
            // side and oval ones on the other.
            let rx = min(radius, el.w / 2) * (100 / el.w)
            let ry = min(radius, el.h / 2) * (100 / el.h)
            d = roundedRectPath(rx: rx, ry: ry)
        }

        let fill = el.fill ?? .solid("#8b5cf6")
        let paint: String
        if fill.kind == "gradient", let stops = fill.stops, !stops.isEmpty {
            let id = "grad\(index)"
            defs.append(gradientDef(id: id, paint: fill, width: el.w, height: el.h))
            paint = "url(#\(id))"
        } else {
            paint = escape(fill.color ?? "#8b5cf6")
        }

        var stroke = ""
        if let color = el.stroke, let width = el.strokeWidth, width > 0 {
            // Non-scaling, because the group below scales a 100-unit box onto
            // the element: a plain stroke-width would come out stretched by
            // the same factor, and differently on each axis.
            stroke = " stroke=\"\(escape(color))\" stroke-width=\"\(num(width))\"" +
                     " vector-effect=\"non-scaling-stroke\" stroke-linejoin=\"round\""
        }

        let sx = el.w / 100, sy = el.h / 100
        return "<g transform=\"translate(\(num(el.x)) \(num(el.y))) scale(\(num(sx)) \(num(sy)))\">" +
               "<path d=\"\(d)\" fill=\"\(paint)\"\(stroke)/></g>"
    }

    private static func roundedRectPath(rx: Double, ry: Double) -> String {
        "M\(num(rx)),0H\(num(100 - rx))A\(num(rx)),\(num(ry)) 0 0 1 100,\(num(ry))" +
        "V\(num(100 - ry))A\(num(rx)),\(num(ry)) 0 0 1 \(num(100 - rx)),100" +
        "H\(num(rx))A\(num(rx)),\(num(ry)) 0 0 1 0,\(num(100 - ry))" +
        "V\(num(ry))A\(num(rx)),\(num(ry)) 0 0 1 \(num(rx)),0Z"
    }

    private static func textMarkup(_ el: Element, index: Int, defs: inout [String]) -> String {
        guard let path = TextOutliner.path(for: el) else { return "" }
        let d = TextOutliner.svgPathData(path)
        guard !d.isEmpty else { return "" }
        let paint: String
        if let fill = el.textFill, fill.kind == "gradient", let stops = fill.stops, !stops.isEmpty {
            // userSpaceOnUse over the element's box rather than the path's
            // bounding box: the letters' own box is shorter than the element
            // and varies with the text, and the canvas paints the gradient
            // across the element.
            let id = "textgrad\(index)"
            defs.append(gradientDef(id: id, paint: fill, width: el.w, height: el.h))
            paint = "url(#\(id))"
        } else {
            paint = escape(el.color ?? "#1f2430")
        }
        return "<g transform=\"translate(\(num(el.x)) \(num(el.y)))\">" +
               "<path d=\"\(d)\" fill=\"\(paint)\" fill-rule=\"nonzero\"/></g>"
    }

    private static func lineMarkup(_ el: Element) -> String {
        let y = el.y + el.h / 2
        let width = max(el.thickness ?? 4, 0.5)
        var dash = ""
        switch el.dash {
        case "dashed": dash = " stroke-dasharray=\"\(num(width * 3)) \(num(width * 2))\""
        case "dotted": dash = " stroke-dasharray=\"0 \(num(width * 2))\" stroke-linecap=\"round\""
        default: dash = " stroke-linecap=\"round\""
        }
        let stroke = escape(el.color ?? "#1f2430")
        var markup = "<line x1=\"\(num(el.x))\" y1=\"\(num(y))\" " +
                     "x2=\"\(num(el.x + el.w))\" y2=\"\(num(y))\" " +
                     "stroke=\"\(stroke)\" stroke-width=\"\(num(width))\"\(dash)/>"
        markup += capMarkup(el.startCap, at: CGPoint(x: el.x, y: y), pointingLeft: true,
                            width: width, color: stroke)
        markup += capMarkup(el.endCap, at: CGPoint(x: el.x + el.w, y: y), pointingLeft: false,
                            width: width, color: stroke)
        return markup
    }

    private static func capMarkup(_ cap: String?, at point: CGPoint, pointingLeft: Bool,
                                  width: Double, color: String) -> String {
        switch cap {
        case "arrow":
            let size = width * 3.2
            let tipX = point.x + (pointingLeft ? -size : size)
            return "<path d=\"M\(num(tipX)) \(num(point.y))" +
                   "L\(num(point.x)) \(num(point.y - size * 0.55))" +
                   "L\(num(point.x)) \(num(point.y + size * 0.55))Z\" fill=\"\(color)\"/>"
        case "dot":
            return "<circle cx=\"\(num(point.x))\" cy=\"\(num(point.y))\" " +
                   "r=\"\(num(width * 1.4))\" fill=\"\(color)\"/>"
        default:
            return ""
        }
    }

    /// Images and stickers travel as bitmaps, rendered through the same views
    /// the canvas draws, so crop, filter, corner radius and emoji colour are
    /// whatever the editor showed rather than a second interpretation of it.
    @MainActor
    private static func bitmapMarkup(_ el: Element) -> String {
        guard el.w > 0, el.h > 0 else { return "" }
        var upright = el
        // The group already carries rotation, flip and opacity; baking them
        // into the bitmap as well would apply each of them twice.
        upright.rotation = 0
        upright.flipH = false
        upright.flipV = false
        upright.opacity = 1
        upright.x = 0
        upright.y = 0

        let renderer = ImageRenderer(content: ElementView(element: upright))
        renderer.scale = bitmapScale
        renderer.isOpaque = false
        guard let image = renderer.uiImage, let data = image.pngData() else { return "" }
        let uri = "data:image/png;base64," + data.base64EncodedString()
        return "<image x=\"\(num(el.x))\" y=\"\(num(el.y))\" " +
               "width=\"\(num(el.w))\" height=\"\(num(el.h))\" " +
               "preserveAspectRatio=\"none\" xlink:href=\"\(uri)\"/>"
    }

    // MARK: background

    @MainActor
    private static func backgroundMarkup(design: Design, page: Page, defs: inout [String]) -> String {
        switch page.background {
        case .color(let hex):
            return "<rect width=\"\(num(design.width))\" height=\"\(num(design.height))\" " +
                   "fill=\"\(escape(hex))\"/>"
        case .gradient(let paint):
            defs.append(gradientDef(id: "bg", paint: paint,
                                    width: design.width, height: design.height))
            return "<rect width=\"\(num(design.width))\" height=\"\(num(design.height))\" " +
                   "fill=\"url(#bg)\"/>"
        case .image:
            let renderer = ImageRenderer(content: PageBackgroundView(design: design, page: page))
            renderer.scale = bitmapScale
            renderer.isOpaque = true
            guard let image = renderer.uiImage, let data = image.jpegData(compressionQuality: 0.9) else {
                return "<rect width=\"\(num(design.width))\" height=\"\(num(design.height))\" fill=\"#ffffff\"/>"
            }
            let uri = "data:image/jpeg;base64," + data.base64EncodedString()
            return "<image x=\"0\" y=\"0\" width=\"\(num(design.width))\" " +
                   "height=\"\(num(design.height))\" preserveAspectRatio=\"none\" " +
                   "xlink:href=\"\(uri)\"/>"
        }
    }

    /// A linear gradient in objectBoundingBox units, matching the CSS angle
    /// convention the model stores (0 degrees points up, 90 to the right).
    ///
    /// Bounding-box units stretch with the box, so the direction vector has to
    /// be divided by the box's own dimensions or a gradient on a wide element
    /// comes out at the wrong angle.
    private static func gradientDef(id: String, paint: Paint,
                                    width: Double, height: Double) -> String {
        let radians = ((paint.angle ?? 0) - 90) * .pi / 180
        let dx = cos(radians), dy = sin(radians)
        let length = abs(width * dx) + abs(height * dy)
        let ux = width > 0 ? (dx * length) / (2 * width) : 0
        let uy = height > 0 ? (dy * length) / (2 * height) : 0
        let stops = (paint.stops ?? []).map {
            "<stop offset=\"\(num($0.offset))\" stop-color=\"\(escape($0.color))\"/>"
        }.joined()
        return "<linearGradient id=\"\(id)\" x1=\"\(num(0.5 - ux))\" y1=\"\(num(0.5 - uy))\" " +
               "x2=\"\(num(0.5 + ux))\" y2=\"\(num(0.5 + uy))\">\(stops)</linearGradient>"
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

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
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
            } else {
                Color.white
            }
        }
        .frame(width: design.width, height: design.height)
        .clipped()
    }
}
