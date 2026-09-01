// Minimal SVG path parser for the shape library. The library only uses
// absolute commands: M, L, H, V, C, Q, A, Z. Elliptical arcs are converted
// via the SVG spec's endpoint->center parameterization (F.6) and emitted
// as cubic Bézier segments.

import CoreGraphics
import Foundation

enum SVGPath {

    private static var cache: [String: CGPath] = [:]

    /// Parse a path definition in the library's 0…100 viewBox space.
    static func path(_ d: String) -> CGPath {
        if let cached = cache[d] { return cached }
        let path = CGMutablePath()
        var scanner = Tokenizer(d)
        var current = CGPoint.zero
        var start = CGPoint.zero

        while let cmd = scanner.nextCommand() {
            switch cmd {
            case "M":
                if let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    current = CGPoint(x: x, y: y)
                    path.move(to: current)
                    start = current
                }
                // Additional coordinate pairs after M are implicit L.
                while scanner.numberFollows,
                      let lx = scanner.nextNumber(), let ly = scanner.nextNumber() {
                    current = CGPoint(x: lx, y: ly)
                    path.addLine(to: current)
                }
            case "L":
                while let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    current = CGPoint(x: x, y: y)
                    path.addLine(to: current)
                    if !scanner.numberFollows { break }
                }
            case "H":
                while let x = scanner.nextNumber() {
                    current = CGPoint(x: x, y: current.y)
                    path.addLine(to: current)
                    if !scanner.numberFollows { break }
                }
            case "V":
                while let y = scanner.nextNumber() {
                    current = CGPoint(x: current.x, y: y)
                    path.addLine(to: current)
                    if !scanner.numberFollows { break }
                }
            case "C":
                while let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                      let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    current = CGPoint(x: x, y: y)
                    path.addCurve(to: current,
                                  control1: CGPoint(x: x1, y: y1),
                                  control2: CGPoint(x: x2, y: y2))
                    if !scanner.numberFollows { break }
                }
            case "Q":
                while let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    current = CGPoint(x: x, y: y)
                    path.addQuadCurve(to: current, control: CGPoint(x: x1, y: y1))
                    if !scanner.numberFollows { break }
                }
            case "A":
                while let rx = scanner.nextNumber(), let ry = scanner.nextNumber(),
                      let rot = scanner.nextNumber(),
                      let largeArc = scanner.nextNumber(), let sweep = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    let end = CGPoint(x: x, y: y)
                    addArc(to: path, from: current, to: end,
                           rx: rx, ry: ry, rotationDeg: rot,
                           largeArc: largeArc != 0, sweep: sweep != 0)
                    current = end
                    if !scanner.numberFollows { break }
                }
            case "Z":
                path.closeSubpath()
                current = start
            default:
                break
            }
        }
        cache[d] = path
        return path
    }

    /// Path scaled from the 100×100 definition space to an arbitrary size,
    /// with optional corner radius override for rect-like shapes.
    static func scaledPath(_ d: String, to size: CGSize) -> CGPath {
        var transform = CGAffineTransform(scaleX: size.width / 100, y: size.height / 100)
        return path(d).copy(using: &transform) ?? path(d)
    }

    // MARK: arc conversion (SVG spec F.6.5 / F.6.6)

    private static func addArc(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint,
                               rx rxIn: Double, ry ryIn: Double, rotationDeg: Double,
                               largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx < 1e-9 || ry < 1e-9 || (p0.x == p1.x && p0.y == p1.y) {
            path.addLine(to: p1)
            return
        }
        let phi = rotationDeg * .pi / 180
        let cosPhi = CoreGraphics.cos(phi), sinPhi = CoreGraphics.sin(phi)

        // (F.6.5.1) transform to the ellipse-aligned frame
        let dx2 = (p0.x - p1.x) / 2, dy2 = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // (F.6.6) scale radii up if the endpoints can't be reached
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = lambda.squareRoot()
            rx *= s; ry *= s
        }

        // (F.6.5.2) center in the primed frame
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var factor = den < 1e-12 ? 0 : max(0, num / den).squareRoot()
        if largeArc == sweep { factor = -factor }
        let cxp = factor * (rx * y1p / ry)
        let cyp = factor * (-ry * x1p / rx)

        // (F.6.5.3) center in the original frame
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        // (F.6.5.5 / F.6.5.6) start and sweep angles
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = ((ux * ux + uy * uy) * (vx * vx + vy * vy)).squareRoot()
            var a = CoreGraphics.acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
                           (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        // Emit cubic Béziers in segments of at most 90°.
        let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / Double(segments)
        let t = 4.0 / 3.0 * tan(delta / 4)
        var angle1 = theta1
        var prev = p0
        for _ in 0..<segments {
            let angle2 = angle1 + delta
            let cos1 = CoreGraphics.cos(angle1), sin1 = CoreGraphics.sin(angle1)
            let cos2 = CoreGraphics.cos(angle2), sin2 = CoreGraphics.sin(angle2)

            func onEllipse(_ c: Double, _ s: Double) -> CGPoint {
                CGPoint(
                    x: cx + rx * c * cosPhi - ry * s * sinPhi,
                    y: cy + rx * c * sinPhi + ry * s * cosPhi)
            }
            func derivative(_ c: Double, _ s: Double) -> CGPoint {
                CGPoint(
                    x: -rx * s * cosPhi - ry * c * sinPhi,
                    y: -rx * s * sinPhi + ry * c * cosPhi)
            }

            let end = onEllipse(cos2, sin2)
            let d1 = derivative(cos1, sin1)
            let d2 = derivative(cos2, sin2)
            let c1 = CGPoint(x: prev.x + t * d1.x, y: prev.y + t * d1.y)
            let c2 = CGPoint(x: end.x - t * d2.x, y: end.y - t * d2.y)
            path.addCurve(to: end, control1: c1, control2: c2)
            prev = end
            angle1 = angle2
        }
    }

    // MARK: tokenizer

    private struct Tokenizer {
        private let chars: [Character]
        private var index = 0

        init(_ s: String) { chars = Array(s) }

        var numberFollows: Bool {
            var i = index
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" { i += 1 }
            guard i < chars.count else { return false }
            let c = chars[i]
            return c.isNumber || c == "-" || c == "." || c == "+"
        }

        mutating func nextCommand() -> Character? {
            while index < chars.count {
                let c = chars[index]
                index += 1
                if c.isLetter { return Character(c.uppercased()) }
            }
            return nil
        }

        mutating func nextNumber() -> Double? {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n" {
                index += 1
            }
            var s = ""
            var seenDot = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber { s.append(c); index += 1 }
                else if c == "." && !seenDot { seenDot = true; s.append(c); index += 1 }
                else if (c == "-" || c == "+") && s.isEmpty { s.append(c); index += 1 }
                else { break }
            }
            return s.isEmpty ? nil : Double(s)
        }
    }
}
