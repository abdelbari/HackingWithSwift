// The illustrated graphics: doodle arrows, underlines, sparkles, badges,
// ribbons, blobs, confetti, dividers, bubbles, frames, scribbles and
// patterns, a couple of hundred of them in twelve categories, each in up to
// four colours — drawn by tools/generate_graphics.py into Graphics.json,
// the very file the Android twin bundles, byte for byte, so a graphic is the
// same on both phones (GraphicsLibraryTests hashes it).
//
// A graphic goes on the page as any SVG graphic does (SvgImport.graphic):
// its shapes, each in its own colour, kept together as a group — so it is
// drawn, exported, recoloured one colour at a time (Colour swap) and changed
// across the design (Change all) as an imported SVG is, and a build that
// knows nothing of the pack still draws it. Each of its shapes keeps the
// graphic's id (`graphicId`), to be named by and for More like this.
//
// A graphic that moves (`motion`) — an arrow, an underline or a scribble
// drawing itself on, a sparkle twinkling — goes on with that animation set
// (ElementAnimation.motioned), is found under the Animated chip and by the
// word "animated", and plays in Present and the video, GIF and web page.

import Foundation

/// One illustrated graphic: its id, what Add calls it, its category, words
/// to find it by, the whole SVG it is drawn from, and its fills in the order
/// they are first used.
struct GraphicDef: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: String
    var tags: [String] = []
    var svg: String
    var colours: [String] = []
    /// "draw" | "twinkle" | "float"; nil for a graphic that stays still.
    var motion: String?

    private enum CodingKeys: String, CodingKey { case id, name, category, tags, svg, colours, motion }

    init(id: String, name: String, category: String, tags: [String] = [], svg: String, colours: [String] = [],
         motion: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.tags = tags
        self.svg = svg
        self.colours = colours
        self.motion = motion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(String.self, forKey: .category)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        svg = try c.decode(String.self, forKey: .svg)
        colours = (try? c.decodeIfPresent([String].self, forKey: .colours)) ?? []
        motion = try? c.decodeIfPresent(String.self, forKey: .motion)
    }

    /// The element animation a graphic that moves goes on with: draw draws
    /// on, twinkle twinkles, float bobs (bounce); nil for one that is still
    /// or moves in a way this build does not know.
    var animationKind: String? {
        switch motion {
        case "draw": return ElementAnimation.draw
        case "twinkle": return ElementAnimation.twinkle
        case "float": return "bounce"
        default: return nil
        }
    }
}

enum GraphicsLibrary {

    /// The file's shape.
    private struct Pack: Codable {
        var categories: [String]
        var graphics: [GraphicDef]
    }

    /// Read once, on first use.
    private static let file: Pack = {
        guard let url = Bundle.main.url(forResource: "Graphics", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Pack.self, from: data) else {
            assertionFailure("Graphics.json missing or invalid")
            return Pack(categories: [], graphics: [])
        }
        return decoded
    }()

    /// Every graphic, category by category, in the generator's order.
    static var graphics: [GraphicDef] { file.graphics }

    /// The categories, in the order Add's chips show them.
    static var categories: [String] { file.categories }

    /// The chip, and the word, for every graphic that moves, whatever its
    /// category: shown first among Add's chips.
    static let animated = "Animated"

    /// Every graphic that moves, in the pack's order.
    static var moving: [GraphicDef] { file.graphics.filter { $0.motion != nil } }

    // A duplicate id would be a content bug: keep the first, as the icons do.
    private static let byId: [String: GraphicDef] = Dictionary(
        file.graphics.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func graphic(_ id: String?) -> GraphicDef? {
        id.flatMap { byId[$0] }
    }

    /// The graphics in `category`, or all of them for nil; Animated is every
    /// graphic that moves.
    static func inCategory(_ category: String?) -> [GraphicDef] {
        guard let category else { return graphics }
        if category == animated { return moving }
        return graphics.filter { $0.category == category }
    }

    /// The graphics whose name, id or one of whose tags has `query` in it,
    /// case aside, within `category` when one is chosen; every graphic
    /// there for a blank one. As the Android twin's search.
    static func search(_ query: String, in category: String? = nil) -> [GraphicDef] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let from = inCategory(category)
        guard !needle.isEmpty else { return from }
        return from.filter { g in
            g.name.lowercased().contains(needle) || g.id.contains(needle) || g.tags.contains { $0.contains(needle) }
                || (g.motion != nil && "animated".contains(needle))
        }
    }

    /// The graphic an element was put on as, when it is one this pack has.
    static func graphic(of el: Element) -> GraphicDef? {
        graphic(el.graphicId)
    }

    /// `graphic` as it goes on a page this size: its shapes as
    /// SvgImport.graphic places any SVG — fitted to 0.4 of the page's
    /// shorter side, centred, one group — each naming the graphic; one that
    /// moves with its animation set, its paths in turn (motioned).
    static func elements(_ graphic: GraphicDef, pageWidth: Double, pageHeight: Double) -> [Element] {
        guard let placed = SvgImport.graphic(graphic.svg, pageWidth: pageWidth, pageHeight: pageHeight) else { return [] }
        let named = placed.elements.map { el in
            var named = el
            named.graphicId = graphic.id
            return named
        }
        guard let kind = graphic.animationKind else { return named }
        return ElementAnimation.motioned(named, kind: kind)
    }
}
