// Drawing by hand: a finger (or a Pencil) stroke becomes a shape.
//
// The stroke is kept as path data in the element's own 0…100 box, drawn
// with a stroke and no fill, so it is an ordinary element afterwards —
// moved, rotated, recoloured, exported as a real path in the SVG — and a
// single undo step. Points are thinned and then smoothed with quadratic
// curves through the midpoints, which takes the sawtooth out of raw touch
// samples without pulling the line off the finger.

import CoreGraphics
import Foundation
import UIKit

enum Freehand {

    /// What the pen lays down: ink; a highlighter — the ink see-through,
    /// three times as wide, multiplying with what is under it as a real one
    /// does; a glow — the ink with a halo of itself; and an eraser, which
    /// lays nothing down and takes away the strokes it passes over. The
    /// Android twin has the same four, and makes the same strokes.
    enum Pen: String, CaseIterable, Identifiable {
        case pen, highlighter, glow, eraser
        var id: String { rawValue }
        var label: String {
            switch self {
            case .pen: return "Pen"
            case .highlighter: return "Highlighter"
            case .glow: return "Glow"
            case .eraser: return "Eraser"
            }
        }
        /// How the pen is used, in a line over the drawing bar — the
        /// Android twin's words.
        var hint: String {
            self == .eraser ? "Drag over strokes to take them away" : "One finger draws, two move the page"
        }
        /// Whether it lays down ink, and so has an ink to choose.
        var hasInk: Bool { self != .eraser }
        var symbol: String {
            switch self {
            case .pen: return "pencil.tip"
            case .highlighter: return "highlighter"
            case .glow: return "sparkles"
            case .eraser: return "eraser"
            }
        }
    }

    struct Tool: Equatable {
        var color = "#1f2430"
        var width: Double = 6
        var pen: Pen = .pen
        /// How see-through the strokes are, 0 to 90 per cent, written as
        /// each stroke's own `opacity`; a highlighter's ink is see-through
        /// besides.
        var transparency: Double = 0
        /// The eraser takes whole strokes rather than the part it passes
        /// over.
        var eraseWhole = false
    }

    /// How see-through a highlighter's ink is, as the two hex digits added
    /// to it.
    static let highlighterAlpha = "73"

    /// The width a stroke is drawn at: a highlighter's is three of the pen's.
    static func drawnWidth(_ tool: Tool) -> Double { tool.pen == .highlighter ? tool.width * 3 : tool.width }

    /// The ink a stroke is drawn in: a highlighter's made see-through.
    static func drawnColor(_ tool: Tool) -> String {
        guard tool.pen == .highlighter, tool.color.count == 7, tool.color.hasPrefix("#") else { return tool.color }
        return tool.color + highlighterAlpha
    }

    /// A glow's halo: the ink itself, soft and all round.
    static func glow(of tool: Tool) -> Shadow {
        Shadow(color: tool.color, opacity: 0.9, blur: tool.width * 3 + 6, offsetX: 0, offsetY: 0)
    }

    /// How far an eraser reaches from the finger, in page units: twice the
    /// size chosen, and never less than a fingertip's worth.
    static func eraserRadius(_ tool: Tool) -> Double { max(tool.width * 2, 12) }

    /// The widths the Size slider settles on, the pen's old six.
    static let widths: [Double] = [2, 4, 6, 10, 16, 24]
    /// The Size slider's reach, in page units.
    static let widthRange: ClosedRange<Double> = 1...60
    /// How near a detent the slider has to come to settle on it.
    static let detentReach = 0.75
    /// The most see-through a stroke is drawn.
    static let maxTransparency: Double = 90

    /// A width from the Size slider: within `detentReach` of one of the old
    /// widths it is that width, else it is whole; always within reach.
    static func snappedWidth(_ value: Double) -> Double {
        let kept = min(max(value, widthRange.lowerBound), widthRange.upperBound)
        if let detent = widths.first(where: { abs($0 - kept) <= detentReach }) { return detent }
        return kept.rounded()
    }

    /// A transparency from its slider: whole, 0 to `maxTransparency`.
    static func keptTransparency(_ value: Double) -> Double {
        min(max(value, 0), maxTransparency).rounded()
    }

    /// The `opacity` a stroke is written with for a transparency.
    static func opacity(transparency: Double) -> Double {
        1 - keptTransparency(transparency) / 100
    }

    /// The name strokes drawn in one go are grouped under when the pen is
    /// put down.
    static let drawingName = "Drawing"
    static let colors: [String] = ["#1f2430", "#ffffff", "#ef4444", "#f59e0b", "#22c55e", "#3b82f6", "#8b5cf6", "#ec4899"]

    /// Drops points closer than `minDistance` to the last one kept: a finger
    /// held still emits dozens of them and they make the smoothed line
    /// wobble in place.
    static func thinned(_ points: [CGPoint], minDistance: Double = 2) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in points {
            if let last = out.last, hypot(p.x - last.x, p.y - last.y) < minDistance { continue }
            out.append(p)
        }
        return out
    }

    /// The smoothed curve: a start and quadratic segments whose ends are
    /// the midpoints between successive samples and whose controls are the
    /// samples themselves, so the curve passes near every sample and is
    /// continuous in slope. Fewer than three points draw straight.
    static func segments(_ raw: [CGPoint]) -> (start: CGPoint, quads: [(control: CGPoint, end: CGPoint)])? {
        let points = thinned(raw)
        guard let first = points.first else { return nil }
        if points.count < 3 {
            let end = points.last ?? first
            return (first, [(control: CGPoint(x: (first.x + end.x) / 2, y: (first.y + end.y) / 2), end: end)])
        }
        var quads: [(control: CGPoint, end: CGPoint)] = []
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            quads.append((control: points[i], end: mid))
        }
        quads.append((control: points[points.count - 1], end: points[points.count - 1]))
        return (first, quads)
    }

    static func cgPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let seg = segments(points) else { return path }
        path.move(to: seg.start)
        for q in seg.quads { path.addQuadCurve(to: q.end, control: q.control) }
        return path
    }

    /// SVG path data for the smoothed curve through `points`, in the space
    /// they are given in.
    static func pathData(_ points: [CGPoint]) -> String {
        guard let seg = segments(points) else { return "" }
        var d = "M\(num(seg.start.x)) \(num(seg.start.y))"
        for q in seg.quads {
            d += "Q\(num(q.control.x)) \(num(q.control.y)) \(num(q.end.x)) \(num(q.end.y))"
        }
        return d
    }

    /// The stroke's bounds padded by half its width so the line is not
    /// clipped at the element's edge, and at least the width across, so a
    /// dot is a dot.
    static func bounds(of points: [CGPoint], width: Double) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let pad = width / 2 + 1
        return CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + 2 * pad, height: maxY - minY + 2 * pad)
    }

    /// The element for a stroke in page units: a shape with the curve as
    /// path data normalised into its box, stroked in the tool's colour with
    /// no fill.
    static func element(points raw: [CGPoint], tool: Tool) -> Element? {
        guard tool.pen != .eraser else { return nil }
        var e = Element.shape("freehand")
        e.fill = Paint.clear
        e.stroke = drawnColor(tool)
        e.strokeWidth = drawnWidth(tool)
        e.radius = nil
        let shown = opacity(transparency: tool.transparency)
        if shown < 1 { e.opacity = shown }
        if tool.pen == .highlighter { e.blendMode = "multiply" }
        if tool.pen == .glow { e.shadow = glow(of: tool) }
        return laid(e, along: raw)
    }

    /// `base` — its ink, width, opacity, blend, glow and group — drawn
    /// along `raw` (page units): placed in the stroke's padded bounds,
    /// upright and unflipped, with the curve normalised into its box.
    static func laid(_ base: Element, along raw: [CGPoint]) -> Element? {
        let points = thinned(raw)
        guard let box = bounds(of: points, width: base.strokeWidth ?? 0) else { return nil }
        let unit = points.map { p in
            CGPoint(x: (p.x - box.minX) / box.width * 100, y: (p.y - box.minY) / box.height * 100)
        }
        var e = base
        e.x = box.minX
        e.y = box.minY
        e.w = box.width
        e.h = box.height
        e.rotation = 0
        e.flipH = false
        e.flipV = false
        e.pathData = pathData(unit)
        return e
    }

    /// One stroke the eraser cut: its id, and what is left of it — none
    /// when it was rubbed out whole.
    struct Cut: Equatable {
        var id: String
        var pieces: [Element]
    }

    /// What an eraser dragged along `path` (page units) leaves of the
    /// strokes it passes over: each stroke's points (pagePoints) within
    /// `radius` of the path are taken out, and every run of at least two
    /// points left becomes a stroke of its own — a new id, the same ink,
    /// width, opacity, blend, glow and group — laid along them as a stroke
    /// is drawn. Strokes in drawing order, locked and hidden ones never;
    /// one that loses no point is not cut.
    static func erasedPartially(_ elements: [Element], path: [CGPoint], radius: Double) -> [Cut] {
        guard !path.isEmpty else { return [] }
        let sweep: [CGPoint] = path.count == 1 ? [path[0], path[0]] : path
        var cuts: [Cut] = []
        for el in elements where isStroke(el) && !el.locked && !el.isHidden {
            let points = pagePoints(el)
            let gone = points.map { p in
                (0..<(sweep.count - 1)).contains { distance(p, sweep[$0], sweep[$0 + 1]) <= radius }
            }
            guard gone.contains(true) else { continue }
            var runs: [[CGPoint]] = [[]]
            for (p, out) in zip(points, gone) {
                if out {
                    if !(runs.last?.isEmpty ?? true) { runs.append([]) }
                } else {
                    runs[runs.count - 1].append(p)
                }
            }
            let pieces: [Element] = runs.filter { $0.count >= 2 }.compactMap { run in
                var base = el
                base.id = UID.make()
                return laid(base, along: run)
            }
            cuts.append(Cut(id: el.id, pieces: pieces))
        }
        return cuts
    }

    /// The drawn strokes an eraser dragged along `path` (page units) touches:
    /// any stroke whose line comes within `radius` of it, its own half-width
    /// added. Only strokes, and none that is locked or hidden — the eraser
    /// never takes what cannot be seen.
    static func erased(_ elements: [Element], path: [CGPoint], radius: Double) -> Set<String> {
        guard !path.isEmpty else { return [] }
        let sweep: [CGPoint] = path.count == 1 ? [path[0], path[0]] : path
        var out = Set<String>()
        for el in elements where isStroke(el) && !el.locked && !el.isHidden {
            let points = pagePoints(el)
            guard !points.isEmpty else { continue }
            let line: [CGPoint] = points.count == 1 ? [points[0], points[0]] : points
            let reach: Double = radius + (el.strokeWidth ?? 0) / 2
            var hit = false
            outer: for i in 0..<(sweep.count - 1) {
                for j in 0..<(line.count - 1) where segmentDistance(sweep[i], sweep[i + 1], line[j], line[j + 1]) <= reach {
                    hit = true
                    break outer
                }
            }
            if hit { out.insert(el.id) }
        }
        return out
    }

    /// A stroke's points — every coordinate pair of its path — on the page:
    /// out of the element's 0…100 box, flipped and turned as it is drawn.
    static func pagePoints(_ el: Element) -> [CGPoint] {
        guard let data = el.pathData else { return [] }
        var numbers: [Double] = []
        var current = ""
        for ch in data {
            if ch.isNumber || ch == "." || (ch == "-" && current.isEmpty) {
                current.append(ch)
            } else {
                if let v = Double(current) { numbers.append(v) }
                current = ch == "-" ? "-" : ""
            }
        }
        if let v = Double(current) { numbers.append(v) }
        let cx: Double = el.x + el.w / 2, cy: Double = el.y + el.h / 2
        let turn: Double = el.rotation * .pi / 180
        let c: Double = cos(turn), s: Double = sin(turn)
        var out: [CGPoint] = []
        var i = 0
        while i + 1 < numbers.count {
            var x: Double = el.x + numbers[i] / 100 * el.w
            var y: Double = el.y + numbers[i + 1] / 100 * el.h
            if el.flipH { x = 2 * cx - x }
            if el.flipV { y = 2 * cy - y }
            let dx: Double = x - cx, dy: Double = y - cy
            out.append(CGPoint(x: cx + dx * c - dy * s, y: cy + dx * s + dy * c))
            i += 2
        }
        return out
    }

    /// The least distance between two segments: none where they cross.
    private static func segmentDistance(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Double {
        func cross(_ o: CGPoint, _ p: CGPoint, _ q: CGPoint) -> Double {
            let first: Double = Double(p.x - o.x) * Double(q.y - o.y)
            let second: Double = Double(p.y - o.y) * Double(q.x - o.x)
            return first - second
        }
        let d1 = cross(c, d, a), d2 = cross(c, d, b), d3 = cross(a, b, c), d4 = cross(a, b, d)
        let straddlesCD: Bool = (d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)
        let straddlesAB: Bool = (d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)
        if straddlesCD && straddlesAB { return 0 }
        let first: Double = min(distance(a, c, d), distance(b, c, d))
        let second: Double = min(distance(c, a, b), distance(d, a, b))
        return min(first, second)
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx: Double = Double(b.x - a.x), dy: Double = Double(b.y - a.y)
        let length: Double = dx * dx + dy * dy
        var t: Double = 0
        if length > 0 { t = min(max((Double(p.x - a.x) * dx + Double(p.y - a.y) * dy) / length, 0), 1) }
        let x: Double = Double(a.x) + t * dx, y: Double = Double(a.y) + t * dy
        return hypot(Double(p.x) - x, Double(p.y) - y)
    }

    /// Whether an element is a drawn stroke: a path shape with no fill.
    static func isStroke(_ el: Element) -> Bool {
        el.type == .shape && el.pathData?.isEmpty == false && el.fill?.kind == "none"
    }

    /// The strokes drawn black on white at `scale` pixels per page unit,
    /// padded, with the page rect the bitmap covers — what handwriting
    /// recognition reads.
    static func bitmap(of strokes: [Element], scale: Double = 2) -> (image: UIImage, frame: CGRect)? {
        let members = strokes.filter(isStroke)
        guard let first = members.first else { return nil }
        var union = first.frame
        for s in members.dropFirst() { union = union.union(s.frame) }
        let pad = max(12, union.height * 0.15)
        let frame = union.insetBy(dx: -pad, dy: -pad)
        let w = Int((frame.width * scale).rounded()), h = Int((frame.height * scale).rounded())
        guard w > 0, h > 0, w * h < 30_000_000 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(gray: 1, alpha: 1)
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: -frame.minX, y: -frame.minY)
            cg.setStrokeColor(gray: 0, alpha: 1)
            cg.setLineCap(.round); cg.setLineJoin(.round)
            for s in members {
                guard let data = s.pathData else { continue }
                var into = CGAffineTransform(translationX: s.x, y: s.y)
                let path = SVGPath.scaledPath(data, to: CGSize(width: s.w, height: s.h)).copy(using: &into)
                cg.setLineWidth(max(2, s.strokeWidth ?? 4))
                if let path { cg.addPath(path); cg.strokePath() }
            }
        }
        return (image, frame)
    }

    private static func num(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }
}
