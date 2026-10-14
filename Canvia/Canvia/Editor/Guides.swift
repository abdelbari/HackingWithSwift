// Guides laid out for you: columns and rows, a gutter between them and a
// margin round them, turned into ordinary guides — the `guides` the design
// already keeps, each dragged, moved or removed like one placed by hand.
// Nothing new is written to the file. The Android twin's Guides.layout
// lays them out by the same rules. And the rulers' arithmetic: their ticks,
// labels and the guides pulled out of them.

import Foundation
import CoreGraphics

enum Guides {

    /// One of Add guides' ready-made layouts.
    struct PresetLayout: Identifiable, Equatable {
        var label: String
        var columns: Int
        var rows: Int
        var id: String { label }
    }

    /// Columns alone, then a three-by-three grid, none with a gutter or a
    /// margin; Custom sets those.
    static let presets: [PresetLayout] = [
        PresetLayout(label: "2 columns", columns: 2, rows: 0),
        PresetLayout(label: "3 columns", columns: 3, rows: 0),
        PresetLayout(label: "4 columns", columns: 4, rows: 0),
        PresetLayout(label: "6 columns", columns: 6, rows: 0),
        PresetLayout(label: "12 columns", columns: 12, rows: 0),
        PresetLayout(label: "3 × 3 grid", columns: 3, rows: 3),
    ]
    static let customLabel = "Custom…"

    /// What Custom takes, in whole pixels for the gutter and margin.
    static let columnRange = 1...24
    static let rowRange = 0...24
    static let gutterRange = 0...200
    static let marginRange = 0...400

    /// How close a guide may come to one already there, in pixels, and still
    /// count as the same line.
    static let tolerance = 0.5

    /// The guides for `columns` columns and `rows` rows on a page of `size`,
    /// leaving out any within `tolerance` of a guide in `existing` (or of one
    /// made before it): vertical ones left to right, then horizontal ones top
    /// to bottom. The columns share the width inside the margin; each
    /// boundary between two is a guide at either side of the gutter, or one
    /// guide with no gutter. A margin is a guide at either side too. No rows
    /// is no horizontal guides at all; one row is only its margins. Every
    /// guide falls on a half pixel. Out-of-range numbers are brought into
    /// Custom's ranges.
    static func layout(size: CGSize, columns: Int, rows: Int, gutter: Double, margin: Double,
                       existing: [Guide] = []) -> [Guide] {
        let columns = min(max(columns, columnRange.lowerBound), columnRange.upperBound)
        let rows = min(max(rows, rowRange.lowerBound), rowRange.upperBound)
        let gutter = min(max(gutter, Double(gutterRange.lowerBound)), Double(gutterRange.upperBound))
        let margin = min(max(margin, Double(marginRange.lowerBound)), Double(marginRange.upperBound))
        var taken = existing
        var made: [Guide] = []
        func add(_ position: Double, vertical: Bool) {
            guard !taken.contains(where: { $0.vertical == vertical && abs($0.position - position) <= tolerance })
            else { return }
            let guide = Guide(vertical: vertical, position: position)
            taken.append(guide)
            made.append(guide)
        }
        for x in lines(across: Double(size.width), count: columns, gutter: gutter, margin: margin) {
            add(x, vertical: true)
        }
        if rows > 0 {
            for y in lines(across: Double(size.height), count: rows, gutter: gutter, margin: margin) {
                add(y, vertical: false)
            }
        }
        return made
    }

    /// The lines along one side `length` long, in order: the margins, and
    /// the gutter edges of every boundary between `count` equal tracks
    /// inside them — on half pixels, within the page. A margin past half the
    /// side meets the other in the middle, and a gutter that leaves no room
    /// leaves tracks of nothing, as on Android.
    static func lines(across length: Double, count: Int, gutter: Double, margin: Double) -> [Double] {
        guard length > 0, count >= 1 else { return [] }
        let margin = min(margin, length / 2)
        var out: [Double] = []
        if margin > 0 { out += [margin, length - margin] }
        let track = max(0, (length - 2 * margin - gutter * Double(count - 1)) / Double(count))
        for i in 1..<count {
            let edge = margin + Double(i) * track + Double(i - 1) * gutter
            out.append(edge)
            if gutter > 0 { out.append(edge + gutter) }
        }
        return out.map { min(max(halfPixel($0), 0), length) }.sorted()
    }

    /// `value` to the nearest half pixel.
    static func halfPixel(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    // MARK: rulers

    /// The More menu's "Rulers": off unless turned on. The Android twin's
    /// Prefs key.
    static let rulersKey = "rulers"

    /// How thick the rulers along the canvas's top and left are, in points.
    static let rulerThickness = 20.0

    /// The least two labelled ticks of a ruler stand apart, in points.
    static let rulerMajorGap = 48.0

    /// The small ticks between two labelled ones: each step in five.
    static let rulerDivisions = 5

    /// The step between a ruler's labelled ticks, in the ruler's unit, at
    /// `zoom` points to a unit: the least of 1, 2 or 5 times a power of ten
    /// that puts them `rulerMajorGap` apart or more — 50 px at 1 point a
    /// pixel, 5 mm at 10 points a millimetre, 0.5 in at 100 points an inch.
    /// 1 for a zoom that is no zoom. The Android twin's `rulerStep`.
    static func rulerStep(_ zoom: Double) -> Double {
        let need = rulerMajorGap / zoom
        guard zoom.isFinite, zoom > 0, need.isFinite, need > 0 else { return 1 }
        // The power of ten at or below what one step must span: a step is
        // found at it or the next one up.
        let power = Int(floor(log10(need)))
        // Built from whole numbers, so 0.2 is the 0.2 a person types and
        // not 2 × 0.1's neighbour.
        func step(_ m: Double, _ p: Int) -> Double {
            p >= 0 ? m * pow(10, Double(p)) : m / pow(10, Double(-p))
        }
        for p in power...(power + 2) {
            for m in [1.0, 2.0, 5.0] {
                let s = step(m, p)
                if s * zoom >= rulerMajorGap - 1e-9 { return s }
            }
        }
        return step(1, power + 3)
    }

    /// One tick of a ruler: where, in the ruler's unit, and whether it is a
    /// labelled one.
    struct Tick: Equatable {
        var value: Double
        var major: Bool
    }

    /// The ticks of a ruler from `from` to `to` in its unit, a labelled one
    /// every `step` — from 0 at the page's top left, so negative before it —
    /// with `rulerDivisions` small ones to each step. None for a stretch of
    /// more than ten thousand.
    static func rulerTicks(from: Double, to: Double, step: Double) -> [Tick] {
        guard step > 0, from.isFinite, to.isFinite, to >= from else { return [] }
        let minor = step / Double(rulerDivisions)
        let first = (from / minor - 1e-9).rounded(.up)
        let last = (to / minor + 1e-9).rounded(.down)
        guard abs(first) < 1e15, abs(last) < 1e15, last - first <= 10_000, first <= last else { return [] }
        return (Int(first)...Int(last)).map { k in
            Tick(value: Double(k) * step / Double(rulerDivisions), major: k % rulerDivisions == 0)
        }
    }

    /// A labelled tick's number: to as many places as the step has, none
    /// for a step of 1 or more, and without trailing zeros — "50", "1.5",
    /// "1" — written with a point whatever the phone's language, and never
    /// "-0". The Android twin's `rulerLabel`.
    static func rulerLabel(_ value: Double, step: Double) -> String {
        var places = 0
        var s = step
        while places < 6 && s < 1 - 1e-9 {
            s *= 10
            places += 1
        }
        var text = String(format: "%.\(places)f", value)
        if places > 0 {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// The unit `design`'s rulers count in, and how many page pixels make
    /// one: millimetres, centimetres or inches at the design's dpi; pixels
    /// one to one.
    static func rulerUnit(_ design: Design) -> (unit: String, pixels: Double) {
        guard let unit = design.physicalUnit else { return ("px", 1) }
        return (unit, design.effectiveDPI / Units.perInch(unit))
    }

    /// Whether `position` on the page, along a ruler, is over that ruler
    /// on screen: within `rulerThickness` points of the view's edge, or past
    /// it — the view showing from `viewportStart`, at `zoom` points a page
    /// unit. Where a guide dragged back goes, and a new one is not made.
    static func onRuler(_ position: Double, viewportStart: Double, zoom: Double) -> Bool {
        (position - viewportStart) * zoom < rulerThickness
    }

    /// Where a guide pulled out of a ruler lands, in page units: on the
    /// nearest of `lines` — the elements' edges and middles, the page's —
    /// within `threshold`, else on the whole unit nearest `position`,
    /// `unitPixels` page pixels to a unit, to the half pixel; and on the
    /// page, from 0 to `limit`.
    static func rulerGuidePosition(_ position: Double, lines: [Double], threshold: Double,
                                   unitPixels: Double, limit: Double) -> Double {
        let near = lines.filter { abs($0 - position) <= threshold }
            .min { abs($0 - position) < abs($1 - position) }
        let unit = unitPixels > 0 && unitPixels.isFinite ? unitPixels : 1
        let at = near ?? halfPixel((position / unit).rounded() * unit)
        return min(max(at, 0), max(limit, 0))
    }

    /// A position typed for a guide — "120", "120.5", "120 px" — kept within
    /// the page's `limit`; nil when it is not a number.
    static func typedPosition(_ typed: String, limit: Double) -> Double? {
        typedPosition(typed, limit: limit, unit: nil, dpi: Units.screenDPI)
    }

    /// The same in a design measured in `unit` (mm, cm or in) at `dpi`: typed
    /// in that unit — "12.5", "12.5 mm" — as Position's numbers are, and
    /// given back in whole page pixels (Units.typedLength), as Android does.
    /// Pixels with no unit, as typed.
    static func typedPosition(_ typed: String, limit: Double, unit: String?, dpi: Double) -> Double? {
        guard let px = Units.typedLength(typed, unit: unit, dpi: dpi) else { return nil }
        return min(max(px, 0), max(limit, 0))
    }
}
