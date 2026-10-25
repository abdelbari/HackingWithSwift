// The outlines of the library's straight-edged shapes built at the
// element's own size, as the Android twin's ShapeGeometry builds them, rule
// for rule, so Corner rounding stays circular however a shape is stretched
// and a star's points, a polygon's sides, an arrow's head and shaft, a
// callout's tail and a chevron's notch can be set (`shapeParams`). The same
// path draws on the canvas, in the SVG and PDF, and in PowerPoint; the shared
// fixture shape-geometry.json, read by both phones, holds rows of it and says
// the rule in full.
//
// Each shape is a polygon in a 0…100 box, each corner then times w/100 and
// h/100. Every corner is filleted with a circular arc: its radius held to
// half the shorter edge beside it, and how far the arc reaches along each
// edge held to half that edge too, the radius taken down with it, so two
// arcs never cross. A corner where the outline runs straight on is left.
// A polygon of an odd count has a corner straight up, of an even count a
// flat top. The two callouts take no rounding: each is the library's path
// with its tail's tip moved. Circles, hearts and blobs are not built here.
//
// The shape's id is never changed, and only parameters that differ from the
// shape's own are written, so a build without this draws the stored path.

import CoreGraphics
import Foundation

enum ShapeGeometry {

    /// Each parameter's range; points and sides are whole.
    static let limits: [String: ClosedRange<Double>] = [
        "points": 4...24, "inner": 0.2...0.9, "sides": 3...12, "head": 0.1...0.9, "shaft": 0.1...0.9,
        "tailX": 0...1, "tailY": 0...1.4, "notch": 0...0.5,
    ]
    static let wholeKeys: Set<String> = ["points", "sides"]

    /// How near a parameter may be to its shape's own and still not be
    /// written.
    private static let same = 1e-9

    /// A star's points and how far in its inner corners sit, as a share of
    /// its outer radius: the stored stars' own.
    private static let stars: [String: (points: Double, inner: Double)] = [
        "star-5": (5, 0.4), "star-4": (4, 0.24), "star-6": (6, 0.52), "star-8": (8, 0.64),
        "seal": (12, 0.84), "burst-16": (16, 0.76),
    ]
    private static let polygons: [String: Double] = ["pentagon": 5, "hexagon": 6, "octagon": 8]
    /// An arrow's head, its length as a share of the box along it, and its
    /// shaft, its thickness as a share of the box across it.
    private static let arrows: [String: (head: Double, shaft: Double)] = [
        "arrow-right": (0.4, 0.4), "arrow-left": (0.4, 0.4), "arrow-up": (0.4, 0.4), "arrow-down": (0.4, 0.4),
        "arrow-double": (0.3, 0.24),
    ]
    /// How deep a chevron's or a ribbon's notch is, as a share of the width;
    /// a tag's, half the height of its tip (0 a point, 0.5 square).
    private static let notches: [String: Double] = ["chevron": 0.3, "ribbon": 0.15, "tag": 0.15]
    /// Where a callout's tail ends, as shares of the box.
    private static let tails: [String: (x: Double, y: Double)] = ["speech": (0.2, 0.95), "thought": (0.08, 0.8)]
    /// The rest of the straight-edged shapes, their stored path's corners in
    /// the 0…100 box.
    private static let fixed: [String: [CGPoint]] = [
        "triangle": points([50, 0, 100, 100, 0, 100]),
        "triangle-down": points([0, 0, 100, 0, 50, 100]),
        "diamond": points([50, 0, 100, 50, 50, 100, 0, 50]),
        "parallelogram": points([25, 0, 100, 0, 75, 100, 0, 100]),
        "trapezoid": points([20, 0, 80, 0, 100, 100, 0, 100]),
        "banner": points([0, 0, 100, 0, 100, 100, 50, 78, 0, 100]),
        "cross": points([35, 0, 65, 0, 65, 35, 100, 35, 100, 65, 65, 65, 65, 100, 35, 100,
                         35, 65, 0, 65, 0, 35, 35, 35]),
        "lightning": points([60, 0, 15, 58, 42, 58, 32, 100, 85, 40, 55, 40]),
    ]

    private static func points(_ xy: [Double]) -> [CGPoint] {
        stride(from: 0, to: xy.count - 1, by: 2).map { CGPoint(x: xy[$0], y: xy[$0 + 1]) }
    }

    // MARK: what a shape takes

    /// The parameters `id` takes, at the shape's own values; none for a
    /// shape that has none.
    static func defaults(_ id: String) -> [String: Double] {
        if let star = stars[id] { return ["points": star.points, "inner": star.inner] }
        if let sides = polygons[id] { return ["sides": sides] }
        if let arrow = arrows[id] { return ["head": arrow.head, "shaft": arrow.shaft] }
        if let notch = notches[id] { return ["notch": notch] }
        if let tail = tails[id] { return ["tailX": tail.x, "tailY": tail.y] }
        return [:]
    }

    /// Whether Corner rounding rounds `id`: a straight-edged shape. The
    /// rectangles round as they always have (CornerPatterns), and the
    /// callouts and curved shapes not at all.
    static func rounds(_ id: String) -> Bool {
        tails[id] == nil && (fixed[id] != nil || !defaults(id).isEmpty)
    }

    /// Whether `id` is drawn here at all, rounded or shaped.
    static func builds(_ id: String) -> Bool {
        rounds(id) || tails[id] != nil
    }

    /// Parameter `key` of shape `id`: as `params` sets it, held to its
    /// range — whole for points and sides (halves away from zero), a double
    /// arrow's head to half — or the shape's own.
    static func value(_ id: String, _ params: [String: Double]?, _ key: String) -> Double {
        let own = defaults(id)[key] ?? 0
        var v = params?[key].flatMap { $0.isFinite ? $0 : nil } ?? own
        if let range = limits[key] { v = min(max(v, range.lowerBound), range.upperBound) }
        if id == "arrow-double" && key == "head" { v = min(v, 0.5) }
        if wholeKeys.contains(key) { v = v.rounded() }
        return v
    }

    /// `params` as kept on a shape `id`: the ones it takes, held to their
    /// ranges, and only those that differ from its own; nil when none do.
    static func kept(_ id: String, _ params: [String: Double]?) -> [String: Double]? {
        guard let params else { return nil }
        var out: [String: Double] = [:]
        for (key, own) in defaults(id) where params[key] != nil {
            let v = value(id, params, key)
            if abs(v - own) > same { out[key] = v }
        }
        return out.isEmpty ? nil : out
    }

    // MARK: the outline

    /// `id`'s corners in the 0…100 box with `params`; nil for a shape that
    /// is not a polygon (a callout, a curve, a rectangle, an icon). The
    /// Android twin's polygon, number for number.
    static func unitPolygon(_ id: String, _ params: [String: Double]?) -> [CGPoint]? {
        if let shape = fixed[id] { return shape }
        if stars[id] != nil {
            let n = Int(value(id, params, "points"))
            let inner = value(id, params, "inner")
            return (0..<(2 * n)).map { k -> CGPoint in
                let a = -Double.pi / 2 + Double(k) * Double.pi / Double(n)
                let r = k % 2 == 0 ? 50.0 : 50.0 * inner
                return CGPoint(x: 50 + r * cos(a), y: 50 + r * sin(a))
            }
        }
        if polygons[id] != nil {
            // A corner straight up when the sides are odd, a flat top when even.
            let n = Int(value(id, params, "sides"))
            let start = n % 2 == 1 ? -Double.pi / 2 : -Double.pi / 2 + Double.pi / Double(n)
            return (0..<n).map { k -> CGPoint in
                let a = start + 2 * Double.pi * Double(k) / Double(n)
                return CGPoint(x: 50 + 50 * cos(a), y: 50 + 50 * sin(a))
            }
        }
        if arrows[id] != nil { return arrow(id, head: value(id, params, "head") * 100, shaft: value(id, params, "shaft")) }
        if notches[id] != nil {
            let n = value(id, params, "notch") * 100
            switch id {
            case "chevron": return points([0, 0, 100 - n, 0, 100, 50, 100 - n, 100, 0, 100, n, 50])
            case "ribbon": return points([0, 20, 100, 20, 100 - n, 50, 100, 80, 0, 80, n, 50])
            default: return points([0, 50 - n, 60, 0, 100, 0, 100, 100, 60, 100, 0, 50 + n])
            }
        }
        return nil
    }

    /// An arrow pointing right, from its head's length (in the box's
    /// units) and its shaft's share, turned for the others.
    private static func arrow(_ id: String, head: Double, shaft: Double) -> [CGPoint] {
        let lo = 50 - shaft * 50, hi = 50 + shaft * 50
        let right = points([0, lo, 100 - head, lo, 100 - head, 10, 100, 50, 100 - head, 90, 100 - head, hi, 0, hi])
        switch id {
        case "arrow-right": return right
        case "arrow-left": return right.map { CGPoint(x: 100 - $0.x, y: $0.y) }
        case "arrow-down": return right.map { CGPoint(x: $0.y, y: $0.x) }
        case "arrow-up": return right.map { CGPoint(x: $0.y, y: 100 - $0.x) }
        default:
            return points([0, 50, head, 15, head, lo, 100 - head, lo, 100 - head, 15, 100, 50,
                           100 - head, 85, 100 - head, hi, head, hi, head, 85])
        }
    }

    /// Shape `id`'s outline as SVG path data at `w` × `h`, every corner
    /// rounded by `radius` and its parameters `params` (see above); nil for
    /// a shape not built here. A callout ignores the radius.
    static func path(_ id: String, w: Double, h: Double, radius: Double, params: [String: Double]?) -> String? {
        if tails[id] != nil { return callout(id, w: w, h: h, params: params) }
        guard let unit = unitPolygon(id, params) else { return nil }
        let corners = unit.map { CGPoint(x: Double($0.x) * w / 100, y: Double($0.y) * h / 100) }
        return filleted(corners, radius: radius.isFinite ? radius : 0)
    }

    /// A speech bubble's or round callout's outline at `w` × `h`: the
    /// library's own path but for its tail's tip, where its parameters put
    /// it.
    private static func callout(_ id: String, w: Double, h: Double, params: [String: Double]?) -> String {
        func at(_ x: Double, _ y: Double) -> String { pt(CGPoint(x: x * w / 100, y: y * h / 100)) }
        let t = at(value(id, params, "tailX") * 100, value(id, params, "tailY") * 100)
        if id == "speech" {
            let top = "M\(at(10, 0))L\(at(90, 0))Q\(at(100, 0)) \(at(100, 10))L\(at(100, 60))Q\(at(100, 70)) \(at(90, 70))"
            let tail = "L\(at(45, 70))L\(t)L\(at(25, 70))L\(at(10, 70))"
            let back = "Q\(at(0, 70)) \(at(0, 60))L\(at(0, 10))Q\(at(0, 0)) \(at(10, 0))Z"
            return top + tail + back
        }
        let top = "M\(at(50, 0))C\(at(77, 0)) \(at(100, 15)) \(at(100, 35))C\(at(100, 55)) \(at(77, 70)) \(at(50, 70))"
        let tail = "C\(at(43, 70)) \(at(36, 69)) \(at(30, 67))L\(t)L\(at(18, 60))"
        let back = "C\(at(7, 53)) \(at(0, 45)) \(at(0, 35))C\(at(0, 15)) \(at(23, 0)) \(at(50, 0))Z"
        return top + tail + back
    }

    private static func pt(_ p: CGPoint) -> String { "\(num(Double(p.x))),\(num(Double(p.y)))" }

    /// The closed polygon `corners`, each rounded (see above), as path data:
    /// a corner repeated is dropped; each corner written M (the first) or L
    /// to where its arc starts, then A r,r 0 0 sweep to where it ends, or
    /// just M or L to the corner when it is not rounded; then Z.
    static func filleted(_ corners: [CGPoint], radius: Double) -> String {
        var list: [CGPoint] = []
        for p in corners where list.last != p { list.append(p) }
        if list.count > 1, list.first == list.last { list.removeLast() }
        let n = list.count
        var d = ""
        for i in 0..<n {
            let v = list[i], prev = list[(i + n - 1) % n], next = list[(i + 1) % n]
            let vx = Double(v.x), vy = Double(v.y)
            let px = Double(prev.x), py = Double(prev.y), nx = Double(next.x), ny = Double(next.y)
            let a = hypot(px - vx, py - vy)
            let b = hypot(nx - vx, ny - vy)
            let move = i == 0 ? "M" : "L"
            var t = 0.0
            var r = 0.0
            if radius > 0, a > 0, b > 0 {
                let cosine = min(max(((px - vx) * (nx - vx) + (py - vy) * (ny - vy)) / (a * b), -1), 1)
                let half = tan(acos(cosine) / 2)
                if half > 1e-9, half < 1e9 {
                    let limit = min(a, b) / 2
                    r = min(radius, limit)
                    t = r / half
                    if t > limit {
                        t = limit
                        r = t * half
                    }
                }
            }
            guard t > 0 else {
                d += move + pt(v)
                continue
            }
            let start = CGPoint(x: vx + (px - vx) / a * t, y: vy + (py - vy) / a * t)
            let end = CGPoint(x: vx + (nx - vx) / b * t, y: vy + (ny - vy) / b * t)
            // A turn clockwise on the page sweeps the arc clockwise.
            let turn = (vx - px) * (ny - vy) - (vy - py) * (nx - vx)
            d += move + pt(start) + "A" + num(r) + "," + num(r) + " 0 0 " + (turn > 0 ? "1" : "0") + " " + pt(end)
        }
        return d + "Z"
    }

    /// A number as the paths write it: to the hundredth, a whole one with
    /// no point.
    static func num(_ v: Double) -> String {
        let rounded = (v * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    // MARK: on an element

    /// The library shape `el` is drawn from when its outline is built here:
    /// a straight-edged shape or a callout from the library (no drawn path),
    /// whatever its rounding and parameters, as the Android twin's pathOf.
    /// Nil draws the stored path.
    static func builtId(_ el: Element) -> String? {
        guard el.type == .shape, el.pathData?.isEmpty ?? true, let id = el.shapeId,
              ContentLibrary.shapeMap[id] != nil, builds(id) else { return nil }
        return built(id, radius: el.radius ?? 0, params: el.shapeParams)
    }

    /// `id` when a shape of it is built here rather than drawn from the
    /// stored path: always, for one that builds — at its own rounding and
    /// parameters it is the stored polygon.
    static func built(_ id: String, radius: Double, params: [String: Double]?) -> String? {
        builds(id) ? id : nil
    }

    /// `el`'s outline at its own size, when it is built here.
    static func outline(_ el: Element) -> String? {
        guard let id = builtId(el) else { return nil }
        return path(id, w: el.w, h: el.h, radius: el.radius ?? 0, params: el.shapeParams)
    }

    /// `el` with parameter `key` set to `value`, held to its range, and
    /// `shapeParams` keeping only what differs from the shape's own.
    static func setting(_ key: String, to value: Double, on el: inout Element) {
        guard let id = el.shapeId else { return }
        var params = el.shapeParams ?? [:]
        params[key] = value
        el.shapeParams = kept(id, params)
    }

    // MARK: handles

    /// The yellow handles a selected shape of `id` shows, in its box's units
    /// (0…1 across and down): a star's first inner corner, an arrow's head
    /// where it meets the shaft, a callout's tail tip, a notch's point (a
    /// tag's tip's top corner). None for a
    /// polygon, whose sides are counted rather than dragged.
    static func handles(_ id: String, _ params: [String: Double]?) -> [CGPoint] {
        if stars[id] != nil {
            let n = value(id, params, "points"), inner = value(id, params, "inner")
            let a = -Double.pi / 2 + Double.pi / n
            return [CGPoint(x: 0.5 + 0.5 * inner * cos(a), y: 0.5 + 0.5 * inner * sin(a))]
        }
        if arrows[id] != nil {
            let h = value(id, params, "head"), s = value(id, params, "shaft")
            switch id {
            case "arrow-right": return [CGPoint(x: 1 - h, y: 0.5 - s / 2)]
            case "arrow-left", "arrow-double": return [CGPoint(x: h, y: 0.5 - s / 2)]
            case "arrow-up": return [CGPoint(x: 0.5 - s / 2, y: h)]
            default: return [CGPoint(x: 0.5 - s / 2, y: 1 - h)]
            }
        }
        if notches[id] != nil {
            let n = value(id, params, "notch")
            return id == "tag" ? [CGPoint(x: 0, y: 0.5 - n)] : [CGPoint(x: n, y: 0.5)]
        }
        if tails[id] != nil {
            return [CGPoint(x: value(id, params, "tailX"), y: value(id, params, "tailY"))]
        }
        return []
    }

    /// `params` with the handle of shape `id` dragged to `unit`, in its
    /// box's units, each value held to its range: a star's inner radius its
    /// distance from the middle over 0.5, an arrow's head and shaft from the
    /// corner, a callout's tail tip there, a notch from its place (a tag's
    /// 0.5 less how far down).
    static func dragged(_ id: String, _ params: [String: Double]?, to unit: CGPoint) -> [String: Double]? {
        let x = Double(unit.x), y = Double(unit.y)
        var out = params ?? [:]
        if stars[id] != nil {
            out["inner"] = hypot(x - 0.5, y - 0.5) / 0.5
        } else if arrows[id] != nil {
            switch id {
            case "arrow-right": out["head"] = 1 - x; out["shaft"] = 1 - 2 * y
            case "arrow-left", "arrow-double": out["head"] = x; out["shaft"] = 1 - 2 * y
            case "arrow-up": out["head"] = y; out["shaft"] = 1 - 2 * x
            default: out["head"] = 1 - y; out["shaft"] = 1 - 2 * x
            }
        } else if notches[id] != nil {
            out["notch"] = id == "tag" ? 0.5 - y : x
        } else if tails[id] != nil {
            out["tailX"] = x
            out["tailY"] = y
        } else {
            return kept(id, params)
        }
        // Held to their ranges, and what is the shape's own dropped.
        var held = out
        for key in out.keys { held[key] = value(id, out, key) }
        return kept(id, held)
    }

    /// What VoiceOver calls a handle of `id`.
    static func handleName(_ id: String) -> String {
        if stars[id] != nil { return tr("Inner radius") }
        if arrows[id] != nil { return tr("Arrow head") }
        if notches[id] != nil { return tr("Notch") }
        return tr("Tail")
    }

    /// Whether the shape counts points (a star) or sides (a polygon), and
    /// which: the key a stepper sets.
    static func countKey(_ id: String) -> String? {
        if stars[id] != nil { return "points" }
        if polygons[id] != nil { return "sides" }
        return nil
    }
}
