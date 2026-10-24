// What a line's ends look like — the Android twin's LineEnds, shape for
// shape, with the same golden rows.
//
// A line's `startCap` and `endCap` are one of eleven keys: "none", "arrow"
// (an open arrow), "triangle" and "triangleOutline", "dot" (a filled circle)
// and "circle" (its outline), "square" and "squareOutline", "diamond" and
// "diamondOutline", and "bar". Anything else reads as none. `capScale`,
// 0.5…3 and 1 unless written, sizes the heads of both ends.
//
// Each head is one shape in unit space: its tip at the origin, pointing
// along +x, reaching back to x = -1. On the page it is that shape scaled by
// the head's length — max(3 × thickness, 10) × capScale — turned to the
// end's tangent and moved onto the end's tip, so it sits the same on a
// straight, an elbowed and a curved line (LineRoutes). A filled head is
// filled; an open arrow, an outline and a bar are stroked as wide as the
// line, round-joined. The stroke stops short of the tip (back) so a thick
// line never shows through: under a filled head by half its length, at an
// outline's back edge, and by half the line's weight at an open arrow or a
// bar, whose round cap then ends on the tip.

import CoreGraphics
import Foundation

enum LineEnds {

    enum Kind: String, CaseIterable, Identifiable {
        case none, arrow, triangle, triangleOutline, dot, circle, square, squareOutline, diamond, diamondOutline, bar

        var id: String { rawValue }

        /// What the Line panel calls it.
        var label: String {
            switch self {
            case .none: return tr("None")
            case .arrow: return tr("Arrow")
            case .triangle: return tr("Triangle")
            case .triangleOutline: return tr("Triangle outline")
            case .dot: return tr("Dot")
            case .circle: return tr("Circle outline")
            case .square: return tr("Square")
            case .squareOutline: return tr("Square outline")
            case .diamond: return tr("Diamond")
            case .diamondOutline: return tr("Diamond outline")
            case .bar: return tr("Bar", context: "line end")
            }
        }

        /// Drawn as a line as wide as the line's own, not filled.
        var stroked: Bool {
            switch self {
            case .arrow, .triangleOutline, .circle, .squareOutline, .diamondOutline, .bar: return true
            case .none, .triangle, .dot, .square, .diamond: return false
            }
        }
    }

    /// A cap key as one of the kinds; anything unknown, or none, is none.
    static func kind(_ key: String?) -> Kind {
        key.flatMap { Kind(rawValue: $0) } ?? Kind.none
    }

    static let scaleRange: ClosedRange<Double> = 0.5...3

    /// `capScale` held to 0.5…3; 1 when none is written or it is not a number.
    static func scale(_ capScale: Double?) -> Double {
        guard let capScale, capScale.isFinite else { return 1 }
        return min(max(capScale, scaleRange.lowerBound), scaleRange.upperBound)
    }

    static func scale(of el: Element) -> Double { scale(el.capScale) }

    /// `capScale` as written: none for 1.
    static func written(_ scale: Double) -> Double? {
        let held = self.scale(scale)
        return abs(held - 1) < 1e-9 ? nil : held
    }

    /// A head's length for a line `t` thick at `scale`.
    static func size(thickness t: Double, scale: Double = 1) -> Double {
        max(t * 3, 10) * self.scale(scale)
    }

    /// How far beyond a line's box its heads can reach: a head's length.
    static func reach(_ el: Element) -> Double {
        size(thickness: max(el.thickness ?? 4, 0.5), scale: scale(of: el))
    }

    // MARK: shapes

    /// A head's outline: a closed polygon, an open polyline, or a circle.
    enum Outline: Equatable {
        case polygon([CGPoint])
        case polyline([CGPoint])
        case circle(center: CGPoint, radius: Double)
    }

    /// Each kind's shape in unit space, tip at the origin pointing +x; none
    /// for none.
    static func unit(_ kind: Kind) -> Outline? {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        switch kind {
        case .none: return nil
        case .arrow: return .polyline([p(-1, -0.6), p(0, 0), p(-1, 0.6)])
        case .triangle, .triangleOutline: return .polygon([p(0, 0), p(-1, -0.6), p(-1, 0.6)])
        case .dot, .circle: return .circle(center: p(-0.5, 0), radius: 0.5)
        case .square, .squareOutline: return .polygon([p(0, -0.5), p(0, 0.5), p(-1, 0.5), p(-1, -0.5)])
        case .diamond, .diamondOutline: return .polygon([p(0, 0), p(-0.5, 0.5), p(-1, 0), p(-0.5, -0.5)])
        case .bar: return .polyline([p(0, -0.6), p(0, 0.6)])
        }
    }

    /// One end's head on the page (or in the line's box): its shape, and
    /// whether it is stroked `width` wide or filled.
    struct Head: Equatable {
        var kind: Kind
        var outline: Outline
        var stroked: Bool
        var width: Double
    }

    /// `kind`'s head at `tip`, pointing `angle` radians (0 along +x, y
    /// down), for a line `t` thick at `scale`; none for none.
    static func head(_ kind: Kind, tip: CGPoint, angle: Double, thickness t: Double, scale: Double = 1) -> Head? {
        guard let shape = unit(kind) else { return nil }
        let length = size(thickness: t, scale: scale)
        let c = cos(angle), s = sin(angle)
        func place(_ q: CGPoint) -> CGPoint {
            let x = Double(q.x) * length, y = Double(q.y) * length
            return CGPoint(x: Double(tip.x) + x * c - y * s, y: Double(tip.y) + x * s + y * c)
        }
        let placed: Outline
        switch shape {
        case .polygon(let points): placed = .polygon(points.map(place))
        case .polyline(let points): placed = .polyline(points.map(place))
        case .circle(let center, let radius): placed = .circle(center: place(center), radius: radius * length)
        }
        return Head(kind: kind, outline: placed, stroked: kind.stroked, width: t)
    }

    /// How far a line `t` thick stops short of an end with `kind` at
    /// `scale`: half the head under a filled one, the whole head at an
    /// outline's back edge, half the weight at an open arrow or a bar.
    static func back(_ kind: Kind, thickness t: Double, scale: Double = 1) -> Double {
        let length = size(thickness: t, scale: scale)
        switch kind {
        case .none: return 0
        case .arrow, .bar: return t / 2
        case .triangle, .dot, .square, .diamond: return length / 2
        case .triangleOutline, .circle, .squareOutline, .diamondOutline: return length
        }
    }

    /// The heads at both ends of `el`'s route, in its own box.
    static func heads(_ el: Element) -> [Head] {
        let t = max(el.thickness ?? 4, 0.5)
        let s = scale(of: el)
        let route = LineRoutes.route(el)
        return [head(kind(el.startCap), tip: route.start, angle: route.startAngle, thickness: t, scale: s),
                head(kind(el.endCap), tip: route.end, angle: route.endAngle, thickness: t, scale: s)].compactMap { $0 }
    }

    /// A head as a path, to fill or to stroke `width` wide.
    static func path(_ head: Head) -> CGPath {
        let path = CGMutablePath()
        switch head.outline {
        case .polygon(let points):
            path.addLines(between: points)
            path.closeSubpath()
        case .polyline(let points):
            path.addLines(between: points)
        case .circle(let center, let radius):
            path.addEllipse(in: CGRect(x: Double(center.x) - radius, y: Double(center.y) - radius,
                                       width: radius * 2, height: radius * 2))
        }
        return path
    }

    /// A head as SVG path data, each point written by `at`: polygons as
    /// M…L…Z, polylines M…L, a circle as two half arcs.
    static func svgData(_ head: Head, at: (CGPoint) -> String, number: (Double) -> String) -> String {
        switch head.outline {
        case .polygon(let points):
            return points.enumerated().map { ($0.offset == 0 ? "M" : "L") + at($0.element) }.joined() + "Z"
        case .polyline(let points):
            return points.enumerated().map { ($0.offset == 0 ? "M" : "L") + at($0.element) }.joined()
        case .circle(let center, let radius):
            let r = number(radius)
            let left = at(CGPoint(x: Double(center.x) - radius, y: Double(center.y)))
            let right = at(CGPoint(x: Double(center.x) + radius, y: Double(center.y)))
            return "M\(right)A\(r) \(r) 0 1 0 \(left)A\(r) \(r) 0 1 0 \(right)Z"
        }
    }

    // MARK: PowerPoint

    /// PowerPoint's nearest line end: "arrow" for the open arrow,
    /// "triangle" for either triangle, "oval" for a dot or a circle, and
    /// "diamond" for a diamond or a square (PowerPoint has no square end);
    /// none for none or a bar, which it has no end for.
    static func pptxType(_ kind: Kind) -> String? {
        switch kind {
        case .none, .bar: return nil
        case .arrow: return "arrow"
        case .triangle, .triangleOutline: return "triangle"
        case .dot, .circle: return "oval"
        case .square, .squareOutline, .diamond, .diamondOutline: return "diamond"
        }
    }

    /// PowerPoint's head width and length for `scale`: "sm" under 0.75,
    /// "lg" from 1.5, else "med" — none written at 1, PowerPoint's own
    /// default being medium.
    static func pptxSize(_ scale: Double) -> String? {
        let s = self.scale(scale)
        if abs(s - 1) < 1e-9 { return nil }
        if s < 0.75 { return "sm" }
        return s >= 1.5 ? "lg" : "med"
    }
}
