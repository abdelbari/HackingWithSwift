// Colour vision deficiency: the Machado (2009) matrices at severity 1.0 and
// greyscale, applied in linear sRGB, and the colourVision findings of Check
// accessibility — the same rows and ids as the Android twin's
// ColourVisionTest.

import XCTest
@testable import Canvia

final class ColourVisionTests: XCTestCase {

    // MARK: the matrices

    /// Each kind's output for the same inputs on both phones.
    func testSimulatedColoursMatchTheFixture() {
        let rows: [(String, [String])] = [
            ("#ff0000", ["#6d5f00", "#a39000", "#ff000f", "#7f7f7f"]),
            ("#00ff00", ["#ffe500", "#efd63a", "#00f7d9", "#dcdcdc"]),
            ("#0000ff", ["#0059ff", "#003dfb", "#006b96", "#4c4c4c"]),
            ("#e53935", ["#6e6332", "#98892e", "#fc003a", "#7b7b7b"]),
            ("#43a047", ["#a3923f", "#978a4e", "#329c8c", "#8d8d8d"]),
            ("#ffffff", ["#ffffff", "#ffffff", "#ffffff", "#ffffff"]),
        ]
        for (hex, seen) in rows {
            XCTAssertEqual(ColourVision.simulated.map { ColourVision.simulate(hex, $0) }, seen, hex)
            XCTAssertEqual(ColourVision.simulate(hex, .typical), hex)
        }
        XCTAssertEqual(ColourVision.simulate("not a colour", .protanopia), "not a colour")
    }

    func testTheRowsKeysAndWords() {
        XCTAssertEqual(ColourVision.Sight.allCases.map(\.rawValue),
                       ["typical", "protanopia", "deuteranopia", "tritanopia", "achromatopsia"])
        XCTAssertEqual(ColourVision.Sight.allCases.map(\.label),
                       ["Typical", "Red-blind", "Green-blind", "Blue-blind", "Greyscale"])
        XCTAssertEqual(ColourVision.simulated, [.protanopia, .deuteranopia, .tritanopia, .achromatopsia])
        XCTAssertEqual(ColourVision.announcement(.typical), "Showing the design as it is")
        XCTAssertEqual(ColourVision.announcement(.tritanopia), "Showing the design as seen Blue-blind")
    }

    func testDeltaEIsCIE76() {
        XCTAssertEqual(ColourVision.deltaE("#e53935", "#43a047"), 111.24, accuracy: 0.01)
        XCTAssertEqual(ColourVision.deltaE("#123456", "#123456"), 0, accuracy: 1e-9)
    }

    // MARK: findings

    private func design(_ elements: [Element], background: String = "#004400") -> Design {
        var d = Design(title: "Seen", width: 1080, height: 1080)
        d.pages = [Page(background: .color(background), elements: elements)]
        return d
    }

    /// Large red on dark green passes typically (3.3:1 of 3) but not
    /// red-blind or blue-blind; the worst is said, and Fix colour mends it.
    func testTextThatPassesOnlyTypicallyIsFlagged() throws {
        var text = Element.text("Sale", fontSize: 48)
        text.id = "t1"
        text.color = "#ff4040"
        let d = design([text])
        let seen = ColourVision.textFindings(d)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen[0].contrast.elementId, "t1")
        XCTAssertEqual(seen[0].kinds, [.protanopia, .tritanopia])
        XCTAssertEqual(seen[0].contrast.ratio, 2.187, accuracy: 0.001)
        let found = AccessibilityAudit.findings(d).filter { $0.kind == .colourVision }
        XCTAssertEqual(found.map(\.message), ["Hard to read in Red-blind, Blue-blind view: 2.2:1"])
        XCTAssertEqual(found.first?.fix, .fixColour)
        let fixed = AccessibilityAudit.fixed(d, try XCTUnwrap(found.first))
        XCTAssertTrue(ColourVision.textFindings(fixed).isEmpty)
        XCTAssertTrue(ContrastAudit.audit(fixed).isEmpty)
    }

    /// Text that fails typically is contrast's, not this check's; hidden
    /// text and hidden pages are not checked.
    func testOnlyTextThatPassesTypicallyIsChecked() {
        var faint = Element.text("Faint", fontSize: 48)
        faint.color = "#105010"
        XCTAssertTrue(ColourVision.textFindings(design([faint])).isEmpty)
        var hidden = Element.text("Sale", fontSize: 48)
        hidden.color = "#ff4040"
        hidden.hidden = true
        XCTAssertTrue(ColourVision.textFindings(design([hidden])).isEmpty)
        var shown = Element.text("Sale", fontSize: 48)
        shown.color = "#ff4040"
        var d = design([shown])
        d.pages[0].hidden = true
        XCTAssertTrue(ColourVision.textFindings(d).isEmpty)
    }

    /// Orange and green bars apart as drawn, alike red-blind and in
    /// greyscale: named by the chart's bottom element.
    func testChartSeriesThatLookAlikeAreFlagged() {
        let spec = ChartSpec(id: "chart_1", kind: "column", data: "A,1,2")
        var a = Element.shape("rect")
        a.id = "bar1"
        a.chart = spec
        a.chartPart = "series:1"
        a.fill = .solid("#ff7f0e")
        var b = Element.shape("rect")
        b.id = "bar2"
        b.chart = spec
        b.chartPart = "series:2"
        b.fill = .solid("#2ca02c")
        let d = design([a, b], background: "#ffffff")
        let charts = ColourVision.chartFindings(d)
        XCTAssertEqual(charts, [ColourVision.ChartFinding(pageIndex: 0, elementId: "bar1", first: 1, second: 2,
                                                          kinds: [.protanopia, .achromatopsia])])
        let found = AccessibilityAudit.findings(d).filter { $0.kind == .colourVision }
        XCTAssertEqual(found.map(\.message), ["Chart colours look alike in Red-blind, Greyscale view"])
        XCTAssertNil(found.first?.fix)
    }

    func testKindsInTheirOrder() {
        XCTAssertEqual(AccessibilityAudit.Kind.allCases.map(\.rawValue),
                       ["contrast", "altText", "smallText", "flashing", "linkText", "chartColours", "readingOrder",
                        "headings", "colourVision", "missingLetters"])
    }

    // MARK: the shared fixture

    /// Shared: each colour as each way of seeing shows it, and what is
    /// flagged in the design — the Android twin's fixtures/colour-vision.json.
    func testTheSharedFixture() throws {
        let fixture = try SharedFixture.object("colour-vision")
        let colours = try XCTUnwrap(fixture["colours"] as? [String: [String: String]])
        for (hex, seen) in colours {
            for (key, want) in seen {
                let kind = try XCTUnwrap(ColourVision.Sight(rawValue: key))
                XCTAssertEqual(ColourVision.simulate(hex, kind), want, "\(hex) \(key)")
            }
        }
        let design = try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(fixture["design"])))
        let texts = try XCTUnwrap(fixture["texts"] as? [[String: Any]])
        let seenTexts = ColourVision.textFindings(design)
        XCTAssertEqual(seenTexts.map(\.contrast.elementId), texts.map { $0["id"] as? String ?? "" })
        XCTAssertEqual(seenTexts.map { $0.kinds.map(\.rawValue) }, texts.map { $0["kinds"] as? [String] ?? [] })
        let charts = try XCTUnwrap(fixture["charts"] as? [[String: Any]])
        let seenCharts = ColourVision.chartFindings(design)
        XCTAssertEqual(seenCharts.map(\.elementId), charts.map { $0["id"] as? String ?? "" })
        XCTAssertEqual(seenCharts.map(\.first), charts.map { $0["first"] as? Int ?? -1 })
        XCTAssertEqual(seenCharts.map(\.second), charts.map { $0["second"] as? Int ?? -1 })
        XCTAssertEqual(seenCharts.map { $0.kinds.map(\.rawValue) }, charts.map { $0["kinds"] as? [String] ?? [] })
    }
}
