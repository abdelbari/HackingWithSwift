// A range of cells copied from a spreadsheet — Google Sheets, Excel,
// Numbers — read off the clipboard: the Android twin's ClipboardTable, rule
// for rule, with the same fixtures (Fixtures/clipboard-tables.json).
//
// The HTML comes first: its first <table>, a row per <tr>, a cell per <td>
// or <th>, each cell placed in the first place of its row no cell above
// already covers, as a browser places them. A cell's colspan and rowspan
// are honoured up to TableCell.maxSpan, and a rowspan no further than the
// table's last row. Its words are its text with the tags taken out, <br> a
// line break, runs of spaces and source line breaks one space, the named
// entities amp, lt, gt, quot, apos and nbsp and numbered ones decoded, then
// trimmed.
//
// With no table in the HTML, the plain text is read as tab-separated values
// when it has at least two lines and at least two columns: a line per row, a
// tab between cells, a cell opened with a double quote reaching to its
// closing quote (tabs and line breaks inside it kept, a doubled quote one
// quote), as Sheets and Excel write a cell with a line break in it. Blank
// lines at the end are left out.
//
// Every row is padded with blank cells to the widest; anything else is no
// block (nil), and the paste goes on as words.

import CoreGraphics
import Foundation

enum ClipboardTable {

    /// A merged cell of the block: its first row and column, and how many
    /// rows and columns it covers.
    struct Merge: Equatable {
        var row: Int
        var col: Int
        var rowSpan: Int
        var colSpan: Int
    }

    /// The cells read: `rows` of words, every row as long as the widest, a
    /// place a merged cell covers past its first blank; and the merged
    /// cells, in rows then columns.
    struct Block: Equatable {
        var rows: [[String]]
        var merges: [Merge] = []

        var rowCount: Int { rows.count }
        var columnCount: Int { rows.map(\.count).max() ?? 0 }
    }

    /// The block `text` and `html` hold, or nil when they hold none.
    static func parse(text: String?, html: String?) -> Block? {
        if let html, let block = fromHtml(html) { return block }
        return text.flatMap(fromTabs)
    }

    // MARK: HTML

    private static func regex(_ pattern: String, dotAll: Bool = true) -> NSRegularExpression {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotAll { options.insert(.dotMatchesLineSeparators) }
        // The patterns are fixed and known to compile.
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let tableRegex = regex(#"<table\b[^>]*>(.*?)</table\s*>"#)
    private static let rowRegex = regex(#"<tr\b[^>]*>(.*?)(?=<tr\b|</table|$)"#)
    private static let cellRegex = regex(#"<(td|th)\b([^>]*)>(.*?)(?=<td\b|<th\b|</tr|$)"#)
    private static let commentRegex = regex(#"<!--.*?-->"#)
    private static let breakRegex = regex(#"<br\b[^>]*>"#)
    private static let tagRegex = regex(#"<[^>]*>"#)
    private static let spacesRegex = regex("[ \\t\\r\\n\\u000C]+")
    private static let entityRegex = regex("&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);", dotAll: false)

    /// The matches of `re` in `s`, each its groups' text ("" for a group
    /// that took part in none).
    private static func captured(_ re: NSRegularExpression, in s: String) -> [[String]] {
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    /// `s` with every match of `re` replaced by what `with` makes of its
    /// groups.
    private static func replacing(_ re: NSRegularExpression, in s: String, with: ([String]) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let parts = (0..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            out += with(parts)
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    /// The block in `html`'s first table, or nil when it has none with a
    /// cell.
    static func fromHtml(_ html: String) -> Block? {
        let bare = replacing(commentRegex, in: html) { _ in "" }
        guard let table = captured(tableRegex, in: bare).first?[1] else { return nil }
        let rawRows = captured(rowRegex, in: table).map { row in
            captured(cellRegex, in: row[1]).map { (attributes: $0[2], inner: $0[3]) }
        }
        guard rawRows.contains(where: { !$0.isEmpty }) else { return nil }
        var placed: [[Int]: String] = [:]
        var covered = Set<[Int]>()
        var merges: [Merge] = []
        var width = 0
        for (r, cells) in rawRows.enumerated() {
            var c = 0
            for cell in cells {
                while covered.contains([r, c]) { c += 1 }
                let colSpan = span(cell.attributes, "colspan")
                let rowSpan = min(span(cell.attributes, "rowspan"), rawRows.count - r)
                placed[[r, c]] = words(cell.inner)
                for dr in 0..<rowSpan {
                    for dc in 0..<colSpan { covered.insert([r + dr, c + dc]) }
                }
                if rowSpan > 1 || colSpan > 1 { merges.append(Merge(row: r, col: c, rowSpan: rowSpan, colSpan: colSpan)) }
                c += colSpan
                width = max(width, c)
            }
        }
        // A cell running past every <tr>'s own cells still widens the block.
        width = max(width, (covered.map { $0[1] + 1 }.max() ?? 0))
        guard width > 0 else { return nil }
        let rows = rawRows.indices.map { r in (0..<width).map { c in placed[[r, c]] ?? "" } }
        return Block(rows: rows, merges: merges.sorted { ($0.row, $0.col) < ($1.row, $1.col) })
    }

    /// A cell's colspan or rowspan: a whole number from 1 to
    /// TableCell.maxSpan, 1 when it is missing or anything else.
    private static func span(_ attributes: String, _ name: String) -> Int {
        let re = regex("\\b\(name)\\s*=\\s*[\"']?\\s*(\\d+)", dotAll: false)
        guard let digits = captured(re, in: attributes).first?[1], let n = Int(digits.prefix(7)) else { return 1 }
        return min(max(n, 1), TableCell.maxSpan)
    }

    /// A cell's words: tags out, <br> a line break, spaces run together,
    /// entities decoded, each line trimmed.
    private static func words(_ inner: String) -> String {
        let marked = replacing(breakRegex, in: inner) { _ in "\u{0}" }
        let bare = replacing(tagRegex, in: marked) { _ in "" }
        let spaced = replacing(spacesRegex, in: bare) { _ in " " }
        return decode(spaced).components(separatedBy: "\u{0}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `s` with the named entities amp, lt, gt, quot, apos and nbsp, and
    /// numbered ones, decoded; an unknown one left as it is. A non-breaking
    /// space is a space.
    static func decode(_ s: String) -> String {
        replacing(entityRegex, in: s) { m in
            let name = m[1]
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                return Int(name.dropFirst(2), radix: 16).flatMap(codePoint) ?? m[0]
            }
            if name.hasPrefix("#") { return Int(name.dropFirst()).flatMap(codePoint) ?? m[0] }
            switch name.lowercased() {
            case "amp": return "&"
            case "lt": return "<"
            case "gt": return ">"
            case "quot": return "\""
            case "apos": return "'"
            case "nbsp": return " "
            default: return m[0]
            }
        }
    }

    private static func codePoint(_ n: Int) -> String? {
        if n == 0xA0 { return " " }
        guard n >= 1, n <= 0x10FFFF, !(0xD800...0xDFFF).contains(n), let scalar = Unicode.Scalar(UInt32(n)) else {
            return nil
        }
        return String(Character(scalar))
    }

    // MARK: tab-separated values

    /// The block in tab-separated `text`, or nil unless it has at least two
    /// rows and at least two columns.
    static func fromTabs(_ text: String) -> Block? {
        let s = Array(text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").unicodeScalars)
        var rows: [[String]] = []
        var row: [String] = []
        var cell = String.UnicodeScalarView()
        var i = 0
        var quoted = false
        var atStart = true
        while i < s.count {
            let ch = s[i]
            if quoted {
                if ch == "\"" {
                    if i + 1 < s.count && s[i + 1] == "\"" {
                        cell.append("\"")
                        i += 2
                        continue
                    }
                    quoted = false
                } else {
                    cell.append(ch)
                }
                i += 1
                continue
            }
            switch ch {
            case "\"":
                if atStart { quoted = true } else { cell.append(ch) }
            case "\t":
                row.append(String(cell))
                cell = String.UnicodeScalarView()
                atStart = true
                i += 1
                continue
            case "\n":
                row.append(String(cell))
                cell = String.UnicodeScalarView()
                rows.append(row)
                row = []
                atStart = true
                i += 1
                continue
            default:
                cell.append(ch)
            }
            atStart = false
            i += 1
        }
        row.append(String(cell))
        rows.append(row)
        while let last = rows.last, last.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.removeLast()
        }
        let width = rows.map(\.count).max() ?? 0
        guard rows.count >= 2, width >= 2 else { return nil }
        return Block(rows: rows.map { r in
            r.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } + Array(repeating: "", count: width - r.count)
        })
    }

    // MARK: into a table

    /// `block` as a new table in `frame` (DataGraphics.table, its first row
    /// the header in `accent`), each of its merges made a merged cell
    /// (DataGraphics.mergingTableCells); empty when it has no cell.
    static func table(_ block: Block, in frame: CGRect, accent: String,
                      heightFor: (Element) -> Double) -> [Element] {
        var made = DataGraphics.table(block.rows, in: frame, accent: accent, heightFor: heightFor)
        guard let id = made.lazy.compactMap({ $0.table?.id }).first else { return made }
        for m in block.merges {
            var places = Set<TableCell>()
            for r in m.row..<(m.row + m.rowSpan) {
                for c in m.col..<(m.col + m.colSpan) { places.insert(TableCell(id: id, row: r, col: c)) }
            }
            made = DataGraphics.mergingTableCells(made, id: id, cells: places, heightFor: heightFor) ?? made
        }
        return made
    }

    /// `grid` — a table's cells as DataGraphics.tableGrid reads them — with
    /// `block` written into it from `row`, `col` on, the grid grown with
    /// blank rows and columns as far as it reaches. Merges in the block are
    /// not made in a table that already exists: each of its places takes
    /// its own words.
    static func pastedInto(_ grid: [[String]], row: Int, col: Int, block: Block) -> [[String]] {
        let width = max(grid.map(\.count).max() ?? 0, col + block.columnCount)
        let height = max(grid.count, row + block.rowCount)
        return (0..<height).map { r in
            (0..<width).map { c in
                if r >= row, c >= col, r - row < block.rows.count, c - col < block.rows[r - row].count {
                    return block.rows[r - row][c - col]
                }
                return r < grid.count && c < grid[r].count ? grid[r][c] : ""
            }
        }
    }
}
