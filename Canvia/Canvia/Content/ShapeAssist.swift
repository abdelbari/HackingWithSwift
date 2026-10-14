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

    /// A stroke shorter than this along its path, in page units, is too
    /// short to read.
    static let shortest = 12.0
    /// A line strays from the straight between its ends by less than this
    /// share of the distance between them.
    static let lineDeviation = 0.04
    /// A closed stroke's ends are nearer together than this share of its
    /// path's length.
    static let closedGap = 0.15
    /// An ellipse's points are, on average, within this share of the
    /// ellipse filling the stroke's bounds (its radial residual).
    static let ellipseResidual = 0.12
    /// A rectangle's corners are each within this many degrees of square,
    /// and a triangle's each at least this many degrees.
    static let angleSlack = 20.0
    /// Ramer–Douglas–Peucker's tolerance, as a share of the larger side of
    /// the stroke's bounds, and how little a corner may turn, in degrees,
    /// and be a straight run.
    static let cornerTolerance = 0.08
    static let straightTurn = 25.0
    /// An arrow's shaft is at least this share of its path; its head lies
    /// within this share of the shaft's length of the tip; and each barb
    /// is turned back towards the tail by no more than this many degrees
    /// from the shaft.
    static let shaftShare = 0.4
    static let headReach = 0.5
    static let barbAngle = 75.0

    /// Whether the finger, come to rest at `rest`, has moved on at `point`
    /// (page units, the canvas at `zoom`): holdSlop points on the screen
    /// or more. Until it has for holdSeconds, it rests.
    static func movedOn(from rest: CGPoint, to point: CGPoint, zoom: Double) -> Bool {
        hypot(Double(point.x - rest.x), Double(point.y - rest.y)) >= holdSlop / max(zoom, 0.01)
    }

    /// The shape `raw` (page units) was drawn as, or nil when it is none of
    /// them — the Android twin's rules, number for number: thinned as a
    /// kept stroke is (Freehand.thinned) and too short to read under
    /// `shortest` along its path; a line when no point strays from the
    /// straight between its ends by lineDeviation of the distance between
    /// them; closed when its ends are within closedGap of its path's
    /// length, and then an ellipse, a rectangle or a triangle (closed);
    /// open and not a line, an arrow (arrow).
    static func classify(_ raw: [CGPoint]) -> Snap? {
        let points = Freehand.thinned(raw)
        guard points.count >= 2, let start = points.first, let end = points.last else { return nil }
        let total = length(points)
        guard total >= shortest else { return nil }
        let chord = hypot(Double(end.x - start.x), Double(end.y - start.y))
        let far = points.map { MaskRaster.distance($0, start, end) }.max() ?? 0
        if chord > 0 && far < lineDeviation * chord { return Snap(kind: .line, start: start, end: end) }
        if chord < closedGap * total { return closed(points) }
        return arrow(points, length: total)
    }

    /// A closed stroke: an ellipse — its bounds' centre and half-sides —
    /// when its points' radial residual is under ellipseResidual; else its
    /// corners (corners), four all within angleSlack of square a rectangle,
    /// three each of at least angleSlack a triangle.
    static func closed(_ points: [CGPoint]) -> Snap? {
        let bounds = boundsOf(points)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        if fitsEllipse(points, in: bounds) { return Snap(kind: .ellipse, frame: bounds) }
        let found = corners(points, closed: true)
        let angles = found.indices.map { angle(at: $0, of: found) }
        if found.count == 4 && angles.allSatisfy({ abs($0 - 90) <= angleSlack }) { return rectangle(found) }
        if found.count == 3 && angles.allSatisfy({ $0 >= angleSlack }) {
            return Snap(kind: .triangle, frame: boundsOf(found))
        }
        return nil
    }

    /// An arrow: its corners (corners, open) start with a shaft from tail
    /// to tip at least shaftShare of the path's `length`; the rest — the
    /// head — all within headReach of the shaft of the tip; and of the head's
    /// corners not at the tip (within a tenth of the shaft), each turned
    /// back towards the tail by no more than barbAngle, with one either side
    /// of the shaft at least.
    static func arrow(_ points: [CGPoint], length total: Double) -> Snap? {
        let found = corners(points, closed: false)
        guard found.count >= 4 else { return nil }
        let tail = found[0], tip = found[1]
        let shaft = hypot(Double(tip.x - tail.x), Double(tip.y - tail.y))
        guard shaft > 0, shaft >= shaftShare * total else { return nil }
        let head = found.dropFirst(2)
        let reach = headReach * shaft
        guard head.allSatisfy({ hypot(Double($0.x - tip.x), Double($0.y - tip.y)) <= reach }) else { return nil }
        let bx = Double(tail.x - tip.x) / shaft, by = Double(tail.y - tip.y) / shaft
        var left = false, right = false
        for h in head {
            let d = hypot(Double(h.x - tip.x), Double(h.y - tip.y))
            if d < 0.1 * shaft { continue }
            let dx = Double(h.x - tip.x) / d, dy = Double(h.y - tip.y) / d
            let back = acos(min(max(dx * bx + dy * by, -1), 1)) * 180 / .pi
            if back > barbAngle { return nil }
            if bx * dy - by * dx > 0 { left = true } else { right = true }
        }
        return left && right ? Snap(kind: .arrow, start: tail, end: tip) : nil
    }

    /// A rectangle from its four corners in the order drawn: turned as its
    /// first side runs, brought within ±45° (quarterTurn); centred on the
    /// corners' mean; its sides the means of the opposite sides (sides).
    static func rectangle(_ corners: [CGPoint]) -> Snap {
        let first = atan2(Double(corners[1].y - corners[0].y), Double(corners[1].x - corners[0].x)) * 180 / .pi
        let turn = quarterTurn(first)
        let (w, h) = sides(corners, rotation: turn)
        let cx = corners.map { Double($0.x) }.reduce(0, +) / 4
        let cy = corners.map { Double($0.y) }.reduce(0, +) / 4
        return Snap(kind: .rectangle, frame: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), rotation: turn)
    }

    /// A rectangle's width — the mean of its first and third sides, the way
    /// it is turned — and its height, the mean of the other two; swapped
    /// when its first side runs a quarter turn from `rotation`.
    static func sides(_ p: [CGPoint], rotation: Double) -> (width: Double, height: Double) {
        func dist(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(Double(b.x - a.x), Double(b.y - a.y)) }
        let a = (dist(p[0], p[1]) + dist(p[2], p[3])) / 2
        let b = (dist(p[1], p[2]) + dist(p[3], p[0])) / 2
        let first = atan2(Double(p[1].y - p[0].y), Double(p[1].x - p[0].x)) * 180 / .pi
        let off = ((first - rotation).truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
        return abs(off - 90) < 45 ? (b, a) : (a, b)
    }

    /// An angle in degrees less a whole number of quarter turns: from -45
    /// up to, not including, 45.
    static func quarterTurn(_ degrees: Double) -> Double {
        let q = degrees - 90 * ((degrees + 45) / 90).rounded(.down)
        return q >= 45 ? q - 90 : q
    }

    /// An ellipse: the points' distance from the centre of `bounds`, over
    /// the ellipse filling them, off 1 by less than ellipseResidual on
    /// average.
    static func fitsEllipse(_ points: [CGPoint], in bounds: CGRect) -> Bool {
        let a = Double(bounds.width) / 2, b = Double(bounds.height) / 2
        guard a > 0, b > 0, !points.isEmpty else { return false }
        let cx = Double(bounds.minX) + a, cy = Double(bounds.minY) + b
        let off = points.map { p -> Double in
            let u = (Double(p.x) - cx) / a, v = (Double(p.y) - cy) / b
            return abs((u * u + v * v).squareRoot() - 1)
        }
        return off.reduce(0, +) / Double(off.count) < ellipseResidual
    }

    // MARK: corners

    /// A stroke's corners: Ramer–Douglas–Peucker (simplified) at
    /// cornerTolerance of its bounds' larger side, then the corner turning
    /// least taken out while it turns less than straightTurn, again until
    /// none does — a closed stroke's end dropped, joined to its start, and
    /// its start a corner like any other; an open one's ends always kept.
    static func corners(_ points: [CGPoint], closed: Bool) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        let bounds = boundsOf(points)
        let span = max(Double(bounds.width), Double(bounds.height))
        var out = simplified(points, tolerance: cornerTolerance * span)
        if closed && out.count > 2 { out.removeLast() }
        while out.count > (closed ? 3 : 2) {
            let range = closed ? Array(out.indices) : Array(1..<(out.count - 1))
            guard let straightest = range.min(by: { turn(at: $0, of: out) < turn(at: $1, of: out) }),
                  turn(at: straightest, of: out) < straightTurn else { break }
            out.remove(at: straightest)
        }
        return out
    }

    /// How far a path through `corners` turns at corner `i`: 0 straight on,
    /// 180 straight back.
    static func turn(at i: Int, of corners: [CGPoint]) -> Double {
        180 - angle(at: i, of: corners)
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
    /// transparency (none for a marker's), highlighter blend or glow either
    /// way. Nil for the eraser.
    static func element(_ snap: Snap, tool: Freehand.Tool) -> Element? {
        guard tool.pen != .eraser else { return nil }
        let width = Freehand.drawnWidth(tool)
        var e: Element
        if let id = shapeId(snap.kind) {
            e = Element.shape(id, w: max(1, Double(snap.frame.width)), h: max(1, Double(snap.frame.height)))
            e.x = Double(snap.frame.minX)
            e.y = Double(snap.frame.minY)
            // Turned as a rectangle was drawn, written from 0 up to 360 as
            // the Android twin writes it.
            e.rotation = snap.kind == .rectangle ? (snap.rotation + 360).truncatingRemainder(dividingBy: 360) : 0
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
        let shown = Freehand.strokeOpacity(tool)
        if shown < 1 { e.opacity = shown }
        if tool.pen == .highlighter { e.blendMode = "multiply" }
        if tool.pen == .glow { e.shadow = Freehand.glow(of: tool) }
        return e
    }
}
