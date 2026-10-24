// Lines whose ends are dragged anywhere, and elbowed and curved lines, as
// the Android twin's LineRoutesTest has them, row for row.

import XCTest
@testable import Canvia

@MainActor
final class LineRoutesTests: XCTestCase {

    /// A straight line from (0, 0) to (100, 0), 4 thick.
    private var flat: Element {
        var el = Element.line(w: 100)
        el.id = "l"
        el.x = 0
        el.y = -4
        return el
    }

    private func box(_ id: String, x: Double, y: Double) -> Element {
        var el = Element.shape("rect", w: 100, h: 100)
        el.id = id
        el.x = x
        el.y = y
        return el
    }

    private func near(_ expected: CGPoint, _ actual: CGPoint, _ eps: Double = 1e-6,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(actual.x), Double(expected.x), accuracy: eps, "x of \(actual)", file: file, line: line)
        XCTAssertEqual(Double(actual.y), Double(expected.y), accuracy: eps, "y of \(actual)", file: file, line: line)
    }

    func testAStraightLinesEndsAreAcrossItsMiddleTurnedWithIt() {
        let ends = LineRoutes.ends(of: flat)
        near(CGPoint(x: 0, y: 0), ends.start)
        near(CGPoint(x: 100, y: 0), ends.end)
        var upright = Element.line(w: 300)
        upright.x = 100
        upright.y = 96
        upright.rotation = 90
        let turned = LineRoutes.ends(of: upright)
        near(CGPoint(x: 250, y: -50), turned.start)
        near(CGPoint(x: 250, y: 250), turned.end)
        // Flipped across, its start is on the right.
        var flipped = flat
        flipped.flipH = true
        near(CGPoint(x: 100, y: 0), LineRoutes.ends(of: flipped).start)
    }

    func testTheSharedEndDragTable() {
        // Pointer, the end it lands at, and whether it is held on a snap.
        let rows: [(pointer: CGPoint, landed: CGPoint, snapped: Bool)] = [
            // Within 3 degrees of 0: level, as long as the finger is far.
            (CGPoint(x: 100, y: 4), CGPoint(x: 100.07996802557443, y: 0), true),
            // 5.7 degrees is no multiple of 15 within 3: where the finger is.
            (CGPoint(x: 100, y: 10), CGPoint(x: 100, y: 10), false),
            // 14 degrees: held on 15.
            (CGPoint(x: 100, y: 25), CGPoint(x: 99.56535520754612, y: 26.678456521979857), true),
            // Straight down: 90.
            (CGPoint(x: 2, y: 80), CGPoint(x: 0, y: 80.02499609497022), true),
        ]
        for row in rows {
            let drag = LineRoutes.endDragged(flat, atStart: false, pointer: row.pointer, others: [], reach: 10)
            XCTAssertEqual(drag.snapped, row.snapped, "\(row.pointer)")
            let ends = LineRoutes.ends(of: drag.line)
            near(CGPoint(x: 0, y: 0), ends.start, 1e-9)
            near(row.landed, ends.end, 1e-9)
            XCTAssertNil(drag.target)
        }
        // The readout's length and angle, start to end.
        let down = LineRoutes.endDragged(flat, atStart: false, pointer: CGPoint(x: 2, y: 80), others: [], reach: 10)
        XCTAssertEqual(down.angle, 90, accuracy: 1e-9)
        XCTAssertEqual(down.length, 80.02499609497022, accuracy: 1e-9)
        var paper = Design(title: "l", width: 2480, height: 3508)
        XCTAssertEqual(LineRoutes.readout(down, design: paper), "80 · 90°")
        // In the design's unit, as the move and size readouts beside it.
        paper.unit = "mm"
        paper.dpi = 300
        XCTAssertEqual(LineRoutes.readout(down, design: paper), "6.8 mm · 90°")
        // The start dragged: the end holds, the angle still read start to end.
        let left = LineRoutes.endDragged(flat, atStart: true, pointer: CGPoint(x: -50, y: 1), others: [], reach: 10)
        near(CGPoint(x: 100, y: 0), LineRoutes.ends(of: left.line).end)
        XCTAssertEqual(left.angle, 0, accuracy: 1e-9)
    }

    func testAnEndSnapsToAnotherElementsEdgeMidpointsAndCentreAndIsTiedThere() {
        let square = box("box", x: 200, y: -50)
        let drag = LineRoutes.endDragged(flat, atStart: false, pointer: CGPoint(x: 195, y: 3), others: [square, flat], reach: 10)
        XCTAssertEqual(drag.target, "box")
        XCTAssertTrue(drag.snapped)
        near(CGPoint(x: 200, y: 0), LineRoutes.ends(of: drag.line).end)
        let points = LineRoutes.snapPoints(square)
        let expected = [CGPoint(x: 250, y: -50), CGPoint(x: 300, y: 0), CGPoint(x: 250, y: 50),
                        CGPoint(x: 200, y: 0), CGPoint(x: 250, y: 0)]
        XCTAssertEqual(points.count, expected.count)
        for (e, a) in zip(expected, points) { near(e, a) }
        // Out of reach of them all: free, and not tied.
        XCTAssertNil(LineRoutes.endDragged(flat, atStart: false, pointer: CGPoint(x: 230, y: 20),
                                           others: [square], reach: 10).target)
        // Tied by start or end under the existing keys; let go with nil.
        let tied = LineRoutes.tied(drag.line, atStart: false, to: "box")
        XCTAssertEqual(tied.connectTo, "box")
        XCTAssertNil(tied.connectFrom)
        XCTAssertNil(LineRoutes.tied(tied, atStart: false, to: nil).connectTo)
    }

    func testTheSharedElbowAndCurveRouteTable() throws {
        // From (0, 0) to (100, 50), 4 thick: a box padded by 4 round the ends.
        var plain = Element.line(w: 100)
        plain.y = -4
        let elbow = LineRoutes.withType(plain, .elbow)
        let ended = LineRoutes.withEnds(elbow, CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50))
        XCTAssertEqual([ended.x, ended.y, ended.w, ended.h], [-4, -4, 108, 58])
        XCTAssertEqual(ended.rotation, 0)
        let fractions = try XCTUnwrap(ended.ends)
        for (e, a) in zip([4.0 / 108, 4.0 / 58, 104.0 / 108, 54.0 / 58], fractions) { XCTAssertEqual(a, e, accuracy: 1e-12) }
        let route = LineRoutes.route(ended)
        XCTAssertEqual(route.points.count, 4)
        let corners = [CGPoint(x: 4, y: 4), CGPoint(x: 54, y: 4), CGPoint(x: 54, y: 54), CGPoint(x: 104, y: 54)]
        for (e, a) in zip(corners, route.points) { near(e, a, 1e-9) }
        XCTAssertEqual(route.startAngle, .pi, accuracy: 1e-9)
        XCTAssertEqual(route.endAngle, 0, accuracy: 1e-9)
        // A bend of 0.5 puts the corner three quarters of the way across.
        near(CGPoint(x: 79, y: 4), LineRoutes.route(LineRoutes.withBend(ended, 0.5)).points[1], 1e-9)
        // Cut back 10 at the start, for an arrowhead.
        near(CGPoint(x: 14, y: 4), LineRoutes.trimmed(route, startBack: 10, endBack: 0)[0], 1e-9)

        // A curve from (0, 0) to (100, 0) bowing a quarter of its length to
        // its right — below — through (50, 25): its control point at (50, 50).
        let curve = LineRoutes.withEnds(LineRoutes.withType(flat, .curve), CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0))
        XCTAssertEqual(LineRoutes.bend(of: curve), LineRoutes.curveBend)
        let bow = LineRoutes.route(curve)
        XCTAssertTrue(bow.curved)
        near(CGPoint(x: 54, y: 54), bow.points[1], 1e-9)
        XCTAssertEqual(bow.startAngle, -3 * .pi / 4, accuracy: 1e-9)
        XCTAssertEqual(LineRoutes.bow(curve), 25, accuracy: 1e-9)
        near(CGPoint(x: 50, y: 50), LineRoutes.control(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), bend: 0.25), 1e-9)
        // A triangle's tip and back corners, 10 long, pointing along +x.
        let head = try XCTUnwrap(LineEnds.head(LineEnds.Kind.triangle, tip: CGPoint(x: 0, y: 0), angle: 0, thickness: 2))
        guard case .polygon(let corners) = head.outline else { return XCTFail("a triangle is a polygon") }
        for (e, a) in zip([CGPoint(x: 0, y: 0), CGPoint(x: -10, y: -6), CGPoint(x: -10, y: 6)], corners) { near(e, a, 1e-12) }
    }

    func testALinesWeightChangedKeepsItsEndsWhereTheyWere() {
        // An elbow from (100, 100) to (300, 300), 4 thick, is 208 tall; 6
        // thick it is 212, its ends held, not squashed into an 8 tall band.
        let elbow = LineRoutes.withEnds(LineRoutes.withType(flat, .elbow), CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 300))
        XCTAssertEqual(elbow.h, 208)
        let heavier = LineRoutes.withThickness(elbow, 6)
        XCTAssertEqual(heavier.thickness, 6)
        XCTAssertEqual([heavier.x, heavier.y, heavier.w, heavier.h], [94, 94, 212, 212])
        near(CGPoint(x: 100, y: 100), LineRoutes.ends(of: heavier).start, 1e-9)
        near(CGPoint(x: 300, y: 300), LineRoutes.ends(of: heavier).end, 1e-9)
        // A straight line is as tall as its weight, and at least 8; with no
        // weight written its height is kept.
        XCTAssertEqual(LineRoutes.withThickness(flat, 20).h, 20)
        XCTAssertEqual(LineRoutes.withThickness(flat, 2).h, 8)
        var tall = flat
        tall.h = 20
        XCTAssertEqual(LineRoutes.withThickness(tall, 2).h, 8)
        XCTAssertEqual(LineRoutes.withThickness(tall, nil).h, 20)

        // A line's style pasted on an elbow, as the Android twin's
        // ElementStyleTest has it: the weight lays it round the same ends.
        var arrow = Element.line()
        arrow.thickness = 12
        arrow.endCap = "arrow"
        var heavy = LineRoutes.withEnds(LineRoutes.withType(Element.line(), .elbow),
                                        CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 300))
        DesignStore.apply(DesignStore.style(of: arrow), to: &heavy)
        XCTAssertEqual([heavy.x, heavy.y, heavy.w, heavy.h], [88, 88, 224, 224])
        near(CGPoint(x: 100, y: 100), LineRoutes.ends(of: heavy).start, 1e-9)
        near(CGPoint(x: 300, y: 300), LineRoutes.ends(of: heavy).end, 1e-9)
        XCTAssertEqual(heavy.endCap, "arrow")
    }

    func testALinesTypeChangesWithItsEndsKeptAndIsInTheFile() throws {
        var turned = Element.line(w: 300)
        turned.x = 100
        turned.y = 96
        turned.rotation = 30
        let before = LineRoutes.ends(of: turned)
        for type in LineRoutes.RouteType.allCases {
            let typed = LineRoutes.withType(turned, type)
            XCTAssertEqual(LineRoutes.routeType(of: typed), type)
            near(before.start, LineRoutes.ends(of: typed).start)
            near(before.end, LineRoutes.ends(of: typed).end)
            // And back.
            let back = LineRoutes.withType(typed, .straight)
            near(before.start, LineRoutes.ends(of: back).start)
            XCTAssertNil(back.lineType)
            XCTAssertNil(back.ends)
            XCTAssertNil(back.bend)
        }
        let elbow = LineRoutes.withType(turned, .elbow)
        XCTAssertEqual(elbow.lineType, "elbow")
        XCTAssertNil(elbow.bend)
        let bent = LineRoutes.withBend(elbow, -0.5)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(bent)) as? [String: Any])
        XCTAssertEqual(object["lineType"] as? String, "elbow")
        XCTAssertEqual(object["bend"] as? Double, -0.5)
        XCTAssertEqual((object["ends"] as? [Double])?.count, 4)
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(bent))
        XCTAssertEqual(LineRoutes.bend(of: back), -0.5)
        XCTAssertEqual(back.ends, bent.ends)
        // A straight line writes none of them.
        let straight = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(turned)) as? [String: Any])
        for key in ["lineType", "ends", "bend"] { XCTAssertNil(straight[key], key) }
        // As the Android twin writes one.
        let android = #"{"id":"l","type":"line","x":0,"y":0,"w":100,"h":40,"lineType":"curve","ends":[0,0,1,1],"bend":0.25}"#
        let read = try JSONDecoder().decode(Element.self, from: Data(android.utf8))
        XCTAssertEqual(LineRoutes.routeType(of: read), .curve)
        XCTAssertEqual(LineRoutes.fractions(of: read), [0, 0, 1, 1])
        XCTAssertEqual(LineRoutes.bend(of: read), 0.25)
    }

    func testAConnectorWithATypeIsLaidOnItsRoute() {
        let a = box("a", x: 0, y: 0)
        let b = box("b", x: 300, y: 200)
        var arrow = Element.line(w: 100)
        arrow.connectFrom = "a"
        arrow.connectTo = "b"
        arrow.endCap = "arrow"
        arrow = LineRoutes.withType(arrow, .elbow)
        var page = Page(elements: [a, b, arrow])
        Connectors.resolve(&page)
        let laid = page.elements[2]
        let ends = LineRoutes.ends(of: laid)
        near(Connectors.anchor(of: a.frame, toward: CGPoint(x: b.frame.midX, y: b.frame.midY)), ends.start)
        near(Connectors.anchor(of: b.frame, toward: CGPoint(x: a.frame.midX, y: a.frame.midY)), ends.end)
        XCTAssertEqual(laid.rotation, 0)
        // Laid again, nothing changes.
        XCTAssertFalse(Connectors.resolve(&page))
    }

    func testALineTiedByOneEndFollowsThatEndAloneAndLetsGoOfItWhenItGoes() throws {
        let a = box("a", x: 0, y: 0)
        let free = LineRoutes.withEnds(flat, CGPoint(x: 150, y: 50), CGPoint(x: 300, y: 50))
        let line = LineRoutes.tied(free, atStart: true, to: "a")
        var design = Design(title: "Lines", width: 1000, height: 1000)
        design.pages[0].elements = [a, line]
        let store = DesignStore(design: design)
        store.select("a")
        store.updateSelected { $0.y = 100 }
        let moved = try XCTUnwrap(store.element("l"))
        near(CGPoint(x: 100, y: 130), LineRoutes.ends(of: moved).start)
        near(CGPoint(x: 300, y: 50), LineRoutes.ends(of: moved).end)
        XCTAssertEqual(moved.connectFrom, "a")
        // Unchanged when nothing moved: laying it again changes nothing.
        var page = store.page
        XCTAssertFalse(Connectors.resolve(&page))
        store.select("a")
        store.deleteSelected()
        let plain = try XCTUnwrap(store.element("l"))
        XCTAssertNil(plain.connectFrom)
        near(CGPoint(x: 300, y: 50), LineRoutes.ends(of: plain).end)
    }

    func testAnEndDraggedAndTiedIsOneUndoStep() throws {
        let square = box("box", x: 200, y: -50)
        var design = Design(title: "Lines", width: 1000, height: 1000)
        design.pages[0].elements = [square, flat]
        let store = DesignStore(design: design)
        store.select("l")
        for x in [120.0, 160.0, 197.0] {
            let drag = LineRoutes.endDragged(flat, atStart: false, pointer: CGPoint(x: x, y: 2),
                                             others: store.page.elements, reach: 10)
            store.updateSelectedTransient { el in
                if el.id == drag.line.id { el = drag.line }
            }
        }
        let last = LineRoutes.endDragged(flat, atStart: false, pointer: CGPoint(x: 197, y: 2),
                                         others: store.page.elements, reach: 10)
        store.updateSelectedTransient { el in
            el = LineRoutes.tied(el, atStart: false, to: last.target)
        }
        store.commit()
        let tied = try XCTUnwrap(store.element("l"))
        XCTAssertEqual(tied.connectTo, "box")
        near(CGPoint(x: 200, y: 0), LineRoutes.ends(of: tied).end)
        store.undo()
        XCTAssertEqual(store.element("l"), flat)
    }

    /// Shared rows with the Android twin's LineRoutesTest: an elbowed or
    /// curved line is touched along its route — a curve where it bows, out
    /// of its box; an elbow not across its box — and outlined and caught
    /// round where it is drawn.
    func testAnElbowOrACurveIsTouchedAlongItsRouteAndOutlinedRoundIt() {
        let curve = LineRoutes.withEnds(LineRoutes.withType(flat, .curve), CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0))
        XCTAssertTrue(LineRoutes.near(curve, CGPoint(x: 200, y: 100), reach: 0))
        XCTAssertTrue(LineRoutes.near(curve, CGPoint(x: 200, y: 110), reach: 12))
        XCTAssertFalse(LineRoutes.near(curve, CGPoint(x: 200, y: 0), reach: 12))
        XCTAssertTrue(Geometry.hits(curve, point: CGPoint(x: 200, y: 100)))
        XCTAssertFalse(Geometry.hits(curve, point: CGPoint(x: 200, y: 0)))
        let outline = LineRoutes.outlineOf(curve)
        XCTAssertEqual(outline.x, -4, accuracy: 1e-6)
        XCTAssertEqual(outline.w, 408, accuracy: 1e-6)
        XCTAssertEqual(outline.y, -4, accuracy: 1e-6)
        XCTAssertEqual(outline.h, 106, accuracy: 1e-6)
        XCTAssertEqual(Geometry.intersecting([curve], CGRect(x: 190, y: 95, width: 20, height: 10)).count, 1)
        XCTAssertEqual(LineRoutes.outlineOf(flat), flat)

        let elbow = LineRoutes.withEnds(LineRoutes.withType(flat, .elbow), CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 200))
        XCTAssertFalse(LineRoutes.near(elbow, CGPoint(x: 50, y: 150), reach: 12))
        XCTAssertFalse(Geometry.hits(elbow, point: CGPoint(x: 50, y: 150)))
        XCTAssertTrue(LineRoutes.near(elbow, CGPoint(x: 105, y: 120), reach: 12))
        XCTAssertTrue(LineRoutes.near(elbow, CGPoint(x: 150, y: 200), reach: 0))
        XCTAssertEqual(LineRoutes.outlineOf(elbow), elbow)
    }

    /// Shared rows with the Android twin's LineRoutesTest: a line tied by
    /// one end, flipped on its own or with its element, keeps its length
    /// and its free end, and stays tied.
    func testALineTiedByOneEndFlippedAloneOrWithItsElementKeepsItsLength() throws {
        let a = box("a", x: 0, y: 0)
        var free = LineRoutes.withEnds(flat, CGPoint(x: 100, y: 50), CGPoint(x: 300, y: 50))
        free.endCap = "arrow"
        let line = LineRoutes.tied(free, atStart: true, to: "a")
        func store() -> DesignStore {
            var design = Design(title: "Lines", width: 1000, height: 1000)
            design.pages[0].elements = [a, line]
            return DesignStore(design: design)
        }

        // Across, alone: the tie goes to the end now on the element.
        let across = store()
        across.select("l")
        across.flipSelected(horizontal: true)
        let flipped = try XCTUnwrap(across.element("l"))
        near(CGPoint(x: 300, y: 50), LineRoutes.ends(of: flipped).start)
        near(CGPoint(x: 100, y: 50), LineRoutes.ends(of: flipped).end)
        XCTAssertNil(flipped.connectFrom)
        XCTAssertEqual(flipped.connectTo, "a")

        // Up and down, alone: a level line's ends stay, and so does the tie.
        let down = store()
        down.select("l")
        down.flipSelected(horizontal: false)
        let level = try XCTUnwrap(down.element("l"))
        near(CGPoint(x: 100, y: 50), LineRoutes.ends(of: level).start)
        near(CGPoint(x: 300, y: 50), LineRoutes.ends(of: level).end)
        XCTAssertEqual(level.connectFrom, "a")

        // Across, with its element: mirrored, its tie and caps swapped.
        let both = store()
        both.select("a")
        both.select("l", additive: true)
        both.flipSelected(horizontal: true)
        let mirrored = try XCTUnwrap(both.element("l"))
        near(CGPoint(x: 0, y: 50), LineRoutes.ends(of: mirrored).start)
        near(CGPoint(x: 200, y: 50), LineRoutes.ends(of: mirrored).end)
        XCTAssertNil(mirrored.connectFrom)
        XCTAssertEqual(mirrored.connectTo, "a")
        XCTAssertEqual(mirrored.startCap, "arrow")
        XCTAssertEqual(mirrored.endCap, "none")
    }

    func testFlippingAnElbowOrACurveMirrorsItsRouteInItsBox() throws {
        let curve = LineRoutes.withEnds(LineRoutes.withType(flat, .curve), CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 40))
        let flipped = try XCTUnwrap(Geometry.flipAll([curve], box: curve.frame, horizontal: true).first)
        let ends = LineRoutes.ends(of: flipped)
        near(CGPoint(x: 100, y: 0), ends.start)
        near(CGPoint(x: 0, y: 40), ends.end)
        XCTAssertEqual(LineRoutes.bend(of: flipped), -LineRoutes.curveBend)
        XCTAssertEqual(flipped.startCap, curve.startCap)
        XCTAssertEqual(flipped.endCap, curve.endCap)
    }

    func testOnlyALineWithAFreeEndOffersEndDiscsAndATypedOneNoTurn() {
        XCTAssertTrue(LineRoutes.hasEndHandles(flat))
        XCTAssertEqual(Touch.handleSet(for: flat), [])
        var joined = flat
        joined.connectFrom = "a"
        joined.connectTo = "b"
        XCTAssertFalse(LineRoutes.hasEndHandles(joined))
        XCTAssertEqual(Touch.handleSet(for: joined), [.e, .w])
        XCTAssertFalse(LineRoutes.keepsLevel(flat))
        XCTAssertTrue(LineRoutes.keepsLevel(LineRoutes.withType(flat, .elbow)))
    }

    func testSVGAndPowerPointDrawAnElbowAndACurveOnTheirRoutes() {
        var elbow = LineRoutes.withEnds(LineRoutes.withType(flat, .elbow), CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50))
        elbow.endCap = "arrow"
        var d = Design(title: "Lines", width: 800, height: 600)
        d.pages = [Page(elements: [elbow])]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        // The stroke's round cap ends on the open arrow's tip at (100, 50):
        // it stops half the weight short of it.
        XCTAssertTrue(svg.contains("<path d=\"M0 0L50 0L50 50L98 50\" fill=\"none\" stroke=\"#1f2430\" stroke-width=\"4\" "
                                   + "stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"), svg)
        XCTAssertTrue(svg.contains("<path d=\"M88 42.8L100 50L88 57.2\" fill=\"none\" stroke=\"#1f2430\" stroke-width=\"4\" "
                                   + "stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"), svg)
        let curve = LineRoutes.withEnds(LineRoutes.withType(flat, .curve), CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0))
        d.pages = [Page(elements: [curve])]
        XCTAssertTrue(SVGExporter.svg(design: d, page: d.pages[0]).contains("<path d=\"M0 0Q50 50 100 0\""))

        d.pages = [Page(elements: [elbow, LineRoutes.withBend(curve, -0.25)])]
        let slide = PptxExporter.slide(design: d, page: d.pages[0], number: 1, previous: nil, firstImage: 1).xml
        XCTAssertTrue(slide.contains("<a:prstGeom prst=\"bentConnector3\"><a:avLst><a:gd name=\"adj1\" fmla=\"val 50000\"/>"
                                     + "</a:avLst></a:prstGeom>"), slide)
        XCTAssertTrue(slide.contains("<a:prstGeom prst=\"curvedConnector3\">"), slide)
        XCTAssertTrue(slide.contains("<a:tailEnd type=\"arrow\"/>"), slide)
        XCTAssertEqual(slide.components(separatedBy: "<p:cxnSp>").count - 1, 2)
    }
}
