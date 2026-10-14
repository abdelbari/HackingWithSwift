// Shape assist: sample strokes read as the shape they were trying to be,
// in rows written for both phones alike; the elements each becomes; the
// rest that triggers it; and the marker pen.

import XCTest
import CoreGraphics
@testable import Canvia

final class ShapeAssistTests: XCTestCase {

    // MARK: the sample strokes, as both phones make them

    /// `n` evenly spaced points from `a` towards `b`, `b` left out.
    private func segment(_ a: CGPoint, _ b: CGPoint, _ n: Int = 20) -> [CGPoint] {
        (0..<n).map { i in
            let t = Double(i) / Double(n)
            return CGPoint(x: Double(a.x) + Double(b.x - a.x) * t, y: Double(a.y) + Double(b.y - a.y) * t)
        }
    }

    /// A stroke through `corners`, 20 points a side, round to the first
    /// again when `closed`, ending on its last corner.
    private func polyline(_ corners: [(Double, Double)], closed: Bool = false) -> [CGPoint] {
        var points = corners.map { CGPoint(x: $0.0, y: $0.1) }
        if closed, let first = points.first { points.append(first) }
        var out: [CGPoint] = []
        for i in 0..<(points.count - 1) { out += segment(points[i], points[i + 1]) }
        if let last = points.last { out.append(last) }
        return out
    }

    /// A hand's wobble: each point nudged by `amp` × sin(1.7 i) across and
    /// cos(2.3 i) down.
    private func wobbled(_ points: [CGPoint], _ amp: Double) -> [CGPoint] {
        points.enumerated().map { i, p in
            CGPoint(x: Double(p.x) + amp * sin(Double(i) * 1.7), y: Double(p.y) + amp * cos(Double(i) * 2.3))
        }
    }

    /// `n` + 1 points round an ellipse about (`cx`, `cy`), `steps` to a turn.
    private func oval(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, steps: Int, n: Int) -> [CGPoint] {
        (0...n).map { t in
            let a = Double(t) * 2 * .pi / Double(steps)
            return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
        }
    }

    private func kind(_ points: [CGPoint]) -> ShapeAssist.Kind? {
        ShapeAssist.classify(points)?.kind
    }

    func testTheSharedStrokesReadAsTheirShapes() {
        var line = segment(CGPoint(x: 20, y: 40), CGPoint(x: 220, y: 90), 40)
        line.append(CGPoint(x: 220, y: 90))
        let wavy = (0...40).map { i in CGPoint(x: 20 + Double(i) * 5, y: 100 + 12 * sin(Double(i) / 3)) }
        let scribble = (0..<80).map { t -> CGPoint in
            let a = Double(t)
            return CGPoint(x: 100 + 50 * cos(a / 5) * sin(a / 3), y: 100 + 50 * sin(a / 4))
        }
        let rows: [(String, [CGPoint], ShapeAssist.Kind?)] = [
            ("line", wobbled(line, 1.5), .line),
            ("wavy", wavy, nil),
            ("circle", oval(150, 150, 60, 60, steps: 48, n: 48), .ellipse),
            ("ellipse", wobbled(oval(200, 120, 90, 40, steps: 60, n: 57), 1.5), .ellipse),
            ("rectangle", wobbled(polyline([(40, 40), (240, 40), (240, 160), (40, 160)], closed: true), 1), .rectangle),
            ("rectangle begun mid-side", polyline([(140, 40), (240, 40), (240, 160), (40, 160), (40, 40), (138, 40)]),
             .rectangle),
            ("tilted rectangle", polyline([(100, 20), (200, 80), (150, 160), (50, 100)], closed: true), .rectangle),
            ("triangle", wobbled(polyline([(150, 30), (250, 200), (50, 200)], closed: true), 1), .triangle),
            ("arrow", polyline([(20, 200), (220, 100), (165, 97), (190, 146)]), .arrow),
            ("arrow back through its tip", polyline([(20, 100), (220, 100), (190, 80), (220, 100), (190, 120)]), .arrow),
            ("arrow along", polyline([(40, 60), (200, 60), (170, 40), (170, 80)]), .arrow),
            ("V", polyline([(20, 20), (100, 150), (180, 20)]), nil),
            ("dot", [CGPoint(x: 10, y: 10), CGPoint(x: 11, y: 10), CGPoint(x: 12, y: 11)], nil),
            ("scribble", scribble, nil),
        ]
        for (name, points, expected) in rows {
            XCTAssertEqual(kind(points), expected, name)
        }
    }

    func testEachShapeIsPlacedWhereItWasDrawn() throws {
        let rect = try XCTUnwrap(ShapeAssist.classify(
            polyline([(140, 40), (240, 40), (240, 160), (40, 160), (40, 40), (138, 40)])))
        XCTAssertEqual(rect.frame, CGRect(x: 40, y: 40, width: 200, height: 120))
        XCTAssertEqual(rect.rotation, 0)

        let tilted = try XCTUnwrap(ShapeAssist.classify(
            polyline([(100, 20), (200, 80), (150, 160), (50, 100)], closed: true)))
        XCTAssertEqual(tilted.rotation, 30.96, accuracy: 1e-9, "turned as its first side runs")
        XCTAssertEqual(Double(tilted.frame.midX), 125, accuracy: 1e-9)
        XCTAssertEqual(Double(tilted.frame.midY), 90, accuracy: 1e-9)
        XCTAssertEqual(Double(tilted.frame.width), 118.33, accuracy: 0.01)
        XCTAssertEqual(Double(tilted.frame.height), 94.32, accuracy: 0.01)

        let circle = try XCTUnwrap(ShapeAssist.classify(oval(150, 150, 60, 60, steps: 48, n: 48)))
        XCTAssertEqual(Double(circle.frame.minX), 90, accuracy: 1e-9)
        XCTAssertEqual(Double(circle.frame.width), 120, accuracy: 1e-9)

        let arrow = try XCTUnwrap(ShapeAssist.classify(polyline([(40, 60), (200, 60), (170, 40), (170, 80)])))
        XCTAssertEqual(arrow.start, CGPoint(x: 40, y: 60))
        XCTAssertEqual(arrow.end, CGPoint(x: 200, y: 60))
    }

    func testTheElementsAreTheAppsOwnLineAndShapes() throws {
        let tool = Freehand.Tool(color: "#ef4444", width: 6, pen: .pen, transparency: 30)
        let arrowSnap = ShapeAssist.Snap(kind: .arrow, start: CGPoint(x: 40, y: 60), end: CGPoint(x: 200, y: 60))
        let arrow = try XCTUnwrap(ShapeAssist.element(arrowSnap, tool: tool))
        XCTAssertEqual(arrow.type, .line)
        XCTAssertEqual(arrow.endCap, "arrow")
        XCTAssertEqual(arrow.color, "#ef4444")
        XCTAssertEqual(arrow.thickness, 6)
        XCTAssertEqual(arrow.w, 160, accuracy: 1e-9)
        XCTAssertEqual(arrow.rotation, 0, accuracy: 1e-9)
        XCTAssertEqual(arrow.opacity, 0.7, accuracy: 1e-9)
        let ends = LineRoutes.ends(of: arrow)
        XCTAssertEqual(Double(ends.start.x), 40, accuracy: 1e-9)
        XCTAssertEqual(Double(ends.end.x), 200, accuracy: 1e-9)

        let rectSnap = ShapeAssist.Snap(kind: .rectangle, frame: CGRect(x: 10, y: 20, width: 100, height: 50), rotation: 12)
        let rect = try XCTUnwrap(ShapeAssist.element(rectSnap, tool: Freehand.Tool(color: "#1f2430", width: 4, pen: .marker)))
        XCTAssertEqual(rect.type, .shape)
        XCTAssertEqual(rect.shapeId, "rect")
        XCTAssertEqual(rect.fill?.kind, "none")
        XCTAssertEqual(rect.stroke, "#1f2430")
        XCTAssertEqual(rect.strokeWidth ?? 0, 6.4, accuracy: 1e-9, "as wide as the marker draws")
        XCTAssertEqual(rect.rotation, 12)
        XCTAssertEqual([rect.x, rect.y, rect.w, rect.h], [10, 20, 100, 50])
        XCTAssertNil(rect.pen, "a shape is no stroke")

        let ellipse = try XCTUnwrap(ShapeAssist.element(ShapeAssist.Snap(kind: .ellipse, frame: CGRect(x: 0, y: 0, width: 80, height: 40),
                                                                         rotation: 30), tool: tool))
        XCTAssertEqual(ellipse.shapeId, "circle")
        XCTAssertEqual(ellipse.rotation, 0, "only a rectangle is turned")
        let triangle = try XCTUnwrap(ShapeAssist.element(ShapeAssist.Snap(kind: .triangle, frame: CGRect(x: 0, y: 0, width: 80, height: 40)),
                                                         tool: Freehand.Tool(pen: .highlighter)))
        XCTAssertEqual(triangle.shapeId, "triangle")
        XCTAssertEqual(triangle.blendMode, "multiply")
        XCTAssertNil(ShapeAssist.element(arrowSnap, tool: Freehand.Tool(pen: .eraser)))
    }

    func testTheFingerRestsWithinSixPointsOnTheScreen() {
        XCTAssertEqual(ShapeAssist.holdSeconds, 0.5)
        let rest = CGPoint(x: 100, y: 100)
        XCTAssertFalse(ShapeAssist.movedOn(from: rest, to: CGPoint(x: 105, y: 100), zoom: 1))
        XCTAssertTrue(ShapeAssist.movedOn(from: rest, to: CGPoint(x: 106, y: 100), zoom: 1))
        // At half the zoom six points on the screen are twelve on the page.
        XCTAssertFalse(ShapeAssist.movedOn(from: rest, to: CGPoint(x: 111, y: 100), zoom: 0.5))
        XCTAssertTrue(ShapeAssist.movedOn(from: rest, to: CGPoint(x: 100, y: 112), zoom: 0.5))
        XCTAssertEqual(ShapeAssist.key, "drawShapeAssist")
    }

    @MainActor
    func testASnappedStrokeIsOneStepAndPartOfTheDrawing() {
        let store = DesignStore(design: Design(title: "d", width: 400, height: 300))
        store.toggleDrawing()
        store.finishStroke([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 40), CGPoint(x: 90, y: 10)])
        store.finishSnappedStroke(ShapeAssist.Snap(kind: .ellipse, frame: CGRect(x: 100, y: 100, width: 80, height: 60)))
        XCTAssertEqual(store.page.elements.last?.shapeId, "circle")
        store.drawing = nil
        XCTAssertEqual(store.page.elements.count, 2)
        XCTAssertEqual(store.page.elements[0].group, store.page.elements[1].group)
        store.undo()
        XCTAssertEqual(store.page.elements.count, 1, "one Undo takes the shape alone")
    }

    // MARK: the marker

    func testAMarkerStrokeIsWrittenAsOneAndOthersAreNot() throws {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40), CGPoint(x: 90, y: 20)]
        let marker = try XCTUnwrap(Freehand.element(points: points, tool: Freehand.Tool(width: 10, pen: .marker)))
        let ink = try XCTUnwrap(Freehand.element(points: points, tool: Freehand.Tool(width: 10, pen: .pen)))
        XCTAssertEqual(marker.pen, "marker")
        XCTAssertNil(ink.pen)
        let data = try JSONEncoder().encode(marker)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(written["pen"] as? String, "marker")
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: data), marker)
    }

    func testTheMarkerIsOpaqueAndWiderWithAnEdgeFromItsOwnSeed() throws {
        let tool = Freehand.Tool(color: "#3b82f6", width: 10, pen: .marker)
        XCTAssertEqual(Freehand.drawnWidth(tool), 16, accuracy: 1e-9)
        XCTAssertEqual(Freehand.drawnColor(tool), "#3b82f6", "opaque, as ink")
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40), CGPoint(x: 90, y: 20), CGPoint(x: 120, y: 60)]
        let stroke = try XCTUnwrap(Freehand.element(points: points, tool: tool))
        XCTAssertTrue(Freehand.isMarker(stroke))
        XCTAssertEqual(stroke.blendMode, nil)
        XCTAssertEqual(stroke.opacity, 1)

        // The seed is the path's FNV-1a hash, so the edge is the stroke's own.
        XCTAssertEqual(Freehand.markerSeed(""), 2_166_136_261 & 0x7fff_ffff)
        XCTAssertEqual(Freehand.markerSeed("a"), 0xe40c292c & 0x7fff_ffff)
        let alphas = Freehand.markerAlphas(count: 5, seed: 42)
        XCTAssertEqual(alphas, Freehand.markerAlphas(count: 5, seed: 42))
        XCTAssertTrue(alphas.allSatisfy { $0 >= Freehand.markerEdge && $0 < Freehand.markerEdge + Freehand.markerJitter })
        var random = SeededRandom(seed: 42)
        XCTAssertEqual(alphas[0], 0.55 + 0.3 * random.next(), accuracy: 1e-12)
        let pieces = Freehand.markerPieces(stroke, size: CGSize(width: stroke.w, height: stroke.h))
        let again = Freehand.markerPieces(stroke, size: CGSize(width: stroke.w, height: stroke.h))
        XCTAssertEqual(pieces.map { $0.alpha }, again.map { $0.alpha })
        XCTAssertFalse(pieces.isEmpty)
        // A build without the marker reads it as an ink stroke.
        var older = stroke
        older.pen = nil
        XCTAssertTrue(Freehand.isStroke(older))
        XCTAssertFalse(Freehand.isMarker(older))
    }
}
