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

    // MARK: Import CSV

    /// The most of a CSV file the grid takes in, rows and columns, and the
    /// largest file Import CSV opens.
    static let csvRows = 50
    static let csvColumns = 12
    static let csvBytes = 1024 * 1024

    /// A CSV file in the grid: its first csvRows rows of its first
    /// csvColumns columns, and how many of each the file had.
    struct CsvImport: Equatable {
        var cells: [[String]]
        var rows: Int
        var columns: Int

        /// What was left out, when anything was: "Imported 50 of 212 rows",
        /// "Imported 12 of 20 columns", or both — "Imported 50 of 212 rows
        /// and 12 of 20 columns" — in the Android twin's words.
        var note: String? {
            let r = rows > DataGrid.csvRows, c = columns > DataGrid.csvColumns
            switch (r, c) {
            case (true, true):
                return tr("Imported %d of %d rows and %d of %d columns",
                          DataGrid.csvRows, rows, DataGrid.csvColumns, columns)
            case (true, false): return tr("Imported %d of %d rows", DataGrid.csvRows, rows)
            case (false, true): return tr("Imported %d of %d columns", DataGrid.csvColumns, columns)
            default: return nil
            }
        }
    }

    /// A CSV file's rows as RFC 4180 has them, as the Android twin reads
    /// one (the test rows are shared): a byte-order mark at the start
    /// dropped; cells split at commas — or at tabs, when the file's first
    /// line has one (a TSV); a cell in double quotes holding commas, line
    /// breaks and doubled quotes ("" for "); rows ending at CRLF, LF or CR.
    /// A quote opens a quoted cell only where the cell begins, spaces
    /// before it aside; anywhere else it is a quote. Each cell's spaces are
    /// trimmed, as cells trims them, and rows with no words are left out.
    /// The first csvRows rows and csvColumns columns are kept — or
    /// `maxRows` and `maxColumns`, for Bulk create — every row as wide as
    /// the widest kept.
    static func fromCsv(_ text: String, maxRows: Int = csvRows, maxColumns: Int = csvColumns) -> CsvImport {
        var body = Array(text.unicodeScalars)
        if body.first == "\u{FEFF}" { body.removeFirst() }
        let firstLine = body.prefix { $0 != "\n" && $0 != "\r" }
        let split: Unicode.Scalar = firstLine.contains("\t") ? "\t" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var cell = String.UnicodeScalarView()
        var quoted = false
        var started = false
        func endCell() {
            row.append(String(cell).trimmingCharacters(in: .whitespaces))
            cell = String.UnicodeScalarView()
            started = false
        }
        func endRow() {
            endCell()
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            row = []
        }
        var i = 0
        while i < body.count {
            let ch = body[i]
            if quoted {
                if ch == "\"" {
                    if i + 1 < body.count && body[i + 1] == "\"" {
                        cell.append("\"")
                        i += 1
                    } else {
                        quoted = false
                    }
                } else {
                    cell.append(ch)
                }
            } else if ch == "\"" && !started && String(cell).trimmingCharacters(in: .whitespaces).isEmpty {
                cell = String.UnicodeScalarView()
                quoted = true
                started = true
            } else if ch == split {
                endCell()
            } else if ch == "\r" || ch == "\n" {
                if ch == "\r" && i + 1 < body.count && body[i + 1] == "\n" { i += 1 }
                endRow()
            } else {
                cell.append(ch)
            }
            i += 1
        }
        if !cell.isEmpty || started || !row.isEmpty { endRow() }
        let columns = rows.map(\.count).max() ?? 0
        let kept = padded(rows.prefix(maxRows).map { Array($0.prefix(maxColumns)) })
        return CsvImport(cells: kept, rows: rows.count, columns: columns)
    }

    /// Rows read some other way — a workbook's sheet (XlsxReader) — into
    /// the grid as a CSV file's are: each cell's spaces trimmed, rows with
    /// no words left out, the first csvRows rows of the first csvColumns
    /// columns kept, every row as wide as the widest kept, and how many of
    /// each there were for the same note of what was left out. A sheet's
    /// rows come padded, so its trailing empty cells are no columns of
    /// their own, as on Android.
    static func fromRows(_ cells: [[String]], maxRows: Int = csvRows, maxColumns: Int = csvColumns) -> CsvImport {
        let rows = cells.map { row in row.map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { row in row.contains { !$0.isEmpty } }
        let columns = rows.map { row in (row.lastIndex { !$0.isEmpty } ?? -1) + 1 }.max() ?? 0
        let kept = padded(rows.prefix(maxRows).map { Array($0.prefix(min(maxColumns, columns))) })
        return CsvImport(cells: kept, rows: rows.count, columns: columns)
    }

    /// What Import CSV makes of a file: its rows, or why it brought none.
    enum CsvRead: Equatable {
        case rows(CsvImport)
        case refused(String)
    }

    /// A file's bytes for the grid, in the Android twin's words when they
    /// will not do: none read, more than csvBytes, or no rows with words.
    /// Read as UTF-8, anything that is not standing in for a character.
    static func read(csv data: Data?, maxRows: Int = csvRows, maxColumns: Int = csvColumns) -> CsvRead {
        guard let data else { return .refused(tr("That file could not be read")) }
        guard data.count <= csvBytes else { return .refused(tr("That file is over 1 MB")) }
        let read = fromCsv(String(decoding: data, as: UTF8.self), maxRows: maxRows, maxColumns: maxColumns)
        return read.cells.isEmpty ? .refused(tr("No rows to import in that file")) : .rows(read)
    }

    /// The file at `url` — one the file picker handed over — read for the
    /// grid, no more of it than one byte past csvBytes.
    static func read(csvAt url: URL, maxRows: Int = csvRows, maxColumns: Int = csvColumns) -> CsvRead {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return read(csv: nil) }
        defer { try? handle.close() }
        return read(csv: (try? handle.read(upToCount: csvBytes + 1)) ?? Data(), maxRows: maxRows,
                    maxColumns: maxColumns)
    }

    // MARK: Import data

    /// The largest workbook Import data opens: 20 MB, as on Android.
    static let xlsxBytes = 20 * 1024 * 1024

    /// What Import data makes of a file: its rows, a workbook's sheets to
    /// choose from — each with rows — or why it brought none.
    enum DataRead: Equatable {
        case rows(CsvImport)
        case sheets([XlsxReader.Sheet])
        case refused(String)
    }

    /// Whether `data` is a ZIP, as a workbook is.
    static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4).elementsEqual([0x50, 0x4b, 0x03, 0x04])
    }

    /// A workbook's bytes for the grid: its one sheet with rows, or its
    /// sheets with rows to choose from; why not, in the Android twin's
    /// words, when none is read, it is too big or none has rows.
    static func read(xlsx data: Data?) -> DataRead {
        guard let data else { return .refused(tr("That file isn't a spreadsheet Canvia can read.")) }
        guard data.count <= xlsxBytes else { return .refused(tr("That spreadsheet is too big to open.")) }
        let sheets = XlsxReader.read(data)
        guard !sheets.isEmpty else { return .refused(tr("That file isn't a spreadsheet Canvia can read.")) }
        let withRows = sheets.filter { !fromRows($0.cells).cells.isEmpty }
        guard let first = withRows.first else { return .refused(tr("No rows to import in that file")) }
        return withRows.count == 1 ? .rows(fromRows(first.cells)) : .sheets(withRows)
    }

    /// The file at `url` — one the file picker handed over — for the grid:
    /// a workbook (named .xlsx, or a ZIP) as `read(xlsx:)` reads it, any
    /// other as a CSV, TSV or text file.
    static func read(dataAt url: URL) -> DataRead {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .refused(tr("That file could not be read")) }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4)) ?? Data()
        if url.pathExtension.lowercased() == "xlsx" || isZip(head) {
            try? handle.seek(toOffset: 0)
            return read(xlsx: (try? handle.read(upToCount: xlsxBytes + 1)) ?? Data())
        }
        try? handle.seek(toOffset: 0)
        switch read(csv: (try? handle.read(upToCount: csvBytes + 1)) ?? Data()) {
        case .rows(let rows): return .rows(rows)
        case .refused(let why): return .refused(why)
        }
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
