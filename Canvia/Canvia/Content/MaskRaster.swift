// Parts of a photo made clear, or blurred or blocked out, with a brush —
// and never by changing its picture. The strokes are kept on the element:
// its `mask` ({strokes: [{mode, w, soft, pts}], base}) makes what they
// cover clear (Erase) or puts it back (Restore), and each of its `retouch`
// layers ({kind, amount, strokes: [{w, pts}]}) blurs or pixelates what its
// strokes cover — or, of kind "adjust", lays dials of its own ({kind,
// adjust: {…}, strokes, area}) over the painted area, the subject or the
// background. A stroke's points are shares of the picture across and
// down, 0…1, and its width a share of the picture's shorter side, so the
// strokes keep their place whatever size the picture is drawn at, on
// either phone.
//
// A mask may also hold taps of Clear a colour, kept in order with the
// strokes: {"mode": "key", x, y, tol, all} clears what is within `tol` of
// the colour tapped at (x, y) — the patch round it, or with `all` that
// colour everywhere (keyCoverage). They read the picture's pixels where a
// stroke needs only its shape; an older build reads one as no stroke.
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
/// shorter side (read within 0.005…0.2), `soft` the share of its half-width
/// its edge fades over (0…1), and `pts` its points as shares of the picture
/// across and down. Every field is written, `soft` too when it is 0.
///
/// Read leniently, by the rule both phones share (the shared rows in
/// BrushesTests and the Android twin's MaskRasterTest): no `mode` erases;
/// a mode that is neither "erase" nor "restore", no `w` that is a number,
/// or no point that reads, and the stroke is left out; `w` is held to
/// widthRange and `soft` to 0…1, 0 when it is not a number; a pair that
/// is short or not numbers is left out, a third number dropped.
///
/// A tap of Clear a colour is an entry of mode "key" instead: the point
/// tapped, `x` and `y` in shares of the picture across and down (as a
/// stroke's points), `tol` the tolerance 0…1 and `all` whether the colour
/// goes everywhere or only where it joins the tap. It has no width,
/// softness or points; its x and y must be numbers (held to 0…1), a `tol`
/// that is not one is the default and an `all` that is not true or false
/// is false.
struct MaskStroke: Codable, Equatable, Hashable {
    var mode: String = MaskStroke.erase
    var w: Double = 0.05
    var soft: Double = 0
    /// [x, y] each, as written.
    var pts: [[Double]] = []
    /// A key's point, tolerance and reach.
    var x: Double = 0
    var y: Double = 0
    var tol: Double = MaskStroke.defaultTolerance
    var all: Bool = false

    static let erase = "erase"
    static let restore = "restore"
    static let key = "key"

    /// What the brush's width is read within.
    static let widthRange = 0.005...0.2
    /// A new Clear a colour's tolerance: 25 on the slider's 0…100.
    static let defaultTolerance = 0.25

    var restores: Bool { mode == Self.restore }

    /// Whether it is a tap of Clear a colour.
    var keys: Bool { mode == Self.key }

    /// Its points.
    var points: [CGPoint] { MaskStroke.points(pts) }

    private enum CodingKeys: String, CodingKey { case mode, w, soft, pts, x, y, tol, all }

    init(mode: String = MaskStroke.erase, w: Double = 0.05, soft: Double = 0, points: [CGPoint] = []) {
        self.mode = mode
        self.w = w
        self.soft = soft
        self.pts = MaskStroke.pairs(points)
    }

    /// A tap of Clear a colour at (`x`, `y`), held to the picture and to
    /// the ten-thousandth as a stroke's points are written, its tolerance
    /// to the hundredth.
    init(keyAt x: Double, _ y: Double, tol: Double = MaskStroke.defaultTolerance, all: Bool = false) {
        func fourth(_ v: Double) -> Double { (min(max(v.isFinite ? v : 0, 0), 1) * 10_000).rounded() / 10_000 }
        mode = Self.key
        self.x = fourth(x)
        self.y = fourth(y)
        self.tol = (min(max(tol.isFinite ? tol : 0, 0), 1) * 100).rounded() / 100
        self.all = all
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // No mode is Erase; one that is there but not text is no mode.
        let named: String? = c.contains(.mode) ? (try? c.decode(String.self, forKey: .mode)) : Self.erase
        if named == Self.key {
            guard let x = try? c.decode(Double.self, forKey: .x), let y = try? c.decode(Double.self, forKey: .y),
                  x.isFinite, y.isFinite else {
                throw DecodingError.dataCorruptedError(forKey: .x, in: c, debugDescription: "No point")
            }
            mode = Self.key
            self.x = min(max(x, 0), 1)
            self.y = min(max(y, 0), 1)
            let tol = (try? c.decode(Double.self, forKey: .tol)).flatMap { $0.isFinite ? $0 : nil }
            self.tol = min(max(tol ?? Self.defaultTolerance, 0), 1)
            all = (try? c.decode(Bool.self, forKey: .all)) ?? false
            return
        }
        guard let mode = named, mode == Self.erase || mode == Self.restore else {
            throw DecodingError.dataCorruptedError(forKey: .mode, in: c, debugDescription: "Not a mask stroke")
        }
        self.mode = mode
        w = try MaskStroke.width(c, .w)
        let soft = (try? c.decode(Double.self, forKey: .soft)).flatMap { $0.isFinite ? $0 : nil } ?? 0
        self.soft = min(max(soft, 0), 1)
        pts = MaskStroke.read(c, .pts)
        guard !pts.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .pts, in: c, debugDescription: "No points")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        if keys {
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
            try c.encode(tol, forKey: .tol)
            try c.encode(all, forKey: .all)
            return
        }
        try c.encode(w, forKey: .w)
        try c.encode(soft, forKey: .soft)
        try c.encode(pts, forKey: .pts)
    }

    /// The width at `key`, held to widthRange; a stroke with none that is
    /// a number is not read.
    static func width<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, _ key: Key) throws -> Double {
        guard let w = try? c.decode(Double.self, forKey: key), w.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "No width")
        }
        return min(max(w, widthRange.lowerBound), widthRange.upperBound)
    }

    /// The pairs of numbers at `key`, [[x, y], …], each a point; a pair that
    /// is short or not numbers is left out, and a third number dropped —
    /// each pair on its own, so one that does not read leaves the rest.
    static func read<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, _ key: Key) -> [[Double]] {
        guard let pairs = try? c.decode([Lossy<[Lossy<Double>]>].self, forKey: key) else { return [] }
        return pairs.compactMap { item in
            guard let pair = item.value, pair.count >= 2,
                  let x = pair[0].value, let y = pair[1].value, x.isFinite, y.isFinite else { return nil }
            return [x, y]
        }
    }

    /// Points as a stroke writes them, as the Android twin does: each held
    /// to the picture, 0…1, and to the ten-thousandth, so a design does not
    /// carry a finger's every digit.
    static func written(_ points: [CGPoint]) -> [CGPoint] {
        func fourth(_ v: CGFloat) -> Double { (min(max(Double(v), 0), 1) * 10_000).rounded() / 10_000 }
        return points.map { CGPoint(x: fourth($0.x), y: fourth($0.y)) }
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

    /// `mask` with its base forgotten, its strokes kept: for a picture that
    /// is no longer the Cut out the base was the original of — the object
    /// eraser's inpainted copy — so Restore paints the picture itself back
    /// and the original is no longer drawn in its place. nil once nothing
    /// is left. The Android twin's PhotoMask.withoutBase.
    static func withoutBase(_ mask: ImageMask?) -> ImageMask? {
        guard var out = mask else { return nil }
        out.base = nil
        return kept(out)
    }
}

/// One stroke of a retouch layer: `w` and `pts` as a mask stroke's, read
/// by the same rule. A stroke of Erase from effect takes the effect back
/// off where it goes, and is written with "mode": "erase"; a painting
/// stroke has no mode, and one of any other mode is left out when read. It
/// has no softness, read or written (its edge is retouchFeather of its
/// width).
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
        if c.contains(.mode) {
            guard (try? c.decode(String.self, forKey: .mode)) == MaskStroke.erase else {
                throw DecodingError.dataCorruptedError(forKey: .mode, in: c, debugDescription: "Not a retouch stroke")
            }
            erases = true
        }
        w = try MaskStroke.width(c, .w)
        pts = MaskStroke.read(c, .pts)
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
    /// effect lowers it, feathered by a quarter of the width — half of its
    /// half-width.
    var asMaskStroke: MaskStroke {
        let soft = 2 * MaskRaster.retouchFeather
        var stroke = MaskStroke(mode: erases ? MaskStroke.erase : MaskStroke.restore, w: w, soft: soft)
        stroke.pts = pts
        return stroke
    }
}

/// A blur or a pixelate brushed onto part of a photo: `kind` "blur" or
/// "pixelate", `amount` 0…1 (read within it), and the strokes it covers.
/// The element's `retouch` is a list of them, drawn in order, and written
/// only when it has one; a layer of a kind this build does not know, or
/// with no stroke, is left out when read.
///
/// Of kind "adjust", the layer is the photo's dials of its own — `adjust`,
/// the Adjustments fields less selective colour and the vignette, which it
/// never keeps (neither is drawn on part of a photo, on either phone) —
/// laid over `area`: "brush" what its strokes cover (written so; a layer
/// with none is left out), "subject" the photo's cut-out and "background"
/// all but it, which need no strokes. It has no amount. A missing or
/// unknown area is "brush"; missing dials are all at rest.
struct RetouchLayer: Codable, Equatable, Hashable {
    var kind: String
    var amount: Double = 0.5
    var strokes: [RetouchStroke] = []
    /// An adjust layer's dials; nil for the other kinds.
    var adjust: Adjustments?
    /// An adjust layer's area; nil for the other kinds.
    var area: String?

    static let blur = "blur"
    static let pixelate = "pixelate"
    static let adjusting = "adjust"
    static let kinds = [blur, pixelate, adjusting]

    /// Where an adjust layer's dials go.
    static let brushArea = "brush"
    static let subjectArea = "subject"
    static let backgroundArea = "background"
    static let areas = [brushArea, subjectArea, backgroundArea]
    /// The most adjust layers a photo takes.
    static let maxAdjust = 4

    private enum CodingKeys: String, CodingKey { case kind, amount, strokes, adjust, area }

    init(kind: String, amount: Double = 0.5, strokes: [RetouchStroke] = []) {
        self.kind = kind
        self.amount = amount
        self.strokes = strokes
    }

    /// An adjust layer over `area`, its dials at rest unless given.
    init(adjustOver area: String, strokes: [RetouchStroke] = [], adjust: Adjustments = .neutral) {
        kind = Self.adjusting
        self.strokes = strokes
        self.area = Self.areas.contains(area) ? area : Self.brushArea
        self.adjust = Self.areaDials(adjust)
    }

    /// `dials` as an area keeps them: no selective colour, no vignette.
    static func areaDials(_ dials: Adjustments) -> Adjustments {
        var kept = dials
        kept.hsl = [:]
        kept.vignette = 0
        return kept
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        guard Self.kinds.contains(kind) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Not a retouch")
        }
        self.kind = kind
        strokes = (try? c.decode([Lossy<RetouchStroke>].self, forKey: .strokes))?.compactMap(\.value) ?? []
        if kind == Self.adjusting {
            let named = try? c.decode(String.self, forKey: .area)
            area = named.flatMap { Self.areas.contains($0) ? $0 : nil } ?? Self.brushArea
            adjust = Self.areaDials((try? c.decode(Adjustments.self, forKey: .adjust)) ?? .neutral)
        } else {
            let amount = (try? c.decode(Double.self, forKey: .amount)).flatMap { $0.isFinite ? $0 : nil } ?? 0.5
            self.amount = min(max(amount, 0), 1)
        }
        guard !strokes.isEmpty || !paintsArea else {
            throw DecodingError.dataCorruptedError(forKey: .strokes, in: c, debugDescription: "No strokes")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        if adjusts {
            try Self.areaDials(adjust ?? .neutral).encodeDials(to: c.superEncoder(forKey: .adjust), keepsVignette: false)
            try c.encode(strokes, forKey: .strokes)
            try c.encode(area ?? Self.brushArea, forKey: .area)
        } else {
            try c.encode(amount, forKey: .amount)
            try c.encode(strokes, forKey: .strokes)
        }
    }

    /// Its amount within 0…1.
    var share: Double { min(max(amount, 0), 1) }

    /// Whether it is an adjust layer.
    var adjusts: Bool { kind == Self.adjusting }

    /// Whether what it covers is its strokes': every layer but an adjust
    /// layer over the subject or the background.
    var paintsArea: Bool { !adjusts || (area ?? Self.brushArea) == Self.brushArea }

    /// The layers as they are kept on an element: those with a stroke — or
    /// over the subject or background — and nil when none is left.
    static func kept(_ layers: [RetouchLayer]?) -> [RetouchLayer]? {
        let painted = (layers ?? []).filter { !$0.strokes.isEmpty || !$0.paintsArea }
        return painted.isEmpty ? nil : painted
    }

    /// How much an adjust layer over `area` shows at a pixel its strokes
    /// cover by `strokes` (0…1) and the photo's cut-out by `subject` (0…1):
    /// the strokes' cover for "brush", the subject's for "subject" and the
    /// rest for "background". The rule both phones mix by.
    static func cover(area: String?, strokes: Double, subject: Double) -> Double {
        switch area ?? brushArea {
        case subjectArea: return min(max(subject, 0), 1)
        case backgroundArea: return 1 - min(max(subject, 0), 1)
        default: return min(max(strokes, 0), 1)
        }
    }

    /// A channel of the adjusted copy, `adjusted`, mixed into the picture's,
    /// `base`, by `cover` 0…1: base + (adjusted − base) × cover, rounded
    /// half up — as the layer is laid over the picture, on both phones.
    static func mixed(_ base: UInt8, _ adjusted: UInt8, cover: Double) -> UInt8 {
        let c = min(max(cover, 0), 1)
        let v = Double(base) + (Double(adjusted) - Double(base)) * c
        return UInt8(min(max((v + 0.5).rounded(.down), 0), 255))
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
    static let retouchFeather = 0.25

    /// The grid for a picture `width` × `height` (any unit): the picture
    /// itself up to `maxSide` on its longer side, scaled down to it beyond,
    /// each side rounded and at least 1.
    static func gridSize(width: Double, height: Double) -> (width: Int, height: Int) {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return (1, 1) }
        let scale = min(1, Double(maxSide) / max(width, height))
        return (max(1, Int((width * scale).rounded())), max(1, Int((height * scale).rounded())))
    }

    /// How much of a point `distance` from a stroke's line it covers, 0…1,
    /// for a brush of `radius` whose edge fades over `feather` (held within
    /// the radius): none at the radius or beyond, all within radius less
    /// the feather, and a straight ramp between; with no feather, all of
    /// what lies inside the radius. The Android twin's rule, number for
    /// number.
    static func coverage(distance: Double, radius: Double, feather: Double) -> Double {
        guard distance < radius else { return 0 }
        let f = min(max(feather, 0), radius)
        guard f > 0, distance > radius - f else { return 1 }
        return (radius - distance) / f
    }

    /// A stroke's half-width and feather, as shares of the picture's
    /// shorter side: its `w` held within MaskStroke.widthRange, halved, and
    /// its `soft` (held to 0…1) of that half-width.
    static func reach(_ stroke: MaskStroke) -> (radius: Double, feather: Double) {
        let w = min(max(stroke.w, MaskStroke.widthRange.lowerBound), MaskStroke.widthRange.upperBound)
        return (w / 2, min(max(stroke.soft, 0), 1) * w / 2)
    }

    /// How a share across and down a picture of shape `aspect` (width over
    /// height) becomes a share of its shorter side, each way.
    static func scales(aspect: Double) -> (x: Double, y: Double) {
        let a = aspect.isFinite && aspect > 0 ? aspect : 1
        return a >= 1 ? (a, 1) : (1, 1 / a)
    }

    /// How much of the point (`x`, `y`) — shares of a picture of shape
    /// `aspect` across and down — `stroke` covers: measured in shares of
    /// the picture's shorter side, so only its shape matters, never its
    /// size; a stroke of one point is a dot.
    static func coverage(_ stroke: MaskStroke, aspect: Double, x: Double, y: Double) -> Double {
        let k = scales(aspect: aspect)
        let line = stroke.points.map { CGPoint(x: Double($0.x) * k.x, y: Double($0.y) * k.y) }
        guard let first = line.first else { return 0 }
        let p = CGPoint(x: x * k.x, y: y * k.y)
        var d = distance(p, first, first)
        for (a, b) in zip(line, line.dropFirst()) { d = min(d, distance(p, a, b)) }
        let (radius, feather) = reach(stroke)
        return coverage(distance: d, radius: radius, feather: feather)
    }

    /// The mask `strokes` make at a point (see coverage): it starts at 1,
    /// the whole picture, and the strokes are laid down in order — an Erase
    /// takes the cover away (a × (1 − c)), a Restore puts it back
    /// (a + (1 − a) × c) — so a hard Erase sets 0 and a hard Restore 1.
    static func alpha(_ strokes: [MaskStroke], aspect: Double, x: Double, y: Double) -> Double {
        var a = 1.0
        for stroke in strokes {
            let c = coverage(stroke, aspect: aspect, x: x, y: y)
            a = stroke.restores ? a + (1 - a) * c : a * (1 - c)
        }
        return a
    }

    /// How much of a retouch layer of `strokes` shows at a point: none to
    /// start with, each painting stroke laying it on (m + (1 − m) × c) and
    /// each Erase from effect taking it off (m × (1 − c)), feathered by a
    /// quarter of their width.
    static func effect(_ strokes: [RetouchStroke], aspect: Double, x: Double, y: Double) -> Double {
        var m = 0.0
        for stroke in strokes.map(\.asMaskStroke) {
            let c = coverage(stroke, aspect: aspect, x: x, y: y)
            m = stroke.restores ? m + (1 - m) * c : m * (1 - c)
        }
        return m
    }

    /// `strokes` painted in order into a grid `width` × `height`, row by row
    /// from the top, each cell starting at `start` (or `initial` when
    /// given, one value a cell) and taking the value at its centre, (x +
    /// 0.5, y + 0.5): as alpha lays them, an Erase stroke taking each cell
    /// down by what it covers of it, a Restore bringing it up as far. A
    /// stroke's points are at x × width, y × height and its reach (reach)
    /// in shares of the grid's shorter side.
    ///
    /// A tap of Clear a colour takes each cell down to the least of it and
    /// what `keyed` leaves of it — its keyCoverage over the grid's own
    /// pixels — so a colour tapped twice, or an edge two taps share, never
    /// goes further (the Android twin's rule); it is passed over when there
    /// is nothing to give.
    static func raster(_ strokes: [MaskStroke], width: Int, height: Int, start: Float = 1,
                       initial: [Float]? = nil, keyed: Keyed = { _ in nil }) -> [Float] {
        let w = max(1, width), h = max(1, height)
        var grid = initial.flatMap { $0.count == w * h ? $0 : nil } ?? [Float](repeating: start, count: w * h)
        let short = Double(min(w, h))
        for stroke in strokes {
            if stroke.keys {
                guard let left = keyed(stroke), left.count == w * h else { continue }
                for k in 0..<(w * h) where left[k] < grid[k] { grid[k] = left[k] }
                continue
            }
            let (share, fade) = reach(stroke)
            let radius = share * short, feather = fade * short
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
                        let c = Float(coverage(distance: distance(centre, a, b), radius: radius, feather: feather))
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

    // MARK: clear a colour

    /// What a tap of Clear a colour leaves of the grid, one value a cell;
    /// nil when there is no picture to read.
    typealias Keyed = (MaskStroke) -> [Float]?

    /// The squared Lab distance (CIE76 ΔE) within which a colour is the
    /// one tapped, for a tolerance `tol` 0…1: (100 × tol)².
    static func keyLimit(_ tol: Double) -> Double {
        let e = min(max(tol, 0), 1) * 100
        return e * e
    }

    /// sRGB channels 0…255 in CIE Lab (D65, white X 0.95047, Y 1, Z
    /// 1.08883): linear light, then XYZ by the 7-digit sRGB matrix, then
    /// L*, a* and b* with the CIE's exact 216/24389 and 24389/27 — the same
    /// numbers, written the same way, as the Android twin's lab.
    static func lab(_ red: Int, _ green: Int, _ blue: Int) -> (l: Double, a: Double, b: Double) {
        let r = linear[min(max(red, 0), 255)], g = linear[min(max(green, 0), 255)], b = linear[min(max(blue, 0), 255)]
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        let fx = labF(x), fy = labF(y), fz = labF(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    private static func labF(_ t: Double) -> Double {
        t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116
    }

    /// Each sRGB level 0…255 as linear light, 0…1.
    private static let linear: [Double] = (0...255).map { v in
        let c = Double(v) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// What a tap of Clear a colour leaves of a picture `width` × `height`
    /// — `pixels` RGBA, not premultiplied, top row first; the grid's own
    /// proxy of the picture, at most maxSide on its longer side, so the
    /// coverage is scaled up with the rest of the mask — one value a pixel,
    /// 0…1. The tapped pixel is the one (x, y) falls in (x × width and y ×
    /// height rounded down, held within the picture); a pixel is its
    /// colour when it is not clear and lies within keyLimit(tol) of it in
    /// Lab. Those joined to the tapped pixel through its four neighbours
    /// are cleared (0 left) — or with `all`, every such pixel — the rest
    /// kept (1), and a pixel not cleared with a cleared one among its four
    /// neighbours is half left (0.5): the one-pixel feathered edge. A clear
    /// tapped pixel clears nothing. The Android twin's rule, pixel for
    /// pixel, checked on both phones by Fixtures/colour-key.json.
    static func keyCoverage(_ pixels: [UInt8], width: Int, height: Int, entry: MaskStroke) -> [Float] {
        let w = max(0, width), h = max(0, height)
        var out = [Float](repeating: 1, count: w * h)
        guard w > 0, h > 0, pixels.count >= w * h * 4, entry.keys else { return out }
        let tx = min(max(Int((entry.x * Double(w)).rounded(.down)), 0), w - 1)
        let ty = min(max(Int((entry.y * Double(h)).rounded(.down)), 0), h - 1)
        let tapped = ty * w + tx
        guard pixels[tapped * 4 + 3] > 0 else { return out }
        let ref = lab(Int(pixels[tapped * 4]), Int(pixels[tapped * 4 + 1]), Int(pixels[tapped * 4 + 2]))
        let limit = keyLimit(entry.tol)
        func within(_ p: Int) -> Bool {
            let i = p * 4
            guard pixels[i + 3] > 0 else { return false }
            let c = lab(Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
            let dl = c.l - ref.l, da = c.a - ref.a, db = c.b - ref.b
            return dl * dl + da * da + db * db <= limit
        }
        var cleared = [Bool](repeating: false, count: w * h)
        if entry.all {
            for p in 0..<(w * h) where within(p) { cleared[p] = true }
        } else {
            cleared[tapped] = true
            var waiting = [tapped]
            while let p = waiting.popLast() {
                let x = p % w, y = p / w
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let n = ny * w + nx
                    guard !cleared[n], within(n) else { continue }
                    cleared[n] = true
                    waiting.append(n)
                }
            }
        }
        for p in 0..<(w * h) {
            if cleared[p] {
                out[p] = 0
                continue
            }
            let x = p % w, y = p / w
            let touches = (x > 0 && cleared[p - 1]) || (x + 1 < w && cleared[p + 1])
                || (y > 0 && cleared[p - w]) || (y + 1 < h && cleared[p + w])
            if touches { out[p] = 0.5 }
        }
        return out
    }

    /// Remove white background's taps: the four corners, at tolerance 0.12,
    /// each clearing the white joined to it.
    static let whiteBackgroundTolerance = 0.12
    static var whiteBackgroundTaps: [MaskStroke] {
        [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)].map {
            MaskStroke(keyAt: $0.0, $0.1, tol: whiteBackgroundTolerance)
        }
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
