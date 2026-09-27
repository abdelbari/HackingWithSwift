// PDFs that say what became of them, and a code edited in place — the
// editor's parity with the Android twin.

import XCTest
import UIKit
@testable import Canvia

final class EditorParityTests: XCTestCase {

    /// A PDF of `pages` pages, locked with a password when one is given.
    private func pdf(pages: Int, password: String?) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var info: [String: Any] = [:]
        if let password {
            info[kCGPDFContextUserPassword as String] = password
            info[kCGPDFContextOwnerPassword as String] = password
        }
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary))
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    // MARK: PDF import

    func testAPDFSaysHowManyPagesItHasAndHowManyCameIn() throws {
        var drawn = 0
        XCTAssertEqual(PDFImporter.forEachPage(of: try pdf(pages: 3, password: nil), maxEdge: 100) { _ in drawn += 1 },
                       .pages(rendered: 3, total: 3))
        XCTAssertEqual(drawn, 3)
        XCTAssertEqual(PDFImporter.forEachPage(of: try pdf(pages: 3, password: nil), limit: 1, maxEdge: 100) { _ in },
                       .pages(rendered: 1, total: 3), "a replace draws the first page only")
    }

    /// Locked is told apart from unreadable, and neither draws anything.
    func testALockedPDFIsNotAnEmptyOne() throws {
        var drawn = 0
        XCTAssertEqual(PDFImporter.forEachPage(of: try pdf(pages: 2, password: "open sesame"), maxEdge: 100) { _ in drawn += 1 },
                       .locked)
        XCTAssertEqual(PDFImporter.forEachPage(of: Data("not a pdf".utf8)) { _ in drawn += 1 }, .unreadable)
        XCTAssertEqual(drawn, 0)
    }

    func testWhatAnImportSays() {
        XCTAssertNil(PDFImporter.summary(brought: 1, total: 1), "one page speaks for itself")
        XCTAssertEqual(PDFImporter.summary(brought: 4, total: 4), "Brought in 4 pages")
        XCTAssertEqual(PDFImporter.summary(brought: 60, total: 75), "Brought in the first 60 of 75 pages")
        XCTAssertEqual(PDFImporter.summary(brought: 1, total: 2), "Brought in the first 1 of 2 pages",
                       "said whenever fewer came in than the document has")
    }

    // MARK: a code edited in place

    /// Anything that makes a code is taken as typed; nothing, or more than
    /// a code holds, says why and keeps the last code.
    func testACodeSaysWhyItCannotBeMade() {
        XCTAssertNil(CodeGenerator.problem(with: "https://example.com/menu"))
        XCTAssertNil(CodeGenerator.problem(with: " spaced "), "not trimmed: it scans as typed")
        XCTAssertEqual(CodeGenerator.problem(with: ""),
                       "A code needs a link or some words; it keeps the last until then.")
        XCTAssertEqual(CodeGenerator.problem(with: String(repeating: "x", count: 4000)),
                       "Too long for a QR code; it keeps the last that fitted.")
    }

    /// A refusal carries no Undo; an edit's toast does.
    func testARefusalOffersNoUndo() {
        let s = DesignStore(design: Design(title: "toast", width: 400, height: 400))
        s.announce("That PDF is locked with a password", undoable: false)
        XCTAssertFalse(s.announcementUndoes)
        s.announce("Brought in 3 pages")
        XCTAssertTrue(s.announcementUndoes)
    }
}
