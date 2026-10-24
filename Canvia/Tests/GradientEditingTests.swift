// Your own gradients, row for row with the Android twin's
// GradientEditingTest: stops added, moved, recoloured and taken away, the
// angle snapped, the recents, a brand kit's gradients, and a 4-stop
// gradient through the file, SVG and PowerPoint — the shared
// Fixtures/text-gradient.json among them.

import XCTest
@testable import Canvia

final class GradientEditingTests: XCTestCase {

    private func paint(_ stops: [(Double, String)], angle: Double = 90) -> Paint {
        Paint(kind: "gradient", color: nil, angle: angle, stops: stops.map { GradientStop(offset: $0.0, color: $0.1) })
    }

    private func rows(_ p: Paint) -> [String] {
        (p.stops ?? []).map { "\($0.offset) \($0.color)" }
    }

    func testAStopIsAddedInTheWidestGapHalfwayInColourUpToFive() {
        var p = paint([(0, "#ff0000"), (1, "#0000ff")])
        p = GradientEditing.adding(p)
        XCTAssertEqual(rows(p), ["0.0 #ff0000", "0.5 #800080", "1.0 #0000ff"])
        // The widest gap next: 0.5 to 1 ties 0 to 0.5, so the first.
        p = GradientEditing.adding(p)
        XCTAssertEqual(rows(p), ["0.0 #ff0000", "0.25 #c00040", "0.5 #800080", "1.0 #0000ff"])
        p = GradientEditing.adding(p)
        XCTAssertEqual(rows(p).count, 5)
        XCTAssertEqual(rows(p)[3], "0.75 #4000c0")
        XCTAssertFalse(GradientEditing.canAdd(p))
        XCTAssertEqual(GradientEditing.adding(p), p, "never more than five")
    }

    func testAStopIsTakenAwayDownToTwo() {
        let three = paint([(0, "#000000"), (0.5, "#888888"), (1, "#ffffff")])
        XCTAssertEqual(rows(GradientEditing.removing(three, at: 1)), ["0.0 #000000", "1.0 #ffffff"])
        let two = GradientEditing.removing(three, at: 0)
        XCTAssertEqual(rows(two), ["0.5 #888888", "1.0 #ffffff"])
        XCTAssertFalse(GradientEditing.canRemove(two))
        XCTAssertEqual(GradientEditing.removing(two, at: 0), two, "never fewer than two")
    }

    func testAStopMovesBetweenItsNeighboursAtAHundredth() {
        let p = paint([(0, "#000000"), (0.4, "#888888"), (0.8, "#cccccc"), (1, "#ffffff")])
        XCTAssertEqual(GradientEditing.moved(p, at: 1, to: 0.333).stops?[1].offset, 0.33)
        XCTAssertEqual(GradientEditing.moved(p, at: 1, to: 0.95).stops?[1].offset, 0.8, "held at the next stop")
        XCTAssertEqual(GradientEditing.moved(p, at: 2, to: 0.1).stops?[2].offset, 0.4, "held at the one before")
        XCTAssertEqual(GradientEditing.moved(p, at: 0, to: -1).stops?[0].offset, 0)
        XCTAssertEqual(GradientEditing.moved(p, at: 3, to: 7).stops?[3].offset, 1)
        XCTAssertEqual(GradientEditing.recoloured(p, at: 2, "#00ff00").stops?[2].color, "#00ff00")
    }

    func testTheAngleIsWholeDegreesSnappingTo45() {
        XCTAssertEqual([0, 3.6, 4, 4.6, 41, 44.5, 50, 359, 360, 405, -45, 200.4].map(GradientEditing.snapped),
                       [0, 0, 0, 5, 45, 45, 50, 0, 0, 45, 315, 200])
        XCTAssertEqual(GradientEditing.angled(paint([(0, "#000"), (1, "#fff")]), 137).angle, 135)
        XCTAssertEqual(GradientEditing.angles, [0, 45, 90, 135, 180, 225, 270, 315])
    }

    func testShapesAreWrittenAsPresetsStoreThem() {
        let p = paint([(0, "#000000"), (1, "#ffffff")])
        XCTAssertNil(GradientEditing.shaped(p, "linear").gradientKind)
        XCTAssertEqual(GradientEditing.shaped(p, "radial").gradientKind, "radial")
        XCTAssertEqual(GradientEditing.shaped(p, "angular").gradientKind, "angular")
        XCTAssertNil(GradientEditing.shaped(p, "diamond").gradientKind)
    }

    func testTheEditorStartsFromTheGradientThereOrTheColour() {
        let unordered = paint([(1, "#ffffff"), (0, "#000000"), (0.5, "#808080")])
        XCTAssertEqual(rows(GradientEditing.editable(unordered, colour: nil)), ["0.0 #000000", "0.5 #808080", "1.0 #ffffff"])
        let fresh = GradientEditing.editable(.solid("#ff0000"), colour: "#FF0000")
        XCTAssertEqual(fresh.kind, "gradient")
        XCTAssertEqual(fresh.angle, 90)
        XCTAssertEqual(rows(fresh), ["0.0 #ff0000", "1.0 #ffffff"])
        XCTAssertEqual(rows(GradientEditing.editable(nil, colour: nil)), ["0.0 #1f2430", "1.0 #ffffff"])
        XCTAssertEqual(GradientEditing.mix("#ff0000", "nope"), "#ff0000")
        XCTAssertEqual(GradientEditing.mix("#000", "#fff"), "#808080")
    }

    func testRecentGradientsAreTheLastEightNewestFirst() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "GradientEditingTests"))
        defaults.removePersistentDomain(forName: "GradientEditingTests")
        for i in 0..<10 {
            GradientRecents.record(paint([(0, "#000000"), (1, String(format: "#0000%02x", i))]), defaults)
        }
        let first = paint([(0, "#000000"), (1, "#000003")])
        GradientRecents.record(first, defaults)
        let all = GradientRecents.all(defaults)
        XCTAssertEqual(all.count, 8)
        XCTAssertEqual(all.first, first, "recorded again, it moves to the front, once")
        XCTAssertEqual(all.filter { $0 == first }.count, 1)
        XCTAssertEqual(all[1].stops?[1].color, "#000009")
        GradientRecents.record(.solid("#ff0000"), defaults)
        XCTAssertEqual(GradientRecents.all(defaults).count, 8, "a plain colour is no gradient")
        defaults.removePersistentDomain(forName: "GradientEditingTests")
    }

    func testABrandKitKeepsGradients() throws {
        var kit = BrandKit()
        let p = paint([(0, "#000000"), (0.3, "#ff0000"), (0.6, "#00ff00"), (1, "#ffffff")], angle: 45)
        XCTAssertTrue(kit.addGradient(p))
        XCTAssertFalse(kit.addGradient(p), "once")
        XCTAssertFalse(kit.addGradient(.solid("#ff0000")))
        XCTAssertFalse(kit.isEmpty)
        let data = try JSONEncoder().encode(kit)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["gradients"] as? [Any])?.count, 1)
        XCTAssertEqual(try JSONDecoder().decode(BrandKit.self, from: data).gradients, [p])
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(BrandKit())) as? [String: Any])
        XCTAssertNil(plain["gradients"], "a kit without gradients is written as before")
    }

    @MainActor
    func testAFourStopGradientRoundTripsAndExportsEveryStop() throws {
        var shape = Element.shape("rect", w: 200, h: 100)
        shape.fill = paint([(0, "#000000"), (0.25, "#ff0000"), (0.75, "#00ff00"), (1, "#0000ff")], angle: 45)
        var d = Design(title: "Four stops", width: 800, height: 600)
        d.pages = [Page(elements: [shape])]
        let read = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(read.pages[0].elements[0].fill, shape.fill)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(shape)) as? [String: Any])
        let fill = try XCTUnwrap(json["fill"] as? [String: Any])
        XCTAssertEqual(fill["kind"] as? String, "gradient")
        XCTAssertEqual((fill["stops"] as? [[String: Any]])?.map { $0["offset"] as? Double }, [0, 0.25, 0.75, 1])

        let svg = SVGExporter.svg(design: read, page: read.pages[0])
        XCTAssertEqual(svg.components(separatedBy: "<stop offset=").count - 1, 4, svg)
        XCTAssertTrue(svg.contains("<stop offset=\"0.75\" stop-color=\"#00ff00\"/>"), svg)
        let slide = PptxExporter.slide(design: read, page: read.pages[0], number: 1, previous: nil, firstImage: 1).xml
        XCTAssertEqual(slide.components(separatedBy: "<a:gs pos=").count - 1, 4, slide)
        XCTAssertTrue(slide.contains("<a:gs pos=\"75000\"><a:srgbClr val=\"00FF00\"/></a:gs>"), slide)
    }

    @MainActor
    func testTheSharedFourStopTextGradient() throws {
        let fixture = try SharedFixture.object("text-gradient")
        let el = try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(try XCTUnwrap(fixture["element"])))
        let fill = try XCTUnwrap(el.textFill)
        XCTAssertEqual(fill.stops?.count, fixture["stops"] as? Int)
        XCTAssertEqual(fill.angle, fixture["angle"] as? Double)
        XCTAssertEqual(fill.stops?.map(\.offset), [0, 0.35, 0.7, 1])
        XCTAssertTrue(TextEffect.from(el.effect).takesGradient)

        var d = Design(title: "Sunset", width: 800, height: 600)
        d.pages = [Page(elements: [el])]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("<linearGradient id=\"textgrad"), svg)
        XCTAssertEqual(svg.components(separatedBy: "<stop offset=").count - 1, 4, svg)
        let slide = PptxExporter.slide(design: d, page: d.pages[0], number: 1, previous: nil, firstImage: 1).xml
        XCTAssertEqual(slide.components(separatedBy: "<a:gs pos=").count - 1, 4, slide)
        let ang = try XCTUnwrap(fixture["pptxLinAng"] as? Int)
        XCTAssertTrue(slide.contains("<a:lin ang=\"\(ang)\"/>"), slide)
    }
}
