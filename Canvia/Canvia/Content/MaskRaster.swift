// Parts of a photo made clear, or blurred or blocked out, with a brush —
// and never by changing its picture. The strokes are kept on the element:
// its `mask` ({strokes: [{mode, w, soft, pts}], base}) makes what they
// cover clear (Erase) or puts it back (Restore), and each of its `retouch`
// layers ({kind, amount, strokes: [{w, pts}]}) blurs or pixelates what its
// strokes cover. A stroke's points are shares of the picture across and
// down, 0…1, and its width a share of the picture's shorter side, so the
// strokes keep their place whatever size the picture is drawn at, on
// either phone.
//
// MaskRaster turns strokes into a grid of coverage — pure, by rules written
// for both phones alike, row for row in the tests. The drawing is
// the filter engine's (ImageMasking): the retouch after the filter and the
// dials, before the vignette and the duotone; the mask after all of them,
// before the edge and the shadow, so an outline follows the new edge.

import CoreGraphics
import Foundation

/// One stroke of a photo's mask: Erase makes what it covers clear, Restore
/// brings it back. `w` is the brush's width as a share of the picture's
/// shorter side (read within 0.005…0.2), `soft` how much of its width is
/// feathered (0…1), and `pts` its points as shares of the picture across and
/// down. Every field is written; a stroke of another mode, or with no point
/// that reads, is left out when read.
struct MaskStroke: Codable, Equatable, Hashable {
    var mode: String = MaskStroke.erase
    var w: Double = 0.05
    var soft: Double = 0
    /// [x, y] each, as written.
    var pts: [[Double]] = []

    static let erase = "erase"
    static let restore = "restore"

    /// What the brush's width is read within.
    static let widthRange = 0.005...0.2

    var restores: Bool { mode == Self.restore }

    /// Its points.
    var points: [CGPoint] { MaskStroke.points(pts) }

    private enum CodingKeys: String, CodingKey { case mode, w, soft, pts }

    init(mode: String = MaskStroke.erase, w: Double = 0.05, soft: Double = 0, points: [CGPoint] = []) {
        self.mode = mode
        self.w = w
        self.soft = soft
        self.pts = MaskStroke.pairs(points)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mode = (try? c.decode(String.self, forKey: .mode)) ?? Self.erase
        guard mode == Self.erase || mode == Self.restore else {
            throw DecodingError.dataCorruptedError(forKey: .mode, in: c, debugDescription: "Not a mask stroke")
        }
        self.mode = mode
        w = (try? c.decode(Double.self, forKey: .w)).flatMap { $0.isFinite ? $0 : nil } ?? 0.05
        soft = (try? c.decode(Double.self, forKey: .soft)).flatMap { $0.isFinite ? $0 : nil } ?? 0
        pts = MaskStroke.read(c, .pts)
        guard !pts.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .pts, in: c, debugDescription: "No points")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(w, forKey: .w)
        try c.encode(soft, forKey: .soft)
        try c.encode(pts, forKey: .pts)
    }

    /// The pairs of numbers at `key`, [[x, y], …], each a point; a pair that
    /// is short or not numbers is left out, and a third number dropped.
    static func read<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, _ key: Key) -> [[Double]] {
        guard let pairs = try? c.decode([[Double?]].self, forKey: key) else { return [] }
        return pairs.compactMap { pair in
            guard pair.count >= 2, let x = pair[0], let y = pair[1], x.isFinite, y.isFinite else { return nil }
            return [x, y]
        }
    }

    /// Points as pairs, [x, y] each.
    static func pairs(_ points: [CGPoint]) -> [[Double]] {
        points.map { [Double($0.x), Double($0.y)] }
    }

    /// Pairs as points; one short of two numbers is left out.
    static func points(_ pairs: [[Double]]) -> [CGPoint] {
        pairs.compactMap { $0.count >= 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }
}

/// A photo's mask: its strokes, in the order they were painted, and — once
/// Cut out has made its picture — `base`, the picture before the cut, which
/// Restore paints back. Written only while it has a stroke or a base, so a
/// photo nobody brushed has no key.
struct ImageMask: Codable, Equatable, Hashable {
    var strokes: [MaskStroke] = []
    var base: String?

    private enum CodingKeys: String, CodingKey { case strokes, base }

    init(strokes: [MaskStroke] = [], base: String? = nil) {
        self.strokes = strokes
        self.base = base
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strokes = (try? c.decode([Lossy<MaskStroke>].self, forKey: .strokes))?.compactMap(\.value) ?? []
        base = (try? c.decode(String.self, forKey: .base)).flatMap { $0.isEmpty ? nil : $0 }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(strokes, forKey: .strokes)
        try c.encodeIfPresent(base, forKey: .base)
    }

    /// Whether there is nothing to write.
    var isEmpty: Bool { strokes.isEmpty && base == nil }

    /// `mask` as it is kept on an element: nil when empty.
    static func kept(_ mask: ImageMask?) -> ImageMask? {
        mask.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// One stroke of a retouch layer: `w` and `pts` as a mask stroke's. A stroke
/// of Erase from effect takes the effect back off where it goes, and is
/// written with "mode": "erase"; a painting stroke has no mode.
struct RetouchStroke: Codable, Equatable, Hashable {
    var w: Double = 0.05
    /// [x, y] each, as written.
    var pts: [[Double]] = []
    var erases = false

    private enum CodingKeys: String, CodingKey { case w, pts, mode }

    init(w: Double = 0.05, points: [CGPoint] = [], erases: Bool = false) {
        self.w = w
        self.pts = MaskStroke.pairs(points)
        self.erases = erases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        w = (try? c.decode(Double.self, forKey: .w)).flatMap { $0.isFinite ? $0 : nil } ?? 0.05
        pts = MaskStroke.read(c, .pts)
        erases = (try? c.decode(String.self, forKey: .mode)) == MaskStroke.erase
        guard !pts.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .pts, in: c, debugDescription: "No points")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(w, forKey: .w)
        try c.encode(pts, forKey: .pts)
        if erases { try c.encode(MaskStroke.erase, forKey: .mode) }
    }

    /// The stroke as MaskRaster paints it into a layer's coverage, which
    /// starts at none: painting raises it (a mask's Restore), Erase from
    /// effect lowers it, feathered by a quarter of the width.
    var asMaskStroke: MaskStroke {
        var stroke = MaskStroke(mode: erases ? MaskStroke.erase : MaskStroke.restore, w: w, soft: MaskRaster.retouchSoftness)
        stroke.pts = pts
        return stroke
    }
}

/// A blur or a pixelate brushed onto part of a photo: `kind` "blur" or
/// "pixelate", `amount` 0…1 (read within it), and the strokes it covers.
/// The element's `retouch` is a list of them, drawn in order, and written
/// only when it has one; a layer of a kind this build does not know, or
/// with no stroke, is left out when read.
struct RetouchLayer: Codable, Equatable, Hashable {
    var kind: String
    var amount: Double = 0.5
    var strokes: [RetouchStroke] = []

    static let blur = "blur"
    static let pixelate = "pixelate"
    static let kinds = [blur, pixelate]

    private enum CodingKeys: String, CodingKey { case kind, amount, strokes }

    init(kind: String, amount: Double = 0.5, strokes: [RetouchStroke] = []) {
        self.kind = kind
        self.amount = amount
        self.strokes = strokes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        guard Self.kinds.contains(kind) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Not a retouch")
        }
        self.kind = kind
        amount = (try? c.decode(Double.self, forKey: .amount)).flatMap { $0.isFinite ? $0 : nil } ?? 0.5
        strokes = (try? c.decode([Lossy<RetouchStroke>].self, forKey: .strokes))?.compactMap(\.value) ?? []
        guard !strokes.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .strokes, in: c, debugDescription: "No strokes")
        }
    }

    /// Its amount within 0…1.
    var share: Double { min(max(amount, 0), 1) }

    /// The layers as they are kept on an element: those with a stroke, and
    /// nil when none has.
    static func kept(_ layers: [RetouchLayer]?) -> [RetouchLayer]? {
        let painted = (layers ?? []).filter { !$0.strokes.isEmpty }
        return painted.isEmpty ? nil : painted
    }
}

/// A value read on its own from a list, so one that cannot be read is left
/// out rather than losing the rest.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

enum MaskRaster {

    /// The longest side of the grid strokes are painted into.
    static let maxSide = 1024
    /// A retouch stroke's feather: a quarter of its width.
    static let retouchSoftness = 0.25

    /// The grid for a picture `width` × `height` (any unit): the picture
    /// itself up to `maxSide` on its longer side, scaled down to it beyond,
    /// each side rounded and at least 1.
    static func gridSize(width: Double, height: Double) -> (width: Int, height: Int) {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return (1, 1) }
        let scale = min(1, Double(maxSide) / max(width, height))
        return (max(1, Int((width * scale).rounded())), max(1, Int((height * scale).rounded())))
    }

    /// How much of a pixel `distance` from a stroke's line it covers, 0…1:
    /// all of it within the brush's `radius` less the feather, none beyond
    /// the radius, and a straight ramp between. The feather is `soft` times
    /// the brush's width (twice the radius), up to the radius itself; with
    /// none the edge is hard, a pixel exactly on it covered.
    static func coverage(distance: Double, radius: Double, soft: Double) -> Double {
        let feather = min(max(soft, 0), 1) * 2 * radius
        guard feather > 0 else { return distance <= radius ? 1 : 0 }
        return min(max((radius - distance) / min(feather, radius), 0), 1)
    }

    /// `strokes` painted in order into a grid `width` × `height`, row by row
    /// from the top, each cell starting at `start` (or `initial` when
    /// given, one value a cell): an Erase stroke takes each cell down by
    /// what it covers of it (a × (1 − c)), a Restore stroke brings it up as
    /// far (a + (1 − a) × c). A cell is measured from its centre, (x + 0.5,
    /// y + 0.5); a stroke's points are at x × width, y × height, its radius
    /// half its `w` — held within MaskStroke.widthRange — times the grid's
    /// shorter side; a stroke of one point is a dot.
    static func raster(_ strokes: [MaskStroke], width: Int, height: Int, start: Float = 1,
                       initial: [Float]? = nil) -> [Float] {
        let w = max(1, width), h = max(1, height)
        var grid = initial.flatMap { $0.count == w * h ? $0 : nil } ?? [Float](repeating: start, count: w * h)
        let short = Double(min(w, h))
        for stroke in strokes {
            let share = min(max(stroke.w, MaskStroke.widthRange.lowerBound), MaskStroke.widthRange.upperBound)
            let radius = share * short / 2
            let points = stroke.points.map { CGPoint(x: Double($0.x) * Double(w), y: Double($0.y) * Double(h)) }
            guard let first = points.first, radius > 0 else { continue }
            let line = points.count == 1 ? [first, first] : points
            // The stroke's coverage, cell by cell over its bounds, the most
            // any of its segments gives a cell.
            let minX = max(0, cell((line.map { Double($0.x) }.min() ?? 0) - radius - 1, w))
            let maxX = min(w - 1, cell((line.map { Double($0.x) }.max() ?? 0) + radius + 1, w))
            let minY = max(0, cell((line.map { Double($0.y) }.min() ?? 0) - radius - 1, h))
            let maxY = min(h - 1, cell((line.map { Double($0.y) }.max() ?? 0) + radius + 1, h))
            guard minX <= maxX, minY <= maxY else { continue }
            let across = maxX - minX + 1
            var covered = [Float](repeating: 0, count: across * (maxY - minY + 1))
            for i in 0..<(line.count - 1) {
                let a = line[i], b = line[i + 1]
                let x0 = max(minX, cell(Double(min(a.x, b.x)) - radius - 1, w))
                let x1 = min(maxX, cell(Double(max(a.x, b.x)) + radius + 1, w))
                let y0 = max(minY, cell(Double(min(a.y, b.y)) - radius - 1, h))
                let y1 = min(maxY, cell(Double(max(a.y, b.y)) + radius + 1, h))
                guard x0 <= x1, y0 <= y1 else { continue }
                for y in y0...y1 {
                    for x in x0...x1 {
                        let centre = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                        let c = Float(coverage(distance: distance(centre, a, b), radius: radius, soft: stroke.soft))
                        let k = (y - minY) * across + (x - minX)
                        if c > covered[k] { covered[k] = c }
                    }
                }
            }
            for y in minY...maxY {
                for x in minX...maxX {
                    let c = covered[(y - minY) * across + (x - minX)]
                    guard c > 0 else { continue }
                    let k = y * w + x
                    grid[k] = stroke.restores ? grid[k] + (1 - grid[k]) * c : grid[k] * (1 - c)
                }
            }
        }
        return grid
    }

    /// The cell `v` falls in along a side `limit` cells long, held just
    /// beyond it, so a point far off the picture never overflows.
    private static func cell(_ v: Double, _ limit: Int) -> Int {
        Int(min(max(v, -1), Double(limit)))
    }

    /// The cell of a `width` × `height` grid at (`x`, `y`), shares of the
    /// picture across and down: the one that point falls in, the last
    /// column or row for 1.
    static func sample(_ grid: [Float], width: Int, height: Int, x: Double, y: Double) -> Float {
        guard width > 0, height > 0, grid.count == width * height else { return 1 }
        let col = min(max(cell(x * Double(width), width), 0), width - 1)
        let row = min(max(cell(y * Double(height), height), 0), height - 1)
        return grid[row * width + col]
    }

    /// The distance from `p` to the segment from `a` to `b`.
    static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let length = dx * dx + dy * dy
        var t = 0.0
        if length > 0 { t = min(max((Double(p.x - a.x) * dx + Double(p.y - a.y) * dy) / length, 0), 1) }
        return hypot(Double(p.x) - (Double(a.x) + t * dx), Double(p.y) - (Double(a.y) + t * dy))
    }

    // MARK: retouch

    /// A blur layer's Gaussian radius, in pixels of a picture whose shorter
    /// side is `shortSide`: its amount times 4% of that side.
    static func blurRadius(amount: Double, shortSide: Double) -> Double {
        min(max(amount, 0), 1) * 0.04 * max(shortSide, 0)
    }

    /// A layer's coverage in a `width` × `height` grid: its strokes painted
    /// from none (RetouchStroke.asMaskStroke).
    static func coverage(of layer: RetouchLayer, width: Int, height: Int) -> [Float] {
        raster(layer.strokes.map(\.asMaskStroke), width: width, height: height, start: 0, initial: nil)
    }
}
