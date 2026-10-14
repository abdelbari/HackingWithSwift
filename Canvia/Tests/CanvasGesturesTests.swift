// Round 25's editing that feels like Canva, with the rows the Android
// twin's tests hold too: dragging the selection's body under something on
// top, the edge scroll and the glide, the menu a hold on the empty page
// brings up and Paste at the finger, the move handle, a held nudge arrow,
// the paint roller, and Undo selecting what it changed.

import XCTest
import CoreGraphics
@testable import Canvia

@MainActor
final class CanvasGesturesTests: XCTestCase {

    private func box(_ id: String, x: Double, y: Double, w: Double = 100, h: Double = 100,
                     rotation: Double = 0, group: String? = nil) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        el.rotation = rotation
        el.group = group
        return el
    }

    private func store(_ elements: [Element]) -> DesignStore {
        var d = Design(title: "editing", width: 1080, height: 1080)
        d.pages = [Page(id: "p1", elements: elements)]
        return DesignStore(design: d)
    }

    // MARK: the selection's body

    func testTheSelectedBodyIsTheTurnedFrameOfOneOrTheBoxOfSeveral() {
        let flat = box("a", x: 100, y: 100, w: 200, h: 100)
        XCTAssertTrue(CanvasGestures.onSelectedBody(CGPoint(x: 150, y: 150), selected: [flat]))
        XCTAssertFalse(CanvasGestures.onSelectedBody(CGPoint(x: 90, y: 150), selected: [flat]))
        let turned = box("a", x: 100, y: 100, w: 200, h: 100, rotation: 90)
        XCTAssertTrue(CanvasGestures.onSelectedBody(CGPoint(x: 200, y: 230), selected: [turned]),
                      "in its turned frame, though outside the unturned one")
        XCTAssertFalse(CanvasGestures.onSelectedBody(CGPoint(x: 290, y: 150), selected: [turned]))
        var locked = flat
        locked.locked = true
        XCTAssertFalse(CanvasGestures.onSelectedBody(CGPoint(x: 150, y: 150), selected: [locked]))
        var pinned = flat
        pinned.lockPosition = true
        XCTAssertFalse(CanvasGestures.onSelectedBody(CGPoint(x: 150, y: 150), selected: [pinned]))
        var hidden = flat
        hidden.hidden = true
        XCTAssertFalse(CanvasGestures.onSelectedBody(CGPoint(x: 150, y: 150), selected: [hidden]))
        XCTAssertFalse(CanvasGestures.onSelectedBody(CGPoint(x: 150, y: 150), selected: []))

        let a = box("a", x: 0, y: 0), b = box("b", x: 300, y: 0)
        XCTAssertTrue(CanvasGestures.onSelectedBody(CGPoint(x: 200, y: 50), selected: [a, b]),
                      "between them, inside the box round both")
        XCTAssertFalse(CanvasGestures.onSelectedBody(CGPoint(x: 200, y: 150), selected: [a, b]))
        var lockedA = a, lockedB = b
        lockedA.locked = true
        lockedB.locked = true
        XCTAssertFalse(CanvasGestures.onSelectedBody(CGPoint(x: 200, y: 50), selected: [lockedA, lockedB]))
    }

    // MARK: edge scroll

    func testTheEdgeScrollRows() {
        // Shared with the Android twin: finger → (dx, dy), in a 400 × 800
        // canvas, a 40 band and 14 a frame at most.
        let view = CGRect(x: 0, y: 0, width: 400, height: 800)
        let rows: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: 200, y: 400), 0, 0),
            (CGPoint(x: 0, y: 400), -14, 0),
            (CGPoint(x: 20, y: 400), -3.5, 0),
            (CGPoint(x: 40, y: 400), 0, 0),
            (CGPoint(x: 360, y: 400), 0, 0),
            (CGPoint(x: 400, y: 800), 14, 14),
            (CGPoint(x: 390, y: 10), 7.875, -7.875),
            (CGPoint(x: -10, y: 400), -14, 0),
        ]
        for (finger, dx, dy) in rows {
            let d = Viewport.edgeScroll(finger: finger, viewport: view)
            XCTAssertEqual(d.dx, dx, accuracy: 0.0001, "\(finger)")
            XCTAssertEqual(d.dy, dy, accuracy: 0.0001, "\(finger)")
        }
        // The canvas below a bar: its own top is the edge.
        let below = CGRect(x: 0, y: 100, width: 400, height: 600)
        XCTAssertEqual(Viewport.edgeScroll(finger: CGPoint(x: 200, y: 110), viewport: below).dy, -7.875, accuracy: 0.0001)
        XCTAssertEqual(Viewport.edgeBand, 40)
        XCTAssertEqual(Viewport.edgeMaxSpeed, 14)
        XCTAssertEqual(Viewport.topSpeed(reduceMotion: false), 14)
        XCTAssertEqual(Viewport.topSpeed(reduceMotion: true), 7, "half under Reduce Motion")
        let slow = Viewport.edgeScroll(finger: CGPoint(x: 0, y: 400), viewport: view,
                                       maxSpeed: Viewport.topSpeed(reduceMotion: true))
        XCTAssertEqual(slow.dx, -7, accuracy: 0.0001)
    }

    // MARK: glide

    func testAFlickGlidesForAFifthOfASecondOfItsSpeed() {
        XCTAssertEqual(Viewport.flingCarry, 0.2)
        XCTAssertEqual(Viewport.flingMinSpeed, 50)
        let at = CGPoint(x: 100, y: 100)
        XCTAssertNil(Viewport.flingTarget(offset: at, velocity: CGPoint(x: 40, y: 0)), "a lift, not a flick")
        XCTAssertNil(Viewport.flingTarget(offset: at, velocity: CGPoint(x: 50, y: 0)), "50 a second is still a lift")
        XCTAssertEqual(Viewport.flingTarget(offset: at, velocity: CGPoint(x: 500, y: -250)), CGPoint(x: 0, y: 150))
    }

    // MARK: hold on the empty page

    func testTheHoldMenuItemsAndWhereAPasteLands() {
        XCTAssertEqual(HoldMenu.items(canPaste: true, canPastePage: true).map(\.title),
                       ["Paste", "Paste page", "Select all", "Add text here", "Background"])
        XCTAssertEqual(HoldMenu.items(canPaste: false, canPastePage: false).map(\.title),
                       ["Select all", "Add text here", "Background"])
        XCTAssertEqual(HoldMenu.items(canPaste: true, canPastePage: false), [.paste, .selectAll, .addText, .background])
        let page = CGSize(width: 1080, height: 1080)
        let size = CGSize(width: 100, height: 50)
        XCTAssertEqual(HoldMenu.placed(size, at: CGPoint(x: 500, y: 500), page: page), CGPoint(x: 450, y: 475))
        XCTAssertEqual(HoldMenu.placed(size, at: CGPoint(x: 20, y: 20), page: page), CGPoint(x: 0, y: 0),
                       "kept on the page")
        XCTAssertEqual(HoldMenu.placed(size, at: CGPoint(x: 1070, y: 1075), page: page), CGPoint(x: 980, y: 1030))
    }

    func testPasteHereCentresTheCopyOnTheFingerAsOneStep() {
        let a = box("a", x: 0, y: 0)
        let s = store([a])
        s.selection = ["a"]
        s.copySelected()
        s.select(nil)
        s.paste(at: CGPoint(x: 500, y: 500))
        XCTAssertEqual(s.page.elements.count, 2)
        let pasted = s.selectedElements
        XCTAssertEqual(pasted.count, 1)
        XCTAssertEqual(pasted.first?.x, 450)
        XCTAssertEqual(pasted.first?.y, 450)
        s.undo()
        XCTAssertEqual(s.page.elements.map(\.id), ["a"], "one step")
    }

    func testAddTextHereTypesOverTheDefaultBoxAndLeavesItAsOneStep() {
        let s = store([])
        s.addText(at: CGPoint(x: 540, y: 540))
        XCTAssertEqual(s.page.elements.count, 1)
        let typed = try? XCTUnwrap(s.page.elements.first)
        XCTAssertEqual(s.editingTextId, typed?.id, "typing at once")
        XCTAssertEqual(typed?.text, "Your text here", "the default text box, as on the Android twin")
        XCTAssertTrue(s.typingSelectsWords, "its words chosen, so the first key replaces them")
        XCTAssertEqual(typed?.fontSize, 65)
        XCTAssertEqual(typed?.w, 778)
        XCTAssertEqual(typed?.x, 151, "centred on the finger")
        XCTAssertEqual((typed?.y ?? 0) + (typed?.h ?? 0) / 2, 540, accuracy: 0.0001)
        s.endTextEdit()
        XCTAssertEqual(s.page.elements.first?.text, "Your text here", "left as it is, it stays")
        s.undo()
        XCTAssertTrue(s.page.elements.isEmpty, "as one step")
        XCTAssertFalse(s.canUndo)

        s.addText(at: CGPoint(x: 540, y: 540))
        if let id = s.editingTextId { s.typeWords("Hello", into: id) }
        s.endTextEdit()
        XCTAssertEqual(s.page.elements.first?.text, "Hello")
        s.undo()
        XCTAssertTrue(s.page.elements.isEmpty, "the box and its words are one Undo")
    }

    // MARK: move handle

    func testTheMoveHandleSitsBesideTheRotateHandle() {
        let el = box("a", x: 100, y: 100, w: 200, h: 40)
        XCTAssertEqual(Geometry.rotateHandlePosition(el, offset: 28), CGPoint(x: 200, y: 168))
        XCTAssertEqual(Geometry.rotateHandlePosition(el, offset: 28, above: true), CGPoint(x: 200, y: 72))
        XCTAssertEqual(Geometry.moveHandlePosition(el, offset: 28), CGPoint(x: 172, y: 168))
        XCTAssertEqual(Geometry.moveHandlePosition(el, offset: 28, above: true), CGPoint(x: 172, y: 72))
        let turned = box("a", x: 100, y: 100, w: 200, h: 40, rotation: 90)
        let p = Geometry.moveHandlePosition(turned, offset: 28)
        XCTAssertEqual(p.x, 152, accuracy: 0.0001)
        XCTAssertEqual(p.y, 92, accuracy: 0.0001)
    }

    func testWhoGetsTheMoveHandle() {
        XCTAssertEqual(Touch.moveHandleSize, 28)
        XCTAssertEqual(Touch.moveHandleBelow, 56)
        let bar = box("a", x: 0, y: 0, w: 200, h: 40)
        XCTAssertTrue(Touch.showsMoveHandle(bar, zoom: 1, typing: false), "40 on screen is under 56")
        XCTAssertFalse(Touch.showsMoveHandle(bar, zoom: 2, typing: false))
        XCTAssertTrue(Touch.showsMoveHandle(bar, zoom: 2, typing: true), "always while typed into")
        let square = box("b", x: 0, y: 0)
        XCTAssertTrue(Touch.showsMoveHandle(square, zoom: 0.5, typing: false))
        XCTAssertFalse(Touch.showsMoveHandle(square, zoom: 0.6, typing: false))
        var locked = bar
        locked.locked = true
        XCTAssertFalse(Touch.showsMoveHandle(locked, zoom: 1, typing: true))
        var hidden = bar
        hidden.hidden = true
        XCTAssertFalse(Touch.showsMoveHandle(hidden, zoom: 1, typing: false))
    }

    // MARK: held nudges

    func testAHeldNudgeArrowRepeatsAtTheSharedPace() {
        XCTAssertEqual(NudgeRepeat.delay(afterSteps: 1), 0.4)
        XCTAssertEqual(NudgeRepeat.delay(afterSteps: 2), 0.08)
        XCTAssertEqual(NudgeRepeat.delay(afterSteps: 19), 0.08)
        XCTAssertEqual(NudgeRepeat.delay(afterSteps: 20), 0.04)
        XCTAssertEqual(NudgeRepeat.delay(afterSteps: 50), 0.04)
        XCTAssertEqual((1...30).filter(NudgeRepeat.ticks(at:)), [10, 20, 30])
        XCTAssertFalse(NudgeRepeat.ticks(at: 0))
    }

    func testAHeldNudgeIsOneUndoStep() {
        var pinned = box("p", x: 500, y: 500)
        pinned.lockPosition = true
        let s = store([box("a", x: 0, y: 0), pinned])
        s.selection = ["a", "p"]
        for _ in 0..<3 { s.nudgeSelectedTransient(dx: 10, dy: 0) }
        s.commit()
        XCTAssertEqual(s.element("a")?.x, 30)
        XCTAssertEqual(s.element("p")?.x, 500, "a position lock stays put")
        s.undo()
        XCTAssertEqual(s.element("a")?.x, 0, "the whole hold is one step")
        XCTAssertFalse(s.canUndo)
    }

    // MARK: paint style

    func testColourCarriesAcrossKinds() {
        var text = Element.text("Hi")
        text.color = "#ff0000"
        text.fontFamily = "serif"
        text.opacity = 0.5
        var shape = Element.shape("rect")
        shape.fill = .solid("#00ff00")
        shape.stroke = "#123456"
        var line = Element.line()
        line.color = "#0000ff"
        var photo = Element.image("asset:x")
        photo.stroke = "#abcdef"

        let fromText = StylePaint.pasted(DesignStore.style(of: text), from: .text, onto: shape)
        XCTAssertEqual(fromText.fill, .solid("#ff0000"), "a text's colour becomes a shape's fill")
        XCTAssertEqual(fromText.opacity, 0.5, "opacity goes across too")
        XCTAssertNil(fromText.fontFamily, "nothing of the other kind's")

        let fromShape = StylePaint.pasted(DesignStore.style(of: shape), from: .shape, onto: text)
        XCTAssertEqual(fromShape.color, "#00ff00", "a solid fill becomes a text's colour")
        XCTAssertEqual(fromShape.fontFamily, "serif", "the text keeps its type")

        let gradient = Paint(kind: "gradient", color: nil, angle: 90,
                             stops: [GradientStop(offset: 0, color: "#000000"), GradientStop(offset: 1, color: "#ffffff")])
        var shaded = shape
        shaded.fill = gradient
        let fromGradient = StylePaint.pasted(DesignStore.style(of: shaded), from: .shape, onto: text)
        XCTAssertEqual(fromGradient.textFill, gradient, "a gradient fill goes to textFill")
        XCTAssertEqual(fromGradient.color, "#ff0000")
        var shadedText = text
        shadedText.textFill = gradient
        XCTAssertEqual(StylePaint.pasted(DesignStore.style(of: shadedText), from: .text, onto: shape).fill, gradient)

        XCTAssertEqual(StylePaint.pasted(DesignStore.style(of: line), from: .line, onto: shape).stroke, "#0000ff")
        XCTAssertEqual(StylePaint.pasted(DesignStore.style(of: line), from: .line, onto: text).color, "#0000ff")
        XCTAssertEqual(StylePaint.pasted(DesignStore.style(of: shape), from: .shape, onto: line).color, "#123456")
        XCTAssertEqual(StylePaint.pasted(DesignStore.style(of: text), from: .text, onto: line).color, "#ff0000")
        XCTAssertEqual(StylePaint.pasted(DesignStore.style(of: photo), from: .image, onto: shape).stroke, "#abcdef")
        XCTAssertEqual(StylePaint.pasted(DesignStore.style(of: shape), from: .shape, onto: photo).stroke, "#123456")
        // The colour only: each keeps its own outline width.
        photo.strokeWidth = 6
        shape.strokeWidth = 4
        XCTAssertEqual(StylePaint.pasted(DesignStore.style(of: photo), from: .image, onto: shape).strokeWidth, 4)
        XCTAssertEqual(StylePaint.pasted(DesignStore.style(of: shape), from: .shape, onto: photo).strokeWidth, 6)
        // Only a gradient in the letters fills a shape with it.
        var pictured = text
        pictured.textFill = .solid("#0000ff")
        XCTAssertEqual(StylePaint.pasted(DesignStore.style(of: pictured), from: .text, onto: shape).fill, .solid("#ff0000"))

        var other = Element.text("Other")
        other.fontFamily = "mono"
        XCTAssertEqual(StylePaint.pasted(DesignStore.style(of: text), from: .text, onto: other).fontFamily, "serif",
                       "between texts, the whole style")
        XCTAssertEqual(StylePaint.chip, "Tap something to paste the style")
    }

    func testPaintModePastesOnEachTapAsAStepAndSkipsLocked() {
        var text = Element.text("Hi")
        text.id = "t"
        text.color = "#ff0000"
        var locked = box("l", x: 600, y: 0)
        locked.locked = true
        let s = store([text, box("a", x: 0, y: 300), box("b", x: 300, y: 300, group: "g"),
                       box("c", x: 500, y: 300, group: "g"), locked])
        s.selection = ["t"]
        s.toggleStylePainting()
        XCTAssertTrue(s.stylePainting)
        s.paintStyle(onto: "a")
        XCTAssertEqual(s.element("a")?.fill, .solid("#ff0000"))
        XCTAssertEqual(s.selection, ["a"], "and it is selected")
        XCTAssertTrue(s.stylePainting, "paint mode stays on for further taps")
        s.paintStyle(onto: "b")
        XCTAssertEqual(s.element("c")?.fill, .solid("#ff0000"), "the whole group")
        XCTAssertEqual(s.selection, ["b", "c"])
        s.paintStyle(onto: "l")
        XCTAssertEqual(s.element("l")?.fill, .solid("#8b5cf6"), "a locked thing is left as it is")
        s.undo()
        XCTAssertEqual(s.element("b")?.fill, .solid("#8b5cf6"), "each tap one step")
        XCTAssertEqual(s.element("a")?.fill, .solid("#ff0000"))
        s.toggleStylePainting()
        XCTAssertFalse(s.stylePainting, "the button again puts it away")
    }

    func testPasteStyleSkipsLockedThings() {
        var text = Element.text("Hi")
        text.id = "t"
        text.color = "#ff0000"
        var locked = box("l", x: 600, y: 0)
        locked.locked = true
        let s = store([text, box("a", x: 0, y: 300), locked])
        s.selection = ["t"]
        s.copyStyle()
        s.selection = ["a", "l"]
        s.pasteStyle()
        XCTAssertEqual(s.element("a")?.fill, .solid("#ff0000"))
        XCTAssertEqual(s.element("l")?.fill, .solid("#8b5cf6"))
    }

    // MARK: undo selects what it changed

    func testChangedIds() {
        let a = box("a", x: 0, y: 0), b = box("b", x: 100, y: 0), c = box("c", x: 200, y: 0)
        var moved = b
        moved.x = 150
        let before = Page(id: "p", elements: [a, b, c])
        let after = Page(id: "p", elements: [a, moved, box("d", x: 0, y: 0)])
        XCTAssertEqual(History.changedIds(before: before, after: after), ["b", "c", "d"])
        XCTAssertEqual(History.changedIds(before: before, after: before), [])
    }

    func testUndoAndRedoSelectWhatTheyChanged() {
        let s = store([box("a", x: 0, y: 0), box("b", x: 300, y: 0),
                       box("g1", x: 0, y: 500, group: "g"), box("g2", x: 300, y: 500, group: "g")])
        s.selection = ["a"]
        s.nudgeSelected(dx: 10, dy: 0)
        s.selection = ["b"]
        s.undo()
        XCTAssertEqual(s.selection, ["a"], "the moved thing is selected again")
        s.selection = []
        s.redo()
        XCTAssertEqual(s.selection, ["a"])

        s.selection = ["a"]
        s.deleteSelected()
        XCTAssertTrue(s.selection.isEmpty)
        s.undo()
        XCTAssertEqual(s.selection, ["a"], "what came back is selected")

        s.add(box("new", x: 700, y: 700))
        s.undo()
        XCTAssertTrue(s.selection.isEmpty, "a step that only took things away selects nothing")

        s.selection = ["g1"]
        s.nudgeSelected(dx: 5, dy: 0)
        s.selection = []
        s.undo()
        XCTAssertEqual(s.selection, ["g1", "g2"], "widened to the whole sticky group")
    }

    func testUndoingDeletePageSelectsNothingOnIt() {
        // The Android twin's row (HistoryTest).
        var d = Design(title: "editing", width: 1080, height: 1080)
        d.pages = [Page(id: "p1", elements: [box("a", x: 0, y: 0)]),
                   Page(id: "p2", elements: [box("x", x: 0, y: 0), box("y", x: 300, y: 0)])]
        let s = DesignStore(design: d)
        s.pageIndex = 1
        s.deletePage()
        s.undo()
        XCTAssertEqual(s.page.id, "p2")
        XCTAssertTrue(s.selection.isEmpty, "a page brought back whole has nothing changed on it")
    }
}
