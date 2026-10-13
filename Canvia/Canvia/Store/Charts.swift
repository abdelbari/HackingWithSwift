// Charts that stay editable: every element of a chart carries the chart it
// makes up (Element.chart) — its kind, its data as typed and its switches —
// so selecting any of it offers Edit chart, and Update draws it again from
// the new data in the same place, as one step. The Android twin's
// EditorViewModel does the same with the same keys.

import Foundation

extension DesignStore {

    /// The chart the selection is part of, when it is one Edit chart can draw
    /// again: some of it carries a chart of a kind this build knows, all of
    /// that the same one. A chart from before charts were kept — a plain
    /// group — has none, and a kind from a newer build is kept as it is. A
    /// locked chart still offers Edit chart, which says how to unlock it, as
    /// on the Android twin.
    var selectedChart: ChartSpec? {
        let charted = selectedElements.filter { $0.chart != nil }
        guard let spec = charted.first?.chart, charted.allSatisfy({ $0.chart?.id == spec.id }),
              DataGraphics.ChartKind(rawValue: spec.kind) != nil else { return nil }
        return spec
    }

    /// Whether any element of chart `id` on the page is locked: Edit chart
    /// then only says how to unlock it.
    func chartIsLocked(_ id: String) -> Bool {
        page.elements.contains { $0.locked && $0.chart?.id == id }
    }

    /// The series number a chart part names: 2 for "series:2".
    static func chartSeries(_ part: String?) -> Int? {
        guard let part, part.hasPrefix("series:") else { return nil }
        return Int(part.dropFirst("series:".count))
    }

    /// The colour a chart's mark shows: a line's stroke — its fill being
    /// none, or a solid colour wholly see-through — anything else's fill, as
    /// the Android twin's `seriesColours` reads it.
    static func chartColour(of el: Element) -> Paint? {
        let unfilled = el.fill == nil || el.fill?.kind == "none" || (el.fill?.kind == "solid" && isClear(el.fill?.color))
        if unfilled, let stroke = el.stroke, (el.strokeWidth ?? 0) > 0 { return .solid(stroke) }
        return el.fill
    }

    /// An eight-digit hex colour whose alpha is zero.
    private static func isClear(_ hex: String?) -> Bool {
        guard var digits = hex?.trimmingCharacters(in: .whitespaces) else { return false }
        if digits.hasPrefix("#") { digits.removeFirst() }
        return digits.count == 8 && UInt8(digits.suffix(2), radix: 16) == 0
    }

    /// Draws chart `spec` again in place of every element on the page that
    /// carries its id: so that it fills the box their frames fill together —
    /// measured with them upright, as the Android twin measures it, so
    /// Update after Update never shrinks or grows it — as the chart before
    /// did (see DataGraphics.updateFrame), at the place in the stack of the
    /// lowest of them, under the group of the lowest one in a group, with
    /// the colours they had by series ("series:<n>") and a new series in a
    /// colour of the design's the chart does not show yet
    /// (DataGraphics.palette(updating:)), turned, faded, linked and animated
    /// as they all were (DataGraphics.carrying), still hidden when the whole
    /// of it was — as one step, the new chart's whole group selected. False,
    /// and nothing recorded, when the chart is not on the page or the data
    /// draws nothing.
    @discardableResult
    func updateChart(_ spec: ChartSpec) -> Bool {
        let members = page.elements.filter { $0.chart?.id == spec.id }
        guard let was = members.first?.chart else { return false }
        // Measured upright, turned about the middle of the box they fill,
        // and turned back the same way once drawn.
        let turn = DataGraphics.turn(of: members)
        let box = Geometry.union(members.map(\.frame))
        let pivot = CGPoint(x: box.midX, y: box.midY)
        let upright = turn != 0 ? Geometry.rotate(members, around: pivot, by: -turn) : members
        let frame = DataGraphics.updateFrame(was, to: spec, bounds: Geometry.union(upright.map(\.frame)),
                                             width: pageWidth, height: pageHeight)
        var colours: [Int: Paint] = [:]
        for el in members {
            guard let n = Self.chartSeries(el.chartPart), colours[n] == nil,
                  let paint = Self.chartColour(of: el) else { continue }
            colours[n] = paint
        }
        let palette = DataGraphics.palette(updating: spec.id, design: design, page: page, colours: colours)
        var made = DataGraphics.chart(spec, in: frame, palette: palette,
                                      ink: DataGraphics.ink(for: page), colours: colours,
                                      group: members.first(where: { $0.group != nil })?.group ?? UID.make("grp"))
        guard !made.isEmpty else { return false }
        made = DataGraphics.carrying(members, into: made, pivot: pivot, turn: turn)
        // A chart hidden whole stays hidden; one only partly hidden comes
        // back whole, as on Android.
        if members.allSatisfy(\.isHidden) {
            for i in made.indices { made[i].hidden = true }
        }
        let ids = Set(members.map(\.id))
        applyToPage { page in
            guard let at = page.elements.firstIndex(where: { ids.contains($0.id) }) else { return }
            page.elements.removeAll { ids.contains($0.id) }
            page.elements.insert(contentsOf: made, at: at)
        }
        // The new chart's whole group, as a tap on it selects, as on Android.
        selection = Set(page.elements.filter { $0.group == made[0].group }.map(\.id))
        return true
    }
}
