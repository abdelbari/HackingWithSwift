// Charts and tables built from typed data, as ordinary elements.
//
// Not a new element kind: a bar chart is rectangles and labels, a pie is
// path shapes, a table is cells and text — all things the editor already
// moves, recolours, exports and reads aloud. The data comes in as lines of
// "Label, value"; the result is a group that behaves like anything else on
// the page.

import Foundation

enum DataGraphics {

    struct Series: Equatable {
        var label: String
        var value: Double
    }

    /// "Label, value" per line; a line with no number is skipped, a line with
    /// only a number gets a numbered label.
    static func parse(_ text: String) -> [Series] {
        text.components(separatedBy: .newlines).enumerated().compactMap { n, line in
            let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let last = parts.last else { return nil }
            let numeric = last.replacingOccurrences(of: "%", with: "")
            guard let value = Double(numeric), value.isFinite else { return nil }
            let label = parts.count > 1 && !parts[0].isEmpty ? parts[0] : "Item \(n + 1)"
            return Series(label: label, value: max(0, value))
        }
    }

    enum ChartKind: String, CaseIterable, Identifiable {
        case bar, column, pie, donut, line
        var id: String { rawValue }
        var name: String {
            switch self {
            case .bar: return "Bars"
            case .column: return "Columns"
            case .pie: return "Pie"
            case .donut: return "Donut"
            case .line: return "Line"
            }
        }
    }

    /// Chart elements filling `frame`, grouped, coloured from `palette` in
    /// turn, labelled in `ink`.
    static func chart(_ kind: ChartKind, series: [Series], in frame: CGRect,
                      palette: [String], ink: String = "#1f2430") -> [Element] {
        guard !series.isEmpty, frame.width > 0, frame.height > 0 else { return [] }
        let colors = palette.isEmpty ? ["#5a31f4"] : palette
        let group = UID.make("grp")
        var out: [Element] = []
        let labelSize = max(10, (min(frame.width, frame.height) * 0.06).rounded())
        let total = series.reduce(0) { $0 + $1.value }
        let peak = series.map(\.value).max() ?? 1

        func label(_ text: String, x: Double, y: Double, w: Double, align: String = "center") -> Element {
            var t = Element.text(text, fontSize: labelSize, w: max(w, labelSize * 2))
            t.align = align
            t.color = ink
            t.x = x; t.y = y
            t.h = FontLibrary.layoutHeight(for: t)
            return t
        }

        switch kind {
        case .column:
            let labelH = labelSize * 1.6
            let plotH = frame.height - labelH
            let slot = frame.width / Double(series.count)
            let barW = slot * 0.64
            for (i, s) in series.enumerated() {
                let h = peak > 0 ? plotH * s.value / peak : 0
                var bar = Element.shape("rect", w: barW.rounded(), h: max(1, h.rounded()))
                bar.x = (frame.minX + slot * Double(i) + (slot - barW) / 2).rounded()
                bar.y = (frame.minY + plotH - h).rounded()
                bar.fill = .solid(colors[i % colors.count])
                out.append(bar)
                out.append(label(s.label, x: frame.minX + slot * Double(i), y: frame.minY + plotH + labelSize * 0.3, w: slot))
            }
        case .bar:
            let labelW = min(frame.width * 0.28, labelSize * 9)
            let plotW = frame.width - labelW
            let slot = frame.height / Double(series.count)
            let barH = slot * 0.64
            for (i, s) in series.enumerated() {
                let w = peak > 0 ? plotW * s.value / peak : 0
                var bar = Element.shape("rect", w: max(1, w.rounded()), h: barH.rounded())
                bar.x = (frame.minX + labelW).rounded()
                bar.y = (frame.minY + slot * Double(i) + (slot - barH) / 2).rounded()
                bar.fill = .solid(colors[i % colors.count])
                out.append(bar)
                var l = label(s.label, x: frame.minX, y: bar.y + (barH - labelSize * 1.25) / 2, w: labelW - labelSize * 0.5, align: "right")
                l.x = frame.minX
                out.append(l)
            }
        case .pie, .donut:
            let side = min(frame.width, frame.height)
            let box = CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side)
            var start = -Double.pi / 2
            for (i, s) in series.enumerated() where total > 0 && s.value > 0 {
                let sweep = 2 * .pi * s.value / total
                var slice = Element.shape("rect", w: side.rounded(), h: side.rounded())
                slice.x = box.minX.rounded(); slice.y = box.minY.rounded()
                slice.pathData = wedge(from: start, sweep: sweep, inner: kind == .donut ? 0.55 : 0)
                slice.fill = .solid(colors[i % colors.count])
                slice.altText = "\(s.label): \(Int((s.value / total * 100).rounded()))%"
                out.append(slice)
                start += sweep
            }
        case .line:
            let labelH = labelSize * 1.6
            let plotH = frame.height - labelH
            let n = max(series.count - 1, 1)
            let points = series.enumerated().map { i, s in
                CGPoint(x: Double(i) / Double(n) * 100, y: 100 - (peak > 0 ? s.value / peak * 100 : 0))
            }
            var line = Element.shape("rect", w: frame.width.rounded(), h: plotH.rounded())
            line.x = frame.minX.rounded(); line.y = frame.minY.rounded()
            line.pathData = polyline(points)
            line.fill = .solid("#00000000")
            line.stroke = colors[0]
            line.strokeWidth = max(2, (plotH * 0.02).rounded())
            out.append(line)
            let slot = frame.width / Double(series.count)
            for (i, s) in series.enumerated() {
                out.append(label(s.label, x: frame.minX + Double(i) / Double(n) * frame.width - slot / 2,
                                 y: frame.minY + plotH + labelSize * 0.3, w: slot))
            }
        }
        return out.map { var e = $0; e.group = group; return e }
    }

    /// A slice of a circle in a 0…100 box, from `start` radians (clockwise
    /// from 3 o'clock, y down) through `sweep`; with `inner` > 0, a ring.
    static func wedge(from start: Double, sweep: Double, inner: Double) -> String {
        let c = 50.0, r = 50.0, ri = r * inner
        func pt(_ radius: Double, _ a: Double) -> String {
            "\(num(c + radius * cos(a))) \(num(c + radius * sin(a)))"
        }
        // A whole circle: two half arcs, since an arc whose ends coincide
        // is no arc at all once the numbers are rounded.
        if sweep >= 2 * .pi - 0.001 {
            let half = start + .pi
            if inner > 0 {
                return "M\(pt(r, start)) A\(num(r)) \(num(r)) 0 0 1 \(pt(r, half)) A\(num(r)) \(num(r)) 0 0 1 \(pt(r, start)) Z " +
                       "M\(pt(ri, start)) A\(num(ri)) \(num(ri)) 0 0 0 \(pt(ri, half)) A\(num(ri)) \(num(ri)) 0 0 0 \(pt(ri, start)) Z"
            }
            return "M\(num(c)) \(num(c)) L\(pt(r, start)) A\(num(r)) \(num(r)) 0 0 1 \(pt(r, half)) A\(num(r)) \(num(r)) 0 0 1 \(pt(r, start)) Z"
        }
        let end = start + sweep
        let large = sweep > .pi ? 1 : 0
        if inner > 0 {
            return "M\(pt(ri, start)) L\(pt(r, start)) A\(num(r)) \(num(r)) 0 \(large) 1 \(pt(r, end)) " +
                   "L\(pt(ri, end)) A\(num(ri)) \(num(ri)) 0 \(large) 0 \(pt(ri, start)) Z"
        }
        return "M\(num(c)) \(num(c)) L\(pt(r, start)) A\(num(r)) \(num(r)) 0 \(large) 1 \(pt(r, end)) Z"
    }

    static func polyline(_ points: [CGPoint]) -> String {
        guard let first = points.first else { return "" }
        return "M\(num(first.x)) \(num(first.y))" + points.dropFirst().map { " L\(num($0.x)) \(num($0.y))" }.joined()
    }

    private static func num(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    // MARK: tables

    /// Rows of cells as text; the first row is the header. Cells are
    /// separated by commas or tabs.
    static func parseTable(_ text: String) -> [[String]] {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                let sep: Character = line.contains("\t") ? "\t" : ","
                return line.split(separator: sep, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
    }

    /// A table filling `frame`: a header row in `accent` with light text,
    /// banded body rows, hairline cells, text in each cell. Column widths
    /// follow the longest text in each column; row heights follow the text.
    static func table(_ rows: [[String]], in frame: CGRect, accent: String) -> [Element] {
        table(rows, in: frame, accent: accent, ink: "#1f2430", band: "#f3f4f6", fontSize: nil)
    }

    static func table(_ rows: [[String]], in frame: CGRect, accent: String, ink: String,
                      band: String, fontSize: Double?) -> [Element] {
        guard let columns = rows.map(\.count).max(), columns > 0, !rows.isEmpty,
              frame.width > 0 else { return [] }
        let group = UID.make("grp")
        let size = fontSize ?? max(10, (frame.width / Double(columns) * 0.11).rounded())
        let pad = size * 0.6
        // Column widths in proportion to the longest cell, floored so an
        // empty column still exists.
        let longest = (0..<columns).map { c in
            max(3.0, rows.map { $0.count > c ? Double($0[c].count) : 0 }.max() ?? 3)
        }
        let sum = longest.reduce(0, +)
        let widths = longest.map { ($0 / sum * frame.width).rounded() }
        var out: [Element] = []
        var y = frame.minY
        for (r, row) in rows.enumerated() {
            var x = frame.minX
            // The row is as tall as its tallest cell.
            var texts: [Element] = []
            for c in 0..<columns {
                let cellText = c < row.count ? row[c] : ""
                var t = Element.text(cellText, fontSize: size, w: max(widths[c] - 2 * pad, size))
                t.align = "left"
                t.fontWeight = r == 0 ? 700 : 400
                t.color = r == 0 ? ColorTheory.readableInk(on: accent) : ink
                t.x = (x + pad).rounded()
                t.h = FontLibrary.layoutHeight(for: t)
                texts.append(t)
                x += widths[c]
            }
            let rowH = ((texts.map(\.h).max() ?? size) + 2 * pad).rounded()
            x = frame.minX
            for c in 0..<columns {
                var cell = Element.shape("rect", w: widths[c], h: rowH)
                cell.x = x.rounded(); cell.y = y.rounded()
                cell.fill = .solid(r == 0 ? accent : (r % 2 == 0 ? band : "#ffffff"))
                cell.stroke = "#00000022"
                cell.strokeWidth = 1
                cell.radius = 0
                out.append(cell)
                x += widths[c]
            }
            for var t in texts {
                t.y = (y + pad).rounded()
                out.append(t)
            }
            y += rowH
        }
        return out.map { var e = $0; e.group = group; return e }
    }
}
