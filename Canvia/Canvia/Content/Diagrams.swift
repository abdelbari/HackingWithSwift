// Diagrams made from a list of words — a Venn diagram, a cycle, a pyramid,
// funnel steps, a process, a timeline, an org chart and a two-by-two matrix
// — made locally as charts are and edited as a list: an item added or taken
// away and the shapes reflow and recolour. Once made they are plain shapes,
// words and lines, so every export draws them as it draws anything.
//
// Every member carries the diagram's spec under `diagram` — {"id":
// "dia_<uid>", "kind", "items": [{"text", "note"?, "color"?, "level"?}],
// "style": "solid"|"outline"|"soft", "palette"?, "font"?} — and its part
// under `diagramPart`: "item:<n>" (a shape, the item's words in it but for a
// Venn diagram's circles and a timeline's dots), "label:<n>" (those items'
// words beside them) or "connector:<n>" (a line that follows the items it
// joins, Connectors). They share one group, as a chart's do.
//
// Each kind lays its parts out to fill the box it is made in — or, a Venn
// diagram's circles and a cycle's ring, centred in it at their own shape —
// so the box its items and labels fill is the box it was made in, and
// making it again there (`remade`) puts everything back where it was. The
// rules both phones share (Tests/Fixtures/diagrams.json, the Android twin's
// Diagrams).

import CoreGraphics
import Foundation

/// One item of a diagram: its words, a second line under them, its own
/// colour, and in an org chart how deep it sits (0 the top). Each key is
/// written only when set; a note that is blank, a colour that is no colour
/// or a level that is no whole number reads as none.
struct DiagramItem: Codable, Equatable, Hashable {
    var text: String
    var note: String?
    var color: String?
    var level: Int?

    private enum CodingKeys: String, CodingKey { case text, note, color, level }

    init(text: String, note: String? = nil, color: String? = nil, level: Int? = nil) {
        self.text = text
        self.note = note
        self.color = color
        self.level = level
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)).flatMap { $0.isEmpty ? nil : $0 }
        color = (try? c.decodeIfPresent(String.self, forKey: .color)).flatMap { ColorTools.rgb255($0) != nil ? $0 : nil }
        level = (try? c.decodeIfPresent(Int.self, forKey: .level)).map { max(0, $0) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(level, forKey: .level)
    }
}

/// A diagram as its members carry it. One without an id, of a kind this
/// build does not know, or without items is no diagram: the key does not
/// read, and its parts are a plain group.
struct DiagramSpec: Codable, Equatable, Hashable {
    var id: String
    var kind: DiagramKind
    var items: [DiagramItem]
    var style: DiagramStyle = .solid
    /// Its own colours, chosen in Edit diagram; nil takes the page's.
    var palette: [String]?
    /// Its words' font family; nil is the default face.
    var font: String?

    private enum CodingKeys: String, CodingKey { case id, kind, items, style, palette, font }

    init(id: String = Diagrams.newId(), kind: DiagramKind, items: [DiagramItem], style: DiagramStyle = .solid,
         palette: [String]? = nil, font: String? = nil) {
        self.id = id
        self.kind = kind
        self.items = items
        self.style = style
        self.palette = palette
        self.font = font
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "no id")
        }
        kind = try c.decode(DiagramKind.self, forKey: .kind)
        items = try c.decode([DiagramItem].self, forKey: .items)
        style = (try? c.decodeIfPresent(String.self, forKey: .style)).flatMap { DiagramStyle(rawValue: $0) } ?? .solid
        let colours = (try? c.decodeIfPresent([String].self, forKey: .palette))?.filter { ColorTools.rgb255($0) != nil }
        palette = colours.flatMap { $0.isEmpty ? nil : $0 }
        font = (try? c.decodeIfPresent(String.self, forKey: .font)).flatMap { $0.isEmpty ? nil : $0 }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(items, forKey: .items)
        try c.encode(style.rawValue, forKey: .style)
        try c.encodeIfPresent(palette, forKey: .palette)
        try c.encodeIfPresent(font, forKey: .font)
    }
}

/// A diagram's kinds, in Add's order, with the fewest and most items each
/// takes.
enum DiagramKind: String, Codable, CaseIterable, Identifiable {
    case venn2, venn3, cycle, pyramid, funnelSteps, process, timeline, orgChart, matrix2x2

    var id: String { rawValue }

    var label: String {
        switch self {
        case .venn2: return tr("Venn, two circles")
        case .venn3: return tr("Venn, three circles")
        case .cycle: return tr("Cycle")
        case .pyramid: return tr("Pyramid")
        case .funnelSteps: return tr("Funnel steps")
        case .process: return tr("Process")
        case .timeline: return tr("Timeline")
        case .orgChart: return tr("Org chart")
        case .matrix2x2: return tr("Matrix")
        }
    }

    var minItems: Int {
        switch self {
        case .venn2: return 2
        case .venn3: return 3
        default: return 2
        }
    }

    var maxItems: Int {
        switch self {
        case .venn2: return 2
        case .venn3: return 3
        default: return 8
        }
    }
}

/// How a diagram's shapes are painted: filled, outlined, or a pale tint.
enum DiagramStyle: String, CaseIterable, Identifiable {
    case solid, outline, soft

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solid: return tr("Solid")
        case .outline: return tr("Outline")
        case .soft: return tr("Soft")
        }
    }
}

enum Diagrams {

    static func newId() -> String { UID.make("dia") }

    /// A new diagram of `kind`, with words to start from.
    static func starter(_ kind: DiagramKind) -> DiagramSpec {
        let words: [String]
        switch kind {
        case .venn2: words = [tr("Ours"), tr("Theirs")]
        case .venn3: words = [tr("Fast"), tr("Good"), tr("Cheap")]
        case .cycle: words = [tr("Plan"), tr("Do"), tr("Check"), tr("Act")]
        case .pyramid: words = [tr("Vision"), tr("Goals"), tr("Projects"), tr("Tasks")]
        case .funnelSteps: words = [tr("Visitors"), tr("Sign-ups"), tr("Customers")]
        case .process: words = [tr("Idea"), tr("Design"), tr("Build"), tr("Launch")]
        // Years are the same in every language.
        case .timeline: words = ["2023", "2024", "2025", "2026"]
        case .orgChart: words = [tr("Director"), tr("Design lead"), tr("Engineering lead"), tr("Designer"), tr("Engineer")]
        case .matrix2x2: words = [tr("Do now"), tr("Plan"), tr("Delegate"), tr("Eliminate")]
        }
        let levels: [Int]? = kind == .orgChart ? [0, 1, 1, 2, 2] : nil
        let items = words.enumerated().map { i, w in DiagramItem(text: w, level: levels?[i]) }
        return DiagramSpec(kind: kind, items: items)
    }

    /// The diagram `elements` are all parts of, when they are one's.
    static func of(_ elements: [Element]) -> DiagramSpec? {
        let specs = elements.compactMap(\.diagram)
        guard let first = specs.first, specs.allSatisfy({ $0.id == first.id }) else { return nil }
        return first
    }

    /// Diagram `id`'s members on `page`, in the page's order.
    static func members(_ page: Page, id: String) -> [Element] {
        page.elements.filter { $0.diagram?.id == id }
    }

    // MARK: the list editor

    /// `spec` with `text` added after item `after` (at the end for none), at
    /// that item's level; itself at the kind's most.
    static func adding(_ spec: DiagramSpec, text: String, after: Int?) -> DiagramSpec {
        guard spec.items.count < spec.kind.maxItems else { return spec }
        let at = min(max((after ?? spec.items.count - 1) + 1, 0), spec.items.count)
        let level: Int? = spec.kind == .orgChart ? (at > 0 ? spec.items[at - 1].level ?? 0 : 0) : nil
        var out = spec
        out.items.insert(DiagramItem(text: text, level: level), at: at)
        return out
    }

    /// The same at the end of the list.
    static func adding(_ spec: DiagramSpec, text: String) -> DiagramSpec {
        adding(spec, text: text, after: nil)
    }

    /// `spec` without item `index`; itself at the kind's fewest.
    static func removing(_ spec: DiagramSpec, at index: Int) -> DiagramSpec {
        guard spec.items.count > spec.kind.minItems, spec.items.indices.contains(index) else { return spec }
        var out = spec
        out.items.remove(at: index)
        return out
    }

    /// `spec` with item `index` moved `by` places, within the list.
    static func moving(_ spec: DiagramSpec, at index: Int, by: Int) -> DiagramSpec {
        guard spec.items.indices.contains(index) else { return spec }
        let to = min(max(index + by, 0), spec.items.count - 1)
        guard to != index else { return spec }
        var out = spec
        let item = out.items.remove(at: index)
        out.items.insert(item, at: to)
        return out
    }

    /// `spec` with item `index`'s words and note as given; a blank note is
    /// none.
    static func editing(_ spec: DiagramSpec, at index: Int, text: String, note: String?) -> DiagramSpec {
        guard spec.items.indices.contains(index) else { return spec }
        var out = spec
        out.items[index].text = text
        let kept = note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        out.items[index].note = kept
        return out
    }

    /// An org chart's item `index` a level deeper (`by` 1) or shallower
    /// (−1): never below the item above's level and one, never above 0.
    static func indenting(_ spec: DiagramSpec, at index: Int, by: Int) -> DiagramSpec {
        guard spec.kind == .orgChart, spec.items.indices.contains(index) else { return spec }
        let levels = Diagrams.levels(spec)
        let most = index == 0 ? 0 : levels[index - 1] + 1
        var out = spec
        out.items[index].level = min(max(levels[index] + by, 0), most)
        return out
    }

    /// `spec` of `kind`, its items kept as far as the kind takes them — cut
    /// to its most, made up to its fewest with "Item <n>". Into an org chart
    /// from another kind, the first at the top and the rest under it.
    static func switching(_ spec: DiagramSpec, to kind: DiagramKind) -> DiagramSpec {
        var items = Array(spec.items.prefix(kind.maxItems))
        while items.count < kind.minItems { items.append(DiagramItem(text: tr("Item %d", items.count + 1))) }
        if kind == .orgChart && spec.kind != .orgChart {
            items = items.enumerated().map { i, item in
                var out = item
                out.level = i == 0 ? 0 : 1
                return out
            }
        }
        var out = spec
        out.kind = kind
        out.items = items
        return out
    }

    /// `spec` with each item's colour the one its shape on the page has now
    /// (`members`' "item:<n>" fills), so the colours go with the items when
    /// they are moved or one is taken away.
    static func pinned(_ spec: DiagramSpec, members: [Element]) -> DiagramSpec {
        var shapes: [Int: Element] = [:]
        for el in members {
            if let n = index(el.diagramPart, "item:"), shapes[n] == nil { shapes[n] = el }
        }
        var out = spec
        for i in out.items.indices where out.items[i].color == nil {
            out.items[i].color = shapes[i].flatMap { colour(of: $0, style: spec.style) }
        }
        return out
    }

    /// `spec` in `palette` — nil for the page's or brand's colours — each
    /// item's own colour let go, so all of them take the palette.
    static func repainted(_ spec: DiagramSpec, palette: [String]?) -> DiagramSpec {
        var out = spec
        out.palette = palette.flatMap { $0.isEmpty ? nil : $0 }
        for i in out.items.indices { out.items[i].color = nil }
        return out
    }

    // MARK: speech

    /// The diagram in a sentence, for VoiceOver: "Cycle diagram, 4 items".
    static func summary(_ spec: DiagramSpec) -> String {
        tr("%@ diagram, %@", spec.kind.label, trn("%d item|%d items", spec.items.count))
    }

    /// The items VoiceOver steps through, as a list: "1 of 4: Plan". An org
    /// chart's say their level after: "2 of 5: Design lead, level 2".
    static func stops(_ spec: DiagramSpec) -> [String] {
        let levels = Diagrams.levels(spec)
        return spec.items.enumerated().map { i, item in
            let words = [item.text, item.note ?? ""]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            let said = tr("%d of %d: %@", i + 1, spec.items.count, words)
            return spec.kind == .orgChart ? tr("%@, level %d", said, levels[i] + 1) : said
        }
    }

    // MARK: making

    /// The org chart's levels as laid out: the first item at 0, each after
    /// at most one deeper than the item before it.
    static func levels(_ spec: DiagramSpec) -> [Int] {
        var out: [Int] = []
        for (i, item) in spec.items.enumerated() {
            let most = i == 0 ? 0 : out[i - 1] + 1
            out.append(min(max(item.level ?? (i == 0 ? 0 : 1), 0), most))
        }
        return out
    }

    /// A colour `tint` of the way from white to `hex`: a soft style's fill.
    static func tint(_ hex: String, _ tint: Double = 0.25) -> String {
        guard let rgb = ColorTools.rgb255(hex) else { return hex }
        func c(_ v: Int) -> Int { min(max(Int((255 - Double(255 - v) * tint + 0.5).rounded(.down)), 0), 255) }
        return String(format: "#%02x%02x%02x", c(rgb.r), c(rgb.g), c(rgb.b))
    }

    /// The colour a part was painted in, as `pinned` reads it back: a solid
    /// fill's, an outline's stroke. A soft tint is no item colour.
    private static func colour(of shape: Element, style: DiagramStyle) -> String? {
        switch style {
        case .solid: return shape.fill?.kind == "solid" ? shape.fill?.color : nil
        case .outline: return shape.stroke
        case .soft: return nil
        }
    }

    /// The number after `prefix` in a part's name: 2 for "item:2".
    static func index(_ part: String?, _ prefix: String) -> Int? {
        guard let part, part.hasPrefix(prefix) else { return nil }
        return Int(part.dropFirst(prefix.count))
    }

    /// How a diagram's parts are made: its spec, colours, ink, group and box.
    private struct Maker {
        let spec: DiagramSpec
        let box: CGRect
        let swatches: [String]
        let ink: String
        let group: String

        var items: [DiagramItem] { spec.items }

        func colour(_ i: Int) -> String { items[i].color ?? swatches[i % swatches.count] }

        func tagged(_ el: Element, _ part: String) -> Element {
            var out = el
            out.group = group
            out.diagram = spec
            out.diagramPart = part
            return out
        }

        func words(_ i: Int) -> String {
            RichText.escapeLiteral([items[i].text, items[i].note].compactMap { $0 }.joined(separator: "\n"))
        }

        /// Item `i`'s shape, its words in it unless `bare`, painted in the
        /// style; a drawn `path` in its own 0…100 box where it has one.
        func shape(_ i: Int, _ shapeId: String, _ r: CGRect, bare: Bool = false, path: String? = nil) -> Element {
            let hex = colour(i)
            var el = Element.shape(shapeId, w: r.width, h: r.height)
            el.x = r.minX
            el.y = r.minY
            switch spec.style {
            case .solid:
                el.fill = .solid(hex)
            case .outline:
                el.fill = .clear
                el.stroke = hex
                el.strokeWidth = max(2, (min(r.width, r.height) * 0.03 + 0.5).rounded(.down))
            case .soft:
                el.fill = .solid(Diagrams.tint(hex))
            }
            if let path { el.pathData = path }
            if !bare {
                el.text = words(i)
                el.fontFamily = spec.font ?? "sans"
                el.fontSize = ShapeText.defaultFontSize(width: r.width, height: r.height)
                el.align = "center"
                el.vAlign = "middle"
                switch spec.style {
                case .solid: el.color = ShapeText.defaultInk(for: el.fill)
                case .outline: el.color = hex
                case .soft: el.color = ink
                }
            }
            return tagged(el, "item:\(i)")
        }

        /// Item `i`'s words beside its shape, in `r`.
        func label(_ i: Int, _ r: CGRect) -> Element {
            var t = Element.text(words(i), fontSize: ShapeText.defaultFontSize(width: r.width, height: r.height),
                                 w: r.width)
            t.x = r.minX
            t.y = r.minY
            t.h = r.height
            t.fontFamily = spec.font ?? "sans"
            t.color = ink
            t.vAlign = "middle"
            return tagged(t, "label:\(i)")
        }

        /// A line from `a` to `b`, following them; an arrow unless `plain`.
        func connector(_ k: Int, _ a: Element, _ b: Element, plain: Bool = false) -> Element {
            var line = Element.line(w: 100)
            line.connectFrom = a.id
            line.connectTo = b.id
            line.endCap = plain ? "none" : "arrow"
            line.color = ink
            line.thickness = max(2, (min(box.width, box.height) * 0.008 + 0.5).rounded(.down))
            return tagged(Connectors.laid(line, from: a.frame, to: b.frame), "connector:\(k)")
        }
    }

    /// `spec`'s parts in `box`: its items' shapes, labels and connectors,
    /// each tagged with the diagram and its part, all in `group`. Each item
    /// is painted in its own colour, else its place's in `spec`'s palette,
    /// else in `palette` (the page's or the brand's, DataGraphics.palette);
    /// lines and labels in `ink`. Nothing for a box with no room or no items.
    ///
    /// The layouts, in the box (x, y, w, h), n items:
    /// - venn2: circles of diameter d, centres 0.6 d apart; venn3: three of
    ///   diameter d, two 0.6 d apart along the foot and one 0.52 d above
    ///   their middle. Each fits its circles' bounds in the box at its own
    ///   shape, centred, at 0.7 opacity and blended by multiply. Each
    ///   circle's words are a label 0.4 d by 0.25 d centred 0.22 d out from
    ///   the middle of all of them, through its centre.
    /// - cycle: n circles 0.3 of a ring's diameter, round a ring from twelve
    ///   o'clock clockwise; their bounds fitted and centred as a Venn's; an
    ///   arrow from each to the next, the last to the first.
    /// - pyramid: n bands top to bottom, a gap of 0.02 h between, band i's
    ///   top w·i/n and foot w·(i+1)/n wide, centred; funnelSteps the same
    ///   upside down, band i from w·(1 − 0.6·i/n) to w·(1 − 0.6·(i+1)/n).
    /// - process: n boxes across the full height, gaps of 0.06 w between,
    ///   corners 0.1 of the shorter side, an arrow from each to the next.
    /// - timeline: n slots of w/n; in each a dot 0.16 h (at most half the
    ///   slot) across on the middle line, its words a label the slot wide
    ///   and 0.4 h tall, at the top for an even item and the foot for an odd
    ///   one; a line from each dot to the next.
    /// - orgChart: a row a level, boxes b tall with 0.6 b between rows; each
    ///   item with no item under it a box wide, 0.2 of one between, side by
    ///   side left to right; an item over others centred over its first and
    ///   last; a line from each to the item above it.
    /// - matrix2x2: two columns and as many rows as it takes, gaps of 0.03
    ///   of the shorter side.
    static func make(_ spec: DiagramSpec, in box: CGRect, palette: [String], ink: String = ShapeText.darkInk,
                     group: String = UID.make("grp")) -> [Element] {
        let n = spec.items.count
        guard n > 0, box.width > 0, box.height > 0 else { return [] }
        let chosen = spec.palette ?? palette
        let m = Maker(spec: spec, box: box, swatches: chosen.isEmpty ? ["#5a31f4"] : chosen, ink: ink, group: group)
        switch spec.kind {
        case .venn2, .venn3: return venn(m)
        case .cycle: return cycle(m)
        case .pyramid, .funnelSteps: return bands(m)
        case .process: return process(m)
        case .timeline: return timeline(m)
        case .orgChart: return org(m)
        case .matrix2x2: return matrix(m)
        }
    }

    private static func venn(_ m: Maker) -> [Element] {
        // Circles of diameter 1.
        let all: [(Double, Double)] = m.spec.kind == .venn2 ? [(-0.3, 0), (0.3, 0)] : [(0, -0.52), (-0.3, 0), (0.3, 0)]
        let centres = Array(all.prefix(m.items.count))
        let fit = fitted(centres.map { CGRect(x: $0.0 - 0.5, y: $0.1 - 0.5, width: 1, height: 1) }, in: m.box)
        let d = Double(fit[0].width)
        let gx = fit.reduce(0.0) { $0 + Double($1.minX + $1.width / 2) } / Double(fit.count)
        let gy = fit.reduce(0.0) { $0 + Double($1.minY + $1.height / 2) } / Double(fit.count)
        let shapes = fit.enumerated().map { i, r -> Element in
            var circle = m.shape(i, "circle", r, bare: true)
            circle.opacity = 0.7
            circle.blendMode = "multiply"
            return circle
        }
        let labels = fit.enumerated().map { i, r -> Element in
            let cx = Double(r.minX + r.width / 2), cy = Double(r.minY + r.height / 2)
            let dx = cx - gx, dy = cy - gy
            let length = (dx * dx + dy * dy).squareRoot()
            let len = length > 0 ? length : 1
            let lx = cx + dx / len * 0.22 * d
            let ly = cy + dy / len * 0.22 * d
            return m.label(i, CGRect(x: lx - 0.2 * d, y: ly - 0.125 * d, width: 0.4 * d, height: 0.25 * d))
        }
        return shapes + labels
    }

    private static func cycle(_ m: Maker) -> [Element] {
        let n = m.items.count
        // A ring of diameter 1, its circles 0.3 across, fitted.
        let node = 0.3
        let rects = (0..<n).map { i -> CGRect in
            let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(n)
            return CGRect(x: 0.5 * cos(a) - node / 2, y: 0.5 * sin(a) - node / 2, width: node, height: node)
        }
        let shapes = fitted(rects, in: m.box).enumerated().map { i, r in m.shape(i, "circle", r) }
        let arrows = shapes.indices.map { i in m.connector(i, shapes[i], shapes[(i + 1) % n]) }
        return shapes + arrows
    }

    private static func bands(_ m: Maker) -> [Element] {
        let n = m.items.count
        let box = m.box
        let w = Double(box.width), h = Double(box.height)
        let gap = h * 0.02
        let band = (h - gap * Double(n - 1)) / Double(n)
        return (0..<n).map { i -> Element in
            let top: Double, foot: Double
            if m.spec.kind == .pyramid {
                top = w * Double(i) / Double(n)
                foot = w * Double(i + 1) / Double(n)
            } else {
                top = w * (1 - 0.6 * Double(i) / Double(n))
                foot = w * (1 - 0.6 * Double(i + 1) / Double(n))
            }
            let wide = max(top, foot)
            let r = CGRect(x: Double(box.minX) + (w - wide) / 2, y: Double(box.minY) + Double(i) * (band + gap),
                           width: wide, height: band)
            // The band's outline in its own 0…100 box.
            let inTop = (wide - top) / 2 / wide * 100
            let inFoot = (wide - foot) / 2 / wide * 100
            let path = "M\(num(inTop)) 0L\(num(100 - inTop)) 0L\(num(100 - inFoot)) 100L\(num(inFoot)) 100Z"
            return m.shape(i, "rect", r, path: path)
        }
    }

    private static func process(_ m: Maker) -> [Element] {
        let n = m.items.count
        let box = m.box
        let gap = Double(box.width) * 0.06
        let cell = (Double(box.width) - gap * Double(n - 1)) / Double(n)
        let shapes = (0..<n).map { i -> Element in
            let left = Double(box.minX) + Double(i) * (cell + gap)
            var el = m.shape(i, "rect", CGRect(x: left, y: Double(box.minY), width: cell, height: Double(box.height)))
            el.radius = (min(cell, Double(box.height)) * 0.1 + 0.5).rounded(.down)
            return el
        }
        let arrows = (0..<(n - 1)).map { i in m.connector(i, shapes[i], shapes[i + 1]) }
        return shapes + arrows
    }

    private static func timeline(_ m: Maker) -> [Element] {
        let n = m.items.count
        let box = m.box
        let x = Double(box.minX), y = Double(box.minY), h = Double(box.height)
        let slot = Double(box.width) / Double(n)
        let dot = min(h * 0.16, slot * 0.5)
        let labelH = h * 0.4
        let mid = y + h / 2
        let dots = (0..<n).map { i in
            m.shape(i, "circle", CGRect(x: x + slot * (Double(i) + 0.5) - dot / 2, y: mid - dot / 2, width: dot, height: dot),
                    bare: true)
        }
        let labels = (0..<n).map { i in
            m.label(i, CGRect(x: x + slot * Double(i), y: i % 2 == 0 ? y : y + h - labelH, width: slot, height: labelH))
        }
        let lines = (0..<(n - 1)).map { i in m.connector(i, dots[i], dots[i + 1], plain: true) }
        return dots + labels + lines
    }

    private static func org(_ m: Maker) -> [Element] {
        let levels = Diagrams.levels(m.spec)
        let n = levels.count
        let box = m.box
        // The item each one hangs from: the nearest before it a level up.
        let parent: [Int?] = (0..<n).map { i in (0..<i).reversed().first { levels[$0] == levels[i] - 1 } }
        let children: [[Int]] = (0..<n).map { p in (0..<n).filter { parent[$0] == p } }
        let leaves = (0..<n).filter { children[$0].isEmpty }
        let depth = (levels.max() ?? 0) + 1
        let bw = Double(box.width) / (Double(leaves.count) + Double(leaves.count - 1) * 0.2)
        let bh = Double(box.height) / (Double(depth) + Double(depth - 1) * 0.6)
        var centre = [Double](repeating: 0, count: n)
        // Leaves left to right, then each parent over its first and last child.
        for (k, leaf) in leaves.enumerated() { centre[leaf] = Double(box.minX) + bw / 2 + Double(k) * bw * 1.2 }
        for i in (0..<n).reversed() {
            if let first = children[i].first, let last = children[i].last { centre[i] = (centre[first] + centre[last]) / 2 }
        }
        let shapes = (0..<n).map { i -> Element in
            let r = CGRect(x: centre[i] - bw / 2, y: Double(box.minY) + Double(levels[i]) * bh * 1.6, width: bw, height: bh)
            var el = m.shape(i, "rect", r)
            el.radius = (min(bw, bh) * 0.1 + 0.5).rounded(.down)
            return el
        }
        let lines = (0..<n).compactMap { i in parent[i].map { m.connector(i, shapes[$0], shapes[i], plain: true) } }
        return shapes + lines
    }

    private static func matrix(_ m: Maker) -> [Element] {
        let n = m.items.count
        let box = m.box
        let rows = (n + 1) / 2
        let gap = min(Double(box.width), Double(box.height)) * 0.03
        let cw = (Double(box.width) - gap) / 2
        let ch = (Double(box.height) - gap * Double(rows - 1)) / Double(rows)
        return (0..<n).map { i -> Element in
            let r = CGRect(x: Double(box.minX) + Double(i % 2) * (cw + gap), y: Double(box.minY) + Double(i / 2) * (ch + gap),
                           width: cw, height: ch)
            var el = m.shape(i, "rect", r)
            el.radius = (min(cw, ch) * 0.06 + 0.5).rounded(.down)
            return el
        }
    }

    /// `rects`, laid out in units of their own, scaled alike to fit `box`
    /// and centred in it.
    private static func fitted(_ rects: [CGRect], in box: CGRect) -> [CGRect] {
        guard let first = rects.first else { return [] }
        let bounds = rects.dropFirst().reduce(first) { $0.union($1) }
        let scale = min(box.width / bounds.width, box.height / bounds.height)
        let ox = box.minX + (box.width - bounds.width * scale) / 2
        let oy = box.minY + (box.height - bounds.height * scale) / 2
        return rects.map {
            CGRect(x: ox + ($0.minX - bounds.minX) * scale, y: oy + ($0.minY - bounds.minY) * scale,
                   width: $0.width * scale, height: $0.height * scale)
        }
    }

    /// The box diagram `id`'s items and labels fill on `page` — the box it
    /// was made in — or nil when it has none there.
    static func frame(of id: String, on page: Page) -> CGRect? {
        let parts = members(page, id: id).filter { !($0.diagramPart ?? "").hasPrefix("connector:") }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    /// Diagram `spec` made again where `spec.id`'s parts stand on `page`: in
    /// the box they fill (`frame`) and in their group. The colours the
    /// person gave its items stay with them when `spec` was `pinned` to the
    /// parts first, as charts keep theirs (DataGraphics.keepingPalette). Nil
    /// when it is not on the page.
    static func remade(on page: Page, _ spec: DiagramSpec, palette: [String], ink: String = ShapeText.darkInk) -> [Element]? {
        guard let box = frame(of: spec.id, on: page) else { return nil }
        let group = members(page, id: spec.id).lazy.compactMap(\.group).first ?? UID.make("grp")
        return make(spec, in: box, palette: palette, ink: ink, group: group)
    }

    /// `page` with diagram `id`'s parts replaced by `made`, which take the
    /// place of the lowest of them in the page's order.
    static func replacing(_ page: Page, id: String, with made: [Element]) -> Page {
        guard let at = page.elements.firstIndex(where: { $0.diagram?.id == id }) else { return page }
        var out = page
        let after = page.elements[at...].filter { $0.diagram?.id != id }
        out.elements = Array(page.elements[..<at]) + made + after
        return out
    }

    /// A number as a drawn path writes it, to the hundredth — the Android
    /// twin's Freehand.num, which rounds a half up as Swift does.
    private static func num(_ v: Double) -> String {
        ShapeGeometry.num(v)
    }
}
