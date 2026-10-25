// Words on a line or a connector — "Yes" and "No" on a flowchart's arrows —
// as Canva puts them: typed on the line, sitting on its route at a share of
// its length, upright whichever way the line runs, and breaking the stroke
// behind them. The Android twin's LineLabels, rule for rule, over the same
// rows (Fixtures/line-labels.json).
//
// A line keeps its label in `label` (LineLabel): {"text" (RichText's markers
// allowed, as in a text box), "at" 0…1 along the route's length (0.5 unless
// written), "font", "size", "color" (the line's when none), "weight",
// "italic", "gap" (true: the stroke stops round the label's box, gapPad
// further)}. The rules where the format left a choice:
//
//   • the route is LineRoutes.polyline on the page (a curve its curveSteps
//     pieces), consecutive points that are the same taken once; a point
//     `at` of it is `at` × its length along it, held to its ends, on the
//     piece that ends there when it falls on a corner (pointAt), and its
//     tangent that piece's heading (tangentAt)
//   • the label's box is its words' size, centred on that point and never
//     turned with the line
//   • the stroke drawn is the route less what lies within the box grown by
//     gapPad (clipGap) — each piece cut where it enters and leaves it
//   • a label dragged slides `at` to the route's nearest point, held on 0.5
//     within snapReach (slid)
//
// A connector's label stays where it is along it as either end moves: it is
// the line's own, laid again with it (Connectors).

import CoreGraphics
import Foundation

/// A line's words (Element.label).
struct LineLabel: Codable, Equatable, Hashable {
    var text: String
    /// Where along the route, 0 the start to 1 the end.
    var at: Double = 0.5
    /// A family id; nil is the app's default face.
    var font: String?
    var size: Double = LineLabels.defaultSize
    /// "#rrggbb"; nil is the line's colour.
    var color: String?
    var weight: Int = 400
    var italic: Bool = false
    /// Whether the stroke stops round the words.
    var gap: Bool = true

    init(text: String, at: Double = 0.5, font: String? = nil, size: Double = LineLabels.defaultSize,
         color: String? = nil, weight: Int = 400, italic: Bool = false, gap: Bool = true) {
        self.text = text
        self.at = at
        self.font = font
        self.size = size
        self.color = color
        self.weight = weight
        self.italic = italic
        self.gap = gap
    }

    private enum CodingKeys: String, CodingKey { case text, at, font, size, color, weight, italic, gap }

    // Each key on its own, read leniently as the Android twin reads them: a
    // place past either end held to it, a size that is no size the default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        at = (try? c.decode(Double.self, forKey: .at)).flatMap { $0.isFinite ? min(max($0, 0), 1) : nil } ?? 0.5
        font = (try? c.decode(String.self, forKey: .font)).flatMap { $0.isEmpty ? nil : $0 }
        size = (try? c.decode(Double.self, forKey: .size)).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            ?? LineLabels.defaultSize
        color = (try? c.decode(String.self, forKey: .color)).flatMap { $0.isEmpty ? nil : $0 }
        weight = (try? c.decode(Int.self, forKey: .weight)) ?? 400
        italic = (try? c.decode(Bool.self, forKey: .italic)) ?? false
        gap = (try? c.decode(Bool.self, forKey: .gap)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(at, forKey: .at)
        try c.encodeIfPresent(font, forKey: .font)
        try c.encode(size, forKey: .size)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encode(weight, forKey: .weight)
        try c.encode(italic, forKey: .italic)
        try c.encode(gap, forKey: .gap)
    }
}

enum LineLabels {

    /// A new label's type size, in page units.
    static let defaultSize = 18.0
    /// How far past the words' box the stroke stops.
    static let gapPad = 4.0
    /// Within this share of the length of the middle, a dragged label sits
    /// on it.
    static let snapReach = 0.03

    /// `el`'s label when it is a line with words to show; nil otherwise.
    static func label(of el: Element) -> LineLabel? {
        guard el.type == .line, let label = el.label,
              !RichText.strip(label.text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return label
    }

    // MARK: along the route

    /// `route` with consecutive points that are the same taken once.
    static func cleaned(_ route: [CGPoint]) -> [CGPoint] {
        route.reduce(into: [CGPoint]()) { out, p in
            if out.last != p { out.append(p) }
        }
    }

    /// Each point's distance along `route` from its start.
    static func lengths(_ route: [CGPoint]) -> [Double] {
        var out = [0.0]
        for (a, b) in zip(route, route.dropFirst()) {
            out.append(out[out.count - 1] + Double(hypot(b.x - a.x, b.y - a.y)))
        }
        return out
    }

    /// The piece of `route` a point `distance` along it is on — the one that
    /// ends there at a corner — and how far along that piece, 0…1.
    private static func piece(_ cumulative: [Double], _ distance: Double) -> (index: Int, t: Double) {
        var i = 1
        while i < cumulative.count - 1 && cumulative[i] < distance { i += 1 }
        let span = cumulative[i] - cumulative[i - 1]
        let t = span > 0 ? (distance - cumulative[i - 1]) / span : 0
        return (i, min(max(t, 0), 1))
    }

    /// The point `at` (0…1) of the way along `route`'s length.
    static func pointAt(_ route: [CGPoint], at: Double) -> CGPoint {
        let points = cleaned(route)
        guard points.count >= 2 else { return points.first ?? .zero }
        let cumulative = lengths(points)
        let found = piece(cumulative, min(max(at, 0), 1) * cumulative[cumulative.count - 1])
        let a = points[found.index - 1], b = points[found.index]
        return CGPoint(x: Double(a.x) + Double(b.x - a.x) * found.t, y: Double(a.y) + Double(b.y - a.y) * found.t)
    }

    /// The heading of `route` there, in radians (0 along +x, y down).
    static func tangentAt(_ route: [CGPoint], at: Double) -> Double {
        let points = cleaned(route)
        guard points.count >= 2 else { return 0 }
        let cumulative = lengths(points)
        let found = piece(cumulative, min(max(at, 0), 1) * cumulative[cumulative.count - 1])
        let a = points[found.index - 1], b = points[found.index]
        return atan2(Double(b.y - a.y), Double(b.x - a.x))
    }

    /// `el`'s route on the page.
    static func route(of el: Element) -> [CGPoint] {
        LineRoutes.polyline(el).map { LineRoutes.toPage(el, $0) }
    }

    // MARK: the words' box

    /// The label as a text box: its words in its face, size, weight, slant
    /// and colour (the line's when it has none), centred, as wide as they
    /// are, its centre where the label sits on the page.
    static func textElement(for el: Element) -> Element? {
        guard let label = label(of: el) else { return nil }
        return words(label, on: el, atLeast: 1)
    }

    /// The label as the typing field shows it, words or none yet: as
    /// textElement, at least an em and a half wide.
    static func fieldElement(for el: Element) -> Element? {
        guard el.type == .line, let label = el.label else { return nil }
        return words(label, on: el, atLeast: label.size * 1.5)
    }

    /// `label`'s words on the line `el`, at least `least` wide.
    private static func words(_ label: LineLabel, on el: Element, atLeast least: Double) -> Element {
        var text = Element.text(label.text, fontSize: label.size, w: 10_000)
        text.id = el.id + "-label"
        text.fontFamily = label.font ?? text.fontFamily
        text.fontWeight = label.weight
        text.italic = label.italic ? true : nil
        text.color = label.color ?? el.color ?? "#1f2430"
        text.w = max(least, ceil(Double(FontLibrary.attributedString(for: text).size().width)) + 1)
        text.h = FontLibrary.layoutHeight(for: text)
        let centre = pointAt(route(of: el), at: label.at)
        text.x = Double(centre.x) - text.w / 2
        text.y = Double(centre.y) - text.h / 2
        text.opacity = el.opacity
        return text
    }

    /// Where the label's words stand on the page, upright; nil for none.
    static func rect(of el: Element) -> CGRect? {
        textElement(for: el).map { $0.frame }
    }

    /// The box the stroke stops round: the words' grown by gapPad; nil for
    /// none, or a label set not to break the stroke.
    static func gapRect(of el: Element) -> CGRect? {
        guard label(of: el)?.gap == true, let words = rect(of: el) else { return nil }
        return words.insetBy(dx: -gapPad, dy: -gapPad)
    }

    // MARK: the stroke round the words

    /// The pieces of `route` to stroke round a label whose words stand in
    /// `labelRect`: the route less what lies within that box grown by
    /// gapPad, each piece cut where it enters and leaves it, in order.
    static func clipGap(_ route: [CGPoint], _ labelRect: CGRect) -> [[CGPoint]] {
        clipped(cleaned(route), labelRect.insetBy(dx: -gapPad, dy: -gapPad))
    }

    /// `route` less what lies within `box`.
    static func clipped(_ route: [CGPoint], _ box: CGRect) -> [[CGPoint]] {
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
            CGPoint(x: Double(a.x) + Double(b.x - a.x) * t, y: Double(a.y) + Double(b.y - a.y) * t)
        }
        func close() {
            if current.count >= 2 { runs.append(current) }
            current = []
        }
        for (a, b) in zip(route, route.dropFirst()) {
            guard let inside = within(a, b, box) else {
                if current.isEmpty { current = [a] }
                current.append(b)
                continue
            }
            if inside.from > 0 {
                if current.isEmpty { current = [a] }
                current.append(lerp(a, b, inside.from))
            }
            close()
            if inside.to < 1 { current = [lerp(a, b, inside.to), b] }
        }
        close()
        return runs
    }

    /// The share of the piece from `a` to `b` within `box` (Liang–Barsky);
    /// nil when none of it is, or only a point.
    static func within(_ a: CGPoint, _ b: CGPoint, _ box: CGRect) -> (from: Double, to: Double)? {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        var t0 = 0.0, t1 = 1.0
        let checks: [(Double, Double)] = [
            (-dx, Double(a.x - box.minX)), (dx, Double(box.maxX - a.x)),
            (-dy, Double(a.y - box.minY)), (dy, Double(box.maxY - a.y)),
        ]
        for (p, q) in checks {
            if p == 0 {
                if q < 0 { return nil }
                continue
            }
            let r = q / p
            if p < 0 { t0 = max(t0, r) } else { t1 = min(t1, r) }
            if t0 > t1 { return nil }
        }
        return t1 - t0 > 1e-9 ? (t0, t1) : nil
    }

    // MARK: changing it

    /// Where along `el`'s route a label dragged to `point` on the page sits:
    /// the route's nearest point, as a share of its length, held on 0.5
    /// within snapReach.
    static func slid(_ el: Element, toward point: CGPoint) -> Double {
        let points = cleaned(route(of: el))
        guard points.count >= 2 else { return 0.5 }
        let cumulative = lengths(points)
        let total = cumulative[cumulative.count - 1]
        guard total > 0 else { return 0.5 }
        var best = (distance: Double.infinity, along: 0.0)
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let length2 = dx * dx + dy * dy
            let t = length2 == 0 ? 0 : min(max((Double(point.x - a.x) * dx + Double(point.y - a.y) * dy) / length2, 0), 1)
            let gap = hypot(Double(a.x) + dx * t - Double(point.x), Double(a.y) + dy * t - Double(point.y))
            if gap < best.distance { best = (gap, cumulative[i - 1] + t * (cumulative[i] - cumulative[i - 1])) }
        }
        let at = best.along / total
        return abs(at - 0.5) <= snapReach ? 0.5 : at
    }

    /// What a screen reader says for a line: "Line, labelled Yes" when it
    /// has words; nil for none.
    static func spoken(_ el: Element) -> String? {
        guard let label = label(of: el) else { return nil }
        return tr("Line, labelled %@", RichText.strip(label.text))
    }
}
