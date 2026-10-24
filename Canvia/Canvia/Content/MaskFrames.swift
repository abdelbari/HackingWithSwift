// Mask frames — brush strokes, torn and deckled paper, blobs, arches,
// tickets and stamps, badges and a ring — that a photo drops into as it does
// into any frame: Add ▸ Photos ▸ Shaped frames, and the Frame sheet. They
// are the `photoMasks` of PhotoFrames.json (tools/generate_frames.py writes
// the file both phones ship, byte for byte), each {"id", "name",
// "category", "path", "fillRule"}, its path an SVG d in the unit square.
// A frame on the page is an empty photo whose `maskShapeId` is
// "mask:<id>", so ContentLibrary.frameShape clips the photo to it — the
// path scaled to the library's 0…100 box — and isFrameLike, a drop and
// Detach image treat it as any shaped frame. A hole (the ring) is wound
// against its outline in the file, so the nonzero rule every renderer
// clips by cuts it as "evenodd" says. The Android twin's MaskFrames.

import CoreGraphics
import Foundation

/// One entry as the file has it; one missing its id, name, category or
/// path is passed over, as on the Android twin.
struct MaskFrameDef: Decodable {
    var id: String?
    var name: String?
    var category: String?
    var path: String?
    var fillRule: String?

    private enum CodingKeys: String, CodingKey { case id, name, category, path, fillRule }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        id = try? c.decode(String.self, forKey: .id)
        name = try? c.decode(String.self, forKey: .name)
        category = try? c.decode(String.self, forKey: .category)
        path = try? c.decode(String.self, forKey: .path)
        fillRule = try? c.decode(String.self, forKey: .fillRule)
    }
}

enum MaskFrames {

    /// What a mask frame's maskShapeId starts with.
    static let prefix = "mask:"

    /// The categories, in the order the chips show them.
    static let categories = ["brush", "torn", "blob", "arch", "badge", "ticket"]

    /// The share of the page's shorter side a mask frame takes as it goes on.
    static let pageShare = 0.5

    /// One mask: its shape (id "mask:<id>", path in the 0…100 box), its
    /// category, and its fill rule.
    struct Mask: Identifiable, Equatable {
        var shape: ShapeDef
        var category: String
        var fillRule: String

        var id: String { shape.id }

        static func == (a: Mask, b: Mask) -> Bool {
            a.id == b.id && a.category == b.category && a.fillRule == b.fillRule && a.shape.path == b.shape.path
        }
    }

    /// What a category's chip says.
    static func categoryName(_ category: String) -> String {
        switch category {
        case "brush": return tr("Brush")
        case "torn": return tr("Torn")
        case "blob": return tr("Blobs")
        case "arch": return tr("Arches")
        case "badge": return tr("Badges")
        case "ticket": return tr("Tickets")
        default: return category
        }
    }

    /// Every mask in the file's order.
    static let all: [Mask] = parse(PhotoGrids.file.photoMasks ?? [])

    /// The masks the entries make: one with no id, name, path or a known
    /// category left out; a fill rule other than "evenodd" read as nonzero.
    static func parse(_ entries: [MaskFrameDef]) -> [Mask] {
        entries.compactMap { entry in
            guard let id = entry.id, !id.isEmpty, let name = entry.name, let path = entry.path, !path.isEmpty,
                  let category = entry.category, categories.contains(category) else { return nil }
            let shape = ShapeDef(id: prefix + id, name: name, category: "Frames", path: scaled(path),
                                 rectLike: false, englishName: name)
            return Mask(shape: shape, category: category, fillRule: entry.fillRule == "evenodd" ? "evenodd" : "nonzero")
        }
    }

    /// Path data in the unit square as the library's 0…100 box has it:
    /// every number a hundred times as large (the file's paths are absolute
    /// M, L, C and Z, so every number is a coordinate).
    static func scaled(_ d: String) -> String {
        var out = ""
        var number = ""
        func flush() {
            guard !number.isEmpty else { return }
            if let v = Double(number) { out += SVGExporter.num(v * 100) } else { out += number }
            number = ""
        }
        for ch in d {
            if ch.isNumber || ch == "." || (ch == "-" && number.isEmpty) {
                number.append(ch)
            } else {
                flush()
                out.append(ch)
            }
        }
        flush()
        return out
    }

    private static let byId: [String: Mask] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// The mask a maskShapeId ("mask:blob1") names, or nil.
    static func mask(_ id: String?) -> Mask? {
        id.flatMap { byId[$0] }
    }

    static func shape(_ id: String?) -> ShapeDef? {
        mask(id)?.shape
    }

    /// The masks of `category` (any, for nil) whose name or category — in
    /// English or as the chip says it — has `query` in it, case aside, in
    /// the file's order.
    static func filter(_ masks: [Mask] = all, category: String?, query: String) -> [Mask] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return masks.filter { mask in
            (category == nil || mask.category == category)
                && (needle.isEmpty || tags(mask).contains { $0.contains(needle) })
        }
    }

    /// The words a mask is found by: its name, as the file has it and as
    /// the app says it, and its category both ways.
    static func tags(_ mask: Mask) -> [String] {
        [mask.shape.name, tr(mask.shape.name), mask.category, categoryName(mask.category), "frame", "mask"]
            .map { $0.lowercased() }
    }

    /// `mask` as an empty photo frame on a page of `page`'s size: a square
    /// `pageShare` of the page's shorter side, centred — the rule both
    /// phones share.
    static func element(_ mask: Mask, page: CGSize) -> Element {
        let side = Double(min(page.width, page.height)) * pageShare
        var el = Element()
        el.type = .image
        el.src = nil
        el.radius = 0
        el.w = side
        el.h = side
        el.x = (Double(page.width) - side) / 2
        el.y = (Double(page.height) - side) / 2
        el.maskShapeId = mask.shape.id
        return el
    }
}
