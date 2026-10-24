// A line's eleven end styles and their size, row for row with the Android
// twin's LineEndsTest: the golden head geometry both phones read from
// Fixtures/line-ends.json, capScale in the file, and how the ends export.

import XCTest
@testable import Canvia

final class LineEndsTests: XCTestCase {

    private func near(_ e: [Double], _ a: CGPoint, _ label: String) {
        XCTAssertEqual(Double(a.x), e[0], accuracy: 1e-4, label)
        XCTAssertEqual(Double(a.y), e[1], accuracy: 1e-4, label)
    }

    func testTheSharedHeadGeometry() throws {
        let fixture = try SharedFixture.object("line-ends")
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 16)
        for row in cases {
            let cap = try XCTUnwrap(row["cap"] as? String)
            let t = try XCTUnwrap(row["thickness"] as? Double)
            let scale = try XCTUnwrap(row["capScale"] as? Double)
            let tip = try XCTUnwrap(row["tip"] as? [Double])
            let degrees = try XCTUnwrap(row["angle"] as? Double)
            let kind = LineEnds.kind(cap)
            let label = "\(cap) \(t) \(scale) \(degrees)"
            XCTAssertEqual(kind.rawValue, cap)
            XCTAssertEqual(LineEnds.size(thickness: t, scale: scale), try XCTUnwrap(row["size"] as? Double), accuracy: 1e-9, label)
            XCTAssertEqual(LineEnds.back(kind, thickness: t, scale: scale), try XCTUnwrap(row["back"] as? Double), accuracy: 1e-9, label)
            let head = LineEnds.head(kind, tip: CGPoint(x: tip[0], y: tip[1]), angle: degrees * .pi / 180, thickness: t, scale: scale)
            guard let head else {
                XCTAssertEqual(kind, LineEnds.Kind.none, label)
                continue
            }
            XCTAssertEqual(head.stroked, row["stroked"] as? Bool, label)
            XCTAssertEqual(head.width, t)
            switch head.outline {
            case .polygon(let points):
                let expected = try XCTUnwrap(row["polygon"] as? [[Double]], label)
                XCTAssertEqual(points.count, expected.count, label)
                for (e, a) in zip(expected, points) { near(e, a, label) }
            case .polyline(let points):
                let expected = try XCTUnwrap(row["polyline"] as? [[Double]], label)
                XCTAssertEqual(points.count, expected.count, label)
                for (e, a) in zip(expected, points) { near(e, a, label) }
            case .circle(let center, let radius):
                let expected = try XCTUnwrap(row["circle"] as? [Double], label)
                near(expected, center, label)
                XCTAssertEqual(radius, expected[2], accuracy: 1e-4, label)
            }
        }
    }

    func testCapScaleIsHeldToHalfToThreeAndWrittenOnlyWhenNotOne() throws {
        XCTAssertEqual(LineEnds.scale(nil), 1)
        XCTAssertEqual(LineEnds.scale(0.1), 0.5)
        XCTAssertEqual(LineEnds.scale(9), 3)
        XCTAssertEqual(LineEnds.scale(.nan), 1)
        XCTAssertNil(LineEnds.written(1))
        XCTAssertEqual(LineEnds.written(2), 2)

        var line = Element.line()
        line.startCap = "squareOutline"
        line.endCap = "diamond"
        line.capScale = 2
        let data = try JSONEncoder().encode(line)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["capScale"] as? Double, 2)
        XCTAssertEqual(json["startCap"] as? String, "squareOutline")
        let read = try JSONDecoder().decode(Element.self, from: data)
        XCTAssertEqual(read.capScale, 2)
        XCTAssertEqual(read.endCap, "diamond")
        // Out of range reads held; 1 reads as none written.
        var odd = json
        odd["capScale"] = 7
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(odd)).capScale, 3)
        odd["capScale"] = 1
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(odd)).capScale)
        line.capScale = nil
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(line)) as? [String: Any])
        XCTAssertNil(plain["capScale"])
    }

    func testHeadsFollowTheEndTangentOnEveryRoute() throws {
        // A curve from (0, 0) to (100, 0) bowing down: its end head points
        // up and to the right, along the last tangent, and its stroke stops
        // short of a filled head by half the head.
        let flat = Element.line(w: 100)
        var curve = LineRoutes.withEnds(LineRoutes.withType(flat, .curve), CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0))
        curve.endCap = "triangle"
        let route = LineRoutes.route(curve)
        let heads = LineEnds.heads(curve)
        XCTAssertEqual(heads.count, 1, "a start of none has no head")
        let head = try XCTUnwrap(heads.first)
        guard case .polygon(let points) = head.outline else { return XCTFail("a triangle is a polygon") }
        XCTAssertEqual(points[0], route.end)
        XCTAssertEqual(route.endAngle, -.pi / 4, accuracy: 1e-9)
        XCTAssertEqual(LineRoutes.strokeBack(curve, cap: curve.endCap), 6)
        // An elbow's start head points back along its first segment.
        var elbow = LineRoutes.withEnds(LineRoutes.withType(flat, .elbow), CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50))
        elbow.startCap = "bar"
        let bar = try XCTUnwrap(LineEnds.heads(elbow).first)
        guard case .polyline(let across) = bar.outline else { return XCTFail("a bar is a polyline") }
        XCTAssertEqual(Double(across[0].x), Double(across[1].x), accuracy: 1e-9, "a bar stands across a level first segment")
        // An outline stops the stroke at its back edge, so no line shows inside.
        XCTAssertEqual(LineRoutes.strokeBack(Element.line(), cap: "circle"), 12)
        var big = Element.line()
        big.capScale = 2
        XCTAssertEqual(LineRoutes.strokeBack(big, cap: "circle"), 24)
        XCTAssertEqual(LineRoutes.strokeBack(big, cap: "unknown"), 0)
    }

    @MainActor
    func testEndsExportToSVGAndPowerPoint() {
        var line = Element.line(w: 300)
        line.x = 10; line.y = 20
        line.startCap = "squareOutline"
        line.endCap = "diamond"
        line.capScale = 2
        var d = Design(title: "Ends", width: 800, height: 600)
        d.pages = [Page(elements: [line])]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        // Heads 24 long: the stroke from the square's back edge to the
        // diamond's middle.
        XCTAssertTrue(svg.contains("<line x1=\"34\" y1=\"24\" x2=\"298\" y2=\"24\""), svg)
        XCTAssertTrue(svg.contains("<path d=\"M10 36L10 12L34 12L34 36Z\" fill=\"none\" stroke=\"#1f2430\" stroke-width=\"4\" "
                                   + "stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"), svg)
        XCTAssertTrue(svg.contains("<path d=\"M310 24L298 36L286 24L298 12Z\" fill=\"#1f2430\"/>"), svg)

        let slide = PptxExporter.slide(design: d, page: d.pages[0], number: 1, previous: nil, firstImage: 1).xml
        XCTAssertTrue(slide.contains("<a:headEnd type=\"diamond\" w=\"lg\" len=\"lg\"/><a:tailEnd type=\"diamond\" w=\"lg\" len=\"lg\"/>"), slide)
        XCTAssertEqual(LineEnds.Kind.allCases.map { LineEnds.pptxType($0) ?? "-" },
                       ["-", "arrow", "triangle", "triangle", "oval", "oval", "diamond", "diamond", "diamond", "diamond", "-"])
        XCTAssertEqual([0.5, 0.74, 0.75, 1, 1.49, 1.5, 3].map { LineEnds.pptxSize($0) ?? "-" },
                       ["sm", "sm", "med", "-", "med", "lg", "lg"])
    }
}
