// Words on lines (LineLabels), over the shared rows of
// Fixtures/line-labels.json the Android twin's LineLabelsTest reads: where a
// label sits along a route, the stroke broken round it, a label slid along
// its line, and the `label` key read and written.

import XCTest
import CoreGraphics
@testable import Canvia

final class LineLabelsTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("line-labels") }

    private func route(_ name: Any?, in fixture: [String: Any]) throws -> [CGPoint] {
        let routes = try XCTUnwrap(fixture["routes"] as? [String: Any])
        let points = try XCTUnwrap(routes[try XCTUnwrap(name as? String)] as? [[Double]])
        return points.map { CGPoint(x: $0[0], y: $0[1]) }
    }

    /// The line element of the fixture's `lines` row drawn along `name`.
    private func line(_ name: Any?, in fixture: [String: Any]) throws -> Element {
        let lines = try XCTUnwrap(fixture["lines"] as? [[String: Any]])
        let row = try XCTUnwrap(lines.first { $0["route"] as? String == name as? String })
        return try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(XCTUnwrap(row["line"])))
    }

    private func near(_ found: [CGPoint], _ want: [[Double]], _ label: String) {
        XCTAssertEqual(found.count, want.count, label)
        for (p, q) in zip(found, want) {
            XCTAssertEqual(Double(p.x), q[0], accuracy: 1e-4, label)
            XCTAssertEqual(Double(p.y), q[1], accuracy: 1e-4, label)
        }
    }

    func testTheSharedLinesRunAlongTheirRoutes() throws {
        let rows = try fixture()
        for row in try XCTUnwrap(rows["lines"] as? [[String: Any]]) {
            let want = try route(row["route"], in: rows).map { [Double($0.x), Double($0.y)] }
            near(LineLabels.route(of: try line(row["route"], in: rows)), want, "\(row)")
        }
    }

    func testALabelSitsAtItsShareOfTheRoutesLength() throws {
        let rows = try fixture()
        for row in try XCTUnwrap(rows["points"] as? [[String: Any]]) {
            let points = try route(row["route"], in: rows)
            let at = try XCTUnwrap(row["at"] as? Double)
            let centre = try XCTUnwrap(row["centre"] as? [Double])
            near([LineLabels.pointAt(points, at: at)], [centre], "\(row)")
            XCTAssertEqual(LineLabels.tangentAt(points, at: at), try XCTUnwrap(row["tangent"] as? Double),
                           accuracy: 1e-4, "\(row)")
        }
    }

    func testTheStrokeBreaksRoundTheLabelsBoxGrownByTheGap() throws {
        let rows = try fixture()
        for row in try XCTUnwrap(rows["gaps"] as? [[String: Any]]) {
            let points = try route(row["route"], in: rows)
            let box = try XCTUnwrap(row["rect"] as? [Double])
            let runs = LineLabels.clipGap(points, CGRect(x: box[0], y: box[1], width: box[2], height: box[3]))
            let want = try XCTUnwrap(row["runs"] as? [[[Double]]])
            XCTAssertEqual(runs.count, want.count, "\(row)")
            for (run, expected) in zip(runs, want) { near(run, expected, "\(row)") }
        }
    }

    func testADraggedLabelSlidesToTheNearestPointHeldOnTheMiddle() throws {
        let rows = try fixture()
        for row in try XCTUnwrap(rows["slides"] as? [[String: Any]]) {
            let point = try XCTUnwrap(row["point"] as? [Double])
            let found = LineLabels.slid(try line(row["line"], in: rows), toward: CGPoint(x: point[0], y: point[1]))
            XCTAssertEqual(found, try XCTUnwrap(row["at"] as? Double), accuracy: 1e-4, "\(row)")
        }
    }

    func testTheLabelKeyIsReadLenientlyAndWrittenAsBothPhonesWriteIt() throws {
        for row in try XCTUnwrap(fixture()["labels"] as? [[String: Any]]) {
            let json = try SharedFixture.encoded(XCTUnwrap(row["json"]))
            guard let read = row["read"] as? [String: Any] else {
                XCTAssertThrowsError(try JSONDecoder().decode(LineLabel.self, from: json), "\(row)")
                continue
            }
            let label = try JSONDecoder().decode(LineLabel.self, from: json)
            XCTAssertEqual(label.text, read["text"] as? String)
            XCTAssertEqual(label.at, try XCTUnwrap(read["at"] as? Double), accuracy: 1e-9)
            XCTAssertEqual(label.size, try XCTUnwrap(read["size"] as? Double), accuracy: 1e-9)
            XCTAssertEqual(label.weight, read["weight"] as? Int)
            XCTAssertEqual(label.italic, read["italic"] as? Bool)
            XCTAssertEqual(label.gap, read["gap"] as? Bool)
            XCTAssertEqual(label.font, read["font"] as? String)
            XCTAssertEqual(label.color, read["color"] as? String)
            // Written back: the keys both phones write, and it reads the same.
            let written = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(label)) as? [String: Any])
            let want = try XCTUnwrap(row["write"] as? [String: Any])
            XCTAssertEqual(Set(written.keys), Set(want.keys), "\(row)")
            for (key, value) in want {
                if let text = value as? String {
                    XCTAssertEqual(written[key] as? String, text, "\(row) \(key)")
                } else {
                    let got = try XCTUnwrap(written[key] as? NSNumber, "\(row) \(key)")
                    XCTAssertEqual(got.doubleValue, try XCTUnwrap(value as? NSNumber).doubleValue, accuracy: 1e-9, "\(row) \(key)")
                }
            }
            let again = try JSONDecoder().decode(LineLabel.self, from: JSONEncoder().encode(label))
            XCTAssertEqual(again, label)
        }
        // On a line, under "label"; a line without one has no key, and one
        // without words is none.
        var line = Element.line(w: 200)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(line), as: UTF8.self).contains("\"label\""))
        line.label = LineLabel(text: "Yes")
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(back.label?.text, "Yes")
        let wordless = Data(#"{"type":"line","label":{"at":0.3}}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: wordless).label)
    }

    /// A connector's label stays where it is along it as its ends move, and
    /// a line with words is said as "Line, labelled …".
    func testALabelFollowsItsLineAndIsSpoken() throws {
        var line = LineRoutes.withEnds(Element.line(w: 100), CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 100))
        line.label = LineLabel(text: "**Yes**")
        let before = try XCTUnwrap(LineLabels.rect(of: line))
        XCTAssertEqual(Double(before.midX), 100, accuracy: 0.5)
        XCTAssertEqual(Double(before.midY), 100, accuracy: 0.5)
        let moved = LineRoutes.withEnds(line, CGPoint(x: 0, y: 300), CGPoint(x: 400, y: 300))
        let after = try XCTUnwrap(LineLabels.rect(of: moved))
        XCTAssertEqual(Double(after.midX), 200, accuracy: 0.5)
        XCTAssertEqual(Double(after.midY), 300, accuracy: 0.5)
        // Upright whatever the line's turn.
        XCTAssertEqual(Double(after.width), Double(before.width), accuracy: 0.5)
        XCTAssertEqual(LineLabels.spoken(moved), "Line, labelled Yes")
        var spaced = moved
        spaced.label?.text = "  Yes \n"
        XCTAssertEqual(LineLabels.spoken(spaced), "Line, labelled Yes")
        XCTAssertNil(LineLabels.spoken(Element.line(w: 100)))
        // The gap is the words' box grown by gapPad; none with gap off.
        XCTAssertEqual(LineLabels.gapRect(of: moved), after.insetBy(dx: -LineLabels.gapPad, dy: -LineLabels.gapPad))
        var plain = moved
        plain.label?.gap = false
        XCTAssertNil(LineLabels.gapRect(of: plain))
        // A line with no colour of its own: a new line's.
        plain.color = nil
        XCTAssertEqual(LineLabels.textElement(for: plain)?.color, "#1f2430")
        // A blank label shows nothing.
        plain.label?.text = "  "
        XCTAssertNil(LineLabels.rect(of: plain))
    }

    /// Find and spelling read a line's words; replacing them changes the
    /// label, the line kept as it was.
    func testFindAndReplaceReachALinesLabel() throws {
        var line = LineRoutes.withEnds(Element.line(w: 100), CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 100))
        line.label = LineLabel(text: "Yes please")
        var design = Design(title: "Flow", width: 400, height: 400)
        design.pages = [Page(id: "p1", elements: [line])]
        let found = DesignStore.matches(in: design, for: "yes", caseSensitive: false, wholeWord: false)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.elementId, line.id)
        // The match is marked in the words' own upright box.
        XCTAssertEqual(FindReplace.letterRects(of: NSRange(location: 0, length: 3), in: line).count, 1)
        let replaced = try XCTUnwrap(DesignStore.replacingOne(design, try XCTUnwrap(found.first), with: "No"))
        let after = try XCTUnwrap(replaced.pages[0].elements.first)
        XCTAssertEqual(after.label?.text, "No please")
        XCTAssertEqual(after.h, line.h)
        XCTAssertEqual(Proofreader.checkables(in: design).filter { $0.elementId == line.id }.count, 1)
    }

    /// The SVG breaks the stroke with a mask and writes the words upright
    /// over it; the PowerPoint groups the line with a text box.
    @MainActor
    func testExportsCarryTheLabel() throws {
        var line = LineRoutes.withEnds(Element.line(w: 100), CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 100))
        line.label = LineLabel(text: "Yes")
        var design = Design(title: "Flow", width: 400, height: 400)
        design.pages = [Page(id: "p1", elements: [line])]
        let svg = SVGExporter.svg(design: design, page: design.pages[0])
        XCTAssertTrue(svg.contains("<mask id=\"linegap"), svg)
        XCTAssertTrue(svg.contains("mask=\"url(#linegap"), svg)
        let slide = try XCTUnwrap(PptxExporter.deck(design: design, indices: [0]).first)
        XCTAssertTrue(slide.xml.contains("<p:grpSp>"), slide.xml)
        XCTAssertTrue(slide.xml.contains("<a:t>Yes</a:t>"), slide.xml)
    }
}
