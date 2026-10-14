// Round 29's Forward and Backward, with the rows the Android twin's tests
// hold too: a group is one layer and never has the selection stepped in
// between its members, a step skips what the selection does not overlap,
// a member selected alone steps within its group, To front and To back
// keep a group whole, and a step at the front or the back changes nothing
// and says so.

import XCTest
import CoreGraphics
@testable import Canvia

@MainActor
final class LayerStepTests: XCTestCase {

    private func box(_ id: String, x: Double, y: Double, w: Double = 100, h: Double = 100,
                     group: String? = nil) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        el.group = group
        return el
    }

    private func ids(_ elements: [Element]) -> [String] { elements.map(\.id) }

    private func store(_ elements: [Element]) -> DesignStore {
        var d = Design(title: "layers", width: 1080, height: 1080)
        d.pages = [Page(id: "p1", elements: elements)]
        return DesignStore(design: d)
    }

    // MARK: blocks

    func testAGroupIsOneBlockWhereItsFrontMostMemberIs() {
        let page = [box("g1", x: 0, y: 0, group: "g"), box("e", x: 0, y: 0), box("g2", x: 0, y: 0, group: "g")]
        XCTAssertEqual(Layers.blocks(page).map(ids), [["e"], ["g1", "g2"]])
    }

    // MARK: Forward and Backward

    func testAStepNeverLeavesTheSelectionBetweenAGroupsMembers() {
        // E just below the group [G1, G2]: Forward lifts it past the whole
        // group, not between its members.
        let page = [box("e", x: 0, y: 0), box("g1", x: 50, y: 0, group: "g"), box("g2", x: 0, y: 50, group: "g")]
        XCTAssertEqual(ids(Layers.stepped(page, ids: ["e"], forward: true)), ["g1", "g2", "e"])
        let above = [box("g1", x: 50, y: 0, group: "g"), box("g2", x: 0, y: 50, group: "g"), box("e", x: 0, y: 0)]
        XCTAssertEqual(ids(Layers.stepped(above, ids: ["e"], forward: false)), ["e", "g1", "g2"])
        // A group stepped moves as one block.
        XCTAssertEqual(ids(Layers.stepped(page, ids: ["g1", "g2"], forward: false)), ["g1", "g2", "e"])
    }

    func testAStepSkipsWhatTheSelectionDoesNotOverlap() {
        let s = box("s", x: 0, y: 0)
        let far = box("x", x: 600, y: 600)
        let near = box("y", x: 50, y: 50)
        XCTAssertEqual(ids(Layers.stepped([s, far, near], ids: ["s"], forward: true)), ["x", "y", "s"])
        XCTAssertEqual(ids(Layers.stepped([near, far, s], ids: ["s"], forward: false)), ["s", "y", "x"])
        // Overlapping nothing, it goes past the very next block.
        let other = box("z", x: 900, y: 0)
        XCTAssertEqual(ids(Layers.stepped([s, far, other], ids: ["s"], forward: true)), ["x", "s", "z"])
        XCTAssertEqual(ids(Layers.stepped([far, other, s], ids: ["s"], forward: false)), ["x", "s", "z"])
        // Boxes that only touch do not overlap.
        let touching = box("t", x: 100, y: 0)
        XCTAssertEqual(ids(Layers.stepped([s, far, touching], ids: ["s"], forward: true)), ["x", "s", "t"])
    }

    func testAMemberSelectedAloneStepsWithinItsGroup() {
        let a = box("a", x: 0, y: 0)
        let g1 = box("g1", x: 0, y: 0, group: "g")
        let g2 = box("g2", x: 500, y: 500, group: "g")
        let g3 = box("g3", x: 50, y: 50, group: "g")
        let b = box("b", x: 0, y: 0)
        let page = [a, g1, g2, g3, b]
        XCTAssertEqual(ids(Layers.stepped(page, ids: ["g1"], forward: true)), ["a", "g2", "g3", "g1", "b"],
                       "past the member it overlaps, and no further than its group")
        XCTAssertEqual(ids(Layers.stepped(page, ids: ["g3"], forward: true)), ids(page), "already at its group's front")
        XCTAssertEqual(ids(Layers.stepped(page, ids: ["g3"], forward: false)), ["a", "g3", "g1", "g2", "b"])
    }

    func testAtTheFrontOrTheBackNothingChanges() {
        let page = [box("a", x: 0, y: 0), box("b", x: 0, y: 0)]
        XCTAssertEqual(ids(Layers.stepped(page, ids: ["b"], forward: true)), ["a", "b"])
        XCTAssertEqual(ids(Layers.stepped(page, ids: ["a"], forward: false)), ["a", "b"])
        XCTAssertEqual(ids(Layers.stepped(page, ids: ["a", "b"], forward: true)), ["a", "b"])
        // Spread out with the front-most at the front: nothing in front to
        // step past, so nothing changes, as on the Android twin.
        let spread = [box("a", x: 0, y: 0), box("m", x: 0, y: 0), box("b", x: 0, y: 0)]
        XCTAssertEqual(ids(Layers.stepped(spread, ids: ["a", "b"], forward: true)), ["a", "m", "b"])
        XCTAssertEqual(ids(Layers.stepped(spread, ids: ["a", "b"], forward: false)), ["a", "m", "b"])
    }

    func testTheAndroidTwinsFixtures() {
        // A group already split comes out in one run, where its front-most
        // member is.
        let split = [box("g1", x: 0, y: 0, group: "G"), box("e", x: 0, y: 0), box("g2", x: 0, y: 0, group: "G"),
                     box("f", x: 0, y: 0)]
        XCTAssertEqual(Layers.blocks(split).flatMap { $0 }.map(\.id), ["e", "g1", "g2", "f"])
        XCTAssertEqual(ids(Layers.stepped(split, ids: ["f"], forward: false)), ["e", "f", "g1", "g2"])
        XCTAssertEqual(ids(Layers.stepped(split, ids: ["g1", "g2"], forward: true)), ["e", "f", "g1", "g2"])
        XCTAssertEqual(ids(Layers.sentToEnd(split, ids: ["f"], front: false)), ["f", "e", "g1", "g2"])
        // Forward skips what does not overlap, to the nearest thing that does.
        let spread = [box("a", x: 0, y: 0), box("b", x: 300, y: 0), box("c", x: 600, y: 0), box("d", x: 50, y: 50)]
        XCTAssertEqual(ids(Layers.stepped(spread, ids: ["a"], forward: true)), ["b", "c", "d", "a"])
        XCTAssertEqual(ids(Layers.stepped(spread, ids: ["d"], forward: false)), ["d", "a", "b", "c"])
        // A member alone, within its group's run.
        let run = [box("x", x: 0, y: 0), box("g1", x: 0, y: 0, group: "G"), box("g2", x: 0, y: 0, group: "G"),
                   box("g3", x: 0, y: 0, group: "G"), box("y", x: 0, y: 0)]
        XCTAssertEqual(ids(Layers.stepped(run, ids: ["g1"], forward: true)), ["x", "g2", "g1", "g3", "y"])
        XCTAssertEqual(ids(Layers.sentToEnd(run, ids: ["g3"], front: false)), ["x", "g3", "g1", "g2", "y"])
    }

    // MARK: To front and To back

    func testToFrontAndToBackKeepAGroupWhole() {
        let page = [box("g1", x: 0, y: 0, group: "g"), box("e", x: 0, y: 0), box("g2", x: 0, y: 0, group: "g")]
        XCTAssertEqual(ids(Layers.sentToEnd(page, ids: ["e"], front: true)), ["g1", "g2", "e"])
        XCTAssertEqual(ids(Layers.sentToEnd(page, ids: ["g1", "g2"], front: false)), ["g1", "g2", "e"])
        let grouped = [box("a", x: 0, y: 0), box("g1", x: 0, y: 0, group: "g"), box("g2", x: 0, y: 0, group: "g"),
                       box("b", x: 0, y: 0)]
        XCTAssertEqual(ids(Layers.sentToEnd(grouped, ids: ["g1"], front: true)), ["a", "g2", "g1", "b"],
                       "a member alone goes to its group's front")
    }

    // MARK: the store

    func testAStepIsOneUndoAndAtTheFrontItIsRefusedAndSaid() {
        let s = store([box("e", x: 0, y: 0), box("g1", x: 50, y: 0, group: "g"), box("g2", x: 0, y: 50, group: "g")])
        s.select("e")
        s.reorderSelected(.forward)
        XCTAssertEqual(ids(s.page.elements), ["g1", "g2", "e"])
        s.undo()
        XCTAssertEqual(ids(s.page.elements), ["e", "g1", "g2"], "one step")
        s.redo()
        s.select("e")
        s.reorderSelected(.forward)
        XCTAssertEqual(ids(s.page.elements), ["g1", "g2", "e"])
        XCTAssertEqual(s.haptic.kind, .reject)
        XCTAssertEqual(s.announcement, "Already at the front")
        s.reorderSelected(.front)
        XCTAssertEqual(s.announcement, "Already at the front")
        s.select("g1")
        s.reorderSelected(.back)
        s.reorderSelected(.backward)
        XCTAssertEqual(s.announcement, "Already at the back")
        XCTAssertEqual(ids(s.page.elements), ["g1", "g2", "e"])
    }
}
