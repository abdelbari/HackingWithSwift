// Drawing by hand: a finger (or a Pencil) stroke becomes a shape.
//
// The stroke is kept as path data in the element's own 0…100 box, drawn
// with a stroke and no fill, so it is an ordinary element afterwards —
// moved, rotated, recoloured, exported as a real path in the SVG — and a
// single undo step. Points are thinned and then smoothed with quadratic
// curves through the midpoints, which takes the sawtooth out of raw touch
// samples without pulling the line off the finger.
//
// With Pressure on for the pen, each sample also keeps how wide the line is
// there — 0.35 to 1 of the pen's width, from how hard a Pencil presses or,
// for a finger, how fast it moves — as the stroke's `widths`, one for each
// sample the curve passes. Such a stroke is drawn as a filled outline
// (outline) rather than a stroked line; a build without it draws the line
// at its one width from the same path data.

import CoreGraphics
import Foundation
import UIKit

enum Freehand {

    /// What the pen lays down: ink; a marker — the ink opaque, 1.6 times
    /// as wide, round at its ends and a little uneven along it; a
    /// highlighter — the ink see-through, three times as wide, multiplying
    /// with what is under it as a real one does; a glow — the ink with a
    /// halo of itself; and an eraser, which lays nothing down and takes away
    /// the strokes it passes over. The Android twin has the same pens, and
    /// makes the same strokes.
    enum Pen: String, CaseIterable, Identifiable {
        case pen, marker, highlighter, glow, eraser
        var id: String { rawValue }
        var label: String {
            switch self {
            case .pen: return tr("Pen")
            case .marker: return tr("Marker")
            case .highlighter: return tr("Highlighter")
            case .glow: return tr("Glow")
            case .eraser: return tr("Eraser")
            }
        }
        /// How the pen is used, in a line over the drawing bar — the
        /// Android twin's words.
        var hint: String {
            self == .eraser ? tr("Drag over strokes to take them away") : tr("One finger draws, two move the page")
        }
        /// Whether it lays down ink, and so has an ink to choose.
        var hasInk: Bool { self != .eraser }
        var symbol: String {
            switch self {
            case .pen: return "pencil.tip"
            case .marker: return "paintbrush.pointed"
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
        /// The pens whose strokes thin and thicken with pressure or speed.
        var pressurePens: Set<Pen> = []

        /// Whether this pen's strokes do.
        var pressure: Bool { pen.hasInk && pressurePens.contains(pen) }
    }

    // MARK: pressure

    /// The thinnest a pressure stroke gets, as a share of the pen's width.
    static let minWidthFactor = 0.35
    /// The speed, in page units a second, at which a finger's stroke is as
    /// thin as it gets.
    static let fastSpeed = 2000.0

    /// How wide the line is where a Pencil presses with `pressure`, 0…1 of
    /// its full force: 0.35 at none, the whole width at full, in a straight
    /// line between — to the hundredth, as both phones keep it.
    static func pressureFactor(_ pressure: Double) -> Double {
        let p = pressure.isFinite ? min(max(pressure, 0), 1) : 1
        return rounded(minWidthFactor + (1 - minWidthFactor) * p)
    }

    /// How wide the line is where a finger moves at `speed`, page units a
    /// second, with no pressure to read: the whole width standing still,
    /// thinning in a straight line to 0.35 at fastSpeed and beyond.
    static func speedFactor(_ speed: Double) -> Double {
        let v = speed.isFinite ? min(max(speed, 0), fastSpeed) : fastSpeed
        return rounded(1 - (1 - minWidthFactor) * v / fastSpeed)
    }

    private static func rounded(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// `points` thinned as `thinned` thins them, with the width factor of
    /// each kept beside it.
    static func thinned(_ points: [CGPoint], widths: [Double], minDistance: Double = 2) -> (points: [CGPoint], widths: [Double]) {
        var kept: [CGPoint] = []
        var factors: [Double] = []
        for (p, w) in zip(points, widths) {
            if let last = kept.last, hypot(p.x - last.x, p.y - last.y) < minDistance { continue }
            kept.append(p)
            factors.append(w)
        }
        return (kept, factors)
    }

    /// The samples a stroke's path data passes, in its 0…100 box: its start,
    /// each curve's control but the last, and the last curve's end — one
    /// for each of its `widths`.
    static func samples(_ pathData: String) -> [CGPoint] {
        let n = pathNumbers(pathData)
        guard n.count >= 2 else { return [] }
        var out = [CGPoint(x: n[0], y: n[1])]
        var i = 2
        while i + 3 < n.count {
            out.append(i + 7 < n.count ? CGPoint(x: n[i], y: n[i + 1]) : CGPoint(x: n[i + 2], y: n[i + 3]))
            i += 4
        }
        return out
    }

    /// A pressure stroke's outline in its own box, as path data at its
    /// size: nil for a stroke drawn at one width, or whose widths do not
    /// match its samples.
    static func outline(_ el: Element) -> String? {
        guard isStroke(el), let widths = el.widths, !widths.isEmpty, let data = el.pathData else { return nil }
        let points = samples(data).map { CGPoint(x: Double($0.x) / 100 * el.w, y: Double($0.y) / 100 * el.h) }
        guard points.count == widths.count || (widths.count == 1 && points.count == 2 && points[0] == points[1]) else {
            return nil
        }
        let width = el.strokeWidth ?? 4
        let radii = widths.map { max(0.25, width * min(max($0, minWidthFactor), 1) / 2) }
        return outlinePath(widths.count == 1 ? [points[0]] : points, radii: radii)
    }

    /// The outline of a line through `points`, `radii[i]` from it at each:
    /// the left edge (each point moved out along the normal to the line
    /// there, the left of its way on the page) smoothed as the line is
    /// (segments), a round cap at the end — a half circle round to the
    /// right edge — that edge back the same way, and a round cap at the
    /// start. One point is a circle. The rows are shared with the Android
    /// twin (stroke-outline.json).
    static func outlinePath(_ points: [CGPoint], radii: [Double]) -> String {
        let n = min(points.count, radii.count)
        guard n > 0 else { return "" }
        func pt(_ p: CGPoint) -> String { "\(num(Double(p.x))) \(num(Double(p.y)))" }
        if n == 1 {
            let c = points[0], r = radii[0]
            let a = CGPoint(x: Double(c.x) - r, y: Double(c.y)), b = CGPoint(x: Double(c.x) + r, y: Double(c.y))
            let arc = "A\(num(r)) \(num(r)) 0 1 1 "
            return "M\(pt(a))\(arc)\(pt(b))\(arc)\(pt(a))Z"
        }
        var left: [CGPoint] = [], right: [CGPoint] = []
        var normal = (x: 0.0, y: -1.0)
        for i in 0..<n {
            let a = points[max(i - 1, 0)], b = points[min(i + 1, n - 1)]
            let tx = Double(b.x - a.x), ty = Double(b.y - a.y)
            let length = hypot(tx, ty)
            if length > 0 { normal = (x: ty / length, y: -tx / length) }
            let p = points[i], r = radii[i]
            left.append(CGPoint(x: Double(p.x) + normal.x * r, y: Double(p.y) + normal.y * r))
            right.append(CGPoint(x: Double(p.x) - normal.x * r, y: Double(p.y) - normal.y * r))
        }
        /// The curves through `edge` after its first point, as segments
        /// lays them.
        func through(_ edge: [CGPoint]) -> String {
            var d = ""
            if edge.count > 2 {
                for i in 1..<(edge.count - 1) {
                    let mid = CGPoint(x: (edge[i].x + edge[i + 1].x) / 2, y: (edge[i].y + edge[i + 1].y) / 2)
                    d += "Q\(pt(edge[i])) \(pt(mid))"
                }
            }
            return d + "Q\(pt(edge[edge.count - 1])) \(pt(edge[edge.count - 1]))"
        }
        let back = Array(right.reversed())
        let end = radii[n - 1], start = radii[0]
        return "M\(pt(left[0]))" + through(left)
            + "A\(num(end)) \(num(end)) 0 0 1 \(pt(right[n - 1]))" + through(back)
            + "A\(num(start)) \(num(start)) 0 0 1 \(pt(left[0]))Z"
    }


    /// How see-through a highlighter's ink is, as the two hex digits added
    /// to it.
    static let highlighterAlpha = "73"

    /// The width a stroke is drawn at: a highlighter's is three of the pen's,
    /// a marker's 1.6.
    static func drawnWidth(_ tool: Tool) -> Double {
        switch tool.pen {
        case .highlighter: return tool.width * 3
        case .marker: return tool.width * markerWidth
        default: return tool.width
        }
    }

    // MARK: the marker

    /// How much wider a marker draws than the pen's size.
    static let markerWidth = 1.6
    /// The most a marker's ink thins at a piece of its line.
    static let markerJitter = 0.15

    /// Whether `el` is a stroke laid down by the marker.
    static func isMarker(_ el: Element) -> Bool { isStroke(el) && el.pen == Pen.marker.rawValue }

    /// The seed a marker stroke's texture is drawn from: the sum of its
    /// path data's UTF-16 code units, as the Android twin seeds it, so the
    /// same stroke has the same edge every time it is drawn, on either
    /// phone.
    static func markerSeed(_ pathData: String) -> Int {
        pathData.utf16.reduce(0) { $0 + Int($1) }
    }

    /// How solid each of `count` pieces of a marker's line is, in order: 1
    /// less markerJitter times each draw from `seed` (SeededRandom, the
    /// Android twin's generator).
    static func markerAlphas(count: Int, seed: Int) -> [Double] {
        var random = SeededRandom(seed: Double(seed))
        return (0..<max(count, 0)).map { _ in 1 - markerJitter * random.next() }
    }

    /// How many pieces a marker's line `length` long and `width` wide is
    /// drawn in: one for each twice its width along it, 1 to 4000.
    static func markerPieceCount(length: Double, width: Double) -> Int {
        guard length > 0, length.isFinite else { return 1 }
        return min(max(Int((length / (max(width, 1) * 2)).rounded(.up)), 1), 4000)
    }

    /// The length of a stroke's curve drawn in a box `size` across: its
    /// path data (a start, then a control and an end for each piece) in the
    /// box's 0…100, each piece followed in 16 straight steps.
    static func markerLength(_ el: Element, size: CGSize) -> Double {
        let n = pathNumbers(el.pathData ?? "")
        guard n.count >= 2 else { return 0 }
        let sx = Double(size.width) / 100, sy = Double(size.height) / 100
        var x = n[0] * sx, y = n[1] * sy, total = 0.0
        var i = 2
        while i + 3 < n.count {
            let cx = n[i] * sx, cy = n[i + 1] * sy, ex = n[i + 2] * sx, ey = n[i + 3] * sy
            var px = x, py = y
            for step in 1...16 {
                let t = Double(step) / 16, u = 1 - t
                let qx = u * u * x + 2 * u * t * cx + t * t * ex
                let qy = u * u * y + 2 * u * t * cy + t * t * ey
                total += hypot(qx - px, qy - py)
                px = qx
                py = qy
            }
            x = ex
            y = ey
            i += 4
        }
        return total
    }

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

    /// The `opacity` `tool`'s strokes are written with: its transparency's,
    /// and a marker's always whole — it is opaque ink, as on the Android
    /// twin.
    static func strokeOpacity(_ tool: Tool) -> Double {
        tool.pen == .marker ? 1 : opacity(transparency: tool.transparency)
    }

    /// The name strokes drawn in one go are grouped under when the pen is
    /// put down.
    static let drawingName = tr("Drawing")
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
        let shown = strokeOpacity(tool)
        if shown < 1 { e.opacity = shown }
        if tool.pen == .highlighter { e.blendMode = "multiply" }
        if tool.pen == .glow { e.shadow = glow(of: tool) }
        if tool.pen == .marker { e.pen = Pen.marker.rawValue }
        return laid(e, along: raw)
    }

    /// The element for a stroke whose samples `raw` each have a width
    /// factor in `widths`: as `element`, and, with Pressure on for the pen,
    /// the factors of the samples kept as its `widths`.
    static func element(points raw: [CGPoint], widths: [Double], tool: Tool) -> Element? {
        guard tool.pressure, widths.count == raw.count, var e = element(points: raw, tool: tool) else {
            return element(points: raw, tool: tool)
        }
        let kept = thinned(raw, widths: widths)
        e.widths = kept.widths.isEmpty ? nil : kept.widths
        return e
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
        // Widths belong to the samples they were laid with: a piece laid
        // again — what an eraser leaves — is drawn at the pen's one width.
        e.widths = nil
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
        let numbers = pathNumbers(data)
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

    /// Every number in path data, in order.
    static func pathNumbers(_ data: String) -> [Double] {
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
        return numbers
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

    /// Whether an element is a drawn stroke: a "freehand" path shape with
    /// no fill. The shape id matters: an imported SVG's unfilled parts are
    /// path shapes with no fill too, but they are a graphic, not ink to
    /// erase.
    static func isStroke(_ el: Element) -> Bool {
        el.type == .shape && el.shapeId == "freehand" && el.pathData?.isEmpty == false && el.fill?.kind == "none"
    }

    /// Whether a colour picked for `el` is its ink: a drawn stroke, or a
    /// path shape with no fill and a stroke, as an imported SVG's line or
    /// outline part is. Filled, it would turn into a blob the shape of the
    /// line.
    static func inksOnly(_ el: Element) -> Bool {
        if isStroke(el) { return true }
        guard el.type == .shape, el.stroke != nil, el.fill?.kind == "none" else { return false }
        return el.pathData?.isEmpty == false
    }

    /// The colour Fill shows for shape `el`: its ink when it `inksOnly`,
    /// its fill's otherwise.
    static func fillColour(_ el: Element) -> String? {
        inksOnly(el) ? el.stroke : el.fill?.primaryColor
    }

    /// Shape `el` in colour `hex`, picked from the swatches: its ink when it
    /// `inksOnly`, a solid fill otherwise. The Android twin's `coloured`.
    static func coloured(_ el: Element, _ hex: String) -> Element {
        var e = el
        if inksOnly(el) { e.stroke = hex } else { e.fill = .solid(hex) }
        return e
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
