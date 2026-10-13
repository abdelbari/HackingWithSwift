// A chart's data and a table's words as a grid of cells, for the
// spreadsheet-style editor Edit chart and Edit as text open: rows and
// columns of cells read from the text each already keeps, and written back
// as that same text, so the file never changes for it. The Android twin's
// DataGrid, rule for rule, with the same test rows:
// - cells: a row per line, blank lines left out; a line holding a tab splits
//   on tabs, any other on commas (as parseTable splits one); each cell's
//   spaces trimmed; every row as wide as the widest. Quotes are words like
//   any other: neither phone's text reads them.
// - chartText: cells joined by ", ", each row's empty cells at its end left
//   off and rows with no words left out, so a single series still reads
//   "Label, value"; a comma in a cell is taken out, as a chart's text has no
//   way to hold one, and a line break or tab is a space.
// - tableText: tableText's: every cell, joined by ", " — or by tabs in every
//   row once any cell holds a comma — a line break or tab a space.
// - pasting: text pasted at a cell, read as cells reads it, laid over the
//   grid from there, the grid growing to hold it.

import Foundation

enum DataGrid {

    static func cells(_ text: String) -> [[String]] {
        let rows = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line -> [String] in
                let split: Character = line.contains("\t") ? "\t" : ","
                return line.split(separator: split, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
        return padded(rows)
    }

    static func chartText(_ cells: [[String]]) -> String {
        cells.map { row -> [String] in
            var words = row.map {
                flat($0).replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            while words.last?.isEmpty == true { words.removeLast() }
            return words
        }
        .filter { !$0.isEmpty }
        .map { $0.joined(separator: ", ") }
        .joined(separator: "\n")
    }

    static func tableText(_ cells: [[String]]) -> String {
        let split = tabbed(cells) ? "\t" : ", "
        return cells.map { row in row.map(flat).joined(separator: split) }.joined(separator: "\n")
    }

    /// Whether tableText puts tabs between `cells`: when any holds a comma.
    static func tabbed(_ cells: [[String]]) -> Bool {
        cells.contains { row in row.contains { $0.contains(",") } }
    }

    static func pasting(_ text: String, into cells: [[String]], row: Int, col: Int) -> [[String]] {
        let clip = self.cells(text)
        guard let first = clip.first, row >= 0, col >= 0 else { return cells }
        var out = padded(cells)
        let width = max(out.first?.count ?? 0, col + first.count)
        while out.count < row + clip.count { out.append(Array(repeating: "", count: width)) }
        out = out.map { $0 + Array(repeating: "", count: max(0, width - $0.count)) }
        for (r, line) in clip.enumerated() {
            for (c, words) in line.enumerated() { out[row + r][col + c] = words }
        }
        return out
    }

    /// `cells` with the cell at `row`, `col` set to `words`.
    static func settingCell(_ cells: [[String]], row: Int, col: Int, to words: String) -> [[String]] {
        guard cells.indices.contains(row), cells[row].indices.contains(col) else { return cells }
        var out = cells
        out[row][col] = words
        return out
    }

    /// A blank row in at `at`, as wide as the grid (one cell, in a grid
    /// with none).
    static func addingRow(_ cells: [[String]], at: Int) -> [[String]] {
        var out = cells
        out.insert(Array(repeating: "", count: max(cells.first?.count ?? 0, 1)), at: min(max(at, 0), cells.count))
        return out
    }

    /// A blank column in at `at`, in every row (one row, in a grid with
    /// none).
    static func addingColumn(_ cells: [[String]], at: Int) -> [[String]] {
        (cells.isEmpty ? [[]] : cells).map { row in
            var out = row
            out.insert("", at: min(max(at, 0), row.count))
            return out
        }
    }

    /// Row `at` taken out; the last row never goes.
    static func removingRow(_ cells: [[String]], at: Int) -> [[String]] {
        guard cells.count > 1, cells.indices.contains(at) else { return cells }
        var out = cells
        out.remove(at: at)
        return out
    }

    /// Column `at` taken out of every row; the last column never goes.
    static func removingColumn(_ cells: [[String]], at: Int) -> [[String]] {
        let width = cells.first?.count ?? 0
        guard width > 1, at >= 0, at < width else { return cells }
        return cells.map { row in row.enumerated().filter { $0.offset != at }.map(\.element) }
    }

    /// Whether the grid's first row is a chart's header, as parseChart
    /// reads one: some cell after the first has words in it, and none is a
    /// number.
    static func chartHasHeader(_ cells: [[String]]) -> Bool {
        cells.first.map { DataGraphics.isHeader(chartText([$0])) } ?? false
    }

    /// The chart grid's Header row switched `on`: a first row put in
    /// naming a series for each column after the first, "Series 1" on — a
    /// blank first cell over the labels — or the header row there taken
    /// out. `cells` as they were when the header is already as asked.
    static func withChartHeader(_ cells: [[String]], on: Bool) -> [[String]] {
        guard on != chartHasHeader(cells) else { return cells }
        guard on else { return Array(cells.dropFirst()) }
        let body = padded(cells)
        let width = max(body.first?.count ?? 0, 2)
        let names = (0..<width).map { $0 == 0 ? "" : "Series \($0)" }
        return [names] + body.map { $0 + Array(repeating: "", count: max(0, width - $0.count)) }
    }

    /// Every row as wide as the widest.
    static func padded(_ rows: [[String]]) -> [[String]] {
        let width = rows.map(\.count).max() ?? 0
        return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    /// How many columns `cells` has: its widest row's.
    static func width(_ cells: [[String]]) -> Int {
        cells.map(\.count).max() ?? 0
    }

    /// Column `c`'s name over the grid, as a spreadsheet names it: A to Z,
    /// then AA, AB… from the 27th.
    static func columnName(_ c: Int) -> String {
        var n = max(0, c) + 1
        var out = ""
        while n > 0 {
            let rest = (n - 1) % 26
            out = String(Character(UnicodeScalar(UInt8(65 + rest)))) + out
            n = (n - 1) / 26
        }
        return out
    }

    /// A cell's words on one line: its line breaks and tabs spaces.
    private static func flat(_ cell: String) -> String {
        let breaks = CharacterSet.newlines.union(CharacterSet(charactersIn: "\t"))
        var out = String.UnicodeScalarView()
        for scalar in cell.unicodeScalars { out.append(breaks.contains(scalar) ? " " : scalar) }
        return String(out)
    }
}
