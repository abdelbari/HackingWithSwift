// Where a line runs, and dragging its ends — the Android twin's LineRoutes,
// rule for rule, with the same test rows.
//
// A straight line runs across the middle of its box, left to right, turned
// by its rotation (a flip across swaps which end is which). An elbowed or
// curved line (`lineType` "elbow" or "curve") keeps rotation 0 and its ends
// as `ends`, [x1, y1, x2, y2], fractions of its box; its box is the ends'
// bounds padded by its thickness. `bend`, -1 to 1 and 0 unless written, is
// where an elbow's corner sits between the ends' x (-1 at the start's, 1 at
// the end's) and how far a curve bows from the straight line between its
// ends, as a share of that line's length — to its right, as it runs from
// start to end (below a line run left to right).
//
// - Elbow: start, (corner x, y1), (corner x, y2), end.
// - Curve: a quadratic through the bend point, halfway along.
// - Arrowheads point along the first and the last segment.
//
// An end dragged (endDragged) moves anywhere, the other end holding still:
// its angle from the other end snaps to a multiple of 15 degrees within 3,
// and the end itself to another element's edge midpoints and centre —
// which, let go there, ties the line to that element (tied), under the
// existing `connectFrom` (start) and `connectTo` (end).

import CoreGraphics
import Foundation

enum LineRoutes {

    /// How a line runs between its ends, by its `lineType` and the word the
    /// Line panel shows; straight has no key.
    enum RouteType: String, CaseIterable, Identifiable {
        case straight, elbow, curve

        var id: String { rawValue }
        /// The `lineType` written for it; none for straight.
        var key: String? { self == .straight ? nil : rawValue }
        var label: String {
            switch self {
            case .straight: return "Straight"
            case .elbow: return "Elbow"
            case .curve: return "Curve"
            }
        }
    }

    /// The bend a line made a curve is given when it had none, so the curve
    /// shows: a quarter of its length.
    static let curveBend = 0.25

    /// Within `angleReach` degrees of a multiple of `angleStep`, a dragged
    /// end's angle is held on it.
    static let angleStep = 15.0
    static let angleReach = 3.0

    static func routeType(of el: Element) -> RouteType {
        guard el.type == .line else { return .straight }
        switch el.lineType {
        case "elbow": return .elbow
        case "curve": return .curve
        default: return .straight
        }
    }

    /// `el`'s bend, held to -1…1; 0 when it has none.
    static func bend(of el: Element) -> Double {
        guard let bend = el.bend, bend.isFinite else { return 0 }
        return min(max(bend, -1), 1)
    }

    /// An elbowed or curved line's ends as fractions of its box; the middle
    /// of its left and right sides when it has none to read.
    static func fractions(of el: Element) -> [Double] {
        guard let ends = el.ends, ends.count == 4, ends.allSatisfy(\.isFinite) else { return [0, 0.5, 1, 0.5] }
        return ends
    }

    /// Whether the selection shows `el`'s ends as discs to drag: a line,
    /// unless both its ends are tied, when it is laid from its elements.
    static func hasEndHandles(_ el: Element) -> Bool {
        el.type == .line && !(el.connectFrom != nil && el.connectTo != nil)
    }

    /// Whether `el` keeps rotation 0, and so offers no turn handle: an
    /// elbowed or curved line.
    static func keepsLevel(_ el: Element) -> Bool {
        routeType(of: el) != .straight
    }

    // MARK: the ends on the page

    /// A point of `el`'s own box (origin its top left) on the page: flipped
    /// and turned as the element is drawn.
    static func toPage(_ el: Element, _ local: CGPoint) -> CGPoint {
        var dx = Double(local.x) - el.w / 2
        var dy = Double(local.y) - el.h / 2
        if el.flipH { dx = -dx }
        if el.flipV { dy = -dy }
        let c = el.center
        let a = el.rotation * .pi / 180
        return CGPoint(x: Double(c.x) + dx * cos(a) - dy * sin(a), y: Double(c.y) + dx * sin(a) + dy * cos(a))
    }

    /// `el`'s two ends in its own box: a straight line's across its middle,
    /// an elbowed or curved one's where its fractions put them.
    static func localEnds(_ el: Element) -> (start: CGPoint, end: CGPoint) {
        guard routeType(of: el) != .straight else {
            return (CGPoint(x: 0, y: el.h / 2), CGPoint(x: el.w, y: el.h / 2))
        }
        let f = fractions(of: el)
        return (CGPoint(x: f[0] * el.w, y: f[1] * el.h), CGPoint(x: f[2] * el.w, y: f[3] * el.h))
    }

    /// `el`'s start and end on the page.
    static func ends(of el: Element) -> (start: CGPoint, end: CGPoint) {
        let local = localEnds(el)
        return (toPage(el, local.start), toPage(el, local.end))
    }

    /// `el` running from `start` to `end` on the page, unflipped. A straight
    /// line: centred between them, as long as they are apart (at least 1),
    /// its height kept, turned to point from start to end. An elbowed or
    /// curved one: its box the ends' bounds padded by its thickness, its
    /// ends the fractions of it they are, rotation 0.
    static func withEnds(_ el: Element, _ start: CGPoint, _ end: CGPoint) -> Element {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        var out = el
        out.flipH = false
        out.flipV = false
        if routeType(of: el) == .straight {
            let w = max(hypot(dx, dy), 1)
            let degrees = atan2(dy, dx) * 180 / .pi
            out.x = Double(start.x + end.x) / 2 - w / 2
            out.y = Double(start.y + end.y) / 2 - el.h / 2
            out.w = w
            out.rotation = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            return out
        }
        let pad = max(el.thickness ?? 4, 1)
        let x = Double(min(start.x, end.x)) - pad
        let y = Double(min(start.y, end.y)) - pad
        let w = abs(dx) + 2 * pad
        let h = abs(dy) + 2 * pad
        out.x = x
        out.y = y
        out.w = w
        out.h = h
        out.rotation = 0
        out.ends = [(Double(start.x) - x) / w, (Double(start.y) - y) / h, (Double(end.x) - x) / w, (Double(end.y) - y) / h]
        return out
    }

    /// `el` made a `type` of line, its ends where they were on the page: an
    /// elbowed or curved one written with its ends; a straight one with no
    /// ends or bend, at least 8 tall, as a connector is laid. A line made a
    /// curve with no bend is given curveBend, or it would draw straight.
    static func withType(_ el: Element, _ type: RouteType) -> Element {
        guard el.type == .line, routeType(of: el) != type else { return el }
        let was = ends(of: el)
        var typed = el
        typed.lineType = type.key
        typed.ends = nil
        if type == .straight {
            typed.bend = nil
            typed.h = max(8, el.thickness ?? 4)
        }
        if type == .curve && bend(of: el) == 0 { typed.bend = curveBend }
        return withEnds(typed, was.start, was.end)
    }

    /// `el` with its bend at `bend`, -1 to 1; none written for 0.
    static func withBend(_ el: Element, _ bend: Double) -> Element {
        var out = el
        let b = min(max(bend.isFinite ? bend : 0, -1), 1)
        out.bend = b == 0 ? nil : b
        return out
    }

    /// `el` `thickness` thick, or with none written: a straight line at
    /// least 8 tall, as tall as its weight (its height kept with none); an
    /// elbowed or curved one laid round the same ends again, its box their
    /// bounds padded by its new weight — so a weight changed, or a style
    /// pasted on, never squashes its route.
    static func withThickness(_ el: Element, _ thickness: Double?) -> Element {
        var out = el
        out.thickness = thickness
        guard keepsLevel(el) else {
            if let thickness { out.h = max(8, thickness) }
            return out
        }
        let was = ends(of: el)
        return withEnds(out, was.start, was.end)
    }

    /// `el` mirrored in place across its box's middle — horizontally or not
    /// — as flipping several things together mirrors a line: an elbowed or
    /// curved line's ends mirrored within its box, a curve bowing the other
    /// way. A straight line is itself (Geometry.flipAll swaps its ends).
    static func mirrored(_ el: Element, horizontal: Bool) -> Element {
        let type = routeType(of: el)
        guard type != .straight else { return el }
        let f = fractions(of: el)
        var out = el
        out.ends = horizontal ? [1 - f[0], f[1], 1 - f[2], f[3]] : [f[0], 1 - f[1], f[2], 1 - f[3]]
        return type == .curve ? withBend(out, -bend(of: el)) : out
    }

    /// How far a curve bows out of its box at most: its bend times the
    /// distance between its ends; 0 for any other line.
    static func bow(_ el: Element) -> Double {
        guard routeType(of: el) == .curve else { return 0 }
        let local = localEnds(el)
        return abs(bend(of: el)) * Double(hypot(local.end.x - local.start.x, local.end.y - local.start.y))
    }

    // MARK: the route

    /// How a line is drawn in its own box: its points — two for a straight
    /// line, four for an elbow, and for a curve its start, the quadratic's
    /// control point and its end (`curved`) — and each end's tip with the
    /// way an arrowhead there points, in radians (0 along +x, y down).
    struct Route: Equatable {
        var points: [CGPoint]
        var curved: Bool
        var start: CGPoint
        var startAngle: Double
        var end: CGPoint
        var endAngle: Double
    }

    static func route(_ el: Element) -> Route {
        let local = localEnds(el)
        let a = local.start, b = local.end
        let points: [CGPoint]
        switch routeType(of: el) {
        case .straight:
            points = [a, b]
        case .elbow:
            let x = Double(a.x) + Double(b.x - a.x) * (1 + bend(of: el)) / 2
            points = [a, CGPoint(x: x, y: a.y), CGPoint(x: x, y: b.y), b]
        case .curve:
            points = [a, control(a, b, bend: bend(of: el)), b]
        }
        return Route(points: points, curved: routeType(of: el) == .curve,
                     start: a, startAngle: outward(points, atStart: true),
                     end: b, endAngle: outward(points, atStart: false))
    }

    /// The control point of a quadratic from `a` to `b` passing through the
    /// point `bend` of their distance to the right of their middle.
    static func control(_ a: CGPoint, _ b: CGPoint, bend: Double) -> CGPoint {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let throughX = Double(mid.x) - Double(b.y - a.y) * bend
        let throughY = Double(mid.y) + Double(b.x - a.x) * bend
        return CGPoint(x: 2 * throughX - Double(mid.x), y: 2 * throughY - Double(mid.y))
    }

    /// The way an end's arrowhead points: from the nearest other point of
    /// the route that is not on it, out through the end.
    private static func outward(_ points: [CGPoint], atStart: Bool) -> Double {
        let ordered = atStart ? points : points.reversed()
        guard let tip = ordered.first else { return 0 }
        guard let from = ordered.dropFirst().first(where: { $0 != tip }) else { return atStart ? .pi : 0 }
        return atan2(Double(tip.y - from.y), Double(tip.x - from.x))
    }

    /// `route`'s stroke, its ends drawn back `startBack` and `endBack` along
    /// their first and last segments — where an arrowhead's tip is the end
    /// — never past the segment's other end.
    static func trimmed(_ route: Route, startBack: Double, endBack: Double) -> [CGPoint] {
        var points = route.points
        func back(_ i: Int, _ next: Int, _ by: Double) {
            guard by > 0, points.indices.contains(i), points.indices.contains(next) else { return }
            let p = points[i], q = points[next]
            let length = Double(hypot(q.x - p.x, q.y - p.y))
            guard length > 0 else { return }
            let t = min(by, length) / length
            points[i] = CGPoint(x: Double(p.x) + Double(q.x - p.x) * t, y: Double(p.y) + Double(q.y - p.y) * t)
        }
        back(0, 1, startBack)
        back(points.count - 1, points.count - 2, endBack)
        return points
    }

    /// An arrowhead `size` long with its tip at `tip`, pointing `angle`: the
    /// tip, then its two back corners, each 0.6 of `size` aside.
    static func arrowhead(tip: CGPoint, angle: Double, size: Double) -> [CGPoint] {
        let c = cos(angle), s = sin(angle)
        func at(_ along: Double, _ across: Double) -> CGPoint {
            CGPoint(x: Double(tip.x) + along * c - across * s, y: Double(tip.y) + along * s + across * c)
        }
        return [tip, at(-size, -size * 0.6), at(-size, size * 0.6)]
    }

    /// A dot's centre for an end at `tip` pointing `angle`: one thickness
    /// `t` in from it, as a straight line's dot sits.
    static func dotCentre(tip: CGPoint, angle: Double, t: Double) -> CGPoint {
        CGPoint(x: Double(tip.x) - cos(angle) * t, y: Double(tip.y) - sin(angle) * t)
    }

    /// An arrowhead's length for a line `t` thick, as every line draws it.
    static func arrowSize(_ t: Double) -> Double { max(t * 3, 10) }

    /// A dot's radius at a line's end, for a line `t` thick.
    static func dotRadius(_ t: Double) -> Double { max(t * 1.4, 5) }

    /// How far the stroke stops short of an end with an arrowhead (`cap`):
    /// 0.9 of the head, so the head's point is the end.
    static func strokeBack(_ el: Element, cap: String?) -> Double {
        cap == "arrow" ? arrowSize(max(el.thickness ?? 4, 0.5)) * 0.9 : 0
    }

    // MARK: dragging an end

    /// An end dragged: the line as it is now, the element the end has
    /// snapped to (and would be tied to, let go) if any, whether the end or
    /// its angle is held on a snap, and the line's length and angle (0 to
    /// 360, clockwise from +x) for the readout.
    struct EndDrag {
        var line: Element
        var target: String?
        var snapped: Bool
        var length: Double
        var angle: Double
    }

    /// `line`'s start (or, not `atStart`, its end) dragged to `pointer`, the
    /// other end held: on the nearest edge midpoint or centre of `others`
    /// within `reach` — not of a line, nor of what the other end is tied to
    /// — else at an angle from the other end held on a multiple of 15
    /// degrees within 3. The dragged end lets go of what it was tied to.
    static func endDragged(_ line: Element, atStart: Bool, pointer: CGPoint, others: [Element],
                           reach: Double) -> EndDrag {
        let now = ends(of: line)
        let fixed = atStart ? now.end : now.start
        let otherTie = atStart ? line.connectTo : line.connectFrom
        var best: (point: CGPoint, id: String)?
        var bestDistance = reach
        for el in others where el.id != line.id && el.type != .line && el.id != otherTie {
            for p in snapPoints(el) {
                let d = Double(hypot(p.x - pointer.x, p.y - pointer.y))
                if d <= bestDistance {
                    bestDistance = d
                    best = (point: p, id: el.id)
                }
            }
        }
        var moved = best?.point ?? pointer
        var snapped = best != nil
        let length = Double(hypot(moved.x - fixed.x, moved.y - fixed.y))
        let raw = atan2(Double(moved.y - fixed.y), Double(moved.x - fixed.x)) * 180 / .pi
        var angle = (raw.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        if best == nil && length > 0 {
            let nearest = (angle / angleStep).rounded() * angleStep
            if abs(angle - nearest) <= angleReach {
                angle = nearest.truncatingRemainder(dividingBy: 360)
                let r = angle * .pi / 180
                moved = CGPoint(x: Double(fixed.x) + cos(r) * length, y: Double(fixed.y) + sin(r) * length)
                snapped = true
            }
        }
        let freed = tied(line, atStart: atStart, to: nil)
        let drawn = atStart ? withEnds(freed, moved, fixed) : withEnds(freed, fixed, moved)
        // The angle the line runs at, start to end, whichever end moved.
        let runs = atStart ? (angle + 180).truncatingRemainder(dividingBy: 360) : angle
        return EndDrag(line: drawn, target: best?.id, snapped: snapped, length: length, angle: runs)
    }

    /// Where an end snaps to on `el`: the middle of each edge and its
    /// centre, turned with it.
    static func snapPoints(_ el: Element) -> [CGPoint] {
        let c = el.center
        let offsets: [(Double, Double)] = [(0, -el.h / 2), (el.w / 2, 0), (0, el.h / 2), (-el.w / 2, 0), (0, 0)]
        let a = el.rotation * .pi / 180
        return offsets.map { o in
            CGPoint(x: Double(c.x) + o.0 * cos(a) - o.1 * sin(a), y: Double(c.y) + o.0 * sin(a) + o.1 * cos(a))
        }
    }

    /// `line` with its start (`connectFrom`) or end (`connectTo`) tied to
    /// the element `target`, or let go of with nil.
    static func tied(_ line: Element, atStart: Bool, to target: String?) -> Element {
        var out = line
        if atStart { out.connectFrom = target } else { out.connectTo = target }
        return out
    }

    /// The readout while an end is dragged: its length, whole, and its
    /// angle, whole degrees — "240 · 45°".
    static func readout(_ drag: EndDrag) -> String {
        "\(Int(drag.length.rounded())) · \(Int(drag.angle.rounded()) % 360)°"
    }
}
