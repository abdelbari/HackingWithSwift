// Letter and number frames — A to Z and 0 to 9, each a Bebas Neue glyph's
// outline — that a photo drops into as it does into any frame: Add ▸ Frames
// ▸ Letters & numbers. They are the `glyphFrames` of PhotoFrames.json
// (the Android twin's tools/generate_frames.py writes the file both phones
// ship, byte for byte), each a ShapeLibrary-style path entry in its own
// 0…100 box with the glyph's own proportions, the taller side 100. A frame
// on the page is an empty photo whose `maskShapeId` names the entry
// ("glyph-A"), so ContentLibrary.frameShape clips the photo to the letter
// and every renderer and export draws it as a framed photo.

import CoreGraphics
import Foundation

/// One entry as the file has it. One missing its id, glyph, path or a side
/// is passed over, as on the Android twin.
struct GlyphFrameDef: Decodable {
    var id: String?
    var frameGlyph: String?
    var name: String?
    var width: Double?
    var height: Double?
    var path: String?

    private enum CodingKeys: String, CodingKey { case id, frameGlyph, name, width, height, path }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        id = try? c.decode(String.self, forKey: .id)
        frameGlyph = try? c.decode(String.self, forKey: .frameGlyph)
        name = try? c.decode(String.self, forKey: .name)
        width = try? c.decode(Double.self, forKey: .width)
        height = try? c.decode(Double.self, forKey: .height)
        path = try? c.decode(String.self, forKey: .path)
    }
}

enum GlyphFrames {

    /// The key a glyph frame's entry carries: the letter or digit it is.
    static let glyphKey = "frameGlyph"

    /// The share of the page's shorter side a frame's taller side takes as
    /// it goes on.
    static let pageShare = 0.5

    /// One frame: its shape, the glyph, and its proportions (the taller
    /// side 100).
    struct Frame: Identifiable, Equatable {
        var shape: ShapeDef
        var glyph: String
        var width: Double
        var height: Double

        var id: String { shape.id }

        /// Two frames are the same frame when they are the same shape: the
        /// shape's id names the glyph's outline in the shared file.
        static func == (a: Frame, b: Frame) -> Bool {
            a.id == b.id && a.glyph == b.glyph && a.width == b.width && a.height == b.height
        }
    }

    /// Every frame in the file's order: A to Z, then 0 to 9.
    static let all: [Frame] = (PhotoGrids.file.glyphFrames ?? []).compactMap { entry in
        guard let id = entry.id, let glyph = entry.frameGlyph, let path = entry.path,
              let width = entry.width, width > 0, let height = entry.height, height > 0 else { return nil }
        let shape = ShapeDef(id: id, name: entry.name ?? glyph, category: "Frames", path: path, rectLike: false,
                             englishName: glyph)
        return Frame(shape: shape, glyph: glyph, width: width, height: height)
    }

    private static let byId: [String: Frame] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// The frame whose shape is `id` ("glyph-A"), or nil.
    static func frame(_ id: String?) -> Frame? {
        id.flatMap { byId[$0] }
    }

    static func shape(_ id: String?) -> ShapeDef? {
        frame(id)?.shape
    }

    /// The frame for `glyph` ("A", "7"), or nil.
    static func of(_ glyph: String) -> Frame? {
        all.first { $0.glyph == glyph }
    }

    /// `frame` as an empty photo frame on a page of `page`'s size: its
    /// taller side `pageShare` of the page's shorter side, the other by the
    /// glyph's proportions, centred — the rule both phones share. Framed
    /// from the start, in the glyph's own proportions, not squared as a
    /// photo taking its first frame is.
    static func element(_ frame: Frame, page: CGSize) -> Element {
        let side = Double(min(page.width, page.height)) * pageShare
        let w = side * frame.width / 100
        let h = side * frame.height / 100
        var el = Element()
        el.type = .image
        el.src = nil
        el.radius = 0
        el.w = w
        el.h = h
        el.x = (Double(page.width) - w) / 2
        el.y = (Double(page.height) - h) / 2
        el.maskShapeId = frame.shape.id
        return el
    }

    /// What a frame's tile says: "A letter frame".
    static func label(_ frame: Frame) -> String {
        tr("%@ letter frame", frame.glyph)
    }
}
