// Decorative photo frames — a polaroid, a film strip, a phone, a laptop, a
// browser window, torn paper, a circle stamp and an arch — each a group of
// ordinary elements round one empty photo frame, its window: shapes drawn
// from `pathData`, a caption where there is one. They are the `photoFrames`
// of PhotoFrames.json, the Android twin's file byte for byte (see
// PhotoGrids), so both phones draw them identically and neither needs a new
// kind of element. A photo picked or dropped goes into the window by the
// rules every empty frame follows (PhotoFrames).

import CoreGraphics
import Foundation

/// One element of a frame as the file has it, in the frame's own box.
/// Every field is read on its own, so one odd value loses that element
/// at most, never the frame.
struct FramePart: Decodable {
    var type: String?
    var x: Double?
    var y: Double?
    var w: Double?
    var h: Double?
    var rotation: Double?
    var opacity: Double?
    var pathData: String?
    var fill: String?
    var stroke: String?
    var strokeWidth: Double?
    var radius: Double?
    var maskShapeId: String?
    var text: String?
    var fontFamily: String?
    var fontSize: Double?
    var fontWeight: Double?
    var color: String?
    var align: String?

    private enum CodingKeys: String, CodingKey {
        case type, x, y, w, h, rotation, opacity, pathData, fill, stroke, strokeWidth, radius, maskShapeId
        case text, fontFamily, fontSize, fontWeight, color, align
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try? c.decode(String.self, forKey: .type)
        x = try? c.decode(Double.self, forKey: .x)
        y = try? c.decode(Double.self, forKey: .y)
        w = try? c.decode(Double.self, forKey: .w)
        h = try? c.decode(Double.self, forKey: .h)
        rotation = try? c.decode(Double.self, forKey: .rotation)
        opacity = try? c.decode(Double.self, forKey: .opacity)
        pathData = try? c.decode(String.self, forKey: .pathData)
        fill = try? c.decode(String.self, forKey: .fill)
        stroke = try? c.decode(String.self, forKey: .stroke)
        strokeWidth = try? c.decode(Double.self, forKey: .strokeWidth)
        radius = try? c.decode(Double.self, forKey: .radius)
        maskShapeId = try? c.decode(String.self, forKey: .maskShapeId)
        text = try? c.decode(String.self, forKey: .text)
        fontFamily = try? c.decode(String.self, forKey: .fontFamily)
        fontSize = try? c.decode(Double.self, forKey: .fontSize)
        fontWeight = try? c.decode(Double.self, forKey: .fontWeight)
        color = try? c.decode(String.self, forKey: .color)
        align = try? c.decode(String.self, forKey: .align)
    }
}

/// One frame as the file has it: its elements in a `width` × `height`
/// box, bottom to top. One without an id, a name or a size is passed
/// over (`DecorativeFrames.presets`), as the Android twin passes it over.
struct FrameDef: Decodable, Identifiable {
    var id: String
    var name: String
    var width: Double
    var height: Double
    var parts: [FramePart]

    private enum CodingKeys: String, CodingKey { case id, name, width, height, elements }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        width = (try? c.decode(Double.self, forKey: .width)) ?? 0
        height = (try? c.decode(Double.self, forKey: .height)) ?? 0
        parts = (try? c.decode([FramePart].self, forKey: .elements)) ?? []
    }

    var isUsable: Bool { !id.isEmpty && !name.isEmpty && width > 0 && height > 0 }
}

enum DecorativeFrames {

    /// The share of the page each side of a frame may take as it goes on.
    static let pageShare = 0.6

    /// Every frame the file has, in its order.
    static let presets: [FrameDef] = PhotoGrids.file.photoFrames.filter(\.isUsable)

    static func preset(_ id: String?) -> FrameDef? {
        presets.first { $0.id == id }
    }

    /// `preset`'s elements on a page of `page` size, grouped: scaled as one,
    /// by the larger factor that keeps it within `pageShare` of the page's
    /// width and of its height, and centred — not rounded, so the window
    /// stays exactly inside its bezel. An element of a kind the file should
    /// not hold is left out.
    static func elements(_ preset: FrameDef, page: CGSize) -> [Element] {
        let width = Double(page.width), height = Double(page.height)
        let scale = min(width * pageShare / preset.width, height * pageShare / preset.height)
        let left = (width - preset.width * scale) / 2
        let top = (height - preset.height * scale) / 2
        let group = UID.make("grp")
        return preset.parts.compactMap { part in
            guard var el = element(part, scale: scale) else { return nil }
            el.x += left
            el.y += top
            el.group = group
            return el
        }
    }

    /// One of a preset's elements, at `scale`, placed within the preset's
    /// box: a shape from its path, the window as an empty frame — clipped
    /// to a library shape when the file names one — or the caption.
    static func element(_ part: FramePart, scale: Double) -> Element? {
        guard let w = part.w, let h = part.h else { return nil }
        var el: Element
        switch part.type {
        case "shape":
            guard let path = part.pathData else { return nil }
            el = Element.shape("rect", w: w * scale, h: h * scale)
            el.pathData = path
            el.fill = .solid(part.fill ?? "#000000")
            el.stroke = part.stroke
            el.strokeWidth = part.strokeWidth.map { $0 * scale }
        case "image":
            el = Element()
            el.type = .image
            el.src = nil
            el.w = w * scale
            el.h = h * scale
            el.radius = (part.radius ?? 0) * scale
            el.maskShapeId = part.maskShapeId
        case "text":
            guard let text = part.text else { return nil }
            el = Element.text(text, fontSize: (part.fontSize ?? 42) * scale, w: w * scale)
            el.h = h * scale
            el.fontFamily = part.fontFamily ?? "sans"
            el.fontWeight = part.fontWeight.map { Int($0) } ?? 400
            el.color = part.color ?? "#1f2430"
            el.align = part.align ?? "center"
        default:
            return nil
        }
        el.x = (part.x ?? 0) * scale
        el.y = (part.y ?? 0) * scale
        el.rotation = part.rotation ?? 0
        el.opacity = part.opacity ?? 1
        return el
    }
}
