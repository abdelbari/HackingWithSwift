// Drawing by hand: a finger (or a Pencil) stroke becomes a shape.
//
// The stroke is kept as path data in the element's own 0…100 box, drawn
// with a stroke and no fill, so it is an ordinary element afterwards —
// moved, rotated, recoloured, exported as a real path in the SVG — and a
// single undo step. Points are thinned and then smoothed with quadratic
// curves through the midpoints, which takes the sawtooth out of raw touch
// samples without pulling the line off the finger.

import CoreGraphics
import Foundation

enum Freehand {

    struct Tool: Equatable {
        var color = "#1f2430"
        var width: Double = 6
    }

    static let widths: [Double] = [2, 4, 6, 10, 16, 24]
    static let colors: [String] = ["#1f2430", "#ffffff", "#ef4444", "#f59e0b", "#22c55e", "#3b82f6", "#8b5cf6", "#ec4899"]

    /// Drops points closer than `minDistance` to the last one kept: a finger
    /// held still emits dozens of them and they make the smoothed line
    /// wobble in place.
    static func thinned(_ points: [CGPoint], minDistance: Double = 2) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in points {
            if let last = out.last, hypot(p.x - last.x, p.y - last.y) < minDistance { continue }
            out.append(p)
        }
        return out
    }

    /// The smoothed curve: a start and quadratic segments whose ends are
    /// the midpoints between successive samples and whose controls are the
    /// samples themselves, so the curve passes near every sample and is
    /// continuous in slope. Fewer than three points draw straight.
    static func segments(_ raw: [CGPoint]) -> (start: CGPoint, quads: [(control: CGPoint, end: CGPoint)])? {
        let points = thinned(raw)
        guard let first = points.first else { return nil }
        if points.count < 3 {
            let end = points.last ?? first
            return (first, [(control: CGPoint(x: (first.x + end.x) / 2, y: (first.y + end.y) / 2), end: end)])
        }
        var quads: [(control: CGPoint, end: CGPoint)] = []
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            quads.append((control: points[i], end: mid))
        }
        quads.append((control: points[points.count - 1], end: points[points.count - 1]))
        return (first, quads)
    }

    static func cgPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let seg = segments(points) else { return path }
        path.move(to: seg.start)
        for q in seg.quads { path.addQuadCurve(to: q.end, control: q.control) }
        return path
    }

    /// SVG path data for the smoothed curve through `points`, in the space
    /// they are given in.
    static func pathData(_ points: [CGPoint]) -> String {
        guard let seg = segments(points) else { return "" }
        var d = "M\(num(seg.start.x)) \(num(seg.start.y))"
        for q in seg.quads {
            d += "Q\(num(q.control.x)) \(num(q.control.y)) \(num(q.end.x)) \(num(q.end.y))"
        }
        return d
    }

    /// The stroke's bounds padded by half its width so the line is not
    /// clipped at the element's edge, and at least the width across, so a
    /// dot is a dot.
    static func bounds(of points: [CGPoint], width: Double) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let pad = width / 2 + 1
        return CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + 2 * pad, height: maxY - minY + 2 * pad)
    }

    /// The element for a stroke in page units: a shape with the curve as
    /// path data normalised into its box, stroked in the tool's colour with
    /// no fill.
    static func element(points raw: [CGPoint], tool: Tool) -> Element? {
        let points = thinned(raw)
        guard let box = bounds(of: points, width: tool.width) else { return nil }
        let unit = points.map { p in
            CGPoint(x: (p.x - box.minX) / box.width * 100, y: (p.y - box.minY) / box.height * 100)
        }
        var e = Element.shape("freehand", w: box.width, h: box.height)
        e.x = box.minX
        e.y = box.minY
        e.pathData = pathData(unit)
        e.fill = Paint.clear
        e.stroke = tool.color
        e.strokeWidth = tool.width
        e.radius = nil
        return e
    }

    private static func num(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }
}
