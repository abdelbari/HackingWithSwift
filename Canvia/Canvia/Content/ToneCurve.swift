// Tone curves as presets: the five-point curves a photographer reaches
// for, by name rather than by dragging points on a phone-sized graph.

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum ToneCurve {

    struct Preset: Identifiable, Equatable {
        var id: String
        var name: String
        /// Five points on the unit square, x ascending from 0 to 1.
        var points: [CGPoint]
    }

    static let presets: [Preset] = [
        Preset(id: "fade", name: tr("Fade"), points: [CGPoint(x: 0, y: 0.1), CGPoint(x: 0.25, y: 0.3), CGPoint(x: 0.5, y: 0.52), CGPoint(x: 0.75, y: 0.75), CGPoint(x: 1, y: 0.95)]),
        Preset(id: "lift", name: tr("Lift shadows"), points: [CGPoint(x: 0, y: 0.08), CGPoint(x: 0.25, y: 0.34), CGPoint(x: 0.5, y: 0.55), CGPoint(x: 0.75, y: 0.76), CGPoint(x: 1, y: 1)]),
        Preset(id: "crush", name: tr("Crush blacks"), points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.15), CGPoint(x: 0.5, y: 0.48), CGPoint(x: 0.75, y: 0.76), CGPoint(x: 1, y: 1)]),
        Preset(id: "scurve", name: tr("S-curve"), points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.18), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.75, y: 0.82), CGPoint(x: 1, y: 1)]),
        Preset(id: "matte", name: tr("Matte"), points: [CGPoint(x: 0, y: 0.12), CGPoint(x: 0.25, y: 0.3), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.75, y: 0.7), CGPoint(x: 1, y: 0.9)]),
        Preset(id: "bright", name: tr("Brighten mids"), points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.32), CGPoint(x: 0.5, y: 0.6), CGPoint(x: 0.75, y: 0.82), CGPoint(x: 1, y: 1)]),
    ]

    static func preset(_ id: String?) -> Preset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    // MARK: the curve as numbers, shared with the Android twin

    /// The preset's curve as a table: what each of the 256 levels becomes.
    /// nil for an unknown or missing curve.
    static func table(preset id: String?) -> [Int]? {
        preset(id).map { table($0.points) }
    }

    /// The smooth curve through `points` as a table of 256 steps.
    static func table(_ points: [CGPoint]) -> [Int] {
        (0..<256).map { PhotoLook.byte(at(points, Double($0) / 255) * 255) }
    }

    /// How far a light dial at full moves its point.
    static let lightReach = 0.15

    /// The four light dials — highlights, shadows, whites and blacks — as
    /// one five-point curve, drawn like a preset's on each channel; nil when
    /// all four are at zero. The Android twin builds the same five points:
    ///
    /// - blacks below zero crush the darkest tones: the curve starts at
    ///   (0.15 × −blacks, 0), black from there down; above zero they lift
    ///   black itself, to (0, 0.15 × blacks);
    /// - shadows move the quarter point to (0.25, 0.25 + 0.15 × shadows);
    /// - the middle stays at (0.5, 0.5);
    /// - highlights move the three-quarter point to (0.75, 0.75 + 0.15 × highlights);
    /// - whites above zero clip sooner, the curve reaching white at
    ///   (1 − 0.15 × whites, 1); below zero white itself greys, to
    ///   (1, 1 + 0.15 × whites).
    static func light(highlights: Double, shadows: Double, whites: Double, blacks: Double) -> [CGPoint]? {
        func unit(_ v: Double) -> Double { min(max(v, -1), 1) }
        let h = unit(highlights), s = unit(shadows), w = unit(whites), b = unit(blacks)
        if h == 0 && s == 0 && w == 0 && b == 0 { return nil }
        return [
            b < 0 ? CGPoint(x: -b * lightReach, y: 0) : CGPoint(x: 0, y: b * lightReach),
            CGPoint(x: 0.25, y: 0.25 + s * lightReach),
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.75, y: 0.75 + h * lightReach),
            w > 0 ? CGPoint(x: 1 - w * lightReach, y: 1) : CGPoint(x: 1, y: 1 + w * lightReach),
        ]
    }

    /// The smooth curve through `points` at `x`: a natural cubic spline —
    /// the one that bends least between the points — held at the ends'
    /// values outside them, and within 0…1.
    static func at(_ points: [CGPoint], _ x: Double) -> Double {
        let n = points.count
        guard let first = points.first, let last = points.last else { return x }
        if x <= Double(first.x) { return min(max(Double(first.y), 0), 1) }
        if x >= Double(last.x) { return min(max(Double(last.y), 0), 1) }
        let xs = points.map { Double($0.x) }
        let ys = points.map { Double($0.y) }
        let m = secondDerivatives(xs, ys)
        var i = 0
        while i < n - 2 && x > xs[i + 1] { i += 1 }
        let h = xs[i + 1] - xs[i]
        let a = (xs[i + 1] - x) / h
        let b = (x - xs[i]) / h
        let y = a * ys[i] + b * ys[i + 1] + ((a * a * a - a) * m[i] + (b * b * b - b) * m[i + 1]) * h * h / 6
        return min(max(y, 0), 1)
    }

    /// The spline's second derivative at each point, zero at both ends.
    private static func secondDerivatives(_ xs: [Double], _ ys: [Double]) -> [Double] {
        let n = xs.count
        var m = [Double](repeating: 0, count: n)
        guard n >= 3 else { return m }
        var u = [Double](repeating: 0, count: n)
        for i in 1..<(n - 1) {
            let sig = (xs[i] - xs[i - 1]) / (xs[i + 1] - xs[i - 1])
            let p = sig * m[i - 1] + 2
            m[i] = (sig - 1) / p
            let d = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) - (ys[i] - ys[i - 1]) / (xs[i] - xs[i - 1])
            u[i] = (6 * d / (xs[i + 1] - xs[i - 1]) - sig * u[i - 1]) / p
        }
        for k in stride(from: n - 2, through: 0, by: -1) { m[k] = m[k] * m[k + 1] + u[k] }
        return m
    }

    /// The curve applied to `image` through CIToneCurve; an unknown or nil
    /// name leaves it alone.
    static func apply(_ id: String?, to image: CIImage) -> CIImage {
        guard let p = preset(id) else { return image }
        let f = CIFilter.toneCurve()
        f.inputImage = image
        f.point0 = p.points[0]
        f.point1 = p.points[1]
        f.point2 = p.points[2]
        f.point3 = p.points[3]
        f.point4 = p.points[4]
        return f.outputImage ?? image
    }
}
