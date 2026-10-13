// The Layers sheet: an element's `hidden` and `layerName` in the file,
// hidden elements left out of everything that draws, sounds, reads or hits,
// hiding, locking and renaming as one undo each, the rows Layers lists and
// how a drag among them reorders the page, and Overlapping.

import XCTest
import UIKit
@testable import Canvia

@MainActor
final class LayersTests: XCTestCase {

    private func json(_ el: Element) throws -> [String: Any] {
        let data = try JSONEncoder().encode(el)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func element(_ json: String) throws -> Element {
        try JSONDecoder().decode(Element.self, from: Data(json.utf8))
    }

    private func box(_ id: String, x: Double, y: Double, w: Double = 100, h: Double = 100,
                     group: String? = nil) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        el.group = group
        return el
    }

    private func design(_ elements: [Element], width: Double = 1080, height: Double = 1080) -> Design {
        var d = Design(title: "layers", width: width, height: height)
        d.pages = [Page(elements: elements)]
        return d
    }

    // MARK: the file

    func testAnElementWithoutTheKeysIsShownUnnamedAndWrittenWithoutThem() throws {
        let el = try element(#"{"id":"e1","type":"shape","shapeId":"rect"}"#)
        XCTAssertNil(el.hidden)
        XCTAssertFalse(el.isHidden)
        XCTAssertNil(el.layerName)
        let out = try json(el)
        XCTAssertNil(out["hidden"])
        XCTAssertNil(out["layerName"])
    }

    func testHiddenAndANameRoundTrip() throws {
        let el = try element(#"{"id":"e1","type":"shape","shapeId":"rect","hidden":true,"layerName":"Logo"}"#)
        XCTAssertEqual(el.hidden, true)
        XCTAssertEqual(el.layerName, "Logo")
        let out = try json(el)
        XCTAssertEqual(out["hidden"] as? Bool, true)
        XCTAssertEqual(out["layerName"] as? String, "Logo")
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el)), el)
    }

    func testFalseAndBlankAreNeverKept() throws {
        let el = try element(#"{"id":"e1","type":"shape","hidden":false,"layerName":"   "}"#)
        XCTAssertNil(el.hidden, "shown is the key's absence, never false")
        XCTAssertNil(el.layerName, "a blank name is no name")
        XCTAssertNil(try json(el)["hidden"])
        XCTAssertNil(try json(el)["layerName"])
    }

    func testANameIsTrimmedAndCutTo60() {
        XCTAssertEqual(LayerNames.maxLength, 60)
        XCTAssertEqual(LayerNames.cleaned("  Logo \n"), "Logo")
        XCTAssertNil(LayerNames.cleaned("   "))
        XCTAssertEqual(LayerNames.cleaned(String(repeating: "a", count: 75))?.count, 60)
        XCTAssertEqual(LayerNames.cleaned(String(repeating: "a", count: 59) + "  b"), String(repeating: "a", count: 59),
                       "cut, then trimmed again")
    }

    // MARK: hidden is never drawn, heard, read or hit

    func testDrawnElementsLeaveHiddenOnesOut() {
        var master = Page(elements: [box("m1", x: 0, y: 0), box("m2", x: 0, y: 0)])
        master.elements[1].hidden = true
        var page = Page(elements: [box("p1", x: 0, y: 0), box("p2", x: 0, y: 0)])
        page.elements[0].hidden = true
        var d = Design(title: "drawn", width: 400, height: 400)
        d.pages = [master, page]
        d.masterPageId = master.id
        XCTAssertEqual(d.masterElements(behind: d.pages[1]).map(\.id), ["m1"])
        XCTAssertEqual(d.drawnElements(on: d.pages[1]).map(\.id), ["m1", "p2"])
        XCTAssertEqual(d.drawnElements(on: d.pages[0]).map(\.id), ["m1"], "the master's own page leaves it out too")
    }

    func testTheSVGLeavesAHiddenElementOut() {
        let shown = design([box("a", x: 10, y: 10)], width: 400, height: 400)
        var withHidden = shown
        var ghost = box("b", x: 200, y: 200)
        ghost.fill = .solid("#ff0000")
        ghost.hidden = true
        withHidden.pages[0].elements.append(ghost)
        XCTAssertEqual(SVGExporter.svg(design: withHidden, page: withHidden.pages[0]),
                       SVGExporter.svg(design: shown, page: shown.pages[0]))
    }

    func testAHiddenClipMakesNoSoundAndDoesNotAnimateTheVideo() {
        var quiet = Element.image("video:vid-2")
        quiet.hidden = true
        let d = design([Element.image("video:vid-1"), quiet], width: 320, height: 240)
        XCTAssertEqual(AudioMix.clips(design: d, page: d.pages[0]).map(\.source), ["vid-1"])
        let onlyHidden = design([quiet], width: 320, height: 240)
        XCTAssertTrue(AudioMix.clips(design: onlyHidden, page: onlyHidden.pages[0]).isEmpty)
        XCTAssertFalse(MovieExporter.isAnimated(onlyHidden.pages[0], in: onlyHidden), "nothing on the page plays")
    }

    func testAHiddenLinkIsNotFollowedAndHiddenWordsAreNotReadAloud() {
        var linked = box("l", x: 0, y: 0)
        linked.link = "https://example.com"
        linked.hidden = true
        var said = Element.text("Hello")
        said.y = 0
        var unsaid = Element.text("Secret")
        unsaid.y = 300
        unsaid.hidden = true
        let d = design([linked, said, unsaid], width: 800, height: 600)
        XCTAssertTrue(Links.areas(design: d, page: d.pages[0]).isEmpty)
        XCTAssertNil(Links.at(design: d, page: d.pages[0], point: CGPoint(x: 50, y: 50)))
        XCTAssertEqual(ReadAloud.script(for: d.pages[0], in: d), "Hello.")
    }

    func testProofreadSkipsHiddenWordsButFindStillFindsThem() throws {
        var typo = Element.text("Teh end")
        typo.hidden = true
        let d = design([typo], width: 800, height: 600)
        if UITextChecker.availableLanguages.contains(where: { $0.hasPrefix("en") }) {
            XCTAssertTrue(Proofreader.misspellings(in: d, language: "en_US").isEmpty)
        }
        let s = DesignStore(design: d)
        XCTAssertEqual(s.matches(for: "end").count, 1, "Find still finds it, so it can be found and shown")
    }

    func testAHiddenElementIsNotHitBandedSnappedToOrSelectedByAll() {
        var ghost = box("g", x: 0, y: 0)
        ghost.hidden = true
        let shown = box("s", x: 500, y: 500)
        XCTAssertFalse(Geometry.hits(ghost, point: CGPoint(x: 50, y: 50)))
        XCTAssertTrue(Geometry.intersecting([ghost, shown], CGRect(x: 0, y: 0, width: 1080, height: 1080)).map(\.id) == ["s"])
        let d = design([ghost, shown])
        let lines = Geometry.taggedSnapLines(design: d, page: d.pages[0], excluding: [],
                                             settings: SnapSettings(toPage: false, toElements: true))
        XCTAssertFalse(lines.x.contains { $0.source == .element("g") })
        XCTAssertTrue(lines.x.contains { $0.source == .element("s") })
        let s = DesignStore(design: d)
        s.selectAll()
        XCTAssertEqual(s.selection, ["s"])
        s.select(within: CGRect(x: 0, y: 0, width: 1080, height: 1080))
        XCTAssertEqual(s.selection, ["s"])
    }

    func testAHiddenElementIsNotExportedOrAudited() {
        var ghost = box("g", x: 0, y: 0)
        ghost.hidden = true
        let d = design([ghost, box("s", x: 500, y: 500)])
        XCTAssertNil(DesignExporter.selectionDesign(design: d, page: d.pages[0], ids: ["g"]),
                     "a selection of only hidden things exports nothing")
        let both = DesignExporter.selectionDesign(design: d, page: d.pages[0], ids: ["g", "s"])
        XCTAssertEqual(both?.pages[0].elements.map(\.id), ["s"])
        var faint = Element.text("Pale", fontSize: 20)
        faint.color = "#f5f5f5"
        faint.hidden = true
        XCTAssertTrue(ContrastAudit.audit(design([faint])).isEmpty)
    }

    // MARK: names

    func testANameOfItsOwnIsUsedWhereverItIsNamed() {
        var logo = box("l", x: 0, y: 0)
        let made = ElementNames.name(of: logo)
        logo.layerName = "Logo"
        XCTAssertEqual(ElementNames.name(of: logo), "Logo")
        XCTAssertEqual(CanvasAccessibility.label(for: logo), "Logo")
        XCTAssertEqual(ElementNames.guideLabel(.element("l"), vertical: true, elements: [logo]), "Lined up with Logo",
                       "kept as typed, not lower-cased")
        logo.altText = "Our company logo"
        XCTAssertEqual(CanvasAccessibility.label(for: logo), "Our company logo", "alt text still comes first")
        logo.layerName = nil
        XCTAssertEqual(ElementNames.name(of: logo), made)
        var empty = Element.text("")
        empty.layerName = "Caption"
        XCTAssertEqual(CanvasAccessibility.label(for: empty), "Caption")
    }

    // MARK: the store

    func testHidingAndLockingFromLayersAreOneUndoEach() throws {
        let s = DesignStore(design: design([box("a", x: 0, y: 0), box("b", x: 0, y: 0)]))
        s.setHidden(["a"], hidden: true)
        XCTAssertEqual(s.element("a")?.hidden, true)
        s.setHidden(["a"], hidden: false)
        XCTAssertNil(s.element("a")?.hidden, "shown is nil, never false")
        s.setLocked(["a", "b"], locked: true)
        XCTAssertEqual(s.page.elements.map(\.locked), [true, true])
        s.setLocked(["a", "b"], locked: true)
        s.undo()
        XCTAssertEqual(s.page.elements.map(\.locked), [false, false], "locking again changed nothing and took no step")
        s.undo()
        XCTAssertEqual(s.element("a")?.hidden, true)
        s.undo()
        XCTAssertNil(s.element("a")?.hidden)
        XCTAssertFalse(s.canUndo)
    }

    func testAHiddenElementPickedInLayersStaysSelected() {
        let s = DesignStore(design: design([box("a", x: 0, y: 0)]))
        s.select("a")
        s.setHidden(["a"], hidden: true)
        XCTAssertEqual(s.selection, ["a"])
        XCTAssertEqual(s.singleSelection?.isHidden, true)
    }

    func testRenamingIsOneUndoAndBlankGivesTheMadeNameBack() {
        let s = DesignStore(design: design([box("a", x: 0, y: 0)]))
        s.renameLayer("a", to: "  Logo  ")
        XCTAssertEqual(s.element("a")?.layerName, "Logo")
        s.renameLayer("a", to: "Logo")
        s.renameLayer("a", to: "   ")
        XCTAssertNil(s.element("a")?.layerName)
        s.undo()
        XCTAssertEqual(s.element("a")?.layerName, "Logo")
        s.undo()
        XCTAssertNil(s.element("a")?.layerName)
        XCTAssertFalse(s.canUndo, "the same name again took no step")
    }

    // MARK: rows

    /// Back to front: a, g1, b, g2 — g1 and g2 grouped.
    private var mixed: [Element] {
        [box("a", x: 0, y: 0), box("g1", x: 0, y: 0, group: "grp"), box("b", x: 0, y: 0), box("g2", x: 0, y: 0, group: "grp")]
    }

    func testAGroupFoldsIntoOneRowWhereItsTopMemberIs() {
        let rows = LayerRows.rows(mixed, expanded: [])
        XCTAssertEqual(rows.map(\.id), ["group:grp", "b", "a"])
        XCTAssertEqual(rows[0].elements.map(\.id), ["g2", "g1"])
        XCTAssertEqual(LayerRows.groupName(2), "Group (2)")
        let open = LayerRows.rows(mixed, expanded: ["grp"])
        XCTAssertEqual(open.map(\.id), ["group:grp", "g2", "g1", "b", "a"])
        XCTAssertEqual(open.map(\.movable), [true, false, false, true, true])
        let lone = LayerRows.rows([box("c", x: 0, y: 0, group: "solo")], expanded: [])
        XCTAssertEqual(lone, [.element(box("c", x: 0, y: 0, group: "solo"), member: false)], "a group of one is its element")
    }

    func testDraggingARowMovesOnlyThatElement() {
        let page = [box("a", x: 0, y: 0), box("b", x: 0, y: 0), box("c", x: 0, y: 0)]
        let rows = LayerRows.rows(page, expanded: [])
        XCTAssertEqual(LayerRows.moved(page, rows: rows, from: [2], to: 0).map(\.id), ["b", "c", "a"], "to the front")
        XCTAssertEqual(LayerRows.moved(page, rows: rows, from: [0], to: 3).map(\.id), ["c", "a", "b"], "to the back")
        XCTAssertEqual(LayerRows.moved(page, rows: rows, from: [1], to: 1).map(\.id), ["a", "b", "c"], "where it was")
    }

    func testDraggingAGroupRowMovesTheGroupAsOneBlock() {
        let rows = LayerRows.rows(mixed, expanded: [])
        XCTAssertEqual(LayerRows.moved(mixed, rows: rows, from: [0], to: 3).map(\.id), ["g1", "g2", "a", "b"],
                       "to the back, together, in their order")
        XCTAssertEqual(LayerRows.moved(mixed, rows: rows, from: [1], to: 0).map(\.id), ["a", "g1", "g2", "b"],
                       "above the group's top member")
        XCTAssertEqual(LayerRows.moved(mixed, rows: rows, from: [2], to: 1).map(\.id), ["g1", "b", "a", "g2"],
                       "everything else keeps its place")
    }

    func testAMemberRowDoesNotMoveAndADropAmongMembersLandsBelowTheGroup() {
        let page = [box("a", x: 0, y: 0), box("b", x: 0, y: 0), box("g1", x: 0, y: 0, group: "grp"),
                    box("g2", x: 0, y: 0, group: "grp")]
        let rows = LayerRows.rows(page, expanded: ["grp"])
        XCTAssertEqual(rows.map(\.id), ["group:grp", "g2", "g1", "b", "a"])
        XCTAssertEqual(LayerRows.moved(page, rows: rows, from: [2], to: 0).map(\.id), page.map(\.id))
        XCTAssertEqual(LayerRows.moved(page, rows: rows, from: [4], to: 2).map(\.id), ["b", "a", "g1", "g2"])
    }

    func testMovingLayersIsOneUndo() {
        let s = DesignStore(design: design([box("a", x: 0, y: 0), box("b", x: 0, y: 0)]))
        let rows = LayerRows.rows(s.page.elements, expanded: [])
        s.moveLayers(rows, from: [1], to: 0)
        XCTAssertEqual(s.page.elements.map(\.id), ["b", "a"])
        s.undo()
        XCTAssertEqual(s.page.elements.map(\.id), ["a", "b"])
        XCTAssertFalse(s.canUndo)
    }

    func testOverlappingListsWhatOverlapsTheSelection() {
        let page = [box("a", x: 0, y: 0), box("b", x: 50, y: 50), box("c", x: 300, y: 300, w: 50, h: 50),
                    box("d", x: 100, y: 0, w: 50, h: 50)]
        XCTAssertEqual(LayerRows.overlapping(page, selection: ["a"]).map(\.id), ["a", "b"],
                       "the selection itself, and what overlaps it; d only touches")
        XCTAssertEqual(LayerRows.overlapping(page, selection: ["a", "c"]).map(\.id), ["a", "b", "c"])
        XCTAssertTrue(LayerRows.overlapping(page, selection: []).isEmpty)
        XCTAssertEqual(LayerRows.flat(page).map(\.id), ["d", "c", "b", "a"], "top-most first")
        XCTAssertEqual(LayerRows.Filter.allCases.map(\.rawValue), ["All", "Overlapping"])
    }
}
