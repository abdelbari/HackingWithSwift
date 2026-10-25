// Quick flow: a + beside each side of a selected shape or sticky note adds
// a copy of it that way, joined to it by a connector, ready to type into —
// Canva's quick flow, and the Android twin's QuickFlow, with the same rows
// (Fixtures/quick_flow.json). Dragged instead, the + draws the connector to
// the finger: let go on another element, the line ties to it; on empty
// space, the copy goes there. No new keys: the copy is an ordinary shape,
// the connector an ordinary line tied by `connectFrom` and `connectTo`.

import CoreGraphics
import Foundation

enum QuickFlow {

    /// The four ways a copy can go, in the order VoiceOver offers them.
    enum Side: String, CaseIterable {
        case top, right, bottom, left

        /// One step that way, in page units: x and y, each -1, 0 or 1.
        var step: (dx: Double, dy: Double) {
            switch self {
            case .top: return (0, -1)
            case .right: return (1, 0)
            case .bottom: return (0, 1)
            case .left: return (-1, 0)
            }
        }

        /// VoiceOver's action, and the key's name, for this side.
        var actionName: String {
            switch self {
            case .top: return tr("Add connected shape above")
            case .right: return tr("Add connected shape right")
            case .bottom: return tr("Add connected shape below")
            case .left: return tr("Add connected shape left")
            }
        }
    }

    /// The undo step a quick-flow add is named.
    static var stepName: String { tr("Add connected shape") }

    /// The gap between a shape and its copy: at least this, in page units…
    static let minGap = 40.0
    /// …or this share of the shape's side along the way it goes, if more.
    static let gapShare = 0.5
    /// How many times a copy that would overlap something moves on, by its
    /// own size, before it stays where it got to.
    static let moves = 3
    /// The connector's look when the page has no connector to copy: a
    /// 2-unit line in the ink, ending in an arrow.
    static let defaultThickness = 2.0
    /// Each + is a disc this many points across, its near edge this many
    /// points beyond the handle ring.
    static let discSize = 22.0
    static let discGap = 20.0

    /// Whether `el`, selected alone, offers quick flow: a shape that takes
    /// words — a sticky note among them — shown and free to move, and not
    /// part of a table, a chart or a photo grid.
    static func offers(_ el: Element) -> Bool {
        el.type == .shape && ShapeText.takesText(el) && !el.holdsPlace && !el.isHidden
            && el.table == nil && el.chartPart == nil && el.grid == nil
    }

    /// Where the copy of `source` going `side` lands on `page`, of size
    /// `frame`: kept inside the page — but not on a whiteboard, which grows
    /// to take it, as its bounds follow what is on it.
    static func place(_ source: Element, side: Side, page: Page, frame: CGSize) -> CGRect {
        place(source, side: side, page: page, bounds: Whiteboards.isExpanded(page) ? nil : CGRect(origin: .zero, size: frame))
    }

    /// place(_:side:obstacles:bounds:) from the source's unturned frame —
    /// the copy keeping its turn — with every other shown element's turned
    /// box in the way, kept inside `bounds` when there are any.
    static func place(_ source: Element, side: Side, page: Page, bounds: CGRect?) -> CGRect {
        let others = page.elements.filter { $0.id != source.id && !$0.isHidden }.map(Geometry.aabb)
        return place(source.frame, side: side, obstacles: others, bounds: bounds)
    }

    /// A box the size of `source`, `side` of it with a gap of max(40, half
    /// the source's side along that way) between them. While it overlaps
    /// one of `obstacles` — sharing area, not just an edge — it moves on
    /// that way by its own size, up to `moves` times, and stays where it
    /// got to. Last, it is kept inside `bounds`, when given: pushed back in
    /// on each axis, to the left or top edge when it is the wider.
    static func place(_ source: CGRect, side: Side, obstacles: [CGRect], bounds: CGRect?) -> CGRect {
        let w = Double(source.width), h = Double(source.height)
        let along = side == .left || side == .right ? w : h
        let gap = max(minGap, gapShare * along)
        let step = side.step
        var box = CGRect(x: Double(source.minX) + step.dx * (w + gap), y: Double(source.minY) + step.dy * (h + gap),
                         width: w, height: h)
        var moved = 0
        while moved < moves && obstacles.contains(where: { overlaps($0, box) }) {
            box = box.offsetBy(dx: step.dx * w, dy: step.dy * h)
            moved += 1
        }
        guard let bounds else { return box }
        return kept(box, inside: bounds)
    }

    /// Whether two boxes share some area: touching edges do not.
    static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }

    /// `box` moved the least that puts it inside `bounds` on each axis; on
    /// an axis where it is the wider, its left or top on the bounds'.
    static func kept(_ box: CGRect, inside bounds: CGRect) -> CGRect {
        func axis(_ start: Double, _ size: Double, _ low: Double, _ high: Double) -> Double {
            size >= high - low ? low : min(max(start, low), high - size)
        }
        let x = axis(Double(box.minX), Double(box.width), Double(bounds.minX), Double(bounds.maxX))
        let y = axis(Double(box.minY), Double(box.height), Double(bounds.minY), Double(bounds.maxY))
        return CGRect(x: x, y: y, width: box.width, height: box.height)
    }

    /// The copy: the same kind of shape with the same fill, border, corners
    /// and type, at `box`, under a new id and with no words — nor the
    /// source's group, ties, link, name or description, which are its own.
    static func copy(of source: Element, at box: CGRect) -> Element {
        var copy = ShapeText.withoutWords(source, was: nil)
        copy.id = UID.make()
        copy.x = Double(box.minX)
        copy.y = Double(box.minY)
        copy.spans = nil
        copy.spansText = nil
        copy.paragraphs = nil
        copy.paragraphsText = nil
        copy.group = nil
        copy.subgroups = nil
        copy.groupTurn = nil
        copy.connectFrom = nil
        copy.connectTo = nil
        copy.link = nil
        copy.altText = nil
        copy.altTextSource = nil
        copy.layerName = nil
        copy.bulkField = nil
        return copy
    }

    /// The page's last connector — a line tied at both ends — whose look a
    /// new one takes; nil when it has none.
    static func lastConnector(on page: Page) -> Element? {
        page.elements.last { $0.type == .line && $0.connectFrom != nil && $0.connectTo != nil }
    }

    /// A straight line from `from` to `to`, tied to both (`connectFrom`,
    /// `connectTo`) and laid edge to edge (Connectors.laid): in the colour,
    /// weight, dash, ends and transparency of `style` — the page's last
    /// connector — or, with none, 2 units of ink ending in an arrow.
    static func connector(from: Element, to: Element, style: Element?) -> Element {
        var line = Element.line(w: 100)
        line.thickness = defaultThickness
        line.endCap = "arrow"
        if let style {
            line.color = style.color
            line.thickness = style.thickness
            line.dash = style.dash
            line.startCap = style.startCap
            line.endCap = style.endCap
            line.capScale = style.capScale
            line.opacity = style.opacity
        }
        line.connectFrom = from.id
        line.connectTo = to.id
        return Connectors.laid(line, from: from.frame, to: to.frame)
    }

    /// What a + dragged and let go at `point` ties to: the topmost shown
    /// element there that is not the source nor a line — a locked one too,
    /// which a connector tied to it does not move; a line on top is passed
    /// over for what lies under it. Nil over empty space, where the copy
    /// goes instead. The Android twin's QuickFlow.dropTarget, with the same
    /// rows (Fixtures/quick_flow_drop.json).
    static func dropTarget(_ elements: [Element], source: String, at point: CGPoint) -> Element? {
        elements.last { $0.id != source && $0.type != .line && !$0.isHidden && Geometry.hits($0, point: point) }
    }

    /// The copy's box let go at `point` over empty space: the source's
    /// size, centred there.
    static func centred(_ source: Element, at point: CGPoint) -> CGRect {
        CGRect(x: Double(point.x) - source.w / 2, y: Double(point.y) - source.h / 2, width: source.w, height: source.h)
    }

    /// Where a side's + sits round `box` — the shape's page-axis box
    /// (Geometry.aabb), not turned with it, as on the Android twin — so the
    /// + is always on the side its copy goes: `distance` page units out from
    /// the middle of that side.
    static func discPoint(_ box: CGRect, side: Side, distance: Double) -> CGPoint {
        let step = side.step
        let reach = side == .left || side == .right ? Double(box.width) / 2 + distance : Double(box.height) / 2 + distance
        return CGPoint(x: Double(box.midX) + step.dx * reach, y: Double(box.midY) + step.dy * reach)
    }

    /// Which side of `box` — the shape's page-axis box, round which the +s
    /// stand — the turn handle at `handle` is on: the way the line from the
    /// box's middle to it runs most, top or bottom on a tie. That side's +
    /// stands past the turn handle, wherever the shape's turn has taken it.
    /// The Android twin's QuickFlow.turnedSide, with the same rows
    /// (Fixtures/quick_flow_turned.json).
    static func turnedSide(_ box: CGRect, handle: CGPoint) -> Side {
        let dx = Double(handle.x - box.midX)
        let dy = Double(handle.y - box.midY)
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy < 0 ? .top : .bottom
    }
}
