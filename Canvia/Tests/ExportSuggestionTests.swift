// The export sheet's Suggested file type, read from the design: the same
// cases as the Android twin's ExportSuggestionTest, and its shared fixture
// Fixtures/export-suggestion.json.

import XCTest
@testable import Canvia

final class ExportSuggestionTests: XCTestCase {

    /// A fixture's JSON: from the test bundle, or beside this file.
    private func fixture(_ name: String, file: StaticString = #filePath) throws -> Data {
        if let url = Bundle(for: ExportSuggestionTests.self).url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appendingPathComponent("Fixtures/\(name).json"))
    }

    private struct Case: Decodable {
        var name: String
        var suggested: String
        var design: Design
    }

    private struct Cases: Decodable {
        var cases: [Case]
    }

    private func slides(_ pages: [Page] = [Page(id: "a"), Page(id: "b")]) -> Design {
        var d = Design(title: "Slides", width: 1920, height: 1080)
        d.pages = pages
        return d
    }

    private func sized(_ w: Double, _ h: Double) -> Design {
        Design(title: "Sized", width: w, height: h)
    }

    private func image(_ src: String, w: Double, h: Double, x: Double = 0, y: Double = 0) -> Element {
        var el = Element.image(src, w: w, h: h)
        el.x = x
        el.y = y
        return el
    }

    /// Shared: the fixture lists designs, in the JSON the two apps
    /// exchange, with the format each must suggest — the same cases on both
    /// phones.
    func testTheSharedCasesSuggestWhatTheFixtureSays() throws {
        let cases = try JSONDecoder().decode(Cases.self, from: fixture("export-suggestion")).cases
        XCTAssertGreaterThanOrEqual(cases.count, 20)
        for c in cases {
            XCTAssertEqual(ExportSuggestion.suggest(c.design), c.suggested, c.name)
        }
    }

    func testMovementSoundAndADocumentComeBeforeAPictureInThatOrder() {
        XCTAssertEqual(ExportSuggestion.suggest(slides()), "pdf")
        // A song makes it a film, document or not.
        var song = slides()
        song.audio = [AudioTrack(src: "audio:audio-1.m4a")]
        XCTAssertEqual(ExportSuggestion.suggest(song), "mp4")
        // An animated element.
        var rising = Element.text("Hi")
        rising.animation = ElementAnimation(kind: "rise")
        XCTAssertEqual(ExportSuggestion.suggest(slides([Page(id: "a", elements: [rising]), Page(id: "b")])), "mp4")
        // Its own transition is a page made to play; a hold of its own is
        // not.
        var wipe = Page(id: "a")
        wipe.transition = "wipe"
        XCTAssertEqual(ExportSuggestion.suggest(slides([wipe, Page(id: "b")])), "mp4")
        var held = Page(id: "a")
        held.holdSeconds = 4
        XCTAssertEqual(ExportSuggestion.suggest(slides([held, Page(id: "b")])), "pdf")
    }

    func testADocumentIsSeveralShownPagesOfADocumentsPrintOrPresentationsType() {
        // Its own way round first: a 1920 × 1080 is a Presentation, not an
        // Instagram Story turned on its side.
        XCTAssertEqual(ExportSuggestion.category(sized(1920, 1080)), "Presentations")
        XCTAssertEqual(ExportSuggestion.category(sized(1080, 1920)), "Social")
        // Then the other way round, and a print size by its pixels.
        XCTAssertEqual(ExportSuggestion.category(sized(3508, 2480)), "Documents")
        XCTAssertEqual(ExportSuggestion.category(sized(1050, 600)), "Print")
        XCTAssertEqual(ExportSuggestion.category(sized(1080, 1080)), "Social")
        XCTAssertNil(ExportSuggestion.category(sized(1000, 700)))
        XCTAssertEqual(ExportSuggestion.documentCategories, ["Documents", "Print", "Presentations"])
        // One shown page of a document type is a picture.
        var one = sized(2480, 3508)
        var hidden = Page(id: "b")
        hidden.hidden = true
        one.pages = [Page(id: "a"), hidden]
        XCTAssertEqual(ExportSuggestion.suggest(one), "png")
    }

    func testAPageIsAPhotoWhenOneCoversNineTenthsOfItThePartOnThePageCounted() {
        let design = sized(1000, 1000)
        func page(_ elements: Element...) -> Page { Page(elements: elements) }
        XCTAssertTrue(ExportSuggestion.isPhoto(design, page(image("media:a", w: 1000, h: 900))))
        XCTAssertFalse(ExportSuggestion.isPhoto(design, page(image("media:a", w: 1000, h: 899))))
        // Hanging off the page: only what is on it covers it.
        XCTAssertFalse(ExportSuggestion.isPhoto(design, page(image("media:a", w: 1000, h: 1000, x: 200))))
        XCTAssertTrue(ExportSuggestion.isPhoto(design, page(image("media:a", w: 1400, h: 1400, x: -200, y: -200))))
        // Two photos of half a page each are not one photo.
        XCTAssertFalse(ExportSuggestion.isPhoto(design, page(image("media:a", w: 1000, h: 500),
                                                             image("media:b", w: 1000, h: 500, y: 500))))
        // An empty frame is no photo; a picture behind the page is.
        XCTAssertFalse(ExportSuggestion.isPhoto(design, page(image("", w: 1000, h: 1000))))
        XCTAssertTrue(ExportSuggestion.isPhoto(design, Page(background: .image("media:a"))))
        XCTAssertEqual(ExportSuggestion.photoCover, 0.9)
    }
}
