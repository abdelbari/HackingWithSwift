// Round 34's stylus drawing: a stroke's width at each sample from a
// Pencil's pressure or a finger's speed, kept as its `widths` and drawn as
// a filled outline. The outline and factor rows are the shared fixture
// stroke-outline.json, read by the Android twin's FreehandTest too.

import XCTest
@testable import Canvia

final class StylusTests: XCTestCase {

    func testTheSharedOutlineRows() throws {
        let rows = try XCTUnwrap(SharedFixture.object("stroke-outline")["outline"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let points = try XCTUnwrap(row["points"] as? [[NSNumber]]).map {
                CGPoint(x: $0[0].doubleValue, y: $0[1].doubleValue)
            }
            let radii = try XCTUnwrap(row["radii"] as? [NSNumber]).map(\.doubleValue)
            XCTAssertEqual(Freehand.outlinePath(points, radii: radii), row["d"] as? String, "\(row)")
        }
    }

    func testTheSharedFactorRows() throws {
        let fixture = try SharedFixture.object("stroke-outline")
        for row in try XCTUnwrap(fixture["pressure"] as? [[String: NSNumber]]) {
            XCTAssertEqual(Freehand.pressureFactor(row["in"]!.doubleValue), row["factor"]!.doubleValue, "\(row)")
        }
        for row in try XCTUnwrap(fixture["speed"] as? [[String: NSNumber]]) {
            XCTAssertEqual(Freehand.speedFactor(row["in"]!.doubleValue), row["factor"]!.doubleValue, "\(row)")
        }
    }

    func testAPressureStrokeKeepsAWidthForEverySampleItsCurvePasses() throws {
        var tool = Freehand.Tool()
        tool.width = 10
        let points = (0..<6).map { CGPoint(x: 100 + Double($0) * 20, y: 100 + Double($0 % 2) * 10) }
        let widths = [0.4, 0.6, 0.8, 1, 0.7, 0.5]
        // Pressure off: one width, as before.
        XCTAssertNil(Freehand.element(points: points, widths: widths, tool: tool)?.widths)
        tool.pressurePens = [.pen]
        let el = try XCTUnwrap(Freehand.element(points: points, widths: widths, tool: tool))
        XCTAssertEqual(el.widths, widths)
        XCTAssertEqual(Freehand.samples(try XCTUnwrap(el.pathData)).count, widths.count)
        XCTAssertNotNil(Freehand.outline(el))
        // The eraser has no ink, and no pressure.
        tool.pen = .eraser
        XCTAssertFalse(tool.pressure)
        // A width of the wrong count is drawn at one width.
        var odd = el
        odd.widths = [1, 1]
        XCTAssertNil(Freehand.outline(odd))
    }

    func testTheWidthsTravelInTheFileAndAnOlderBuildKeepsThePath() throws {
        var tool = Freehand.Tool()
        tool.pressurePens = [.marker]
        tool.pen = .marker
        let el = try XCTUnwrap(Freehand.element(points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0), CGPoint(x: 80, y: 30)],
                                                widths: [0.35, 1, 0.5], tool: tool))
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(el), encoding: .utf8))
        XCTAssertTrue(json.contains("\"widths\":[0.35,1,0.5]"), json)
        XCTAssertTrue(json.contains("\"pen\":\"marker\""), json)
        XCTAssertTrue(json.contains("\"pathData\""), json)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: Data(json.utf8)).widths, [0.35, 1, 0.5])
        let plain = try XCTUnwrap(Freehand.element(points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)], tool: Freehand.Tool()))
        XCTAssertFalse(try XCTUnwrap(String(data: JSONEncoder().encode(plain), encoding: .utf8)).contains("widths"))
    }

    @MainActor
    func testTheSVGDrawsTheOutline() throws {
        var tool = Freehand.Tool()
        tool.pressurePens = [.pen]
        let el = try XCTUnwrap(Freehand.element(points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 10), CGPoint(x: 90, y: 40)],
                                                widths: [1, 0.5, 0.35], tool: tool))
        var d = Design(title: "ink", width: 200, height: 200)
        d.pages[0].elements = [el]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("d=\"\(try XCTUnwrap(Freehand.outline(el)))\""), svg)
    }
}
