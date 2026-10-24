// A spreadsheet's range read off the clipboard, held to the cases both
// phones share (Fixtures/clipboard-tables.json: Excel HTML, Sheets HTML and
// Sheets TSV), and laid into a table — the Android twin's
// ClipboardTableTest.

import XCTest
@testable import Canvia

final class ClipboardTableTests: XCTestCase {

    private var heightFor: (Element) -> Double {
        { el in Double((el.text ?? "").components(separatedBy: "\n").count) * 20 }
    }

    /// Shared with the Android twin: each case reads to its rows (none for
    /// null) and its merges.
    func testTheSharedCasesReadAsBothPhonesReadThem() throws {
        let root = try SharedFixture.object("clipboard-tables")
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8)
        for c in cases {
            let name = c["name"] as? String ?? ""
            let block = ClipboardTable.parse(text: c["text"] as? String, html: c["html"] as? String)
            if let rows = c["rows"] as? [[String]] {
                let got = try XCTUnwrap(block, name)
                XCTAssertEqual(got.rows, rows, name)
                let merges = (c["merges"] as? [[Int]] ?? []).map {
                    ClipboardTable.Merge(row: $0[0], col: $0[1], rowSpan: $0[2], colSpan: $0[3])
                }
                XCTAssertEqual(got.merges, merges, name)
            } else {
                XCTAssertNil(block, name)
            }
        }
    }

    func testEntitiesAreDecodedAndAnUnknownOneKept() {
        XCTAssertEqual(ClipboardTable.decode("a&amp;b &lt;c&gt; &#233;&#x2615; &bogus; &nbsp;"), "a&b <c> é☕ &bogus;  ")
    }

    func testABlockBecomesATableWithItsMergesKept() throws {
        let block = try XCTUnwrap(ClipboardTable.parse(
            text: nil, html: "<table><tr><td colspan=2>Head</td></tr><tr><td>a</td><td>b</td></tr></table>"))
        let made = ClipboardTable.table(block, in: CGRect(x: 0, y: 0, width: 400, height: 300), accent: "#1f2430",
                                        heightFor: heightFor)
        let rects = made.filter { $0.type == .shape }
        XCTAssertEqual(rects.count, 3)
        XCTAssertEqual(rects.first { $0.table?.row == 0 }?.table?.colSpan, 2)
    }

    func testARangePastedIntoAGridGrowsIt() {
        let block = ClipboardTable.Block(rows: [["x", "y"], ["z", "w"]])
        let grid = [["a", "b"], ["c", "d"]]
        XCTAssertEqual(ClipboardTable.pastedInto(grid, row: 1, col: 1, block: block),
                       [["a", "b", ""], ["c", "x", "y"], ["", "z", "w"]])
    }
}
