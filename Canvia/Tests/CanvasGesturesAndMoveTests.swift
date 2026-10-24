// Round 21's editing on the canvas, with the rows the Android twin's tests
// hold too: the gesture table, Move to page and where a paste lands on
// another page, and Select multiple's taps.

import XCTest
@testable import Canvia

@MainActor
final class CanvasGesturesAndMoveTests: XCTestCase {

    private func box(_ id: String, x: Double, y: Double, w: Double = 100, h: Double = 100,
                     group: String? = nil) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        el.group = group
        return el
    }

    /// A design of `pages`, each with its id, its elements and, when given,
    /// a size of its own.
    private func store(_ pages: [(id: String, elements: [Element], size: CGSize?)],
                       width: Double = 1080, height: Double = 1080) -> DesignStore {
        var d = Design(title: "editing", width: width, height: height)
        d.pages = pages.map { spec in
            var page = Page(id: spec.id, elements: spec.elements)
            if let size = spec.size {
                page.width = size.width
                page.height = size.height
            }
            return page
        }
        return DesignStore(design: d)
    }

    // MARK: the gesture table

    func testTheGestureTableIsTheAndroidTwins() {
        let rows: [(CanvasGestures.Input, CanvasGestures.Target, CanvasGestures.Action)] = [
            (.drag, .element, .move),
            (.drag, .emptyPage, .pan),
            (.holdThenDrag, .emptyPage, .band),
            (.hold, .element, .toggleInSelection),
            (.twoFingers, .element, .panAndZoom),
            (.twoFingers, .emptyPage, .panAndZoom),
            (.holdThenDrag, .element, .move),
            // Round 25: a still hold on the empty page brings up the menu.
            (.hold, .emptyPage, .menu),
            (.tap, .element, .select),
            // Nothing there: nothing selected (the Android twin's SELECT).
            (.tap, .emptyPage, .select),
            // Round 25: inside the selection a drag moves it, whatever lies
            // on top, while a tap still picks the topmost thing.
            (.drag, .selectedBody, .move),
            (.tap, .selectedBody, .select),
            (.holdThenDrag, .selectedBody, .move),
            (.hold, .selectedBody, .toggleInSelection),
            (.twoFingers, .selectedBody, .panAndZoom),
            // Round 29: a backdrop and the workspace start a band too; a
            // plain drag and a tap there do what they did.
            (.drag, .backdrop, .move),
            (.holdThenDrag, .backdrop, .band),
            (.hold, .backdrop, .menu),
            (.tap, .backdrop, .select),
            (.twoFingers, .backdrop, .panAndZoom),
            (.drag, .workspace, .pan),
            (.holdThenDrag, .workspace, .band),
            (.hold, .workspace, .menu),
            (.tap, .workspace, .select),
            (.twoFingers, .workspace, .panAndZoom),
            // Round 32: a pinch begun on the selection scales and turns it;
            // anywhere else two fingers still move the view.
            (.twoFingersOnSelection, .selectedBody, .transformSelection),
            (.twoFingersOnSelection, .element, .transformSelection),
            (.twoFingersOnSelection, .emptyPage, .transformSelection),
            (.twoFingersOnSelection, .backdrop, .transformSelection),
            (.twoFingersOnSelection, .workspace, .transformSelection),
        ]
        for (input, target, action) in rows {
            XCTAssertEqual(CanvasGestures.action(input, on: target), action, "\(input) on \(target)")
        }
        XCTAssertEqual(rows.count, CanvasGestures.Input.allCases.count * CanvasGestures.Target.allCases.count)
        XCTAssertEqual(CanvasGestures.holdSeconds, 0.4)
    }

    /// Round 31's rows, the Android twin's too: with Scroll through pages
    /// off, a fling across the page at the zoom that fits turns the page;
    /// zoomed in, or anything else, it pans as before.
    func testAFlingAtFitStepsThePage() {
        typealias Row = (CanvasGestures.Target, Double, Double, Double, Bool, Double, CanvasGestures.Action)
        let rows: [Row] = [
            // target, vx, dx, dy, single page, zoom (fit 0.5) -> action
            (.emptyPage, -1200, -200, 20, true, 0.5, .stepPage),
            (.workspace, 1200, 200, 20, true, 0.5, .stepPage),
            (.emptyPage, -1200, -200, 20, true, 0.505, .stepPage),
            (.emptyPage, -1200, -200, 20, true, 1.0, .pan),
            (.emptyPage, -1200, -200, 20, false, 0.5, .pan),
            (.emptyPage, -700, -200, 20, true, 0.5, .pan),
            (.emptyPage, -1200, -200, 120, true, 0.5, .pan),
            (.element, -1200, -200, 20, true, 0.5, .move),
            (.selectedBody, -1200, -200, 20, true, 0.5, .move),
        ]
        for (target, vx, dx, dy, single, zoom, action) in rows {
            XCTAssertEqual(CanvasGestures.flingAction(on: target, velocityX: vx, dx: dx, dy: dy,
                                                      singlePage: single, zoom: zoom, fitZoom: 0.5),
                           action, "\(target) vx \(vx) dy \(dy) zoom \(zoom) single \(single)")
        }
        XCTAssertEqual(CanvasGestures.flingSpeed, 800)
        XCTAssertEqual(CanvasGestures.fitSlack, 0.02)
        XCTAssertEqual(CanvasGestures.pageStep(velocityX: -1200, rightToLeft: false), 1, "leftward: the next page")
        XCTAssertEqual(CanvasGestures.pageStep(velocityX: 1200, rightToLeft: false), -1)
        XCTAssertEqual(CanvasGestures.pageStep(velocityX: -1200, rightToLeft: true), -1, "mirrored right to left")
        XCTAssertEqual(CanvasGestures.pageStep(velocityX: 1200, rightToLeft: true), 1)
    }

    func testOneFingerPansFromTheEmptyPageOnlyWhenItDidNotHoldFirst() {
        XCTAssertTrue(CanvasGestures.pansFromPage(onElement: false, held: 0))
        XCTAssertTrue(CanvasGestures.pansFromPage(onElement: false, held: 0.39))
        XCTAssertFalse(CanvasGestures.pansFromPage(onElement: false, held: 0.4), "a hold, then a drag, is the band")
        XCTAssertFalse(CanvasGestures.pansFromPage(onElement: true, held: 0), "one finger on an element moves it")
    }

    func testTheWordsSayHoldOnTheEmptyPage() {
        let hands = Onboarding.cards.first { $0.id == "hands" }
        XCTAssertEqual(hands?.text, "Two fingers zoom and move the page, even over what you just added. Hold on the empty page and drag to select several things at once. Rotation and alignment snap, and you feel it when they do.")
        let select = HelpTopics.all.first { $0.id == "select" }
        XCTAssertTrue(select?.body.hasPrefix("Hold on the empty page and drag to draw a band") == true)
    }

    // MARK: move to page

    func testTheClampRows() {
        // Shared with the Android twin: (low, high, size) → shift.
        let rows: [(Double, Double, Double, Double)] = [
            (10, 20, 100, 0),
            (-40, 60, 1000, 40),
            (900, 1100, 800, -300),
            (-50, 1150, 1000, 50),
            (300, 1300, 1000, -300),
            (0, 1080, 1080, 0),
        ]
        for (low, high, size, shift) in rows {
            XCTAssertEqual(PageMove.shift(low, high, within: size), shift, "\(low)…\(high) in \(size)")
        }
    }

    func testMovedThingsKeepTheirPlaceAndAreClampedTogetherOnAnotherSize() {
        let a = box("a", x: 900, y: 100, w: 200), b = box("b", x: 1000, y: 300)
        let same = PageMove.clamped([a, b], from: CGSize(width: 1080, height: 1080), to: CGSize(width: 1080, height: 1080))
        XCTAssertEqual(same, [a, b], "the same size: where they were, even over the edge")
        let small = PageMove.clamped([a, b], from: CGSize(width: 1080, height: 1080), to: CGSize(width: 800, height: 800))
        XCTAssertEqual(small.map(\.x), [600, 700], "moved together into the page, apart as they were")
        XCTAssertEqual(small.map(\.y), [100, 300])
        XCTAssertEqual(small.map(\.w), [200, 100], "never scaled")
        let tall = box("t", x: 40, y: 1500, h: 200)
        let short = PageMove.clamped([tall], from: CGSize(width: 1080, height: 1920), to: CGSize(width: 1080, height: 1080))
        XCTAssertEqual(short.first?.y, 880)
        XCTAssertEqual(short.first?.x, 40)
    }

    func testMoveToPageTakesTheGroupAndItsArrowAsOneStep() {
        let a = box("a", x: 100, y: 100, group: "g"), b = box("b", x: 300, y: 100, group: "g")
        let c = box("c", x: 600, y: 600)
        var arrow = Element.line(w: 100)
        arrow.id = "arrow"
        arrow.connectFrom = "a"
        arrow.connectTo = "b"
        var locked = box("lk", x: 0, y: 0, group: "g")
        locked.locked = true
        let s = store([(id: "p1", elements: [a, arrow, c, b, locked], size: nil),
                       (id: "p2", elements: [box("x", x: 0, y: 0)], size: nil)])
        s.selection = ["a"]
        s.moveSelectedToPage(1)
        XCTAssertEqual(s.pageIndex, 1, "the page moved to is shown")
        XCTAssertEqual(s.page.elements.map(\.id), ["x", "a", "arrow", "b"], "on top, in the order they were")
        XCTAssertEqual(s.element("a")?.frame, a.frame, "where it sat")
        XCTAssertEqual(s.selection, ["a", "arrow", "b"])
        XCTAssertEqual(s.design.pages[0].elements.map(\.id), ["c", "lk"], "the locked member stays behind")
        XCTAssertEqual(s.announcement, "Moved to page 2")
        XCTAssertEqual(s.element("arrow")?.connectFrom, "a", "the arrow still holds both ends")
        s.undo()
        XCTAssertEqual(s.pageIndex, 0)
        XCTAssertEqual(s.page.elements.map(\.id), ["a", "arrow", "c", "b", "lk"])
        XCTAssertFalse(s.canUndo, "one step")
    }

    func testMoveToPageNamesThePagesAndRefusesWhatIsLocked() {
        var pinned = box("a", x: 0, y: 0)
        pinned.lockPosition = true
        let s = store([(id: "p1", elements: [pinned], size: nil),
                       (id: "p2", elements: [], size: nil),
                       (id: "p3", elements: [], size: nil)])
        s.design.pages[1].title = "Intro"
        XCTAssertEqual(s.moveTargets.map(\.name), ["Page 2 · Intro", "Page 3"])
        XCTAssertEqual(s.moveTargets.map(\.index), [1, 2])
        s.selection = ["a"]
        s.moveSelectedToPage(2)
        XCTAssertEqual(s.pageIndex, 0)
        XCTAssertNotNil(s.element("a"))
        XCTAssertFalse(s.canUndo)
    }

    // MARK: pasting onto another page

    func testThePasteOffsetRows() {
        let here = Page(id: "p2", elements: [box("orig", x: 0, y: 0)])
        // (nth, source page, copied ids) → offset
        let rows: [(Int, String?, [String], Double)] = [
            (1, "p1", ["gone"], 0),
            (2, "p1", ["gone"], 24),
            (3, "p1", ["gone"], 48),
            (1, "p2", ["orig"], 24),
            (2, "p2", ["orig"], 48),
            (1, "p2", ["gone"], 0),
            (1, "p1", ["orig"], 0),
            (1, nil, ["orig"], 24),
            (1, nil, ["gone"], 0),
        ]
        for (nth, source, ids, offset) in rows {
            XCTAssertEqual(Copies.pasteOffset(nth: nth, sourcePage: source, onto: here, copied: ids), offset,
                           "paste \(nth) from \(source ?? "nil") of \(ids)")
        }
    }

    func testCutOnPageOnePastedOnPageTwoLandsAtTheSameSpot() {
        let s = store([(id: "p1", elements: [box("a", x: 100, y: 120)], size: nil),
                       (id: "p2", elements: [], size: nil)])
        s.selection = ["a"]
        s.cutSelected()
        s.setPage(1)
        s.paste()
        XCTAssertEqual(s.selectedElements.map(\.x), [100])
        XCTAssertEqual(s.selectedElements.map(\.y), [120])
        s.paste()
        XCTAssertEqual(s.selectedElements.map(\.x), [124], "a repeat paste on the page steps")
        XCTAssertEqual(s.selectedElements.map(\.y), [144])
    }

    func testCopiedOnPageOnePastedOnPageTwoLandsInPlaceThenSteps() {
        let s = store([(id: "p1", elements: [box("a", x: 100, y: 120)], size: nil),
                       (id: "p2", elements: [], size: nil)])
        s.selection = ["a"]
        s.copySelected()
        s.paste()
        XCTAssertEqual(s.selectedElements.map(\.x), [124], "beside the original, it steps")
        s.setPage(1)
        s.paste()
        XCTAssertEqual(s.selectedElements.map(\.x), [100], "on another page, in place")
        // The rest of the Android twin's MoveToPageTest rows: each page
        // counts its own pastes.
        s.paste()
        XCTAssertEqual(s.selectedElements.map(\.x), [124], "a repeat there steps")
        s.setPage(0)
        s.paste()
        XCTAssertEqual(s.selectedElements.map(\.x), [124], "back beside the original, it counts afresh")
    }

    // MARK: select multiple

    func testSelectMultipleTapsToggle() {
        let s = store([(id: "p1", elements: [box("A", x: 0, y: 0), box("B", x: 200, y: 0)], size: nil)])
        s.startSelectingMultiple()
        XCTAssertTrue(s.selectingMultiple)
        s.tapInSelectMultiple("A")
        s.tapInSelectMultiple("B")
        s.tapInSelectMultiple("A")
        XCTAssertEqual(s.selection, ["B"], "tap A, tap B, tap A gives B")
        s.endSelectingMultiple()
        XCTAssertFalse(s.selectingMultiple)
        XCTAssertEqual(s.selection, ["B"], "Done keeps the selection")
        XCTAssertEqual(DesignStore.selectMultipleOn, "Select multiple on")
    }

    func testSelectMultipleTakesAGroupAsOne() {
        let s = store([(id: "p1", elements: [box("A", x: 0, y: 0, group: "g"), box("B", x: 200, y: 0, group: "g"),
                                             box("C", x: 400, y: 0)], size: nil)])
        s.startSelectingMultiple()
        s.tapInSelectMultiple("C")
        s.tapInSelectMultiple("A")
        XCTAssertEqual(s.selection, ["A", "B", "C"])
        s.tapInSelectMultiple("B")
        XCTAssertEqual(s.selection, ["C"])
    }
}
