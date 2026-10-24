// The outlines of the library's straight-edged shapes built at the
// element's own size, as the Android twin's ShapeGeometry builds them, so
// Corner rounding stays circular however a shape is stretched and a star's
// points, a polygon's sides, an arrow's head and shaft, a callout's tail and
// a chevron's notch can be set (`shapeParams`). The same path draws on the
// canvas, in the SVG and PDF, and in PowerPoint as a free-form shape; the
// shared fixture shape-geometry.json holds rows of it.
//
// Each shape is a polygon in a 0…1 box, times the element's width and
// height. Every vertex is filleted with a circular arc: its radius held to
// half the shorter edge beside it, and how far the arc reaches along each
// edge held to half that edge too, the radius taken down with it, so two
// arcs never cross. A vertex where the outline runs straight on is left.
// The curved shapes — circles, hearts, blobs and the thought bubble's body
// — take no rounding; the thought bubble takes its tail.
//
// At no rounding and every parameter its own, a shape is drawn from the
// library's stored path, as a build without this draws it: the shape's id
// is never changed, and only parameters that differ from the shape's own
// are written.

import CoreGraphics
import Foundation

enum ShapeGeometry {

    /// Each parameter's range; points and sides are whole.
    static let limits: [String: ClosedRange<Double>] = [
        "points": 4...24, "inner": 0.2...0.9, "sides": 3...12, "head": 0.1...0.9, "shaft": 0.1...0.9,
        "tailX": 0...1, "tailY": 0...1.4, "notch": 0...0.5,
    ]
    static let wholeKeys: Set<String> = ["points", "sides"]

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
    /// a tag's, half the height of its tip.
    private static let notches: [String: Double] = ["chevron": 0.3, "ribbon": 0.15, "tag": 0.15]
    /// Where a callout's tail ends, as shares of the box.
    private static let tails: [String: (x: Double, y: Double)] = ["speech": (0.2, 0.95), "thought": (0.08, 0.8)]
    /// The rest of the straight-edged shapes, as stored.
    private static let fixed: [String: [CGPoint]] = [
        "triangle": points([0.5, 0, 1, 1, 0, 1]),
        "triangle-down": points([0, 0, 1, 0, 0.5, 1]),
        "diamond": points([0.5, 0, 1, 0.5, 0.5, 1, 0, 0.5]),
        "parallelogram": points([0.25, 0, 1, 0, 0.75, 1, 0, 1]),
        "trapezoid": points([0.2, 0, 0.8, 0, 1, 1, 0, 1]),
        "banner": points([0, 0, 1, 0, 1, 1, 0.5, 0.78, 0, 1]),
        "cross": points([0.35, 0, 0.65, 0, 0.65, 0.35, 1, 0.35, 1, 0.65, 0.65, 0.65, 0.65, 1, 0.35, 1,
                         0.35, 0.65, 0, 0.65, 0, 0.35, 0.35, 0.35]),
        "lightning": points([0.6, 0, 0.15, 0.58, 0.42, 0.58, 0.32, 1, 0.85, 0.4, 0.55, 0.4]),
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
    /// rectangles round as they always have (CornerPatterns), and the curved
    /// shapes not at all.
    static func rounds(_ id: String) -> Bool {
        id != "thought" && (fixed[id] != nil || !defaults(id).isEmpty)
    }

    /// Whether `id` is drawn here at all, rounded or shaped.
    static func builds(_ id: String) -> Bool {
        rounds(id) || id == "thought"
    }

    /// Parameter `key` of shape `id`: as `params` sets it, held to its
    /// range — whole for points and sides, a double arrow's head to half —
    /// or the shape's own.
    static func value(_ id: String, _ params: [String: Double]?, _ key: String) -> Double {
        let own = defaults(id)[key] ?? 0
        var v = params?[key].flatMap { $0.isFinite ? $0 : nil } ?? own
        if wholeKeys.contains(key) { v = v.rounded() }
        if let range = limits[key] { v = min(max(v, range.lowerBound), range.upperBound) }
        if id == "arrow-double" && key == "head" { v = min(v, 0.5) }
        return v
    }

    /// `params` as kept on a shape `id`: the ones it takes, held to their
    /// ranges, and only those that differ from its own; nil when none do.
    static func kept(_ id: String, _ params: [String: Double]?) -> [String: Double]? {
        guard let params else { return nil }
        var out: [String: Double] = [:]
        for (key, own) in defaults(id) where params[key] != nil {
            let v = value(id, params, key)
            if abs(v - own) > 1e-9 { out[key] = v }
        }
        return out.isEmpty ? nil : out
    }

    // MARK: the outline

    /// `id`'s polygon in a 0…1 box with `params`; nil for a shape that is
    /// not one (a curve, the thought bubble, a rectangle, an icon).
    static func unitPolygon(_ id: String, _ params: [String: Double]?) -> [CGPoint]? {
        if let shape = fixed[id] { return shape }
        if stars[id] != nil {
            let n = Int(value(id, params, "points"))
            let inner = value(id, params, "inner")
            return (0..<(2 * n)).map { k -> CGPoint in
                let a = (-90 + Double(k) * 180 / Double(n)) * .pi / 180
                let r = k % 2 == 0 ? 0.5 : 0.5 * inner
                return CGPoint(x: 0.5 + r * cos(a), y: 0.5 + r * sin(a))
            }
        }
        if polygons[id] != nil {
            // A vertex at the top when the sides are odd, a flat top when even.
            let n = Int(value(id, params, "sides"))
            let start = n % 2 == 1 ? -90.0 : -90.0 + 180.0 / Double(n)
            return (0..<n).map { k -> CGPoint in
                let a = (start + Double(k) * 360 / Double(n)) * .pi / 180
                return CGPoint(x: 0.5 + 0.5 * cos(a), y: 0.5 + 0.5 * sin(a))
            }
        }
        if arrows[id] != nil { return arrow(id, head: value(id, params, "head"), shaft: value(id, params, "shaft")) }
        if notches[id] != nil {
            let n = value(id, params, "notch")
            switch id {
            case "chevron": return points([0, 0, 1 - n, 0, 1, 0.5, 1 - n, 1, 0, 1, n, 0.5])
            case "ribbon": return points([0, 0.2, 1, 0.2, 1 - n, 0.5, 1, 0.8, 0, 0.8, n, 0.5])
            default: return points([0, 0.5 - n, 0.6, 0, 1, 0, 1, 1, 0.6, 1, 0, 0.5 + n])
            }
        }
        if id == "speech" {
            // The body the top 70% of the box; the tail's base a fifth of the
            // width, just right of its tip, kept on the body's foot.
            let tx = value(id, params, "tailX"), ty = value(id, params, "tailY")
            let b0 = min(max(tx + 0.05, 0.1), 0.7)
            return points([0, 0, 1, 0, 1, 0.7, b0 + 0.2, 0.7, tx, ty, b0, 0.7, 0, 0.7])
        }
        return nil
    }

    private static func arrow(_ id: String, head h: Double, shaft s: Double) -> [CGPoint] {
        let a = 0.5 - s / 2, b = 0.5 + s / 2
        switch id {
        case "arrow-right": return points([0, a, 1 - h, a, 1 - h, 0.1, 1, 0.5, 1 - h, 0.9, 1 - h, b, 0, b])
        case "arrow-left": return points([1, a, h, a, h, 0.1, 0, 0.5, h, 0.9, h, b, 1, b])
        case "arrow-up": return points([a, 1, a, h, 0.1, h, 0.5, 0, 0.9, h, b, h, b, 1])
        case "arrow-down": return points([a, 0, a, 1 - h, 0.1, 1 - h, 0.5, 1, 0.9, 1 - h, b, 1 - h, b, 0])
        default:
            return points([0, 0.5, h, 0.15, h, a, 1 - h, a, 1 - h, 0.15, 1, 0.5, 1 - h, 0.85, 1 - h, b, h, b, h, 0.85])
        }
    }

    /// Shape `id`'s outline as SVG path data at `w` × `h`, every corner
    /// rounded by `radius` and its parameters `params` (see above); nil for
    /// a shape not built here. A speech bubble with no radius rounds by a
    /// tenth of its shorter side, as the stored one does.
    static func path(_ id: String, w: Double, h: Double, radius: Double, params: [String: Double]?) -> String? {
        if id == "thought" { return thought(w: w, h: h, params: params) }
        guard let unit = unitPolygon(id, params) else { return nil }
        let corners = unit.map { CGPoint(x: Double($0.x) * w, y: Double($0.y) * h) }
        let r = id == "speech" && !(radius > 0) ? 0.1 * min(w, h) : radius
        return filleted(corners, radius: r.isFinite ? r : 0)
    }

    /// The thought bubble: an ellipse filling the top 70% of the box, and
    /// its tail, from either side of the point of the ellipse facing the
    /// tip (0.3 radians round each way) out to the tip.
    private static func thought(w: Double, h: Double, params: [String: Double]?) -> String {
        let tx = value("thought", params, "tailX") * w, ty = value("thought", params, "tailY") * h
        let cx = 0.5 * w, cy = 0.35 * h, rx = 0.5 * w, ry = 0.35 * h
        let theta = atan2(ry > 0 ? (ty - cy) / ry : 0, rx > 0 ? (tx - cx) / rx : 0)
        func at(_ a: Double) -> String { "\(num(cx + rx * cos(a))) \(num(cy + ry * sin(a)))" }
        return "M\(at(theta + 0.3))A\(num(rx)) \(num(ry)) 0 1 1 \(at(theta - 0.3))L\(num(tx)) \(num(ty))Z"
    }

    /// The closed polygon `corners`, each rounded (see above), as path data.
    static func filleted(_ corners: [CGPoint], radius: Double) -> String {
        func pt(_ p: CGPoint) -> String { "\(num(Double(p.x))) \(num(Double(p.y)))" }
        let n = corners.count
        guard n > 2 else { return "" }
        guard radius > 0 else { return "M" + corners.map(pt).joined(separator: "L") + "Z" }
        var rounded: [(enter: CGPoint, leave: CGPoint, r: Double, sweep: Int)] = []
        for i in 0..<n {
            let p = corners[i], prev = corners[(i + n - 1) % n], next = corners[(i + 1) % n]
            let a = hypot(Double(p.x - prev.x), Double(p.y - prev.y))
            let b = hypot(Double(next.x - p.x), Double(next.y - p.y))
            guard a > 0, b > 0 else {
                rounded.append((p, p, 0, 1))
                continue
            }
            let ux = Double(prev.x - p.x) / a, uy = Double(prev.y - p.y) / a
            let vx = Double(next.x - p.x) / b, vy = Double(next.y - p.y) / b
            let theta = acos(min(max(ux * vx + uy * vy, -1), 1))
            guard theta > 1e-6, Double.pi - theta > 1e-6 else {
                rounded.append((p, p, 0, 1))
                continue
            }
            let half = tan(theta / 2)
            var r = min(radius, a / 2, b / 2)
            var t = r / half
            if t > min(a, b) / 2 {
                t = min(a, b) / 2
                r = t * half
            }
            let enter = CGPoint(x: Double(p.x) + ux * t, y: Double(p.y) + uy * t)
            let leave = CGPoint(x: Double(p.x) + vx * t, y: Double(p.y) + vy * t)
            // A turn clockwise on the page sweeps the arc clockwise.
            let cross = Double(p.x - prev.x) * Double(next.y - p.y) - Double(p.y - prev.y) * Double(next.x - p.x)
            rounded.append((enter, leave, r, cross > 0 ? 1 : 0))
        }
        var d = "M" + pt(rounded[0].leave)
        for i in Array(1..<n) + [0] {
            let c = rounded[i]
            guard c.r > 0 else {
                if i != 0 { d += "L" + pt(c.enter) }
                continue
            }
            d += "L" + pt(c.enter) + "A" + num(c.r) + " " + num(c.r) + " 0 0 \(c.sweep) " + pt(c.leave)
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
    /// a shape from the library (no drawn path), not a rectangle, rounded or
    /// with a parameter of its own set. Nil draws the stored path.
    static func builtId(_ el: Element) -> String? {
        guard el.type == .shape, el.pathData?.isEmpty ?? true, let id = el.shapeId,
              ContentLibrary.shapeMap[id] != nil, builds(id) else { return nil }
        return built(id, radius: el.radius ?? 0, params: el.shapeParams)
    }

    /// `id` when a shape of it rounded by `radius` with `params` is built
    /// here rather than drawn from the stored path.
    static func built(_ id: String, radius: Double, params: [String: Double]?) -> String? {
        guard builds(id) else { return nil }
        let rounded = rounds(id) && radius > 0
        return rounded || kept(id, params) != nil ? id : nil
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
    /// (0…1 across and down): a star's inner corner, an arrow's head where
    /// it meets the shaft, a callout's tail tip, a notch's point. None for a
    /// polygon, whose sides are counted rather than dragged.
    static func handles(_ id: String, _ params: [String: Double]?) -> [CGPoint] {
        if stars[id] != nil {
            let n = value(id, params, "points"), inner = value(id, params, "inner")
            let a = (-90 + 180 / n) * .pi / 180
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
    /// box's units, each value held to its range.
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
            return params
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
