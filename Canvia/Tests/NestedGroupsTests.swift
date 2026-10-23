// Round 31's groups: groups inside groups — the "subgroups" key, Group and
// Ungroup a level at a time, a tap going a level deeper, Layers' tree, the
// copies and the exports — and a group turned as a whole, its "groupTurn"
// and its turned frame. The shared fixture Fixtures/nested-groups.json is
// the Android twin's too, and both phones' tests hold the same rows.

import XCTest
@testable import Canvia

@MainActor
final class NestedGroupsTests: XCTestCase {

    /// A fixture's JSON: from the test bundle, or beside this file.
    private func fixture(_ name: String, file: StaticString = #filePath) throws -> Data {
        if let url = Bundle(for: NestedGroupsTests.self).url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appendingPathComponent("Fixtures/\(name).json"))
    }

    /// The fixture's design: a card group holding a logo group (mark and
    /// word) and a heading, and a loose box beside it.
    private func card() throws -> Design {
        try JSONDecoder().decode(Design.self, from: fixture("nested-groups"))
    }

    private func json(_ el: Element) throws -> [String: Any] {
        let data = try JSONEncoder().encode(el)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func box(_ id: String, x: Double, y: Double, w: Double = 100, h: Double = 100,
                     rotation: Double = 0, group: String? = nil, subgroups: [String]? = nil) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        el.rotation = rotation
        el.group = group
        el.subgroups = subgroups
        return el
    }

    private func store(_ elements: [Element]) -> DesignStore {
        var d = Design(title: "groups", width: 1080, height: 1080)
        d.pages = [Page(elements: elements)]
        return DesignStore(design: d)
    }

    private func assertSame(_ a: [Element], _ b: [Element], accuracy: Double = 1e-6,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.map(\.id), b.map(\.id), file: file, line: line)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(x.x, y.x, accuracy: accuracy, "\(x.id) x", file: file, line: line)
            XCTAssertEqual(x.y, y.y, accuracy: accuracy, "\(x.id) y", file: file, line: line)
            XCTAssertEqual(x.w, y.w, accuracy: accuracy, "\(x.id) w", file: file, line: line)
            XCTAssertEqual(x.h, y.h, accuracy: accuracy, "\(x.id) h", file: file, line: line)
            let turn = abs(x.rotation - y.rotation).truncatingRemainder(dividingBy: 360)
            XCTAssertEqual(min(turn, 360 - turn), 0, accuracy: accuracy, "\(x.id) turn", file: file, line: line)
        }
    }

    // MARK: the file

    func testTheSharedFixtureReadsTwoLevels() throws {
        let els = try card().pages[0].elements
        XCTAssertEqual(els.map(\.id), ["loose", "mark", "word", "heading"])
        XCTAssertEqual(els.map(Groups.chain), [[], ["g-card", "g-logo"], ["g-card", "g-logo"], ["g-card"]])
        XCTAssertEqual(Groups.members(els, of: "g-logo"), ["mark", "word"])
        XCTAssertEqual(Groups.members(els, of: "g-card"), ["mark", "word", "heading"])
    }

    func testTheKeysRoundTripAndAreLeftOutWhenEmpty() throws {
        let design = try card()
        let again = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(again, design)
        let els = design.pages[0].elements
        XCTAssertEqual(try json(els[1])["subgroups"] as? [String], ["g-logo"])
        XCTAssertNil(try json(els[3])["subgroups"], "no key when there is no level below")
        XCTAssertNil(try json(els[0])["subgroups"])
        XCTAssertNil(try json(els[0])["groupTurn"])
    }

    func testAnEmptyListAZeroTurnAndLevelsWithoutAGroupAreNoKey() throws {
        let read = { (text: String) in try JSONDecoder().decode(Element.self, from: Data(text.utf8)) }
        let empty = try read(#"{"id":"e","type":"shape","group":"g","subgroups":[],"groupTurn":0}"#)
        XCTAssertNil(empty.subgroups)
        XCTAssertNil(empty.groupTurn)
        let orphan = try read(#"{"id":"e","type":"shape","subgroups":["g2"],"groupTurn":30}"#)
        XCTAssertNil(orphan.subgroups, "levels below no group are none")
        XCTAssertNil(orphan.groupTurn)
        let turned = try read(#"{"id":"e","type":"shape","group":"g","groupTurn":30}"#)
        XCTAssertEqual(turned.groupTurn, 30)
        XCTAssertEqual(try json(turned)["groupTurn"] as? Double, 30)
    }

    // MARK: Group and Ungroup, a level at a time

    func testGroupingAGroupKeepsItAndUngroupGivesItBack() {
        let s = store([box("mark", x: 0, y: 0, group: "g-logo"), box("word", x: 120, y: 0, group: "g-logo"),
                       box("heading", x: 0, y: 200)])
        s.select("mark")
        XCTAssertEqual(s.selection, ["mark", "word"], "a tap takes the group")
        s.select("heading", additive: true)
        s.groupSelected()
        let card = s.element("heading")?.group
        XCTAssertNotNil(card)
        XCTAssertEqual(s.page.elements.map(\.group), [card, card, card])
        XCTAssertEqual(s.page.elements.map(\.subgroups), [["g-logo"], ["g-logo"], nil])
        s.select("mark")
        XCTAssertEqual(s.selection, ["mark", "word", "heading"], "a tap takes the outermost group")

        s.ungroupSelected()
        XCTAssertEqual(s.page.elements.map(\.group), ["g-logo", "g-logo", nil], "the logo group comes back")
        XCTAssertEqual(s.page.elements.map(\.subgroups), [nil, nil, nil])
        s.select("mark")
        XCTAssertEqual(s.selection, ["mark", "word"], "and still works")

        s.ungroupSelected()
        XCTAssertEqual(s.page.elements.map(\.group), [nil, nil, nil])
        s.undo()
        XCTAssertEqual(s.page.elements.map(\.group), ["g-logo", "g-logo", nil], "one undo step each")
        s.undo()
        XCTAssertEqual(s.page.elements.map(\.group), [card, card, card])
    }

    func testThePureRulesStepByStep() {
        let els = [box("a", x: 0, y: 0, group: "g1", subgroups: ["g2"]), box("b", x: 0, y: 0)]
        let grouped = Groups.grouped(els, ids: ["a", "b"], into: "g0")
        XCTAssertEqual(grouped.map(Groups.chain), [["g0", "g1", "g2"], ["g0"]])
        let once = Groups.ungrouped(grouped, ids: ["a", "b"])
        XCTAssertEqual(once.map(Groups.chain), [["g1", "g2"], []])
        let twice = Groups.ungrouped(once, ids: ["a", "b"])
        XCTAssertEqual(twice.map(Groups.chain), [["g2"], []])
        let thrice = Groups.ungrouped(twice, ids: ["a", "b"])
        XCTAssertEqual(thrice.map(Groups.chain), [[], []])
        XCTAssertEqual(thrice.map(\.subgroups), [nil, nil])
    }

    func testGroupAndUngroupLetATurnGo() {
        var a = box("a", x: 0, y: 0, group: "g")
        a.groupTurn = 30
        XCTAssertNil(Groups.grouped([a], ids: ["a"], into: "g0")[0].groupTurn)
        XCTAssertNil(Groups.ungrouped([a], ids: ["a"])[0].groupTurn)
    }

    // MARK: a tap a level deeper

    /// Shared rows: what is selected, the thing tapped, and what the tap
    /// selects then — nil where the tap selects as ever, the outermost group.
    func testTapDepthTable() throws {
        let els = try card().pages[0].elements
        let rows: [(Set<String>, String, Set<String>?)] = [
            (["mark", "word", "heading"], "mark", ["mark", "word"]),
            (["mark", "word"], "mark", ["mark"]),
            (["mark"], "mark", nil),
            (["mark", "word", "heading"], "heading", ["heading"]),
            (["mark", "word"], "word", ["word"]),
            // Not one of its groups: selected as ever.
            (["loose", "mark"], "mark", nil),
            (["loose"], "loose", nil),
            ([], "mark", nil),
        ]
        for (selection, tapped, next) in rows {
            XCTAssertEqual(Groups.deeper(els, selection: selection, tapped: tapped), next, "\(selection) tap \(tapped)")
        }
    }

    func testTapsGoInALevelAtATimeOnTheCanvas() throws {
        let s = DesignStore(design: try card())
        XCTAssertFalse(s.selectMember("mark"), "the first tap takes the group")
        s.select("mark")
        XCTAssertEqual(s.selection, ["mark", "word", "heading"])
        XCTAssertTrue(s.selectMember("mark"))
        XCTAssertEqual(s.selection, ["mark", "word"], "the second the logo")
        XCTAssertTrue(s.selectMember("mark"))
        XCTAssertEqual(s.selection, ["mark"], "the third the mark alone")
        XCTAssertFalse(s.selectMember("mark"))
    }

    // MARK: Layers' tree

    func testLayersListGroupsAsATreeIndentedPerLevel() throws {
        let els = try card().pages[0].elements
        let folded = LayerRows.rows(els, expanded: [])
        XCTAssertEqual(folded.map(\.id), ["group:g-card", "loose"])
        XCTAssertEqual(folded.first?.elements.map(\.id), ["heading", "word", "mark"])
        let open = LayerRows.rows(els, expanded: ["g-card"])
        XCTAssertEqual(open.map(\.id), ["group:g-card", "heading", "group:g-logo", "loose"])
        XCTAssertEqual(open.map(\.depth), [0, 1, 1, 0])
        let both = LayerRows.rows(els, expanded: ["g-card", "g-logo"])
        XCTAssertEqual(both.map(\.id), ["group:g-card", "heading", "group:g-logo", "word", "mark", "loose"])
        XCTAssertEqual(both.map(\.depth), [0, 1, 1, 2, 2, 0])
        XCTAssertEqual(both.map(\.movable), [true, false, false, false, false, true])
    }

    func testDraggingAGroupRowMovesItsWholeSubtree() throws {
        let els = try card().pages[0].elements
        let rows = LayerRows.rows(els, expanded: ["g-card", "g-logo"])
        // The card's row dropped below the loose box: to the very back.
        let moved = LayerRows.moved(els, rows: rows, from: [0], to: rows.count)
        XCTAssertEqual(moved.map(\.id), ["mark", "word", "heading", "loose"])
        XCTAssertEqual(moved.map(Groups.chain), [["g-card", "g-logo"], ["g-card", "g-logo"], ["g-card"], []])
    }

    // MARK: copies and exports

    func testCopiesKeepEveryLevelUnderFreshKeys() throws {
        let els = try card().pages[0].elements
        let copies = Copies.of(els)
        let chains = copies.map(Groups.chain)
        XCTAssertEqual(chains[0], [])
        XCTAssertEqual(chains[1], chains[2], "the logo's members still share both levels")
        XCTAssertEqual(chains[3], [chains[1][0]], "the heading shares the outer level")
        XCTAssertEqual(chains[1].count, 2)
        XCTAssertFalse(chains[1].contains("g-card") || chains[1].contains("g-logo"), "new keys")
        XCTAssertNotEqual(chains[1][0], chains[1][1])
    }

    func testNestedRunsWrapALevelAtATime() throws {
        let els = try card().pages[0].elements
        var items: [(el: Element?, part: String)] = [(el: nil, part: "bg")]
        for el in els { items.append((el: el, part: el.id)) }
        let out = Groups.nested(items) { _, members, inner in
            "[" + inner.joined(separator: " ") + "]#\(members.count)"
        }
        XCTAssertEqual(out, ["bg", "loose", "[[mark word]#2 heading]#3"])
        // A group of one is not wrapped; members apart are two runs.
        let apart = [box("a", x: 0, y: 0, group: "g"), box("b", x: 0, y: 0), box("c", x: 0, y: 0, group: "g")]
        var parts: [(el: Element?, part: String)] = []
        for el in apart { parts.append((el: el, part: el.id)) }
        let split = Groups.nested(parts) { _, _, inner in
            "[" + inner.joined() + "]"
        }
        XCTAssertEqual(split, ["a", "b", "c"])
    }

    func testTheSVGNestsAGForEachLevel() throws {
        let nested = try card()
        var flat = nested
        for i in flat.pages[0].elements.indices {
            flat.pages[0].elements[i].group = nil
            flat.pages[0].elements[i].subgroups = nil
        }
        let wrapped = SVGExporter.svg(design: nested, page: nested.pages[0])
        let plain = SVGExporter.svg(design: flat, page: flat.pages[0])
        XCTAssertEqual(wrapped.components(separatedBy: "<g>").count - plain.components(separatedBy: "<g>").count, 2,
                       "one <g> for the card, one inside it for the logo")
        XCTAssertTrue(wrapped.contains("</g></g>"))
    }

    func testTheSlideNestsAGrpSpForEachLevel() throws {
        let design = try card()
        let slide = PptxExporter.slide(design: design, page: design.pages[0], number: 1, previous: nil, firstImage: 1)
        XCTAssertEqual(slide.xml.components(separatedBy: "<p:grpSp>").count - 1, 2)
        XCTAssertTrue(slide.xml.contains("<a:chOff"))
    }

    // MARK: a group turned as a whole

    /// Two boxes, one turned a little: their upright box is 0,0 to 210,140.
    private var pair: [Element] {
        [box("a", x: 0, y: 0, w: 100, h: 50, group: "g"),
         box("b", x: 150, y: 80, w: 60, h: 60, rotation: 0, group: "g")]
    }

    func testTheFrameOfMembersTurned30IsTheirUprightBox() {
        let upright = Geometry.groupFrame(pair, angle: 0)
        XCTAssertEqual(upright.upright, CGRect(x: 0, y: 0, width: 210, height: 140))
        let turned = Geometry.rotate(pair, around: upright.center, by: 30)
        let frame = Geometry.groupFrame(turned, angle: 30)
        XCTAssertEqual(Double(frame.size.width), 210, accuracy: 1e-6)
        XCTAssertEqual(Double(frame.size.height), 140, accuracy: 1e-6)
        XCTAssertEqual(Double(frame.center.x), Double(upright.center.x), accuracy: 1e-6)
        XCTAssertEqual(Double(frame.center.y), Double(upright.center.y), accuracy: 1e-6)
        XCTAssertEqual(frame.angle, 30)
        XCTAssertEqual(frame.element.rotation, 30)
        // The upright box round them is bigger: what the frame replaces.
        XCTAssertGreaterThan(Geometry.union(turned.map(Geometry.aabb)).width, 210)
    }

    func testTurnThenScaleThenTurnBackGivesTheOriginalGeometry() {
        var members = pair
        members[1].rotation = 10
        let start = Geometry.groupFrame(members, angle: 0)
        let turned = Geometry.rotate(members, around: start.center, by: 30)
        let frame = Geometry.groupFrame(turned, angle: 30)
        let bigger = CGRect(origin: frame.upright.origin,
                            size: CGSize(width: frame.size.width * 2, height: frame.size.height * 2))
        let scaled = Geometry.scale(turned, frame: frame, to: bigger)
        XCTAssertEqual(scaled[0].w, 200, accuracy: 1e-6, "scaled in the frame's own axes")
        XCTAssertEqual(scaled[1].rotation, 40, accuracy: 1e-6, "a turned member keeps its turn")
        let grown = Geometry.groupFrame(scaled, angle: 30)
        XCTAssertEqual(Double(grown.size.width), Double(frame.size.width) * 2, accuracy: 1e-6)
        // Back down from the same corner, which stayed put on the page.
        let back = Geometry.scale(scaled, frame: grown, to: CGRect(origin: grown.upright.origin, size: frame.size))
        assertSame(back, turned)
        let straight = Geometry.rotate(back, around: Geometry.groupFrame(back, angle: 30).center, by: -30)
        assertSame(straight, members)
    }

    func testPositionsTurnSetsTheGroupsTurnAndTurnTo0StraightensIt() {
        let s = store(pair)
        s.select("a")
        XCTAssertEqual(s.selectedGroupTurn, 0)
        XCTAssertNil(s.turnedGroupFrame, "upright: today's box")
        s.setGroupTurn(30)
        XCTAssertEqual(s.page.elements.map(\.groupTurn), [30, 30], "written on every member")
        XCTAssertEqual(s.selectedGroupTurn, 30)
        let frame = s.turnedGroupFrame
        XCTAssertNotNil(frame)
        XCTAssertEqual(Double(frame?.size.width ?? 0), 210, accuracy: 1e-6)
        XCTAssertEqual(Double(frame?.size.height ?? 0), 140, accuracy: 1e-6)
        s.rotateSelection(by: 15)
        XCTAssertEqual(s.selectedGroupTurn ?? 0, 45, accuracy: 1e-9, "Rotate by adds to the turn")
        s.setGroupTurn(0)
        XCTAssertEqual(s.page.elements.map(\.groupTurn), [nil, nil], "no key at 0")
        assertSame(s.page.elements, pair)
        s.undo()
        XCTAssertEqual(s.selectedGroupTurn ?? 0, 45, accuracy: 1e-9, "one undo step")
    }

    func testSeveralThatAreNoGroupKeepTheUprightBox() {
        let s = store([box("a", x: 0, y: 0), box("b", x: 200, y: 0)])
        s.select("a")
        s.select("b", additive: true)
        XCTAssertNil(s.selectedGroupTurn)
        XCTAssertNil(s.turnedGroupFrame)
        s.setGroupTurn(30)
        XCTAssertEqual(s.page.elements.map(\.rotation), [0, 0], "Turn is a group's alone")
    }

    /// Shared with the Android twin: Position's Width for a turned group
    /// scales it evenly about its frame's middle, which stays put.
    func testPositionsWidthScalesAGroupAboutItsFramesMiddle() throws {
        let s = store(pair)
        s.select("a")
        s.setGroupTurn(30)
        let before = try XCTUnwrap(s.turnedGroupFrame)
        s.scaleGroup(by: 2)
        let after = try XCTUnwrap(s.turnedGroupFrame)
        XCTAssertEqual(Double(after.size.width), Double(before.size.width) * 2, accuracy: 1e-6)
        XCTAssertEqual(Double(after.size.height), Double(before.size.height) * 2, accuracy: 1e-6)
        XCTAssertEqual(Double(after.center.x), Double(before.center.x), accuracy: 1e-6)
        XCTAssertEqual(Double(after.center.y), Double(before.center.y), accuracy: 1e-6)
        XCTAssertEqual(after.angle, 30)
    }

    /// Shared with the Android twin: a group with a member locked keeps the
    /// upright box, and turning it writes no groupTurn on any member.
    func testAGroupWithALockedMemberIsNeverTurnedAsOne() {
        var members = pair
        members[1].locked = true
        let s = store(members)
        s.select("a")
        XCTAssertEqual(s.selection, ["a", "b"])
        XCTAssertNil(s.selectedGroupTurn)
        XCTAssertNil(s.turnedGroupFrame)
        s.rotateSelection(by: 30)
        s.setGroupTurn(30)
        XCTAssertEqual(s.page.elements.map(\.groupTurn), [nil, nil])
    }

    /// Shared with the Android twin: Ungroup takes off each selected
    /// member's outermost group, whatever level is selected — with the logo
    /// alone selected, it is the card the logo leaves, and the heading stays
    /// in the card.
    func testUngroupTakesOffTheOutermostLevelWhateverLevelIsSelected() throws {
        let els = try card().pages[0].elements
        let out = Groups.ungrouped(els, ids: ["mark", "word"])
        XCTAssertEqual(out.map(Groups.chain), [[], ["g-logo"], ["g-logo"], ["g-card"]])
    }

    func testAFlipMirrorsTheTurn() {
        var a = box("a", x: 0, y: 0, group: "g")
        a.groupTurn = 30
        let flipped = Geometry.flipAll([a], box: Geometry.aabb(a), horizontal: true)
        XCTAssertEqual(flipped[0].groupTurn, 330)
    }
}
