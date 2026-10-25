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

// MARK: bent words a glyph at a time

/// Where each letter of words round a curve, along a path or down a column
/// stands (glyphPlacements), and the band behind a line of them (band): what
/// Highlight, a word's own marker, its link, Find and text moving a unit at
/// a time are drawn and found by when the words are not set in straight
/// lines. The outliner places the letters (TextOutliner.outline), so this
/// is the same layout the canvas draws. The rules both phones share
/// (Fixtures/bent-text.json):
///
///   • a glyph's quad runs `advance` along its tangent from its origin (its
///     baseline's start) and from `descent` below to `ascent` above it, up
///     being (sin θ, −cos θ) for a turn θ clockwise
///   • a curve's band is the annular sector from r − descent − pad to
///     r + ascent + pad (r signed: negative bends down) over the arc from
///     its first glyph's start to its last's end, pad more along the
///     baseline at each end; a path's the strip from descent + pad below the
///     baseline to ascent + pad above it, pad past either end; a column's
///     the rectangle of its letters' cells, pad round it — one closed path
///     a line (a curve or a path is one line, a column each column)
///   • ascent and descent are the box's own type's; pad is Highlight's
///     spread rule (0.18 em × spread / 50), and the corners are rounded by
///     roundness / 100 of half the band's thickness
extension TextPaths {

    /// One letter of bent words as it stands in the box: `index` its place
    /// in the words as they read (RichText.strip, UTF-16), `origin` where
    /// its baseline starts, turned `angle` degrees clockwise, `advance`
    /// along, its face's `ascent` above and `descent` below.
    struct GlyphPlacement: Equatable {
        var index: Int
        var origin: CGPoint
        var angle: Double
        var advance: Double
        var ascent: Double
        var descent: Double

        /// Its corners: top-left, top-right, bottom-right, bottom-left.
        var quad: [CGPoint] {
            TextPaths.quad(origin: origin, angle: angle, advance: advance, ascent: ascent, descent: descent)
        }

        /// The middle of its quad.
        var centre: CGPoint {
            let q = quad
            return CGPoint(x: (q[0].x + q[2].x) / 2, y: (q[0].y + q[2].y) / 2)
        }
    }

    /// A glyph's stretch along its line: angles in radians round a curve,
    /// distances along a path.
    struct Extent: Equatable {
        var index: Int
        var from: Double
        var to: Double
    }

    /// A letter's cell down a column.
    struct Cell: Equatable {
        var index: Int
        var column: Int
        var rect: CGRect
    }

    /// What bent words run along, as the outliner set them: round a circle
    /// about `centre` of signed `radius`, along a path, or down columns.
    enum Spine {
        case arc(centre: CGPoint, radius: Double, glyphs: [Extent])
        case path(PathWalker, glyphs: [Extent])
        case columns([Cell])

        /// The same, moved by `dx`, `dy`.
        func moved(_ dx: Double, _ dy: Double) -> Spine {
            switch self {
            case .arc(let centre, let radius, let glyphs):
                return .arc(centre: CGPoint(x: centre.x + dx, y: centre.y + dy), radius: radius, glyphs: glyphs)
            case .path, .columns:
                return self
            }
        }
    }

    /// The corners of a glyph's quad (GlyphPlacement.quad).
    static func quad(origin: CGPoint, angle: Double, advance: Double, ascent: Double, descent: Double) -> [CGPoint] {
        let a = angle * .pi / 180
        let along = CGPoint(x: cos(a), y: sin(a)), up = CGPoint(x: sin(a), y: -cos(a))
        func at(_ s: Double, _ h: Double) -> CGPoint {
            CGPoint(x: origin.x + along.x * s + up.x * h, y: origin.y + along.y * s + up.y * h)
        }
        return [at(0, ascent), at(advance, ascent), at(advance, -descent), at(0, -descent)]
    }

    /// Each letter of `el`'s bent words where the canvas sets it, in
    /// reading order; none for straight or warped words, or a list's
    /// markers.
    static func glyphPlacements(_ el: Element) -> [GlyphPlacement] {
        guard let outline = TextOutliner.outline(of: el), !outline.placements.isEmpty else { return [] }
        let plain = plainIndices(el)
        return outline.placements.compactMap { glyph -> GlyphPlacement? in
            guard let index = plain[glyph.index] else { return nil }
            var out = glyph
            out.index = index
            return out
        }
    }

    /// Where each letter of the words as they read is in the words as drawn
    /// — past a list's markers (FontLibrary.displayRanges) — drawn index to
    /// read index.
    static func plainIndices(_ el: Element) -> [Int: Int] {
        let count = (RichText.strip(el.text ?? "") as NSString).length
        guard count > 0 else { return [:] }
        let shown = FontLibrary.displayRanges((0..<count).map { NSRange(location: $0, length: 1) }, for: el)
        var out: [Int: Int] = [:]
        for (plain, range) in shown.enumerated() { out[range.location] = plain }
        return out
    }

    /// The band behind each line of `el`'s bent words — of the letters in
    /// `range` of the words as they read, or all of them — for Highlight at
    /// `spread` and `roundness` (its settings).
    static func band(_ el: Element, spread: Double, roundness: Double, range: NSRange? = nil) -> [CGPath] {
        band(el, pad: highlightPad(fontSize: el.fontSize ?? 42, spread: spread), roundness: roundness / 100, range: range)
    }

    /// How far Highlight reaches past the letters at `spread`: 0.18 em at
    /// 50, as its straight bars do (TextEffect.resolve).
    static func highlightPad(fontSize: Double, spread: Double) -> Double {
        0.18 * fontSize * spread / 50
    }

    /// The same, `pad` round the letters, its corners `share` of half its
    /// thickness round.
    static func band(_ el: Element, pad: Double, roundness share: Double, range: NSRange? = nil) -> [CGPath] {
        bandPaths(el, pad: pad, range: range) { thickness in min(max(share, 0), 1) * thickness / 2 }
    }

    /// The same, its corners `corner` round (at most half its thickness):
    /// a word's own marker (Spans.highlightRadiusEm).
    static func band(_ el: Element, pad: Double, corner: Double, range: NSRange? = nil) -> [CGPath] {
        bandPaths(el, pad: pad, range: range) { thickness in min(max(corner, 0), thickness / 2) }
    }

    /// The bands, each corner `radius` round for a band so thick.
    private static func bandPaths(_ el: Element, pad: Double, range: NSRange?,
                                  radius rounding: (Double) -> Double) -> [CGPath] {
        guard let outline = TextOutliner.outline(of: el), !outline.spines.isEmpty else { return [] }
        var drawn: Set<Int>?
        if let range {
            let shown = FontLibrary.displayRanges([range], for: el)[0]
            drawn = Set(shown.location..<NSMaxRange(shown))
        }
        let radius = rounding(outline.ascent + outline.descent + 2 * pad)
        return outline.spines.flatMap { spine -> [CGPath] in
            spineBands(spine, only: drawn, ascent: outline.ascent, descent: outline.descent, pad: pad)
                .map { rounded($0.core(radius), radius: radius) }
        }
    }

    /// A band to be rounded: its outline with every side `pad − radius` past
    /// the letters, so rounding by `radius` reaches pad.
    struct BandCore {
        var core: (Double) -> CGPath
    }

    /// The bands along `spine` over its glyphs (those in `only`, by their
    /// index in the words as drawn), unrounded until asked.
    static func spineBands(_ spine: Spine, only: Set<Int>?, ascent: Double, descent: Double, pad: Double) -> [BandCore] {
        switch spine {
        case .arc(let centre, let radius, let glyphs):
            let kept = glyphs.filter { only?.contains($0.index) ?? true }
            let ends = kept.flatMap { [$0.from, $0.to] }
            guard let from = ends.min(), let to = ends.max() else { return [] }
            return [BandCore(core: { r in
                arcBand(centre: centre, radius: radius, from: from, to: to, ascent: ascent, descent: descent, pad: pad - r)
            })]
        case .path(let walker, let glyphs):
            let kept = glyphs.filter { only?.contains($0.index) ?? true }
            let ends = kept.flatMap { [$0.from, $0.to] }
            guard let from = ends.min(), let to = ends.max() else { return [] }
            return [BandCore(core: { r in
                stripBand(walker, from: from, to: to, ascent: ascent, descent: descent, pad: pad - r)
            })]
        case .columns(let cells):
            let kept = cells.filter { only?.contains($0.index) ?? true }
            let columns = Dictionary(grouping: kept, by: \.column).sorted { $0.key < $1.key }
            return columns.map { column -> BandCore in
                let cells = column.value
                let box = cells.dropFirst().reduce(cells[0].rect) { $0.union($1.rect) }
                return BandCore(core: { r in columnBand(box, pad: pad - r) })
            }
        }
    }

    /// The annular sector round `centre` from r − descent − pad to
    /// r + ascent + pad (`radius` r signed), over angles `from` to `to`
    /// (radians, clockwise from up, as a glyph is turned) and pad more along
    /// the baseline each way. A point at angle a and signed radius R is
    /// centre + R·(sin a, −cos a).
    static func arcBand(centre: CGPoint, radius r: Double, from: Double, to: Double, ascent: Double,
                        descent: Double, pad: Double) -> CGPath {
        let path = CGMutablePath()
        guard abs(r) > 0 else { return path }
        let reach = pad / abs(r)
        let a0 = min(from, to) - reach
        let a1 = max(max(from, to) + reach, a0)
        let above = r + ascent + pad, below = r - descent - pad
        func point(_ a: Double, _ radius: Double) -> CGPoint {
            CGPoint(x: centre.x + radius * sin(a), y: centre.y - radius * cos(a))
        }
        // From `start` to `end` at `radius`; a radius past the centre (of
        // the other sign to r) is the centre itself, the band a wedge.
        // CoreGraphics measures from +x: a at a positive radius is a − π/2,
        // at a negative one a + π/2 round |radius|.
        func arc(_ radius: Double, _ start: Double, _ end: Double, first: Bool) {
            guard radius * r > 0 else {
                if first { path.move(to: centre) } else { path.addLine(to: centre) }
                return
            }
            if first { path.move(to: point(start, radius)) } else { path.addLine(to: point(start, radius)) }
            let turn = radius > 0 ? -Double.pi / 2 : Double.pi / 2
            path.addArc(center: centre, radius: CGFloat(abs(radius)), startAngle: CGFloat(start + turn),
                        endAngle: CGFloat(end + turn), clockwise: end < start)
        }
        arc(above, a0, a1, first: true)
        arc(below, a1, a0, first: false)
        path.closeSubpath()
        return path
    }

    /// The strip along `walker` from `from` to `to` (distances along it),
    /// pad past either end, from descent + pad below its baseline to
    /// ascent + pad above: at each point of the path between, and the two
    /// ends, offset along its heading's up.
    static func stripBand(_ walker: PathWalker, from: Double, to: Double, ascent: Double, descent: Double,
                          pad: Double) -> CGPath {
        let path = CGMutablePath()
        let d0 = max(0, min(from, to) - pad), d1 = min(walker.length, max(from, to) + pad)
        guard d1 > d0 else { return path }
        var stops = [d0]
        stops += walker.cumulative.filter { $0 > d0 && $0 < d1 }
        stops.append(d1)
        let placed = stops.map { walker.locate($0) }
        func offset(_ spot: (point: CGPoint, angle: Double), _ h: Double) -> CGPoint {
            CGPoint(x: spot.point.x + sin(spot.angle) * h, y: spot.point.y - cos(spot.angle) * h)
        }
        let top = placed.map { offset($0, ascent + pad) }
        let foot = placed.reversed().map { offset($0, -(descent + pad)) }
        path.addLines(between: top + foot)
        path.closeSubpath()
        return path
    }

    /// A column's band: its letters' cells, pad round them.
    static func columnBand(_ box: CGRect, pad: Double) -> CGPath {
        CGPath(rect: box.insetBy(dx: CGFloat(-pad), dy: CGFloat(-pad)), transform: nil)
    }

    /// `core` grown by `radius` all round, its corners round: the band
    /// itself when radius is none.
    static func rounded(_ core: CGPath, radius: Double) -> CGPath {
        guard radius > 0.01, !core.isEmpty else { return core }
        let ring = core.copy(strokingWithWidth: CGFloat(2 * radius), lineCap: .round, lineJoin: .round, miterLimit: 1)
        return core.union(ring)
    }
}
