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
        // For S and T: the last control point, reflected for a smooth join.
        var lastControl: CGPoint?
        var lastWasCurve = false

        while let raw = scanner.nextCommand() {
            // Lowercase commands are relative to the current point; the
            // shape library is all absolute, but an imported SVG rarely is.
            let relative = raw.isLowercase
            let cmd = Character(raw.uppercased())
            func abs(_ x: Double, _ y: Double) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            var thisWasCurve = false
            switch cmd {
            case "M":
                if let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    current = abs(x, y)
                    path.move(to: current)
                    start = current
                }
                // Additional coordinate pairs after M are implicit L.
                while scanner.numberFollows,
                      let lx = scanner.nextNumber(), let ly = scanner.nextNumber() {
                    current = abs(lx, ly)
                    path.addLine(to: current)
                }
            case "L":
                while let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    current = abs(x, y)
                    path.addLine(to: current)
                    if !scanner.numberFollows { break }
                }
            case "H":
                while let x = scanner.nextNumber() {
                    current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                    path.addLine(to: current)
                    if !scanner.numberFollows { break }
                }
            case "V":
                while let y = scanner.nextNumber() {
                    current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                    path.addLine(to: current)
                    if !scanner.numberFollows { break }
                }
            case "C":
                while let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                      let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    let c1 = abs(x1, y1), c2 = abs(x2, y2)
                    current = abs(x, y)
                    path.addCurve(to: current, control1: c1, control2: c2)
                    lastControl = c2
                    thisWasCurve = true
                    if !scanner.numberFollows { break }
                }
            case "S":
                while let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    let reflected = (lastWasCurve || thisWasCurve) && lastControl != nil
                        ? CGPoint(x: 2 * current.x - lastControl!.x, y: 2 * current.y - lastControl!.y) : current
                    let c2 = abs(x2, y2)
                    current = abs(x, y)
                    path.addCurve(to: current, control1: reflected, control2: c2)
                    lastControl = c2
                    thisWasCurve = true
                    if !scanner.numberFollows { break }
                }
            case "Q":
                while let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    let c = abs(x1, y1)
                    current = abs(x, y)
                    path.addQuadCurve(to: current, control: c)
                    lastControl = c
                    thisWasCurve = true
                    if !scanner.numberFollows { break }
                }
            case "T":
                while let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    let c = (lastWasCurve || thisWasCurve) && lastControl != nil
                        ? CGPoint(x: 2 * current.x - lastControl!.x, y: 2 * current.y - lastControl!.y) : current
                    current = abs(x, y)
                    path.addQuadCurve(to: current, control: c)
                    lastControl = c
                    thisWasCurve = true
                    if !scanner.numberFollows { break }
                }
            case "A":
                while let rx = scanner.nextNumber(), let ry = scanner.nextNumber(),
                      let rot = scanner.nextNumber(),
                      let largeArc = scanner.nextNumber(), let sweep = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() {
                    let end = abs(x, y)
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
            lastWasCurve = thisWasCurve
        }
        cache[d] = path
        return path
    }

    /// Path data for a CGPath, fitted into the 0…100 box the library uses:
    /// scaled by its longer side and centred on the shorter. What an
    /// imported SVG path becomes.
    static func normalised(_ path: CGPath) -> String? {
        let box = path.boundingBoxOfPath
        guard box.width > 0 || box.height > 0 else { return nil }
        let scale = 100 / max(box.width, box.height)
        var t = CGAffineTransform(translationX: -box.minX, y: -box.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (100 - box.width * scale) / 2,
                                             y: (100 - box.height * scale) / 2))
        guard let fitted = path.copy(using: &t) else { return nil }
        return TextOutliner.svgPathData(fitted)
    }

    /// The first path in an SVG document, as normalised path data.
    static func importFirstPath(fromSVG text: String) -> String? {
        guard let range = text.range(of: #"<path[^>]*\sd\s*=\s*"([^"]*)""#, options: .regularExpression) else { return nil }
        let tag = String(text[range])
        guard let dStart = tag.range(of: #"d\s*=\s*""#, options: .regularExpression) else { return nil }
        let d = tag[dStart.upperBound...].dropLast()
        let parsed = path(String(d))
        return parsed.isEmpty ? nil : normalised(parsed)
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
                if c.isLetter { return c }
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
