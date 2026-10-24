// Warped text: the warp's JSON, its preset handles, the Coons patch every
// outline point goes through (map), a handle dragged into a custom warp,
// and a path's points moved by Edit shape. The map rows are shared with
// the Android twin's TextWarpTest (Fixtures/text-warp.json).

import XCTest
@testable import Canvia

final class TextWarpTests: XCTestCase {

    private let box = CGRect(x: 0, y: 0, width: 100, height: 100)

    private func assertPoint(_ p: CGPoint, _ x: Double, _ y: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(p.x), x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(Double(p.y), y, accuracy: 1e-9, file: file, line: line)
    }

    func testTheWarpReadsAndWritesAsBothPhonesDo() throws {
        let preset = try JSONDecoder().decode(TextWarpSpec.self, from: Data(#"{"kind":"bulge","amount":250}"#.utf8))
        XCTAssertEqual(preset, TextWarpSpec(kind: "bulge", amount: 100), "an amount past 100 is held to it")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let grid = [Double](repeating: 0, count: 16)
        let custom = TextWarpSpec(kind: "custom", amount: 40, grid: grid)
        let written = String(decoding: try encoder.encode(custom), as: UTF8.self)
        XCTAssertEqual(written, #"{"amount":40,"grid":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"kind":"custom"}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(TextWarpSpec(kind: "arch", amount: 40, grid: grid)), as: UTF8.self),
                       #"{"amount":40,"kind":"arch"}"#, "a preset writes no grid")
        let short = try JSONDecoder().decode(TextWarpSpec.self, from: Data(#"{"kind":"custom","amount":0,"grid":[1,2]}"#.utf8))
        XCTAssertNil(short.grid, "a grid that is not sixteen numbers is none")
        var el = Element.text("Warp")
        el.warp = TextWarpSpec(kind: "flag", amount: -30)
        let back = try JSONDecoder().decode(Element.self, from: try JSONEncoder().encode(el))
        XCTAssertEqual(back.warp, el.warp)
    }

    /// The shared rows (Fixtures/text-warp.json, the Android twin's byte
    /// for byte): each a warp, a box, a point and where it goes.
    func testMapIsTheSameOnBothPhones() throws {
        let fixture = try SharedFixture.object("text-warp")
        let grid = try XCTUnwrap(fixture["grid"] as? [Double])
        let rows = try XCTUnwrap(fixture["rows"] as? [[Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 20)
        for row in rows {
            let kind = try XCTUnwrap(row.first as? String)
            let n = try row.dropFirst().map { try XCTUnwrap($0 as? Double) }
            let warp = TextWarpSpec(kind: kind, amount: n[0], grid: kind == TextWarp.custom ? grid : nil)
            let box = CGRect(x: n[1], y: n[2], width: n[3], height: n[4])
            let got = TextWarp.map(CGPoint(x: n[5], y: n[6]), box: box, warp: warp)
            XCTAssertEqual(Double(got.x), n[7], accuracy: 1e-6, "\(row)")
            XCTAssertEqual(Double(got.y), n[8], accuracy: 1e-6, "\(row)")
        }
    }

    func testThePresetsMoveTheirHandles() {
        XCTAssertEqual(TextWarp.kinds, ["arch", "bulge", "flag", "squeeze", "rise", "perspective"])
        let squeeze = TextWarp.handles(TextWarpSpec(kind: "squeeze", amount: 100))
        XCTAssertEqual(squeeze.count, 8)
        assertPoint(squeeze[4], 0.5, 0.3)
        assertPoint(squeeze[6], 0.5, 0.7)
        let perspective = TextWarp.handles(TextWarpSpec(kind: "perspective", amount: 100))
        assertPoint(perspective[1], 1, -0.25)
        assertPoint(perspective[2], 1, 1.25)
        let flag = TextWarp.offsets(TextWarpSpec(kind: "flag", amount: -100))
        XCTAssertEqual(flag[9], 0.25, accuracy: 1e-12, "the top's middle down with a negative amount")
        XCTAssertEqual(flag[3], -0.25, accuracy: 1e-12)
    }

    func testADraggedHandleMakesItCustom() {
        let warp = TextWarp.moved(TextWarpSpec(kind: "arch", amount: 100), handle: 0, to: CGPoint(x: 0.1, y: -0.2))
        XCTAssertEqual(warp.kind, "custom")
        let grid = warp.grid ?? []
        XCTAssertEqual(grid.count, 16)
        XCTAssertEqual(grid[0], 0.1, accuracy: 1e-12)
        XCTAssertEqual(grid[1], -0.2, accuracy: 1e-12)
        XCTAssertEqual(grid[9], -0.3, accuracy: 1e-12, "the arch's own offsets kept")
        assertPoint(TextWarp.map(CGPoint(x: 0, y: 0), box: box, warp: warp), 10, -20)
    }

    func testWarpExcludesACurveAPathAndAColumn() {
        var el = Element.text("Hi")
        el.warp = TextWarpSpec(kind: "bulge")
        XCTAssertTrue(TextWarp.isWarped(el))
        XCTAssertTrue(TextOutliner.followsAPath(el), "drawn from its outlines")
        el.curve = 90
        XCTAssertFalse(TextWarp.isWarped(el), "a curve comes first")
        el.curve = nil
        el.vertical = true
        XCTAssertFalse(TextWarp.isWarped(el))
        el.vertical = nil
        el.warp = TextWarpSpec(kind: "twist")
        XCTAssertFalse(TextWarp.isWarped(el), "a kind this build does not know is straight")
    }

    func testAPathsPointsMove() {
        let data = "M0 95Q50 -20 100 95"
        XCTAssertEqual(TextWarp.pathPoints(data), [CGPoint(x: 0, y: 95), CGPoint(x: 50, y: -20), CGPoint(x: 100, y: 95)])
        XCTAssertEqual(TextWarp.movingPathPoint(data, index: 1, to: CGPoint(x: 40, y: 10.5)), "M0 95Q40 10.5 100 95")
        XCTAssertEqual(TextWarp.movingPathPoint("M0 60Q25 10 50 60T100 60", index: 3, to: CGPoint(x: 90, y: 70)),
                       "M0 60Q25 10 50 60T90 70")
        XCTAssertNil(TextWarp.pathPoints("M0 0H100"), "a horizontal line's number is not a point")
    }

    func testTheHullHoldsTheBentBox() {
        let hull = TextWarp.hull(TextWarpSpec(kind: "bulge", amount: 100), w: 100, h: 100)
        XCTAssertEqual(Double(hull.minY), -30, accuracy: 1e-9)
        XCTAssertEqual(Double(hull.maxY), 130, accuracy: 1e-9)
        var el = Element.text("Hi", w: 100)
        el.h = 100
        el.warp = TextWarpSpec(kind: "bulge", amount: 100)
        XCTAssertTrue(Geometry.hits(el, point: CGPoint(x: 50, y: -20)), "a tap on the bulge above the box")
    }
}
