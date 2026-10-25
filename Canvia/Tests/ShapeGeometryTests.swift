// Round 34's shape geometry: corner rounding on every straight-edged shape,
// and a star's points, a polygon's sides, an arrow's head and shaft, a
// callout's tail and a notch as parameters. The path, handle, drag and
// write rows are the shared fixture shape-geometry.json, read by the
// Android twin too.

import XCTest
@testable import Canvia

final class ShapeGeometryTests: XCTestCase {

    private func numbers(_ value: Any?) -> [String: Double]? {
        (value as? [String: NSNumber])?.mapValues(\.doubleValue)
    }

    private func point(_ value: Any?) -> CGPoint? {
        guard let xy = value as? [NSNumber], xy.count == 2 else { return nil }
        return CGPoint(x: xy[0].doubleValue, y: xy[1].doubleValue)
    }

    func testTheSharedPathRows() throws {
        let rows = try XCTUnwrap(SharedFixture.object("shape-geometry")["paths"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let id = try XCTUnwrap(row["shape"] as? String)
            let w = try XCTUnwrap((row["w"] as? NSNumber)?.doubleValue)
            let h = try XCTUnwrap((row["h"] as? NSNumber)?.doubleValue)
            let radius = try XCTUnwrap((row["radius"] as? NSNumber)?.doubleValue)
            XCTAssertEqual(ShapeGeometry.path(id, w: w, h: h, radius: radius, params: numbers(row["params"])),
                           row["path"] as? String, "\(row)")
        }
    }

    func testTheSharedHandleRows() throws {
        let rows = try XCTUnwrap(SharedFixture.object("shape-geometry")["handles"] as? [[String: Any]])
        for row in rows {
            let id = try XCTUnwrap(row["shape"] as? String)
            let got = ShapeGeometry.handles(id, numbers(row["params"]))
            if let want = point(row["at"]) {
                XCTAssertEqual(got.count, 1, "\(row)")
                XCTAssertEqual(Double(got.first?.x ?? -9), Double(want.x), accuracy: 1e-4, "\(row)")
                XCTAssertEqual(Double(got.first?.y ?? -9), Double(want.y), accuracy: 1e-4, "\(row)")
            } else {
                XCTAssertEqual(got, [], "\(row)")
            }
        }
    }

    func testTheSharedDragAndWriteRows() throws {
        let fixture = try SharedFixture.object("shape-geometry")
        let drags = try XCTUnwrap(fixture["dragged"] as? [[String: Any]])
        for row in drags {
            let id = try XCTUnwrap(row["shape"] as? String)
            let to = try XCTUnwrap(point(row["to"]))
            let got = ShapeGeometry.dragged(id, numbers(row["params"]), to: to)
            let want = numbers(row["keeps"])
            XCTAssertEqual(got.map { Set($0.keys) }, want.map { Set($0.keys) }, "\(row)")
            for (key, v) in want ?? [:] { XCTAssertEqual(got?[key] ?? -9, v, accuracy: 1e-4, "\(row)") }
        }
        let writes = try XCTUnwrap(fixture["writes"] as? [[String: Any]])
        for row in writes {
            let id = try XCTUnwrap(row["shape"] as? String)
            XCTAssertEqual(ShapeGeometry.kept(id, numbers(row["set"])), numbers(row["keeps"]), "\(row)")
        }
    }

    func testAtItsOwnLookEveryShapeIsItsStoredPolygon() {
        // Not rounded and every parameter its own, each straight-edged shape
        // has the stored shape's corners, so nothing changes until asked.
        for shape in ContentLibrary.shapes where ShapeGeometry.rounds(shape.id) {
            let built = ShapeGeometry.unitPolygon(shape.id, nil) ?? []
            let stored = SVGPath.path(shape.path)
            var corners: [CGPoint] = []
            stored.applyWithBlock { e in
                if e.pointee.type == .moveToPoint || e.pointee.type == .addLineToPoint {
                    corners.append(e.pointee.points[0])
                }
            }
            for p in built {
                XCTAssertTrue(corners.contains { abs($0.x - p.x) < 0.05 && abs($0.y - p.y) < 0.05 },
                              "\(shape.id) \(p)")
            }
        }
        // Built whatever its rounding, as on the Android twin.
        var star = Element.shape("star-5")
        XCTAssertNotNil(ShapeGeometry.outline(star))
        star.radius = 6
        XCTAssertNotNil(ShapeGeometry.outline(star))
        var square = Element.shape("rect")
        square.radius = 6
        XCTAssertNil(ShapeGeometry.outline(square), "a rectangle rounds as it always has")
        var heart = Element.shape("heart")
        heart.radius = 6
        XCTAssertNil(ShapeGeometry.outline(heart), "a curve takes no rounding")
        XCTAssertFalse(ShapeGeometry.rounds("speech"), "a callout keeps its curves")
        XCTAssertTrue(ShapeGeometry.builds("speech"))
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
        let arrow = ShapeGeometry.dragged("arrow-right", nil, to: CGPoint(x: 0.75, y: 0.3)) ?? [:]
        XCTAssertEqual(arrow["head"] ?? 0, 0.25, accuracy: 1e-9)
        XCTAssertNil(arrow["shaft"], "0.4 is its own")
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
        // Unrounded, a preset draws it; a heart is still a picture.
        XCTAssertEqual(PptxExporter.form(of: Element.shape("triangle")), .geometry)
        XCTAssertEqual(PptxExporter.form(of: Element.shape("heart")), .picture)
    }

    func testBuiltShapesArePresetsWhereOneMatchesElseFreeForm() {
        // The Android twin's PptxWriterTest has the same rows.
        let triangle = Element.shape("triangle", w: 200, h: 100)
        XCTAssertEqual(PptxExporter.presetGeometry(triangle), "<a:prstGeom prst=\"triangle\"><a:avLst/></a:prstGeom>")
        var chevron = Element.shape("chevron", w: 200, h: 100)
        ShapeGeometry.setting("notch", to: 0.25, on: &chevron)
        // The point a quarter of the width, as a share of the shorter side.
        XCTAssertEqual(PptxExporter.presetGeometry(chevron),
                       "<a:prstGeom prst=\"chevron\"><a:avLst><a:gd name=\"adj\" fmla=\"val 50000\"/></a:avLst></a:prstGeom>")
        var rounded = triangle
        rounded.radius = 10
        XCTAssertNil(PptxExporter.presetGeometry(rounded), "rounded, it is its outline")
        XCTAssertNil(PptxExporter.presetGeometry(Element.shape("star-5")))
    }
}
