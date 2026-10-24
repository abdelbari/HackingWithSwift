// The table designs (tables.json) and restyling a table with one, held to
// the fixture both phones share (Fixtures/table-restyle.json), as the
// Android twin's TableDesignsTest.

import XCTest
@testable import Canvia

final class TableDesignsTests: XCTestCase {

    private var heightFor: (Element) -> Double {
        { el in Double((el.text ?? "").components(separatedBy: "\n").count) * 20 }
    }

    private func tableId(_ els: [Element]) -> String {
        els.lazy.compactMap { $0.table?.id }.first ?? ""
    }

    private func cell(_ els: [Element], _ type: ElementType, _ row: Int, _ col: Int) -> Element {
        els.first { $0.type == type && $0.table?.row == row && $0.table?.col == col } ?? Element.shape("rect")
    }

    /// Each cell's [row, col, rowSpan, colSpan, words], in rows then columns.
    private func texts(_ els: [Element]) -> [[String]] {
        els.filter { $0.type == .text && $0.table != nil }
            .sorted { a, b in (a.table?.row ?? 0, a.table?.col ?? 0) < (b.table?.row ?? 0, b.table?.col ?? 0) }
            .map { el in
                let c = el.table ?? TableCell(id: "", row: 0, col: 0)
                return ["\(c.row)", "\(c.col)", "\(c.rowSpan)", "\(c.colSpan)", el.text ?? ""]
            }
    }

    private func sample() -> [Element] {
        DataGraphics.table(TableDesigns.sample, in: CGRect(x: 0, y: 0, width: 600, height: 400), accent: "#1f2430",
                           heightFor: heightFor)
    }

    func testTheFileHasSixteenDesignsWithEveryFieldRead() {
        let all = TableDesigns.all
        XCTAssertEqual(all.count, 16)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertFalse(all.contains { $0.id == "table" })
        XCTAssertTrue(all.allSatisfy { Tables.borderModes.contains($0.borders) && $0.borders != "vertical" })
        XCTAssertEqual(all.first?.id, "classic")
        XCTAssertNotNil(TableDesigns.design("night"))
        XCTAssertNil(TableDesigns.design("nope"))
    }

    /// Shared with the Android twin's TableDesignsTest.
    func testRestylingWithEveryDesignKeepsEachCellsWordsAndSpans() throws {
        let root = try SharedFixture.object("table-restyle")
        let rows = try XCTUnwrap(root["rows"] as? [[String]])
        let merge = try XCTUnwrap(root["merge"] as? [[Int]])
        let accent = try XCTUnwrap(root["accent"] as? String)
        let accent2 = try XCTUnwrap(root["accent2"] as? String)
        let want = try XCTUnwrap(root["cells"] as? [[Any]]).map { c in
            c.map { v -> String in (v as? NSNumber).map { "\($0.intValue)" } ?? (v as? String ?? "") }
        }
        let headers = try XCTUnwrap(root["headerFill"] as? [String: String])
        let made = DataGraphics.table(rows, in: CGRect(x: 0, y: 0, width: 600, height: 400), accent: "#1f2430",
                                      heightFor: heightFor)
        let id = tableId(made)
        let places = Set(merge.map { cell(made, .text, $0[0], $0[1]) }.compactMap(\.table))
        let merged = try XCTUnwrap(DataGraphics.mergingTableCells(made, id: id, cells: places, heightFor: heightFor))
        XCTAssertEqual(texts(merged), want)
        for design in TableDesigns.all {
            let styled = Tables.withDesign(merged, id: id, design: design, accent: accent, accent2: accent2,
                                           heightFor: heightFor) ?? merged
            XCTAssertEqual(texts(styled), want, design.id)
            XCTAssertEqual(Tables.designOf(DataGraphics.tableMembers(styled, id: id)), design.id)
            XCTAssertEqual(Tables.borderMode(styled, id: id), design.borders)
            if let header = headers[design.id] {
                XCTAssertEqual(cell(styled, .shape, 0, 0).fill?.color, header, design.id)
            }
            // Column widths are kept.
            XCTAssertEqual(DataGraphics.tableColumnWidths(styled, id: id), DataGraphics.tableColumnWidths(merged, id: id))
        }
    }

    func testADesignsBandsBordersAndFontsGoOnTheCells() throws {
        let made = sample()
        let id = tableId(made)
        // A word in a font of its own: a design's font takes it, as a font for the box does.
        let word = cell(made, .text, 1, 1)
        let spanned = made.map { el -> Element in
            guard el.id == word.id else { return el }
            var out = el
            out.setSpans([TextSpan(start: 0, end: 1, color: "#ff0000", font: "lora")])
            return out
        }
        let mono = try XCTUnwrap(Tables.withDesign(spanned, id: id, design: try XCTUnwrap(TableDesigns.design("mono")),
                                                   accent: "#7c3aed", accent2: "#0ea5e9", heightFor: heightFor))
        XCTAssertEqual(cell(mono, .shape, 0, 0).fill?.color, "#111111")
        XCTAssertEqual(cell(mono, .shape, 2, 0).fill?.color, "#f4f4f5")
        XCTAssertEqual(cell(mono, .shape, 1, 0).fill?.color, "#ffffff")
        XCTAssertEqual(DataGraphics.tableBands(mono, id: id), "#f4f4f5")
        XCTAssertEqual(cell(mono, .text, 1, 1).fontFamily, "roboto-mono")
        XCTAssertEqual(cell(mono, .text, 1, 1).liveSpans, [TextSpan(start: 0, end: 1, color: "#ff0000")])
        XCTAssertEqual(cell(mono, .text, 0, 1).fontWeight, 700)
        // A dark body keeps no bands, which stripe with white.
        let night = try XCTUnwrap(Tables.withDesign(mono, id: id, design: try XCTUnwrap(TableDesigns.design("night")),
                                                    accent: "#7c3aed", accent2: "#0ea5e9", heightFor: heightFor))
        XCTAssertNil(DataGraphics.tableBands(night, id: id))
        XCTAssertEqual(cell(night, .shape, 2, 0).fill?.color, "#1e293b")
        // Outline strokes the outside only, in the accent.
        let outline = try XCTUnwrap(Tables.withDesign(night, id: id, design: try XCTUnwrap(TableDesigns.design("outline")),
                                                      accent: "#7c3aed", accent2: "#0ea5e9", heightFor: heightFor))
        XCTAssertEqual(cell(outline, .shape, 1, 1).stroke, "#7c3aed")
        XCTAssertEqual(cell(outline, .shape, 1, 1).sides, "")
        XCTAssertEqual(cell(outline, .shape, 0, 0).sides, "tl")
        // A hairline stays faint.
        let classic = try XCTUnwrap(Tables.withDesign(outline, id: id, design: try XCTUnwrap(TableDesigns.design("classic")),
                                                      accent: "#7c3aed", accent2: "#0ea5e9", heightFor: heightFor))
        XCTAssertEqual(cell(classic, .shape, 1, 1).stroke, "#00000022")
    }

    func testAThemeGivesADesignedTableItsDesignAgainInTheNewColours() throws {
        let made = sample()
        let id = tableId(made)
        let classic = try XCTUnwrap(Tables.withDesign(made, id: id, design: try XCTUnwrap(TableDesigns.design("classic")),
                                                      accent: "#7c3aed", accent2: "#0ea5e9", heightFor: heightFor))
        let again = Tables.redesigned(classic, accent: "#dc2626", accent2: "#16a34a", heightFor: heightFor)
        XCTAssertEqual(cell(again, .shape, 0, 0).fill?.color, "#dc2626")
        // A table with no design is left as it is.
        XCTAssertEqual(Tables.redesigned(made, accent: "#dc2626", accent2: "#16a34a", heightFor: heightFor), made)
    }

    func testTheAccentsAreTheBrandsFirstTwoColoursElseThePalettes() {
        let both = TableDesigns.accents(brand: ["#111111", "#222222", "#333333"], palette: ["#aaaaaa"])
        XCTAssertEqual([both.0, both.1], ["#111111", "#222222"])
        let one = TableDesigns.accents(brand: ["#111111"], palette: ["#aaaaaa", "#bbbbbb"])
        XCTAssertEqual([one.0, one.1], ["#111111", "#111111"])
        let own = TableDesigns.accents(brand: [], palette: ["#aaaaaa", "#bbbbbb"])
        XCTAssertEqual([own.0, own.1], ["#aaaaaa", "#bbbbbb"])
    }

    func testDesignsAreFoundByName() {
        let hits = ElementSearch.results("striped table")
        XCTAssertEqual(hits.first?.kind, .table)
        XCTAssertEqual(hits.first?.id, "striped")
        XCTAssertTrue(ElementSearch.results("night").contains { $0.kind == .table && $0.id == "night" })
    }
}
