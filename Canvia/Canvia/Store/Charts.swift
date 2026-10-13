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

    /// The colour a chart's mark shows: a line's stroke, anything else's fill.
    static func chartColour(of el: Element) -> Paint? {
        let unfilled = el.fill == nil || el.fill?.kind == "none" || el.fill?.color == "#00000000"
        if unfilled, let stroke = el.stroke, (el.strokeWidth ?? 0) > 0 { return .solid(stroke) }
        return el.fill
    }

    /// Draws chart `spec` again in place of every element on the page that
    /// carries its id: so that it fills the box they fill together as the
    /// chart before did (see DataGraphics.frameFilling), at the place in the
    /// stack of the lowest of them, under their group, with the colours they
    /// had by series ("series:<n>") — as one step, the new chart selected.
    /// False, and nothing recorded, when the chart is not on the page or the
    /// data draws nothing.
    @discardableResult
    func updateChart(_ spec: ChartSpec) -> Bool {
        let members = page.elements.filter { $0.chart?.id == spec.id }
        guard let was = members.first?.chart else { return false }
        let frame = DataGraphics.frameFilling(was, bounds: Geometry.union(members.map(Geometry.aabb)))
        var colours: [Int: Paint] = [:]
        for el in members {
            guard let n = Self.chartSeries(el.chartPart), colours[n] == nil,
                  let paint = Self.chartColour(of: el) else { continue }
            colours[n] = paint
        }
        let made = DataGraphics.chart(spec, in: frame, palette: DataGraphics.palette(for: design, page: page),
                                      ink: DataGraphics.ink(for: page), colours: colours,
                                      group: members.first(where: { $0.group != nil })?.group ?? UID.make("grp"))
        guard !made.isEmpty else { return false }
        let ids = Set(members.map(\.id))
        applyToPage { page in
            guard let at = page.elements.firstIndex(where: { ids.contains($0.id) }) else { return }
            page.elements.removeAll { ids.contains($0.id) }
            page.elements.insert(contentsOf: made, at: at)
        }
        selection = Set(made.map(\.id))
        return true
    }
}
