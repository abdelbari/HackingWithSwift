// Element model: one struct for all five element kinds (shape, text, image,
// sticker, line) with optional per-kind fields — mirroring the web JSON so
// templates decode directly. Every field the decoder might miss gets a
// sensible default.

import Foundation
import CoreGraphics

enum ElementType: String, Codable {
    case shape, text, image, sticker, line
}

struct TextEffectSpec: Codable, Equatable, Hashable {
    var type: String = "none"     // none|shadow|lift|outline|splice|neon|glitch|highlight
}

struct Element: Codable, Equatable, Identifiable {
    var id: String = UID.make()
    var type: ElementType = .shape
    var x: Double = 0
    var y: Double = 0
    var w: Double = 100
    var h: Double = 100
    var rotation: Double = 0
    var opacity: Double = 1
    var locked: Bool = false
    var flipH: Bool = false
    var flipV: Bool = false
    var group: String?

    // shape
    var shapeId: String?
    var fill: Paint?
    var stroke: String?
    var strokeWidth: Double?
    var radius: Double?

    // text
    var text: String?
    var fontFamily: String?
    var fontSize: Double?
    var fontWeight: Int?
    var italic: Bool?
    var underline: Bool?
    var align: String?
    var lineHeight: Double?
    var letterSpacing: Double?
    var color: String?
    var listStyle: String?
    var effect: TextEffectSpec?
    /// Degrees of arc for curved text. Positive bends the baseline into a
    /// rainbow, negative into a valley; nil or zero is a straight line.
    var curve: Double?

    // image
    var src: String?
    var filter: String?
    /// A shape from the library to clip this image to. Unknown ids resolve to
    /// no frame rather than to a rectangle, so a document from a build with
    /// more shapes than this one does not silently crop someone's photo.
    var maskShapeId: String?
    var adjustments: Adjustments?
    var cropScale: Double?
    var cropX: Double?
    var cropY: Double?

    // sticker
    var glyph: String?

    // line
    var thickness: Double?
    var dash: String?
    var startCap: String?
    var endCap: String?

    var frame: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    var center: CGPoint { CGPoint(x: x + w / 2, y: y + h / 2) }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UID.make()
        type = (try? c.decode(ElementType.self, forKey: .type)) ?? .shape
        x = (try? c.decode(Double.self, forKey: .x)) ?? 0
        y = (try? c.decode(Double.self, forKey: .y)) ?? 0
        w = (try? c.decode(Double.self, forKey: .w)) ?? 100
        h = (try? c.decode(Double.self, forKey: .h)) ?? Element.defaultHeight(for: type, decoded: c)
        rotation = (try? c.decode(Double.self, forKey: .rotation)) ?? 0
        opacity = (try? c.decode(Double.self, forKey: .opacity)) ?? 1
        locked = (try? c.decode(Bool.self, forKey: .locked)) ?? false
        flipH = (try? c.decode(Bool.self, forKey: .flipH)) ?? false
        flipV = (try? c.decode(Bool.self, forKey: .flipV)) ?? false
        group = try? c.decode(String.self, forKey: .group)
        shapeId = try? c.decode(String.self, forKey: .shapeId)
        fill = try? c.decode(Paint.self, forKey: .fill)
        stroke = try? c.decode(String.self, forKey: .stroke)
        strokeWidth = try? c.decode(Double.self, forKey: .strokeWidth)
        radius = try? c.decode(Double.self, forKey: .radius)
        text = try? c.decode(String.self, forKey: .text)
        fontFamily = try? c.decode(String.self, forKey: .fontFamily)
        fontSize = try? c.decode(Double.self, forKey: .fontSize)
        fontWeight = try? c.decode(Int.self, forKey: .fontWeight)
        italic = try? c.decode(Bool.self, forKey: .italic)
        underline = try? c.decode(Bool.self, forKey: .underline)
        align = try? c.decode(String.self, forKey: .align)
        lineHeight = try? c.decode(Double.self, forKey: .lineHeight)
        letterSpacing = try? c.decode(Double.self, forKey: .letterSpacing)
        color = try? c.decode(String.self, forKey: .color)
        listStyle = try? c.decode(String.self, forKey: .listStyle)
        effect = try? c.decode(TextEffectSpec.self, forKey: .effect)
        curve = try? c.decode(Double.self, forKey: .curve)
        src = try? c.decode(String.self, forKey: .src)
        filter = try? c.decode(String.self, forKey: .filter)
        maskShapeId = try? c.decode(String.self, forKey: .maskShapeId)
        adjustments = try? c.decode(Adjustments.self, forKey: .adjustments)
        cropScale = try? c.decode(Double.self, forKey: .cropScale)
        cropX = try? c.decode(Double.self, forKey: .cropX)
        cropY = try? c.decode(Double.self, forKey: .cropY)
        glyph = try? c.decode(String.self, forKey: .glyph)
        thickness = try? c.decode(Double.self, forKey: .thickness)
        dash = try? c.decode(String.self, forKey: .dash)
        startCap = try? c.decode(String.self, forKey: .startCap)
        endCap = try? c.decode(String.self, forKey: .endCap)
    }

    private static func defaultHeight(for type: ElementType, decoded c: KeyedDecodingContainer<CodingKeys>) -> Double {
        switch type {
        case .line:
            let t = (try? c.decode(Double.self, forKey: .thickness)) ?? 4
            return max(8, t)
        case .text:
            // Pre-layout estimate; the canvas measures and corrects it.
            let size = (try? c.decode(Double.self, forKey: .fontSize)) ?? 42
            let lh = (try? c.decode(Double.self, forKey: .lineHeight)) ?? 1.25
            let lines = ((try? c.decode(String.self, forKey: .text)) ?? "x")
                .components(separatedBy: "\n").count
            return (size * lh * Double(lines)).rounded(.up)
        default:
            return 100
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, x, y, w, h, rotation, opacity, locked, flipH, flipV, group
        case shapeId, fill, stroke, strokeWidth, radius
        case text, fontFamily, fontSize, fontWeight, italic, underline, align
        case lineHeight, letterSpacing, color, listStyle, effect, curve
        case src, filter, maskShapeId, adjustments, cropScale, cropX, cropY
        case glyph
        case thickness, dash, startCap, endCap
    }

    // MARK: factories (defaults mirror the web factories)

    static func shape(_ shapeId: String, w: Double = 200, h: Double = 200) -> Element {
        var e = Element()
        e.type = .shape
        e.shapeId = shapeId
        e.w = w; e.h = h
        e.fill = .solid("#8b5cf6")
        e.radius = 0
        return e
    }

    static func text(_ string: String, fontSize: Double = 42, w: Double = 400) -> Element {
        var e = Element()
        e.type = .text
        e.text = string
        e.fontSize = fontSize
        e.fontFamily = "sans"
        e.fontWeight = 400
        e.align = "center"
        e.lineHeight = 1.25
        e.letterSpacing = 0
        e.color = "#1f2430"
        e.effect = TextEffectSpec(type: "none")
        e.w = w
        e.h = fontSize * 1.25
        return e
    }

    static func image(_ src: String, w: Double = 480, h: Double = 360) -> Element {
        var e = Element()
        e.type = .image
        e.src = src
        e.w = w; e.h = h
        e.filter = "none"
        e.cropScale = 1; e.cropX = 0.5; e.cropY = 0.5
        e.radius = 0
        return e
    }

    static func sticker(_ glyph: String, size: Double = 160) -> Element {
        var e = Element()
        e.type = .sticker
        e.glyph = glyph
        e.w = size; e.h = size
        return e
    }

    static func line(w: Double = 300) -> Element {
        var e = Element()
        e.type = .line
        e.w = w; e.h = 8
        e.color = "#1f2430"
        e.thickness = 4
        e.dash = "solid"
        e.startCap = "none"; e.endCap = "none"
        return e
    }

    /// Deep copy with a fresh id, offset for duplicate/paste.
    func duplicated(offset: Double = 24) -> Element {
        var copy = self
        copy.id = UID.make()
        copy.x += offset
        copy.y += offset
        return copy
    }
}
