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
    /// - blank lines are skipped, and a line's trailing commas ignored;
    /// - the first line that is not blank is a header when it has cells
    ///   after the first, words and no numbers: "Quarter, North, South"
    ///   names two series; a blank name is "Series <n>";
    /// - one series — no header, or a header naming one — is read as it
    ///   always was: split at the first comma only, a line with no number is
    ///   skipped, one with only a number gets a numbered label ("Item <line>");
    /// - several series: cells split at every comma; a value cell that is not
    ///   a number, or is missing, reads as 0, a row with no number among its
    ///   values is skipped, and cells past the last series are ignored;
    /// - a "%" is ignored and below zero reads 0; with no header the one
    ///   series is "Series 1".
    static func parseChart(_ text: String) -> ChartData {
        let lines = text.components(separatedBy: .newlines).map(withoutTrailingCommas)
        let first = lines.firstIndex { !$0.isEmpty }
        let header = first.flatMap { headerNames(lines[$0]) }
        guard let names = header, names.count > 1 else {
            let rows = lines.enumerated().compactMap { n, line in
                header != nil && n == first ? nil : single(n, line)
            }
            return ChartData(names: [header?.first ?? "Series 1"], rows: rows)
        }
        let rows = lines.enumerated().compactMap { n, line in
            n <= (first ?? -1) ? nil : multiple(n, line, count: names.count)
        }
        return ChartData(names: names, rows: rows)
    }

    private static func withoutTrailingCommas(_ line: String) -> String {
        var s = line
        while let c = s.unicodeScalars.last, c == "," || CharacterSet.whitespaces.contains(c) {
            s.unicodeScalars.removeLast()
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// The series' names when `line` is a header: some cell after the first
    /// has words in it and none is a number.
    private static func headerNames(_ line: String) -> [String]? {
        let after = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.dropFirst()
        if after.allSatisfy(\.isEmpty) || after.contains(where: { number($0) != nil }) { return nil }
        return after.enumerated().map { i, name in name.isEmpty ? "Series \(i + 1)" : name }
    }

    private static func single(_ n: Int, _ line: String) -> ChartData.Row? {
        let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, let value = number(last) else { return nil }
        let label = parts.count > 1 && !parts[0].isEmpty ? parts[0] : "Item \(n + 1)"
        return ChartData.Row(label: label, values: [max(0, value)])
    }

    private static func multiple(_ n: Int, _ line: String, count: Int) -> ChartData.Row? {
        let cells = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let read = (1...count).map { $0 < cells.count ? number(cells[$0]) : nil }
        guard read.contains(where: { $0 != nil }) else { return nil }
        return ChartData.Row(label: cells[0].isEmpty ? "Item \(n + 1)" : cells[0], values: read.map { max(0, $0 ?? 0) })
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
    /// spec so Edit chart can find them all and draw them again; nothing for
    /// a kind this build does not know. `colours` are the series colours of
    /// the chart drawn before, by series number, which win over the
    /// palette's; `group` the group it is drawn into.
    static func chart(_ spec: ChartSpec, in frame: CGRect, palette: [String],
                      ink: String = "#1f2430", colours: [Int: Paint] = [:], group: String = UID.make("grp"),
                      heightFor: @escaping (Element) -> Double = FontLibrary.layoutHeight(for:)) -> [Element] {
        guard let kind = ChartKind(rawValue: spec.kind) else { return [] }
        return chart(kind, data: parseChart(spec.data), in: frame, palette: palette, ink: ink,
                     legend: spec.legend, values: spec.values, gridlines: spec.gridlines,
                     colours: colours, group: group, heightFor: heightFor)
            .map { var e = $0; e.chart = spec; return e }
    }

    /// One series, item by item, as a chart.
    static func chart(_ kind: ChartKind, series: [Series], in frame: CGRect,
                      palette: [String], ink: String = "#1f2430") -> [Element] {
        let rows = series.map { ChartData.Row(label: $0.label, values: [$0.value]) }
        return chart(kind, data: ChartData(names: ["Series 1"], rows: rows), in: frame, palette: palette, ink: ink)
    }

    /// Chart elements filling `frame`, grouped, coloured from `palette` in
    /// turn, labelled in `ink`, by the same maths as the Android twin's
    /// `chart` (the test vectors are shared); `heightFor` measures a label's
    /// box. Colour n — a series, or an item where each item has its own (one
    /// series of columns or bars, and every pie) — is `colours[n]` when
    /// given, else the palette's, and is the mark's part, "series:<n>".
    ///
    /// A legend takes a row along the bottom, value labels room above the
    /// columns or beside the bars (a stack's total, a slice's share), and
    /// gridlines go behind, at quarters. With all three off and one series,
    /// the five first kinds are exactly what they always were. Progress
    /// kinds read the first value, clamped to 0...100, and write it
    /// themselves, with no legend.
    static func chart(_ kind: ChartKind, data: ChartData, in frame: CGRect, palette: [String],
                      ink: String = "#1f2430", legend: Bool = false, values: Bool = false,
                      gridlines: Bool = false, colours: [Int: Paint] = [:], group: String = UID.make("grp"),
                      heightFor: @escaping (Element) -> Double = FontLibrary.layoutHeight(for:)) -> [Element] {
        let rows = data.rows
        guard !rows.isEmpty, frame.width > 0, frame.height > 0 else { return [] }
        let colors = palette.isEmpty ? ["#5a31f4"] : palette
        let count = max(1, data.names.count)
        var out: [Element] = []
        let labelSize: Double = max(10, (min(frame.width, frame.height) * 0.06).rounded())
        let firsts = rows.map { $0.values.first ?? 0 }
        let total = firsts.reduce(0, +)
        let peak = rows.map { $0.values.max() ?? 0 }.max() ?? 0
        if (kind == .pie || kind == .donut) && total <= 0 { return [] }
        // Each item its own colour, rather than each series.
        let byItem = kind == .pie || kind == .donut || (count == 1 && (kind == .column || kind == .bar))
        let faint = normalised(ink)
        let legendH = legend && !kind.isProgress ? labelSize * 1.6 : 0
        let plot = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - legendH)

        func paint(_ n: Int) -> Paint { colours[n] ?? .solid(colors[n % colors.count]) }
        func hex(_ n: Int) -> String { colours[n]?.primaryColor ?? colors[n % colors.count] }
        func value(_ row: ChartData.Row, _ s: Int) -> Double { s < row.values.count ? row.values[s] : 0 }
        func part(_ el: Element, _ name: String) -> Element {
            var e = el
            e.chartPart = name
            return e
        }
        func label(_ text: String, x: Double, y: Double, w: Double, align: String = "center",
                   part name: String = "label") -> Element {
            var t = Element.text(text, fontSize: labelSize, w: max(w, labelSize * 2))
            t.align = align
            t.color = ink
            t.x = x; t.y = y
            t.h = heightFor(t)
            return part(t, name)
        }
        /// A value's label centred on `cx`, its foot at `foot`.
        func valueAbove(_ v: Double, cx: Double, foot: Double, w: Double) -> Element {
            var t = label(num(v), x: 0, y: 0, w: max(w, labelSize * 3), part: "value")
            t.x = cx - t.w / 2
            t.y = foot - labelSize * 0.3 - t.h
            return t
        }
        func bar(w: Double, h: Double, x: Double, y: Double, fill: Paint) -> Element {
            var b = Element.shape("rect", w: w, h: h)
            b.x = x; b.y = y
            b.fill = fill
            return b
        }
        func gridAcross(top: Double, plotH: Double) {
            guard gridlines else { return }
            for g in 0...4 {
                out.append(part(bar(w: plot.width.rounded(), h: 1, x: plot.minX.rounded(),
                                    y: (top + plotH * Double(g) / 4).rounded(), fill: .solid(faint + "33")), "grid"))
            }
        }
        func gridDown(left: Double, plotW: Double) {
            guard gridlines else { return }
            for g in 0...4 {
                out.append(part(bar(w: 1, h: plot.height.rounded(), x: (left + plotW * Double(g) / 4).rounded(),
                                    y: plot.minY.rounded(), fill: .solid(faint + "33")), "grid"))
            }
        }
        func shape(_ path: String, x: Double, y: Double, w: Double, h: Double, fill: Paint) -> Element {
            var s = bar(w: w.rounded(), h: h.rounded(), x: x.rounded(), y: y.rounded(), fill: fill)
            s.pathData = path
            return s
        }

        switch kind {
        case .column, .stackedColumn:
            let stacked = kind == .stackedColumn
            let labelH: Double = labelSize * 1.6
            let valueH: Double = values ? labelH : 0
            let top: Double = plot.minY + valueH
            let plotH: Double = plot.height - labelH - valueH
            let base: Double = top + plotH
            let slot: Double = plot.width / Double(rows.count)
            let barW: Double = slot * 0.64
            let tallest = stacked ? (rows.map { $0.values.reduce(0, +) }.max() ?? 0) : peak
            gridAcross(top: top, plotH: plotH)
            for (i, row) in rows.enumerated() {
                let left: Double = plot.minX + slot * Double(i) + (slot - barW) / 2
                if stacked {
                    var below = 0.0
                    for (j, v) in row.values.enumerated() where v > 0 && tallest > 0 {
                        let y0 = (base - plotH * (below + v) / tallest).rounded()
                        let y1 = (base - plotH * below / tallest).rounded()
                        out.append(part(bar(w: barW.rounded(), h: y1 - y0, x: left.rounded(), y: y0, fill: paint(j)), "series:\(j)"))
                        below += v
                    }
                    let sum = row.values.reduce(0, +)
                    if values {
                        out.append(valueAbove(sum, cx: left + barW / 2, foot: base - (tallest > 0 ? plotH * sum / tallest : 0), w: barW))
                    }
                } else {
                    let w = barW / Double(count)
                    for s in 0..<count {
                        let v = value(row, s)
                        let h = peak > 0 ? plotH * v / peak : 0
                        let x = left + w * Double(s)
                        let n = byItem ? i : s
                        out.append(part(bar(w: w.rounded(), h: max(1, h.rounded()), x: x.rounded(), y: (base - h).rounded(),
                                            fill: paint(n)), "series:\(n)"))
                        if values { out.append(valueAbove(v, cx: x + w / 2, foot: base - h, w: w)) }
                    }
                }
                out.append(label(row.label, x: plot.minX + slot * Double(i), y: base + labelSize * 0.3, w: slot))
            }
        case .bar, .stackedBar:
            let stacked = kind == .stackedBar
            let labelW: Double = min(plot.width * 0.28, labelSize * 9)
            let valueW: Double = values ? labelSize * 4 : 0
            let plotW: Double = plot.width - labelW - valueW
            let left: Double = plot.minX + labelW
            let slot: Double = plot.height / Double(rows.count)
            let barH: Double = slot * 0.64
            let longest = stacked ? (rows.map { $0.values.reduce(0, +) }.max() ?? 0) : peak
            gridDown(left: left, plotW: plotW)
            func valueBeside(_ v: Double, end: Double, y: Double, h: Double) -> Element {
                var t = label(num(v), x: end + labelSize * 0.3, y: 0, w: valueW - labelSize * 0.3, align: "left", part: "value")
                t.y = y + (h - t.h) / 2
                return t
            }
            for (i, row) in rows.enumerated() {
                let top: Double = (plot.minY + slot * Double(i) + (slot - barH) / 2).rounded()
                if stacked {
                    var before = 0.0
                    for (j, v) in row.values.enumerated() where v > 0 && longest > 0 {
                        let x0 = (left + plotW * before / longest).rounded()
                        let x1 = (left + plotW * (before + v) / longest).rounded()
                        out.append(part(bar(w: x1 - x0, h: barH.rounded(), x: x0, y: top, fill: paint(j)), "series:\(j)"))
                        before += v
                    }
                    let sum = row.values.reduce(0, +)
                    if values {
                        out.append(valueBeside(sum, end: left + (longest > 0 ? plotW * sum / longest : 0), y: top, h: barH.rounded()))
                    }
                } else {
                    let h = barH / Double(count)
                    for s in 0..<count {
                        let v = value(row, s)
                        let w = peak > 0 ? plotW * v / peak : 0
                        let n = byItem ? i : s
                        let b = bar(w: max(1, w.rounded()), h: h.rounded(), x: left.rounded(),
                                    y: (plot.minY + slot * Double(i) + (slot - barH) / 2 + h * Double(s)).rounded(), fill: paint(n))
                        out.append(part(b, "series:\(n)"))
                        if values { out.append(valueBeside(v, end: b.x + b.w, y: b.y, h: b.h)) }
                    }
                }
                out.append(label(row.label, x: plot.minX, y: top + (barH - labelSize * 1.25) / 2, w: labelW - labelSize * 0.5, align: "right"))
            }
        case .pie, .donut:
            let side: Double = min(plot.width, plot.height)
            let left: Double = plot.midX - side / 2
            let top: Double = plot.midY - side / 2
            let inner = kind == .donut ? 0.55 : 0
            var start = -Double.pi / 2
            for (i, v) in firsts.enumerated() where v > 0 {
                let sweep = 2 * .pi * v / total
                let share = "\(Int((v / total * 100).rounded()))%"
                var slice = shape(wedge(from: start, sweep: sweep, inner: inner), x: left, y: top, w: side, h: side, fill: paint(i))
                slice.altText = "\(rows[i].label): \(share)"
                out.append(part(slice, "series:\(i)"))
                if values {
                    // Halfway across the slice, in ink that reads on it.
                    let middle = start + sweep / 2
                    let reach = side / 2 * (inner > 0 ? (1 + inner) / 2 : 0.62)
                    var t = label(share, x: 0, y: 0, w: labelSize * 3, part: "value")
                    t.x = plot.midX + reach * cos(middle) - t.w / 2
                    t.y = plot.midY + reach * sin(middle) - t.h / 2
                    t.color = ColorTheory.readableInk(on: hex(i))
                    out.append(t)
                }
                start += sweep
            }
        case .line, .area:
            let labelH: Double = labelSize * 1.6
            let valueH: Double = values ? labelH : 0
            let top: Double = plot.minY + valueH
            let plotH: Double = plot.height - labelH - valueH
            let n = max(rows.count - 1, 1)
            gridAcross(top: top, plotH: plotH)
            for s in 0..<count {
                let points = rows.enumerated().map { i, row in
                    CGPoint(x: Double(i) / Double(n) * 100, y: 100 - (peak > 0 ? value(row, s) / peak * 100 : 0))
                }
                var mark: Element
                if kind == .line {
                    mark = shape(polyline(points), x: plot.minX, y: top, w: plot.width, h: plotH, fill: .solid("#00000000"))
                    mark.stroke = hex(s)
                    mark.strokeWidth = max(2, (plotH * 0.02).rounded())
                } else {
                    mark = shape(polyline(points) + " L100 100 L0 100 Z", x: plot.minX, y: top, w: plot.width, h: plotH, fill: paint(s))
                    // Several areas overlap, so each lets the others show.
                    mark.opacity = count > 1 ? 0.7 : 1
                }
                out.append(part(mark, "series:\(s)"))
                if values {
                    for (i, row) in rows.enumerated() {
                        let v = value(row, s)
                        out.append(valueAbove(v, cx: plot.minX + Double(i) / Double(n) * plot.width,
                                              foot: top + plotH - (peak > 0 ? plotH * v / peak : 0), w: 0))
                    }
                }
            }
            let slot: Double = plot.width / Double(rows.count)
            for (i, row) in rows.enumerated() {
                out.append(label(row.label, x: plot.minX + Double(i) / Double(n) * plot.width - slot / 2,
                                 y: top + plotH + labelSize * 0.3, w: slot))
            }
        case .progressRing:
            let percent = min(100, max(0, firsts[0]))
            let side: Double = min(frame.width, frame.height)
            let left: Double = frame.midX - side / 2
            let top: Double = frame.midY - side / 2
            out.append(part(shape(wedge(from: -Double.pi / 2, sweep: 2 * .pi, inner: 0.8),
                                  x: left, y: top, w: side, h: side, fill: .solid(faint + "22")), "axis"))
            if percent > 0 {
                out.append(part(shape(wedge(from: -Double.pi / 2, sweep: 2 * .pi * percent / 100, inner: 0.8),
                                      x: left, y: top, w: side, h: side, fill: paint(0)), "series:0"))
            }
            var t = Element.text("\(Int(percent.rounded()))%", fontSize: max(10, (side * 0.2).rounded()), w: side.rounded())
            t.align = "center"
            t.fontWeight = 700
            t.color = ink
            t.x = left.rounded()
            t.h = heightFor(t)
            t.y = frame.midY - t.h / 2
            out.append(part(t, "value"))
        case .progressBar:
            let percent = min(100, max(0, firsts[0]))
            let labelW: Double = labelSize * 4
            let plotW: Double = frame.width - labelW
            let barH: Double = (labelSize * 1.6).rounded()
            let top: Double = (frame.midY - barH / 2).rounded()
            var track = bar(w: plotW.rounded(), h: barH, x: frame.minX.rounded(), y: top, fill: .solid(faint + "22"))
            track.radius = barH / 2
            out.append(part(track, "axis"))
            if percent > 0 {
                var done = bar(w: max(1, (plotW * percent / 100).rounded()), h: barH, x: frame.minX.rounded(), y: top, fill: paint(0))
                done.radius = barH / 2
                out.append(part(done, "series:0"))
            }
            var t = label("\(Int(percent.rounded()))%", x: frame.minX + plotW + labelSize * 0.5, y: 0,
                          w: labelW - labelSize * 0.5, align: "left", part: "value")
            t.y = frame.midY - t.h / 2
            out.append(t)
        }

        if legendH > 0 {
            // What each colour is: the items' labels where each item has its
            // own, else the series' names — a swatch and a word each, across.
            let names = byItem ? rows.map(\.label) : data.names
            let top: Double = frame.minY + frame.height - legendH
            let slot: Double = frame.width / Double(names.count)
            let swatch = (labelSize * 0.8).rounded()
            for (i, name) in names.enumerated() {
                let x = frame.minX + slot * Double(i)
                out.append(part(bar(w: swatch, h: swatch, x: x.rounded(), y: (top + (legendH - swatch) / 2).rounded(), fill: paint(i)), "legend"))
                var t = label(name, x: x + swatch * 1.5, y: 0, w: slot - swatch * 1.5, align: "left", part: "legend")
                t.y = top + (legendH - t.h) / 2
                out.append(t)
            }
        }
        return out.map { var e = $0; e.group = group; return e }
    }

    /// The frame to draw `spec`'s chart in so that its elements fill
    /// `bounds` — the chart's own elements' box — as they did: a chart does
    /// not fill its frame to the edge (bars stand back from it, labels are
    /// their text's height, a progress bar is as tall as its type), and
    /// drawn again into its own box it would shrink at every Update. Found
    /// by scaling the frame by what it fell short of, a few times over,
    /// since type grows with the frame — the Android twin's `frameFilling`.
    static func frameFilling(_ spec: ChartSpec, bounds: CGRect,
                             heightFor: @escaping (Element) -> Double = FontLibrary.layoutHeight(for:)) -> CGRect {
        var frame = bounds
        for _ in 0..<8 {
            let made = chart(spec, in: frame, palette: [], heightFor: heightFor)
            if made.isEmpty { return bounds }
            let reached = Geometry.union(made.map(\.frame))
            if reached.width <= 0 || reached.height <= 0 { return bounds }
            if abs(reached.minX - bounds.minX) < 0.5, abs(reached.minY - bounds.minY) < 0.5,
               abs(reached.width - bounds.width) < 0.5, abs(reached.height - bounds.height) < 0.5 { return frame }
            let w = frame.width * bounds.width / reached.width
            let h = frame.height * bounds.height / reached.height
            frame = CGRect(x: (bounds.minX - (reached.minX - frame.minX) / frame.width * w).rounded(),
                           y: (bounds.minY - (reached.minY - frame.minY) / frame.height * h).rounded(),
                           width: w.rounded(), height: h.rounded())
        }
        return frame
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
