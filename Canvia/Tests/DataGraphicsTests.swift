// Charts and tables from typed data, path shapes, and the readers.

import XCTest
import UIKit
@testable import Canvia

final class DataGraphicsTests: XCTestCase {

    private let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
    private let palette = ["#ff0000", "#00ff00", "#0000ff"]

    // MARK: parsing

    func testLinesParseLooselyAndSkipNonNumbers() {
        let series = DataGraphics.parse("Spring, 40\nSummer,65%\n\nnothing here\n12\nWinter , -5")
        XCTAssertEqual(series.map(\.label), ["Spring", "Summer", "Item 5", "Winter"])
        XCTAssertEqual(series.map(\.value), [40, 65, 12, 0])
        XCTAssertEqual(DataGraphics.parseTable("a, b\tc\n\n1,2,3"), [["a", "b\tc"], ["1", "2", "3"]])
        XCTAssertEqual(DataGraphics.parseTable("a\tb\n1\t2"), [["a", "b"], ["1", "2"]])
    }

    // MARK: charts

    func testColumnsScaleToThePeakAndStayInsideTheFrame() {
        let els = DataGraphics.chart(.column, series: DataGraphics.parse("A, 10\nB, 20\nC, 5"), in: frame, palette: palette)
        let bars = els.filter { $0.type == .shape }
        XCTAssertEqual(bars.count, 3)
        XCTAssertEqual(bars[1].h, bars[0].h * 2, accuracy: 1.5, "twice the value, twice the height")
        XCTAssertEqual(bars[1].y + bars[1].h, bars[0].y + bars[0].h, accuracy: 0.001, "a shared baseline")
        for e in els {
            XCTAssertTrue(frame.insetBy(dx: -1, dy: -1).contains(Geometry.aabb(e)), "\(e.type) leaves the frame: \(Geometry.aabb(e))")
        }
        XCTAssertEqual(bars.map { $0.fill?.color }, palette, "colours in palette order")
        XCTAssertEqual(Set(els.compactMap(\.group)).count, 1, "one group")
        XCTAssertEqual(els.filter { $0.type == .text }.map(\.text), ["A", "B", "C"])
    }

    func testAPieIsWedgesThatAddUpAndCarryTheirShare() {
        let els = DataGraphics.chart(.pie, series: DataGraphics.parse("A, 50\nB, 25\nC, 25"), in: frame, palette: palette)
        XCTAssertEqual(els.count, 3)
        XCTAssertTrue(els.allSatisfy { $0.pathData?.hasPrefix("M50 50") == true }, "a pie slice starts at the centre")
        XCTAssertEqual(els[0].altText, "A: 50%")
        XCTAssertEqual(els[0].w, els[0].h, "a pie is round")
        let donut = DataGraphics.chart(.donut, series: DataGraphics.parse("A, 1\nB, 1"), in: frame, palette: palette)
        XCTAssertFalse(donut[0].pathData?.hasPrefix("M50 50") == true, "a ring does not touch the centre")
        // A half-circle wedge parses to a path with area, and a full-circle
        // single value does not degenerate.
        let half = SVGPath.path(DataGraphics.wedge(from: 0, sweep: .pi, inner: 0)).boundingBox
        XCTAssertEqual(half.width, 100, accuracy: 0.5)
        XCTAssertEqual(half.height, 50, accuracy: 1)
        let whole = DataGraphics.chart(.pie, series: DataGraphics.parse("Only, 7"), in: frame, palette: palette)
        XCTAssertEqual(whole.count, 1)
        XCTAssertGreaterThan(SVGPath.path(whole[0].pathData!).boundingBox.width, 90)
    }

    func testALineChartIsOneStrokedPathPlusLabels() {
        let els = DataGraphics.chart(.line, series: DataGraphics.parse("A, 0\nB, 10\nC, 5"), in: frame, palette: palette)
        let line = els.first { $0.type == .shape }!
        XCTAssertEqual(line.pathData, "M0 100 L50 0 L100 50")
        XCTAssertEqual(line.stroke, "#ff0000")
        XCTAssertEqual(els.filter { $0.type == .text }.count, 3)
    }

    func testAnEmptySeriesMakesNothing() {
        XCTAssertTrue(DataGraphics.chart(.bar, series: [], in: frame, palette: palette).isEmpty)
        XCTAssertTrue(DataGraphics.table([], in: frame, accent: "#000000").isEmpty)
    }

    // MARK: tables

    func testATableHasACellAndATextPerSlotAndFillsTheWidth() {
        let rows = DataGraphics.parseTable("Item, Qty\nCoffee, 2\nBagel, 1")
        let els = DataGraphics.table(rows, in: frame, accent: "#123456")
        let cells = els.filter { $0.type == .shape }, texts = els.filter { $0.type == .text }
        XCTAssertEqual(cells.count, 6); XCTAssertEqual(texts.count, 6)
        let union = Geometry.union(cells.map(Geometry.aabb))
        XCTAssertEqual(union.minX, frame.minX, accuracy: 0.001)
        XCTAssertEqual(union.width, frame.width, accuracy: 2)
        XCTAssertEqual(cells[0].fill?.color, "#123456", "header row in the accent")
        XCTAssertEqual(texts[0].fontWeight, 700, "header text bold")
        XCTAssertEqual(texts[0].color, ColorTheory.readableInk(on: "#123456"))
        XCTAssertGreaterThan(cells[0].w, cells[1].w, "'Coffee' is longer than '2', so its column is wider")
        // Rows stack without gaps.
        XCTAssertEqual(cells[2].y, cells[0].y + cells[0].h, accuracy: 0.001)
        XCTAssertEqual(texts.map(\.text), ["Item", "Qty", "Coffee", "2", "Bagel", "1"])
    }

    // MARK: path element

    @MainActor
    func testAPathElementDrawsItsOwnGeometryEverywhere() {
        var el = Element.shape("rect", w: 100, h: 100)
        el.pathData = "M0 0 L100 0 L50 100 Z"   // a triangle
        XCTAssertEqual(ContentLibrary.shape(for: el).path, el.pathData)
        XCTAssertEqual(CanvasAccessibility.label(for: el), "Custom shape")
        var d = Design(title: "p", width: 200, height: 200)
        d.pages[0].elements = [el]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("L50 100"), svg)
        XCTAssertEqual(ContentLibrary.shape(for: Element.shape("circle")).id, "circle", "no path data: the library shape")
    }

    // MARK: readers

    func testRecognisedLinesBecomeTextWhereTheyWere() {
        let lines = [TextRecognizer.Line(text: "HELLO", box: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1))]
        let els = TextRecognizer.elements(from: lines, in: CGRect(x: 100, y: 100, width: 400, height: 200))
        XCTAssertEqual(els.count, 1)
        XCTAssertEqual(els[0].text, "HELLO")
        XCTAssertEqual(els[0].x, 140); XCTAssertEqual(els[0].y, 120)
        XCTAssertEqual(els[0].fontSize, 16, "80% of the line's 20px box")
    }

    func testAQRCodeInAPictureReadsBackItsPayload() throws {
        guard let qr = CodeGenerator.qr("https://canvia.app/hello", side: 400) else { throw XCTSkip("no code generator") }
        // Photograph it: the code on a grey background with a margin.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600), format: format).image { ctx in
            UIColor(white: 0.85, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
            qr.draw(in: CGRect(x: 100, y: 100, width: 400, height: 400))
        }
        guard let payload = TextRecognizer.codePayload(in: photo) else {
            throw XCTSkip("Vision found no barcode in this environment")
        }
        XCTAssertEqual(payload, "https://canvia.app/hello")
    }

    func testTheTextReaderFindsAClearWord() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 120), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 120))
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 60), .foregroundColor: UIColor.black]
            NSAttributedString(string: "HELLO", attributes: attrs).draw(at: CGPoint(x: 40, y: 25))
        }
        let lines = TextRecognizer.lines(in: image, languages: ["en-US"])
        guard let first = lines.first else { throw XCTSkip("no text recognition in this environment") }
        XCTAssertTrue(first.text.uppercased().contains("HELLO"), first.text)
        XCTAssertLessThan(first.box.minY, 0.5, "the word is in the top half, so the box origin must be too")
    }
}
