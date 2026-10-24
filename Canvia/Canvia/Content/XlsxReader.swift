// An Excel workbook (.xlsx) — or a Numbers or Google Sheets export of one —
// read as grids of words for a chart's or a table's data, the Android
// twin's XlsxReader rule for rule (the shared fixture, Tests/Fixtures
// /sheets.xlsx from tools/generate_xlsx_fixture.py, holds both to it).
//
//   • the sheets are xl/workbook.xml's <sheet>s, in its order, each found
//     through xl/_rels/workbook.xml.rels by its r:id — else as
//     xl/worksheets/sheet<n>.xml, n its place from 1
//   • a cell is placed by its r ("C5"); one with none goes after the cell
//     before it in its row, and a row with none after the row before
//   • its words by its t: "s" the shared string its <v> numbers (every <t>
//     of the <si>, phonetic runs aside); "inlineStr" every <t> of its <is>;
//     "str" and "e" its <v> as written; "b" TRUE or FALSE; a number (no t,
//     or "n") its <v> as written — a formula's cached <v>, its expression
//     left out — unless its style's number format is a date's, when it is
//     the ISO date: yyyy-MM-dd for a whole number of days, HH:mm:ss for a
//     time under a day, yyyy-MM-ddTHH:mm:ss otherwise, to the second
//   • a date format is a built-in one, 14 to 22 or 45 to 47, or a format of
//     the workbook's own with a d or a y in it outside quotes and brackets;
//     day 0 is 1899-12-30 (1904-01-01 for a workbook with date1904), and in
//     the 1900 system a day before 61 is one later, as Excel counts 1900 a
//     leap year
//   • each cell's spaces are trimmed; a merged range keeps its words in its
//     top-left cell, the rest empty
//   • nothing past row 500 or column 50 is read
//
// DataGrid.fromRows takes a sheet's cells into the grid as Import CSV does,
// with the same note of what was left out.

import Foundation

enum XlsxReader {

    static let maxRows = 500
    static let maxColumns = 50

    /// One sheet: its name and its rows, every row as wide as the widest.
    struct Sheet: Equatable {
        var name: String
        var cells: [[String]]
    }

    /// The workbook's sheets, in its order; empty for a file that is not a
    /// workbook.
    static func read(_ data: Data) -> [Sheet] {
        guard let zip = try? ZipStore.Reader(data: data, inflating: true),
              let workbook = document(zip.file("xl/workbook.xml")) else { return [] }
        let shared = sharedStrings(document(zip.file("xl/sharedStrings.xml")))
        let styles = dateStyles(document(zip.file("xl/styles.xml")))
        let base1904 = first(workbook, "workbookPr").map { ["1", "true"].contains($0.attributes["date1904"] ?? "") } ?? false
        var targets: [String: String] = [:]
        if let rels = document(zip.file("xl/_rels/workbook.xml.rels")) {
            for rel in descendants(rels, "Relationship") {
                guard let id = rel.attributes["Id"], let target = rel.attributes["Target"] else { continue }
                targets[id] = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            }
        }
        var out: [Sheet] = []
        for (index, sheet) in descendants(workbook, "sheet").enumerated() {
            let rid = sheet.attributes.first { $0.key == "id" || $0.key.hasSuffix(":id") }?.value
            let path = rid.flatMap { targets[$0] } ?? "xl/worksheets/sheet\(index + 1).xml"
            guard let root = document(zip.file(path)) else { continue }
            let name = sheet.attributes["name"] ?? "Sheet \(index + 1)"
            out.append(Sheet(name: name, cells: cells(root, shared: shared, dates: styles, base1904: base1904)))
        }
        return out
    }

    // MARK: the parts

    private static func document(_ data: Data?) -> SvgImport.Node? {
        guard let data, !data.isEmpty else { return nil }
        return SvgImport.parse(String(decoding: data, as: UTF8.self))
    }

    /// Every element named `name` under `node`, in document order.
    static func descendants(_ node: SvgImport.Node, _ name: String) -> [SvgImport.Node] {
        var found: [SvgImport.Node] = []
        for child in node.children {
            if child.name == name { found.append(child) }
            found += descendants(child, name)
        }
        return found
    }

    private static func first(_ node: SvgImport.Node, _ name: String) -> SvgImport.Node? {
        for child in node.children {
            if child.name == name { return child }
            if let deeper = first(child, name) { return deeper }
        }
        return nil
    }

    /// A string item's words: every <t> in it, a phonetic run's aside.
    private static func words(_ node: SvgImport.Node) -> String {
        var out = ""
        for child in node.children where child.name != "rPh" {
            out += child.name == "t" ? child.text : words(child)
        }
        return out
    }

    private static func sharedStrings(_ root: SvgImport.Node?) -> [String] {
        guard let root else { return [] }
        return root.children.filter { $0.name == "si" }.map(words)
    }

    /// The style indices whose number format is a date's.
    private static func dateStyles(_ root: SvgImport.Node?) -> Set<Int> {
        guard let root else { return [] }
        var custom: [Int: String] = [:]
        for format in descendants(root, "numFmt") {
            if let id = format.attributes["numFmtId"].flatMap(Int.init) { custom[id] = format.attributes["formatCode"] ?? "" }
        }
        guard let xfs = first(root, "cellXfs") else { return [] }
        var dates = Set<Int>()
        for (index, xf) in xfs.children.filter({ $0.name == "xf" }).enumerated() {
            guard let id = xf.attributes["numFmtId"].flatMap(Int.init) else { continue }
            if isDateFormat(id, code: custom[id]) { dates.insert(index) }
        }
        return dates
    }

    /// Whether number format `id` — `code` when it is the workbook's own —
    /// shows a date or a time.
    static func isDateFormat(_ id: Int, code: String?) -> Bool {
        if (14...22).contains(id) || (45...47).contains(id) { return true }
        guard let code else { return false }
        var plain = ""
        var quoted = false, bracket = false
        for ch in code {
            if ch == "\"" { quoted.toggle(); continue }
            if quoted { continue }
            if ch == "[" { bracket = true; continue }
            if ch == "]" { bracket = false; continue }
            if !bracket { plain.append(ch) }
        }
        let lower = plain.lowercased()
        return lower.contains("d") || lower.contains("y")
    }

    // MARK: a sheet

    private static func cells(_ root: SvgImport.Node, shared: [String], dates: Set<Int>,
                              base1904: Bool) -> [[String]] {
        var grid: [[String]] = []
        var lastRow = -1
        for row in descendants(root, "row") {
            let r = row.attributes["r"].flatMap(Int.init).map { $0 - 1 } ?? lastRow + 1
            lastRow = r
            guard r >= 0, r < maxRows else { continue }
            var lastColumn = -1
            for cell in row.children where cell.name == "c" {
                let c = cell.attributes["r"].flatMap { place(of: $0)?.column } ?? lastColumn + 1
                lastColumn = c
                guard c >= 0, c < maxColumns else { continue }
                let text = value(cell, shared: shared, dates: dates, base1904: base1904)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                while grid.count <= r { grid.append([]) }
                while grid[r].count <= c { grid[r].append("") }
                grid[r][c] = text
            }
        }
        return DataGrid.padded(grid)
    }

    /// A cell's words, as its type says.
    private static func value(_ cell: SvgImport.Node, shared: [String], dates: Set<Int>, base1904: Bool) -> String {
        let v = cell.children.first { $0.name == "v" }?.text ?? ""
        switch cell.attributes["t"] ?? "n" {
        case "s":
            guard let i = Int(v.trimmingCharacters(in: .whitespaces)), shared.indices.contains(i) else { return "" }
            return shared[i]
        case "inlineStr":
            return cell.children.first { $0.name == "is" }.map(words) ?? ""
        case "b":
            return v.trimmingCharacters(in: .whitespaces) == "1" ? "TRUE" : "FALSE"
        case "str", "e":
            return v
        default:
            let style = cell.attributes["s"].flatMap(Int.init) ?? 0
            guard dates.contains(style), let serial = Double(v.trimmingCharacters(in: .whitespaces)) else { return v }
            return isoDate(serial, base1904: base1904)
        }
    }

    /// "C5" as its column and row from 0.
    static func place(of ref: String) -> (column: Int, row: Int)? {
        var column = 0
        var digits = ""
        var letters = 0
        for ch in ref.uppercased() {
            if let ascii = ch.asciiValue, ascii >= 65, ascii <= 90, digits.isEmpty {
                column = column * 26 + Int(ascii - 64)
                letters += 1
            } else if ch.isASCII, ch.isNumber {
                digits.append(ch)
            } else {
                return nil
            }
        }
        guard letters > 0, let row = Int(digits), row > 0 else { return nil }
        return (column - 1, row - 1)
    }

    /// A date serial as ISO: the day alone for a whole day, the time alone
    /// under a day, else both, to the second.
    static func isoDate(_ serial: Double, base1904: Bool) -> String {
        let seconds = Int((serial * 86400).rounded())
        var days = Int((Double(seconds) / 86400).rounded(.down))
        let clock = seconds - days * 86400
        let time = String(format: "%02d:%02d:%02d", clock / 3600, clock / 60 % 60, clock % 60)
        if days == 0 && clock > 0 && !base1904 { return time }
        // Days since 1970-01-01.
        if base1904 {
            days -= 24107
        } else {
            days -= days < 61 ? 25568 : 25569
        }
        let (y, m, d) = civil(days)
        let date = String(format: "%04d-%02d-%02d", y, m, d)
        return clock == 0 ? date : date + "T" + time
    }

    /// The year, month and day `days` after 1970-01-01, proleptic
    /// Gregorian (Howard Hinnant's civil_from_days).
    static func civil(_ days: Int) -> (Int, Int, Int) {
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
}
