// A print bleed you can see and design into: the design's `bleed` key,
// "Show print bleed" as one step, the bleed's edge as a snap line, and the
// print-ready PDF drawing the real bleed rather than enlarging the page.
// The rows are the Android twin's BleedTest.

import XCTest
import CoreGraphics
import UIKit
@testable import Canvia

final class BleedTests: XCTestCase {

    // MARK: the bleed

    /// 3 mm at the design's dpi, or at 300 when it says none — a design in
    /// pixels among them — to the nearest half unit.
    func testShowPrintBleedGives3mmAtTheDesignsDpiOrAt300ToAHalfUnit() {
        let rows: [(unit: String?, dpi: Double?, px: Double)] = [
            (nil, nil, 35.5),    // pixels: the 300 dpi rule, 35.43
            ("mm", nil, 35.5),   // paper without a dpi is at 300
            ("mm", 300, 35.5),
            ("in", 150, 17.5),   // 17.72
            (nil, 96, 11.5),     // 11.34
            ("cm", 72, 8.5),     // 8.50
            ("in", 600, 71),     // 70.87
        ]
        for row in rows {
            var design = Design(title: "b", width: 1000, height: 500)
            design.unit = row.unit
            design.dpi = row.dpi
            XCTAssertEqual(Bleed.bleedPx(design), row.px, "\(row.unit ?? "px") at \(row.dpi ?? 0)")
        }
    }

    func testABleedIsOnOnlyWhenTheDesignHasOneAboveNothing() {
        var d = Design(title: "b", width: 100, height: 50)
        XCTAssertEqual(Bleed.of(d), 0)
        XCTAssertFalse(Bleed.shown(d))
        for none in [0.0, -4, .nan] {
            d.bleed = none
            XCTAssertEqual(Bleed.of(d), 0, "\(none)")
        }
        d.bleed = 12
        XCTAssertEqual(Bleed.of(d), 12)
        XCTAssertTrue(Bleed.shown(d))
        XCTAssertEqual(Bleed.bledRect(size: CGSize(width: 100, height: 50), bleed: 12),
                       CGRect(x: -12, y: -12, width: 124, height: 74))
    }

    private func json(_ design: Design) throws -> [String: Any] {
        let data = try JSONEncoder().encode(design)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Written only while the bleed is shown, and read as either phone
    /// wrote it.
    func testTheKeyIsWrittenOnlyWhileBleedIsShownAndReadFromAndroid() throws {
        let off = Design(title: "Flyer", width: 1000, height: 500)
        XCTAssertNil(try json(off)["bleed"])
        let on = Bleed.withBleed(off, on: true)
        XCTAssertEqual(try json(on)["bleed"] as? Double, 35.5)
        XCTAssertNil(try json(Bleed.withBleed(on, on: false))["bleed"])

        let android = #"{"id":"d","title":"Flyer","width":2480,"height":3508,"unit":"mm","dpi":300,"bleed":35.5,"pages":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(Design.self, from: Data(android.utf8)).bleed, 35.5)
        XCTAssertEqual(try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(on)).bleed, 35.5)
        XCTAssertNil(try JSONDecoder().decode(Design.self, from: Data(#"{"id":"d","pages":[]}"#.utf8)).bleed)
        XCTAssertNil(try JSONDecoder().decode(Design.self, from: Data(#"{"id":"d","bleed":0,"pages":[]}"#.utf8)).bleed,
                     "nothing is no bleed")
        XCTAssertNil(try JSONDecoder().decode(Design.self, from: Data(#"{"id":"d","bleed":-3,"pages":[]}"#.utf8)).bleed)
    }

    @MainActor
    func testTurningBleedOnOrOffIsOneStep() {
        let store = DesignStore(design: Design(title: "b", width: 1000, height: 500))
        store.setBleed(true)
        XCTAssertEqual(store.design.bleed, 35.5)
        let version = store.historyVersion
        store.setBleed(true)
        XCTAssertEqual(store.historyVersion, version, "already on, nothing recorded")
        store.setBleed(false)
        XCTAssertNil(store.design.bleed)
        store.undo()
        XCTAssertEqual(store.design.bleed, 35.5)
        store.undo()
        XCTAssertNil(store.design.bleed)
    }

    /// The bleed's outer edge is a line of the page's, beside its edges.
    func testSnappingGainsTheBleedEdgeBesideThePages() {
        var design = Design(title: "b", width: 1000, height: 500)
        func edges(_ lines: [Geometry.SnapLine]) -> [Double] {
            lines.filter { $0.source == .bleedEdge }.map(\.position)
        }
        let none = Geometry.taggedSnapLines(design: design, page: design.pages[0], excluding: [])
        XCTAssertTrue(edges(none.x).isEmpty)
        design.bleed = 35.5
        let bled = Geometry.taggedSnapLines(design: design, page: design.pages[0], excluding: [])
        XCTAssertEqual(edges(bled.x), [-35.5, 1035.5])
        XCTAssertEqual(edges(bled.y), [-35.5, 535.5])
        // It is the page's: off with snapping to the page.
        let off = Geometry.taggedSnapLines(design: design, page: design.pages[0], excluding: [],
                                           settings: SnapSettings(toPage: false))
        XCTAssertTrue(edges(off.x).isEmpty)
        XCTAssertEqual(ElementNames.guideLabel(.bleedEdge, vertical: true, elements: []), "Edge of the bleed")
    }

    func testAPhotoPulledToTheBleedEdgeLandsOnIt() {
        var design = Design(title: "b", width: 1000, height: 500)
        design.bleed = 35.5
        let lines = Geometry.taggedSnapLines(design: design, page: design.pages[0], excluding: [])
        let start = CGRect(x: 10, y: 100, width: 200, height: 200)
        let snap = Geometry.snap(box: start.offsetBy(dx: -43, dy: 0), xLines: lines.x.map(\.position),
                                 yLines: lines.y.map(\.position), threshold: 8)
        XCTAssertEqual(-43 + snap.dx, -45.5, accuracy: 1e-9)
        XCTAssertEqual(Geometry.snapSource(at: snap.guideX, in: lines.x), .bleedEdge)
    }

    // MARK: the background through the band

    /// The colour of `image` at `x`, `y` in its pixels from the top left.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> (r: Int, g: Int, b: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        }
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    /// Whether the trimmed page and the bled page's middle, `bleed` in,
    /// are the same picture at each of `xs` along the page's middle row.
    private func assertSameAtTheTrim(_ trimmed: CGImage, _ bled: CGImage, bleed: Int, xs: [Int],
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        for x in xs {
            let a = try pixel(trimmed, x, 500)
            let b = try pixel(bled, x + bleed, 500 + bleed)
            let apart = max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
            XCTAssertLessThanOrEqual(apart, 4, "at \(x): \(a) and \(b)", file: file, line: line)
        }
    }

    /// The trim is the same picture with or without the band round it, as
    /// on Android: a photo is laid over the page and the design's bleed in
    /// both, and a gradient over the page, its end colours on through the
    /// band — so the print PDF's trim is the plain PDF's page.
    @MainActor
    func testThePagesBackgroundIsTheSameAtTheTrimWithOrWithoutTheBand() throws {
        // A square photo, its left quarter red: laid over the page and its
        // 36 px bleed, 1072 px, the red ends at 232, not at 250.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 25, height: 100))
        }
        let src = try XCTUnwrap(MediaStore.storeOpaque(photo))
        defer { MediaStore.delete(String(src.dropFirst("media:".count))) }
        var design = Design(title: "b", width: 1000, height: 1000)
        design.bleed = 36
        design.pages[0].background = .image(src)

        var trimmed = try XCTUnwrap(DesignExporter.render(design: design, page: design.pages[0], scale: 1))
        var bled = try XCTUnwrap(DesignExporter.render(design: design, page: design.pages[0], scale: 1, bleed: 36))
        XCTAssertEqual(trimmed.width, 1000)
        XCTAssertEqual(bled.width, 1072)
        try assertSameAtTheTrim(trimmed, bled, bleed: 36, xs: [100, 241, 500, 900])
        let edge = try pixel(trimmed, 241, 500)
        XCTAssertTrue(edge.b > 150 && edge.r < 100, "the photo covers the bleed too: \(edge)")

        // Black to white across: the band carries the ends on.
        design.pages[0].background = .gradient(Paint(kind: "gradient", color: nil, angle: 90, stops: [
            GradientStop(offset: 0, color: "#000000"), GradientStop(offset: 1, color: "#ffffff"),
        ]))
        trimmed = try XCTUnwrap(DesignExporter.render(design: design, page: design.pages[0], scale: 1))
        bled = try XCTUnwrap(DesignExporter.render(design: design, page: design.pages[0], scale: 1, bleed: 36))
        try assertSameAtTheTrim(trimmed, bled, bleed: 36, xs: [50, 250, 500, 750, 950])
        XCTAssertLessThan(try pixel(bled, 10, 536).r, 8, "the start colour, on through the band")
        XCTAssertGreaterThan(try pixel(bled, 1062, 536).r, 247, "and the end colour")
    }

    // MARK: printing it

    /// Whether a page rect lands, drawn by `d` into a page `points` big,
    /// inside both the clip and the paper.
    private func printed(_ rect: CGRect, _ d: PrintLayout.Drawing, points: CGSize) -> Bool {
        let clip = d.clip
        let overlaps = rect.minX < clip.maxX && rect.maxX > clip.minX && rect.minY < clip.maxY && rect.maxY > clip.minY
        let x0 = Double(d.origin.x) + Double(max(rect.minX, clip.minX)) * d.scale
        let x1 = Double(d.origin.x) + Double(min(rect.maxX, clip.maxX)) * d.scale
        return overlaps && x1 > 0 && x0 < Double(points.width) && x1 - x0 > 1e-9
    }

    func testARectAtMinusTheBleedPrintsInThePrintPDFsBleedAndNotInThePlainPDF() {
        // A4 at 300 dpi with its 3 mm bleed: 35.5 px is 8.52 pt.
        var a4 = Design(title: "A4", width: 2480, height: 3508)
        a4.unit = "mm"
        a4.dpi = 300
        let design = Bleed.withBleed(a4, on: true)
        let bleed = Bleed.of(design)
        let pxToPt = PrintLayout.pxToPt(design)
        let rect = CGRect(x: -bleed, y: 1000, width: bleed, height: 200)
        let size = design.size

        // The print-ready PDF, its stepper at the design's bleed.
        let sheetBleed = Bleed.printPoints(design)
        XCTAssertEqual(sheetBleed, 8.52, accuracy: 1e-9)
        let print = PrintLayout.drawing(size: size, bleed: sheetBleed, pxToPt: pxToPt, designed: true)
        let points = PrintLayout.pagePoints(size: size, dpi: design.effectiveDPI, bleed: sheetBleed)
        XCTAssertTrue(printed(rect, print, points: points))
        // At the page's true size, the trim set in by the bleed.
        XCTAssertEqual(print.scale, pxToPt)
        XCTAssertEqual(print.origin.x, sheetBleed, accuracy: 1e-9)
        XCTAssertEqual(print.origin.y, sheetBleed, accuracy: 1e-9)
        XCTAssertEqual(Double(print.origin.x) + Double(rect.minX) * print.scale, 0, accuracy: 1e-9)

        // The plain PDF is the trim: its page starts at the trim's edge.
        let plain = PrintLayout.Drawing(origin: .zero, scale: pxToPt, clip: CGRect(origin: .zero, size: size))
        let page = CGSize(width: Double(size.width) * pxToPt, height: Double(size.height) * pxToPt)
        XCTAssertFalse(printed(rect, plain, points: page))

        // Nor in a design without bleed, enlarged to make one: cut at its edge.
        let enlarged = PrintLayout.drawing(size: size, bleed: sheetBleed, pxToPt: pxToPt, designed: false)
        XCTAssertFalse(printed(rect, enlarged, points: points))
    }

    func testWithoutADesignedBleedThePageIsEnlargedToCoverTheBledAreaAsBefore() {
        let d = PrintLayout.drawing(size: CGSize(width: 1000, height: 500), bleed: 9, pxToPt: 0.75, designed: false)
        // 768 × 393 pt of bled page: 393 / 500 is the larger share, so the
        // page fills its height and runs past the bleed across, centred.
        XCTAssertEqual(d.scale, 0.786, accuracy: 1e-12)
        XCTAssertEqual(d.origin.y, 0, accuracy: 1e-9)
        XCTAssertEqual(Double(d.origin.x), (768 - 1000 * 0.786) / 2, accuracy: 1e-9)
        XCTAssertEqual(d.clip, CGRect(x: 0, y: 0, width: 1000, height: 500))
    }

    func testASheetHoldingTheWholePageCarriesItsTrimAndBleedBoxes() throws {
        var options = PrintLayout.Options()
        options.fit = .actual
        options.bleed = 8.52
        let points = PrintLayout.pagePoints(size: CGSize(width: 2480, height: 3508), dpi: 300, bleed: options.bleed)
        let placement = try XCTUnwrap(DesignExporter.placements(pagePoints: points, options: options).first)
        let boxes = try XCTUnwrap(PrintLayout.boxes(sheet: placement.sheetRect, source: placement.source, page: points,
                                                    bleed: options.bleed, sheetHeight: Double(options.sheet.height)))
        // 595.2 × 841.92 pt of trim, centred on 595 × 842 pt of A4.
        XCTAssertEqual(boxes.trim.width, 595.2, accuracy: 1e-9)
        XCTAssertEqual(boxes.trim.height, 841.92, accuracy: 1e-9)
        XCTAssertEqual(boxes.bleed.minX, boxes.trim.minX - 8.52, accuracy: 1e-9)
        XCTAssertEqual(boxes.bleed.maxY, boxes.trim.maxY + 8.52, accuracy: 1e-9)
        XCTAssertEqual(boxes.trim.midY, 842.0 / 2, accuracy: 1e-9)
        // A poster's tiles hold pieces, and carry none.
        options.fit = .tile
        let poster = PrintLayout.pagePoints(size: CGSize(width: 4000, height: 4000), dpi: 96, bleed: 8.52)
        let tiles = DesignExporter.placements(pagePoints: poster, options: options)
        XCTAssertGreaterThan(tiles.count, 1)
        for tile in tiles {
            XCTAssertNil(PrintLayout.boxes(sheet: tile.sheetRect, source: tile.source, page: poster,
                                           bleed: 8.52, sheetHeight: 842))
        }
    }

    /// The colour of a PDF's first page at `point`, in its own points up
    /// from the bottom, drawn over white.
    private func colour(of url: URL, at point: CGPoint) throws -> (r: Int, g: Int, b: Int) {
        let page = try XCTUnwrap(CGPDFDocument(url as CFURL)?.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let w = Int(box.width.rounded(.up)), h = Int(box.height.rounded(.up))
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        try bytes.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(page)
        }
        let x = min(max(Int(point.x - box.minX), 0), w - 1)
        let y = min(max(h - 1 - Int(point.y - box.minY), 0), h - 1)
        let i = (y * w + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    private func isRed(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.r > 200 && c.g < 80 && c.b < 80 }

    /// The first page's drawing operators as text, its content streams
    /// joined: what a failing check reports, so the log says where a shape
    /// was drawn and under which clip.
    private func contentStream(of url: URL) -> String {
        guard let page = CGPDFDocument(url as CFURL)?.page(at: 1), let dict = page.dictionary else { return "(no page)" }
        var streams: [CGPDFStreamRef] = []
        var single: CGPDFStreamRef?
        var array: CGPDFArrayRef?
        if CGPDFDictionaryGetStream(dict, "Contents", &single), let single {
            streams.append(single)
        } else if CGPDFDictionaryGetArray(dict, "Contents", &array), let array {
            for i in 0..<CGPDFArrayGetCount(array) {
                var item: CGPDFStreamRef?
                if CGPDFArrayGetStream(array, i, &item), let item { streams.append(item) }
            }
        }
        var text = ""
        for stream in streams {
            var format = CGPDFDataFormat.raw
            guard let data = CGPDFStreamCopyData(stream, &format) as Data? else { continue }
            text += String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
        }
        return text.isEmpty ? "(empty)" : text
    }

    /// The test the spec asks for, end to end: a red bar put wholly in the
    /// bleed, left of the trim, prints there in the print-ready PDF — which
    /// says where its trim and bleed are — and is nowhere in the plain PDF,
    /// nor in the print PDF of the same page without a bleed of its own.
    @MainActor
    func testARectInTheBleedIsInThePrintPDFAndNotTheStandardOne() async throws {
        var design = Bleed.withBleed(Design(title: "Bleed", width: 1000, height: 500), on: true)
        let bleed = Bleed.of(design)
        var bar = Element.shape("rect", w: bleed, h: 100)
        bar.x = -bleed
        bar.y = 200
        bar.fill = .solid("#ff0000")
        design.pages[0].elements = [bar]
        var options = PrintLayout.Options()
        options.landscape = true
        options.fit = .actual
        options.bleed = Bleed.printPoints(design)
        let pxToPt = PrintLayout.pxToPt(design)

        let bledPDF = FileManager.default.temporaryDirectory.appendingPathComponent("bleed-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: bledPDF) }
        try await DesignExporter.exportPrintPDF(design: design, options: options, to: bledPDF)
        let page = try XCTUnwrap(CGPDFDocument(bledPDF as CFURL)?.page(at: 1))
        let trim = page.getBoxRect(.trimBox)
        let bled = page.getBoxRect(.bleedBox)
        XCTAssertEqual(trim.width, 750, accuracy: 0.01, "the page at its true size")
        XCTAssertEqual(Double(trim.minX - bled.minX), options.bleed, accuracy: 0.01)
        // Halfway across the band, level with the bar's middle.
        let inBand = CGPoint(x: Double(bled.minX + trim.minX) / 2, y: Double(trim.maxY) - 250 * pxToPt)
        XCTAssertTrue(isRed(try colour(of: bledPDF, at: inBand)), "the bar prints in the bleed")
        XCTAssertFalse(isRed(try colour(of: bledPDF, at: CGPoint(x: trim.minX + 4, y: inBand.y))),
                       "and not inside the trim")

        let plain = FileManager.default.temporaryDirectory.appendingPathComponent("plain-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: plain) }
        try await DesignExporter.exportPDF(design: design, to: plain)
        let plainBox = try XCTUnwrap(CGPDFDocument(plain as CFURL)?.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(plainBox.width, 750, accuracy: 0.01, "the plain PDF is the trim")
        let plainY = Double(plainBox.maxY) - 250 * pxToPt
        let plainSeen = try [0.5, 1.5, 3.0, 6.0, 12.0, 24.0].map { x in "\(x): \(try colour(of: plain, at: CGPoint(x: x, y: plainY)))" }
        XCTAssertFalse(isRed(try colour(of: plain, at: CGPoint(x: 0.5, y: plainY))),
                       "plain PDF \(plainBox) bleed \(bleed) pxToPt \(pxToPt); colours along the bar's row: \(plainSeen.joined(separator: ", ")); content: \(contentStream(of: plain).prefix(1500))")

        var bare = design
        bare.bleed = nil
        let enlarged = FileManager.default.temporaryDirectory.appendingPathComponent("enlarged-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: enlarged) }
        try await DesignExporter.exportPrintPDF(design: bare, options: options, to: enlarged)
        XCTAssertFalse(isRed(try colour(of: enlarged, at: inBand)), "enlarged, the page is cut at its edge")
        // And, as before there was a bleed to design, it says no trim or
        // bleed: both read as the whole sheet.
        let enlargedPage = try XCTUnwrap(CGPDFDocument(enlarged as CFURL)?.page(at: 1))
        XCTAssertEqual(enlargedPage.getBoxRect(.trimBox), enlargedPage.getBoxRect(.mediaBox))
        XCTAssertEqual(enlargedPage.getBoxRect(.bleedBox), enlargedPage.getBoxRect(.mediaBox))

        // A designed bleed printed with the stepper at 0 still says where
        // the trim is, its bleed the same, as on Android.
        options.bleed = 0
        let unbled = FileManager.default.temporaryDirectory.appendingPathComponent("unbled-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: unbled) }
        try await DesignExporter.exportPrintPDF(design: design, options: options, to: unbled)
        let unbledPage = try XCTUnwrap(CGPDFDocument(unbled as CFURL)?.page(at: 1))
        XCTAssertEqual(unbledPage.getBoxRect(.trimBox).width, 750, accuracy: 0.01)
        XCTAssertEqual(unbledPage.getBoxRect(.bleedBox), unbledPage.getBoxRect(.trimBox))
    }
}
