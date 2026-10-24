// Round 33's group membership: one thing out of a group, or one into it,
// the rest kept grouped (Groups.removedFromGroup, Groups.addedToGroup),
// Layers' drag across a group's edge (LayerRows.drop) and More's Remove
// from group. The Android twin's suite holds the same rows, over the shared
// Fixtures/nested-groups.json.

import XCTest
@testable import Canvia

@MainActor
final class GroupMembershipTests: XCTestCase {

    /// A fixture's JSON: from the test bundle, or beside this file.
    private func fixture(_ name: String, file: StaticString = #filePath) throws -> Data {
        if let url = Bundle(for: GroupMembershipTests.self).url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appendingPathComponent("Fixtures/\(name).json"))
    }

    /// Back to front: loose; mark and word in g-card ▸ g-logo; heading in
    /// g-card.
    private func card() throws -> [Element] {
        try JSONDecoder().decode(Design.self, from: fixture("nested-groups")).pages[0].elements
    }

    private func box(_ id: String, group: String? = nil, subgroups: [String]? = nil,
                     turn: Double? = nil, locked: Bool = false) -> Element {
        var el = Element.shape("rect", w: 100, h: 100)
        el.id = id
        el.group = group
        el.subgroups = subgroups
        el.groupTurn = turn
        el.locked = locked
        return el
    }

    private func store(_ elements: [Element]) -> DesignStore {
        var d = Design(title: "groups", width: 1080, height: 1080)
        d.pages = [Page(elements: elements)]
        return DesignStore(design: d)
    }

    // MARK: Groups.removedFromGroup

    func testRemovingDropsTheInnermostLevelAndKeepsTheRestGrouped() throws {
        let out = Groups.removedFromGroup(try card(), ids: ["heading"])
        XCTAssertEqual(out.map(\.id), ["loose", "mark", "word", "heading"], "the order is kept")
        XCTAssertEqual(out.map(Groups.chain), [[], ["g-card", "g-logo"], ["g-card", "g-logo"], []])
    }

    func testAGroupLeftWithOneMemberLetsItGoToo() throws {
        let out = Groups.removedFromGroup(try card(), ids: ["mark"])
        XCTAssertEqual(out.map(Groups.chain), [[], ["g-card"], ["g-card"], ["g-card"]],
                       "mark leaves g-logo, and word, alone in it, leaves it too")
        let pair = Groups.removedFromGroup([box("a", group: "g"), box("b", group: "g")], ids: ["a"])
        XCTAssertEqual(pair.map(Groups.chain), [[], []])
    }

    func testAGroupsTurnGoesWithLeavingIt() {
        let three = [box("a", group: "g", turn: 30), box("b", group: "g", turn: 30), box("c", group: "g", turn: 30)]
        let out = Groups.removedFromGroup(three, ids: ["a"])
        XCTAssertEqual(out.map(\.groupTurn), [nil, 30, 30])
        let pair = Groups.removedFromGroup(Array(three.prefix(2)), ids: ["a"])
        XCTAssertEqual(pair.map(\.groupTurn), [nil, nil], "a group whose members are gone loses its turn")
        let inner = Groups.removedFromGroup([box("a", group: "g", subgroups: ["h"], turn: 30),
                                             box("b", group: "g", subgroups: ["h"], turn: 30),
                                             box("c", group: "g", subgroups: ["h"], turn: 30)], ids: ["a"])
        XCTAssertEqual(inner.map(\.groupTurn), [30, 30, 30], "still in g, so still turned with it")
    }

    func testRemovingWhatIsInNoGroupChangesNothing() throws {
        let els = try card()
        XCTAssertEqual(Groups.removedFromGroup(els, ids: ["loose"]), els)
        XCTAssertEqual(Groups.removedFromGroup(els, ids: []), els)
    }

    // MARK: Groups.addedToGroup

    func testAddingTakesTheGroupsChainAndGoesAboveItsTopMember() throws {
        let logo = Groups.addedToGroup(try card(), ids: ["loose"], groupId: "g-logo")
        XCTAssertEqual(logo.map(\.id), ["mark", "word", "loose", "heading"])
        XCTAssertEqual(logo.map(Groups.chain), [["g-card", "g-logo"], ["g-card", "g-logo"], ["g-card", "g-logo"], ["g-card"]])
        let outer = Groups.addedToGroup(try card(), ids: ["loose"], groupId: "g-card")
        XCTAssertEqual(outer.map(\.id), ["mark", "word", "heading", "loose"])
        XCTAssertEqual(outer.last.map(Groups.chain), ["g-card"])
    }

    func testAddingKeepsTheirOrderAndTakesTheGroupsTurn() {
        let els = [box("x"), box("a", group: "g", turn: 45), box("y"), box("b", group: "g", turn: 45), box("z")]
        let out = Groups.addedToGroup(els, ids: ["x", "y"], groupId: "g")
        XCTAssertEqual(out.map(\.id), ["a", "b", "x", "y", "z"])
        XCTAssertEqual(out.map(\.groupTurn), [45, 45, 45, 45, nil])
    }

    /// Shared rows: c joins g, and k, left with d alone, lets d go — no
    /// group of one, and no turn of a group d is no longer in.
    func testAJoinersOldGroupOfOneGoes() {
        let els = [box("a", group: "g", turn: 20), box("b", group: "g", turn: 20),
                   box("c", group: "k", turn: 10), box("d", group: "k", turn: 10)]
        let out = Groups.addedToGroup(els, ids: ["c"], groupId: "g")
        XCTAssertEqual(out.map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(out.map(Groups.chain), [["g"], ["g"], ["g"], []])
        XCTAssertEqual(out.map(\.groupTurn), [20, 20, 20, nil])
    }

    /// Shared rows: only the groups the edit left are tidied — a group of
    /// one already on the page keeps its member and its turn either way.
    func testAGroupOfOneTheEditDidNotTouchStays() {
        let els = [box("a", group: "g"), box("b", group: "g"), box("c", group: "g"), box("x"),
                   box("w", group: "k", turn: 15)]
        let removed = Groups.removedFromGroup(els, ids: ["a"])
        XCTAssertEqual(removed.last.map(Groups.chain), ["k"])
        XCTAssertEqual(removed.last?.groupTurn, 15)
        let added = Groups.addedToGroup(els, ids: ["x"], groupId: "g")
        XCTAssertEqual(added.first { $0.id == "x" }.map(Groups.chain), ["g"])
        XCTAssertEqual(added.first { $0.id == "w" }.map(Groups.chain), ["k"])
        XCTAssertEqual(added.first { $0.id == "w" }?.groupTurn, 15)
    }

    func testAddingAMemberOrToNoGroupChangesNothing() throws {
        let els = try card()
        XCTAssertEqual(Groups.addedToGroup(els, ids: ["mark"], groupId: "g-card"), els)
        XCTAssertEqual(Groups.addedToGroup(els, ids: ["loose"], groupId: "g-none"), els)
    }

    func testTheFileKeepsItsKeys() throws {
        let out = Groups.addedToGroup(try card(), ids: ["loose"], groupId: "g-logo")
        let data = try JSONEncoder().encode(out[2])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["group"] as? String, "g-card")
        XCTAssertEqual(json["subgroups"] as? [String], ["g-logo"])
    }

    // MARK: Layers' drag

    func testARowDroppedAmongAnOpenedGroupsRowsJoinsIt() throws {
        let els = try card()
        // group:g-card, heading, group:g-logo, word, mark, loose
        let rows = LayerRows.rows(els, expanded: ["g-card", "g-logo"])
        XCTAssertEqual(LayerRows.drop(rows, from: [5], to: 1), .join("g-card"), "just under the header")
        XCTAssertEqual(LayerRows.drop(rows, from: [5], to: 4), .join("g-logo"), "the innermost group")
        XCTAssertEqual(LayerRows.drop(rows, from: [5], to: 0), .reorder, "above the group")
        XCTAssertEqual(LayerRows.drop(rows, from: [0], to: 6), .reorder, "a group's row reorders")
    }

    func testAMembersRowDroppedPastItsGroupLeavesIt() throws {
        let rows = LayerRows.rows(try card(), expanded: ["g-card", "g-logo"])
        XCTAssertEqual(LayerRows.drop(rows, from: [3], to: 6), .leave, "past the last row")
        XCTAssertEqual(LayerRows.drop(rows, from: [3], to: 2), .leave, "above g-logo, still in g-card")
        XCTAssertEqual(LayerRows.drop(rows, from: [4], to: 3), .reorder, "within its own group")
        XCTAssertEqual(LayerRows.drop(rows, from: [1], to: 1), .reorder, "where it was")
        XCTAssertEqual(rows.map(\.draggable), [true, true, false, true, true, true])
    }

    func testTheGroupAboveARow() throws {
        let folded = LayerRows.rows(try card(), expanded: [])
        XCTAssertEqual(LayerRows.groupAbove(folded, at: 1), "g-card")
        let open = LayerRows.rows(try card(), expanded: ["g-card"])
        XCTAssertEqual(LayerRows.groupAbove(open, at: 3), "g-card", "past its opened rows")
        XCTAssertNil(LayerRows.groupAbove(open, at: 1), "heading's row above is a header a level up")
        XCTAssertNil(LayerRows.groupAbove(open, at: 0))
    }

    // MARK: the store

    func testRemoveFromGroupIsOneUndoNamedUngroup() throws {
        let s = store(try card())
        s.select("mark")
        XCTAssertFalse(s.canRemoveFromGroup, "a whole outermost group")
        s.selectMember("heading")
        XCTAssertEqual(s.selection, ["heading"])
        XCTAssertTrue(s.canRemoveFromGroup, "a tap a level deeper")
        s.removeSelectedFromGroup()
        XCTAssertNil(s.element("heading")?.group)
        XCTAssertEqual(s.undoLabel, "Ungroup")
        s.undo()
        XCTAssertEqual(s.element("heading")?.group, "g-card")
    }

    func testADragIntoAGroupIsOneUndoNamedGroup() throws {
        let s = store(try card())
        let rows = LayerRows.rows(s.page.elements, expanded: ["g-card"])
        s.moveLayers(rows, from: [3], to: 1)
        XCTAssertEqual(s.element("loose").map(Groups.chain), ["g-card"])
        XCTAssertEqual(s.undoLabel, "Group")
        s.undo()
        XCTAssertNil(s.element("loose")?.group)
    }

    func testALockedElementOrPageIsRefused() {
        let s = store([box("a", group: "g", locked: true), box("b", group: "g"), box("c", group: "g")])
        let before = s.haptic.serial
        s.removeFromGroup(["a"])
        XCTAssertEqual(s.element("a")?.group, "g")
        XCTAssertEqual(s.haptic.kind, .reject)
        XCTAssertEqual(s.haptic.serial, before + 1)
        s.setPageLocked(true)
        s.removeFromGroup(["b"])
        XCTAssertEqual(s.element("b")?.group, "g")
        XCTAssertEqual(s.haptic.kind, .reject)
    }
}
