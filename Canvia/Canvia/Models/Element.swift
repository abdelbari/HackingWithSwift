// Element model: one struct for all five element kinds (shape, text, image,
// sticker, line) with optional per-kind fields — mirroring the web JSON so
// templates decode directly. Every field the decoder might miss gets a
// sensible default.

import Foundation
import CoreGraphics

enum ElementType: String, Codable {
    case shape, text, image, sticker, line
}

/// A text effect and its settings. Every setting is optional and absent
/// means the type's default (see TextEffect.defaultValue), so a design from
/// before the settings draws as it did; one at its default is never written.
/// Settings another type does not use are kept and ignored when drawing.
struct TextEffectSpec: Codable, Equatable, Hashable {
    var type: String = "none"     // none|shadow|lift|outline|outlined|splice|echo|extrude|neon|glitch|highlight
    var offset: Double?           // 0–100
    var direction: Double?        // degrees −180…180; 0 points right, 90 down
    var blur: Double?             // 0–100
    var transparency: Double?     // 0–100
    var intensity: Double?        // 0–100
    var thickness: Double?        // 0–100
    var roundness: Double?        // 0–100
    var spread: Double?           // 0–100
    var depth: Double?            // 0–100, 3D's
    var shading: Double?          // 0–100, 3D's
    var color: String?            // "#rrggbb"
    var color2: String?           // "#rrggbb", glitch's second copy
}

extension TextEffectSpec {
    private enum CodingKeys: String, CodingKey {
        case type, offset, direction, blur, transparency, intensity, thickness, roundness, spread, depth, shading
        case color, color2
    }

    // Each key on its own, so one bad value loses that setting, never the
    // effect or the design.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? "none"
        offset = try? c.decodeIfPresent(Double.self, forKey: .offset)
        direction = try? c.decodeIfPresent(Double.self, forKey: .direction)
        blur = try? c.decodeIfPresent(Double.self, forKey: .blur)
        transparency = try? c.decodeIfPresent(Double.self, forKey: .transparency)
        intensity = try? c.decodeIfPresent(Double.self, forKey: .intensity)
        thickness = try? c.decodeIfPresent(Double.self, forKey: .thickness)
        roundness = try? c.decodeIfPresent(Double.self, forKey: .roundness)
        spread = try? c.decodeIfPresent(Double.self, forKey: .spread)
        depth = try? c.decodeIfPresent(Double.self, forKey: .depth)
        shading = try? c.decodeIfPresent(Double.self, forKey: .shading)
        color = try? c.decodeIfPresent(String.self, forKey: .color)
        color2 = try? c.decodeIfPresent(String.self, forKey: .color2)
    }

    /// The type, then only the settings that differ from the type's default.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        let effect = TextEffect(rawValue: type)
        for param in TextEffectParam.allCases {
            guard let value = self[param], let key = CodingKeys(rawValue: param.rawValue) else { continue }
            if let effect, effect.defaultValue(param) == value { continue }
            try c.encode(value, forKey: key)
        }
        if let color, color.lowercased() != effect?.defaultColor?.lowercased() {
            try c.encode(color, forKey: .color)
        }
        if let color2, color2.lowercased() != effect?.defaultColor2?.lowercased() {
            try c.encode(color2, forKey: .color2)
        }
    }

    /// Every setting at its type's default: nothing but the type is held.
    var isAtDefaults: Bool { self == TextEffectSpec(type: type) }

    /// A setting moved in whole steps; at its type's default it is left out.
    mutating func adjust(_ param: TextEffectParam, to value: Double) {
        let whole = value.rounded()
        self[param] = whole == TextEffect(rawValue: type)?.defaultValue(param) ? nil : whole
    }

    /// The colour, or glitch's second, as hex; nil (or the type's own
    /// colour) leaves it out, which for splice, echo and highlight is Auto.
    mutating func setColor(_ hex: String?, second: Bool = false) {
        let effect = TextEffect(rawValue: type)
        let own = second ? effect?.defaultColor2 : effect?.defaultColor
        var kept = hex
        if let hex, hex.lowercased() == own?.lowercased() { kept = nil }
        if second { color2 = kept } else { color = kept }
    }

    /// One numeric setting, by name.
    subscript(param: TextEffectParam) -> Double? {
        get {
            switch param {
            case .offset: return offset
            case .direction: return direction
            case .blur: return blur
            case .transparency: return transparency
            case .intensity: return intensity
            case .thickness: return thickness
            case .roundness: return roundness
            case .spread: return spread
            case .depth: return depth
            case .shading: return shading
            }
        }
        set {
            switch param {
            case .offset: offset = newValue
            case .direction: direction = newValue
            case .blur: blur = newValue
            case .transparency: transparency = newValue
            case .intensity: intensity = newValue
            case .thickness: thickness = newValue
            case .roundness: roundness = newValue
            case .spread: spread = newValue
            case .depth: depth = newValue
            case .shading: shading = newValue
            }
        }
    }
}

/// A drop shadow or glow behind any element.
///
/// A glow is a shadow with no offset and a colour, so it is the same struct;
/// the presets are what tell them apart. Every value has a default so an
/// element that has a shadow at all gets a sensible one.
///
/// A shadow may have a `style` beyond the offset copy (ShadowShapes):
/// "curved", "pageLift", "angle" or "backdrop", with the settings the
/// style reads — `curve` 0…1, `angle` −60…60° and `distance` 0…100 — each
/// written only when it is set, as the Android twin writes them. No style,
/// or one this build does not know, is drawn as a drop shadow, and kept as
/// written.
struct Shadow: Codable, Equatable, Hashable {
    var color: String = "#000000"
    var opacity: Double = 0.35
    var blur: Double = 12
    var offsetX: Double = 0
    var offsetY: Double = 6
    var style: String?
    var curve: Double?
    var angle: Double?
    var distance: Double?

    static let presets: [(name: String, shadow: Shadow)] = [
        (tr("Soft"), Shadow(color: "#000000", opacity: 0.30, blur: 14, offsetX: 0, offsetY: 6)),
        (tr("Lift"), Shadow(color: "#000000", opacity: 0.22, blur: 28, offsetX: 0, offsetY: 14)),
        (tr("Hard"), Shadow(color: "#000000", opacity: 0.55, blur: 0, offsetX: 6, offsetY: 6)),
        (tr("Long"), Shadow(color: "#000000", opacity: 0.25, blur: 4, offsetX: 14, offsetY: 14)),
        (tr("Glow"), Shadow(color: "#ffffff", opacity: 0.9, blur: 20, offsetX: 0, offsetY: 0)),
        (tr("Neon"), Shadow(color: "#5a31f4", opacity: 0.9, blur: 24, offsetX: 0, offsetY: 0)),
        // The four shaped styles, each at its own settings.
        (tr("Curved"), Shadow(color: "#000000", opacity: 0.35, blur: 14, offsetX: 0, offsetY: 10,
                             style: "curved", curve: 0.5)),
        (tr("Page lift"), Shadow(color: "#000000", opacity: 0.3, blur: 16, offsetX: 0, offsetY: 4,
                                style: "pageLift", curve: 0.5)),
        (tr("Angle"), Shadow(color: "#000000", opacity: 0.3, blur: 10, offsetX: 0, offsetY: 0,
                            style: "angle", angle: 30, distance: 40)),
        (tr("Backdrop"), Shadow(color: "#5a31f4", opacity: 1, blur: 0, offsetX: 0, offsetY: 0,
                               style: "backdrop", distance: 16)),
    ]

    private enum CodingKeys: String, CodingKey { case color, opacity, blur, offsetX, offsetY, style, curve, angle, distance }

    init(color: String = "#000000", opacity: Double = 0.35, blur: Double = 12,
         offsetX: Double = 0, offsetY: Double = 6, style: String? = nil,
         curve: Double? = nil, angle: Double? = nil, distance: Double? = nil) {
        self.color = color
        self.opacity = opacity
        self.blur = blur
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.style = style
        self.curve = curve
        self.angle = angle
        self.distance = distance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = (try? c.decode(String.self, forKey: .color)) ?? "#000000"
        opacity = (try? c.decode(Double.self, forKey: .opacity)) ?? 0.35
        blur = (try? c.decode(Double.self, forKey: .blur)) ?? 12
        offsetX = (try? c.decode(Double.self, forKey: .offsetX)) ?? 0
        offsetY = (try? c.decode(Double.self, forKey: .offsetY)) ?? 6
        // Each setting on its own: a style that is no string, or a number
        // that is none, is no key — and "drop" is the key's absence.
        style = (try? c.decodeIfPresent(String.self, forKey: .style)).flatMap { $0 == "drop" ? nil : $0 }
        curve = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .curve))
        angle = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .angle))
        distance = Self.finite(try? c.decodeIfPresent(Double.self, forKey: .distance))
    }

    private static func finite(_ v: Double??) -> Double? {
        guard let v, let v, v.isFinite else { return nil }
        return v
    }

    /// The style's settings as dials, each at its default when the shadow
    /// does not hold it (ShadowShapes).
    var curveDial: Double {
        get { ShadowShapes.curve(self) }
        set { curve = newValue }
    }
    var angleDial: Double {
        get { ShadowShapes.angle(self) }
        set { angle = newValue }
    }
    var distanceDial: Double {
        get { ShadowShapes.distance(self) }
        set { distance = newValue }
    }
}

/// How a video clip plays: the part of the file it shows, how fast,
/// whether it goes round again, how loud and how its sound fades in and
/// out — trimmed and timed without touching the file. Written as the
/// element's `clip` object, each field only when it is not its default, and
/// the object only when one is not; a partial or odd object still reads,
/// every field it lacks or cannot give at its default.
struct ClipPlayback: Codable, Equatable, Hashable {
    /// Seconds into the file where the clip starts.
    var start: Double = 0
    /// Seconds into the file where it stops; nil is the file's own end.
    var end: Double?
    /// The rate, as written; playback reads it within `speedRange`.
    var speed: Double = 1
    /// Round again from the start at the end; off holds the last frame.
    var loop: Bool = true
    /// The clip's own sound, 0...1, as written; it is heard within that.
    var volume: Double = 1
    /// Silent wherever it plays, the video included.
    var muted: Bool = false
    /// Seconds its sound rises from nothing as it starts to be heard on its
    /// page, and falls to nothing as it stops, as written; heard within
    /// `fadeRange` (AudioMix.clipFades).
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    /// Its sound cleaned and levelled by Enhance voice (VoiceEnhance)
    /// wherever it is heard.
    var enhance: Bool = false

    /// What the Clip sheet offers, as the Android twin's panel does.
    static let speeds: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2]
    /// What the Clip sheet offers a fade, and what the mix plays one within:
    /// a track's.
    static let fadeRange = AudioTrack.fadeRange
    /// The shortest a trim leaves a clip, in seconds; a clip no longer than
    /// this cannot be trimmed.
    static let minLength = 0.1
    /// What a reader plays any speed at, however far out the file has it.
    static let speedRange = 0.25...4.0

    var isDefault: Bool { self == ClipPlayback() }

    /// The rate the clip plays at: `speed` kept within `speedRange`.
    var playbackSpeed: Double { min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound) }

    /// Whether the clip is heard as it plays: not muted and not silent, at
    /// any speed — its sound kept at its pitch as it is sped up or slowed.
    var sounds: Bool { !muted && volume > 0 }

    private enum CodingKeys: String, CodingKey { case start, end, speed, loop, volume, muted, fadeIn, fadeOut, enhance }

    init(start: Double = 0, end: Double? = nil, speed: Double = 1, loop: Bool = true,
         volume: Double = 1, muted: Bool = false, fadeIn: Double = 0, fadeOut: Double = 0,
         enhance: Bool = false) {
        self.start = start
        self.end = end
        self.speed = speed
        self.loop = loop
        self.volume = volume
        self.muted = muted
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.enhance = enhance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = (try? c.decodeIfPresent(Double.self, forKey: .start)) ?? 0
        end = try? c.decodeIfPresent(Double.self, forKey: .end)
        speed = (try? c.decodeIfPresent(Double.self, forKey: .speed)) ?? 1
        loop = (try? c.decodeIfPresent(Bool.self, forKey: .loop)) ?? true
        volume = (try? c.decodeIfPresent(Double.self, forKey: .volume)) ?? 1
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? false
        fadeIn = (try? c.decodeIfPresent(Double.self, forKey: .fadeIn)) ?? 0
        fadeOut = (try? c.decodeIfPresent(Double.self, forKey: .fadeOut)) ?? 0
        enhance = (try? c.decodeIfPresent(Bool.self, forKey: .enhance)) == true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if start != 0 { try c.encode(start, forKey: .start) }
        try c.encodeIfPresent(end, forKey: .end)
        if speed != 1 { try c.encode(speed, forKey: .speed) }
        if !loop { try c.encode(false, forKey: .loop) }
        if volume != 1 { try c.encode(volume, forKey: .volume) }
        if muted { try c.encode(true, forKey: .muted) }
        if fadeIn > 0 { try c.encode(fadeIn, forKey: .fadeIn) }
        if fadeOut > 0 { try c.encode(fadeOut, forKey: .fadeOut) }
        if enhance { try c.encode(true, forKey: .enhance) }
    }
}

/// The part of a graphic shown when it is cropped (GraphicClip): a box in
/// shares 0…1 of the element's own box — of its group's frame for a group's
/// member — written as the element's `clip` object {x, y, w, h}, every key.
/// The whole of it is no key at all. A build before this ignores it and
/// shows the whole graphic.
struct ClipBox: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    /// The least share of the box a crop keeps across or down: a
    /// twentieth, Android's Clips.MIN_FRACTION.
    static let minShare = 0.05

    static let whole = ClipBox(x: 0, y: 0, w: 1, h: 1)

    init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    private enum CodingKeys: String, CodingKey { case x, y, w, h }

    /// All four keys as numbers, or no crop at all (the whole graphic), as
    /// Android's Clips.of reads it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        w = try c.decode(Double.self, forKey: .w)
        h = try c.decode(Double.self, forKey: .h)
    }

    /// Whether it shows the whole box, within a millionth.
    var isWhole: Bool {
        x <= 1e-6 && y <= 1e-6 && x + w >= 1 - 1e-6 && y + h >= 1 - 1e-6
    }

    /// A crop as read or about to be kept: inside the box, at least
    /// minShare across and down; nil for the whole box, or for one with a
    /// part that is not a number.
    static func kept(_ box: ClipBox?) -> ClipBox? {
        guard let box, box.x.isFinite, box.y.isFinite, box.w.isFinite, box.h.isFinite else { return nil }
        let x = min(max(box.x, 0), 1 - minShare)
        let y = min(max(box.y, 0), 1 - minShare)
        let out = ClipBox(x: x, y: y, w: min(max(box.w, minShare), 1 - x), h: min(max(box.h, minShare), 1 - y))
        return out.isWhole ? nil : out
    }
}

/// The element's `clip` object: a photo's playback, or a graphic's crop.
enum ElementClip: Equatable {
    case playback(ClipPlayback)
    case box(ClipBox)
}

extension ElementClip: Codable {
    /// A crop when it has a place and size ({x, y, w, h}); a playback else.
    init(from decoder: Decoder) throws {
        if let box = try? ClipBox.Probe(from: decoder), box.complete {
            self = .box(try ClipBox(from: decoder))
        } else {
            self = .playback(try ClipPlayback(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .playback(let playback): try playback.encode(to: encoder)
        case .box(let box): try box.encode(to: encoder)
        }
    }
}

extension ClipBox {
    /// Whether an object carries all four of a crop's keys, as numbers.
    fileprivate struct Probe: Decodable {
        var complete: Bool

        private enum CodingKeys: String, CodingKey { case x, y, w, h }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            complete = [CodingKeys.x, .y, .w, .h].allSatisfy { (try? c.decode(Double.self, forKey: $0)) != nil }
        }
    }
}

/// Where a table's cell rectangle or its text sits in the table: the
/// table's id ("tbl_<uid>"), shared by every cell and text of one table, and
/// the row (0 is the header) and column. The texts are the table's content,
/// so nothing else is kept. Written as the element's `table` object; one
/// missing a part, or with a part that cannot be read, is no key at all,
/// and the element is a plain member of its group, as a table from before
/// tables could be edited is. A merged cell is the top-left one of the
/// cells merged, covering `rowSpan` rows down and `colSpan` columns across
/// from its own; each is written only when over 1, and one missing, or
/// not a whole number of at least 1, is 1, as the Android twin reads it —
/// and so is one past `maxSpan`, which no table made here reaches.
struct TableCell: Codable, Equatable, Hashable {
    var id: String
    var row: Int
    var col: Int
    var rowSpan = 1
    var colSpan = 1
    /// The table's cell spacing — each cell's words inset this far, in page
    /// units — on every cell of it alike; nil is the inset a table is made
    /// with (DataGraphics.tablePad times its type), and is not written.
    var pad: Double?
    /// The table's alternating rows' colour, "#rrggbb", on every cell of it
    /// alike; nil is no alternating rows kept (DataGraphics.withTableBands).
    var bands: String?
    /// The least height of the row this cell starts, in page units, when it
    /// was dragged taller than its words need (DataGraphics
    /// .withRowDragged): kept on the row's first cell, its rectangle and
    /// words, written "minH" only then; nil is as tall as the words.
    var minH: Double?
    /// Which of the table's lines show, on every cell of it alike: one of
    /// Tables.borderModes; nil is "all", and is not written. Each
    /// cell rectangle strokes the sides this leaves it (Element.sides).
    var borders: String?
    /// The table design it was last given (TableDesigns), on every cell of
    /// it alike, so a theme or a brand applied can give it again; nil is
    /// none.
    var design: String?

    private enum CodingKeys: String, CodingKey { case id, row, col, rowSpan, colSpan, pad, bands, minH, borders, design }

    /// `cell` with its spacing and its row's least height, in page units,
    /// times `scale` — as a table scaled with its page or its selection
    /// keeps its inset and its rows in proportion, so its next relayout
    /// holds them; as it is when it is no cell or keeps neither. The
    /// Android twin's Tables.scaledPad.
    static func scaledPad(_ cell: TableCell?, by scale: Double) -> TableCell? {
        guard var out = cell, out.pad != nil || out.minH != nil else { return cell }
        out.pad = out.pad.map { $0 * scale }
        out.minH = out.minH.map { $0 * scale }
        return out
    }

    init(id: String, row: Int, col: Int, rowSpan: Int = 1, colSpan: Int = 1, pad: Double? = nil, bands: String? = nil,
         minH: Double? = nil, borders: String? = nil, design: String? = nil) {
        self.id = id
        self.row = row
        self.col = col
        self.rowSpan = max(1, rowSpan)
        self.colSpan = max(1, colSpan)
        self.pad = pad
        self.bands = bands
        self.minH = minH
        self.borders = borders
        self.design = design
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        guard !id.isEmpty, let row = Self.index(c, .row), let col = Self.index(c, .col) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Not a table cell"))
        }
        self.id = id
        self.row = row
        self.col = col
        rowSpan = Self.span(c, .rowSpan)
        colSpan = Self.span(c, .colSpan)
        // Read tolerantly: a spacing that is no number or below none, or a
        // colour that is none, is no key.
        pad = (try? c.decode(Double.self, forKey: .pad)).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        bands = (try? c.decode(String.self, forKey: .bands)).flatMap { ColorTools.rgb255($0) != nil ? $0 : nil }
        minH = (try? c.decode(Double.self, forKey: .minH)).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        // A border mode this build does not know is every line, as on the
        // Android twin; a design is kept as read, a name it may not know.
        borders = (try? c.decode(String.self, forKey: .borders)).flatMap { Tables.borderModes.contains($0) ? $0 : nil }
        design = (try? c.decode(String.self, forKey: .design)).flatMap { $0.isEmpty ? nil : $0 }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(row, forKey: .row)
        try c.encode(col, forKey: .col)
        if rowSpan > 1 { try c.encode(rowSpan, forKey: .rowSpan) }
        if colSpan > 1 { try c.encode(colSpan, forKey: .colSpan) }
        try c.encodeIfPresent(pad, forKey: .pad)
        try c.encodeIfPresent(bands, forKey: .bands)
        try c.encodeIfPresent(minH, forKey: .minH)
        try c.encodeIfPresent(borders, forKey: .borders)
        try c.encodeIfPresent(design, forKey: .design)
    }

    /// The rows the cell covers: its own, and those merged into it below.
    var spannedRows: Range<Int> { row..<(row + max(1, rowSpan)) }
    /// The columns the cell covers: its own, and those merged into it on
    /// the right.
    var spannedCols: Range<Int> { col..<(col + max(1, colSpan)) }
    /// Whether the cell is several merged.
    var isMerged: Bool { rowSpan > 1 || colSpan > 1 }

    /// Whether the cell covers row `r`, column `c`.
    func covers(row r: Int, col c: Int) -> Bool {
        spannedRows.contains(r) && spannedCols.contains(c)
    }

    /// The most rows or columns one cell is read as covering, so a file
    /// with a span of millions does not make a table of millions of rows.
    static let maxSpan = 1000

    /// A span as written: a whole number from 1 to maxSpan, else 1.
    private static func span<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, _ key: Key) -> Int {
        guard let n = index(c, key), n >= 1, n <= maxSpan else { return 1 }
        return n
    }

    /// A row or column: a whole number from nought below 1,000,000, written
    /// either way, so a span added to it never overflows.
    private static func index<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, _ key: Key) -> Int? {
        if let n = try? c.decode(Int.self, forKey: key) { return n >= 0 && n < 1_000_000 ? n : nil }
        guard let d = try? c.decode(Double.self, forKey: key), d >= 0, d < 1_000_000, d == d.rounded() else { return nil }
        return Int(d)
    }
}

/// The photo grid an empty frame was laid out as a cell of: the grid's id
/// (its group's when it was made), the layout's id (PhotoGrids), the cell's
/// index in that layout, and the spacing (`gutter`) and margin it was laid
/// with — what lets Spacing and Corners lay the whole grid out again after
/// it is placed. Written as the element's `grid` object, every field always,
/// as the Android twin writes it; one without an id, a layout, a cell or a
/// gutter is no key at all, and a missing margin is nought. A grid made
/// before there was a `grid` key has none, and offers neither slider.
/// `splits` are the grid's custom lattice lines once a divider was dragged
/// (PhotoGrids.dragged), written only when they differ from the layout's
/// own; read only when they are sound for the layout (PhotoGrids.kept).
struct GridCell: Codable, Equatable, Hashable {
    var id: String
    var layout: String
    var cell: Int
    var gutter: Double
    var margin: Double
    var splits: GridSplits?

    private enum CodingKeys: String, CodingKey { case id, layout, cell, gutter, margin, splits }

    init(id: String, layout: String, cell: Int, gutter: Double, margin: Double, splits: GridSplits? = nil) {
        self.id = id
        self.layout = layout
        self.cell = cell
        self.gutter = gutter
        self.margin = margin
        self.splits = splits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        layout = try c.decode(String.self, forKey: .layout)
        // A whole number either way it is written, as the Android twin
        // reads it.
        if let n = try? c.decode(Int.self, forKey: .cell) {
            cell = n
        } else {
            let d = try c.decode(Double.self, forKey: .cell)
            guard d.isFinite, abs(d) < 1_000_000 else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Not a cell"))
            }
            cell = Int(d)
        }
        gutter = try c.decode(Double.self, forKey: .gutter)
        margin = (try? c.decodeIfPresent(Double.self, forKey: .margin)) ?? 0
        splits = PhotoGrids.kept(try? c.decodeIfPresent(GridSplits.self, forKey: .splits), for: PhotoGrids.layout(layout))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(layout, forKey: .layout)
        try c.encode(cell, forKey: .cell)
        try c.encode(gutter, forKey: .gutter)
        try c.encode(margin, forKey: .margin)
        try c.encodeIfPresent(splits, forKey: .splits)
    }
}

/// A QR code's form as kept: its type ("wifi", "contact"…) and what is
/// typed in each of its fields, by the fields' keys — the Android twin's
/// `qrForm` object, `{type, fields}`. Read tolerantly: a field that is no
/// words is left out; a type this build does not know is kept as it is and
/// opens no form (QRForms.form(of:)).
struct QRFormFields: Codable, Equatable {
    var type: String
    var fields: [String: String]

    private enum CodingKeys: String, CodingKey { case type, fields }

    init(type: String, fields: [String: String]) {
        self.type = type
        self.fields = fields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        let raw = (try? c.decodeIfPresent([String: Lossy<String>].self, forKey: .fields)) ?? nil
        fields = (raw ?? [:]).compactMapValues(\.value)
    }
}

/// The chart an element was drawn as part of: what Edit chart reopens. Every
/// element of one chart carries the same object — its id, its kind, the data
/// exactly as typed and its three switches — beside a `chartPart` of its
/// own. An object without an id, a kind or data is no chart, and its
/// elements are a plain group again; a kind this build does not know is kept
/// as written and offers no Edit chart. The switches are written only when on.
///
/// Its text's look, so Update keeps it: the `font` family of every label,
/// their `ink` (#rrggbb, the axis and legend's too) and `textScale`, 0.5 to
/// 2 times the size a chart's labels are; and for a kind with a scale,
/// `smooth` lines and areas and the scale's ends, `axisMin` and `axisMax`.
/// Each is written only when set: nil, false and a scale of 1 are not — as
/// the Android twin writes them.
///
/// Its format, each written only when it is not the default: a value's
/// `prefix` and `suffix` (4 characters at most, as a String counts them —
/// an emoji is one — and as the Android twin counts them), its `decimals`
/// (0 to 3, nil for as many as it needs) and whether it is `compact` (1.2k,
/// 3.4M) — see
/// DataGraphics.formatValue; the axes' titles, `xTitle` and `yTitle`; a
/// donut's or a progress ring's `hole` (0.3 to 0.85 of its radius); the
/// bars' `gap` (0 to 0.8 of each slot, the default not written) and
/// `roundBars`; a line's `lineWidth` (1 to 12, scaled by the frame) and its
/// `points`; and the `icon` a pictogram is drawn in, an Icons.json id,
/// "person" — not written — when it has none.
///
/// How a part-to-whole kind's values read, `labelAs`: "value", "percent" or
/// "both" (DataGraphics.labelAs), nil for its kind's own; and where the
/// legend sits, `legendAt`: "top" or "right", nil — never written — for
/// "bottom". A value this build does not know reads as none.
struct ChartSpec: Codable, Equatable, Hashable {
    /// "chart_<uid>", shared by every element of the chart.
    var id: String
    /// A DataGraphics.ChartKind raw value: "column", "stackedBar", "progressRing"…
    var kind: String
    var data: String
    var legend: Bool = false
    /// Each value written beside its column, bar, point or slice.
    var values: Bool = false
    var gridlines: Bool = false
    /// The labels' font family; nil is the default face, "sans".
    var font: String?
    /// The labels', axis's and legend's colour, "#rrggbb"; nil is ink that
    /// reads on the page.
    var ink: String?
    /// The labels' size as a share of their usual one, read within 0.5…2;
    /// nil is 1.
    var textScale: Double?
    /// Lines and areas drawn through their points on curves.
    var smooth: Bool = false
    /// The scale's ends; either nil is the data's own, and both are ignored
    /// when the low one is not below the high one.
    var axisMin: Double?
    var axisMax: Double?
    var prefix: String?
    var suffix: String?
    var decimals: Int?
    var compact: Bool = false
    var xTitle: String?
    var yTitle: String?
    var hole: Double?
    var gap: Double?
    var roundBars: Bool = false
    var lineWidth: Double?
    var points: Bool = false
    var icon: String?
    var labelAs: String?
    var legendAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, kind, data, legend, values, gridlines, font, ink, textScale, smooth, axisMin, axisMax
        case prefix, suffix, decimals, compact, xTitle, yTitle, hole, gap, roundBars, lineWidth, points, icon
        case labelAs, legendAt
    }

    init(id: String = UID.make("chart"), kind: String, data: String,
         legend: Bool = false, values: Bool = false, gridlines: Bool = false,
         font: String? = nil, ink: String? = nil, textScale: Double? = nil, smooth: Bool = false,
         axisMin: Double? = nil, axisMax: Double? = nil) {
        self.id = id
        self.kind = kind
        self.data = data
        self.legend = legend
        self.values = values
        self.gridlines = gridlines
        self.font = font
        self.ink = ink
        self.textScale = textScale
        self.smooth = smooth
        self.axisMin = axisMin
        self.axisMax = axisMax
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        data = try c.decode(String.self, forKey: .data)
        legend = (try? c.decodeIfPresent(Bool.self, forKey: .legend)) ?? false
        values = (try? c.decodeIfPresent(Bool.self, forKey: .values)) ?? false
        gridlines = (try? c.decodeIfPresent(Bool.self, forKey: .gridlines)) ?? false
        // Each read on its own, as the Android twin reads them: a font that
        // is blank, an ink that is no colour or a number that is none is
        // no key.
        font = (try? c.decodeIfPresent(String.self, forKey: .font)).flatMap { $0.isEmpty ? nil : $0 }
        ink = (try? c.decodeIfPresent(String.self, forKey: .ink)).flatMap { ColorTools.rgb255($0) != nil ? $0 : nil }
        textScale = Self.finiteNumber(c, .textScale)
        smooth = (try? c.decodeIfPresent(Bool.self, forKey: .smooth)) ?? false
        axisMin = Self.finiteNumber(c, .axisMin)
        axisMax = Self.finiteNumber(c, .axisMax)
        // The format, each held to its range as the Android twin reads it.
        prefix = Self.affix(try? c.decodeIfPresent(String.self, forKey: .prefix))
        suffix = Self.affix(try? c.decodeIfPresent(String.self, forKey: .suffix))
        decimals = Self.finiteNumber(c, .decimals).map { Int(min(max($0.rounded(.towardZero), 0), 3)) }
        compact = (try? c.decodeIfPresent(Bool.self, forKey: .compact)) ?? false
        xTitle = Self.title(try? c.decodeIfPresent(String.self, forKey: .xTitle))
        yTitle = Self.title(try? c.decodeIfPresent(String.self, forKey: .yTitle))
        hole = Self.finiteNumber(c, .hole).map { min(max($0, DataGraphics.minHole), DataGraphics.maxHole) }
        gap = Self.finiteNumber(c, .gap).map { min(max($0, 0), DataGraphics.maxGap) }
        roundBars = (try? c.decodeIfPresent(Bool.self, forKey: .roundBars)) ?? false
        lineWidth = Self.finiteNumber(c, .lineWidth).map { min(max($0, DataGraphics.minLineWidth), DataGraphics.maxLineWidth) }
        points = (try? c.decodeIfPresent(Bool.self, forKey: .points)) ?? false
        icon = (try? c.decodeIfPresent(String.self, forKey: .icon)).flatMap { $0.isEmpty ? nil : $0 }
        labelAs = (try? c.decodeIfPresent(String.self, forKey: .labelAs)).flatMap(DataGraphics.keptLabelAs)
        legendAt = (try? c.decodeIfPresent(String.self, forKey: .legendAt)).flatMap(DataGraphics.keptLegendAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(data, forKey: .data)
        if legend { try c.encode(true, forKey: .legend) }
        if values { try c.encode(true, forKey: .values) }
        if gridlines { try c.encode(true, forKey: .gridlines) }
        try c.encodeIfPresent(font, forKey: .font)
        try c.encodeIfPresent(ink, forKey: .ink)
        if let textScale, textScale != 1 { try c.encode(textScale, forKey: .textScale) }
        if smooth { try c.encode(true, forKey: .smooth) }
        try c.encodeIfPresent(axisMin, forKey: .axisMin)
        try c.encodeIfPresent(axisMax, forKey: .axisMax)
        try c.encodeIfPresent(Self.affix(prefix), forKey: .prefix)
        try c.encodeIfPresent(Self.affix(suffix), forKey: .suffix)
        try c.encodeIfPresent(decimals.map { min(max($0, 0), 3) }, forKey: .decimals)
        if compact { try c.encode(true, forKey: .compact) }
        try c.encodeIfPresent(Self.title(xTitle), forKey: .xTitle)
        try c.encodeIfPresent(Self.title(yTitle), forKey: .yTitle)
        try c.encodeIfPresent(hole, forKey: .hole)
        if let gap, gap != DataGraphics.defaultGap { try c.encode(gap, forKey: .gap) }
        if roundBars { try c.encode(true, forKey: .roundBars) }
        try c.encodeIfPresent(lineWidth, forKey: .lineWidth)
        if points { try c.encode(true, forKey: .points) }
        if let icon, !icon.isEmpty, icon != DataGraphics.defaultIcon { try c.encode(icon, forKey: .icon) }
        // Only when it is not its kind's own, as the Android twin writes it:
        // a pie's "percent" is not written, its "value" is.
        let ownLabels = DataGraphics.ownLabelAs(kind)
        try c.encodeIfPresent(labelAs.flatMap(DataGraphics.keptLabelAs).flatMap { $0 == ownLabels ? nil : $0 },
                              forKey: .labelAs)
        try c.encodeIfPresent(legendAt.flatMap(DataGraphics.keptLegendAt), forKey: .legendAt)
    }

    /// A prefix or suffix as kept: its first 4 characters, an emoji one, as
    /// the Android twin's DataGraphics.affix counts them; nil when empty.
    static func affix(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return String(text.prefix(DataGraphics.maxAffix))
    }

    /// An axis title as kept: nil when blank.
    private static func title(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// A finite number at `key`, or nil.
    private static func finiteNumber<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, _ key: Key) -> Double? {
        guard let value = try? c.decodeIfPresent(Double.self, forKey: key), value.isFinite else { return nil }
        return value
    }
}

struct Element: Codable, Equatable, Identifiable {
    var id: String = UID.make()
    var type: ElementType = .shape
    var x: Double = 0
    var y: Double = 0
    var w: Double = 100
    var h: Double = 100
    var rotation: Double = 0
    var opacity: Double = 1
    var locked: Bool = false
    /// Locked in place only: it cannot be moved, resized or turned, but its
    /// words, colours, crop and picture can still be changed (see
    /// ElementLock). Never false: the key is written only when true, as the
    /// Android twin writes it, and `locked` stays the whole lock beside it.
    var lockPosition: Bool?
    var flipH: Bool = false
    var flipV: Bool = false
    /// The outermost group the element belongs to, so a build that knows
    /// only one level still sees today's flat group.
    var group: String?
    /// The groups it belongs to below `group`, outer to inner (Groups):
    /// grouping a group keeps it, and Ungroup takes off one level at a
    /// time. Nil when there are none, and no key in the file, as on the
    /// Android twin.
    var subgroups: [String]?
    /// How far the group is turned as a whole, in degrees, written the same
    /// on every member of its outermost level (Geometry.groupFrame): its
    /// selection frame is turned with it. Nil at 0, and no key in the file.
    var groupTurn: Double?
    var shadow: Shadow?
    /// How the element composites over what is under it; nil is normal.
    /// See BlendModes for the names.
    var blendMode: String?
    /// What the element shows, for people who cannot see it: read by
    /// VoiceOver and written into the SVG. Photos mostly.
    var altText: String?
    /// The picture (its `src`) the alt text was drawn from — Suggest's
    /// draft, kept as it was — so replacing that picture takes the alt text
    /// with it (Crop.replaced); nil for alt text typed, and no key.
    var altTextSource: String?
    /// Only there to look at — a flourish, a background shape — so Check
    /// accessibility does not ask for its alt text. Never false: written
    /// only when true, as `hidden`.
    var decorative: Bool?
    /// A line that joins two elements holds their ids and is laid again
    /// whenever either moves (see Connectors).
    var connectFrom: String?
    var connectTo: String?
    /// A web address, mailto or tel link: clickable in the exported PDF and
    /// SVG, and opened by a tap in the presenter (see Links).
    var link: String?
    /// Left off the page: never drawn — on the canvas, in an export, a
    /// thumbnail, Present or a video — never hit or snapped to, and a clip
    /// that makes no sound; still listed in Layers, where it is shown again.
    /// Never false: shown is nil, so the key is written only when true, as
    /// the page's own `hidden`.
    var hidden: Bool?
    /// A name of the person's own, over the one ElementNames makes, wherever
    /// the element is named: Layers, VoiceOver, the snap guides. Kept trimmed
    /// and at most LayerNames.maxLength characters; nil is none.
    var layerName: String?
    /// A cell rectangle or text of a table that can be edited: which table,
    /// and which row and column (see DataGraphics.relayout).
    var table: TableCell?
    /// The sides a table cell's rectangle strokes, some of "tlbr" in that
    /// order, derived by every relayout from its table's borders
    /// (DataGraphics.withSides); nil strokes its whole outline, "" none.
    /// The Android twin's "sides" extra.
    var sides: String?
    /// The chart this element was drawn as part of, and which part of it it
    /// is: "series:<n>", "label", "value", "axis", "grid" or "legend". See
    /// DataGraphics.chart.
    var chart: ChartSpec?
    var chartPart: String?
    /// For an empty frame laid out by a photo grid: which grid, which of its
    /// cells, and the spacing it was laid with (see PhotoGrids).
    var grid: GridCell?
    /// A decorative frame's window (see DecorativeFrames): a frame for a
    /// photo however full it is, so one dropped on it goes in. Never false:
    /// written only when true, as `hidden`.
    var photoFrame: Bool?

    // shape
    var shapeId: String?
    /// Arbitrary vector geometry as SVG path data in a 0…100 box, for
    /// shapes the library does not have: chart slices, traced outlines,
    /// imported paths. When set it wins over shapeId.
    var pathData: String?
    /// The icon from the icon library this shape was put on as (see
    /// IconLibrary): what it is named by. The path draws it; an id this
    /// build does not know is just a custom shape.
    var iconId: String?
    /// The illustrated graphic (see GraphicsLibrary) this shape is a part
    /// of, each of its parts naming it: what More like this offers alike.
    /// A build without the pack draws the parts as any SVG graphic's.
    var graphicId: String?
    /// The Bulk create column whose cell this text's words or this photo's
    /// picture become on each page made (BulkCreate); nil, and not
    /// written, when it takes none.
    var bulkField: String?
    var fill: Paint?
    var stroke: String?
    var strokeWidth: Double?
    var radius: Double?
    /// Per-corner radii — top-left, top-right, bottom-right, bottom-left —
    /// for rect-like shapes; nil means `radius` on all four.
    var corners: [Double]?
    /// How a path that crosses or nests itself is filled: "evenodd", or nil
    /// for nonzero, which is never written. Kept as read otherwise, and any
    /// value but "evenodd" is drawn nonzero. Set by an imported SVG graphic.
    var fillRule: String?
    /// The pen a drawn stroke was laid down with, where its look is more
    /// than its ink, width and opacity say: "marker" (see Freehand.Pen);
    /// nil for every other. A build without the marker draws it as ink.
    var pen: String?
    /// A straight-edged library shape's own parameters (ShapeGeometry): a
    /// star's "points" and "inner", a polygon's "sides", an arrow's "head"
    /// and "shaft", a callout's "tailX" and "tailY", a chevron's, ribbon's
    /// or tag's "notch" — only those that differ from the shape's own, nil
    /// when none do. A build without them draws the stored shape.
    var shapeParams: [String: Double]?
    /// A pressure stroke's width at each sample its curve passes, as a
    /// share of its `strokeWidth`, 0.35…1 (Freehand.outline): drawn as a
    /// filled outline. nil for a stroke at one width; a build without it
    /// draws the line at that width.
    var widths: [Double]?

    // text
    var text: String?
    var fontFamily: String?
    var fontSize: Double?
    var fontWeight: Int?
    var italic: Bool?
    var underline: Bool?
    /// Every letter drawn and measured as a capital; the words are kept as
    /// typed, so turning it off gives them back. nil is as typed.
    var uppercase: Bool?
    var align: String?
    var lineHeight: Double?
    var letterSpacing: Double?
    var color: String?
    /// "none" | "bullet" | "number" | "letter"; nil is none.
    var listStyle: String?
    /// Indent level, 0…4. Each level is one and a half ems.
    var indent: Int?
    /// Each line's own list and indent level, one entry per line of the
    /// words, over `listStyle` and `indent` (see TextLists); nil when those
    /// two set every line.
    var paragraphs: [TextParagraph]?
    /// The words as they read when `paragraphs` were made: paragraphs made
    /// for other words are ignored, and not kept.
    var paragraphsText: String?
    /// Where the text sits in a box taller than it: "top" | "middle" |
    /// "bottom"; nil is top and the box hugs the text.
    var vAlign: String?
    /// Choose the type size so the text fills the box, rather than the box
    /// following the text.
    var fitText: Bool?
    /// Space after each paragraph, in ems.
    var paragraphSpacing: Double?
    /// The saved text style this element follows. Updating the style
    /// re-applies it to every element that carries the id.
    var textStyleId: String?
    /// The first letter set large, three lines deep, with the text wrapping
    /// around it.
    var dropCap: Bool?
    /// What the box is in the document's outline: "title", "h1", "h2",
    /// "h3", "body", "quote" or "caption" (TextRoles); nil is inferred by
    /// size. Kept as read, so a role this build does not know survives a
    /// save; the Android twin's extras key of the same name.
    var textRole: String?
    /// The Text panel's Read as: how a screen reader takes the box in an
    /// export — "h1", "h2", "h3", "p" or "artifact" (TextRoles); nil is as
    /// its role says. Kept as read, as `textRole` is.
    var a11yRole: String?
    /// How the element arrives on the page, in video and preview.
    var animation: ElementAnimation?
    /// How the element leaves as its page ends: the same three fields, the
    /// delay counted back from the page's end. nil is staying to the end.
    var exitAnimation: ElementAnimation?
    /// For photos: a slow drift of the crop over the page's hold.
    var kenBurns: KenBurns?
    /// When the element shows within its page, in seconds; nil is the
    /// whole page (see ElementTiming).
    var timing: ElementTiming?
    /// A gradient behind the letters, or a photo in them (Paint.photo: the
    /// shape fill's keys with a focus and a zoom, see PhotoFills). nil
    /// paints `color`; a solid Paint here is never stored, since `color`
    /// already is one.
    var textFill: Paint?
    var effect: TextEffectSpec?
    /// Degrees of arc for curved text. Positive bends the baseline into a
    /// rainbow, negative into a valley; nil or zero is a straight line.
    /// From -360 to 360 (TextPaths.maxCurve): past ±180 the words close
    /// towards a ring, a space apart at a full one.
    var curve: Double?
    /// How far a curve is turned, in degrees clockwise from its centre —
    /// the top for a positive curve, the bottom for a negative one: the
    /// Rotate slider, which turns a ring. nil is 0, and no key.
    var curveStart: Double?
    /// Path data in the element's 0…100 box that the text follows; the
    /// curve is ignored while this is set.
    var textPath: String?
    /// Characters stacked top to bottom in columns that run right to left,
    /// the way Japanese and Chinese are set on a poster.
    var vertical: Bool?
    /// The letters reshaped in their box by eight handles (TextWarp); a
    /// curve, a path or a column comes first where one is set too.
    var warp: TextWarpSpec?
    /// Captions on this box (see Captions): the words said in a clip or a
    /// voice-over, timed to the page, drawn one cue at a time as it plays;
    /// nil for an ordinary text box, and no key in the file.
    var captions: Captions?
    /// Colours and sizes on chosen words, in offsets into the words as they
    /// read (see Spans); nil when there are none.
    var spans: [TextSpan]?
    /// The words as they read when `spans` were made: spans made for other
    /// words are ignored, and not kept.
    var spansText: String?

    // image
    var src: String?
    var filter: String?
    /// A shape from the library to clip this image to. Unknown ids resolve to
    /// no frame rather than to a rectangle, so a document from a build with
    /// more shapes than this one does not silently crop someone's photo.
    var maskShapeId: String?
    var adjustments: Adjustments?
    var duotone: Duotone?
    var cropScale: Double?
    var cropX: Double?
    var cropY: Double?
    /// Degrees the picture is turned inside its frame, -45…45, to level a
    /// horizon. The frame does not turn; the picture is scaled up to keep
    /// covering it.
    var straighten: Double?
    /// Fit the whole picture inside the frame (letterboxed) instead of
    /// filling the frame and cropping. nil is fill.
    var cropFit: Bool?
    /// How much of the filter shows, 0…1, mixed with the picture without
    /// it; nil is all of it, and 1 is never written.
    var filterStrength: Double?
    /// 0…1: the picture in blocks 2 + 48 × this page units across; nil is
    /// none.
    var pixelate: Double?
    /// Sharp about a point (or round the subject), blurred beyond; nil is
    /// none.
    var focusBlur: FocusBlur?
    /// An outline or a glow round what the photo shows; nil is none.
    var edge: PhotoEdge?
    /// Glitch, slice, halftone or grain on the photo's pixels (PhotoFx); nil
    /// is none, and no key in the file.
    var fx: PhotoFx?
    /// Parts of the picture made clear, or brought back, with the Erase and
    /// Restore brushes, and the picture before a Cut out (see MaskRaster);
    /// nil is none, and no key in the file.
    var mask: ImageMask?
    /// Blur and pixelate brushed onto parts of the picture, in order (see
    /// MaskRaster); nil is none, and no key in the file.
    var retouch: [RetouchLayer]?
    /// What the file's `clip` key holds: on a photo or clip its playback
    /// (`clip`), on anything else the part of it shown (`clipBox`). Read
    /// and written through those two.
    var clipField: ElementClip?
    /// For a clip ("video:" source): its trim, speed, loop and sound. Never a
    /// clip at all its defaults — that is nil, and no key in the file.
    var clip: ClipPlayback? {
        get {
            if case .playback(let playback) = clipField { return playback }
            return nil
        }
        set {
            if let newValue {
                clipField = .playback(newValue)
            } else if case .playback = clipField {
                clipField = nil
            }
        }
    }
    /// A shape, sticker or group member cropped (GraphicClip): the part of
    /// it shown, as shares 0…1 of its own box — of its group's frame for a
    /// group's member, the same on each. Nil is the whole of it, and no key.
    var clipBox: ClipBox? {
        get {
            if case .box(let box) = clipField { return box }
            return nil
        }
        set {
            if let newValue {
                clipField = .box(newValue)
            } else if case .box = clipField {
                clipField = nil
            }
        }
    }
    /// Whether `clipBox` has been put into the member's own box for drawing
    /// (GraphicClip.shown), whatever group it is in. Never in the file, and
    /// never set on what the design holds.
    var clipIsOwn = false
    /// A copy that draws only its outline or glow, laid before its group's
    /// first element so a graphic's edge is round the whole of it
    /// (PhotoEffects.withGroupEdges). Never in the file, and never set on
    /// what the design holds.
    var edgeOnly = false
    /// A QR code's look (see CodeGenerator.Look): its modules' colour
    /// ("#rrggbb"), its background's ("#rrggbb", or "none" for clear) and
    /// the margin round it in whole modules, 0…3. Each nil at its default —
    /// black, white, four — so written only when not, as on the Android twin.
    var qrColor: String?
    var qrBackground: String?
    var qrMargin: Int?
    /// A QR code's dots' shape ("round", "rounded"), its finder eyes'
    /// ("rounded", "circle"), a logo in its middle (an image src) and its
    /// error correction level ("L", "Q", "H"): each nil at its default —
    /// square, square, none, M — and H whenever there is a logo; written
    /// only when not the default, as on the Android twin (CodeGenerator.Look).
    var qrDots: String?
    var qrEyes: String?
    var qrLogo: String?
    var qrEc: String?
    /// A barcode's words under its bars: never true — nil is shown — so
    /// written only when false (Barcodes).
    var barcodeText: Bool?
    /// The form a QR code was made from, kept beside its payload only so it
    /// opens again filled in (QRForms); nil for a code typed as it is.
    var qrForm: QRFormFields?

    // sticker
    var glyph: String?

    // line
    var thickness: Double?
    var dash: String?
    var startCap: String?
    var endCap: String?
    /// How big both ends' heads are against the line's weight (LineEnds),
    /// 0.5…3; nil is 1.
    var capScale: Double?
    /// How a line runs between its ends (see LineRoutes): "elbow" or
    /// "curve"; nil is straight. An elbowed or curved line keeps rotation 0
    /// and its ends as `ends`, [x1, y1, x2, y2], fractions of its box, with
    /// `bend`, -1…1, where its corner sits or how far it bows; nil is 0.
    /// Each written only when set, as on the Android twin.
    var lineType: String?
    var ends: [Double]?
    var bend: Double?

    // sticky note
    /// A whiteboard's sticky note (StickyNotes): a square shape whose words
    /// shrink to fit it rather than growing it. Written only when true, the
    /// key the Android twin keeps in the element's extras.
    var sticky: Bool?

    var frame: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    /// Whether the element is left off the page (see `hidden`).
    var isHidden: Bool { hidden == true }
    /// Whether the element keeps its place — locked whole, or its position
    /// only — so nothing moves, resizes, turns or removes it.
    var holdsPlace: Bool { locked || lockPosition == true }
    var center: CGPoint { CGPoint(x: x + w / 2, y: y + h / 2) }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UID.make()
        type = (try? c.decode(ElementType.self, forKey: .type)) ?? .shape
        x = (try? c.decode(Double.self, forKey: .x)) ?? 0
        y = (try? c.decode(Double.self, forKey: .y)) ?? 0
        w = (try? c.decode(Double.self, forKey: .w)) ?? 100
        h = (try? c.decode(Double.self, forKey: .h)) ?? Element.defaultHeight(for: type, decoded: c)
        rotation = (try? c.decode(Double.self, forKey: .rotation)) ?? 0
        opacity = (try? c.decode(Double.self, forKey: .opacity)) ?? 1
        locked = (try? c.decode(Bool.self, forKey: .locked)) ?? false
        lockPosition = (try? c.decode(Bool.self, forKey: .lockPosition)) == true ? true : nil
        flipH = (try? c.decode(Bool.self, forKey: .flipH)) ?? false
        flipV = (try? c.decode(Bool.self, forKey: .flipV)) ?? false
        group = try? c.decode(String.self, forKey: .group)
        // Levels below a group only, and never an empty list or a turn of 0.
        let levels = ((try? c.decode([String].self, forKey: .subgroups)) ?? []).filter { !$0.isEmpty }
        subgroups = group == nil || levels.isEmpty ? nil : levels
        groupTurn = group == nil ? nil : (try? c.decode(Double.self, forKey: .groupTurn)).flatMap(Groups.keptTurn)
        shadow = try? c.decode(Shadow.self, forKey: .shadow)
        blendMode = try? c.decode(String.self, forKey: .blendMode)
        altText = try? c.decode(String.self, forKey: .altText)
        altTextSource = (try? c.decode(String.self, forKey: .altTextSource)).flatMap { $0.isEmpty ? nil : $0 }
        decorative = (try? c.decode(Bool.self, forKey: .decorative)) == true ? true : nil
        connectFrom = try? c.decode(String.self, forKey: .connectFrom)
        connectTo = try? c.decode(String.self, forKey: .connectTo)
        link = try? c.decode(String.self, forKey: .link)
        hidden = (try? c.decode(Bool.self, forKey: .hidden)) == true ? true : nil
        layerName = (try? c.decode(String.self, forKey: .layerName)).flatMap(LayerNames.kept)
        table = try? c.decode(TableCell.self, forKey: .table)
        sides = (try? c.decode(String.self, forKey: .sides)).map { $0.filter { "tlbr".contains($0) } }
        chart = try? c.decode(ChartSpec.self, forKey: .chart)
        chartPart = try? c.decode(String.self, forKey: .chartPart)
        grid = try? c.decode(GridCell.self, forKey: .grid)
        photoFrame = (try? c.decode(Bool.self, forKey: .photoFrame)) == true ? true : nil
        shapeId = try? c.decode(String.self, forKey: .shapeId)
        pathData = try? c.decode(String.self, forKey: .pathData)
        iconId = try? c.decode(String.self, forKey: .iconId)
        graphicId = try? c.decode(String.self, forKey: .graphicId)
        bulkField = (try? c.decode(String.self, forKey: .bulkField)).flatMap { $0.isEmpty ? nil : $0 }
        fill = try? c.decode(Paint.self, forKey: .fill)
        stroke = try? c.decode(String.self, forKey: .stroke)
        strokeWidth = try? c.decode(Double.self, forKey: .strokeWidth)
        radius = try? c.decode(Double.self, forKey: .radius)
        corners = try? c.decode([Double].self, forKey: .corners)
        fillRule = (try? c.decode(String.self, forKey: .fillRule)).flatMap { $0 == "nonzero" ? nil : $0 }
        pen = try? c.decode(String.self, forKey: .pen)
        // Read leniently: a value that is no number is left out.
        let params = ((try? c.decode([String: Lossy<Double>].self, forKey: .shapeParams)) ?? [:])
            .compactMapValues(\.value).filter { $0.value.isFinite }
        shapeParams = params.isEmpty ? nil : params
        widths = (try? c.decode([Double].self, forKey: .widths)).flatMap { $0.isEmpty ? nil : $0 }
        text = try? c.decode(String.self, forKey: .text)
        fontFamily = try? c.decode(String.self, forKey: .fontFamily)
        fontSize = try? c.decode(Double.self, forKey: .fontSize)
        fontWeight = try? c.decode(Int.self, forKey: .fontWeight)
        italic = try? c.decode(Bool.self, forKey: .italic)
        underline = try? c.decode(Bool.self, forKey: .underline)
        uppercase = try? c.decode(Bool.self, forKey: .uppercase)
        align = try? c.decode(String.self, forKey: .align)
        lineHeight = try? c.decode(Double.self, forKey: .lineHeight)
        letterSpacing = try? c.decode(Double.self, forKey: .letterSpacing)
        color = try? c.decode(String.self, forKey: .color)
        listStyle = try? c.decode(String.self, forKey: .listStyle)
        indent = try? c.decode(Int.self, forKey: .indent)
        vAlign = try? c.decode(String.self, forKey: .vAlign)
        fitText = try? c.decode(Bool.self, forKey: .fitText)
        paragraphSpacing = try? c.decode(Double.self, forKey: .paragraphSpacing)
        textStyleId = try? c.decode(String.self, forKey: .textStyleId)
        dropCap = try? c.decode(Bool.self, forKey: .dropCap)
        textRole = try? c.decode(String.self, forKey: .textRole)
        a11yRole = try? c.decode(String.self, forKey: .a11yRole)
        animation = try? c.decode(ElementAnimation.self, forKey: .animation)
        exitAnimation = try? c.decode(ElementAnimation.self, forKey: .exitAnimation)
        kenBurns = try? c.decode(KenBurns.self, forKey: .kenBurns)
        timing = (try? c.decode(ElementTiming.self, forKey: .timing)).flatMap(ElementTiming.kept)
        textFill = try? c.decode(Paint.self, forKey: .textFill)
        effect = try? c.decode(TextEffectSpec.self, forKey: .effect)
        curve = (try? c.decode(Double.self, forKey: .curve)).flatMap { TextPaths.keptCurve($0) }
        curveStart = (try? c.decode(Double.self, forKey: .curveStart)).flatMap { $0.isFinite && $0 != 0 ? $0 : nil }
        textPath = try? c.decode(String.self, forKey: .textPath)
        vertical = try? c.decode(Bool.self, forKey: .vertical)
        warp = try? c.decode(TextWarpSpec.self, forKey: .warp)
        // Only a text box carries captions; read leniently (Captions).
        captions = type == .text ? try? c.decode(Captions.self, forKey: .captions) : nil
        // Spans made for other words than these — the words changed by a
        // build that does not carry them along — are left behind.
        let madeFor = try? c.decode(String.self, forKey: .spansText)
        let live = Spans.live(try? c.decode([TextSpan].self, forKey: .spans), madeFor: madeFor,
                              plain: RichText.strip(text ?? ""))
        spans = live.isEmpty ? nil : live
        spansText = live.isEmpty ? nil : madeFor
        // Paragraphs made for other words are left behind the same way, and
        // the box-wide list and indent set every line again.
        paragraphs = try? c.decode([TextParagraph].self, forKey: .paragraphs)
        paragraphsText = try? c.decode(String.self, forKey: .paragraphsText)
        if TextLists.paragraphsOf(self) == nil { dropParagraphs() }
        src = try? c.decode(String.self, forKey: .src)
        filter = try? c.decode(String.self, forKey: .filter)
        maskShapeId = try? c.decode(String.self, forKey: .maskShapeId)
        adjustments = try? c.decode(Adjustments.self, forKey: .adjustments)
        duotone = try? c.decode(Duotone.self, forKey: .duotone)
        cropScale = try? c.decode(Double.self, forKey: .cropScale)
        cropX = try? c.decode(Double.self, forKey: .cropX)
        cropY = try? c.decode(Double.self, forKey: .cropY)
        straighten = try? c.decode(Double.self, forKey: .straighten)
        cropFit = try? c.decode(Bool.self, forKey: .cropFit)
        // At their defaults these are no key at all, so a file that wrote
        // one there reads as one that did not.
        filterStrength = (try? c.decode(Double.self, forKey: .filterStrength))
            .flatMap { $0.isFinite && $0 < 1 ? max(0, $0) : nil }
        pixelate = (try? c.decode(Double.self, forKey: .pixelate))
            .flatMap { $0.isFinite && $0 > 0 ? min(1, $0) : nil }
        focusBlur = try? c.decode(FocusBlur.self, forKey: .focusBlur)
        edge = try? c.decode(PhotoEdge.self, forKey: .edge)
        fx = try? c.decode(PhotoFx.self, forKey: .fx)
        mask = ImageMask.kept(try? c.decode(ImageMask.self, forKey: .mask))
        retouch = RetouchLayer.kept((try? c.decode([Lossy<RetouchLayer>].self, forKey: .retouch))?.compactMap(\.value))
        // The `clip` key is a photo's playback, and anything else's crop.
        if type == .image {
            clip = (try? c.decode(ClipPlayback.self, forKey: .clipField)).flatMap { $0.isDefault ? nil : $0 }
        } else {
            clipBox = ClipBox.kept(try? c.decode(ClipBox.self, forKey: .clipField))
        }
        // Read tolerantly, as the Android twin reads them: a colour that is
        // none, or a margin out of 0…4, is the default — and a default is no
        // key at all.
        qrColor = (try? c.decode(String.self, forKey: .qrColor)).flatMap(CodeGenerator.keptColor)
        qrBackground = (try? c.decode(String.self, forKey: .qrBackground)).flatMap(CodeGenerator.keptBackground)
        qrMargin = (try? c.decode(Double.self, forKey: .qrMargin)).flatMap(CodeGenerator.keptMargin)
        qrDots = (try? c.decode(String.self, forKey: .qrDots)).flatMap { CodeGenerator.kept($0, among: CodeGenerator.dotShapes) }
        qrEyes = (try? c.decode(String.self, forKey: .qrEyes)).flatMap { CodeGenerator.kept($0, among: CodeGenerator.eyeShapes) }
        qrLogo = (try? c.decode(String.self, forKey: .qrLogo)).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        qrEc = (try? c.decode(String.self, forKey: .qrEc)).flatMap { $0 == CodeGenerator.defaultLevel || !CodeGenerator.levels.contains($0) ? nil : $0 }
        barcodeText = (try? c.decode(Bool.self, forKey: .barcodeText)) == false ? false : nil
        qrForm = try? c.decode(QRFormFields.self, forKey: .qrForm)
        glyph = try? c.decode(String.self, forKey: .glyph)
        thickness = try? c.decode(Double.self, forKey: .thickness)
        dash = try? c.decode(String.self, forKey: .dash)
        startCap = try? c.decode(String.self, forKey: .startCap)
        endCap = try? c.decode(String.self, forKey: .endCap)
        capScale = (try? c.decode(Double.self, forKey: .capScale)).flatMap(LineEnds.written)
        lineType = try? c.decode(String.self, forKey: .lineType)
        ends = try? c.decode([Double].self, forKey: .ends)
        bend = (try? c.decode(Double.self, forKey: .bend)).flatMap { $0.isFinite ? $0 : nil }
        sticky = (try? c.decode(Bool.self, forKey: .sticky)) == true ? true : nil
    }

    private static func defaultHeight(for type: ElementType, decoded c: KeyedDecodingContainer<CodingKeys>) -> Double {
        switch type {
        case .line:
            let t = (try? c.decode(Double.self, forKey: .thickness)) ?? 4
            return max(8, t)
        case .text:
            // Pre-layout estimate; the canvas measures and corrects it.
            let size = (try? c.decode(Double.self, forKey: .fontSize)) ?? 42
            let lh = (try? c.decode(Double.self, forKey: .lineHeight)) ?? 1.25
            let lines = ((try? c.decode(String.self, forKey: .text)) ?? "x")
                .components(separatedBy: "\n").count
            return (size * lh * Double(lines)).rounded(.up)
        default:
            return 100
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, x, y, w, h, rotation, opacity, locked, lockPosition, flipH, flipV, group, shadow, blendMode, altText
        case subgroups, groupTurn, altTextSource
        case decorative
        case connectFrom, connectTo, link, hidden, layerName, table, sides, chart, chartPart, grid, photoFrame
        case shapeId, pathData, iconId, graphicId, bulkField, fill, stroke, strokeWidth, radius, corners, fillRule, pen
        case shapeParams, widths
        case text, fontFamily, fontSize, fontWeight, italic, underline, uppercase, align
        case lineHeight, letterSpacing, color, listStyle, indent, textFill, effect, curve, curveStart, textPath, vertical, warp
        case spans, spansText, paragraphs, paragraphsText, captions
        case textRole, a11yRole
        case vAlign, fitText, paragraphSpacing, textStyleId, dropCap, animation, exitAnimation, kenBurns, timing
        case src, filter, maskShapeId, adjustments, duotone, cropScale, cropX, cropY, straighten, cropFit
        case clipField = "clip"
        case filterStrength, pixelate, focusBlur, edge, fx, mask, retouch
        case qrColor, qrBackground, qrMargin, qrDots, qrEyes, qrLogo, qrEc, barcodeText, qrForm
        case glyph
        case thickness, dash, startCap, endCap, capScale
        case lineType, ends, bend
        case sticky
    }

    // MARK: factories (defaults mirror the web factories)

    static func shape(_ shapeId: String, w: Double = 200, h: Double = 200) -> Element {
        var e = Element()
        e.type = .shape
        e.shapeId = shapeId
        e.w = w; e.h = h
        e.fill = .solid("#8b5cf6")
        e.radius = 0
        return e
    }

    static func text(_ string: String, fontSize: Double = 42, w: Double = 400) -> Element {
        var e = Element()
        e.type = .text
        e.text = string
        e.fontSize = fontSize
        e.fontFamily = "sans"
        e.fontWeight = 400
        e.align = "center"
        e.lineHeight = 1.25
        e.letterSpacing = 0
        e.color = "#1f2430"
        e.effect = TextEffectSpec(type: "none")
        e.w = w
        e.h = fontSize * 1.25
        return e
    }

    static func image(_ src: String, w: Double = 480, h: Double = 360) -> Element {
        var e = Element()
        e.type = .image
        e.src = src
        e.w = w; e.h = h
        e.filter = "none"
        e.cropScale = 1; e.cropX = 0.5; e.cropY = 0.5
        e.radius = 0
        return e
    }

    static func sticker(_ glyph: String, size: Double = 160) -> Element {
        var e = Element()
        e.type = .sticker
        e.glyph = glyph
        e.w = size; e.h = size
        return e
    }

    static func line(w: Double = 300) -> Element {
        var e = Element()
        e.type = .line
        e.w = w; e.h = 8
        e.color = "#1f2430"
        e.thickness = 4
        e.dash = "solid"
        e.startCap = "none"; e.endCap = "none"
        return e
    }

    /// Deep copy with a fresh id, offset for duplicate/paste.
    func duplicated(offset: Double = 24) -> Element {
        var copy = self
        copy.id = UID.make()
        copy.x += offset
        copy.y += offset
        return copy
    }

    /// Its sizes `scale` times as big, where it stays: its box, type size,
    /// letter spacing, corners and border, and a line's thickness never
    /// under 1. Effects, curves and the words' own sizes are shares of the
    /// type, and stay. As the Android twin's PageResize.scaledSizes.
    func scaledSizes(by scale: Double) -> Element {
        var e = self
        e.w = w * scale
        e.h = h * scale
        if let fontSize { e.fontSize = fontSize * scale }
        if let thickness { e.thickness = max(1, thickness * scale) }
        if let letterSpacing { e.letterSpacing = letterSpacing * scale }
        if let radius { e.radius = radius * scale }
        if let corners { e.corners = corners.map { $0 * scale } }
        if let strokeWidth { e.strokeWidth = strokeWidth * scale }
        e.table = TableCell.scaledPad(table, by: scale)
        return e
    }
}
