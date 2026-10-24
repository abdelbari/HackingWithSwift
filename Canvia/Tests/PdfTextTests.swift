// A PDF's words read where they stand, for importing it as editable text —
// held to the golden runs both phones share (Fixtures/pdf-text.pdf, from
// Tools/generate_pdf_fixture.py, read into Fixtures/pdf-text.json byte for
// byte), as the Android twin's PdfTextTest.

import XCTest
@testable import Canvia

final class PdfTextTests: XCTestCase {

    private func document() throws -> [PdfText.TextPage] {
        guard case .document(let pages, _) = PdfText.read(try SharedFixture.data("pdf-text", ext: "pdf")) else {
            XCTFail("the fixture did not read")
            return []
        }
        return pages
    }

    /// Shared with the Android twin's PdfTextTest.
    func testTheFixtureReadsIntoTheGoldenRuns() throws {
        let golden = try SharedFixture.text("pdf-text", ext: "json")
        XCTAssertEqual(PdfText.json(try document()), golden)
    }

    func testRunsMakeLinesAndLinesMakeParagraphs() throws {
        let pages = try document()
        XCTAssertEqual(pages.count, 2)
        let first = PdfText.paragraphs(PdfText.lines(pages[0].runs))
        XCTAssertEqual(first.map { $0.map(\.text) },
                       [["Café – Menu"], ["Fresh coffee every day", "Open until € 5 (pm)", "Smith’s Bakery"], ["Yellow note"]])
        let second = PdfText.paragraphs(PdfText.lines(pages[1].runs))
        XCTAssertEqual(second.map { $0.map(\.text) }, [["Hello"], ["abcé", "xyz"]])
    }

    func testALineJoinsRunsOnOneBaselineWithASpaceWhereTheyLeaveAGap() {
        func run(_ text: String, _ x: Double, _ y: Double, _ w: Double) -> PdfText.PdfRun {
            PdfText.PdfRun(text: text, x: x, y: y, size: 10, font: "Helvetica", bold: false, italic: false,
                        colour: "#000000", width: w)
        }
        let lines = PdfText.lines([run("world", 60, 101, 25), run("Hello", 20, 100, 25), run("Next", 20, 120, 20)])
        XCTAssertEqual(lines.map(\.text), ["Hello world", "Next"])
        // 3.5 apart is more than 0.3 of the size: a line of its own.
        XCTAssertEqual(PdfText.lines([run("a", 0, 0, 5), run("b", 10, 3.5, 5), run("c", 0, 50, 5)]).count, 3)
    }

    func testAParagraphBreaksAtAWideGapOrAnotherLeftEdge() {
        func line(_ y: Double, _ x: Double) -> PdfText.PdfLine {
            let run = PdfText.PdfRun(text: "w", x: x, y: y, size: 10, font: "F", bold: false, italic: false, colour: "#000000",
                                  width: 10)
            return PdfText.PdfLine(runs: [run], y: y, x: x, right: x + 10)
        }
        let paras = PdfText.paragraphs([line(0, 0), line(16, 1.5), line(33, 1.5), line(45, 10)])
        XCTAssertEqual(paras.map(\.count), [2, 1, 1])
    }

    func testFontsMapToTheNearestFamilyByTheirName() {
        XCTAssertEqual(PdfText.family("Lora-Italic"), "lora")
        XCTAssertEqual(PdfText.family("Montserrat-Bold"), "montserrat")
        XCTAssertEqual(PdfText.family("PlayfairDisplay-Regular"), "playfair-display")
        XCTAssertEqual(PdfText.family("Times-Roman"), "serif")
        XCTAssertEqual(PdfText.family("TimesNewRomanPSMT"), "serif")
        XCTAssertEqual(PdfText.family("Courier-Bold"), "mono")
        XCTAssertEqual(PdfText.family("Helvetica-Bold"), "sans")
        XCTAssertEqual(PdfText.family("ArialMT"), "sans")
        XCTAssertEqual(PdfText.withoutSubset("ABCDEF+Lora-Italic"), "Lora-Italic")
        XCTAssertEqual(PdfText.withoutSubset("Ab+Font"), "Ab+Font")
    }

    func testGlyphNamesReadAsTheirWords() {
        XCTAssertEqual(PdfText.glyph("eacute"), "é")
        XCTAssertEqual(PdfText.glyph("Udieresis"), "Ü")
        XCTAssertEqual(PdfText.glyph("quoteright"), "’")
        XCTAssertEqual(PdfText.glyph("uni20AC"), "€")
        XCTAssertEqual(PdfText.glyph("u1F600"), "😀")
        XCTAssertEqual(PdfText.glyph("seven"), "7")
        XCTAssertNil(PdfText.glyph("g123"))
    }

    func testParagraphsBecomeLeftSetTextBoxesInTheRunsLook() throws {
        let height: (Element) -> Double = { el in
            Double((el.text ?? "").components(separatedBy: "\n").count) * (el.fontSize ?? 10) * 1.2
        }
        let page = try document()[0]
        let boxes = PdfText.textElements(page, scale: 1, heightFor: height)
        XCTAssertEqual(boxes.count, 3)
        let title = boxes[0]
        XCTAssertEqual(title.text, "Café – Menu")
        XCTAssertEqual(title.fontFamily, "sans")
        XCTAssertEqual(title.fontWeight, 700)
        XCTAssertEqual(title.fontSize ?? 0, 24, accuracy: 1e-9)
        XCTAssertEqual(title.color, "#1f2430")
        XCTAssertEqual(title.align, "left")
        XCTAssertEqual(title.x, 72, accuracy: 1e-9)
        XCTAssertEqual(title.y, 72 - 24 * PdfText.ascent, accuracy: 1e-9)
        let body = boxes[1]
        XCTAssertEqual(body.text, "Fresh coffee every day\nOpen until € 5 (pm)\nSmith’s Bakery")
        XCTAssertEqual(body.fontFamily, "serif")
        XCTAssertEqual(body.lineHeight ?? 0, 1.17, accuracy: 1e-9)
        XCTAssertEqual(PdfText.lineBoxes(page).count, 5)
    }

    func testABoxIsPaintedOverWithTheMedianOfTheRingAroundIt() {
        let w = 10, h = 10
        var px = [UInt32](repeating: 0xffffffff, count: w * h)
        // Words in the box, and one dark speck in the ring.
        for y in 4..<6 { for x in 4..<6 { px[y * w + x] = 0xff000000 } }
        px[3 * w + 3] = 0xff000000
        XCTAssertEqual(PdfText.ringMedian(px, width: w, height: h, left: 4, top: 4, right: 6, bottom: 6), 0xffffffff)
    }

    func testAnEncryptedOrBrokenFileReadsAsSuch() {
        let pdf = "%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\ntrailer << /Root 1 0 R /Encrypt 5 0 R >>\n%%EOF"
        guard case .encrypted = PdfText.read(Data(pdf.utf8)) else { return XCTFail("not read as encrypted") }
        guard case .unreadable = PdfText.read(Data("not a pdf".utf8)) else { return XCTFail("not read as unreadable") }
    }

    func testNumbersGoOutToTwoPlaces() {
        XCTAssertEqual(PdfText.num(72), "72")
        XCTAssertEqual(PdfText.num(205.43999999999997), "205.44")
        XCTAssertEqual(PdfText.num(-0.495), "-0.5")
    }

    func testAnEditablePageIsItsLockedPictureItsWordsOverItAndWhereItCameFrom() throws {
        let height: (Element) -> Double = { ($0.fontSize ?? 10) * 1.2 }
        let pages = try document()
        let page = PdfText.editablePage(pages[1], src: "media:img1", name: "menu.pdf", number: 2,
                                        pageSize: CGSize(width: 1190, height: 1684), layerName: "PDF page", heightFor: height)
        let picture = try XCTUnwrap(page.elements.first)
        XCTAssertEqual(picture.src, "media:img1")
        XCTAssertTrue(picture.locked)
        XCTAssertEqual(picture.layerName, "PDF page")
        XCTAssertEqual(picture.w, 1190, accuracy: 1e-9)
        XCTAssertEqual(page.elements.dropFirst().map { $0.text ?? "" }, ["Hello", "abcé\nxyz"])
        // Twice the points: the title 60 at 112 across.
        XCTAssertEqual(page.elements[1].fontSize ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(page.elements[1].x, 112, accuracy: 1e-9)
        XCTAssertEqual(page.pdfSource, PdfSource(name: "menu.pdf", page: 2))
        let json = String(decoding: try JSONEncoder().encode(page.pdfSource), as: UTF8.self)
        XCTAssertTrue(json.contains(#""name":"menu.pdf""#) && json.contains(#""page":2"#))
        XCTAssertTrue(PdfText.editable(pages[0]))
        XCTAssertFalse(PdfText.editable(PdfText.TextPage(width: 10, height: 10, runs: [])))
    }
}
