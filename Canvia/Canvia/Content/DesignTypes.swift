// Round 34's design types: a page cut into slides — an Instagram or
// LinkedIn carousel, a panorama that runs on from one slide to the next —
// and what the new types start with beyond their size. The Android twin's
// core/content/DesignTypes.kt (PageSplit and DesignTypes), rule for rule,
// with the shared fixture Tests/Fixtures/carousel-tiles.json for the cut.

import CoreGraphics
import Foundation

/// A page's "split": {"columns": n, "rows": 1}, both keys written, as both
/// phones write it. The editor draws its seams as guides that never print,
/// and a PNG or JPG export cuts it into a file a slide (ExportPlan.tiles).
/// Read leniently, as the Android twin reads it: "columns" a whole number
/// of at least one, else no split; "rows" one when missing or of another
/// kind.
struct PageSplit: Codable, Equatable {
    var columns: Int
    var rows: Int = 1

    /// The fewest and most slides a carousel's stepper offers.
    static let minColumns = 2
    static let maxColumns = 10

    init(columns: Int, rows: Int = 1) {
        self.columns = columns
        self.rows = rows
    }

    private enum CodingKeys: String, CodingKey { case columns, rows }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        columns = try c.decode(Int.self, forKey: .columns)
        rows = (try? c.decodeIfPresent(Int.self, forKey: .rows)) ?? 1
        guard columns >= 1, rows >= 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "no slides"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(columns, forKey: .columns)
        try c.encode(rows, forKey: .rows)
    }

    /// Every page of `design` cut into `columns` slides, but those cut
    /// already — what a carousel type gives the pages it starts with.
    static func splitAll(_ design: Design, columns: Int) -> Design {
        var out = design
        for i in out.pages.indices where out.pages[i].split == nil {
            out.pages[i].split = PageSplit(columns: columns)
        }
        return out
    }

    /// Page `pageId` given `columns` slides by the stepper — held to
    /// minColumns...maxColumns — its width made columns × one slide's width
    /// (its width now over its columns now), its height and everything on
    /// it left where it is, so a slide added comes in empty at the right
    /// and one taken away leaves what was on it hanging off the edge. The
    /// width is the page's own, and none — the design's — when that is what
    /// it comes to. Nil for a page that is not cut, or already has that
    /// many.
    static func resized(_ design: Design, pageId: String, columns: Int) -> Design? {
        guard let index = design.pages.firstIndex(where: { $0.id == pageId }),
              let split = design.pages[index].split else { return nil }
        let n = min(max(columns, minColumns), maxColumns)
        guard n != split.columns else { return nil }
        var page = design.pages[index]
        let slide = Double(design.size(for: page).width) / Double(split.columns)
        let width = slide * Double(n)
        page.split = PageSplit(columns: n, rows: split.rows)
        page.width = width == design.width ? nil : width
        // A page whose own height is the design's keeps none of its own.
        if page.width == nil && page.height == design.height { page.height = nil }
        var out = design
        out.pages[index] = page
        return out
    }

    /// Where the seams between `split`'s slides fall on a page of `size`,
    /// in page units: the vertical ones, then the horizontal ones.
    static func seams(_ size: CGSize, _ split: PageSplit) -> (vertical: [Double], horizontal: [Double]) {
        let w = Double(size.width), h = Double(size.height)
        let vertical = split.columns > 1 ? (1..<split.columns).map { w * Double($0) / Double(split.columns) } : []
        let horizontal = split.rows > 1 ? (1..<split.rows).map { h * Double($0) / Double(split.rows) } : []
        return (vertical, horizontal)
    }
}

/// What the design types of round 34 start with beyond their size: the
/// folded cards and the trifold as two pages — outside and inside — the
/// trifold's panels marked by guides at its thirds, the mind map and the
/// flowchart as a whiteboard with a starter layout joined by connectors,
/// and the print-on-fabric types' clear background. A blank design only:
/// a template brings its own pages.
enum DesignTypes {

    static let mindMap = "mind-map"
    static let flowchart = "flowchart"
    static let trifold = "trifold-letter"

    /// The whiteboard-kind types, which start expanded as the Whiteboard
    /// type does.
    static let whiteboards: Set<String> = [Whiteboards.presetId, mindMap, flowchart]

    /// The types a blank design starts as two pages of: front and inside.
    static let twoPages: Set<String> = [trifold, "birthday-card", "thank-you-card"]

    /// The types whose export suggests a clear background: printed on
    /// fabric, where the shirt or the bag is the background.
    static let clearBackground: Set<String> = ["tshirt-print", "tote-print"]

    /// Whether a picture of `design` should be clear: of a clearBackground
    /// type's exact pixels, the first type in the catalogue at that size.
    static func suggestsClear(_ design: Design, presets: [SizePreset] = SizePreset.all) -> Bool {
        guard let first = presets.first(where: { $0.w == design.width && $0.h == design.height }) else { return false }
        return clearBackground.contains(first.id)
    }

    /// A blank `design` of `preset` as its type starts: two pages for a
    /// folded type, the trifold's panel guides, a whiteboard's starter.
    static func started(_ preset: SizePreset, _ design: Design) -> Design {
        var made = design
        if twoPages.contains(preset.id), let last = made.pages.last {
            made.pages.append(Page(background: last.background))
        }
        if preset.id == trifold { made.guides = panelGuides(width: made.width) }
        switch preset.id {
        case mindMap: return withStarter(made, mindMapStarter())
        case flowchart: return withStarter(made, flowchartStarter())
        default: return made
        }
    }

    /// A trifold's panel guides: vertical, at a third and two thirds of
    /// `width`.
    static func panelGuides(width: Double) -> [Guide] {
        [1.0, 2.0].map { Guide(vertical: true, position: width * $0 / 3) }
    }

    /// Whether `el` is a connector: a line holding on to an end.
    static func isConnector(_ el: Element) -> Bool {
        el.type == .line && (el.connectFrom != nil || el.connectTo != nil)
    }

    /// `design`'s first page with `elements` on it, laid round the frame's
    /// middle, connectors laid between what they join — and expanded again,
    /// so its bounds take them in.
    private static func withStarter(_ design: Design, _ elements: [Element]) -> Design {
        guard let first = design.pages.first else { return design }
        let size = design.size(for: first)
        let boxes = elements.filter { !isConnector($0) }.map(\.frame)
        guard let box = boxes.dropFirst().reduce(boxes.first, { $0?.union($1) }) else { return design }
        let dx = (Double(size.width) / 2 - Double(box.midX)).rounded(.down)
        let dy = (Double(size.height) / 2 - Double(box.midY)).rounded(.down)
        var page = first
        page.elements = elements.map { el in
            var moved = el
            moved.x += dx
            moved.y += dy
            return moved
        }
        Connectors.resolve(&page)
        var out = design
        out.pages[0] = Whiteboards.expanded(page, frame: size)
        return out
    }

    /// A box with `words` in it, of `shapeId`, `w` × `h` at `x`, `y`.
    private static func box(_ shapeId: String, _ words: String, x: Double, y: Double, w: Double, h: Double,
                            fill: String) -> Element {
        var shape = Element.shape(shapeId, w: w, h: h)
        shape.x = x
        shape.y = y
        shape.fill = .solid(fill)
        var started = ShapeText.starting(shape)
        started.text = words
        return started
    }

    /// An arrow from `a` to `b` that follows them, laid between their edges.
    private static func connect(_ a: Element, _ b: Element) -> Element {
        var line = Element.line(w: 100)
        line.connectFrom = a.id
        line.connectTo = b.id
        line.endCap = "arrow"
        return Connectors.laid(line, from: a.frame, to: b.frame)
    }

    /// A mind map's start: the main idea in the middle and four branches
    /// round it, each joined to it by an arrow.
    static func mindMapStarter() -> [Element] {
        let centre = box("circle", tr("Main idea"), x: 660, y: 420, w: 600, h: 240, fill: "#8b5cf6")
        let spots: [(String, Double, Double)] = [
            (tr("Idea 1"), 120, 120), (tr("Idea 2"), 1400, 120),
            (tr("Idea 3"), 120, 780), (tr("Idea 4"), 1400, 780),
        ]
        let branches = spots.enumerated().map { (i, spot) -> Element in
            var branch = box("rect", spot.0, x: spot.1, y: spot.2, w: 400, h: 180, fill: StickyNotes.colours[i])
            branch.radius = 24
            return branch
        }
        return [centre] + branches + branches.map { connect(centre, $0) }
    }

    /// A flowchart's start: Start, a step, a decision and End, top to
    /// bottom, each joined to the next by an arrow.
    static func flowchartStarter() -> [Element] {
        let boxes = [
            box("circle", tr("Start"), x: 760, y: 0, w: 400, h: 160, fill: "#c5e1a5"),
            box("rect", tr("Step"), x: 760, y: 300, w: 400, h: 180, fill: "#b3e5fc"),
            box("diamond", tr("Decision?"), x: 785, y: 620, w: 350, h: 260, fill: "#fff176"),
            box("circle", tr("End"), x: 760, y: 1020, w: 400, h: 160, fill: "#f8bbd0"),
        ]
        return boxes + zip(boxes, boxes.dropFirst()).map { connect($0, $1) }
    }
}
