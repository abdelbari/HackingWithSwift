// Bitmap to vector: a logo, a signature, a cut-out silhouette traced into a
// path shape that scales cleanly and takes any fill.
//
// The picture is sampled onto a small grid; a cell is ink when it is opaque
// (for a picture with transparency) or dark (for one without). The ink's
// outline is walked cell edge by cell edge into closed loops — holes come
// out wound the other way, so a nonzero fill keeps them open — each loop is
// simplified and smoothed, and the result is path data in the element's
// 0…100 box.

import CoreGraphics
import Foundation
import UIKit

enum Tracer {

    struct Result: Equatable {
        /// Path data in a 0…100 box.
        var pathData: String
        /// Where the ink sits in the picture, in unit coordinates.
        var bounds: CGRect
        /// The ink's average colour.
        var color: String
    }

    /// Cells as a row-major grid of Bools, `width` wide.
    struct Mask {
        var width: Int
        var height: Int
        var cells: [Bool]
        func ink(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < width && y < height && cells[y * width + x]
        }
    }

    static func trace(_ image: UIImage, maxEdge: Int = 96, threshold: Double = 0.5) -> Result? {
        guard let (mask, color) = sample(image, maxEdge: maxEdge, threshold: threshold) else { return nil }
        return trace(mask: mask, color: color)
    }

    static func trace(mask: Mask, color: String) -> Result? {
        let loops = outlines(of: mask)
        guard !loops.isEmpty else { return nil }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for loop in loops { for p in loop { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) } }
        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        var d = ""
        for loop in loops {
            let simplified = simplify(loop, tolerance: 0.6)
            guard simplified.count >= 3 else { continue }
            let unit = simplified.map { CGPoint(x: ($0.x - minX) / w * 100, y: ($0.y - minY) / h * 100) }
            d += smoothClosed(unit)
        }
        guard !d.isEmpty else { return nil }
        return Result(pathData: d,
                      bounds: CGRect(x: minX / Double(mask.width), y: minY / Double(mask.height),
                                     width: w / Double(mask.width), height: h / Double(mask.height)),
                      color: color)
    }

    // MARK: sampling

    private static func sample(_ image: UIImage, maxEdge: Int, threshold: Double) -> (Mask, String)? {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return nil }
        let scale = Double(maxEdge) / Double(max(cg.width, cg.height))
        let w = max(2, Int((Double(cg.width) * min(scale, 1)).rounded()))
        let h = max(2, Int((Double(cg.height) * min(scale, 1)).rounded()))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Transparent anywhere: the alpha is the stencil. Otherwise darkness is.
        var hasAlpha = false
        var i = 3
        while i < pixels.count { if pixels[i] < 128 { hasAlpha = true; break }; i += 4 }
        var cells = [Bool](repeating: false, count: w * h)
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for p in 0..<(w * h) {
            let a = Double(pixels[p * 4 + 3]) / 255
            let pr = Double(pixels[p * 4]) / 255 / max(a, 0.001)
            let pg = Double(pixels[p * 4 + 1]) / 255 / max(a, 0.001)
            let pb = Double(pixels[p * 4 + 2]) / 255 / max(a, 0.001)
            let lum = 0.2126 * pr + 0.7152 * pg + 0.0722 * pb
            let ink = hasAlpha ? a >= 0.5 : lum < threshold
            cells[p] = ink
            if ink { r += min(pr, 1); g += min(pg, 1); b += min(pb, 1); n += 1 }
        }
        guard n > 0 else { return nil }
        // The context drew the image with row 0 at the bottom; flip the grid so
        // y runs down like the page.
        var flipped = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w { flipped[y * w + x] = cells[(h - 1 - y) * w + x] } }
        let hex = String(format: "#%02x%02x%02x", Int((r / n * 255).rounded()), Int((g / n * 255).rounded()), Int((b / n * 255).rounded()))
        return (Mask(width: w, height: h, cells: flipped), hex)
    }

    // MARK: outlines

    /// Directed boundary edges of the ink, chained into closed loops. Ink is
    /// kept on the right of each edge as it is walked, so outer loops turn
    /// one way and holes the other.
    static func outlines(of mask: Mask) -> [[CGPoint]] {
        struct Key: Hashable { var x: Int; var y: Int }
        var edges: [Key: [Key]] = [:]
        func add(_ a: (Int, Int), _ b: (Int, Int)) {
            edges[Key(x: a.0, y: a.1), default: []].append(Key(x: b.0, y: b.1))
        }
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.ink(x, y) {
                if !mask.ink(x, y - 1) { add((x, y), (x + 1, y)) }           // top, left to right
                if !mask.ink(x + 1, y) { add((x + 1, y), (x + 1, y + 1)) }   // right, down
                if !mask.ink(x, y + 1) { add((x + 1, y + 1), (x, y + 1)) }   // bottom, right to left
                if !mask.ink(x - 1, y) { add((x, y + 1), (x, y)) }           // left, up
            }
        }
        var loops: [[CGPoint]] = []
        while let start = edges.keys.min(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
            var loop: [CGPoint] = []
            var current = start
            var guardCount = 0
            repeat {
                loop.append(CGPoint(x: Double(current.x), y: Double(current.y)))
                guard var outs = edges[current], let next = outs.first else { break }
                outs.removeFirst()
                if outs.isEmpty { edges.removeValue(forKey: current) } else { edges[current] = outs }
                current = next
                guardCount += 1
            } while current != start && guardCount < 1_000_000
            if loop.count >= 4 { loops.append(loop) }
        }
        return loops
    }

    /// Ramer–Douglas–Peucker on a closed loop, in cell units.
    static func simplify(_ loop: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard loop.count > 4 else { return loop }
        // Open the loop at its farthest point from the first, so both halves
        // are simplified as open chains, then rejoin.
        var far = 0, farDist = -1.0
        for (i, p) in loop.enumerated() {
            let d = hypot(p.x - loop[0].x, p.y - loop[0].y)
            if d > farDist { farDist = d; far = i }
        }
        let a = rdp(Array(loop[0...far]), tolerance)
        let b = rdp(Array(loop[far...]) + [loop[0]], tolerance)
        return Array(a.dropLast()) + Array(b.dropLast())
    }

    private static func rdp(_ points: [CGPoint], _ tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }
        let a = points[0], b = points[points.count - 1]
        var far = 0, farDist = 0.0
        for i in 1..<(points.count - 1) {
            let d = distance(points[i], toSegment: a, b)
            if d > farDist { farDist = d; far = i }
        }
        guard farDist > tolerance else { return [a, b] }
        return Array(rdp(Array(points[0...far]), tolerance).dropLast()) + rdp(Array(points[far...]), tolerance)
    }

    private static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// A closed polygon as quadratic curves through the midpoints of its
    /// sides, which rounds the cell corners without leaving the shape.
    static func smoothClosed(_ pts: [CGPoint]) -> String {
        guard pts.count >= 3 else { return "" }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        let n = pts.count
        var d = "M\(num(mid(pts[n - 1], pts[0]).x)) \(num(mid(pts[n - 1], pts[0]).y))"
        for i in 0..<n {
            let m = mid(pts[i], pts[(i + 1) % n])
            d += "Q\(num(pts[i].x)) \(num(pts[i].y)) \(num(m.x)) \(num(m.y))"
        }
        return d + "Z"
    }

    private static func num(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(r)
    }
}
