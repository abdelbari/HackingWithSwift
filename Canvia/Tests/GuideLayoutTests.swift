// Guides you lay out: Guides.layout against the spec's shared table, Add
// guides as one undo step, a guide placed at a typed position, and a grid
// spacing of your own.

import XCTest
import CoreGraphics
@testable import Canvia

@MainActor
final class GuideLayoutTests: XCTestCase {

    private func design(width: Double = 1080, height: Double = 1080) -> Design {
        Design(title: "guides", width: width, height: height)
    }

    // MARK: guides

    private struct LayoutCase {
        var name: String
        var size: CGSize
        var columns: Int
        var rows: Int
        var gutter: Double
        var margin: Double
        var existing: [Guide] = []
        var vertical: [Double]
        var horizontal: [Double]
    }

    /// The spec's shared table: what Guides.layout gives, on both phones —
    /// Android's GuidesTest has these rows, in this order.
    private var layoutTable: [LayoutCase] { [
        LayoutCase(name: "3 columns, no gutter, no margin", size: CGSize(width: 1080, height: 1080),
                   columns: 3, rows: 0, gutter: 0, margin: 0, vertical: [360, 720], horizontal: []),
        LayoutCase(name: "2 columns, gutter 20, margin 40", size: CGSize(width: 1080, height: 1080),
                   columns: 2, rows: 0, gutter: 20, margin: 40, vertical: [40, 530, 550, 1040], horizontal: []),
        LayoutCase(name: "3 × 3 grid", size: CGSize(width: 1080, height: 1080),
                   columns: 3, rows: 3, gutter: 0, margin: 0, vertical: [360, 720], horizontal: [360, 720]),
        LayoutCase(name: "dedupe within 0.5 px, each way on its own", size: CGSize(width: 1080, height: 1080),
                   columns: 3, rows: 3, gutter: 0, margin: 0,
                   existing: [Guide(vertical: true, position: 360.4), Guide(vertical: false, position: 719.6)],
                   vertical: [720], horizontal: [360]),
        LayoutCase(name: "0.5 px away is the same guide, 0.6 px is not", size: CGSize(width: 1080, height: 1080),
                   columns: 3, rows: 0, gutter: 0, margin: 0,
                   existing: [Guide(vertical: true, position: 360.5), Guide(vertical: true, position: 720.6)],
                   vertical: [720], horizontal: []),
        LayoutCase(name: "a horizontal guide does not stand in for a vertical one", size: CGSize(width: 1080, height: 1080),
                   columns: 3, rows: 0, gutter: 0, margin: 0,
                   existing: [Guide(vertical: false, position: 360)], vertical: [360, 720], horizontal: []),
        LayoutCase(name: "rows 0 is no horizontal guides, margin or not", size: CGSize(width: 1080, height: 1080),
                   columns: 1, rows: 0, gutter: 0, margin: 40, vertical: [40, 1040], horizontal: []),
        LayoutCase(name: "1 row is its margins", size: CGSize(width: 1080, height: 1080),
                   columns: 1, rows: 1, gutter: 0, margin: 40, vertical: [40, 1040], horizontal: [40, 1040]),
        LayoutCase(name: "2 × 2 with gutter 20, margin 40 on a story", size: CGSize(width: 1080, height: 1920),
                   columns: 2, rows: 2, gutter: 20, margin: 40,
                   vertical: [40, 530, 550, 1040], horizontal: [40, 950, 970, 1880]),
        LayoutCase(name: "rounded to the half pixel", size: CGSize(width: 1000, height: 1000),
                   columns: 3, rows: 0, gutter: 0, margin: 0, vertical: [333.5, 666.5], horizontal: []),
        LayoutCase(name: "12 columns", size: CGSize(width: 1080, height: 1080),
                   columns: 12, rows: 0, gutter: 0, margin: 0,
                   vertical: [90, 180, 270, 360, 450, 540, 630, 720, 810, 900, 990], horizontal: []),
        LayoutCase(name: "4 columns, gutter 16, margin 32", size: CGSize(width: 1080, height: 1080),
                   columns: 4, rows: 0, gutter: 16, margin: 32,
                   vertical: [32, 274, 290, 532, 548, 790, 806, 1048], horizontal: []),
        LayoutCase(name: "3 × 2 grid, gutter 10, margin 20, on a tall page", size: CGSize(width: 1080, height: 1920),
                   columns: 3, rows: 2, gutter: 10, margin: 20,
                   vertical: [20, 360, 370, 710, 720, 1060], horizontal: [20, 955, 965, 1900]),
        LayoutCase(name: "within 0.5 of a guide already there is that guide", size: CGSize(width: 1080, height: 1080),
                   columns: 3, rows: 3, gutter: 0, margin: 0,
                   existing: [Guide(vertical: true, position: 360.4), Guide(vertical: true, position: 719),
                              Guide(vertical: false, position: 720.5)],
                   vertical: [720], horizontal: [360]),
        LayoutCase(name: "numbers past their range are kept to it", size: CGSize(width: 1080, height: 2400),
                   columns: 0, rows: 30, gutter: -5, margin: -10,
                   vertical: [], horizontal: (1...23).map { 100 * Double($0) }),
        LayoutCase(name: "a margin past half the side meets in the middle", size: CGSize(width: 1050, height: 600),
                   columns: 1, rows: 1, gutter: 0, margin: 400, vertical: [400, 650], horizontal: [300]),
        LayoutCase(name: "a gutter that leaves no room leaves tracks of nothing", size: CGSize(width: 1050, height: 600),
                   columns: 1, rows: 5, gutter: 200, margin: 0, vertical: [], horizontal: [0, 200, 400, 600]),
    ] }

    func testGuidesLayoutMatchesTheSharedTable() {
        for c in layoutTable {
            let made = Guides.layout(size: c.size, columns: c.columns, rows: c.rows,
                                     gutter: c.gutter, margin: c.margin, existing: c.existing)
            XCTAssertEqual(made.filter(\.vertical).map(\.position), c.vertical, c.name)
            XCTAssertEqual(made.filter { !$0.vertical }.map(\.position), c.horizontal, c.name)
            XCTAssertEqual(made.map(\.vertical),
                           Array(repeating: true, count: c.vertical.count) + Array(repeating: false, count: c.horizontal.count),
                           "vertical first: \(c.name)")
        }
    }

    func testThePresetsAreTheSpecsWords() {
        XCTAssertEqual(Guides.presets.map(\.label),
                       ["2 columns", "3 columns", "4 columns", "6 columns", "12 columns", "3 × 3 grid"])
        XCTAssertEqual(Guides.customLabel, "Custom…")
        XCTAssertEqual(Guides.presets.last?.columns, 3)
        XCTAssertEqual(Guides.presets.last?.rows, 3)
        XCTAssertEqual(Guides.columnRange, 1...24)
        XCTAssertEqual(Guides.rowRange, 0...24)
        XCTAssertEqual(Guides.gutterRange, 0...200)
        XCTAssertEqual(Guides.marginRange, 0...400)
    }

    func testAddingALayoutIsOneUndoAndCanReplaceTheGuidesThere() {
        let s = DesignStore(design: design())
        s.addGuide(vertical: false, at: 100)
        XCTAssertEqual(s.addGuideLayout(columns: 3, rows: 0, gutter: 0, margin: 0, replace: false), 2)
        XCTAssertEqual(s.design.guides.map(\.position), [100, 360, 720])
        XCTAssertEqual(s.addGuideLayout(columns: 3, rows: 0, gutter: 0, margin: 0, replace: false), 0)
        XCTAssertEqual(s.design.guides.count, 3, "the same layout again adds nothing")
        XCTAssertEqual(s.addGuideLayout(columns: 2, rows: 0, gutter: 0, margin: 0, replace: true), 1)
        XCTAssertEqual(s.design.guides.map(\.position), [540])
        XCTAssertTrue(s.design.guides[0].vertical)
        s.undo()
        XCTAssertEqual(s.design.guides.map(\.position), [100, 360, 720])
        s.undo()
        XCTAssertEqual(s.design.guides.map(\.position), [100])
    }

    func testATypedGuidePositionIsKeptOnThePage() {
        XCTAssertEqual(Guides.typedPosition("120", limit: 400), 120)
        XCTAssertEqual(Guides.typedPosition(" 120.5 px ", limit: 400), 120.5)
        XCTAssertEqual(Guides.typedPosition("12,5", limit: 400), 12.5)
        XCTAssertEqual(Guides.typedPosition("9999", limit: 400), 400)
        XCTAssertEqual(Guides.typedPosition("-5", limit: 400), 0)
        XCTAssertNil(Guides.typedPosition("left", limit: 400))
        XCTAssertNil(Guides.typedPosition("", limit: 400))
        let s = DesignStore(design: design(width: 400, height: 300))
        s.addGuide(vertical: false, at: 50)
        let id = s.design.guides[0].id
        s.setGuidePosition(id, to: 1000)
        XCTAssertEqual(s.design.guides[0].position, 300, "a horizontal guide is kept within the height")
        s.undo()
        XCTAssertEqual(s.design.guides[0].position, 50)
    }

    // MARK: custom grid

    func testACustomGridIsTwoToFiveHundredPixels() throws {
        XCTAssertEqual(SnapSettings.customGrid("2"), 2)
        XCTAssertEqual(SnapSettings.customGrid("500"), 500)
        XCTAssertEqual(SnapSettings.customGrid("12.5"), 12.5)
        XCTAssertEqual(SnapSettings.customGrid("24 px"), 24)
        XCTAssertNil(SnapSettings.customGrid("1"))
        XCTAssertNil(SnapSettings.customGrid("501"))
        XCTAssertNil(SnapSettings.customGrid("lots"))
        XCTAssertEqual(SnapSettings.gridLabel(16), "Every 16 px")
        XCTAssertEqual(SnapSettings.gridLabel(12.5), "Every 12.5 px")
        XCTAssertFalse(SnapSettings.isCustomGrid(16))
        XCTAssertFalse(SnapSettings.isCustomGrid(0))
        XCTAssertTrue(SnapSettings.isCustomGrid(24))
        var settings = SnapSettings()
        settings.grid = 24
        let back = try JSONDecoder().decode(SnapSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.grid, 24, "kept across launches like any other spacing")
        XCTAssertEqual(Geometry.gridLines(across: 100, spacing: 24), [0, 24, 48, 72, 96])
    }
}
