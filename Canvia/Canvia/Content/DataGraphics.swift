// Charts and tables built from typed data, as ordinary elements.
//
// Not a new element kind: a bar chart is rectangles and labels, a pie is
// path shapes, a table is cells and text — all things the editor already
// moves, recolours, exports and reads aloud. The data comes in as lines of
// "Label, value" — or a header row and a value per series; the result is a
// group that behaves like anything else on the page. A chart's elements each
// carry the chart they make up (Element.chart), so it can be drawn again
// from its data with Edit chart.

import Foundation

enum DataGraphics {

    struct Series: Equatable {
        var label: String
        var value: Double
    }

    /// Chart data as typed: a row per item, a value per series in each.
    struct ChartData: Equatable {
        /// One per series: the header's names, "Series <n>" for any it lacks.
        var names: [String]
        var rows: [Row]

        struct Row: Equatable {
            var label: String
            var values: [Double]
        }
    }

    /// The first series of `parseChart`, item by item: "Label, value" per
    /// line; a line with no number is skipped, a line with only a number
    /// gets a numbered label.
    static func parse(_ text: String) -> [Series] {
        parseChart(text).rows.map { Series(label: $0.label, value: $0.values.first ?? 0) }
    }

    /// Chart data from typed lines, by the same rules as the Android twin's
    /// (the test vectors are shared):
    /// - cells are split at commas and trimmed; blank lines are skipped, and
    ///   empty cells at the end of a line — a trailing comma — are dropped;
    /// - the first line that is not blank is a header when it has cells after
    ///   the first and none of them is a number: "Quarter, North, South"
    ///   names two series;
    /// - every other line is a row: its first cell the label ("Item <line>"
    ///   when empty, or when the line is a lone number), the rest its values;
    /// - a value cell that is not a number reads as 0, and a line with no
    ///   number at all is skipped; a "%" is ignored and below zero reads 0;
    /// - every row has a value for every series, 0 where it has none.
    static func parseChart(_ text: String) -> ChartData {
        var header: [String] = []
        var rows: [ChartData.Row] = []
        var first = true
        for (n, line) in text.components(separatedBy: .newlines).enumerated() {
            var cells = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            while cells.count > 1, cells.last?.isEmpty == true { cells.removeLast() }
            guard cells.contains(where: { !$0.isEmpty }) else { continue }
            defer { first = false }
            if first, cells.count > 1, !cells.dropFirst().contains(where: { number($0) != nil }) {
                header = Array(cells.dropFirst())
                continue
            }
            let numbers = (cells.count > 1 ? Array(cells.dropFirst()) : cells).map(number)
            guard numbers.contains(where: { $0 != nil }) else { continue }
            let label = cells.count > 1 && !cells[0].isEmpty ? cells[0] : "Item \(n + 1)"
            rows.append(ChartData.Row(label: label, values: numbers.map { max(0, $0 ?? 0) }))
        }
        let count = max(header.count, rows.map(\.values.count).max() ?? 0)
        let names = (0..<count).map { s in
            s < header.count && !header[s].isEmpty ? header[s] : "Series \(s + 1)"
        }
        for i in rows.indices where rows[i].values.count < count {
            rows[i].values += Array(repeating: 0, count: count - rows[i].values.count)
        }
        return ChartData(names: names, rows: rows)
    }

    /// A cell as a number: "65%" is 65; words, blanks and infinities are none.
    private static func number(_ cell: String) -> Double? {
        guard let value = Double(cell.replacingOccurrences(of: "%", with: "")), value.isFinite else { return nil }
        return value
    }

    /// What the chart typed so far comes to, under the box it is typed in.
    static func chartSummary(_ data: ChartData) -> String {
        let n = data.rows.count
        guard n > 0 else { return "No numbers found yet." }
        let palette = " — coloured from the document's palette."
        if data.names.count > 1 {
            return (n == 1 ? "1 row" : "\(n) rows") + " × \(data.names.count) series" + palette
        }
        return (n == 1 ? "1 value" : "\(n) values") + palette
    }

    /// Raw values are the `kind` written in a chart's JSON.
    enum ChartKind: String, CaseIterable, Identifiable {
        case column, bar, line, pie, donut, stackedColumn, stackedBar, area, progressRing, progressBar
        var id: String { rawValue }
        var name: String {
            switch self {
            case .column: return "Column"
            case .bar: return "Bar"
            case .line: return "Line"
            case .pie: return "Pie"
            case .donut: return "Donut"
            case .stackedColumn: return "Stacked column"
            case .stackedBar: return "Stacked bar"
            case .area: return "Area"
            case .progressRing: return "Progress ring"
            case .progressBar: return "Progress bar"
            }
        }

        /// Drawn against a scale, so gridlines have something to mark.
        var hasScale: Bool {
            switch self {
            case .column, .bar, .line, .stackedColumn, .stackedBar, .area: return true
            case .pie, .donut, .progressRing, .progressBar: return false
            }
        }

        /// One value read as a percentage, written in the chart itself.
        var isProgress: Bool { self == .progressRing || self == .progressBar }
    }

    /// The colours a chart or a table is drawn in: the design's own, counted
    /// across every page — less the ones that would not show on this page
    /// (its background, and anything near it) and the faint ones, such as a
    /// table's hairlines — else the first palette, as far as it shows. The
    /// Android twin's `paletteFor`, so the same data comes out in the same
    /// colours on both phones.
    static func palette(for design: Design, page: Page) -> [String] {
        let background = backgroundColors(of: page).compactMap(rgb)
        func shows(_ hex: String) -> Bool {
            guard let c = rgb(hex), !isFaint(hex) else { return false }
            return !background.contains { near($0, c) }
        }
        var own: [String] = []
        for hex in ColorTools.documentColors(design, limit: 24) where shows(hex) {
            let normal = normalised(hex)
            if !own.contains(normal) { own.append(normal) }
            if own.count == 8 { break }
        }
        if own.count >= 2 { return own }
        let first = ContentLibrary.palettes.first?.colors ?? ["#5a31f4"]
        let fallback = first.filter(shows)
        return fallback.isEmpty ? first : fallback
    }

    /// Label ink that reads on the page: near-black on a light background,
    /// white on a dark one.
    static func ink(for page: Page) -> String {
        let background = backgroundColors(of: page).compactMap(rgb)
        guard !background.isEmpty else { return "#1f2430" }
        var total: Double = 0
        for c in background {
            let r: Double = 0.299 * Double(c.r)
            let g: Double = 0.587 * Double(c.g)
            let b: Double = 0.114 * Double(c.b)
            total += (r + g + b) / 255
        }
        let average: Double = total / Double(background.count)
        return average > 0.62 ? "#1f2430" : "#ffffff"
    }

    private static func backgroundColors(of page: Page) -> [String] {
        switch page.background {
        case .color(let c): return [c]
        case .gradient(let p):
            if let stops = p.stops { return stops.map { $0.color } }
            if let color = p.color { return [color] }
            return []
        case .image: return []
        }
    }

    private static func rgb(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits.prefix(6), radix: 16) else { return nil }
        return (Int((value >> 16) & 0xff), Int((value >> 8) & 0xff), Int(value & 0xff))
    }

    /// Mostly see-through: an alpha, in the eighth and ninth digits, under half.
    private static func isFaint(_ hex: String) -> Bool {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 8, let alpha = UInt8(digits.suffix(2), radix: 16) else { return false }
        return alpha < 0x80
    }

    /// Alike enough that one drawn on the other would hardly show — the
    /// "redmean" distance, as the Android twin measures it.
    private static func near(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Bool {
        ColorTools.redmean(a, b) < 6000
    }

    private static func normalised(_ hex: String) -> String {
        guard let c = rgb(hex) else { return hex }
        return String(format: "#%02x%02x%02x", c.r, c.g, c.b)
    }

    /// The chart `spec` describes, filling `frame`, each element carrying the
    /// spec so Edit chart can find them all and draw them again. A kind this
    /// build does not know is drawn as columns. `colours` are the series
    /// colours of the chart drawn before, by series number, which win over
    /// the palette's.
    static func chart(_ spec: ChartSpec, in frame: CGRect, palette: [String],
                      ink: String = "#1f2430", colours: [Int: Paint] = [:]) -> [Element] {
        let kind = ChartKind(rawValue: spec.kind) ?? .column
        return chart(kind, data: parseChart(spec.data), in: frame, palette: palette, ink: ink,
                     legend: spec.legend, values: spec.values, gridlines: spec.gridlines, colours: colours)
            .map { var e = $0; e.chart = spec; return e }
    }

    /// One series, item by item, as a chart.
    static func chart(_ kind: ChartKind, series: [Series], in frame: CGRect,
                      palette: [String], ink: String = "#1f2430") -> [Element] {
        let rows = series.map { ChartData.Row(label: $0.label, values: [$0.value]) }
        return chart(kind, data: ChartData(names: ["Series 1"], rows: rows), in: frame, palette: palette, ink: ink)
    }

    /// Chart elements filling `frame`, grouped, coloured from `palette` in
    /// turn, labelled in `ink`, by the same maths as the Android twin's (the
    /// test vectors are shared). One colour per series; a single series, and a
    /// pie's slices, one per item, as charts here always were. The colour
    /// number is each mark's part, "series:<n>". Pies and progress kinds
    /// read the first series; progress kinds only its first value, as a
    /// percentage clamped to 0...100.
    ///
    /// The switches: a legend is a band along the top, a swatch and a name
    /// per colour; values are each number beside its mark (inside a stack's
    /// or a slice's); gridlines are five hairlines at 0, 25, 50, 75 and 100%
    /// of the scale, behind the marks, for the kinds that have one. A
    /// progress kind writes its own value, so takes only the legend.
    static func chart(_ kind: ChartKind, data: ChartData, in frame: CGRect, palette: [String],
                      ink: String = "#1f2430", legend: Bool = false, values: Bool = false,
                      gridlines: Bool = false, colours: [Int: Paint] = [:]) -> [Element] {
        let rows = data.rows
        guard !rows.isEmpty, frame.width > 0, frame.height > 0 else { return [] }
        let colors = palette.isEmpty ? ["#5a31f4"] : palette
        let group = UID.make("grp")
        let count = max(1, data.names.count)
        // A progress bar is a band, so its type follows the width alone: drawn
        // again into the band it left, it comes out the same size.
        let labelSize = kind == .progressBar
            ? max(10, (frame.width * 0.045).rounded())
            : max(10, (min(frame.width, frame.height) * 0.06).rounded())
        let byItem = kind == .pie || kind == .donut || (count == 1 && kind != .line && kind != .area)
        let showValues = values && !kind.isProgress
        let showGrid = gridlines && kind.hasScale
        let faint = ink + "22"
        // Behind to front: gridlines, marks, item labels, values, the legend.
        var grid: [Element] = [], marks: [Element] = [], labels: [Element] = []
        var numbers: [Element] = [], key: [Element] = []

        func paint(_ n: Int) -> Paint { colours[n] ?? .solid(colors[n % colors.count]) }
        func hex(_ n: Int) -> String { colours[n]?.primaryColor ?? colors[n % colors.count] }
        func value(_ row: ChartData.Row, _ s: Int) -> Double { s < row.values.count ? row.values[s] : 0 }
        func part(_ el: Element, _ name: String) -> Element {
            var e = el
            e.chartPart = name
            return e
        }
        func label(_ text: String, x: Double, y: Double, w: Double, align: String = "center") -> Element {
            var t = Element.text(text, fontSize: labelSize, w: max(w, labelSize * 2))
            t.align = align
            t.color = ink
            t.x = x; t.y = y
            t.h = FontLibrary.layoutHeight(for: t)
            return t
        }
        /// A hairline, `w` by `h`, at `x`, `y`.
        func hairline(x: Double, y: Double, w: Double, h: Double) -> Element {
            var g = Element.shape("rect", w: w.rounded(), h: h.rounded())
            g.x = x.rounded(); g.y = y.rounded()
            g.fill = .solid(faint)
            return part(g, "grid")
        }
        let fractions: [Double] = [0, 0.25, 0.5, 0.75, 1]
        // Each item's stack, for the stacked kinds' scale.
        let totals = rows.map { $0.values.reduce(0, +) }

        var area = frame
        if legend {
            var entries: [(name: String, n: Int)] = []
            if kind.isProgress {
                entries = [(name: rows[0].label, n: 0)]
            } else if byItem {
                for (i, row) in rows.enumerated() { entries.append((name: row.label, n: i)) }
            } else {
                for s in 0..<count { entries.append((name: s < data.names.count ? data.names[s] : "Series \(s + 1)", n: s)) }
            }
            let band = labelSize * 1.6
            let slot = frame.width / Double(max(1, entries.count))
            let swatch = (labelSize * 0.8).rounded()
            for (k, entry) in entries.enumerated() {
                let left = frame.minX + slot * Double(k)
                var sw = Element.shape("rect", w: swatch, h: swatch)
                sw.x = left.rounded()
                sw.y = (frame.minY + (band - swatch) / 2).rounded()
                sw.fill = paint(entry.n)
                key.append(part(sw, "legend"))
                key.append(part(label(entry.name, x: left + swatch * 1.4, y: frame.minY + (band - labelSize * 1.25) / 2,
                                      w: slot - swatch * 1.4, align: "left"), "legend"))
            }
            area = CGRect(x: frame.minX, y: frame.minY + band, width: frame.width, height: max(1, frame.height - band))
        }

        switch kind {
        case .column, .stackedColumn:
            let stacked = kind == .stackedColumn
            let labelH = labelSize * 1.6
            // Room above the tallest column for its number; a stack's sit inside it.
            let valueH = showValues && !stacked ? labelSize * 1.4 : 0
            let plotTop = area.minY + valueH
            let plotH = max(1, area.height - labelH - valueH)
            let plotBottom = plotTop + plotH
            if showGrid {
                for f in fractions { grid.append(hairline(x: area.minX, y: plotBottom - plotH * f, w: area.width, h: 1)) }
            }
            let slot = area.width / Double(rows.count)
            let groupW = slot * 0.64
            let barW = stacked ? groupW : groupW / Double(count)
            let peak = (stacked ? totals : rows.flatMap(\.values)).max() ?? 0
            for (i, row) in rows.enumerated() {
                let left = area.minX + slot * Double(i) + (slot - groupW) / 2
                var base = 0.0
                for s in 0..<count {
                    let v = value(row, s)
                    let n = byItem ? i : s
                    var bar: Element
                    if stacked {
                        guard v > 0, peak > 0 else { continue }
                        let top = (plotBottom - plotH * (base + v) / peak).rounded()
                        let bottom = (plotBottom - plotH * base / peak).rounded()
                        base += v
                        bar = Element.shape("rect", w: barW.rounded(), h: max(1, bottom - top))
                        bar.x = left.rounded(); bar.y = top
                    } else {
                        let h = peak > 0 ? plotH * v / peak : 0
                        bar = Element.shape("rect", w: barW.rounded(), h: max(1, h.rounded()))
                        bar.x = (left + barW * Double(s)).rounded()
                        bar.y = (plotBottom - h).rounded()
                    }
                    bar.fill = paint(n)
                    marks.append(part(bar, "series:\(n)"))
                    if showValues {
                        let w = max(bar.w, labelSize * 3)
                        var t = label(num(v), x: bar.x + bar.w / 2 - w / 2,
                                      y: stacked ? bar.y + (bar.h - labelSize * 1.25) / 2 : bar.y - labelSize * 1.35, w: w)
                        if stacked { t.color = ColorTheory.readableInk(on: hex(n)) }
                        numbers.append(part(t, "value"))
                    }
                }
                labels.append(part(label(row.label, x: area.minX + slot * Double(i), y: plotBottom + labelSize * 0.3, w: slot), "label"))
            }
        case .bar, .stackedBar:
            let stacked = kind == .stackedBar
            let labelW = min(area.width * 0.28, labelSize * 9)
            let valueW = showValues && !stacked ? labelSize * 3.5 : 0
            let plotLeft = area.minX + labelW
            let plotW = max(1, area.width - labelW - valueW)
            if showGrid {
                for f in fractions { grid.append(hairline(x: plotLeft + plotW * f, y: area.minY, w: 1, h: area.height)) }
            }
            let slot = area.height / Double(rows.count)
            let groupH = slot * 0.64
            let barH = stacked ? groupH : groupH / Double(count)
            let peak = (stacked ? totals : rows.flatMap(\.values)).max() ?? 0
            for (i, row) in rows.enumerated() {
                let top = (area.minY + slot * Double(i) + (slot - groupH) / 2).rounded()
                var base = 0.0
                for s in 0..<count {
                    let v = value(row, s)
                    let n = byItem ? i : s
                    var bar: Element
                    if stacked {
                        guard v > 0, peak > 0 else { continue }
                        let start = (plotLeft + plotW * base / peak).rounded()
                        let end = (plotLeft + plotW * (base + v) / peak).rounded()
                        base += v
                        bar = Element.shape("rect", w: max(1, end - start), h: barH.rounded())
                        bar.x = start; bar.y = top
                    } else {
                        let w = peak > 0 ? plotW * v / peak : 0
                        bar = Element.shape("rect", w: max(1, w.rounded()), h: barH.rounded())
                        bar.x = plotLeft.rounded()
                        bar.y = (top + barH * Double(s)).rounded()
                    }
                    bar.fill = paint(n)
                    marks.append(part(bar, "series:\(n)"))
                    if showValues {
                        let y = bar.y + (bar.h - labelSize * 1.25) / 2
                        if stacked {
                            let w = max(bar.w, labelSize * 2)
                            var t = label(num(v), x: bar.x + bar.w / 2 - w / 2, y: y, w: w)
                            t.color = ColorTheory.readableInk(on: hex(n))
                            numbers.append(part(t, "value"))
                        } else {
                            numbers.append(part(label(num(v), x: bar.x + bar.w + labelSize * 0.3, y: y,
                                                      w: valueW - labelSize * 0.3, align: "left"), "value"))
                        }
                    }
                }
                labels.append(part(label(row.label, x: area.minX, y: top + (groupH - labelSize * 1.25) / 2,
                                         w: labelW - labelSize * 0.5, align: "right"), "label"))
            }
        case .line, .area:
            let labelH = labelSize * 1.6
            let valueH = showValues ? labelSize * 1.4 : 0
            let plotTop = area.minY + valueH
            let plotH = max(1, area.height - labelH - valueH)
            if showGrid {
                for f in fractions { grid.append(hairline(x: area.minX, y: plotTop + plotH * (1 - f), w: area.width, h: 1)) }
            }
            // Each point over the middle of its label's slot, so the first and
            // last labels stay inside the frame and the chart, drawn again
            // into the frame it left, comes out the same.
            let slot = area.width / Double(rows.count)
            let inset = rows.count > 1 ? slot / 2 : 0
            let plotLeft = area.minX + inset
            let plotW = max(1, area.width - 2 * inset)
            let n = max(rows.count - 1, 1)
            let peak = rows.flatMap(\.values).max() ?? 0
            for s in 0..<count {
                let points = rows.enumerated().map { i, row in
                    CGPoint(x: Double(i) / Double(n) * 100, y: 100 - (peak > 0 ? value(row, s) / peak * 100 : 0))
                }
                var mark = Element.shape("rect", w: plotW.rounded(), h: plotH.rounded())
                mark.x = plotLeft.rounded(); mark.y = plotTop.rounded()
                if kind == .area {
                    let ends = [CGPoint(x: points.first?.x ?? 0, y: 100), CGPoint(x: points.last?.x ?? 100, y: 100)]
                    mark.pathData = polyline([ends[0]] + points + [ends[1]]) + " Z"
                    mark.fill = paint(s)
                    // Several areas overlap: each lets the ones behind show.
                    if count > 1 { mark.opacity = 0.75 }
                } else {
                    mark.pathData = polyline(points)
                    mark.fill = .solid("#00000000")
                    mark.stroke = hex(s)
                    mark.strokeWidth = max(2, (plotH * 0.02).rounded())
                }
                marks.append(part(mark, "series:\(s)"))
                if showValues {
                    for (i, row) in rows.enumerated() {
                        let w = labelSize * 3
                        let x = plotLeft + Double(i) / Double(n) * plotW
                        let y = plotTop + plotH * (peak > 0 ? 1 - value(row, s) / peak : 1)
                        numbers.append(part(label(num(value(row, s)), x: x - w / 2, y: y - labelSize * 1.4, w: w), "value"))
                    }
                }
            }
            for (i, row) in rows.enumerated() {
                let x = plotLeft + Double(i) / Double(n) * plotW
                labels.append(part(label(row.label, x: x - slot / 2, y: plotTop + plotH + labelSize * 0.3, w: slot), "label"))
            }
        case .pie, .donut:
            let total = rows.reduce(0.0) { $0 + value($1, 0) }
            let side = min(area.width, area.height)
            let box = CGRect(x: area.midX - side / 2, y: area.midY - side / 2, width: side, height: side)
            let inner = kind == .donut ? 0.55 : 0
            var start = -Double.pi / 2
            for (i, row) in rows.enumerated() where total > 0 && value(row, 0) > 0 {
                let v = value(row, 0)
                let sweep = 2 * .pi * v / total
                var slice = Element.shape("rect", w: side.rounded(), h: side.rounded())
                slice.x = box.minX.rounded(); slice.y = box.minY.rounded()
                slice.pathData = wedge(from: start, sweep: sweep, inner: inner)
                slice.fill = paint(i)
                slice.altText = "\(row.label): \(Int((v / total * 100).rounded()))%"
                marks.append(part(slice, "series:\(i)"))
                if showValues {
                    let middle = start + sweep / 2
                    let reach = side / 2 * (inner > 0 ? (1 + inner) / 2 : 0.62)
                    let w = labelSize * 3
                    var t = label(num(v), x: box.midX + reach * cos(middle) - w / 2,
                                  y: box.midY + reach * sin(middle) - labelSize * 0.625, w: w)
                    t.color = ColorTheory.readableInk(on: hex(i))
                    numbers.append(part(t, "value"))
                }
                start += sweep
            }
        case .progressRing, .progressBar:
            let percent = min(100, max(0, value(rows[0], 0)))
            let words = "\(Int(percent.rounded()))%"
            if kind == .progressRing {
                let side = min(area.width, area.height)
                let box = CGRect(x: area.midX - side / 2, y: area.midY - side / 2, width: side, height: side)
                var track = Element.shape("rect", w: side.rounded(), h: side.rounded())
                track.x = box.minX.rounded(); track.y = box.minY.rounded()
                track.pathData = wedge(from: -Double.pi / 2, sweep: 2 * .pi, inner: 0.75)
                track.fill = .solid(faint)
                marks.append(part(track, "axis"))
                if percent > 0 {
                    var done = Element.shape("rect", w: side.rounded(), h: side.rounded())
                    done.x = track.x; done.y = track.y
                    done.pathData = wedge(from: -Double.pi / 2, sweep: 2 * .pi * percent / 100, inner: 0.75)
                    done.fill = paint(0)
                    marks.append(part(done, "series:0"))
                }
                var t = Element.text(words, fontSize: max(10, (side * 0.2).rounded()), w: (side * 0.7).rounded())
                t.color = ink
                t.fontWeight = 700
                t.h = FontLibrary.layoutHeight(for: t)
                t.x = (box.midX - t.w / 2).rounded(); t.y = (box.midY - t.h / 2).rounded()
                numbers.append(part(t, "value"))
            } else {
                let barH = min(area.height, labelSize * 1.6)
                let textW = labelSize * 3.5
                let trackW = max(1, area.width - textW)
                let top = (area.midY - barH / 2).rounded()
                var track = Element.shape("rect", w: trackW.rounded(), h: barH.rounded())
                track.x = area.minX.rounded(); track.y = top
                track.radius = (barH / 2).rounded()
                track.fill = .solid(faint)
                marks.append(part(track, "axis"))
                if percent > 0 {
                    var done = Element.shape("rect", w: max(1, (trackW * percent / 100).rounded()), h: barH.rounded())
                    done.x = track.x; done.y = top
                    done.radius = track.radius
                    done.fill = paint(0)
                    marks.append(part(done, "series:0"))
                }
                var t = label(words, x: area.minX + trackW + labelSize * 0.4, y: area.midY - labelSize * 0.625,
                              w: textW - labelSize * 0.4, align: "left")
                t.fontWeight = 700
                t.h = FontLibrary.layoutHeight(for: t)
                numbers.append(part(t, "value"))
            }
        }
        return (grid + marks + labels + numbers + key).map { var e = $0; e.group = group; return e }
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
    /// What the table typed so far comes to, under the box it is typed in:
    /// "3 rows × 4 columns; the first row is the header." — the widest row
    /// counting — with "row" and "column" singular when there is one, as
    /// the Android twin says it.
    static func tableSummary(_ rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "Nothing to tabulate yet." }
        let columns = rows.map(\.count).max() ?? 0
        let r = rows.count == 1 ? "1 row" : "\(rows.count) rows"
        let c = columns == 1 ? "1 column" : "\(columns) columns"
        return "\(r) × \(c); the first row is the header."
    }

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
