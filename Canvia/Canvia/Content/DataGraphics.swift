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
    /// - blank lines are skipped; the first line that is not blank once its
    ///   trailing commas are ignored is a header when it has cells after the
    ///   first, words and no numbers: "Quarter, North, South" names two
    ///   series; a blank name is "Series <n>";
    /// - one series — no header, or a header naming one — reads each line
    ///   exactly as it always was: split at the first comma only, a line with
    ///   no number is skipped ("A, 5," too, "5," being no number, and several
    ///   numbers on a line without a header likewise), one with only a number
    ///   gets a numbered label ("Item <line>");
    /// - several series: cells split at every comma, a trailing comma being
    ///   nothing; a value cell that is not a number, or is missing, reads as
    ///   0, a row with no number among its values is skipped, and cells past
    ///   the last series are ignored;
    /// - a "%" is ignored and below zero reads 0; with no header the one
    ///   series is "Series 1".
    static func parseChart(_ text: String) -> ChartData {
        let raw = text.components(separatedBy: .newlines)
        let lines = raw.map(withoutTrailingCommas)
        let first = lines.firstIndex { !$0.isEmpty }
        let header = first.flatMap { headerNames(lines[$0]) }
        guard let names = header, names.count > 1 else {
            let rows = raw.enumerated().compactMap { n, line in
                header != nil && n == first ? nil : single(n, line)
            }
            return ChartData(names: [header?.first ?? "Series 1"], rows: rows)
        }
        let rows = lines.enumerated().compactMap { n, line in
            n <= (first ?? -1) ? nil : multiple(n, line, count: names.count)
        }
        return ChartData(names: names, rows: rows)
    }

    /// A scatter's rows, "Label, x, y": each row's cells after its label
    /// read in pairs, x then y, the nth pair a point of series n — the
    /// Android twin's rule (the test vectors are shared). Cells split at
    /// every comma, as with several series:
    /// - the header is the first line not blank once its trailing commas
    ///   are ignored, when a cell after the first has words in it and none a
    ///   number ("City, Size, Price"). It names x and y: each pair's y names
    ///   its series ("Price"), a blank one "Series <n>"; there are as many
    ///   series as it has whole pairs, at least one;
    /// - without one, there are as many series as the line with the most
    ///   cells has whole pairs after its label, at least one, "Series 1" on;
    /// - a cell that is not a number, or is missing, reads as 0; a row with
    ///   no number at all is skipped; below zero reads 0, as the scale starts
    ///   there; a blank label is "Item <line>".
    /// Each row's values are its points' x and y in turn: x0, y0, x1, y1…
    static func parseScatter(_ text: String) -> ChartData {
        parsePoints(text, width: 2)
    }

    /// A bubble chart's rows, "Label, x, y, size": read as parseScatter
    /// reads a scatter's, in threes rather than pairs — x, y and size, the
    /// nth three a bubble of series n, named by its y's header cell ("City,
    /// Size, Price, People" is one series, "Price"). Each row's values are
    /// x0, y0, size0, x1, y1, size1… The Android twin's `parseBubble`.
    static func parseBubble(_ text: String) -> ChartData {
        parsePoints(text, width: 3)
    }

    /// Rows of points `width` numbers each, as parseScatter reads them.
    private static func parsePoints(_ text: String, width: Int) -> ChartData {
        let lines = text.components(separatedBy: .newlines).map(withoutTrailingCommas)
        let first = lines.firstIndex { !$0.isEmpty }
        let header = first.flatMap { headerCells(lines[$0]) }
        let longest = lines.map { $0.isEmpty ? 0 : ($0.components(separatedBy: ",").count - 1) / width }.max() ?? 0
        let points = max(1, header.map { $0.count / width } ?? longest)
        let names = (0..<points).map { n -> String in
            guard let header, width * n + 1 < header.count, !header[width * n + 1].isEmpty else { return "Series \(n + 1)" }
            return header[width * n + 1]
        }
        let rows = lines.enumerated().compactMap { n, line in
            header != nil && n <= (first ?? -1) ? nil : multiple(n, line, count: width * points)
        }
        return ChartData(names: names, rows: rows)
    }

    /// Chart data as a chart of `kind` reads it: parseScatter's for a
    /// scatter, parseBubble's for a bubble chart, parseChart's for every
    /// other kind.
    static func chartData(_ text: String, kind: ChartKind) -> ChartData {
        switch kind {
        case .scatter: return parseScatter(text)
        case .bubble: return parseBubble(text)
        default: return parseChart(text)
        }
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
    static func headerNames(_ line: String) -> [String]? {
        headerCells(line)?.enumerated().map { i, name in name.isEmpty ? "Series \(i + 1)" : name }
    }

    /// The cells after the first, as they are, when `line` is a header.
    private static func headerCells(_ line: String) -> [String]? {
        let after = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.dropFirst()
        if after.allSatisfy(\.isEmpty) || after.contains(where: { number($0) != nil }) { return nil }
        return Array(after)
    }

    /// Whether `line` is a chart's header, as parseChart reads its first
    /// line: a cell after the first with words in it, and none a number.
    static func isHeader(_ line: String) -> Bool {
        headerNames(withoutTrailingCommas(line)) != nil
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

    /// A cell as a number: "65%" is 65; words, blanks and infinities are
    /// none. Beyond 1e300 either way it reads as 1e300, so no stack of them
    /// adds up to infinity.
    private static func number(_ cell: String) -> Double? {
        guard let value = Double(cell.replacingOccurrences(of: "%", with: "")), value.isFinite else { return nil }
        return min(max(value, -1e300), 1e300)
    }

    /// The hint under the chart's text, for a kind with rows to read.
    static let seriesHint = tr("A first line of names, as in \"Quarter, North, South\", makes a series of each column after the first.")

    /// The hint under a scatter's data.
    static let scatterHint = tr("Each row is \"Label, x, y\"; a first line of names, as in \"City, Size, Price\", names x and y.")

    /// The hint under a bubble chart's data.
    static let bubbleHint = tr("Each row is \"Label, x, y, size\"; a first line of names, as in \"City, Size, Price, People\", names them.")

    /// What the chart typed so far comes to, under the box it is typed in,
    /// in the Android twin's words: "4 values", "3 rows × 2 series", or for a
    /// progress kind the percentage it will show. A bubble chart counts its
    /// bubbles, "6 bubbles"; a funnel its stages, "4 stages, in the order
    /// typed."; a pictogram its rows, "3 rows of up to 10 icons."; a heat map
    /// its cells, "4 rows × 3 series, shaded by value.".
    static func chartSummary(_ data: ChartData, kind: ChartKind) -> String {
        let n = data.rows.count
        guard let first = data.rows.first?.values.first else { return tr("No numbers found yet.") }
        if kind.isProgress {
            return tr("The first value, as a percentage: %@.", "\(Int(min(100, max(0, first)).rounded()))%")
        }
        switch kind {
        case .bubble:
            return tr("%@, coloured from this page.", trn("%d bubble|%d bubbles", n * data.names.count))
        case .funnel:
            return tr("%@, in the order typed.", trn("%d stage|%d stages", n))
        case .pictogram:
            return tr("%@ of up to 10 icons.", trn("%d row|%d rows", n))
        case .heatmap:
            return tr("%@ × %@, shaded by value.", trn("%d row|%d rows", n), trn("%d series|%d series", data.names.count))
        default:
            break
        }
        if data.names.count > 1 {
            return tr("%@ × %@, coloured from this page.", trn("%d row|%d rows", n),
                      trn("%d series|%d series", data.names.count))
        }
        return tr("%@, coloured from this page.", trn("%d value|%d values", n))
    }

    /// Raw values are the `kind` written in a chart's JSON.
    enum ChartKind: String, CaseIterable, Identifiable {
        case column, bar, line, pie, donut, stackedColumn, stackedBar, area, progressRing, progressBar, scatter
        case radar, bubble, funnel, pictogram, heatmap, progressDial
        var id: String { rawValue }
        var name: String {
            switch self {
            case .column: return tr("Column")
            case .bar: return tr("Bar")
            case .line: return tr("Line")
            case .pie: return tr("Pie")
            case .donut: return tr("Donut")
            case .stackedColumn: return tr("Stacked column")
            case .stackedBar: return tr("Stacked bar")
            case .area: return tr("Area")
            case .progressRing: return tr("Progress ring")
            case .progressBar: return tr("Progress bar")
            case .scatter: return tr("Scatter")
            case .radar: return tr("Radar")
            case .bubble: return tr("Bubble")
            case .funnel: return tr("Funnel")
            case .pictogram: return tr("Pictogram")
            case .heatmap: return tr("Heat map")
            case .progressDial: return tr("Progress dial")
            }
        }

        /// Drawn against a scale, so gridlines have something to mark.
        var hasScale: Bool {
            switch self {
            case .column, .bar, .line, .stackedColumn, .stackedBar, .area, .scatter, .radar, .bubble: return true
            case .pie, .donut, .progressRing, .progressBar, .funnel, .pictogram, .heatmap, .progressDial: return false
            }
        }

        /// One value read as a percentage, written in the chart itself.
        var isProgress: Bool { self == .progressRing || self == .progressBar || self == .progressDial }

        /// Has a legend to show: not a progress kind, which reads one value,
        /// nor a heat map, whose shades are its key.
        var hasLegend: Bool { !isProgress && self != .heatmap }

        /// Has an x and a y axis to name (`xTitle`, `yTitle`): a kind with a
        /// scale, but a radar, whose scale runs out along every spoke.
        var hasAxisTitles: Bool { hasScale && self != .radar }

        /// Each row in its own colour whatever the series: a pie's slices, a
        /// funnel's stages, a pictogram's rows.
        var colourByRow: Bool { self == .pie || self == .donut || self == .funnel || self == .pictogram }

        /// Bars whose gap and far-end rounding (`gap`, `roundBars`) apply.
        var hasBars: Bool { self == .column || self == .bar || self == .stackedColumn || self == .stackedBar }

        /// Drawn as a line whose weight and points (`lineWidth`, `points`)
        /// apply; a radar's outline takes its weight too.
        var hasLine: Bool { self == .line || self == .area || self == .radar }

        /// Has a hole whose size (`hole`) applies.
        var hasHole: Bool { self == .donut || self == .progressRing }
    }

    // MARK: format

    /// The most characters a value's prefix or suffix keeps.
    static let maxAffix = 4

    /// A donut's hole and a progress ring's, as a share of the radius, when
    /// the chart sets none; and the range one may be set in.
    static let donutHole = 0.55
    static let ringHole = 0.8
    static let minHole = 0.3
    static let maxHole = 0.85

    /// The share of each slot left between bars when the chart sets none
    /// (the bar the other 0.64), and the most a gap may be.
    static let defaultGap = 0.36
    static let maxGap = 0.8

    /// A line's weight, as set, from thinnest to thickest.
    static let minLineWidth = 1.0
    static let maxLineWidth = 12.0

    /// The icon a pictogram is drawn in when it names none.
    static let defaultIcon = "person"

    /// The icons in a pictogram's row.
    static let pictogramIcons = 10

    /// `spec`'s donut or ring hole within 0.3…0.85, or its kind's own.
    static func hole(of spec: ChartSpec) -> Double {
        let own = spec.kind == ChartKind.donut.rawValue ? donutHole : ringHole
        guard let hole = spec.hole, hole.isFinite else { return own }
        return min(max(hole, minHole), maxHole)
    }

    /// `spec`'s bar gap within 0…0.8, or defaultGap.
    static func gap(of spec: ChartSpec) -> Double {
        guard let gap = spec.gap, gap.isFinite else { return defaultGap }
        return min(max(gap, 0), maxGap)
    }

    /// The stroke of a line chart's lines (and a radar's outlines) in
    /// `frame`: the chart's lineWidth, 1 to 12, as it is on a frame 300 on
    /// its shorter side, scaled to `frame`'s — whole and at least 1.
    /// `fallback`, as it was always drawn, when the chart sets none. The
    /// Android twin's `lineWeight`.
    static func lineWeight(_ spec: ChartSpec, frame: CGRect, fallback: Double) -> Double {
        guard let set = spec.lineWidth, set.isFinite else { return fallback }
        let width = min(max(set, minLineWidth), maxLineWidth)
        return max(1, (width * min(Double(frame.width), Double(frame.height)) / 300).rounded())
    }

    /// The separator between groups of three digits as the app's language
    /// writes it — "." in German, a narrow space in French — read each time
    /// a value is grouped; tests set it. A value's decimal point is a "."
    /// whatever the language.
    static var grouping: () -> String = { DataGraphics.groupingSeparator(for: AppLanguage.current()) }

    /// The grouping separator `code` writes: "," in English.
    static func groupingSeparator(for code: String) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: code)
        return f.groupingSeparator ?? ","
    }

    /// A value as `spec`'s labels write it, the same on both phones:
    /// - with no prefix, suffix, decimals or compact set, valueText, as a
    ///   chart always wrote it;
    /// - compact: from a thousand on, the value over the largest of 1e12
    ///   "T", 1e9 "B", 1e6 "M" and 1e3 "k" it reaches, to its decimals, or
    ///   to the tenth with a trailing ".0" dropped when it sets none —
    ///   "1.2k", "3.4M", "12M"; below a thousand as without compact;
    /// - decimals: exactly that many after a "." whatever the language,
    ///   halves away from zero, the whole part grouped by threes with the
    ///   app language's separator (grouping) — "1,234.50"; without, the
    ///   hundredth at most and no grouping, as valueText;
    /// - from 1e13 on, past a compact "T", valueText's power of ten;
    /// - the sign, then the prefix, the number and the suffix: "-$5".
    /// The Android twin's `formatValue` (the test rows are shared).
    static func formatValue(_ v: Double, _ spec: ChartSpec) -> String {
        let prefix = ChartSpec.affix(spec.prefix) ?? ""
        let suffix = ChartSpec.affix(spec.suffix) ?? ""
        let plain = prefix.isEmpty && suffix.isEmpty && spec.decimals == nil && !spec.compact
        if plain || !v.isFinite { return valueText(v) }
        let decimals = spec.decimals.map { min(max($0, 0), 3) }
        let a = abs(v)
        let units: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "k")]
        let unit = spec.compact ? units.first(where: { a >= $0.0 }) : nil
        let number: String
        if let unit, a / unit.0 < 1e13 {
            let m = a / unit.0
            number = (decimals.map { fixed(m, $0) } ?? trimmedTenth(m)) + unit.1
        } else if a >= 1e13 {
            number = valueText(a)
        } else if let decimals {
            number = fixed(a, decimals)
        } else {
            number = valueText(a)
        }
        // A value that rounds to nothing has no sign: "-0.00" is "0.00".
        let negative = v < 0 && number.contains { $0 >= "1" && $0 <= "9" }
        return (negative ? "-" : "") + prefix + number + suffix
    }

    /// A pie's or donut's slice as a share of the whole, `share` 0…1: a whole
    /// percentage, "75%", or to the chart's decimals when it sets them,
    /// "75.0%". A share has no prefix, suffix or compact form.
    static func shareText(_ share: Double, _ spec: ChartSpec) -> String {
        guard let decimals = spec.decimals else { return "\(Int((share * 100).rounded()))%" }
        return fixed(share * 100, min(max(decimals, 0), 3)) + "%"
    }

    /// `a`, not negative, to exactly `decimals` places, halves away from
    /// zero on its exact value (as Java's BigDecimal does on the Android
    /// twin, so 2.675, a little under, is 2.67), its whole part grouped by
    /// threes.
    private static func fixed(_ a: Double, _ decimals: Int) -> String {
        var exact = Decimal(string: exactDigits(a)) ?? Decimal(a)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, decimals, .plain)
        var text = NSDecimalNumber(decimal: rounded).stringValue
        // NSDecimalNumber drops trailing zeros: write them back.
        let point = text.firstIndex(of: ".")
        let have = point.map { text.distance(from: text.index(after: $0), to: text.endIndex) } ?? 0
        if decimals > 0 {
            if point == nil { text += "." }
            text += String(repeating: "0", count: max(0, decimals - have))
        }
        let whole = String(text.prefix { $0 != "." })
        return grouped(whole) + String(text.dropFirst(whole.count))
    }

    /// `a`'s exact binary value written out in decimal digits — every
    /// double is a whole number over a power of two, so it ends — for the
    /// rounding of `fixed` to see what the number truly is.
    private static func exactDigits(_ a: Double) -> String {
        guard a.isFinite, a < 1e16 else { return String(format: "%.0f", a) }
        // 1074 places is the most any double needs; %.60f is ample below
        // 1e16 for three places of rounding, as the error is far smaller.
        return String(format: "%.60f", a)
    }

    /// `a` to the tenth, a ".0" dropped.
    private static func trimmedTenth(_ a: Double) -> String {
        let text = fixed(a, 1)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    /// Digits `whole` grouped by threes from the right with `grouping`.
    private static func grouped(_ whole: String) -> String {
        guard whole.count > 3 else { return whole }
        let sep = grouping()
        var out = ""
        for (i, c) in whole.enumerated() {
            if i > 0 && (whole.count - i) % 3 == 0 { out += sep }
            out.append(c)
        }
        return out
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
        return chart(kind, data: chartData(spec.data, kind: kind), in: frame, palette: palette, ink: ink,
                     legend: spec.legend, values: spec.values, gridlines: spec.gridlines,
                     colours: colours, group: group, look: spec, heightFor: heightFor)
            .map { var e = $0; e.chart = spec; return e }
    }

    /// The share of their usual size a chart's labels are drawn at.
    static let textScales: ClosedRange<Double> = 0.5...2

    /// `spec`'s text scale, within 0.5…2; 1 when it has none.
    static func textScale(of spec: ChartSpec) -> Double {
        guard let scale = spec.textScale, scale.isFinite else { return 1 }
        return min(max(scale, textScales.lowerBound), textScales.upperBound)
    }

    /// The size a chart's labels are in `frame`: 6% of its shorter side,
    /// whole and at least 10, then times its text scale, whole again — as
    /// the Android twin's `labelSize` (the test rows are shared).
    static func labelSize(_ spec: ChartSpec?, in frame: CGRect) -> Double {
        let base: Double = max(10, (min(frame.width, frame.height) * 0.06).rounded())
        return (base * (spec.map(textScale(of:)) ?? 1)).rounded()
    }

    /// The scale a chart's values are drawn against, from `low` to `high`:
    /// from 0 to `peak`, the largest value (or stack), unless `spec` sets an
    /// end — its axisMin, its axisMax — and both ends as they were when the
    /// ones set leave the low end at or above the high. Only a kind with a
    /// scale has one to set. The Android twin's `axisRange`.
    static func axisRange(_ spec: ChartSpec?, peak: Double) -> (low: Double, high: Double) {
        guard let spec, ChartKind(rawValue: spec.kind)?.hasScale == true else { return (0, peak) }
        let low = spec.axisMin.flatMap { $0.isFinite ? $0 : nil } ?? 0
        let high = spec.axisMax.flatMap { $0.isFinite ? $0 : nil } ?? peak
        return low >= high ? (0, peak) : (low, high)
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
    /// series of columns or bars, and every pie, funnel and pictogram) — is
    /// `colours[n]` when given, else the palette's, and is the mark's part,
    /// "series:<n>". Every such part says what it shows for a screen reader
    /// (ChartSpeech.partLabel), kept as its alt text.
    ///
    /// A legend takes a row along the bottom, value labels room above the
    /// columns or beside the bars (a stack's total, a slice's share), and
    /// gridlines go behind, at quarters. With all three off and one series,
    /// the five first kinds are exactly what they always were. Progress
    /// kinds read the first value, clamped to 0...100, and write it
    /// themselves, with no legend.
    ///
    /// `look` is the chart's text look, scale and format: its labels' font,
    /// ink and size (labelSize), smooth lines and areas (smoothLine), the
    /// scale's ends (axisRange), against which values beyond them are held,
    /// how values are written (formatValue), the axes' titles — a strip
    /// along the foot and one up the left, the y title turned a quarter
    /// anticlockwise — the hole, the bars' gap and rounded ends, the line's
    /// weight and points, and a pictogram's icon.
    static func chart(_ kind: ChartKind, data: ChartData, in frame: CGRect, palette: [String],
                      ink pageInk: String = "#1f2430", legend: Bool = false, values: Bool = false,
                      gridlines: Bool = false, colours: [Int: Paint] = [:], group: String = UID.make("grp"),
                      look: ChartSpec? = nil,
                      heightFor: @escaping (Element) -> Double = FontLibrary.layoutHeight(for:)) -> [Element] {
        let rows = data.rows
        guard !rows.isEmpty, frame.width > 0, frame.height > 0 else { return [] }
        let colors = palette.isEmpty ? ["#5a31f4"] : palette
        let count = max(1, data.names.count)
        var out: [Element] = []
        let labelSize: Double = Self.labelSize(look, in: frame)
        // The chart's format, and what its parts say, read from its spec —
        // the defaults for a chart drawn without one.
        let spec: ChartSpec = {
            var s = look ?? ChartSpec(id: "", kind: kind.rawValue, data: "")
            s.kind = kind.rawValue
            return s
        }()
        // The labels' own font and ink, when the chart has them.
        let font = look?.font ?? "sans"
        let ink = look?.ink ?? pageInk
        let smooth = look?.smooth ?? false
        let firsts = rows.map { $0.values.first ?? 0 }
        let total = firsts.reduce(0, +)
        let peak = rows.map { $0.values.max() ?? 0 }.max() ?? 0
        if (kind == .pie || kind == .donut) && total <= 0 { return [] }
        // Each item its own colour, rather than each series.
        let byItem = kind.colourByRow || (count == 1 && (kind == .column || kind == .bar))
        let faint = normalised(ink)
        let legendH = legend && kind.hasLegend ? labelSize * 1.6 : 0
        // An axis title takes a strip along the foot or up the left side.
        func titled(_ title: String?) -> Bool {
            kind.hasAxisTitles && !(title ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        let xTitleH: Double = titled(spec.xTitle) ? labelSize * 1.6 : 0
        let yTitleW: Double = titled(spec.yTitle) ? labelSize * 1.6 : 0
        let plot = CGRect(x: frame.minX + yTitleW, y: frame.minY, width: frame.width - yTitleW,
                          height: frame.height - legendH - xTitleH)

        func paint(_ n: Int) -> Paint { colours[n] ?? .solid(colors[n % colors.count]) }
        func hex(_ n: Int) -> String { colours[n]?.primaryColor ?? colors[n % colors.count] }
        func value(_ row: ChartData.Row, _ s: Int) -> Double { s < row.values.count ? row.values[s] : 0 }
        func part(_ el: Element, _ name: String) -> Element {
            var e = el
            e.chartPart = name
            return e
        }
        /// Series part `n` for a reader: what it shows, as ChartSpeech says
        /// it — row `row` of it, or the whole series at -1.
        func said(_ el: Element, _ n: Int, _ row: Int) -> Element {
            var e = part(el, "series:\(n)")
            let words = ChartSpeech.partLabel(spec, data: data, part: "series:\(n)", index: row) ?? ""
            e.altText = words.isEmpty ? nil : words
            return e
        }
        func label(_ text: String, x: Double, y: Double, w: Double, align: String = "center",
                   part name: String = "label") -> Element {
            var t = Element.text(text, fontSize: labelSize, w: max(w, labelSize * 2))
            t.align = align
            t.color = ink
            t.fontFamily = font
            t.x = x; t.y = y
            t.h = heightFor(t)
            return part(t, name)
        }
        /// A value's label centred on `cx`, its foot at `foot`.
        func valueAbove(_ v: Double, cx: Double, foot: Double, w: Double) -> Element {
            var t = label(formatValue(v, spec), x: 0, y: 0, w: max(w, labelSize * 3), part: "value")
            t.x = cx - t.w / 2
            t.y = foot - labelSize * 0.3 - t.h
            return t
        }
        /// A value's label beside the end of a bar, centred on its height.
        func valueBeside(_ v: Double, end: Double, y: Double, h: Double, valueW: Double) -> Element {
            var t = label(formatValue(v, spec), x: end + labelSize * 0.3, y: 0, w: valueW - labelSize * 0.3,
                          align: "left", part: "value")
            t.y = y + (h - t.h) / 2
            return t
        }
        /// A row's label to the left of a row of bars, stages or icons.
        func rowLabel(_ text: String, top: Double, h: Double, labelW: Double) -> Element {
            label(text, x: plot.minX, y: top + (h - labelSize * 1.25) / 2, w: labelW - labelSize * 0.5, align: "right")
        }
        func bar(w: Double, h: Double, x: Double, y: Double, fill: Paint) -> Element {
            var b = Element.shape("rect", w: w, h: h)
            b.x = x; b.y = y
            b.fill = fill
            return b
        }
        /// `b` with its far end rounded, a quarter of its shorter side, when
        /// the chart rounds its bars: a column's top, a bar's right end.
        func farEnd(_ b: Element, column: Bool) -> Element {
            guard spec.roundBars else { return b }
            var out = b
            let r: Double = min(b.w, b.h) / 4
            out.radius = r
            out.corners = column ? [r, r, 0, 0] : [0, r, r, 0]
            return out
        }
        func gridAcross(top: Double, plotH: Double) {
            guard gridlines else { return }
            for g in 0...4 {
                out.append(part(bar(w: plot.width.rounded(), h: 1, x: plot.minX.rounded(),
                                    y: (top + plotH * Double(g) / 4).rounded(), fill: .solid(faint + "33")), "grid"))
            }
        }
        func gridDown(left: Double, plotW: Double, top: Double, plotH: Double) {
            guard gridlines else { return }
            for g in 0...4 {
                out.append(part(bar(w: 1, h: plotH.rounded(), x: (left + plotW * Double(g) / 4).rounded(),
                                    y: top.rounded(), fill: .solid(faint + "33")), "grid"))
            }
        }
        func shape(_ path: String, x: Double, y: Double, w: Double, h: Double, fill: Paint) -> Element {
            var s = bar(w: w.rounded(), h: h.rounded(), x: x.rounded(), y: y.rounded(), fill: fill)
            s.pathData = path
            return s
        }
        // The share of a slot a bar fills: its gap's rest.
        let barShare: Double = spec.gap == nil ? 0.64 : 1 - gap(of: spec)

        /// A dot for each row's point in each series (parseScatter), 2.5%
        /// of the frame's shorter side across (whole, at least 2), centred
        /// where its x and y fall on scales from 0 to the largest x and the
        /// largest y, laid out as a line chart is: values — its y — above
        /// the dots, gridlines across and down at quarters, and along the
        /// foot, where a line chart labels its rows, the x scale's ends, "0"
        /// on the left and the largest x on the right. An axis a px wide up
        /// the left and one along the foot are always drawn. A bubble chart's
        /// (parseBubble) dots are its bubbles: the largest 15% of the plot's
        /// shorter side across, each other's area in proportion to its size,
        /// three quarters opaque. The Android twin's layout, number for
        /// number.
        func scatter() {
            let bubble = kind == .bubble
            // A scatter's points are pairs, x and y; a bubble's, x, y and size.
            let width = bubble ? 3 : 2
            let labelH: Double = labelSize * 1.6
            let valueH: Double = values ? labelH : 0
            let left = Double(plot.minX)
            let plotW = Double(plot.width)
            let top: Double = Double(plot.minY) + valueH
            let plotH: Double = Double(plot.height) - labelH - valueH
            let pairs = 0..<count
            let xPeak = rows.map { row in pairs.map { value(row, width * $0) }.max() ?? 0 }.max() ?? 0
            let yPeak = rows.map { row in pairs.map { value(row, width * $0 + 1) }.max() ?? 0 }.max() ?? 0
            let sizePeak: Double = bubble ? (rows.map { row in pairs.map { value(row, 3 * $0 + 2) }.max() ?? 0 }.max() ?? 0) : 0
            // The axis range is the y scale's: the x scale is the foot's.
            let range = axisRange(look, peak: yPeak)
            let dot: Double = max(2, (min(frame.width, frame.height) * 0.025).rounded())
            let widest: Double = max(4, (min(plotW, plotH) * 0.15).rounded())
            gridAcross(top: top, plotH: plotH)
            gridDown(left: left, plotW: plotW, top: top, plotH: plotH)
            let axis = Paint.solid(faint + "66")
            out.append(part(bar(w: 1, h: plotH.rounded(), x: left.rounded(), y: top.rounded(), fill: axis), "axis"))
            out.append(part(bar(w: plotW.rounded(), h: 1, x: left.rounded(), y: (top + plotH).rounded(), fill: axis), "axis"))
            for j in pairs {
                for (i, row) in rows.enumerated() {
                    let x = value(row, width * j)
                    let y = value(row, width * j + 1)
                    var across = dot
                    if bubble {
                        across = sizePeak > 0 ? max(2, (widest * (value(row, 3 * j + 2) / sizePeak).squareRoot()).rounded()) : 2
                    }
                    let along: Double = xPeak > 0 ? plotW * x / xPeak : 0
                    let up: Double = range.high > range.low
                        ? plotH * (min(max(y, range.low), range.high) - range.low) / (range.high - range.low) : 0
                    let cx: Double = left + along
                    let cy: Double = top + plotH - up
                    var mark = Element.shape("circle", w: across, h: across)
                    mark.x = (cx - across / 2).rounded()
                    mark.y = (cy - across / 2).rounded()
                    mark.fill = paint(j)
                    if bubble { mark.opacity = 0.75 }
                    out.append(said(mark, j, i))
                    if values { out.append(valueAbove(y, cx: cx, foot: cy - across / 2, w: 0)) }
                }
            }
            let foot: Double = top + plotH + labelSize * 0.3
            out.append(label("0", x: left, y: foot, w: labelSize * 3, align: "left"))
            var end = label(formatValue(xPeak, spec), x: 0, y: foot, w: labelSize * 3, align: "right")
            end.x = left + plotW - end.w
            out.append(end)
        }

        /// A spoke for each row, clockwise from twelve o'clock; each series
        /// a closed outline across them, 60% opaque, its rows' labels just
        /// beyond the spokes' ends; gridlines are concentric polygons at
        /// quarters of the scale. The Android twin's radar.
        func radar() {
            let n = rows.count
            let labelH: Double = labelSize * 1.6
            let r: Double = max(1, min(Double(plot.width), Double(plot.height)) / 2 - labelH)
            let box = CGRect(x: plot.midX - r, y: plot.midY - r, width: 2 * r, height: 2 * r)
            let range = axisRange(look, peak: peak)
            func share(_ v: Double) -> Double {
                guard range.high > range.low else { return 0 }
                return (min(max(v, range.low), range.high) - range.low) / (range.high - range.low)
            }
            func angle(_ i: Int) -> Double { -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(n) }
            func at(_ i: Int, _ s: Double) -> CGPoint {
                CGPoint(x: 50 + 50 * s * cos(angle(i)), y: 50 + 50 * s * sin(angle(i)))
            }
            if gridlines {
                for g in 1...4 {
                    let ring = polyline((0..<n).map { at($0, Double(g) / 4) }) + " Z"
                    var grid = shape(ring, x: box.minX, y: box.minY, w: box.width, h: box.height, fill: .solid("#00000000"))
                    grid.stroke = faint + "33"
                    grid.strokeWidth = 1
                    out.append(part(grid, "grid"))
                }
            }
            let weight = lineWeight(spec, frame: frame, fallback: max(2, (r * 0.02).rounded()))
            for j in 0..<count {
                let outline = polyline(rows.indices.map { at($0, share(value(rows[$0], j))) }) + " Z"
                var mark = shape(outline, x: box.minX, y: box.minY, w: box.width, h: box.height, fill: paint(j))
                mark.stroke = hex(j)
                mark.strokeWidth = weight
                mark.opacity = 0.6
                out.append(said(mark, j, -1))
                if values {
                    for (i, row) in rows.enumerated() {
                        let p = at(i, share(value(row, j)))
                        out.append(valueAbove(value(row, j), cx: box.minX + p.x / 100 * box.width,
                                              foot: box.minY + p.y / 100 * box.height, w: 0))
                    }
                }
            }
            for (i, row) in rows.enumerated() {
                var t = label(row.label, x: 0, y: 0, w: labelSize * 6)
                let reach: Double = r + labelH / 2
                t.x = plot.midX + reach * cos(angle(i)) - t.w / 2
                t.y = plot.midY + reach * sin(angle(i)) - t.h / 2
                out.append(t)
            }
        }

        /// A stage a row, in the order typed, each a trapezoid centred on
        /// the plot: as wide at its top as its value is of the largest,
        /// narrowing to the next stage's width (the last keeping its own);
        /// its value inside, its label to the left.
        func funnel() {
            let labelW: Double = min(plot.width * 0.28, labelSize * 9)
            let plotW: Double = plot.width - labelW
            let left: Double = plot.minX + labelW
            let slot: Double = plot.height / Double(rows.count)
            let bandH: Double = slot * 0.9
            let widest = firsts.max() ?? 0
            let widths = firsts.map { widest > 0 ? $0 / widest : 0 }
            for (i, row) in rows.enumerated() {
                let top: Double = plot.minY + slot * Double(i) + (slot - bandH) / 2
                let a = widths[i]
                let b = i + 1 < widths.count ? widths[i + 1] : a
                if a > 0 || b > 0 {
                    let path = "M\(num(50 - 50 * a)) 0 L\(num(50 + 50 * a)) 0 L\(num(50 + 50 * b)) 100 L\(num(50 - 50 * b)) 100 Z"
                    out.append(said(shape(path, x: left, y: top, w: plotW, h: bandH, fill: paint(i)), i, i))
                }
                var t = label(formatValue(firsts[i], spec), x: left, y: 0, w: plotW, part: "value")
                // On the stage when it is wide enough for it, else in the labels' ink.
                let inside = plotW * min(a, b) >= labelSize * 3
                t.y = top + (bandH - t.h) / 2
                t.color = inside ? ColorTheory.readableInk(on: hex(i)) : ink
                out.append(t)
                out.append(rowLabel(row.label, top: top, h: bandH, labelW: labelW))
            }
        }

        /// Each row's first value as a row of ten icons: whole icons in its
        /// colour, the last partly so (its icon cut at the share left over,
        /// clippedPath), the rest faint. Each icon stands for 1 when no value
        /// passes 10, else a tenth of the largest.
        func pictogram() {
            let icon = IconLibrary.icon(spec.icon ?? defaultIcon) ?? IconLibrary.icon(defaultIcon)
            let outline = icon?.path ?? wedge(from: 0, sweep: 2 * .pi, inner: 0)
            let labelW: Double = min(plot.width * 0.28, labelSize * 9)
            let valueW: Double = values ? labelSize * 4 : 0
            let areaW: Double = plot.width - labelW - valueW
            let left: Double = plot.minX + labelW
            let slot: Double = plot.height / Double(rows.count)
            let icons = Double(pictogramIcons)
            let step: Double = areaW / icons
            let side: Double = max(1, min(step * 0.9, slot * 0.8).rounded())
            let widest = firsts.max() ?? 0
            let unit: Double = widest <= icons ? 1 : widest / icons
            for (i, row) in rows.enumerated() {
                let top: Double = (plot.minY + slot * Double(i) + (slot - side) / 2).rounded()
                let reached = min(max(firsts[i] / unit, 0), icons)
                for k in 0..<pictogramIcons {
                    let x: Double = left + step * Double(k) + (step - side) / 2
                    let filled = min(max(reached - Double(k), 0), 1)
                    if filled < 1 {
                        out.append(part(shape(outline, x: x, y: top, w: side, h: side, fill: .solid(faint + "22")), "axis"))
                    }
                    if filled > 0 {
                        let cut = filled >= 1 ? outline : clippedPath(outline, upTo: filled * 100)
                        out.append(said(shape(cut, x: x, y: top, w: side, h: side, fill: paint(i)), i, i))
                    }
                }
                if values { out.append(valueBeside(firsts[i], end: left + areaW, y: top, h: side, valueW: valueW)) }
                out.append(rowLabel(row.label, top: top, h: side, labelW: labelW))
            }
        }

        /// A cell for each row and series, the series' names across the top
        /// and the rows' labels down the left; every cell series 0's colour,
        /// as opaque as its value is from 15% (the least) to 100% (the most)
        /// — all 100% when the values are the same. Its cells are all
        /// "series:0", numbered row by row for a reader.
        func heatmap() {
            let labelW: Double = min(plot.width * 0.28, labelSize * 9)
            let headH: Double = labelSize * 1.6
            let left: Double = plot.minX + labelW
            let cellW: Double = (plot.width - labelW) / Double(count)
            let cellH: Double = (plot.height - headH) / Double(rows.count)
            let all = rows.flatMap { row in (0..<count).map { value(row, $0) } }
            let least = all.min() ?? 0
            let most = all.max() ?? 0
            func shade(_ v: Double) -> Double { most > least ? 0.15 + 0.85 * (v - least) / (most - least) : 1 }
            for (j, name) in data.names.enumerated() {
                out.append(label(name, x: left + cellW * Double(j), y: plot.minY + (headH - labelSize * 1.25) / 2, w: cellW))
            }
            for (i, row) in rows.enumerated() {
                let top: Double = plot.minY + headH + cellH * Double(i)
                for j in 0..<count {
                    let v = value(row, j)
                    var cell = bar(w: max(1, cellW.rounded() - 2), h: max(1, cellH.rounded() - 2),
                                   x: (left + cellW * Double(j)).rounded() + 1, y: top.rounded() + 1, fill: paint(0))
                    cell.opacity = shade(v)
                    out.append(said(cell, 0, i * count + j))
                    if values {
                        var t = label(formatValue(v, spec), x: left + cellW * Double(j), y: 0, w: cellW, part: "value")
                        t.y = top + (cellH - t.h) / 2
                        t.color = shade(v) > 0.5 ? ColorTheory.readableInk(on: hex(0)) : ink
                        out.append(t)
                    }
                }
                out.append(rowLabel(row.label, top: top, h: cellH, labelW: labelW))
            }
        }

        /// A ring all the way round from twelve o'clock, or a dial: a 240°
        /// arc from the lower left round to the lower right; the first value
        /// as a percentage filled and written in the middle.
        func progressArc(dial: Bool) {
            let start: Double = dial ? Double.pi * 5 / 6 : -Double.pi / 2
            let sweep: Double = dial ? Double.pi * 4 / 3 : 2 * Double.pi
            let inner: Double = dial ? ringHole : hole(of: spec)
            let percent = min(100, max(0, firsts[0]))
            let side: Double = min(frame.width, frame.height)
            let left: Double = frame.midX - side / 2
            let top: Double = frame.midY - side / 2
            out.append(part(shape(wedge(from: start, sweep: sweep, inner: inner),
                                  x: left, y: top, w: side, h: side, fill: .solid(faint + "22")), "axis"))
            if percent > 0 {
                out.append(said(shape(wedge(from: start, sweep: sweep * percent / 100, inner: inner),
                                      x: left, y: top, w: side, h: side, fill: paint(0)), 0, 0))
            }
            let figure: Double = (max(10, (side * 0.2).rounded()) * (look.map(textScale(of:)) ?? 1)).rounded()
            var t = Element.text("\(Int(percent.rounded()))%", fontSize: figure, w: side.rounded())
            t.align = "center"
            t.fontWeight = 700
            t.color = ink
            t.fontFamily = font
            t.x = left.rounded()
            t.h = heightFor(t)
            t.y = frame.midY - t.h / 2
            out.append(part(t, "value"))
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
            let barW: Double = slot * barShare
            let range = axisRange(look, peak: stacked ? (rows.map { $0.values.reduce(0, +) }.max() ?? 0) : peak)
            // How far up the plot `v` stands, held to the scale.
            func up(_ v: Double) -> Double {
                guard range.high > range.low else { return 0 }
                return plotH * (min(max(v, range.low), range.high) - range.low) / (range.high - range.low)
            }
            gridAcross(top: top, plotH: plotH)
            for (i, row) in rows.enumerated() {
                let left: Double = plot.minX + slot * Double(i) + (slot - barW) / 2
                if stacked {
                    var below = 0.0
                    // Only the top segment of a stack has its end rounded.
                    let last = row.values.lastIndex { $0 > 0 }
                    for (j, v) in row.values.enumerated() where v > 0 && range.high > range.low {
                        let y0 = (base - up(below + v)).rounded()
                        let y1 = (base - up(below)).rounded()
                        let segment = bar(w: barW.rounded(), h: y1 - y0, x: left.rounded(), y: y0, fill: paint(j))
                        out.append(said(j == last ? farEnd(segment, column: true) : segment, j, i))
                        below += v
                    }
                    let sum = row.values.reduce(0, +)
                    if values {
                        out.append(valueAbove(sum, cx: left + barW / 2, foot: base - up(sum), w: barW))
                    }
                } else {
                    let w = barW / Double(count)
                    for s in 0..<count {
                        let v = value(row, s)
                        let h = up(v)
                        let x = left + w * Double(s)
                        let n = byItem ? i : s
                        let b = bar(w: w.rounded(), h: max(1, h.rounded()), x: x.rounded(), y: (base - h).rounded(), fill: paint(n))
                        out.append(said(farEnd(b, column: true), n, i))
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
            let barH: Double = slot * barShare
            let range = axisRange(look, peak: stacked ? (rows.map { $0.values.reduce(0, +) }.max() ?? 0) : peak)
            // How far along the plot `v` reaches, held to the scale.
            func along(_ v: Double) -> Double {
                guard range.high > range.low else { return 0 }
                return plotW * (min(max(v, range.low), range.high) - range.low) / (range.high - range.low)
            }
            gridDown(left: left, plotW: plotW, top: Double(plot.minY), plotH: Double(plot.height))
            for (i, row) in rows.enumerated() {
                let top: Double = (plot.minY + slot * Double(i) + (slot - barH) / 2).rounded()
                if stacked {
                    var before = 0.0
                    let last = row.values.lastIndex { $0 > 0 }
                    for (j, v) in row.values.enumerated() where v > 0 && range.high > range.low {
                        let x0 = (left + along(before)).rounded()
                        let x1 = (left + along(before + v)).rounded()
                        let segment = bar(w: x1 - x0, h: barH.rounded(), x: x0, y: top, fill: paint(j))
                        out.append(said(j == last ? farEnd(segment, column: false) : segment, j, i))
                        before += v
                    }
                    let sum = row.values.reduce(0, +)
                    if values {
                        out.append(valueBeside(sum, end: left + along(sum), y: top, h: barH.rounded(), valueW: valueW))
                    }
                } else {
                    let h = barH / Double(count)
                    for s in 0..<count {
                        let v = value(row, s)
                        let w = along(v)
                        let n = byItem ? i : s
                        let b = bar(w: max(1, w.rounded()), h: h.rounded(), x: left.rounded(),
                                    y: (plot.minY + slot * Double(i) + (slot - barH) / 2 + h * Double(s)).rounded(), fill: paint(n))
                        out.append(said(farEnd(b, column: false), n, i))
                        if values { out.append(valueBeside(v, end: b.x + b.w, y: b.y, h: b.h, valueW: valueW)) }
                    }
                }
                out.append(rowLabel(row.label, top: top, h: barH, labelW: labelW))
            }
        case .pie, .donut:
            let side: Double = min(plot.width, plot.height)
            let left: Double = plot.midX - side / 2
            let top: Double = plot.midY - side / 2
            let inner = kind == .donut ? hole(of: spec) : 0
            var start = -Double.pi / 2
            for (i, v) in firsts.enumerated() where v > 0 {
                let sweep = 2 * .pi * v / total
                let slice = shape(wedge(from: start, sweep: sweep, inner: inner), x: left, y: top, w: side, h: side, fill: paint(i))
                out.append(said(slice, i, i))
                if values {
                    // Halfway across the slice, in ink that reads on it.
                    let middle = start + sweep / 2
                    let reach = side / 2 * (inner > 0 ? (1 + inner) / 2 : 0.62)
                    var t = label(shareText(v / total, spec), x: 0, y: 0, w: labelSize * 3, part: "value")
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
            let range = axisRange(look, peak: peak)
            // How high `v` stands, as a share of the scale.
            func share(_ v: Double) -> Double {
                guard range.high > range.low else { return 0 }
                return (min(max(v, range.low), range.high) - range.low) / (range.high - range.low)
            }
            let weight = lineWeight(spec, frame: frame, fallback: max(2, (plotH * 0.02).rounded()))
            gridAcross(top: top, plotH: plotH)
            for s in 0..<count {
                let points = rows.enumerated().map { i, row in
                    CGPoint(x: Double(i) / Double(n) * 100, y: 100 - share(value(row, s)) * 100)
                }
                // Through every point on a curve, or straight from one to the next.
                let through = smooth ? smoothLine(points) : polyline(points)
                var mark: Element
                if kind == .line {
                    mark = shape(through, x: plot.minX, y: top, w: plot.width, h: plotH, fill: .solid("#00000000"))
                    mark.stroke = hex(s)
                    mark.strokeWidth = weight
                } else {
                    mark = shape(through + " L100 100 L0 100 Z", x: plot.minX, y: top, w: plot.width, h: plotH, fill: paint(s))
                    // Several areas overlap, so each lets the others show.
                    mark.opacity = count > 1 ? 0.7 : 1
                }
                out.append(said(mark, s, -1))
                if spec.points {
                    // A dot on each point, two and a half times the line's weight across.
                    let dot: Double = max(4, (weight * 2.5).rounded())
                    for (i, row) in rows.enumerated() {
                        let cx: Double = plot.minX + Double(i) / Double(n) * plot.width
                        let cy: Double = top + plotH - plotH * share(value(row, s))
                        var d = Element.shape("circle", w: dot, h: dot)
                        d.x = (cx - dot / 2).rounded()
                        d.y = (cy - dot / 2).rounded()
                        d.fill = paint(s)
                        out.append(said(d, s, i))
                    }
                }
                if values {
                    for (i, row) in rows.enumerated() {
                        let v = value(row, s)
                        out.append(valueAbove(v, cx: plot.minX + Double(i) / Double(n) * plot.width,
                                              foot: top + plotH - plotH * share(v), w: 0))
                    }
                }
            }
            let slot: Double = plot.width / Double(rows.count)
            for (i, row) in rows.enumerated() {
                out.append(label(row.label, x: plot.minX + Double(i) / Double(n) * plot.width - slot / 2,
                                 y: top + plotH + labelSize * 0.3, w: slot))
            }
        case .scatter, .bubble:
            scatter()
        case .radar:
            radar()
        case .funnel:
            funnel()
        case .pictogram:
            pictogram()
        case .heatmap:
            heatmap()
        case .progressRing, .progressDial:
            progressArc(dial: kind == .progressDial)
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
                out.append(said(done, 0, 0))
            }
            var t = label("\(Int(percent.rounded()))%", x: frame.minX + plotW + labelSize * 0.5, y: 0,
                          w: labelW - labelSize * 0.5, align: "left", part: "value")
            t.y = frame.midY - t.h / 2
            out.append(t)
        }

        if xTitleH > 0 {
            var t = label(spec.xTitle ?? "", x: plot.minX, y: 0, w: plot.width, part: "axisTitle")
            t.y = plot.minY + plot.height + (xTitleH - t.h) / 2
            out.append(t)
        }
        if yTitleW > 0 {
            // Turned a quarter anticlockwise about its middle, which sits in
            // the middle of the strip up the left of the plot.
            var t = label(spec.yTitle ?? "", x: 0, y: 0, w: plot.height, part: "axisTitle")
            t.x = frame.minX + yTitleW / 2 - t.w / 2
            t.y = plot.midY - t.h / 2
            t.rotation = -90
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

    /// The frame Update draws `spec` in, in place of the chart `was` whose
    /// elements, upright, fill `bounds`: the frame that fills them as `was`
    /// did (frameFilling), which is the frame it was drawn in. When the kind
    /// changes, that frame is kept on the page (`width` by `height`) — a
    /// progress bar's is far taller than the bar, and the new kind fills all
    /// of it. The Android twin's `updateFrame`.
    static func updateFrame(_ was: ChartSpec, to spec: ChartSpec, bounds: CGRect, width: Double, height: Double,
                            heightFor: @escaping (Element) -> Double = FontLibrary.layoutHeight(for:)) -> CGRect {
        let frame = frameFilling(was, bounds: bounds, heightFor: heightFor)
        guard spec.kind != was.kind else { return frame }
        let w = min(Double(frame.width), width)
        let h = min(Double(frame.height), height)
        let x = max(0, min(Double(frame.minX), width - w))
        let y = max(0, min(Double(frame.minY), height - h))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The palette Update draws chart `id`'s series — or rows — in:
    /// palette(for:page:) of the design as it is without the chart, so that
    /// its own marks and labels are not counted as the design's colours,
    /// then keepingPalette for the colours its series have now (`colours`).
    /// The Android twin's `paletteForUpdate`.
    static func palette(updating id: String, design: Design, page: Page, colours: [Int: Paint]) -> [String] {
        func bare(_ p: Page) -> Page {
            var out = p
            out.elements.removeAll { $0.chart?.id == id }
            return out
        }
        var without = design
        without.pages = design.pages.map { $0.id == page.id ? bare($0) : $0 }
        return keepingPalette(palette(for: without, page: bare(page)), colours: colours)
    }

    /// `palette` laid out for a chart whose series have `colours` (by
    /// number): each of those in its own place, and every other place, in
    /// turn, a colour of `palette` none of them has, after the last of them
    /// too — so a series or row added comes out as it would in a chart just
    /// made, not in a colour the chart already shows. `palette` itself when
    /// no series has a colour, or every colour of it is taken. Numbers past
    /// 63 are not given places. The Android twin's `keepingPalette`.
    static func keepingPalette(_ palette: [String], colours: [Int: Paint]) -> [String] {
        let used = Set(colours.values.map { normalised($0.primaryColor) })
        let fresh = palette.filter { !used.contains(normalised($0)) }
        let last = min(colours.keys.max() ?? -1, 63)
        guard !fresh.isEmpty, last >= 0 else { return palette }
        var out: [String] = []
        var taken = 0
        var n = 0
        while n <= last || taken < fresh.count {
            if let own = colours[n] {
                out.append(own.primaryColor)
            } else {
                out.append(fresh[taken % fresh.count])
                taken += 1
            }
            n += 1
        }
        return out
    }

    /// The turn every one of a chart's `members` has; 0 when they differ.
    /// A y axis title is turned a quarter of its own, so it does not count
    /// — so long as it is the chart's turn and that quarter. The Android
    /// twin's `turnOf`.
    static func turn(of members: [Element]) -> Double {
        let titles = members.filter { $0.chartPart == "axisTitle" }
        let upright = titles.count == members.count ? members : members.filter { $0.chartPart != "axisTitle" }
        let turns = Set(upright.map(\.rotation))
        guard turns.count == 1, let turn = turns.first else { return 0 }
        func off(_ el: Element, _ by: Double) -> Bool {
            let d = ((el.rotation - turn + by).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            return abs(d) < 1e-6 || abs(d - 360) < 1e-6
        }
        return titles.allSatisfy { off($0, 0) || off($0, 90) } ? turn : 0
    }

    /// Slice or arc `el` — a pie's or donut's "series:<n>", a progress
    /// ring's or dial's "series:0" — drawn to `share` of its sweep from where
    /// it starts, as the Grow entrance sweeps it round: the wedge chart
    /// made, made again from its spec with its sweep times `share`. `el`
    /// itself for anything else, or a share of 1 or more. The Android twin's
    /// `swept`.
    static func swept(_ el: Element, share: Double) -> Element {
        guard share < 1, let spec = el.chart, let kind = ChartKind(rawValue: spec.kind),
              let part = el.chartPart, part.hasPrefix("series:"),
              let n = Int(part.dropFirst("series:".count)) else { return el }
        let firsts = chartData(spec.data, kind: kind).rows.map { $0.values.first ?? 0 }
        let f = min(max(share, 0), 1)
        var out = el
        switch kind {
        case .pie, .donut:
            let total = firsts.reduce(0, +)
            guard n >= 0, n < firsts.count, firsts[n] > 0, total > 0 else { return el }
            let before = firsts.prefix(n).filter { $0 > 0 }.reduce(0.0) { $0 + 2 * Double.pi * $1 / total }
            let sweep: Double = 2 * .pi * firsts[n] / total * f
            out.pathData = wedge(from: -.pi / 2 + before, sweep: sweep, inner: kind == .donut ? hole(of: spec) : 0)
        case .progressRing, .progressDial:
            guard let first = firsts.first else { return el }
            let dial = kind == .progressDial
            let percent = min(100, max(0, first))
            let whole: Double = dial ? .pi * 4 / 3 : 2 * .pi
            out.pathData = wedge(from: dial ? .pi * 5 / 6 : -.pi / 2, sweep: whole * percent / 100 * f,
                                 inner: dial ? ringHole : hole(of: spec))
        default:
            return el
        }
        return out
    }

    /// `path` — an icon's, of M, L, C and Z in the 0…100 box — cut off at
    /// x = `upTo`, the part to its left kept: each curve flattened to 8
    /// straight steps and each closed piece clipped to the half-plane
    /// (Sutherland–Hodgman), written as polyline writes points, each piece
    /// closed. A piece wholly cut away goes. How a pictogram's last icon
    /// shows the share of it its value reaches. The Android twin's
    /// `clippedPath` (the test rows are shared).
    static func clippedPath(_ path: String, upTo: Double) -> String {
        let pattern = try? NSRegularExpression(pattern: "[MLCZmlcz]|-?\\d*\\.?\\d+(?:[eE][+-]?\\d+)?")
        let whole = NSRange(path.startIndex..., in: path)
        let tokens: [String] = (pattern?.matches(in: path, range: whole) ?? []).compactMap { m in
            Range(m.range, in: path).map { String(path[$0]) }
        }
        var pieces: [[CGPoint]] = []
        // The piece being drawn, as its index in `pieces`.
        var current: Int?
        var i = 0
        var command: Character = "M"
        func next() -> Double {
            defer { i += 1 }
            return i < tokens.count ? Double(tokens[i]) ?? 0 : 0
        }
        reading: while i < tokens.count {
            let token = tokens[i]
            if token.count == 1, let c = token.first, c.isLetter {
                command = Character(c.uppercased())
                i += 1
                if command == "Z" { current = nil }
                continue
            }
            switch command {
            case "M":
                let p = CGPoint(x: next(), y: next())
                pieces.append([p])
                current = pieces.count - 1
                command = "L"
            case "L":
                let p = CGPoint(x: next(), y: next())
                if let k = current {
                    pieces[k].append(p)
                } else {
                    pieces.append([p])
                    current = pieces.count - 1
                }
            case "C":
                guard let k = current, let p0 = pieces[k].last else { break reading }
                let c1 = CGPoint(x: next(), y: next())
                let c2 = CGPoint(x: next(), y: next())
                let p3 = CGPoint(x: next(), y: next())
                for step in 1...8 {
                    let t = Double(step) / 8
                    let u = 1 - t
                    let a: Double = u * u * u, b: Double = 3 * u * u * t, c: Double = 3 * u * t * t, d: Double = t * t * t
                    pieces[k].append(CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
                                             y: a * p0.y + b * c1.y + c * c2.y + d * p3.y))
                }
            default:
                i += 1
            }
        }
        var out: [String] = []
        for piece in pieces {
            var kept: [CGPoint] = []
            for k in piece.indices {
                let a = piece[k]
                let b = piece[(k + 1) % piece.count]
                let aIn = a.x <= upTo
                let bIn = b.x <= upTo
                if aIn { kept.append(a) }
                if aIn != bIn { kept.append(CGPoint(x: upTo, y: a.y + (b.y - a.y) * (upTo - a.x) / (b.x - a.x))) }
            }
            guard kept.count >= 3 else { continue }
            out.append(polyline(kept) + " Z")
        }
        return out.joined(separator: " ")
    }

    /// `made`, drawn upright, given what `members` had as a whole: turned by
    /// `turn` about `pivot`, as a group is turned; the opacity they all had;
    /// the first link, entrance, exit and timing among them on every
    /// element — so Update leaves a turned, faded, linked, animated or timed
    /// chart so. The Android twin's `carried`.
    static func carrying(_ members: [Element], into made: [Element], pivot: CGPoint, turn: Double) -> [Element] {
        let opacities = Set(members.map(\.opacity))
        let opacity: Double? = opacities.count == 1 ? opacities.first : nil
        let link = members.lazy.compactMap(\.link).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let enter = members.lazy.compactMap(\.animation).first
        let exit = members.lazy.compactMap(\.exitAnimation).first
        let timing = members.lazy.compactMap(\.timing).first
        let styled = made.map { el -> Element in
            var out = el
            if let opacity { out.opacity = opacity }
            if let link { out.link = link }
            if let enter { out.animation = enter }
            if let exit { out.exitAnimation = exit }
            if let timing { out.timing = timing }
            return out
        }
        return turn != 0 ? Geometry.rotate(styled, around: pivot, by: turn) : styled
    }

    /// `after` with the font and colour given by hand to a chart's words in
    /// this step (since `before`) written into that chart's spec, on every
    /// one of its elements, so the next Update draws all its labels so: a
    /// new font family is its `font`, a new colour its `ink` (#rrggbb, lower
    /// case). As the Android twin's `styleKept` keeps them; `after` itself
    /// when no chart's words changed either.
    static func styleKept(_ after: Design, since before: Design) -> Design {
        var out = after
        for p in out.pages.indices {
            let page = out.pages[p]
            guard page.elements.contains(where: { $0.type == .text && $0.chart != nil }),
                  let old = before.pages.first(where: { $0.id == page.id }), old.elements != page.elements else { continue }
            var was: [String: Element] = [:]
            for el in old.elements where el.type == .text && el.chart != nil { was[el.id] = el }
            var fonts: [String: String] = [:]
            var inks: [String: String] = [:]
            for el in page.elements where el.type == .text {
                guard let spec = el.chart, let prior = was[el.id], prior != el else { continue }
                if let font = el.fontFamily, font != prior.fontFamily, font != spec.font { fonts[spec.id] = font }
                if let color = el.color, color != prior.color, rgb(color) != nil {
                    let ink = normalised(color)
                    if ink != spec.ink { inks[spec.id] = ink }
                }
            }
            guard !fonts.isEmpty || !inks.isEmpty else { continue }
            for i in out.pages[p].elements.indices {
                guard var spec = out.pages[p].elements[i].chart,
                      fonts[spec.id] != nil || inks[spec.id] != nil else { continue }
                spec.font = fonts[spec.id] ?? spec.font
                spec.ink = inks[spec.id] ?? spec.ink
                out.pages[p].elements[i].chart = spec
            }
        }
        return out
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

    /// A line through every one of `points` on a Catmull-Rom curve: from
    /// each point to the next a cubic whose handles are a sixth of the way
    /// along the line from the point before to the point after — the first
    /// and last points standing in for the ones they lack. One point is
    /// where it starts; the numbers are as polyline writes them. The
    /// Android twin's `smoothLine` (the test rows are shared).
    static func smoothLine(_ points: [CGPoint]) -> String {
        guard let first = points.first else { return "" }
        var out = "M\(num(first.x)) \(num(first.y))"
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            let c1x: Double = p1.x + (p2.x - p0.x) / 6
            let c1y: Double = p1.y + (p2.y - p0.y) / 6
            let c2x: Double = p2.x - (p3.x - p1.x) / 6
            let c2y: Double = p2.y - (p3.y - p1.y) / 6
            out += " C\(num(c1x)) \(num(c1y)) \(num(c2x)) \(num(c2y)) \(num(p2.x)) \(num(p2.y))"
        }
        return out
    }

    static func polyline(_ points: [CGPoint]) -> String {
        guard let first = points.first else { return "" }
        return "M\(num(first.x)) \(num(first.y))" + points.dropFirst().map { " L\(num($0.x)) \(num($0.y))" }.joined()
    }

    private static func num(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    /// A value's label, as the Android twin writes it: to the hundredth
    /// below 1e13 ("12.5", "40"); from there three figures and a power of
    /// ten ("1.23e15", "1e19"), worked out in steps both phones take alike;
    /// "∞" past the largest number.
    static func valueText(_ v: Double) -> String {
        if v.isNaN { return "" }
        let sign = v < 0 ? "-" : ""
        let a = abs(v)
        if a.isInfinite { return sign + "∞" }
        if a < 1e13 { return num(v) }
        var p = 1.0, k = 0
        while a / p >= 1000 { p *= 10; k += 1 }
        let m = a / p
        let whole = m.rounded(.down)
        var d = Int(m - whole >= 0.5 ? whole + 1 : whole)
        if d >= 1000 { d = 100; k += 1 }
        let rest = d % 100
        let mantissa = rest == 0 ? "\(d / 100)"
            : rest % 10 == 0 ? "\(d / 100).\(rest / 10)"
            : "\(d / 100).\(rest < 10 ? "0" : "")\(rest)"
        return "\(sign)\(mantissa)e\(k + 2)"
    }

    // MARK: tables

    /// Rows of cells as text; the first row is the header. Cells are
    /// separated by commas or tabs.
    /// What the table typed so far comes to, under the box it is typed in:
    /// "3 rows × 4 columns; the first row is the header." — the widest row
    /// counting — with "row" and "column" singular when there is one, as
    /// the Android twin says it.
    static func tableSummary(_ rows: [[String]]) -> String {
        guard !rows.isEmpty else { return tr("Nothing to tabulate yet.") }
        let columns = rows.map(\.count).max() ?? 0
        return tr("%@ × %@; the first row is the header.", trn("%d row|%d rows", rows.count),
                  trn("%d column|%d columns", columns))
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

    /// A table's words as Edit as text reads them back (tableText wrote
    /// them as `opened`): a row per line, the blank lines before the first
    /// row and after the last left out and those between kept as rows with
    /// no words, so no row's words move up into another's. A line with a
    /// tab splits on tabs. With `tabs`, the table was written with tabs
    /// between its cells and a comma is part of a cell's words, so a line
    /// as it was opened (a one-column table's "Smith, John") stays one
    /// cell; any other line with no tab — one typed on a keyboard with no
    /// tab key — splits on commas, as parseTable splits it. The Android
    /// twin's `parseEditedTable`.
    static func parseEditedTable(_ text: String, opened: String, tabs: Bool) -> [[String]] {
        let all = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = all.firstIndex(where: { !trim($0).isEmpty }),
              let last = all.lastIndex(where: { !trim($0).isEmpty }) else { return [] }
        let whole: Set<String> = tabs
            ? Set(opened.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines).map(trim))
            : []
        return all[first...last].map { line -> [String] in
            if line.contains("\t") {
                return line.split(separator: "\t", omittingEmptySubsequences: false).map { trim(String($0)) }
            }
            if whole.contains(trim(line)) { return [trim(line)] }
            return line.split(separator: ",", omittingEmptySubsequences: false).map { trim(String($0)) }
        }
    }

    /// A table filling `frame`: a header row in `accent` with light text,
    /// banded body rows, hairline cells, text in each cell. Column widths
    /// follow the longest text in each column; row heights follow the text.
    /// Every cell and its text carry the table's id, row and column, so the
    /// table can be edited afterwards (see relayout). Texts are measured by
    /// `heightFor`, as relayout measures them.
    static func table(_ rows: [[String]], in frame: CGRect, accent: String,
                      heightFor: (Element) -> Double = { FontLibrary.layoutHeight(for: $0) }) -> [Element] {
        table(rows, in: frame, accent: accent, ink: tableInk, band: tableBand, fontSize: nil, heightFor: heightFor)
    }

    static func table(_ rows: [[String]], in frame: CGRect, accent: String, ink: String,
                      band: String, fontSize: Double?, heightFor: (Element) -> Double) -> [Element] {
        guard let columns = rows.map(\.count).max(), columns > 0, !rows.isEmpty,
              frame.width > 0 else { return [] }
        let group = UID.make("grp")
        let tableId = UID.make("tbl")
        let size = fontSize ?? max(10, (frame.width / Double(columns) * 0.11).rounded())
        let pad = size * tablePad
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
                t.h = heightFor(t)
                t.table = TableCell(id: tableId, row: r, col: c)
                texts.append(t)
                x += widths[c]
            }
            let rowH = ((texts.map(\.h).max() ?? size) + 2 * pad).rounded()
            x = frame.minX
            for c in 0..<columns {
                var cell = Element.shape("rect", w: widths[c], h: rowH)
                cell.x = x.rounded(); cell.y = y.rounded()
                cell.fill = .solid(r == 0 ? accent : tableBodyFill(r, band: band))
                cell.stroke = tableHairline
                cell.strokeWidth = 1
                cell.radius = 0
                cell.table = TableCell(id: tableId, row: r, col: c)
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
