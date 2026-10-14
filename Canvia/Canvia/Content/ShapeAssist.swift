// Shape assist: a stroke held still at its end becomes the clean shape it
// was trying to be — a straight line, an arrow, an ellipse, a rectangle or
// a triangle — made of the elements the app already has, so it is edited
// as any other line or shape afterwards. The rules are pure and written for
// both phones alike, number for number over the same test strokes.

import CoreGraphics
import Foundation

enum ShapeAssist {

    enum Kind: String, CaseIterable {
        case line, arrow, ellipse, rectangle, triangle
    }

    /// What a stroke was read as: its kind and where it is on the page. A
    /// line or an arrow runs from `start` to `end`; an ellipse or a triangle
    /// fills `frame`, upright; a rectangle fills `frame` turned `rotation`
    /// degrees about its centre.
    struct Snap: Equatable {
        var kind: Kind
        var start: CGPoint = .zero
        var end: CGPoint = .zero
        var frame: CGRect = .zero
        var rotation: Double = 0
    }

    // MARK: the rules

    /// How long the finger rests at the end of a stroke before it snaps,
    /// and how far it may wander meanwhile, in points on the screen.
    static let holdSeconds = 0.5
    static let holdSlop = 6.0
    /// The setting's key: Shape assist on (the default) or off.
    static let key = "drawShapeAssist"

    /// A line strays from the straight between its ends by less than this
    /// share of its length.
    static let lineDeviation = 0.04
    /// A closed stroke's ends are nearer together than this share of its
    /// length.
    static let closedGap = 0.15
    /// An ellipse's points are, on average, within this share of the
    /// ellipse filling the stroke's bounds.
    static let ellipseResidual = 0.12
    /// A rectangle's corners are each within this many degrees of square.
    static let cornerTolerance = 20.0
    /// A triangle's corners are each at least this many degrees.
    static let thinnestCorner = 20.0
    /// The simplification's tolerance, as a share of the stroke's larger
    /// side, and how little a corner may turn to stay one.
    static let simplify = 0.05
    static let shallowTurn = 30.0
    /// A stroke shorter than this, in page units, is a dot: never a shape.
    static let shortest = 8.0

    /// Whether the finger, come to rest at `rest`, has moved on at `point`
    /// (page units, the canvas at `zoom`): holdSlop points on the screen
    /// or more. Until it has for holdSeconds, it rests.
    static func movedOn(from rest: CGPoint, to point: CGPoint, zoom: Double) -> Bool {
        hypot(Double(point.x - rest.x), Double(point.y - rest.y)) >= holdSlop / max(zoom, 0.01)
    }

    /// The shape `raw` (page units) was trying to be, or nil: tried in
    /// turn as a line, an arrow, then — when its ends meet — a rectangle or
    /// a triangle, then an ellipse.
    static func classify(_ raw: [CGPoint]) -> Snap? {
        let points = Freehand.thinned(raw)
        guard points.count >= 2, length(points) >= shortest,
              let first = points.first, let last = points.last else { return nil }
        let bounds = boundsOf(points)
        let side = max(Double(bounds.width), Double(bounds.height))
        if let line = asLine(points) { return line }
        let gap = hypot(Double(last.x - first.x), Double(last.y - first.y))
        if gap < closedGap * length(points) {
            var ring = points
            if ring.count > 2, gap < side * simplify { ring.removeLast() }
            let corners = closedCorners(ring, tolerance: side * simplify)
            if corners.count == 4, let rect = asRectangle(corners) { return rect }
            if corners.count == 3, isTriangle(corners) {
                return Snap(kind: .triangle, frame: boundsOf(corners))
            }
            if fitsEllipse(ring, in: bounds) { return Snap(kind: .ellipse, frame: bounds) }
            return nil
        }
        return asArrow(points, tolerance: side * simplify)
    }

    /// A line: no point further from the straight between the ends than
    /// lineDeviation of its length.
    static func asLine(_ points: [CGPoint]) -> Snap? {
        guard let a = points.first, let b = points.last else { return nil }
        let chord = hypot(Double(b.x - a.x), Double(b.y - a.y))
        guard chord >= shortest else { return nil }
        let far = points.map { MaskRaster.distance($0, a, b) }.max() ?? 0
        return far < lineDeviation * chord ? Snap(kind: .line, start: a, end: b) : nil
    }

    /// An arrow: a shaft and, at its far end, a head of two strokes. Read
    /// from the simplified stroke: its first leg is the shaft, from A to the
    /// tip B; of the corners after it, those not back at the tip (within
    /// 15% of the shaft) must be exactly two, each within half the shaft of
    /// the tip, both behind it, one either side of the shaft.
    static func asArrow(_ points: [CGPoint], tolerance: Double) -> Snap? {
        let corners = pruned(simplified(points, tolerance: tolerance), closed: false, tolerance: tolerance)
        guard corners.count >= 4, corners.count <= 5 else { return nil }
        let a = corners[0], b = corners[1]
        let shaft = hypot(Double(b.x - a.x), Double(b.y - a.y))
        guard shaft >= shortest else { return nil }
        let head = corners.dropFirst(2).filter { hypot(Double($0.x - b.x), Double($0.y - b.y)) > 0.15 * shaft }
        guard head.count == 2 else { return nil }
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        var sides: [Double] = []
        for p in head {
            let px = Double(p.x - b.x), py = Double(p.y - b.y)
            guard hypot(px, py) <= 0.5 * shaft, px * dx + py * dy < 0 else { return nil }
            sides.append(dx * py - dy * px)
        }
        guard sides[0] * sides[1] < 0 else { return nil }
        return Snap(kind: .arrow, start: a, end: b)
    }

    /// A rectangle: four corners, each within cornerTolerance of square;
    /// turned as its first side runs, brought within ±45°, and as big as its
    /// corners reach along its sides.
    static func asRectangle(_ corners: [CGPoint]) -> Snap? {
        guard corners.count == 4, corners.indices.allSatisfy({ abs(angle(at: $0, of: corners) - 90) <= cornerTolerance })
        else { return nil }
        let first = atan2(Double(corners[1].y - corners[0].y), Double(corners[1].x - corners[0].x)) * 180 / .pi
        var turn = first.truncatingRemainder(dividingBy: 90)
        if turn > 45 { turn -= 90 }
        if turn <= -45 { turn += 90 }
        let cx = corners.map { Double($0.x) }.reduce(0, +) / 4
        let cy = corners.map { Double($0.y) }.reduce(0, +) / 4
        let r = turn * .pi / 180
        let us = corners.map { Double($0.x) * cos(r) + Double($0.y) * sin(r) }
        let vs = corners.map { -Double($0.x) * sin(r) + Double($0.y) * cos(r) }
        let w = (us.max() ?? 0) - (us.min() ?? 0), h = (vs.max() ?? 0) - (vs.min() ?? 0)
        let frame = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        return Snap(kind: .rectangle, frame: frame, rotation: (turn * 100).rounded() / 100)
    }

    /// A triangle: three corners, none thinner than thinnestCorner.
    static func isTriangle(_ corners: [CGPoint]) -> Bool {
        corners.count == 3 && corners.indices.allSatisfy { angle(at: $0, of: corners) >= thinnestCorner }
    }

    /// An ellipse: the points' distance from the centre of `bounds`, over
    /// the ellipse filling them, off 1 by less than ellipseResidual on
    /// average.
    static func fitsEllipse(_ points: [CGPoint], in bounds: CGRect) -> Bool {
        let a = Double(bounds.width) / 2, b = Double(bounds.height) / 2
        guard a > 0, b > 0, !points.isEmpty else { return false }
        let cx = Double(bounds.midX), cy = Double(bounds.midY)
        let off = points.map { p -> Double in
            let u = (Double(p.x) - cx) / a, v = (Double(p.y) - cy) / b
            return abs((u * u + v * v).squareRoot() - 1)
        }
        return off.reduce(0, +) / Double(off.count) < ellipseResidual
    }

    // MARK: corners

    /// A closed stroke's corners: simplified (Ramer–Douglas–Peucker) from
    /// its first point to the point furthest from it and on round again,
    /// then pruned.
    static func closedCorners(_ ring: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard ring.count >= 3, let start = ring.first else { return ring }
        let reach = ring.map { hypot(Double($0.x - start.x), Double($0.y - start.y)) }
        let far = reach.indices.max { reach[$0] < reach[$1] } ?? 0
        guard far > 0 else { return [start] }
        let there = simplified(Array(ring[0...far]), tolerance: tolerance)
        let back = simplified(Array(ring[far...]) + [start], tolerance: tolerance)
        let loop = Array(there.dropLast()) + Array(back.dropLast())
        return pruned(loop, closed: true, tolerance: tolerance)
    }

    /// Ramer–Douglas–Peucker: the ends, and every point further than
    /// `tolerance` from the straight between the points kept either side.
    static func simplified(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var spans = [(0, points.count - 1)]
        while let (from, to) = spans.popLast() {
            guard to > from + 1 else { continue }
            var furthest = from, most = -1.0
            for i in (from + 1)..<to {
                let d = MaskRaster.distance(points[i], points[from], points[to])
                if d > most { most = d; furthest = i }
            }
            if most > tolerance {
                keep[furthest] = true
                spans.append((from, furthest))
                spans.append((furthest, to))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// Corners that are not corners taken out until none is left: one
    /// nearer than `tolerance` to the corner before it, or one where the
    /// stroke turns less than shallowTurn. A closed stroke's corners go
    /// round; an open one keeps its ends.
    static func pruned(_ corners: [CGPoint], closed: Bool, tolerance: Double) -> [CGPoint] {
        var out = corners
        var changed = true
        while changed && out.count > (closed ? 3 : 2) {
            changed = false
            for i in out.indices {
                if !closed && (i == 0 || i == out.count - 1) { continue }
                let prev = out[(i + out.count - 1) % out.count], next = out[(i + 1) % out.count]
                let p = out[i]
                let near = hypot(Double(p.x - prev.x), Double(p.y - prev.y)) < tolerance
                let straight = 180 - angle(prev, p, next) < shallowTurn
                if near || straight {
                    out.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        return out
    }

    /// The angle at corner `i` of a closed polygon, in degrees, 0…180.
    static func angle(at i: Int, of corners: [CGPoint]) -> Double {
        let n = corners.count
        return angle(corners[(i + n - 1) % n], corners[i], corners[(i + 1) % n])
    }

    /// The angle at `p` between the ways to `a` and to `b`, in degrees,
    /// 0…180; 180 for a point with nowhere to turn.
    static func angle(_ a: CGPoint, _ p: CGPoint, _ b: CGPoint) -> Double {
        let ux = Double(a.x - p.x), uy = Double(a.y - p.y), vx = Double(b.x - p.x), vy = Double(b.y - p.y)
        let lengths = hypot(ux, uy) * hypot(vx, vy)
        guard lengths > 0 else { return 180 }
        return acos(min(max((ux * vx + uy * vy) / lengths, -1), 1)) * 180 / .pi
    }

    static func length(_ points: [CGPoint]) -> Double {
        var total = 0.0
        for (a, b) in zip(points, points.dropFirst()) { total += hypot(Double(b.x - a.x), Double(b.y - a.y)) }
        return total
    }

    static func boundsOf(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: the elements

    /// The shape library's ids an ellipse, a rectangle and a triangle are
    /// drawn with — the library's own, which every build draws.
    static func shapeId(_ kind: Kind) -> String? {
        switch kind {
        case .ellipse: return "circle"
        case .rectangle: return "rect"
        case .triangle: return "triangle"
        case .line, .arrow: return nil
        }
    }

    /// The element `snap` becomes in `tool`'s ink: a line — with an arrow
    /// at its end for an arrow — as thick as the stroke would be drawn, or
    /// a shape with no fill and a border as wide; in the pen's ink,
    /// transparency, highlighter blend or glow either way. Nil for the
    /// eraser.
    static func element(_ snap: Snap, tool: Freehand.Tool) -> Element? {
        guard tool.pen != .eraser else { return nil }
        let width = Freehand.drawnWidth(tool)
        var e: Element
        if let id = shapeId(snap.kind) {
            e = Element.shape(id, w: max(1, Double(snap.frame.width)), h: max(1, Double(snap.frame.height)))
            e.x = Double(snap.frame.minX)
            e.y = Double(snap.frame.minY)
            e.rotation = snap.kind == .rectangle ? snap.rotation : 0
            e.fill = Paint.clear
            e.stroke = Freehand.drawnColor(tool)
            e.strokeWidth = width
        } else {
            var line = Element.line(w: 100)
            line.color = Freehand.drawnColor(tool)
            line.thickness = width
            line.h = max(8, width)
            if snap.kind == .arrow { line.endCap = "arrow" }
            e = LineRoutes.withEnds(line, snap.start, snap.end)
        }
        let shown = Freehand.opacity(transparency: tool.transparency)
        if shown < 1 { e.opacity = shown }
        if tool.pen == .highlighter { e.blendMode = "multiply" }
        if tool.pen == .glow { e.shadow = Freehand.glow(of: tool) }
        return e
    }
}
