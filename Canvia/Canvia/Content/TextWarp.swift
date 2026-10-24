// Warped text: the letters themselves reshaped inside their box, as Canva's
// Typecraft bends them, and still typed as words. Kept on a text element as
//
//   "warp": {"kind": "arch"|"bulge"|"flag"|"squeeze"|"rise"|"perspective"|"custom",
//            "amount": -100…100, "grid": [16 numbers]}
//
// The box is bent by eight handles — its four corners and the middles of its
// four edges — each moved from where it rests by an offset in box units (a
// share of the box's width across, of its height down). `grid` holds the
// offsets, a pair (dx, dy) for each handle in the order of `handleOrder`,
// for a custom warp only; a preset makes its offsets from `amount`
// (offsets(_:)). Each edge is the quadratic curve through its two corners
// and its middle handle, and every point of the box is carried by the
// bilinear Coons patch of the four edges (map). The glyph outlines
// (TextOutliner) are flattened and every point mapped, so the effects,
// gradients and photos in letters drawn from the outlines bend with them.
// The Android twin maps by the same patch, number for number.

import CoreGraphics
import Foundation

struct TextWarpSpec: Codable, Equatable, Hashable {
    var kind: String
    /// -100…100: how far a preset bends, and which way.
    var amount: Double = 50
    /// For "custom": 16 numbers, each handle's (dx, dy) in box units.
    var grid: [Double]?

    init(kind: String, amount: Double = 50, grid: [Double]? = nil) {
        self.kind = kind
        self.amount = amount
        self.grid = grid
    }

    private enum CodingKeys: String, CodingKey { case kind, amount, grid }

    // Each key on its own: an amount out of reach is held to it, a grid
    // that is not sixteen numbers is none.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "arch"
        let amount = (try? c.decode(Double.self, forKey: .amount)) ?? 50
        self.amount = amount.isFinite ? min(max(amount, -100), 100) : 50
        let grid = try? c.decode([Double].self, forKey: .grid)
        self.grid = grid.flatMap { $0.count == 16 && $0.allSatisfy(\.isFinite) ? $0 : nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(amount, forKey: .amount)
        if kind == TextWarp.custom { try c.encodeIfPresent(grid, forKey: .grid) }
    }
}

enum TextWarp {

    static let custom = "custom"
    /// The presets, in the order the Effects sheet offers them.
    static let kinds = ["arch", "bulge", "flag", "squeeze", "rise", "perspective"]

    static func name(_ kind: String) -> String {
        switch kind {
        case "arch": return tr("Arch")
        case "bulge": return tr("Bulge")
        case "flag": return tr("Flag")
        case "squeeze": return tr("Squeeze")
        case "rise": return tr("Rise")
        case "perspective": return tr("Perspective")
        default: return tr("Custom")
        }
    }

    /// The handles where they rest, in box units: the corners top-left,
    /// top-right, bottom-right and bottom-left, then the middles of the
    /// top, right, bottom and left edges.
    static let handleOrder: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
        CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.5), CGPoint(x: 0.5, y: 1), CGPoint(x: 0, y: 0.5),
    ]

    /// Whether `el` is warped: a warp of a known kind, and no curve, path or
    /// column, which come first where a file has both.
    static func isWarped(_ el: Element) -> Bool {
        guard let warp = el.warp, el.vertical != true, (el.textPath ?? "").isEmpty,
              !(el.curve.map { abs($0) >= TextOutliner.straightBelowDegrees } ?? false) else { return false }
        return kinds.contains(warp.kind) || warp.kind == custom
    }

    /// The sixteen offsets a warp moves its handles by, a (dx, dy) pair a
    /// handle in handleOrder: a custom warp's grid, or none; a preset's
    /// from a = amount / 100:
    ///  - arch: the middles of the top and bottom up by 0.3a;
    ///  - bulge: the top's middle up and the bottom's down by 0.3a;
    ///  - squeeze: the top's middle down and the bottom's up by 0.3a;
    ///  - flag: the top's and bottom's middles up by 0.25a, the right edge
    ///    (its corners and middle) down by 0.25a;
    ///  - rise: the right edge up by 0.3a, the top's and bottom's middles
    ///    up by 0.15a, so the edges stay straight;
    ///  - perspective: the right edge's top up and its bottom down by
    ///    0.25a, the top's middle up and the bottom's down by 0.125a.
    static func offsets(_ warp: TextWarpSpec) -> [Double] {
        var o = [Double](repeating: 0, count: 16)
        if warp.kind == custom { return warp.grid ?? o }
        let a = min(max(warp.amount, -100), 100) / 100
        // The y of handle i.
        func dy(_ i: Int, _ v: Double) { o[2 * i + 1] = v }
        switch warp.kind {
        case "arch":
            dy(4, -0.3 * a); dy(6, -0.3 * a)
        case "bulge":
            dy(4, -0.3 * a); dy(6, 0.3 * a)
        case "squeeze":
            dy(4, 0.3 * a); dy(6, -0.3 * a)
        case "flag":
            dy(4, -0.25 * a); dy(6, -0.25 * a)
            dy(1, 0.25 * a); dy(2, 0.25 * a); dy(5, 0.25 * a)
        case "rise":
            dy(1, -0.3 * a); dy(2, -0.3 * a); dy(5, -0.3 * a)
            dy(4, -0.15 * a); dy(6, -0.15 * a)
        case "perspective":
            dy(1, -0.25 * a); dy(2, 0.25 * a)
            dy(4, -0.125 * a); dy(6, 0.125 * a)
        default:
            break
        }
        return o
    }

    /// The eight handles where the warp puts them, in box units.
    static func handles(_ warp: TextWarpSpec) -> [CGPoint] {
        let o = offsets(warp)
        return handleOrder.enumerated().map { i, rest in
            CGPoint(x: rest.x + o[2 * i], y: rest.y + o[2 * i + 1])
        }
    }

    /// `warp` as a custom warp with handle `index` at `point`, in box
    /// units: the handles where they are now, that one moved.
    static func moved(_ warp: TextWarpSpec, handle index: Int, to point: CGPoint) -> TextWarpSpec {
        var o = offsets(warp)
        guard handleOrder.indices.contains(index) else { return warp }
        o[2 * index] = Double(point.x - handleOrder[index].x)
        o[2 * index + 1] = Double(point.y - handleOrder[index].y)
        return TextWarpSpec(kind: custom, amount: warp.amount, grid: o.map { ($0 * 10_000).rounded() / 10_000 })
    }

    /// The point `u` along the quadratic edge from `p0` to `p1` through
    /// `mid` at its middle.
    private static func edge(_ p0: CGPoint, _ mid: CGPoint, _ p1: CGPoint, _ u: Double) -> CGPoint {
        // The control point that puts the curve through mid at u = 0.5.
        let cx = 2 * Double(mid.x) - (Double(p0.x) + Double(p1.x)) / 2
        let cy = 2 * Double(mid.y) - (Double(p0.y) + Double(p1.y)) / 2
        let v = 1 - u
        let x = v * v * Double(p0.x) + 2 * v * u * cx + u * u * Double(p1.x)
        let y = v * v * Double(p0.y) + 2 * v * u * cy + u * u * Double(p1.y)
        return CGPoint(x: x, y: y)
    }

    /// Where `point` of `box` lands, warped: its place in the box as (u, v),
    /// carried by the Coons patch of the four edges — the top and bottom
    /// across u, the left and right down v, less the corners' bilinear
    /// share — and back into the box's space.
    static func map(_ point: CGPoint, box: CGRect, warp: TextWarpSpec) -> CGPoint {
        guard box.width > 0, box.height > 0 else { return point }
        let h = handles(warp)
        let u = Double(point.x - box.minX) / Double(box.width)
        let v = Double(point.y - box.minY) / Double(box.height)
        let top = edge(h[0], h[4], h[1], u)
        let bottom = edge(h[3], h[6], h[2], u)
        let left = edge(h[0], h[7], h[3], v)
        let right = edge(h[1], h[5], h[2], v)
        func blend(_ k: KeyPath<CGPoint, CGFloat>) -> Double {
            let t: Double = Double(top[keyPath: k]), b: Double = Double(bottom[keyPath: k])
            let l: Double = Double(left[keyPath: k]), r: Double = Double(right[keyPath: k])
            // Summed in Android's order, so both phones land on the same bits.
            var ruled: Double = (1 - v) * t
            ruled += v * b
            ruled += (1 - u) * l
            ruled += u * r
            var corners: Double = (1 - u) * (1 - v) * Double(h[0][keyPath: k])
            corners += u * (1 - v) * Double(h[1][keyPath: k])
            corners += (1 - u) * v * Double(h[3][keyPath: k])
            corners += u * v * Double(h[2][keyPath: k])
            return ruled - corners
        }
        return CGPoint(x: Double(box.minX) + blend(\.x) * Double(box.width),
                       y: Double(box.minY) + blend(\.y) * Double(box.height))
    }

    /// `path` warped: every curve flattened into `segments` straight pieces
    /// and every point mapped, so straight runs of a glyph bend too — a
    /// line is cut into the same pieces.
    static func warped(_ path: CGPath, box: CGRect, warp: TextWarpSpec, segments: Int = 8) -> CGPath {
        let out = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        path.applyWithBlock { (element: UnsafePointer<CGPathElement>) in
            let e: CGPathElement = element.pointee
            switch e.type {
            case .moveToPoint:
                current = e.points[0]
                start = current
                out.move(to: map(current, box: box, warp: warp))
            case .addLineToPoint:
                let ends: [CGPoint] = [current, e.points[0]]
                addPieces(out, ends, box: box, warp: warp, segments: segments)
                current = e.points[0]
            case .addQuadCurveToPoint:
                let ends: [CGPoint] = [current, e.points[0], e.points[1]]
                addPieces(out, ends, box: box, warp: warp, segments: segments)
                current = e.points[1]
            case .addCurveToPoint:
                let ends: [CGPoint] = [current, e.points[0], e.points[1], e.points[2]]
                addPieces(out, ends, box: box, warp: warp, segments: segments)
                current = e.points[2]
            case .closeSubpath:
                out.closeSubpath()
                current = start
            @unknown default:
                break
            }
        }
        return out
    }

    /// A line (2 points), quadratic (3) or cubic (4) Bézier from its start,
    /// cut into `segments` straight pieces, each end warped, added to `out`.
    private static func addPieces(_ out: CGMutablePath, _ points: [CGPoint], box: CGRect, warp: TextWarpSpec,
                                  segments: Int) {
        for i in 1...segments {
            let t = Double(i) / Double(segments)
            out.addLine(to: map(bezier(points, t), box: box, warp: warp))
        }
    }

    /// The point `t` of the way along a line (2 points), quadratic (3) or
    /// cubic (4) Bézier, by its Bernstein weights — the sums Android uses.
    private static func bezier(_ points: [CGPoint], _ t: Double) -> CGPoint {
        let v: Double = 1 - t
        let weights: [Double]
        switch points.count {
        case 2: weights = [v, t]
        case 3: weights = [v * v, 2 * v * t, t * t]
        default: weights = [v * v * v, 3 * v * v * t, 3 * v * t * t, t * t * t]
        }
        var x: Double = 0
        var y: Double = 0
        for (k, w) in weights.enumerated() where k < points.count {
            x += w * Double(points[k].x)
            y += w * Double(points[k].y)
        }
        return CGPoint(x: x, y: y)
    }

    /// The box's outline warped, as a bounding rectangle in the box's own
    /// space: what a tap on warped words is tested against, with the box.
    static func hull(_ warp: TextWarpSpec, w: Double, h: Double) -> CGRect {
        let box = CGRect(x: 0, y: 0, width: w, height: h)
        var points: [CGPoint] = []
        for i in 0...8 {
            let t = Double(i) / 8
            points.append(map(CGPoint(x: t * w, y: 0), box: box, warp: warp))
            points.append(map(CGPoint(x: t * w, y: h), box: box, warp: warp))
            points.append(map(CGPoint(x: 0, y: t * h), box: box, warp: warp))
            points.append(map(CGPoint(x: w, y: t * h), box: box, warp: warp))
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return box }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).union(box)
    }

    // MARK: a path's points

    /// The points of path data written with absolute M, L, Q, T and C only
    /// — each pair of numbers one point, in the path's 0…100 box — as
    /// Edit shape moves them; nil for data with any other command, whose
    /// numbers are not all points.
    static func pathPoints(_ data: String) -> [CGPoint]? {
        guard data.allSatisfy({ !$0.isLetter || "MLQTCZ".contains($0) }) else { return nil }
        let numbers = pathNumbers(data).map(\.value)
        guard numbers.count >= 2, numbers.count % 2 == 0 else { return nil }
        return stride(from: 0, to: numbers.count, by: 2).map { CGPoint(x: numbers[$0], y: numbers[$0 + 1]) }
    }

    /// `data` with point `index` (pathPoints) at `point`, to two places.
    static func movingPathPoint(_ data: String, index: Int, to point: CGPoint) -> String? {
        guard pathPoints(data) != nil else { return nil }
        let numbers = pathNumbers(data)
        guard 2 * index + 1 < numbers.count else { return nil }
        func written(_ v: CGFloat) -> String {
            let r = (Double(v) * 100).rounded() / 100
            return r == r.rounded() ? String(Int(r)) : String(r)
        }
        let x = numbers[2 * index], y = numbers[2 * index + 1]
        // A space before a number written hard against another's digits.
        func spaced(_ range: Range<String.Index>, _ v: CGFloat) -> String {
            let before = range.lowerBound > data.startIndex ? data[data.index(before: range.lowerBound)] : " "
            return (before.isNumber || before == "." ? " " : "") + written(v)
        }
        return String(data[..<x.range.lowerBound]) + spaced(x.range, point.x)
            + String(data[x.range.upperBound..<y.range.lowerBound]) + spaced(y.range, point.y)
            + String(data[y.range.upperBound...])
    }

    /// Every number in path data and where it is written.
    private static func pathNumbers(_ data: String) -> [(value: Double, range: Range<String.Index>)] {
        var out: [(value: Double, range: Range<String.Index>)] = []
        var i = data.startIndex
        while i < data.endIndex {
            let c = data[i]
            guard c.isNumber || c == "-" || c == "." else {
                i = data.index(after: i)
                continue
            }
            var j = data.index(after: i)
            var seenDot = c == "."
            while j < data.endIndex {
                let d = data[j]
                if d.isNumber { j = data.index(after: j); continue }
                if d == ".", !seenDot { seenDot = true; j = data.index(after: j); continue }
                break
            }
            if let value = Double(data[i..<j]) { out.append((value, i..<j)) }
            i = j
        }
        return out
    }
}
