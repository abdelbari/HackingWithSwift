// Your own gradient: its colours, extra stops, direction and shape — one
// model and one editor for a shape's fill, a page's background and a
// text's letters (textFill), the Android twin's GradientEditing rule for
// rule, with the same test rows.
//
// It edits the Paint as it is: {"kind": "gradient", "angle", "stops":
// [{"offset", "color"}], "gradientKind"} — no new keys. A gradient holds 2
// to 5 stops, kept in order of position:
//
// - + adds a stop in the middle of the widest gap between two neighbours
//   (the first, on a tie), coloured halfway between them, channel by
//   channel, rounded half up.
// - A stop is taken away down to two.
// - A stop dragged stays between its neighbours and inside 0…1, at a
//   hundredth.
// - The angle (linear) is held to 0…359 in whole degrees, and snaps to a
//   multiple of 45 within 4.
//
// The last eight gradients you made (GradientRecents) are kept on this
// phone, newest first.

import Foundation

enum GradientEditing {

    static let minStops = 2
    static let maxStops = 5

    /// The angles the editor offers as chips.
    static let angles: [Double] = [0, 45, 90, 135, 180, 225, 270, 315]

    /// Within this many degrees of a multiple of 45 the angle is held on it.
    static let snapReach = 4.0

    /// The shapes a gradient comes in, as presets store them.
    static let kinds = ["linear", "radial", "angular"]

    /// `paint` as the editor shows it: its stops in order when it is a
    /// gradient of two or more; else `colour` (or the app's ink) running
    /// to white, left to right.
    static func editable(_ paint: Paint?, colour: String?) -> Paint {
        if let paint, paint.kind == "gradient", let stops = paint.stops, stops.count >= minStops {
            var out = paint
            out.stops = Array(ordered(stops).prefix(maxStops))
            return out
        }
        let first = colour.map(RecentColors.normalise).flatMap { $0.isEmpty ? nil : $0 } ?? "#1f2430"
        return Paint(kind: "gradient", color: nil, angle: 90,
                     stops: [GradientStop(offset: 0, color: first), GradientStop(offset: 1, color: "#ffffff")])
    }

    /// Stops by position, those at one position kept in their order.
    static func ordered(_ stops: [GradientStop]) -> [GradientStop] {
        stops.enumerated().sorted { a, b in
            a.element.offset == b.element.offset ? a.offset < b.offset : a.element.offset < b.element.offset
        }.map(\.element)
    }

    /// Whether another stop can be added, or one taken away.
    static func canAdd(_ paint: Paint) -> Bool { (paint.stops?.count ?? 0) < maxStops }
    static func canRemove(_ paint: Paint) -> Bool { (paint.stops?.count ?? 0) > minStops }

    /// `paint` with a stop in the middle of its widest gap, coloured
    /// halfway between the two either side; itself at five stops.
    static func adding(_ paint: Paint) -> Paint {
        let stops = ordered(paint.stops ?? [])
        guard stops.count >= minStops, stops.count < maxStops else { return paint }
        var widest = 0
        for i in 1..<(stops.count - 1) where stops[i + 1].offset - stops[i].offset > stops[widest + 1].offset - stops[widest].offset {
            widest = i
        }
        let a = stops[widest], b = stops[widest + 1]
        let middle = ((a.offset + b.offset) / 2 * 100).rounded() / 100
        var out = paint
        var next = stops
        next.insert(GradientStop(offset: middle, color: mix(a.color, b.color)), at: widest + 1)
        out.stops = next
        return out
    }

    /// `paint` without its stop `index` (in position order); itself at two.
    static func removing(_ paint: Paint, at index: Int) -> Paint {
        var stops = ordered(paint.stops ?? [])
        guard stops.count > minStops, stops.indices.contains(index) else { return paint }
        stops.remove(at: index)
        var out = paint
        out.stops = stops
        return out
    }

    /// `paint` with stop `index` in `hex`.
    static func recoloured(_ paint: Paint, at index: Int, _ hex: String) -> Paint {
        var stops = ordered(paint.stops ?? [])
        guard stops.indices.contains(index) else { return paint }
        stops[index].color = hex
        var out = paint
        out.stops = stops
        return out
    }

    /// `paint` with stop `index` at `position`, held between its
    /// neighbours and inside 0…1, at a hundredth.
    static func moved(_ paint: Paint, at index: Int, to position: Double) -> Paint {
        var stops = ordered(paint.stops ?? [])
        guard stops.indices.contains(index), position.isFinite else { return paint }
        let low = index > 0 ? stops[index - 1].offset : 0
        let high = index < stops.count - 1 ? stops[index + 1].offset : 1
        let at = (min(max(position, 0), 1) * 100).rounded() / 100
        stops[index].offset = min(max(at, low), high)
        var out = paint
        out.stops = stops
        return out
    }

    /// An angle in whole degrees 0…359, held on a multiple of 45 within
    /// snapReach of it.
    static func snapped(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let whole = degrees.rounded()
        let nearest = (whole / 45).rounded() * 45
        let held = abs(whole - nearest) <= snapReach ? nearest : whole
        return (held.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// `paint` pointing `degrees` (the CSS convention it stores: 0 up, 90
    /// right), snapped.
    static func angled(_ paint: Paint, _ degrees: Double) -> Paint {
        var out = paint
        out.angle = snapped(degrees)
        return out
    }

    /// `paint` in the shape `kind`: "linear" is written as no gradientKind.
    static func shaped(_ paint: Paint, _ kind: String) -> Paint {
        var out = paint
        out.gradientKind = kind == "linear" || !kinds.contains(kind) ? nil : kind
        return out
    }

    /// Halfway between two colours, channel by channel, rounded half up:
    /// "#ff0000" and "#0000ff" make "#800080". A colour that does not read
    /// leaves the other.
    static func mix(_ a: String, _ b: String) -> String {
        let x = RecentColors.normalise(a), y = RecentColors.normalise(b)
        guard !x.isEmpty else { return y.isEmpty ? a : y }
        guard !y.isEmpty else { return x }
        func channel(_ hex: String, _ i: Int) -> Int {
            let start = hex.index(hex.startIndex, offsetBy: 1 + 2 * i)
            return Int(hex[start..<hex.index(start, offsetBy: 2)], radix: 16) ?? 0
        }
        let mixed = (0..<3).map { i in (channel(x, i) + channel(y, i) + 1) / 2 }
        return "#" + mixed.map { String(format: "%02x", $0) }.joined()
    }
}

/// The last gradients made in the editor, newest first, kept on this phone
/// as the encoded paints.
enum GradientRecents {
    static let limit = 8
    static let key = "canvia.recentGradients"

    static func all(_ defaults: UserDefaults = .standard) -> [Paint] {
        guard let data = defaults.data(forKey: key),
              let paints = try? JSONDecoder().decode([Paint].self, from: data) else { return [] }
        return paints.filter { $0.kind == "gradient" && ($0.stops?.count ?? 0) >= GradientEditing.minStops }
    }

    /// `paint` first, once, the list held to eight.
    static func record(_ paint: Paint, _ defaults: UserDefaults = .standard) {
        guard paint.kind == "gradient", (paint.stops?.count ?? 0) >= GradientEditing.minStops else { return }
        let list = [paint] + all(defaults).filter { $0 != paint }
        guard let data = try? JSONEncoder().encode(Array(list.prefix(limit))) else { return }
        defaults.set(data, forKey: key)
    }
}
