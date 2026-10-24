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
        Preset(id: "wave", name: tr("Wave"), data: "M0 60Q25 10 50 60T100 60"),
        Preset(id: "arch", name: tr("Arch"), data: "M0 95Q50 -20 100 95"),
        Preset(id: "valley", name: tr("Valley"), data: "M0 5Q50 120 100 5"),
        Preset(id: "rise", name: tr("Rising diagonal"), data: "M0 95L100 25"),
        Preset(id: "swoosh", name: tr("Swoosh"), data: "M0 85C30 -10 70 110 100 25"),
        Preset(id: "circle", name: tr("Circle"), data: "M50 5C74.9 5 95 25.1 95 50C95 74.9 74.9 95 50 95C25.1 95 5 74.9 5 50C5 25.1 25.1 5 50 5"),
    ]

    static func preset(_ id: String?) -> Preset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    // MARK: a curve round to a ring

    /// The Curve slider's reach, in degrees of arc the words span: a full
    /// ring each way. A stored value past ±180 is read as it is.
    static let maxCurve = 360.0
    /// Half a ring: past it the Rotate slider shows and the ends start to
    /// part (arcLength); from it the box is the ring's square (ringSide).
    static let halfCurve = 180.0
    /// The Rotate slider's reach (`curveStart`).
    static let maxCurveStart = 180.0
    /// How near ±180 or ±360 the Curve slider is pulled onto them, with a
    /// tick felt as it lands.
    static let curveSnap = 4.0

    /// A curve within ±maxCurve; nil for one that is not a finite number.
    static func keptCurve(_ degrees: Double?) -> Double? {
        guard let degrees, degrees.isFinite else { return nil }
        return min(max(degrees, -maxCurve), maxCurve)
    }

    /// Whether the Rotate slider shows: the curve past half a ring.
    static func showsRotate(_ curve: Double?) -> Bool {
        abs(keptCurve(curve) ?? 0) > halfCurve
    }

    /// The Curve slider's value pulled onto ±180 or ±360 when within
    /// `curveSnap` of one — the half ring and the closed ring people aim
    /// for — and left as it is anywhere else.
    static func snappedCurve(_ degrees: Double) -> Double {
        for stop in [-maxCurve, -halfCurve, halfCurve, maxCurve] where abs(degrees - stop) <= curveSnap {
            return stop
        }
        return degrees
    }

    /// How long the arc is along its baseline, for words `width` long whose
    /// space is `space` wide, curved `degrees`: the words, and past half a
    /// ring a gap growing to one space at a full ring — so at ±360 the last
    /// letter and the first stand a space apart, as if the words went round
    /// once more. The gap is (|degrees| − 180) / 180 of a space: none at 180
    /// and below. The rule both phones share (the Android twin's
    /// TextPaths.arcLength).
    static func arcLength(width: Double, space: Double, degrees: Double) -> Double {
        width + space * min(max((abs(degrees) - halfCurve) / halfCurve, 0), 1)
    }

    /// Where each piece's centre stands round the arc, in degrees clockwise
    /// from the curve's centre — the top for a positive curve, the bottom
    /// for a negative one: pieces `advances` wide laid end to end, the words
    /// centred on it, the whole turned by `start` (curveStart). The rule
    /// both phones place letters by.
    static func arcAngles(_ advances: [Double], space: Double, degrees: Double, start: Double = 0) -> [Double] {
        let width = advances.reduce(0, +)
        let length = arcLength(width: width, space: space, degrees: degrees)
        guard length > 0 else { return advances.map { _ in start } }
        var position = 0.0
        return advances.map { advance in
            let centre = position + advance / 2
            position += advance
            return (centre - width / 2) / length * degrees + start
        }
    }

    /// The side of the square a ring of `radius` with type `size` stands
    /// in, from |curve| ≥ halfCurve: the circle and a type size round it, so
    /// it fits whichever way it is turned.
    static func ringSide(radius: Double, size: Double) -> Double {
        (2 * (abs(radius) + size)).rounded(.up)
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
