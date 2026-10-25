// Round 36's editing batch: the handle in the middle of a curved or elbowed
// line (Fixtures/line_bend.json), the side the turn and move handles take
// (Fixtures/turn_handle_side.json), pinching to the page organiser and its
// columns, and quick flow (Fixtures/quick_flow.json) — the shared fixtures
// the Android twin's tests read too.

import XCTest
import CoreGraphics
@testable import Canvia

@MainActor
final class EditingFlowTests: XCTestCase {

    private func pair(_ value: Any?) -> CGPoint? {
        guard let xy = value as? [Double], xy.count == 2 else { return nil }
        return CGPoint(x: xy[0], y: xy[1])
    }

    private func rect(_ value: Any?) throws -> CGRect {
        let r = try XCTUnwrap(value as? [Double])
        XCTAssertEqual(r.count, 4)
        return CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
    }

    private func element(_ value: Any?) throws -> Element {
        try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(try XCTUnwrap(value)))
    }

    private func rows(_ name: String) throws -> [[String: Any]] {
        try XCTUnwrap(try SharedFixture.object(name)["rows"] as? [[String: Any]])
    }

    // MARK: the bend handle

    func testTheSharedBendRows() throws {
        let rows = try rows("line_bend")
        XCTAssertGreaterThanOrEqual(rows.count, 12)
        for row in rows {
            let name = row["name"] as? String ?? ""
            let line = try element(row["line"])
            let handle = LineRoutes.bendHandlePoint(line)
            if let want = pair(row["handle"]) {
                let got = try XCTUnwrap(handle, name)
                XCTAssertEqual(Double(got.x), Double(want.x), accuracy: 1e-6, name)
                XCTAssertEqual(Double(got.y), Double(want.y), accuracy: 1e-6, name)
            } else {
                XCTAssertNil(handle, name)
            }
            let point = try XCTUnwrap(pair(row["point"]), name)
            let want = try XCTUnwrap(row["bend"] as? Double, name)
            XCTAssertEqual(LineRoutes.bendFor(line, point), want, accuracy: 1e-6, name)
        }
    }

    func testTheHandleFollowsTheFingerItWasDraggedTo() {
        // Where the handle lands after a drag is where the finger let go —
        // on a curve and an elbow alike — while the bend stays within 1.
        var curve = LineRoutes.withType(Element.line(w: 200), .curve)
        curve.x = 100
        curve.y = 100
        let finger = CGPoint(x: Double(curve.center.x) + 10, y: Double(curve.center.y) + 50)
        let bent = LineRoutes.withBend(curve, LineRoutes.bendFor(curve, finger))
        XCTAssertEqual(Double(LineRoutes.bendHandlePoint(bent)?.y ?? 0), Double(finger.y), accuracy: 1e-6)
        var elbow = LineRoutes.withType(Element.line(w: 200), .elbow)
        elbow.ends = [0, 0, 1, 1]
        elbow.h = 100
        let across = CGPoint(x: elbow.x + 150, y: elbow.y + 10)
        let moved = LineRoutes.withBend(elbow, LineRoutes.bendFor(elbow, across))
        XCTAssertEqual(Double(LineRoutes.bendHandlePoint(moved)?.x ?? 0), Double(across.x), accuracy: 1e-6)
    }

    func testAStraightMiddleWritesNoBend() {
        var curve = LineRoutes.withType(Element.line(w: 200), .curve)
        XCTAssertEqual(curve.bend, LineRoutes.curveBend)
        let middle = LineRoutes.ends(of: curve)
        let mid = CGPoint(x: (middle.start.x + middle.end.x) / 2, y: (middle.start.y + middle.end.y) / 2 + 3)
        // 3 of 200 is 0.015: within 0.03, so straight, and no key written.
        curve = LineRoutes.withBend(curve, LineRoutes.bendFor(curve, mid))
        XCTAssertNil(curve.bend)
        XCTAssertEqual(LineRoutes.bendFor(curve, mid), 0)
    }

    func testDraggingTheBendHandleIsOneStepNamedBend() {
        let store = DesignStore(design: Design(title: "b", width: 1080, height: 1080))
        var curve = LineRoutes.withType(Element.line(w: 200), .curve)
        curve.x = 100
        curve.y = 100
        store.add(curve)
        let centre = curve.center
        store.beginLineBend()
        store.dragLineBend(to: CGPoint(x: Double(centre.x), y: Double(centre.y) + 60))
        store.dragLineBend(to: CGPoint(x: Double(centre.x), y: Double(centre.y) + 80))
        store.endLineBend()
        XCTAssertEqual(store.singleSelection?.bend ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(store.undoLabel, tr("Bend"))
        store.undo()
        XCTAssertEqual(store.singleSelection?.bend, LineRoutes.curveBend)
    }

    func testBendMoreAndLessStepByATenth() {
        var curve = LineRoutes.withType(Element.line(w: 200), .curve)
        curve = LineRoutes.withBend(curve, 0.25)
        XCTAssertEqual(LineRoutes.bentBy(curve, LineRoutes.bendStep).bend, 0.35)
        XCTAssertEqual(LineRoutes.bentBy(curve, -LineRoutes.bendStep).bend, 0.15)
        // Held to 1, and none written at 0.
        XCTAssertEqual(LineRoutes.bentBy(LineRoutes.withBend(curve, 0.95), 0.1).bend, 1)
        XCTAssertNil(LineRoutes.bentBy(LineRoutes.withBend(curve, 0.1), -0.1).bend)
    }

    // MARK: the turn handle's side

    func testTheSharedTurnSideRows() throws {
        let rows = try rows("turn_handle_side")
        XCTAssertGreaterThanOrEqual(rows.count, 8)
        for row in rows {
            let name = row["name"] as? String ?? ""
            let el = try element(row["element"])
            let side = Geometry.turnHandleSide(el, outsetY: try XCTUnwrap(row["outsetY"] as? Double),
                                               offset: try XCTUnwrap(row["offset"] as? Double),
                                               reachable: try rect(row["reachable"]))
            XCTAssertEqual(side == .above ? "above" : "below", row["side"] as? String, name)
        }
    }

    func testTheBubbleGoesWhereTheHandlesAreNot() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 800)
        let rect = CGRect(x: 100, y: 300, width: 200, height: 100)
        // Handles below: above, as before.
        XCTAssertEqual(Geometry.bubbleAnchor(rect, viewport: screen, handleOutset: 46).side, .above)
        // Handles above: below, though there is room above.
        let below = Geometry.bubbleAnchor(rect, viewport: screen, handleOutset: 46, handles: .above)
        XCTAssertEqual(below, Geometry.BubbleAnchor(point: CGPoint(x: 200, y: 458), side: .below))
    }

    // MARK: pinch to the page grid

    func testColumnsAfterAPinch() {
        // Current, scale -> columns: a column for each 1.25 times, rounded,
        // spreading the fingers taking columns away; held to 2…6.
        let rows: [(Int, Double, Int)] = [
            (4, 1, 4),
            (4, 1.1, 4),
            (4, 1.25, 3),
            (4, 1.5625, 2),
            (4, 3, 2),
            (4, 0.8, 5),
            (4, 0.64, 6),
            (4, 0.2, 6),
            (3, 1.11, 3),
            (3, 1.11 * 1.11, 2),
            (2, 0, 2),
            (5, .nan, 5),
        ]
        for (current, scale, want) in rows {
            XCTAssertEqual(PageOrder.columnsAfterPinch(current, scale: scale), want, "\(current) × \(scale)")
        }
        // Unset, the width decides; kept, the kept count.
        XCTAssertEqual(PageOrder.shownColumns(kept: 0, forWidth: 390), 2)
        XCTAssertEqual(PageOrder.shownColumns(kept: 0, forWidth: 1000), 4)
        XCTAssertEqual(PageOrder.shownColumns(kept: 6, forWidth: 390), 6)
        XCTAssertEqual(PageOrder.columnsKey, "canvia.organiserColumns")
    }

    func testAPinchOutPastThePageReachesTheGrid() {
        XCTAssertEqual(Viewport.gridPinch(zoom: 0.5, fit: 0.5, whiteboard: false), .none)
        XCTAssertEqual(Viewport.gridPinch(zoom: 0.38, fit: 0.5, whiteboard: false), .none)
        XCTAssertEqual(Viewport.gridPinch(zoom: 0.37, fit: 0.5, whiteboard: false), .near)
        XCTAssertEqual(Viewport.gridPinch(zoom: 0.3, fit: 0.5, whiteboard: false), .near)
        XCTAssertEqual(Viewport.gridPinch(zoom: 0.29, fit: 0.5, whiteboard: false), .release)
        // Never on a whiteboard.
        XCTAssertEqual(Viewport.gridPinch(zoom: 0.01, fit: 0.5, whiteboard: true), .none)
    }

    // MARK: quick flow

    /// A shape whose unturned frame is `frame`.
    private func shape(_ frame: CGRect, turned rotation: Double = 0) -> Element {
        var el = Element.shape("rect", w: Double(frame.width), h: Double(frame.height))
        el.x = Double(frame.minX)
        el.y = Double(frame.minY)
        el.rotation = rotation
        return el
    }

    func testTheSharedQuickFlowRows() throws {
        let rows = try rows("quick_flow")
        XCTAssertGreaterThanOrEqual(rows.count, 10)
        for row in rows {
            let name = row["name"] as? String ?? ""
            let side = try XCTUnwrap(QuickFlow.Side(rawValue: row["side"] as? String ?? ""), name)
            let source = try shape(rect(row["source"]), turned: row["rotation"] as? Double ?? 0)
            let obstacles = try XCTUnwrap(row["obstacles"] as? [Any], name).map { try shape(rect($0)) }
            // No bounds on a whiteboard, which grows to take the copy.
            let bounds: CGRect? = try row["bounds"] is NSNull ? nil : rect(row["bounds"])
            let box = QuickFlow.place(source, side: side, page: Page(elements: [source] + obstacles), bounds: bounds)
            XCTAssertEqual(box, try rect(row["box"]), name)
        }
    }

    /// An element of a quick_flow_drop row: a shape, or a line when the row
    /// says so, at its box, locked or hidden as it says.
    private func dropElement(_ o: [String: Any]) throws -> Element {
        let r = try rect(o["box"])
        var el = o["line"] as? Bool == true ? Element.line(w: Double(r.width)) : shape(r)
        el.id = try XCTUnwrap(o["id"] as? String)
        el.x = Double(r.minX)
        el.y = Double(r.minY)
        el.h = Double(r.height)
        el.locked = o["locked"] as? Bool == true
        if o["hidden"] as? Bool == true { el.hidden = true }
        return el
    }

    func testTheSharedDropRows() throws {
        let rows = try rows("quick_flow_drop")
        XCTAssertGreaterThanOrEqual(rows.count, 8)
        for row in rows {
            let name = row["name"] as? String ?? ""
            let list = try XCTUnwrap(row["elements"] as? [[String: Any]], name)
            let elements = try list.map { try dropElement($0) }
            let point = try XCTUnwrap(pair(row["point"]), name)
            let source = try XCTUnwrap(row["source"] as? String, name)
            let target = QuickFlow.dropTarget(elements, source: source, at: point)
            XCTAssertEqual(target?.id, row["target"] as? String, name)
        }
    }

    func testTheSharedTurnedSideRows() throws {
        let rows = try rows("quick_flow_turned")
        XCTAssertGreaterThanOrEqual(rows.count, 8)
        for row in rows {
            let name = row["name"] as? String ?? ""
            let handle = try XCTUnwrap(pair(row["handle"]), name)
            let side = QuickFlow.turnedSide(try rect(row["box"]), handle: handle)
            XCTAssertEqual(side.rawValue, row["side"] as? String, name)
        }
    }

    func testTheCopyKeepsTheLookButNotTheWords() {
        var note = StickyNotes.note(StickyNotes.colours[1])
        note.text = "Idea"
        note.group = "g"
        note.x = 100
        note.y = 100
        XCTAssertTrue(QuickFlow.offers(note))
        let copy = QuickFlow.copy(of: note, at: CGRect(x: 500, y: 100, width: note.w, height: note.h))
        XCTAssertNotEqual(copy.id, note.id)
        XCTAssertNil(copy.text)
        XCTAssertNil(copy.group)
        XCTAssertEqual(copy.fill, note.fill)
        XCTAssertEqual(copy.fontSize, note.fontSize)
        XCTAssertEqual(copy.fontFamily, note.fontFamily)
        XCTAssertEqual(copy.sticky, true)
        XCTAssertEqual(copy.x, 500)
        XCTAssertEqual(copy.w, note.w)
        // A turned shape's copy keeps its turn and size.
        let turned = shape(CGRect(x: 100, y: 100, width: 200, height: 100), turned: 45)
        let next = QuickFlow.copy(of: turned, at: QuickFlow.place(turned, side: .right, page: Page(elements: [turned]),
                                                                   bounds: CGRect(x: 0, y: 0, width: 1080, height: 1080)))
        XCTAssertEqual(next.frame, CGRect(x: 400, y: 100, width: 200, height: 100))
        XCTAssertEqual(next.rotation, 45)
        // Lines, photos poured into shapes and locked shapes offer none.
        XCTAssertFalse(QuickFlow.offers(Element.line()))
        var locked = note
        locked.locked = true
        XCTAssertFalse(QuickFlow.offers(locked))
    }

    func testACopyOfADiagramsBoxIsNoPartOfTheDiagram() throws {
        let made = Diagrams.make(Diagrams.starter(.process), in: CGRect(x: 0, y: 0, width: 600, height: 200),
                                 palette: ["#1a6bff", "#ff7a00"])
        let box = try XCTUnwrap(made.first { $0.diagramPart == "item:0" })
        let copy = QuickFlow.copy(of: box, at: CGRect(x: 0, y: 400, width: box.w, height: box.h))
        XCTAssertNil(copy.diagram)
        XCTAssertNil(copy.diagramPart)
        XCTAssertNil(copy.group)
    }

    func testTheConnectorTakesThePagesLastConnectorsLook() {
        var a = Element.shape("rect", w: 100, h: 100)
        a.x = 0
        a.y = 0
        var b = Element.shape("rect", w: 100, h: 100)
        b.x = 300
        b.y = 0
        // None to copy: 2 of ink, an arrow at its end, tied both ways and
        // laid from edge to edge.
        let plain = QuickFlow.connector(from: a, to: b, style: nil)
        XCTAssertEqual(plain.thickness, 2)
        XCTAssertEqual(plain.color, "#1f2430")
        XCTAssertEqual(plain.endCap, "arrow")
        XCTAssertEqual(plain.connectFrom, a.id)
        XCTAssertEqual(plain.connectTo, b.id)
        let ends = LineRoutes.ends(of: plain)
        XCTAssertEqual(Double(ends.start.x), 100, accuracy: 1e-6)
        XCTAssertEqual(Double(ends.end.x), 300, accuracy: 1e-6)
        // The page's last connector's look.
        var styled = plain
        styled.color = "#ff0000"
        styled.thickness = 6
        styled.dash = "dashed"
        styled.endCap = "dot"
        let page = Page(elements: [a, b, styled])
        let next = QuickFlow.connector(from: a, to: b, style: QuickFlow.lastConnector(on: page))
        XCTAssertEqual(next.color, "#ff0000")
        XCTAssertEqual(next.thickness, 6)
        XCTAssertEqual(next.dash, "dashed")
        XCTAssertEqual(next.endCap, "dot")
    }

    func testADraggedPlusTiesToWhatItIsLetGoOn() {
        var a = Element.shape("rect", w: 100, h: 100)
        a.id = "a"
        var b = Element.shape("rect", w: 100, h: 100)
        b.id = "b"
        b.x = 300
        var line = Element.line()
        line.id = "line"
        line.x = 250
        line.y = 46
        let elements = [a, b, line]
        XCTAssertEqual(QuickFlow.dropTarget(elements, source: "a", at: CGPoint(x: 350, y: 50))?.id, "b")
        // Not the source itself, nor a line, nor empty space.
        XCTAssertNil(QuickFlow.dropTarget(elements, source: "a", at: CGPoint(x: 50, y: 50)))
        XCTAssertNil(QuickFlow.dropTarget(elements, source: "a", at: CGPoint(x: 260, y: 50)))
        XCTAssertNil(QuickFlow.dropTarget(elements, source: "a", at: CGPoint(x: 700, y: 700)))
        XCTAssertEqual(QuickFlow.centred(a, at: CGPoint(x: 700, y: 700)), CGRect(x: 650, y: 650, width: 100, height: 100))
    }

    // MARK: Canva's keys and the pointer

    func testDigitKeysSetTransparencyAsOneNamedStep() {
        let store = DesignStore(design: Design(title: "t", width: 1080, height: 1080))
        store.addKeyShape(.circle)
        XCTAssertEqual(store.singleSelection?.shapeId, "circle")
        store.setTransparencyKey(3)
        XCTAssertEqual(store.singleSelection?.opacity ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(store.undoLabel, tr("Transparency"))
        store.setTransparencyKey(0)
        XCTAssertEqual(store.singleSelection?.opacity, 1)
        // Locked things keep theirs.
        store.updateSelected { $0.locked = true }
        store.setTransparencyKey(5)
        XCTAssertEqual(store.singleSelection?.opacity, 1)
        // R and L: a square and a level line, each selected.
        store.addKeyShape(.square)
        XCTAssertEqual(store.singleSelection?.shapeId, "rect")
        store.addKeyShape(.line)
        XCTAssertEqual(store.singleSelection?.type, .line)
        XCTAssertEqual(store.singleSelection?.rotation, 0)
    }

    func testTheOutlineUnderAPointerIsWhatATapWouldSelect() {
        var a = Element.shape("rect", w: 100, h: 100)
        a.id = "a"
        var b = Element.shape("rect", w: 100, h: 100)
        b.id = "b"
        b.x = 300
        b.group = "g"
        var c = Element.shape("rect", w: 100, h: 100)
        c.id = "c"
        c.x = 450
        c.group = "g"
        let elements = [a, b, c]
        XCTAssertEqual(HoverOutline.target(elements, selection: [], at: CGPoint(x: 50, y: 50), touchRadius: 1), ["a"])
        // A group's member: the whole group, as a tap takes it.
        XCTAssertEqual(HoverOutline.target(elements, selection: [], at: CGPoint(x: 350, y: 50), touchRadius: 1),
                       ["b", "c"])
        XCTAssertNil(HoverOutline.target(elements, selection: [], at: CGPoint(x: 900, y: 900), touchRadius: 1))
        // Never drawn over what is selected already.
        XCTAssertFalse(HoverOutline.shows(["a"], selection: ["a"]))
        XCTAssertTrue(HoverOutline.shows(["b", "c"], selection: ["b"]))
        XCTAssertEqual(HoverOutline.key, "canvia.hoverOutline")
    }

    func testAQuickFlowAddIsOneNamedStep() {
        let store = DesignStore(design: Design(title: "q", width: 1080, height: 1080))
        var shape = Element.shape("rect", w: 200, h: 100)
        shape.x = 100
        shape.y = 400
        store.add(shape)
        let before = store.page.elements.count
        store.addConnected(.right)
        XCTAssertEqual(store.page.elements.count, before + 2)
        let copy = store.page.elements[store.page.elements.count - 2]
        let line = store.page.elements[store.page.elements.count - 1]
        XCTAssertEqual(copy.frame, CGRect(x: 400, y: 400, width: 200, height: 100))
        XCTAssertEqual(line.connectFrom, shape.id)
        XCTAssertEqual(line.connectTo, copy.id)
        XCTAssertEqual(store.selection, [copy.id])
        XCTAssertEqual(store.editingTextId, copy.id)
        store.endTextEdit()
        XCTAssertEqual(store.undoLabel, QuickFlow.stepName)
        store.undo()
        XCTAssertEqual(store.page.elements.count, before)
    }
}
