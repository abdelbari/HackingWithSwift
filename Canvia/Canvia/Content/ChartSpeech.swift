// What VoiceOver says of a chart, as the Android twin's ChartSpeech says it:
// the chart as a whole, one stop with a summary — "Column chart, 3 series,
// 4 categories, values 0 to 120" — and each of its series' parts, which a
// reader steps through with Next value and Previous value (partLabel),
// kept on the part as its alt text when the chart is made.

import Foundation

enum ChartSpeech {

    /// `spec`'s chart in a sentence: its kind, how many series and
    /// categories (rows) it has, and its values from the least to the most,
    /// as its labels write them (DataGraphics.formatValue). A progress kind
    /// says its percentage instead: "Progress ring chart, 72%". A scatter's
    /// and a bubble chart's values are their y; a kind coloured by row is
    /// one series. "Chart" for a kind this build does not know.
    static func summary(_ spec: ChartSpec, data: DataGraphics.ChartData) -> String {
        guard let kind = DataGraphics.ChartKind(rawValue: spec.kind) else { return tr("Chart") }
        let chart = tr("%@ chart", kind.name)
        guard !data.rows.isEmpty else { return chart }
        if kind.isProgress { return tr("%@, %@", chart, percent(data)) }
        let names = data.names.indices
        let values: [Double]
        switch kind {
        case .scatter:
            values = data.rows.flatMap { row in names.map { value(row, 2 * $0 + 1) } }
        case .bubble:
            values = data.rows.flatMap { row in names.map { value(row, 3 * $0 + 1) } }
        case .pie, .donut, .funnel, .pictogram:
            values = data.rows.map { value($0, 0) }
        default:
            values = data.rows.flatMap { row in names.map { value(row, $0) } }
        }
        let series = kind.colourByRow ? 1 : data.names.count
        return tr("%@, %@, %@, values %@ to %@", chart, trn("%d series|%d series", series),
                  trn("%d category|%d categories", data.rows.count),
                  DataGraphics.formatValue(values.min() ?? 0, spec), DataGraphics.formatValue(values.max() ?? 0, spec))
    }

    /// What series part `part` ("series:<n>") of `spec`'s chart says, for
    /// row `index` of it — or, at an index below 0, the series as a whole: a
    /// line's, an area's or a radar's outline, "Sales line, from 40 to 96"
    /// (its first value and its last). A bar, a segment, a point or a cell
    /// says its row and its series, "Q2, Sales: 84"; a scatter's point its x
    /// and y, "A, Sales: 10, 20", and a bubble its size after them; a kind
    /// coloured by row — a pie's slice ("Yes: 75%"), a funnel's stage, a
    /// pictogram's icons — its row alone; a progress kind its percentage.
    /// A part-to-whole kind says its value, its share or both as its labels
    /// read (DataGraphics.labelAs): a stack's segment its share of the stack.
    /// One series of columns or bars, each row its own colour, has its part
    /// numbered by row and reads series 0. A heat map's cells are all
    /// "series:0" and number row by row: `index` is row × series + series.
    /// Nil for a part that is no series' or a row the data lacks.
    static func partLabel(_ spec: ChartSpec, data: DataGraphics.ChartData, part: String, index: Int) -> String? {
        guard part.hasPrefix("series:"), let n = Int(part.dropFirst("series:".count)),
              let kind = DataGraphics.ChartKind(rawValue: spec.kind) else { return nil }
        let rows = data.rows
        let names = data.names
        func v(_ x: Double) -> String { DataGraphics.formatValue(x, spec) }
        func row(_ i: Int) -> DataGraphics.ChartData.Row? { i >= 0 && i < rows.count ? rows[i] : nil }
        if kind.isProgress { return percent(data) }
        if index < 0 {
            guard n >= 0, n < names.count, let first = rows.first, let last = rows.last else { return nil }
            let from = v(value(first, n)), to = v(value(last, n))
            return kind == .area ? tr("%@ area, from %@ to %@", names[n], from, to)
                : tr("%@ line, from %@ to %@", names[n], from, to)
        }
        switch kind {
        case .pie, .donut:
            guard let r = row(index) else { return nil }
            let total = rows.reduce(0) { $0 + value($1, 0) }
            guard total > 0 else { return nil }
            return tr("%@: %@", r.label, DataGraphics.labelText(value(r, 0), share: value(r, 0) / total, spec))
        case .funnel, .pictogram:
            guard let r = row(index) else { return nil }
            let total = rows.reduce(0) { $0 + value($1, 0) }
            return tr("%@: %@", r.label, DataGraphics.labelText(value(r, 0), share: total > 0 ? value(r, 0) / total : 0, spec))
        case .heatmap:
            guard !names.isEmpty, let r = row(index / names.count) else { return nil }
            let j = index % names.count
            return tr("%@, %@: %@", r.label, names[j], v(value(r, j)))
        case .scatter, .bubble:
            guard let r = row(index), n >= 0, n < names.count else { return nil }
            let width = kind == .bubble ? 3 : 2
            let point = (0..<width).map { v(value(r, width * n + $0)) }.joined(separator: ", ")
            return tr("%@, %@: %@", r.label, names[n], point)
        default:
            let j = names.count == 1 ? 0 : n
            guard let r = row(index), j >= 0, j < names.count else { return nil }
            guard kind.isStacked else { return tr("%@, %@: %@", r.label, names[j], v(value(r, j))) }
            // A segment's share of its stack, as its label reads it.
            let whole = r.values.reduce(0) { $0 + ($1 > 0 ? $1 : 0) }
            let said = DataGraphics.labelText(value(r, j), share: whole > 0 ? max(value(r, j), 0) / whole : 0, spec)
            return tr("%@, %@: %@", r.label, names[j], said)
        }
    }

    /// The labels a reader steps through with Next value and Previous
    /// value: the alt text of each of a chart's series parts, in the page's
    /// order.
    static func stops(_ members: [Element]) -> [String] {
        members.filter { $0.chartPart?.hasPrefix("series:") == true }.compactMap { el in
            el.altText.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// The summary of the chart `el` is a part of; nil for anything that is
    /// no chart's part.
    static func summary(of el: Element) -> String? {
        guard let spec = el.chart, el.chartPart != nil,
              let kind = DataGraphics.ChartKind(rawValue: spec.kind) else { return nil }
        return summary(spec, data: DataGraphics.chartData(spec.data, kind: kind))
    }

    /// Value `s` of `row`; 0 past its last.
    private static func value(_ row: DataGraphics.ChartData.Row, _ s: Int) -> Double {
        s >= 0 && s < row.values.count ? row.values[s] : 0
    }

    /// A progress kind's first value, 0…100, as a whole percentage.
    private static func percent(_ data: DataGraphics.ChartData) -> String {
        let p = min(max(data.rows.first?.values.first ?? 0, 0), 100)
        return "\(Int(p.rounded()))%"
    }
}
