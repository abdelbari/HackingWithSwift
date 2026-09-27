// Exports that can be watched and stopped, and saves that say what went in.
//
// The pacing, the sheet count and the Photos wording are pure and asserted
// directly. The cancel checks render for real, on tiny designs: a cancelled
// export must leave no file, since a short PDF or GIF opens fine and is
// wrong.

import XCTest
import CoreGraphics
@testable import Canvia

final class ExportProgressTests: XCTestCase {

    private func design(pages: Int) -> Design {
        var d = Design(title: "progress", width: 200, height: 120)
        d.pages = (0..<pages).map { _ in Page(elements: [Element.shape("rect", w: 100, h: 60)]) }
        return d
    }

    private func destination(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("progress-test-\(UUID().uuidString).\(ext)")
    }

    // MARK: pacing

    func testThePacerStepsAsideOnlyOnceTheIntervalHasPassed() {
        let start = Date(timeIntervalSince1970: 1_000)
        let interval: TimeInterval = 1.0 / 30.0
        XCTAssertFalse(DesignExporter.Pacer.isDue(since: start, now: start.addingTimeInterval(0.01), interval: interval))
        XCTAssertTrue(DesignExporter.Pacer.isDue(since: start, now: start.addingTimeInterval(0.05), interval: interval))
    }

    func testThePacerStepsAsideBeforeTheFirstPage() {
        let pacer = DesignExporter.Pacer()
        XCTAssertTrue(DesignExporter.Pacer.isDue(since: pacer.last, now: Date(), interval: pacer.interval))
    }

    // MARK: print sheets

    func testFittedPagesTakeOneSheetEach() {
        let d = design(pages: 3)
        let count = DesignExporter.sheetCount(design: d, indices: [0, 1, 2], options: PrintLayout.Options())
        XCTAssertEqual(count, 3)
    }

    func testTiledPagesCountEverySheet() {
        let d = Design(title: "poster", width: 4000, height: 3000)
        var options = PrintLayout.Options()
        options.fit = .tile
        let pagePts = PrintLayout.pagePoints(size: d.size(at: 0), bleed: options.bleed)
        let tiles = PrintLayout.tiles(page: pagePts, printable: options.printable.size, overlap: options.overlap).count
        XCTAssertEqual(DesignExporter.sheetCount(design: d, indices: [0], options: options), tiles)
        XCTAssertGreaterThan(tiles, 1)
    }

    // MARK: cancelling

    @MainActor
    func testACancelledPDFLeavesNoFile() async {
        let url = destination("pdf")
        let d = design(pages: 3)
        let task = Task { @MainActor in
            try await DesignExporter.exportPDF(design: d, to: url)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("a cancelled PDF was finished")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testACancelledPrintPDFLeavesNoFile() async {
        let url = destination("pdf")
        let d = design(pages: 2)
        let task = Task { @MainActor in
            try await DesignExporter.exportPrintPDF(design: d, options: PrintLayout.Options(), to: url)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("a cancelled print PDF was finished")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testACancelledGIFLeavesNoFile() async {
        let url = destination("gif")
        let d = design(pages: 2)
        let task = Task { @MainActor in
            try await MovieExporter.exportGIF(design: d, to: url)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("a cancelled GIF was finished")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testThePDFReportsEachPage() async throws {
        let url = destination("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var seen: [Double] = []
        try await DesignExporter.exportPDF(design: design(pages: 4), to: url, progress: { seen.append($0) })
        XCTAssertEqual(seen, [0.25, 0.5, 0.75, 1])
        XCTAssertEqual(CGPDFDocument(url as CFURL)?.numberOfPages, 4)
    }

    @MainActor
    func testThePrintPDFReportsEachSheet() async throws {
        let url = destination("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var seen: [Double] = []
        try await DesignExporter.exportPrintPDF(design: design(pages: 2), options: PrintLayout.Options(),
                                                to: url, progress: { seen.append($0) })
        XCTAssertEqual(seen, [0.5, 1])
    }

    // MARK: film length

    func testTheFilmLengthCountsEachPagesOwnHold() {
        var d = design(pages: 3)
        d.pages[1].holdSeconds = 6
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 2
        settings.fps = 30
        XCTAssertEqual(MovieExporter.seconds(design: d, settings: settings), 10, accuracy: 0.001)
    }

    // MARK: file names

    func testAFileIsNamedAsTheAndroidTwinNamesItInAnyScript() {
        XCTAssertEqual(DesignExporter.fileBaseName("Poster"), "Poster")
        XCTAssertEqual(DesignExporter.fileBaseName("  Café menu! "), "Café-menu")
        XCTAssertEqual(DesignExporter.fileBaseName("日本語のポスター"), "日本語のポスター")
        XCTAssertEqual(DesignExporter.fileBaseName("قائمة الطعام"), "قائمة-الطعام")
        XCTAssertEqual(DesignExporter.fileBaseName("Cafe\u{0301}"), "Cafe\u{0301}")
        XCTAssertEqual(DesignExporter.fileBaseName("a_b-c 2"), "a_b-c-2")
    }

    func testARunOfSpacesIsOneHyphen() {
        XCTAssertEqual(DesignExporter.fileBaseName("Q3 / report"), "Q3-report")
        let url = DesignExporter.fileURL(for: Design(title: "Q3 / report", width: 10, height: 10), ext: "png")
        XCTAssertEqual(url.lastPathComponent, "Q3-report.png")
    }

    func testATitleWithNothingToKeepIsCalledDesign() {
        XCTAssertEqual(DesignExporter.fileBaseName(""), "design")
        XCTAssertEqual(DesignExporter.fileBaseName("  ★ !? "), "design")
    }

    func testALongTitleIsCutNeverThroughALetter() {
        XCTAssertEqual(DesignExporter.fileBaseName(String(repeating: "x", count: 100)).count, 60)
        let wide = String(repeating: "\u{20000}", count: 70)
        XCTAssertEqual(DesignExporter.fileBaseName(wide).unicodeScalars.count, 60)
    }

    // MARK: Present

    @MainActor
    func testTheNotesButtonSaysWhenAPageHasNone() {
        XCTAssertEqual(PresentationView.notesLabel(hasNotes: true), "Notes")
        XCTAssertEqual(PresentationView.notesLabel(hasNotes: false), "Notes, none for this page")
    }

    // MARK: Photos wording

    func testOnePhotoSaved() {
        XCTAssertEqual(PhotoSaver.Outcome(saved: 1, total: 1).message, "Saved to your photos")
    }

    func testSomeOfSeveralSaved() {
        XCTAssertEqual(PhotoSaver.Outcome(saved: 3, total: 5).message, "Saved 3 of 5 photos")
    }

    func testAllOfSeveralSaved() {
        XCTAssertEqual(PhotoSaver.Outcome(saved: 5, total: 5).message, "Saved 5 photos")
    }

    func testNothingSavedSaysSo() {
        let outcome = PhotoSaver.Outcome(saved: 0, total: 2)
        XCTAssertEqual(outcome.message, "Couldn't save to your photos")
        XCTAssertFalse(outcome.anySaved)
    }

    func testACancelStillSaysWhatWentIn() {
        XCTAssertEqual(PhotoSaver.Outcome(saved: 2, total: 5, cancelled: true).message, "Saved 2 of 5 photos")
        XCTAssertNil(PhotoSaver.Outcome(saved: 0, total: 5, cancelled: true).message)
    }
}
