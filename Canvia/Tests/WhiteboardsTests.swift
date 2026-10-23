// Whiteboards, as the Android twin's WhiteboardsTest has them, table for
// table: the bounds, the key both phones write, collapsing and expanding,
// the store keeping the bounds up to date, the export's margin, Fit to
// content, the pan and zoom limits, the Whiteboard type and sticky notes.

import XCTest
import CoreGraphics
@testable import Canvia

final class WhiteboardsTests: XCTestCase {

    private let frame = CGSize(width: 1920, height: 1080)

    private func box(_ id: String, _ x: Double, _ y: Double, w: Double = 100, h: Double = 100,
                     rotation: Double = 0) -> Element {
        var el = Element.shape("rectangle", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        el.rotation = rotation
        return el
    }

    private func design(_ elements: [Element]) -> Design {
        var d = Design(title: "w", width: 1920, height: 1080)
        d.pages = [Page(id: "p", elements: elements)]
        return d
    }

    private func assertRect(_ expected: CGRect, _ actual: CGRect?, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("no rect", file: file, line: line) }
        XCTAssertEqual(expected.minX, actual.minX, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(expected.minY, actual.minY, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(expected.width, actual.width, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(expected.height, actual.height, accuracy: 1e-9, file: file, line: line)
    }

    // The bounds table both phones run: the frame, and every element's
    // turned box, unioned — negative where things lie left of or above it.
    func testBoundsAreTheFrameAndEveryElementsTurnedBox() {
        let r = 50 * 2.0.squareRoot()
        let cases: [([Element], CGRect)] = [
            ([], CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            ([box("in", 100, 100)], CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            ([box("left", -500, 200)], CGRect(x: -500, y: 0, width: 2420, height: 1080)),
            ([box("below", 1900, 1200, w: 200, h: 50)], CGRect(x: 0, y: 0, width: 2100, height: 1250)),
            ([box("a", -300, -200), box("b", 2000, 1100)], CGRect(x: -300, y: -200, width: 2400, height: 1400)),
            // A 100 × 100 square turned 45° reaches 70.71 from its middle.
            ([box("turned", -100, 500, rotation: 45)], CGRect(x: -50 - r, y: 0, width: 1970 + r, height: 1080)),
        ]
        for (elements, expected) in cases {
            assertRect(expected, Whiteboards.contentBounds(frame: frame, elements: elements))
        }
    }

    func testExpandingWritesTheKeyAsBothPhonesReadItAndCollapsingTakesItAway() throws {
        let d = design([box("far", -400, 50)])
        let page = Whiteboards.expanded(d.pages[0], frame: frame)
        XCTAssertTrue(Whiteboards.isExpanded(page))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
        let entry = try XCTUnwrap(json["whiteboard"] as? [String: Any])
        XCTAssertEqual(entry["expanded"] as? Bool, true)
        XCTAssertEqual(entry["bounds"] as? [Double], [-400, 0, 2320, 1080])
        assertRect(CGRect(x: -400, y: 0, width: 2320, height: 1080), Whiteboards.storedBounds(page))
        // Back from the file as it was.
        XCTAssertEqual(try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page)).whiteboard, page.whiteboard)
        // The page's own size is still the collapsed frame.
        XCTAssertNil(page.width)
        let collapsed = Whiteboards.collapsed(page, frame: frame)
        XCTAssertFalse(Whiteboards.isExpanded(collapsed))
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(collapsed)) as? [String: Any])
        XCTAssertNil(after["whiteboard"])
    }

    func testBoundsThatDoNotReadAreNone() throws {
        func page(_ bounds: String) throws -> Page {
            try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p","whiteboard":{"expanded":true,"bounds":\#(bounds)}}"#.utf8))
        }
        XCTAssertNil(Whiteboards.storedBounds(try page("[1,2,3]")))
        XCTAssertNil(Whiteboards.storedBounds(try page("[0,0,-5,10]")))
        XCTAssertNil(Whiteboards.storedBounds(try page(#"["0","0","5","10"]"#)))
        XCTAssertTrue(Whiteboards.isExpanded(try page("[1,2,3]")), "still expanded, its bounds worked out afresh")
        XCTAssertNil(Whiteboards.storedBounds(Page()))
        // "expanded" false, or not a boolean, is a page as it always was.
        let quoted = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p","whiteboard":{"expanded":"true"}}"#.utf8))
        XCTAssertFalse(Whiteboards.isExpanded(quoted))
    }

    func testCollapsingHidesWhatLiesWhollyOutsideAndExpandingShowsItAgain() {
        let inside = box("inside", 100, 100)
        let overhang = box("overhang", 1880, 100)
        let beyond = box("beyond", 2500, 100)
        let touching = box("touching", -100, 100) // its right edge on the frame's left
        var chosen = box("chosen", 200, 200)
        chosen.hidden = true
        let page = Whiteboards.expanded(Page(elements: [inside, overhang, beyond, touching, chosen]), frame: frame)
        XCTAssertEqual(Whiteboards.outside(page, frame: frame).map(\.id), ["beyond", "touching"])
        let collapsed = Whiteboards.collapsed(page, frame: frame)
        XCTAssertEqual(collapsed.elements.filter(\.isHidden).map(\.id).sorted(), ["beyond", "chosen", "touching"])
        XCTAssertEqual(collapsed.elements.count, 5)
        // Expanded again: what the collapse hid shows, what was hidden on
        // the page stays hidden.
        let again = Whiteboards.expanded(collapsed, frame: frame)
        XCTAssertEqual(again.elements.filter(\.isHidden).map(\.id), ["chosen"])
    }

    func testRefreshingFollowsWhatMovedAndLeavesADesignWithNothingNewAsItIs() {
        let d = design([box("a", 100, 100)])
        var expanded = d
        expanded.pages = [Whiteboards.expanded(d.pages[0], frame: frame)]
        XCTAssertEqual(Whiteboards.refreshed(expanded), expanded)
        let plain = design([box("a", -900, 100)])
        XCTAssertEqual(Whiteboards.refreshed(plain), plain)
        var moved = expanded
        moved.pages[0].elements = [box("a", 2000, -300)]
        assertRect(CGRect(x: 0, y: -300, width: 2100, height: 1380),
                   Whiteboards.storedBounds(Whiteboards.refreshed(moved).pages[0]))
    }

    func testTheStoreKeepsTheBoundsUpToDateAndExpandsAndCollapsesAsOneStep() {
        let store = DesignStore(design: design([box("a", 100, 100)]))
        XCTAssertEqual(store.setWhiteboard(true), 0)
        XCTAssertNil(store.setWhiteboard(true))
        store.select("a")
        store.updateSelected { $0.x = -600 }
        assertRect(CGRect(x: -600, y: 0, width: 2520, height: 1080), Whiteboards.storedBounds(store.page))
        store.select("a")
        XCTAssertEqual(store.setWhiteboard(false), 1)
        XCTAssertTrue(store.selection.isEmpty)
        XCTAssertTrue(store.page.elements[0].isHidden)
        store.undo()
        XCTAssertTrue(Whiteboards.isExpanded(store.page))
        XCTAssertFalse(store.page.elements[0].isHidden)
        // Nothing on a locked page.
        store.setPagesLocked(["p"], locked: true)
        XCTAssertNil(store.setWhiteboard(false))
        XCTAssertTrue(Whiteboards.isExpanded(store.page))
    }

    func testAnExportDrawsTheBoundsAndFivePercentRoundThem() {
        let d = design([box("a", -400, -100)])
        var expanded = d
        expanded.pages = [Whiteboards.expanded(d.pages[0], frame: frame)]
        // Bounds (-400, -100, 2320, 1180): 116 and 59 each side.
        assertRect(CGRect(x: -516, y: -159, width: 2552, height: 1298), Whiteboards.shownRect(expanded, expanded.pages[0]))
        let flat = Whiteboards.flattened(expanded)
        let page = flat.pages[0]
        XCTAssertFalse(Whiteboards.isExpanded(page))
        XCTAssertEqual(flat.size(for: page), CGSize(width: 2552, height: 1298))
        XCTAssertEqual(page.elements[0].x, 116, accuracy: 1e-9)
        XCTAssertEqual(page.elements[0].y, 59, accuracy: 1e-9)
        // A plain page is drawn as it is.
        XCTAssertEqual(Whiteboards.flattened(d), d)
        assertRect(CGRect(x: 0, y: 0, width: 1920, height: 1080), Whiteboards.shownRect(d, d.pages[0]))
    }

    // The fit table both phones run: content, viewport, limits -> zoom, pan.
    func testFitToContentCentresTheContentAsLargeAsItGoesWithinTheZoomLimits() {
        let cases: [(CGRect, CGSize, Double, CGPoint)] = [
            (CGRect(x: 0, y: 0, width: 1000, height: 500), CGSize(width: 500, height: 500), 0.5, CGPoint(x: 0, y: 125)),
            (CGRect(x: -200, y: -100, width: 400, height: 200), CGSize(width: 800, height: 800), 2, CGPoint(x: 400, y: 400)),
            // Held to the most: 4.
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGSize(width: 1000, height: 1000), 4, CGPoint(x: 480, y: 480)),
            // And the least: 0.05.
            (CGRect(x: 0, y: 0, width: 100_000, height: 1000), CGSize(width: 1000, height: 1000), 0.05,
             CGPoint(x: -2000, y: 475)),
        ]
        for (content, viewport, zoom, pan) in cases {
            let fit = Whiteboards.fit(content: content, viewport: viewport, minZoom: Whiteboards.minZoom, maxZoom: Whiteboards.maxZoom)
            XCTAssertEqual(fit.zoom, zoom, accuracy: 1e-9)
            XCTAssertEqual(fit.pan.x, pan.x, accuracy: 1e-9)
            XCTAssertEqual(fit.pan.y, pan.y, accuracy: 1e-9)
        }
        let none = Whiteboards.fit(content: CGRect(x: 0, y: 0, width: 0, height: 10), viewport: CGSize(width: 100, height: 100),
                                   minZoom: 0.05, maxZoom: 4)
        XCTAssertEqual(none.zoom, 1)
        XCTAssertEqual(none.pan, .zero)
    }

    func testThePanReachesOneScreenPastTheBoundsAndTheZoomRunsFrom5To400Percent() {
        assertRect(CGRect(x: -600, y: -1100, width: 2200, height: 2800),
                   Whiteboards.panContent(bounds: CGRect(x: -100, y: -100, width: 1200, height: 800),
                                          viewport: CGSize(width: 1000, height: 2000), zoom: 2))
        let range = Whiteboards.zoomRange(density: 2.5)
        XCTAssertEqual(range.lowerBound, 0.125, accuracy: 1e-12)
        XCTAssertEqual(range.upperBound, 10, accuracy: 1e-12)
        XCTAssertEqual(Whiteboards.zoomRange(), 0.05...4)
        // The dots double until they are 16 screen units apart.
        XCTAssertEqual(Whiteboards.gridStep(zoom: 1), 40)
        XCTAssertEqual(Whiteboards.gridStep(zoom: 0.1), 160)
    }

    func testTheWhiteboardTypeIsA1920By1080PresentationThatStartsExpanded() throws {
        let preset = try XCTUnwrap(SizePreset.byId(Whiteboards.presetId))
        XCTAssertEqual(preset.category, "Presentations")
        XCTAssertEqual(preset.w, 1920)
        XCTAssertEqual(preset.h, 1080)
        let made = preset.makeDesign()
        XCTAssertTrue(Whiteboards.isExpanded(made.pages[0]))
        assertRect(CGRect(x: 0, y: 0, width: 1920, height: 1080), Whiteboards.storedBounds(made.pages[0]))
        XCTAssertFalse(Whiteboards.isExpanded(try XCTUnwrap(SizePreset.byId("presentation")).makeDesign().pages[0]))
    }

    func testAStickyNoteIsASquareOfSixPapersWhoseWordsShrinkToFit() throws {
        XCTAssertEqual(StickyNotes.colours.count, 6)
        let note = StickyNotes.note(StickyNotes.colours[0])
        XCTAssertTrue(StickyNotes.isSticky(note))
        XCTAssertEqual(note.shapeId, "rectangle")
        XCTAssertEqual(note.w, note.h)
        XCTAssertEqual(note.fontSize, StickyNotes.fontSize)
        XCTAssertTrue(ShapeText.takesText(note))
        // Written as the Android twin keeps it.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any])
        XCTAssertEqual(json["sticky"] as? Bool, true)
        // Words standing 3 × their size fit a room of 90 at 30, not 31.
        XCTAssertEqual(StickyNotes.fittedFontSize(room: 90) { $0 * 3 }, 30)
        XCTAssertEqual(StickyNotes.fittedFontSize(room: 1000) { $0 * 3 }, StickyNotes.fontSize)
        XCTAssertEqual(StickyNotes.fittedFontSize(room: 1) { $0 * 3 }, StickyNotes.minFontSize)
        let placed = StickyNotes.placed(note, at: CGPoint(x: 500, y: 400))
        XCTAssertEqual(placed.x, 500 - note.w / 2)
        XCTAssertEqual(placed.y, 400 - note.h / 2)
    }

    func testANotesWordsShrinkAsTheyGrowAndTheNoteKeepsItsSize() {
        var note = StickyNotes.note(StickyNotes.colours[1])
        note.setText(String(repeating: "Brainstorm the plan ", count: 30))
        ShapeText.fitWords(&note)
        XCTAssertEqual(note.w, StickyNotes.side)
        XCTAssertEqual(note.h, StickyNotes.side)
        XCTAssertLessThan(note.fontSize ?? StickyNotes.fontSize, StickyNotes.fontSize)
        XCTAssertGreaterThanOrEqual(note.fontSize ?? 0, StickyNotes.minFontSize)
    }
}
