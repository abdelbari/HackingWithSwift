// Marquee selection, transforming a multi-selection as one unit, and the
// snapping grid. All pure geometry over the document, so all assertable.

import XCTest
@testable import Canvia

@MainActor
final class LayoutTests: XCTestCase {

    private func rect(_ x: Double, _ y: Double, w: Double = 100, h: Double = 50,
                      rotation: Double = 0, locked: Bool = false) -> Element {
        var e = Element.shape("rect", w: w, h: h)
        e.x = x; e.y = y
        e.rotation = rotation
        e.locked = locked
        return e
    }

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "layout", width: 1000, height: 800)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    // MARK: marquee

    func testTheBandPicksUpWhatItTouchesAndNothingElse() {
        let a = rect(0, 0), b = rect(300, 300), c = rect(900, 700)
        let s = store([a, b, c])
        s.select(within: CGRect(x: 50, y: 25, width: 300, height: 300))
        XCTAssertEqual(s.selection, [a.id, b.id], "touching counts; containing is not required")
    }

    func testLockedElementsAreNotBanded() {
        let a = rect(0, 0), b = rect(0, 100, locked: true)
        let s = store([a, b])
        s.select(within: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertEqual(s.selection, [a.id])
    }

    func testARotatedElementIsBandedByItsRealBox() {
        // Tall and thin, turned flat: its unrotated frame is a column at
        // x 500…520, its actual box a bar at y 240…260 reaching x 410…610.
        let bar = rect(500, 150, w: 20, h: 200, rotation: 90)
        let s = store([bar])
        s.select(within: CGRect(x: 420, y: 200, width: 40, height: 100))
        XCTAssertEqual(s.selection, [bar.id])
    }

    func testTheBandTakesAWholeStickyGroup() {
        let a = rect(0, 0), b = rect(800, 700)
        let s = store([a, b])
        s.selection = [a.id, b.id]
        s.groupSelected()
        s.select(within: CGRect(x: 0, y: 0, width: 50, height: 50))
        XCTAssertEqual(s.selection, [a.id, b.id])
    }

    func testAnEmptyBandSelectsNothing() {
        let s = store([rect(0, 0)])
        s.selection = [s.page.elements[0].id]
        s.select(within: CGRect(x: 0, y: 0, width: 0, height: 0))
        XCTAssertTrue(s.selection.isEmpty)
    }

    // MARK: group scale

    func testScalingTheBoxScalesEveryMemberInPlace() {
        var text = Element.text("Hello", fontSize: 40, w: 200)
        text.x = 100; text.y = 100
        let shape = rect(300, 100, w: 100, h: 100)
        let from = Geometry.union([Geometry.aabb(text), Geometry.aabb(shape)])
        let to = CGRect(x: from.minX, y: from.minY, width: from.width * 2, height: from.height * 2)
        let scaled = Geometry.scale([text, shape], from: from, to: to)

        XCTAssertEqual(scaled[0].x, 100, accuracy: 0.001, "the anchored corner stays put")
        XCTAssertEqual(scaled[0].w, 400, accuracy: 0.001)
        XCTAssertEqual(scaled[0].fontSize ?? 0, 80, accuracy: 0.001, "text scales its type, not just its box")
        XCTAssertEqual(scaled[1].x, 500, accuracy: 0.001)
        XCTAssertEqual(scaled[1].w, 200, accuracy: 0.001)
        XCTAssertEqual(scaled[1].h, 200, accuracy: 0.001)
        let after = Geometry.union(scaled.map(Geometry.aabb))
        XCTAssertEqual(after.width, to.width, accuracy: 0.01)
        XCTAssertEqual(after.height, to.height, accuracy: 0.01)
    }

    func testARotatedMemberKeepsItsAngleAndItsRelativePlace() {
        let turned = rect(100, 100, rotation: 30)
        let other = rect(400, 400)
        let from = Geometry.union([Geometry.aabb(turned), Geometry.aabb(other)])
        let to = CGRect(x: 0, y: 0, width: from.width / 2, height: from.height / 2)
        let scaled = Geometry.scale([turned, other], from: from, to: to)
        XCTAssertEqual(scaled[0].rotation, 30)
        XCTAssertEqual(scaled[0].w, 50, accuracy: 0.001)
        let relativeBefore = (turned.center.x - from.minX) / from.width
        let relativeAfter = (scaled[0].center.x - to.minX) / to.width
        XCTAssertEqual(relativeBefore, relativeAfter, accuracy: 0.001)
    }

    func testALineKeepsItsStrokeWhenScaled() {
        var line = Element()
        line.type = .line
        line.x = 0; line.y = 0; line.w = 200; line.h = 4
        let from = Geometry.aabb(line)
        let scaled = Geometry.scale([line], from: from,
                                    to: CGRect(x: 0, y: 0, width: 400, height: 8))
        XCTAssertEqual(scaled[0].w, 400, accuracy: 0.001)
        XCTAssertEqual(scaled[0].h, 4, "a line's height is its stroke, not a dimension")
    }

    // MARK: group rotate

    func testRotatingTheGroupTurnsEachMemberAboutTheSharedCentre() {
        let left = rect(0, 0, w: 100, h: 100)
        let right = rect(200, 0, w: 100, h: 100)
        let box = Geometry.union([Geometry.aabb(left), Geometry.aabb(right)])
        let centre = CGPoint(x: box.midX, y: box.midY)   // (150, 50)
        let turned = Geometry.rotate([left, right], around: centre, by: 180)
        // A half turn swaps the two, and each is itself half-turned.
        XCTAssertEqual(turned[0].center.x, 250, accuracy: 0.001)
        XCTAssertEqual(turned[1].center.x, 50, accuracy: 0.001)
        XCTAssertEqual(turned[0].center.y, 50, accuracy: 0.001)
        XCTAssertEqual(turned[0].rotation, 180, accuracy: 0.001)
        XCTAssertEqual(turned[0].w, 100)
    }

    func testGroupRotationWrapsInto0To360() {
        let el = rect(0, 0, rotation: 350)
        let turned = Geometry.rotate([el], around: el.center, by: 20)
        XCTAssertEqual(turned[0].rotation, 10, accuracy: 0.001)
        XCTAssertEqual(turned[0].x, 0, accuracy: 0.001, "turning about its own centre does not move it")
    }

    // MARK: grid

    func testGridLinesRunEdgeToEdgeInclusive() {
        XCTAssertEqual(Geometry.gridLines(across: 64, spacing: 16), [0, 16, 32, 48, 64])
        XCTAssertTrue(Geometry.gridLines(across: 64, spacing: 0).isEmpty)
    }

    func testEachSnapSourceHasItsOwnSwitch() {
        let design = store([rect(100, 100)]).design
        let page = design.pages[0]
        let none = Geometry.snapLines(design: design, page: page, excluding: [],
                                      settings: SnapSettings(toPage: false, toElements: false))
        XCTAssertTrue(none.x.isEmpty && none.y.isEmpty)

        let pageOnly = Geometry.snapLines(design: design, page: page, excluding: [],
                                          settings: SnapSettings(toPage: true, toElements: false))
        XCTAssertEqual(pageOnly.x, [0, 500, 1000])

        let grid = Geometry.snapLines(design: design, page: page, excluding: [],
                                      settings: SnapSettings(toPage: false, toElements: false, grid: 250))
        XCTAssertEqual(grid.x, [0, 250, 500, 750, 1000])
        XCTAssertEqual(grid.y, [0, 250, 500, 750])
    }

    func testAMoveSnapsOntoTheGrid() {
        let lines = Geometry.snapLines(design: Design(title: "g", width: 400, height: 400),
                                       page: Page(), excluding: [],
                                       settings: SnapSettings(toPage: false, toElements: false, grid: 32))
        let box = CGRect(x: 61, y: 130, width: 50, height: 50)
        let snap = Geometry.snap(box: box, xLines: lines.x, yLines: lines.y, threshold: 6)
        XCTAssertEqual(box.minX + snap.dx, 64, accuracy: 0.001)
        XCTAssertEqual(box.minY + snap.dy, 128, accuracy: 0.001)
        XCTAssertEqual(snap.guideX, 64)
    }

    func testSnapSettingsSurviveALaunch() throws {
        let suite = "canvia.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(SnapSettings.load(from: defaults), SnapSettings(), "defaults: page and elements on, no grid")
        var chosen = SnapSettings()
        chosen.toElements = false
        chosen.grid = 16
        chosen.showGrid = true
        chosen.save(to: defaults)
        XCTAssertEqual(SnapSettings.load(from: defaults), chosen)
    }
}
