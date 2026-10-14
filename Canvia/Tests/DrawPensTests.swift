// The pens' size and transparency, a drawing session kept together, and
// the eraser taking part of a stroke, in rows the Android twin's tests
// hold too.

import XCTest
import CoreGraphics
@testable import Canvia

final class DrawPensTests: XCTestCase {

    // MARK: size and transparency

    func testTheSizeSliderSettlesOnTheOldWidthsAndIsWholeBetween() {
        let rows: [(Double, Double)] = [
            (4.6, 4), (5.3, 6), (5, 5), (1.3, 2), (23.4, 24), (30.2, 30), (12.4, 12), (0.2, 1), (75, 60),
        ]
        for (value, width) in rows {
            XCTAssertEqual(Freehand.snappedWidth(value), width, "\(value)")
        }
        XCTAssertEqual(Freehand.widthRange, 1...60)
        XCTAssertEqual(Freehand.widths, [2, 4, 6, 10, 16, 24])
    }

    func testTransparencyIsWholeToNinetyAndWrittenAsOpacity() {
        XCTAssertEqual(Freehand.keptTransparency(45.6), 46)
        XCTAssertEqual(Freehand.keptTransparency(95), 90)
        XCTAssertEqual(Freehand.keptTransparency(-3), 0)
        XCTAssertEqual(Freehand.opacity(transparency: 30), 0.7, accuracy: 1e-9)
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40)]
        let clear = Freehand.element(points: points, tool: Freehand.Tool(color: "#ef4444", width: 10, transparency: 40))
        XCTAssertEqual(clear?.opacity ?? 0, 0.6, accuracy: 1e-9)
        XCTAssertEqual(Freehand.element(points: points, tool: Freehand.Tool())?.opacity, 1)
        // The highlighter's own see-through ink is kept beside it.
        let marker = Freehand.element(points: points, tool: Freehand.Tool(color: "#22c55e", pen: .highlighter, transparency: 50))
        XCTAssertEqual(marker?.stroke, "#22c55e73")
        XCTAssertEqual(marker?.opacity ?? 0, 0.5, accuracy: 1e-9)
    }

    // MARK: a session's strokes kept together

    @MainActor
    func testStrokesDrawnTogetherBecomeOneDrawingAndUndoStillTakesOneStroke() {
        let store = DesignStore(design: Design(title: "d", width: 400, height: 300))
        store.toggleDrawing()
        store.finishStroke([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 40), CGPoint(x: 90, y: 10)])
        store.finishStroke([CGPoint(x: 10, y: 100), CGPoint(x: 60, y: 120)])
        store.drawing = nil
        let strokes = store.page.elements
        XCTAssertEqual(strokes.count, 2)
        XCTAssertNotNil(strokes[0].group)
        XCTAssertEqual(strokes[0].group, strokes[1].group)
        XCTAssertEqual(strokes.map(\.layerName), ["Drawing", "Drawing"])
        // Part of the last stroke's step: one Undo takes that stroke only.
        store.undo()
        XCTAssertEqual(store.page.elements.count, 1)
        XCTAssertNil(store.page.elements[0].group)
    }

    @MainActor
    func testAfterAnUndoTheDrawingIsGroupedAsAStepOfItsOwn() {
        let store = DesignStore(design: Design(title: "d", width: 400, height: 300))
        store.toggleDrawing()
        store.finishStroke([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 40)])
        store.finishStroke([CGPoint(x: 10, y: 100), CGPoint(x: 60, y: 120)])
        store.finishStroke([CGPoint(x: 100, y: 100), CGPoint(x: 160, y: 120)])
        store.undo()
        store.drawing = nil
        let kept = store.page.elements
        XCTAssertEqual(kept.count, 2)
        XCTAssertNotNil(kept[0].group)
        XCTAssertEqual(kept[0].group, kept[1].group)
        // Its own step: Undo takes back the grouping, Redo brings it again.
        store.undo()
        XCTAssertEqual(store.page.elements.count, 2)
        XCTAssertTrue(store.page.elements.allSatisfy { $0.group == nil })
        store.redo()
        XCTAssertNotNil(store.page.elements[0].group)
        XCTAssertEqual(store.page.elements[0].group, store.page.elements[1].group)
    }

    @MainActor
    func testOneStrokeIsNoGroupAndANewSessionStartsAfresh() {
        let store = DesignStore(design: Design(title: "d", width: 400, height: 300))
        store.toggleDrawing()
        store.finishStroke([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 40)])
        store.toggleDrawing()
        XCTAssertNil(store.page.elements[0].group)
        store.toggleDrawing()
        store.finishStroke([CGPoint(x: 10, y: 100), CGPoint(x: 60, y: 120)])
        store.toggleDrawing()
        XCTAssertTrue(store.page.elements.allSatisfy { $0.group == nil }, "one stroke a session, twice")
    }

    // MARK: partial erase

    /// A straight stroke through (0,5), (25,5), (50,5), (75,5) and (100,5).
    private func straightStroke() -> Element {
        var e = Element.shape("freehand", w: 100, h: 10)
        e.pathData = "M0 50L25 50L50 50L75 50L100 50"
        e.fill = Paint.clear
        e.stroke = "#ef4444"
        e.strokeWidth = 4
        e.opacity = 0.5
        e.blendMode = "multiply"
        e.group = "grp_drawing"
        return e
    }

    func testTheEraserTakesThePointsItReachesAndLeavesTheRunsEitherSide() throws {
        let stroke = straightStroke()
        let cuts = Freehand.erasedPartially([stroke], path: [CGPoint(x: 50, y: 5)], radius: 10)
        XCTAssertEqual(cuts.count, 1)
        XCTAssertEqual(cuts[0].id, stroke.id)
        let pieces = cuts[0].pieces
        XCTAssertEqual(pieces.count, 2)
        // (0,5)–(25,5) laid as a stroke is: padded by half the width and one.
        XCTAssertEqual(pieces[0].x, -3)
        XCTAssertEqual(pieces[0].y, 2)
        XCTAssertEqual(pieces[0].w, 31)
        XCTAssertEqual(pieces[0].h, 6)
        XCTAssertEqual(pieces[0].pathData, "M9.68 50Q50 50 90.32 50")
        XCTAssertEqual(pieces[1].x, 72)
        XCTAssertEqual(pieces[1].pathData, "M9.68 50Q50 50 90.32 50")
        for piece in pieces {
            XCTAssertNotEqual(piece.id, stroke.id)
            XCTAssertEqual(piece.stroke, "#ef4444")
            XCTAssertEqual(piece.strokeWidth, 4)
            XCTAssertEqual(piece.opacity, 0.5)
            XCTAssertEqual(piece.blendMode, "multiply")
            XCTAssertEqual(piece.group, "grp_drawing")
            XCTAssertTrue(Freehand.isStroke(piece))
        }
        XCTAssertNotEqual(pieces[0].id, pieces[1].id)
    }

    func testARunOfOnePointIsDroppedAndAStrokeRubbedOutWholeLeavesNothing() {
        let stroke = straightStroke()
        // Along x = 60: (50,5) and (75,5) are within 16, leaving (0,5)–(25,5)
        // and (100,5) alone, which is too short to keep.
        let swept = Freehand.erasedPartially([stroke], path: [CGPoint(x: 60, y: -20), CGPoint(x: 60, y: 30)], radius: 16)
        XCTAssertEqual(swept.first?.pieces.count, 1)
        XCTAssertEqual(swept.first?.pieces.first?.x, -3)
        let whole = Freehand.erasedPartially([stroke], path: [CGPoint(x: 50, y: 5)], radius: 60)
        XCTAssertEqual(whole, [Freehand.Cut(id: stroke.id, pieces: [])])
    }

    func testTheEraserPassesStrokesItMissesAndThoseLockedOrHidden() {
        var locked = straightStroke()
        locked.locked = true
        var hidden = straightStroke()
        hidden.hidden = true
        var shape = Element.shape("rect", w: 100, h: 10)
        shape.pathData = "M0 50L100 50"
        XCTAssertEqual(Freehand.erasedPartially([straightStroke()], path: [CGPoint(x: 50, y: 60)], radius: 10), [])
        XCTAssertEqual(Freehand.erasedPartially([locked, hidden, shape], path: [CGPoint(x: 50, y: 5)], radius: 10), [])
        XCTAssertEqual(Freehand.erasedPartially([straightStroke()], path: [], radius: 10), [])
    }

    @MainActor
    func testAPartEraseIsOneStepAndThePiecesKeepTheStrokesPlace() {
        var d = Design(title: "d", width: 400, height: 300)
        let below = Element.shape("rect", w: 20, h: 20)
        let above = Element.shape("circle", w: 20, h: 20)
        let stroke = straightStroke()
        d.pages[0].elements = [below, stroke, above]
        let store = DesignStore(design: d)
        store.drawing = Freehand.Tool(pen: .eraser)
        // The eraser's reach at the default size is 12: (50,5) only.
        store.finishStroke([CGPoint(x: 50, y: 5)])
        let ids = store.page.elements.map(\.id)
        XCTAssertEqual(ids.count, 4)
        XCTAssertEqual(ids.first, below.id)
        XCTAssertEqual(ids.last, above.id)
        XCTAssertFalse(ids.contains(stroke.id))
        XCTAssertEqual(store.announcement, "Erased part of a stroke")
        store.undo()
        XCTAssertEqual(store.page.elements.map(\.id), [below.id, stroke.id, above.id])
    }

    @MainActor
    func testWholeStrokeStillTakesTheWholeStroke() {
        var d = Design(title: "d", width: 400, height: 300)
        d.pages[0].elements = [straightStroke()]
        let store = DesignStore(design: d)
        store.drawing = Freehand.Tool(pen: .eraser, eraseWhole: true)
        store.finishStroke([CGPoint(x: 50, y: 5)])
        XCTAssertTrue(store.page.elements.isEmpty)
    }

    func testAnImportedSVGsUnfilledPartsAreNoStrokesAndNeitherEraserTakesThem() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\">"
            + "<path d=\"M5 12h14M12 5v14\" fill=\"none\" stroke=\"#000000\" stroke-width=\"2\"/>"
            + "<line x1=\"2\" y1=\"2\" x2=\"22\" y2=\"2\" stroke=\"#ff0000\"/></svg>"
        let parts = try XCTUnwrap(SvgImport.graphic(svg, pageWidth: 1000, pageHeight: 1000)).elements
        XCTAssertEqual(parts.count, 2)
        for part in parts {
            XCTAssertEqual(part.fill?.kind, "none")
            XCTAssertFalse(Freehand.isStroke(part))
        }
        let sweep = [CGPoint(x: 0, y: 0), CGPoint(x: 1000, y: 1000), CGPoint(x: 0, y: 1000), CGPoint(x: 1000, y: 0)]
        XCTAssertEqual(Freehand.erasedPartially(parts, path: sweep, radius: 1000), [])
        XCTAssertTrue(Freehand.erased(parts, path: sweep, radius: 1000).isEmpty)
    }

    func testAnImportedSVGsLineAndUnfilledPartsTakeAColourAsTheirInk() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\">"
            + "<path d=\"M5 12h14M12 5v14\" fill=\"none\" stroke=\"#000000\" stroke-width=\"2\"/>"
            + "<line x1=\"2\" y1=\"2\" x2=\"22\" y2=\"2\" stroke=\"#ff0000\"/></svg>"
        let parts = try XCTUnwrap(SvgImport.graphic(svg, pageWidth: 1000, pageHeight: 1000)).elements
        XCTAssertEqual(parts.count, 2)
        for part in parts {
            XCTAssertTrue(Freehand.inksOnly(part))
            let coloured = Freehand.coloured(part, "#00ff00")
            XCTAssertEqual(coloured.stroke, "#00ff00")
            XCTAssertEqual(coloured.fill?.kind, "none")
            XCTAssertEqual(Freehand.fillColour(coloured), "#00ff00")
            let recoloured = DesignStore.recoloured(part, to: "#00ff00")
            XCTAssertEqual(recoloured.stroke, "#00ff00", "a selected graphic's line part changes its ink")
            XCTAssertEqual(recoloured.fill?.kind, "none")
        }
        let box = Element.shape("rect")
        XCTAssertFalse(Freehand.inksOnly(box))
        XCTAssertEqual(Freehand.coloured(box, "#00ff00").fill, .solid("#00ff00"))
        // An outline with no stroke has no ink to colour: it is filled.
        var bare = parts[0]
        bare.stroke = nil
        XCTAssertFalse(Freehand.inksOnly(bare))
        XCTAssertEqual(Freehand.coloured(bare, "#00ff00").fill, .solid("#00ff00"))
    }
}
