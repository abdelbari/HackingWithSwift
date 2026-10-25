// Round 34's Select behind: what lies under a fingertip (Layers.hitStack),
// the row Alt+Tab goes to (Layers.behind), what a still hold on an element
// does (CanvasGestures.holdOnElement) and the hold menu's Select behind —
// the shared fixture Fixtures/hit-stack.json holds the rows the Android
// twin's tests hold too.

import XCTest
import CoreGraphics
@testable import Canvia

@MainActor
final class SelectBehindTests: XCTestCase {

    private struct Fixture {
        let radius: Double
        let elements: [Element]
        let probes: [[String: Any]]
        let behind: [[String: Any]]
        let oneRow: [[String: Any]]
    }

    private func fixture() throws -> Fixture {
        let root = try SharedFixture.object("hit-stack")
        let elements = try JSONDecoder().decode([Element].self, from: SharedFixture.encoded(root["elements"] ?? [Any]()))
        return Fixture(radius: try XCTUnwrap(root["touchRadius"] as? Double), elements: elements,
                       probes: try XCTUnwrap(root["probes"] as? [[String: Any]]),
                       behind: try XCTUnwrap(root["behind"] as? [[String: Any]]),
                       oneRow: try XCTUnwrap(root["oneRow"] as? [[String: Any]]))
    }

    private func point(_ probe: [String: Any]) throws -> CGPoint {
        CGPoint(x: try XCTUnwrap(probe["x"] as? Double), y: try XCTUnwrap(probe["y"] as? Double))
    }

    func testTheStackUnderEachProbeIsTheSharedOne() throws {
        let f = try fixture()
        for probe in f.probes {
            let at = try point(probe)
            // A probe's own radius, where it has one, over the fixture's.
            let radius = probe["touchRadius"] as? Double ?? f.radius
            let stack = Layers.hitStack(f.elements, at, touchRadius: radius)
            XCTAssertEqual(stack.map(\.id), probe["stack"] as? [String], "at \(at) r \(radius)")
        }
    }

    func testAltTabGoesToTheRowUnderTheSelection() throws {
        let f = try fixture()
        for row in f.behind {
            let at = try point(row)
            let stack = Layers.hitStack(f.elements, at, touchRadius: f.radius)
            let selection = Set(try XCTUnwrap(row["selection"] as? [String]))
            let next = Layers.behind(stack, selection: selection)
            XCTAssertEqual(next?.id, row["next"] as? String, "at \(at) from \(selection)")
        }
    }

    func testAGroupRowCarriesEveryMemberAndItsLayersName() throws {
        let f = try fixture()
        let stack = Layers.hitStack(f.elements, CGPoint(x: 250, y: 250), touchRadius: f.radius)
        XCTAssertEqual(stack.count, 4)
        let group = stack[1]
        XCTAssertEqual(group.elements.map(\.id), ["logo-b", "logo-a"])
        XCTAssertEqual(Layers.rowName(group), LayerRows.groupName(2))
    }

    func testAHoldOffTheSelectionOverTwoThingsBringsUpTheMenu() {
        XCTAssertEqual(CanvasGestures.holdOnElement(stack: 2, onSelected: false), .menu)
        XCTAssertEqual(CanvasGestures.holdOnElement(stack: 3, onSelected: false), .menu)
        // On something selected, Select multiple's meaning stays.
        XCTAssertEqual(CanvasGestures.holdOnElement(stack: 3, onSelected: true), .toggleInSelection)
        // Alone under the finger, a hold toggles as ever.
        XCTAssertEqual(CanvasGestures.holdOnElement(stack: 1, onSelected: false), .toggleInSelection)
    }

    func testTheHoldMenuOffersSelectBehindOnlyOverTwoOrMore() {
        XCTAssertEqual(HoldMenu.items(canPaste: false, canPastePage: false, behind: 2).first, .selectBehind)
        XCTAssertFalse(HoldMenu.items(canPaste: false, canPastePage: false, behind: 1).contains(.selectBehind))
        XCTAssertFalse(HoldMenu.items(canPaste: false, canPastePage: false).contains(.selectBehind))
    }

    func testSelectBehindStepsDownAtTheLastTapAndSelectsALockedOne() throws {
        let f = try fixture()
        var elements = f.elements
        if let i = elements.firstIndex(where: { $0.id == "cover" }) { elements[i].locked = true }
        var d = Design(title: "behind", width: 1080, height: 1080)
        d.pages = [Page(id: "p1", elements: elements)]
        let store = DesignStore(design: d)
        store.zoom = 1
        store.select("tiny")
        store.lastTapAt = CGPoint(x: 320, y: 320)
        store.selectBehind()
        XCTAssertEqual(store.selection, ["cover"])
        store.selectBehind()
        XCTAssertEqual(store.selection, ["card"])
        store.selectBehind()
        XCTAssertEqual(store.selection, ["backdrop"])
        store.selectBehind()
        XCTAssertEqual(store.selection, ["tiny"])
    }

    func testSelectBehindStepsOnlyFromOneWholeRowOfTheLayersList() throws {
        let f = try fixture()
        for row in f.oneRow {
            let selection = Set(try XCTUnwrap(row["selection"] as? [String]))
            let want = try XCTUnwrap(row["oneRow"] as? Bool)
            XCTAssertEqual(Layers.isOneRow(f.elements, selection: selection), want, "\(selection)")
        }
    }

    /// A fixture point, [x, y], or nil where the row has none (or null).
    private func pair(_ value: Any?) -> CGPoint? {
        guard let xy = value as? [Double], xy.count == 2 else { return nil }
        return CGPoint(x: xy[0], y: xy[1])
    }

    func testSelectBehindLooksAtTheLastTapOnTheSelectionElseItsMiddle() throws {
        let f = try fixture()
        let root = try SharedFixture.object("hit-stack")
        let rows = try XCTUnwrap(root["behindPoint"] as? [[String: Any]])
        for row in rows {
            let selection = Set(try XCTUnwrap(row["selection"] as? [String]))
            let tap = pair(row["tap"])
            let at = Layers.behindPoint(f.elements, selection: selection, lastTap: tap, touchRadius: f.radius)
            XCTAssertEqual(at, pair(row["at"]), "\(selection) tap \(String(describing: tap))")
            let steps = at.map { Layers.canStepBehind(f.elements, selection: selection, at: $0, touchRadius: f.radius) } ?? false
            let want = try XCTUnwrap(row["steps"] as? Bool)
            XCTAssertEqual(steps, want, "\(selection)")
        }
    }

    func testAHoldOnALockedBackdropOverAShapeListsBothUnderSelectBehind() throws {
        let f = try fixture()
        let lid = try XCTUnwrap(f.elements.first { $0.id == "lid" })
        XCTAssertTrue(CanvasGestures.isBackdrop(lid, page: CGSize(width: 1080, height: 1080), selection: []))
        XCTAssertGreaterThanOrEqual(Layers.hitStack(f.elements, CGPoint(x: 650, y: 350), touchRadius: f.radius).count, 2)
    }

    func testAltTabIsRefusedWithTwoLooseThingsSelected() throws {
        let f = try fixture()
        var d = Design(title: "behind", width: 1080, height: 1080)
        d.pages = [Page(id: "p1", elements: f.elements)]
        let store = DesignStore(design: d)
        store.zoom = 1
        store.selectLayers(["tiny", "cover"])
        store.lastTapAt = CGPoint(x: 320, y: 320)
        XCTAssertFalse(store.canSelectBehind)
        store.selectBehind()
        XCTAssertEqual(store.selection, ["tiny", "cover"])
    }

    func testASelectBehindRowTakesTheWholeGroupHiddenMembersToo() throws {
        let f = try fixture()
        var d = Design(title: "behind", width: 1080, height: 1080)
        d.pages = [Page(id: "p1", elements: f.elements)]
        let store = DesignStore(design: d)
        store.zoom = 1
        let row = try XCTUnwrap(store.hitStack(at: CGPoint(x: 850, y: 150)).first)
        XCTAssertEqual(row.id, "pair-a")
        store.selectStackRow(row)
        XCTAssertEqual(store.selection, ["pair-a", "pair-b"])
    }
}
