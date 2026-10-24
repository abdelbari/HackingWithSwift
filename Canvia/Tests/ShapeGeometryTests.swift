// Round 34's shape geometry: corner rounding on every straight-edged shape,
// and a star's points, a polygon's sides, an arrow's head and shaft, a
// callout's tail and a notch as parameters. The path rows are the shared
// fixture shape-geometry.json, read by the Android twin too.

import XCTest
@testable import Canvia

final class ShapeGeometryTests: XCTestCase {

    func testTheSharedPathRows() throws {
        let rows = try XCTUnwrap(SharedFixture.object("shape-geometry")["paths"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let id = try XCTUnwrap(row["shapeId"] as? String)
            let w = try XCTUnwrap((row["w"] as? NSNumber)?.doubleValue)
            let h = try XCTUnwrap((row["h"] as? NSNumber)?.doubleValue)
            let radius = try XCTUnwrap((row["radius"] as? NSNumber)?.doubleValue)
            let params = (row["params"] as? [String: NSNumber])?.mapValues(\.doubleValue)
            XCTAssertEqual(ShapeGeometry.path(id, w: w, h: h, radius: radius, params: params), row["d"] as? String, "\(row)")
        }
    }

    func testAtItsOwnLookEveryShapeIsItsStoredPolygon() {
        // Not rounded and every parameter its own, each shape built here has
        // the stored shape's corners, so nothing changes until asked.
        for shape in ContentLibrary.shapes where ShapeGeometry.rounds(shape.id) && shape.id != "speech" {
            let built = ShapeGeometry.unitPolygon(shape.id, nil) ?? []
            let stored = SVGPath.path(shape.path)
            var corners: [CGPoint] = []
            stored.applyWithBlock { e in
                if e.pointee.type == .moveToPoint || e.pointee.type == .addLineToPoint {
                    corners.append(e.pointee.points[0])
                }
            }
            for p in built {
                XCTAssertTrue(corners.contains { abs($0.x - p.x * 100) < 0.05 && abs($0.y - p.y * 100) < 0.05 },
                              "\(shape.id) \(p)")
            }
        }
        var star = Element.shape("star-5")
        XCTAssertNil(ShapeGeometry.outline(star), "drawn from the stored path")
        star.radius = 6
        XCTAssertNotNil(ShapeGeometry.outline(star))
        var square = Element.shape("rect")
        square.radius = 6
        XCTAssertNil(ShapeGeometry.outline(square), "a rectangle rounds as it always has")
        var heart = Element.shape("heart")
        heart.radius = 6
        XCTAssertNil(ShapeGeometry.outline(heart), "a curve takes no rounding")
    }

    func testOnlyWhatDiffersIsKeptAndEachIsHeldToItsRange() {
        XCTAssertNil(ShapeGeometry.kept("star-5", ["points": 5, "inner": 0.4]))
        XCTAssertEqual(ShapeGeometry.kept("star-5", ["points": 30, "inner": 0.4]), ["points": 24])
        XCTAssertEqual(ShapeGeometry.kept("star-5", ["points": 6.4]), ["points": 6])
        XCTAssertEqual(ShapeGeometry.kept("hexagon", ["sides": 1, "head": 0.5]), ["sides": 3])
        XCTAssertEqual(ShapeGeometry.kept("arrow-double", ["head": 0.9]), ["head": 0.5])
        XCTAssertEqual(ShapeGeometry.kept("speech", ["tailY": 2]), ["tailY": 1.4])
        XCTAssertEqual(ShapeGeometry.kept("tag", ["notch": -1]), ["notch": 0])
        XCTAssertNil(ShapeGeometry.kept("heart", ["points": 7]))
    }

    func testTheKeyIsWrittenOnlyWhenSetAndAnOlderShapeIdStays() throws {
        var el = Element.shape("star-5")
        ShapeGeometry.setting("points", to: 7, on: &el)
        XCTAssertEqual(el.shapeParams, ["points": 7])
        XCTAssertEqual(el.shapeId, "star-5")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(el), encoding: .utf8))
        XCTAssertTrue(json.contains("\"shapeParams\":{\"points\":7}"), json)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: Data(json.utf8)).shapeParams, ["points": 7])
        ShapeGeometry.setting("points", to: 5, on: &el)
        XCTAssertNil(el.shapeParams, "back to its own: no key")
        let plain = try XCTUnwrap(String(data: JSONEncoder().encode(el), encoding: .utf8))
        XCTAssertFalse(plain.contains("shapeParams"), plain)
        // A value that is no number is left out as it is read.
        let odd = #"{"id":"s","type":"shape","shapeId":"star-5","shapeParams":{"points":"many","inner":0.6}}"#
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: Data(odd.utf8)).shapeParams, ["inner": 0.6])
    }

    func testAHandleDraggedReshapesWithinItsRange() {
        XCTAssertEqual(ShapeGeometry.handles("star-4", nil).count, 1)
        XCTAssertEqual(ShapeGeometry.dragged("star-4", nil, to: CGPoint(x: 0.5, y: 0.2)), ["inner": 0.6])
        XCTAssertEqual(ShapeGeometry.dragged("star-4", nil, to: CGPoint(x: 0.5, y: 0.5)), ["inner": 0.2])
        let arrow = ShapeGeometry.dragged("arrow-right", nil, to: CGPoint(x: 0.75, y: 0.3)) ?? [:]
        XCTAssertEqual(arrow["head"] ?? 0, 0.25, accuracy: 1e-9)
        XCTAssertNil(arrow["shaft"], "0.4 is its own")
        XCTAssertEqual(ShapeGeometry.dragged("speech", nil, to: CGPoint(x: 0.9, y: 1.2)), ["tailX": 0.9, "tailY": 1.2])
        XCTAssertEqual(ShapeGeometry.dragged("chevron", nil, to: CGPoint(x: 0.9, y: 0.5)), ["notch": 0.5])
        XCTAssertEqual(ShapeGeometry.handles("hexagon", nil), [], "sides are counted, not dragged")
        XCTAssertEqual(ShapeGeometry.countKey("hexagon"), "sides")
        XCTAssertEqual(ShapeGeometry.countKey("seal"), "points")
    }

    func testADragOrACountIsOneStepNamedShape() {
        var star = Element.shape("star-5", w: 200, h: 200)
        star.id = "star"
        var d = Design(title: "shapes", width: 600, height: 600)
        d.pages[0].elements = [star]
        let s = DesignStore(design: d)
        s.select("star")
        XCTAssertEqual(s.geometryHandles.count, 1)
        s.dragGeometryHandle(to: CGPoint(x: 100, y: 40))
        s.dragGeometryHandle(to: CGPoint(x: 100, y: 30))
        s.endGeometryDrag()
        XCTAssertEqual(s.element("star")?.shapeParams?["inner"] ?? 0, 0.7, accuracy: 1e-9)
        XCTAssertEqual(s.undoLabel, "Shape")
        s.undo()
        XCTAssertNil(s.element("star")?.shapeParams, "one step")
        s.setShapeParameter("points", to: 8)
        XCTAssertEqual(s.element("star")?.shapeParams, ["points": 8])
        XCTAssertEqual(s.undoLabel, "Shape")
        // Held in place, a shape keeps its geometry.
        s.updateSelected { $0.lockPosition = true }
        XCTAssertTrue(s.geometryHandles.isEmpty)
    }

    @MainActor
    func testTheExportsDrawTheSameOutline() {
        var tri = Element.shape("triangle", w: 200, h: 100)
        tri.radius = 12
        var d = Design(title: "shapes", width: 600, height: 600)
        d.pages[0].elements = [tri]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("d=\"\(ShapeGeometry.outline(tri) ?? "-")\""), svg)
        let xml = PptxExporter.slide(design: d, page: d.pages[0], number: 1, previous: nil, firstImage: 1).xml
        XCTAssertTrue(xml.contains("<a:custGeom>"), xml)
        XCTAssertFalse(xml.contains("<p:pic>"), "a free-form shape, not a picture")
        XCTAssertEqual(PptxExporter.form(of: tri), .geometry)
        XCTAssertEqual(PptxExporter.form(of: Element.shape("triangle")), .picture, "unrounded, as before")
    }
}
