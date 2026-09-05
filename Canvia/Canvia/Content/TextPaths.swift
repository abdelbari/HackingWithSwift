// Text along any path: a wave, an arch, a circle, a diagonal — or, since a
// path is only path data in the element's box, whatever a designer draws.
//
// PathWalker flattens a CGPath into a polyline and answers "where is the
// point `d` along it, and which way is it heading", which is all the
// outliner needs to set each glyph on the line.

import CoreGraphics
import Foundation

enum TextPaths {

    struct Preset: Identifiable, Equatable {
        var id: String
        var name: String
        /// Path data in a 0…100 box.
        var data: String
    }

    static let presets: [Preset] = [
        Preset(id: "wave", name: "Wave", data: "M0 60Q25 10 50 60T100 60"),
        Preset(id: "arch", name: "Arch", data: "M0 95Q50 -20 100 95"),
        Preset(id: "valley", name: "Valley", data: "M0 5Q50 120 100 5"),
        Preset(id: "rise", name: "Rising diagonal", data: "M0 95L100 25"),
        Preset(id: "swoosh", name: "Swoosh", data: "M0 85C30 -10 70 110 100 25"),
        Preset(id: "circle", name: "Circle", data: "M50 5C74.9 5 95 25.1 95 50C95 74.9 74.9 95 50 95C25.1 95 5 74.9 5 50C5 25.1 25.1 5 50 5"),
    ]

    static func preset(_ id: String?) -> Preset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }
}

struct PathWalker {
    private(set) var points: [CGPoint] = []
    private(set) var cumulative: [Double] = []

    var length: Double { cumulative.last ?? 0 }

    /// Flattens curves into `segments` straight pieces each.
    init(_ path: CGPath, segments: Int = 24) {
        var pts: [CGPoint] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                current = e.points[0]; subpathStart = current
                if pts.isEmpty { pts.append(current) }
            case .addLineToPoint:
                current = e.points[0]; pts.append(current)
            case .addQuadCurveToPoint:
                let c = e.points[0], p = e.points[1], s = current
                for i in 1...segments {
                    let t = Double(i) / Double(segments), u = 1 - t
                    let a = u * u, b = 2 * u * t, d = t * t
                    let x: Double = a * s.x + b * c.x + d * p.x
                    let y: Double = a * s.y + b * c.y + d * p.y
                    pts.append(CGPoint(x: x, y: y))
                }
                current = p
            case .addCurveToPoint:
                let c1 = e.points[0], c2 = e.points[1], p = e.points[2], s = current
                for i in 1...segments {
                    let t = Double(i) / Double(segments), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, cc = 3 * u * t * t, d = t * t * t
                    let x: Double = a * s.x + b * c1.x + cc * c2.x + d * p.x
                    let y: Double = a * s.y + b * c1.y + cc * c2.y + d * p.y
                    pts.append(CGPoint(x: x, y: y))
                }
                current = p
            case .closeSubpath:
                current = subpathStart; pts.append(current)
            @unknown default:
                break
            }
        }
        points = pts
        var acc = 0.0
        cumulative = [0]
        for i in 1..<max(pts.count, 1) {
            acc += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            cumulative.append(acc)
        }
    }

    /// The point `distance` along the path (clamped to its ends) and the
    /// heading there in radians, y down.
    func locate(_ distance: Double) -> (point: CGPoint, angle: Double) {
        guard points.count >= 2 else { return (points.first ?? .zero, 0) }
        let d = min(max(distance, 0), length)
        var i = 1
        while i < cumulative.count - 1 && cumulative[i] < d { i += 1 }
        let a = points[i - 1], b = points[i]
        let segment = cumulative[i] - cumulative[i - 1]
        let t = segment > 0 ? (d - cumulative[i - 1]) / segment : 0
        let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        return (point, atan2(b.y - a.y, b.x - a.x))
    }
}
