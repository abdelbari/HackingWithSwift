// Guides laid out for you: columns and rows, a gutter between them and a
// margin round them, turned into ordinary guides — the `guides` the design
// already keeps, each dragged, moved or removed like one placed by hand.
// Nothing new is written to the file. The Android twin's Guides.layout
// lays them out by the same rules.

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

    /// A position typed for a guide — "120", "120.5", "120 px" — kept within
    /// the page's `limit`; nil when it is not a number.
    static func typedPosition(_ typed: String, limit: Double) -> Double? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasSuffix("px") { text = String(text.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        return min(max(value, 0), max(limit, 0))
    }
}
