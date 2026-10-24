// Check spelling's writing rules (Proofing) and their fixes, over the
// shared Fixtures/proofing_rules.json — the Android twin's
// ProofingRulesTest, row for row.

import XCTest
@testable import Canvia

final class ProofingRulesTests: XCTestCase {

    /// Shared rows: every text gives exactly its findings on both phones.
    func testTheSharedRulesFindWhatTheFixtureSays() throws {
        let rows = try XCTUnwrap(try SharedFixture.object("proofing_rules")["rows"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 30)
        for row in rows {
            let text = try XCTUnwrap(row["text"] as? String)
            let language = row["language"] as? String
            let typography = row["typography"] as? Bool ?? true
            let want = try XCTUnwrap(row["findings"] as? [[String: Any]]).map { f in
                Proofing.Finding(kind: f["kind"] as? String ?? "", start: f["start"] as? Int ?? -1,
                                 end: f["end"] as? Int ?? -1, replacement: f["replacement"] as? String)
            }
            XCTAssertEqual(Proofing.findings(text, language: language, typography: typography), want, text)
        }
    }

    func testEveryKindIsInTheOrderFindingsWinByAndTypographySwitchesThreeOff() {
        XCTAssertEqual(Proofing.rules,
                       ["spaceBefore", "spaces", "repeat", "capital", "article", "quotes", "ellipsis", "range", "unbalanced"])
        XCTAssertEqual(Proofing.typography, ["quotes", "ellipsis", "range"])
        XCTAssertEqual(Proofing.typographySetting, "proofTypography")
        let text = "Pages 10-20... \"ok\""
        XCTAssertEqual(Set(Proofing.findings(text, language: "en").map(\.kind)), ["range", "ellipsis", "quotes", "capital"])
        XCTAssertFalse(Proofing.findings(text, language: "en", typography: false).contains { Proofing.typography.contains($0.kind) })
        // Capitals are for the languages that start sentences with them.
        XCTAssertTrue(Proofing.findings("hallo wereld", language: "nl").isEmpty)
        XCTAssertEqual(Proofing.findings("hallo welt", language: "de-DE").map(\.kind), ["capital"])
        XCTAssertEqual(Proofing.findings("hello", language: nil).map(\.kind), ["capital"])
    }

    private func boxDesign(_ text: String, _ change: (inout Element) -> Void = { _ in }) -> Design {
        var d = Design(title: "proof", width: 600, height: 600)
        var el = Element.text(text)
        el.id = "t"
        change(&el)
        d.pages[0].elements = [el]
        return d
    }

    func testAFindingIsPlacedInTheStoredWordsAndFixedWithTheWordsStylingKept() throws {
        let d = boxDesign("**the the** cat")
        let found = Proofreader.writing(in: d, language: "en", typography: true)
        let repeated = try XCTUnwrap(found.first { $0.rule == Proofing.repeated })
        XCTAssertEqual(repeated.word, " the")
        XCTAssertEqual(repeated.range, NSRange(location: 5, length: 4))
        XCTAssertEqual(repeated.suggestions, [""])
        let fixed = try XCTUnwrap(Proofreader.fixed(d, repeated, with: ""))
        XCTAssertEqual(fixed.pages[0].elements[0].text, "**the** cat")
        let capital = try XCTUnwrap(found.first { $0.rule == Proofing.capital })
        XCTAssertEqual(Proofreader.fixed(d, capital, with: "T")?.pages[0].elements[0].text, "**The the** cat")
    }

    func testAFixMovesTheBoxsWordColoursWithIt() throws {
        let d = boxDesign("Wait , red") { $0.setSpans([TextSpan(start: 7, end: 10, color: "#ff0000")]) }
        let space = try XCTUnwrap(Proofreader.writing(in: d, language: "en", typography: true).first { $0.rule == Proofing.spaceBefore })
        let el = try XCTUnwrap(Proofreader.fixed(d, space, with: "")?.pages[0].elements[0])
        XCTAssertEqual(el.text, "Wait, red")
        XCTAssertEqual(el.liveSpans, [TextSpan(start: 6, end: 9, color: "#ff0000")])
    }

    func testFixAllOfAKindChangesEveryOneInOneDesign() throws {
        let d = boxDesign("He said \"hi\" and \"bye\"")
        let quotes = Proofreader.writing(in: d, language: "en", typography: true).filter { $0.rule == Proofing.quotes }
        XCTAssertEqual(quotes.count, 4)
        let all = try XCTUnwrap(Proofreader.fixedAll(d, quotes))
        XCTAssertEqual(all.pages[0].elements[0].text, "He said “hi” and “bye”")
        // Nothing left to fix is no change at all.
        XCTAssertNil(Proofreader.fixedAll(all, quotes))
    }

    func testAnUnclosedBracketHasNoFix() throws {
        let found = Proofreader.writing(in: boxDesign("Note (see below"), language: "en", typography: true)
        let open = try XCTUnwrap(found.first { $0.rule == Proofing.unbalanced })
        XCTAssertTrue(open.suggestions.isEmpty)
        XCTAssertEqual(open.word, "(")
    }

    func testADocsBlocksAndCellsAreCheckedAndFixedWhereTheyAre() throws {
        let doc = Docs.withBlocks(Docs.started("Plan"), [
            DocBlock(id: "h", type: Docs.h1, text: "Plan"),
            DocBlock(id: "p", type: Docs.p, text: "the the plan"),
            DocBlock(id: "t", type: Docs.table, table: DocTable(rows: [["Wait , now"]], header: false)),
        ])
        let items = Proofreader.checkables(in: doc)
        XCTAssertEqual(items.map(\.plain), ["Plan", "the the plan", "Wait , now"])
        XCTAssertTrue(items.allSatisfy { $0.kind == .doc })
        XCTAssertEqual(items.map(\.row), [nil, nil, 0])
        let found = Proofreader.writing(in: doc, language: "en", typography: true)
        XCTAssertEqual(found.map(\.blockId), ["p", "p", "t"])
        XCTAssertEqual(Proofreader.docPlace(doc, blockId: "p"), 2)
        let fixed = try XCTUnwrap(Proofreader.fixedAll(doc, found))
        let blocks = Docs.blocks(fixed)
        XCTAssertEqual(blocks[1].text, "The plan")
        XCTAssertEqual(Docs.tableRows(blocks[2]).rows, [["Wait, now"]])
        XCTAssertEqual(FindReplaceSheet.docPlace(2), "Doc, paragraph 2")
    }

    func testAMisspellingInADocIsFixedInItsBlock() throws {
        let doc = Docs.withBlocks(Docs.started("Plan"), [DocBlock(id: "p", type: Docs.p, text: "Teh **plan**")])
        let item = try XCTUnwrap(Proofreader.checkables(in: doc).first)
        XCTAssertEqual(item.blockId, "p")
        let miss = Proofreader.Misspelling(pageIndex: 0, elementId: "", range: NSRange(location: 0, length: 3), word: "Teh",
                                           suggestions: ["The"], plain: NSRange(location: 0, length: 3), kind: .doc,
                                           blockId: "p")
        XCTAssertEqual(Docs.blocks(try XCTUnwrap(Proofreader.fixed(doc, miss, with: "The"))).first?.text, "The **plan**")
        XCTAssertEqual(ProofreadSheet.change(miss), "“Teh” → “The”")
    }
}
