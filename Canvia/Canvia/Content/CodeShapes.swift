// A styled QR code's shapes: its dots round or rounded, its three finder
// eyes — found by their module position — each drawn as its own ring and
// middle, rounded or circles, made into one outline that the canvas, the
// SVG and the PowerPoint all draw, and a picture of it for anything that
// draws a code as pixels. The same shapes, number for number, as the Android
// twin's QrCodes.marks and outline (the test rows are shared).

import CoreGraphics
import UIKit

extension CodeGenerator {

    /// Whether module (`x`, `y`) of an `n`-module code is in one of its
    /// three finder patterns — the 7 × 7 squares in its top corners and its
    /// bottom left — which marks draws as eyes of their own.
    static func isFinder(x: Int, y: Int, n: Int) -> Bool {
        (x < 7 && y < 7) || (x >= n - 7 && y < 7) || (x < 7 && y >= n - 7)
    }

    /// A shape a code is drawn with, in module units: a rectangle, one
    /// rounded by `radius`, or an oval, with a `hole` cut from it.
    struct CodeMark: Equatable {
        enum Kind: Equatable { case rect, roundRect, oval }
        var kind: Kind
        var box: CGRect
        var radius: Double = 0
        var hole: [CodeMark] = []
    }

    /// `grid`'s dark modules in `style`'s shapes, a module a unit from its
    /// top left, the same on both phones:
    /// - square dots: each run along a row one rectangle (as runs), with
    ///   square eyes the finders' modules among them;
    /// - round: each module a circle filling it; rounded: each a square
    ///   rounded by 0.3 of a module;
    /// - eyes other than square, each finder as its own shapes: a 7-module
    ///   ring (the 5 inside cut out) and the 3-module middle — rounded by 2,
    ///   1.25 and 0.75 modules, or circles.
    static func marks(_ grid: [[Bool]], style: Look) -> [CodeMark] {
        let n = grid.count
        let ownEyes = style.eyes != square
        func dark(_ x: Int, _ y: Int) -> Bool { grid[y][x] && !(ownEyes && isFinder(x: x, y: y, n: n)) }
        var out: [CodeMark] = []
        if style.dots == square {
            let masked = (0..<n).map { y in (0..<n).map { x in dark(x, y) } }
            out = runs(masked).map { CodeMark(kind: .rect, box: $0) }
        } else {
            for y in 0..<n {
                for x in 0..<n where dark(x, y) {
                    let box = CGRect(x: x, y: y, width: 1, height: 1)
                    out.append(style.dots == "round" ? CodeMark(kind: .oval, box: box) : CodeMark(kind: .roundRect, box: box, radius: 0.3))
                }
            }
        }
        guard ownEyes else { return out }
        for (fx, fy) in [(0, 0), (n - 7, 0), (0, n - 7)] {
            func box(_ inset: Int) -> CGRect {
                CGRect(x: fx + inset, y: fy + inset, width: 7 - 2 * inset, height: 7 - 2 * inset)
            }
            if style.eyes == "circle" {
                out.append(CodeMark(kind: .oval, box: box(0), hole: [CodeMark(kind: .oval, box: box(1))]))
                out.append(CodeMark(kind: .oval, box: box(2)))
            } else {
                out.append(CodeMark(kind: .roundRect, box: box(0), radius: 2, hole: [CodeMark(kind: .roundRect, box: box(1), radius: 1.25)]))
                out.append(CodeMark(kind: .roundRect, box: box(2), radius: 0.75))
            }
        }
        return out
    }

    /// A step of an outline: a move, a line or a cubic to its last point,
    /// or a close.
    enum Step: Equatable {
        case move(CGPoint)
        case line(CGPoint)
        case cubic(CGPoint, CGPoint, CGPoint)
        case close

        /// Where the step ends; nil for a close.
        var end: CGPoint? {
            switch self {
            case .move(let p), .line(let p), .cubic(_, _, let p): return p
            case .close: return nil
            }
        }
    }

    /// A quarter circle's handles, as a share of its radius.
    private static let kappa = 0.5522847498

    /// `marks` as one outline, scaled by `unit` and moved by `dx`, `dy`:
    /// each shape clockwise from its top left (an oval from its top), its
    /// hole the other way round, so either fill rule leaves the hole open;
    /// a rounded corner or an oval's quarter a cubic. What the canvas, SVG
    /// and PowerPoint all draw.
    static func outline(_ marks: [CodeMark], unit: Double = 1, dx: Double = 0, dy: Double = 0) -> [Step] {
        var out: [Step] = []
        func shape(_ m: CodeMark, reverse: Bool) {
            let points = steps(of: m, unit: unit, dx: dx, dy: dy)
            out += reverse ? reversed(points) : points
            out.append(.close)
        }
        for m in marks {
            shape(m, reverse: false)
            for hole in m.hole { shape(hole, reverse: true) }
        }
        return out
    }

    /// One mark's steps, unclosed.
    private static func steps(of m: CodeMark, unit: Double, dx: Double, dy: Double) -> [Step] {
        let x0: Double = dx + Double(m.box.minX) * unit
        let y0: Double = dy + Double(m.box.minY) * unit
        let x1: Double = x0 + Double(m.box.width) * unit
        let y1: Double = y0 + Double(m.box.height) * unit
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        switch m.kind {
        case .oval:
            let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
            let kx = (x1 - x0) / 2 * kappa, ky = (y1 - y0) / 2 * kappa
            return [.move(p(cx, y0)),
                    .cubic(p(cx + kx, y0), p(x1, cy - ky), p(x1, cy)),
                    .cubic(p(x1, cy + ky), p(cx + kx, y1), p(cx, y1)),
                    .cubic(p(cx - kx, y1), p(x0, cy + ky), p(x0, cy)),
                    .cubic(p(x0, cy - ky), p(cx - kx, y0), p(cx, y0))]
        case .rect:
            return [.move(p(x0, y0)), .line(p(x1, y0)), .line(p(x1, y1)), .line(p(x0, y1)), .line(p(x0, y0))]
        case .roundRect:
            let r = min(m.radius * unit, (x1 - x0) / 2, (y1 - y0) / 2)
            guard r > 0 else {
                return [.move(p(x0, y0)), .line(p(x1, y0)), .line(p(x1, y1)), .line(p(x0, y1)), .line(p(x0, y0))]
            }
            let k = r * kappa
            return [.move(p(x0 + r, y0)), .line(p(x1 - r, y0)),
                    .cubic(p(x1 - r + k, y0), p(x1, y0 + r - k), p(x1, y0 + r)), .line(p(x1, y1 - r)),
                    .cubic(p(x1, y1 - r + k), p(x1 - r + k, y1), p(x1 - r, y1)), .line(p(x0 + r, y1)),
                    .cubic(p(x0 + r - k, y1), p(x0, y1 - r + k), p(x0, y1 - r)), .line(p(x0, y0 + r)),
                    .cubic(p(x0, y0 + r - k), p(x0 + r - k, y0), p(x0 + r, y0))]
        }
    }

    /// A closed run of steps drawn the other way round.
    private static func reversed(_ steps: [Step]) -> [Step] {
        guard let last = steps.last?.end else { return steps }
        var out: [Step] = [.move(last)]
        for i in stride(from: steps.count - 1, through: 1, by: -1) {
            let before = steps[i - 1].end ?? last
            if case .cubic(let c1, let c2, _) = steps[i] {
                out.append(.cubic(c2, c1, before))
            } else {
                out.append(.line(before))
            }
        }
        return out
    }

    /// `steps` as SVG path data: "M0 0L1 0L1 1L0 1L0 0Z", numbers to the
    /// hundredth as the Android twin writes them.
    static func svgData(_ steps: [Step]) -> String {
        func n(_ v: CGFloat) -> String {
            let r = (Double(v) * 100).rounded() / 100
            return r == r.rounded() && abs(r) < 1e15 ? String(Int(r)) : String(r)
        }
        func pt(_ p: CGPoint) -> String { "\(n(p.x)) \(n(p.y))" }
        return steps.map { step -> String in
            switch step {
            case .move(let p): return "M" + pt(p)
            case .line(let p): return "L" + pt(p)
            case .cubic(let a, let b, let p): return "C" + pt(a) + " " + pt(b) + " " + pt(p)
            case .close: return "Z"
            }
        }.joined()
    }

    /// `steps` as a path, to fill even-odd.
    static func path(_ steps: [Step]) -> CGPath {
        let path = CGMutablePath()
        for step in steps {
            switch step {
            case .move(let p): path.move(to: p)
            case .line(let p): path.addLine(to: p)
            case .cubic(let a, let b, let p): path.addCurve(to: p, control1: a, control2: b)
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    /// A styled code's picture, `side` pixels square: its background, its
    /// marks in its colour, and its logo on a pad of the background's
    /// colour (white for none), placed as vector places them. Drawn with a
    /// renderer whose origin is the top left, so it comes out the right way
    /// up.
    static func drawn(_ grid: [[Bool]], side: Int, style: Look) -> UIImage? {
        let n = grid.count
        guard n > 0, side > 0 else { return nil }
        let around = 2 * min(max(style.margin, 0), quiet)
        let unit = Double(max(side / max(n + around, 1), 1))
        let inset = Double(max((side - Int(unit) * n) / 2, 0))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let g = ctx.cgContext
            if let paper = style.background {
                g.setFillColor(UIColor(hex: paper).cgColor)
                g.fill(CGRect(origin: .zero, size: size))
            }
            g.addPath(path(outline(marks(grid, style: style), unit: unit, dx: inset, dy: inset)))
            g.setFillColor(UIColor(hex: style.color).cgColor)
            g.fillPath(using: .evenOdd)
            guard let logo = style.logo else { return }
            let whole = Double(n) * unit
            let padSide = whole * logoShare
            let pad = CGRect(x: inset + (whole - padSide) / 2, y: inset + (whole - padSide) / 2, width: padSide, height: padSide)
            g.setFillColor(UIColor(hex: style.background ?? defaultBackground).cgColor)
            g.fill(pad)
            if let picture = PhotoLibrary.resolve(logo), let box = logoBox(pad) {
                picture.draw(in: fitted(picture.size, in: box))
            }
        }
    }

    /// A picture of `size` fitted whole into `box`, centred.
    static func fitted(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }
}
