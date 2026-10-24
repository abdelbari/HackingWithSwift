// The web page export as a slide player (HTMLExporter, layout "slides"):
// the shared golden page, fixtures slides.json and slides.html, which the
// Android twin's HtmlWriterTest reads too — compared byte for byte, the
// pictures' base64 aside, with the same stand-in letters and pictures as
// the website's golden page.

import XCTest
@testable import Canvia

final class SlidesExportTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("slides") }

    private func deck() throws -> Design {
        try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(fixture()["design"])))
    }

    private func settings() throws -> HTMLExporter.Settings {
        try JSONDecoder().decode(HTMLExporter.Settings.self, from: SharedFixture.encoded(try XCTUnwrap(fixture()["settings"])))
    }

    private func withoutPictures(_ html: String) -> String {
        html.replacingOccurrences(of: "(;base64,)[A-Za-z0-9+/=]*", with: "$1", options: .regularExpression)
    }

    @MainActor
    private func slides() throws -> String {
        let d = try deck()
        let standIns = SVGExporter.StandIns(letters: { _ in "M0 0L1 1Z" }, picture: { _ in Data([1, 2, 3]) })
        return HTMLExporter.slidePlayer(d, pages: d.visiblePageIndices, settings: try settings(),
                                        clipFile: { el in
                                            guard let id = el.src.flatMap(VideoStore.split)?.id else { return nil }
                                            return HTMLExporter.mediaPath(id, ext: "mp4")
                                        },
                                        poster: { _ in Data([1, 2, 3]) },
                                        standIns: standIns)
    }

    /// Shared: the same slide player, byte for byte but the pictures, on both phones.
    @MainActor
    func testTheSlidePlayerIsTheSharedGoldenPage() throws {
        let want = try SharedFixture.text("slides", ext: "html")
        XCTAssertEqual(withoutPictures(try slides()), withoutPictures(want))
    }

    @MainActor
    func testSlidesAreFullWindowSectionsWithTransitionsEntrancesControlsAndSettings() throws {
        let html = try slides()
        XCTAssertEqual(try settings().layout, HTMLExporter.slides)
        // The hidden page is skipped; the others are numbered as shown.
        XCTAssertTrue(html.contains("<section class=\"slide\" id=\"page-1\" aria-label=\"Intro\" data-t=\"push\" data-s=\"0.5\">"))
        XCTAssertFalse(html.contains("Draft"))
        // Its own length, and a fade for a design's default.
        XCTAssertTrue(html.contains("id=\"page-2\" aria-label=\"Page 2\" data-t=\"zoom\" data-s=\"0.8\">"))
        // A wipe is a fade in CSS.
        XCTAssertTrue(html.contains("id=\"page-3\" aria-label=\"Dates\" data-t=\"fade\" data-s=\"0.25\">"))
        // A link to a page still jumps to its slide.
        XCTAssertTrue(html.contains("<a href=\"#page-3\""))
        // Simple entrances play; a typewriter stays still; the page's own
        // fade comes in through its elements.
        XCTAssertTrue(html.contains("<g class=\"canvia-in canvia-in-rise\" style=\"animation-delay:0.2s;animation-duration:0.6s\">"))
        XCTAssertTrue(html.contains("canvia-in canvia-in-pop"))
        XCTAssertTrue(html.contains("canvia-in canvia-in-wipe"))
        XCTAssertTrue(html.contains("canvia-in canvia-in-pan-left"))
        XCTAssertEqual(html.components(separatedBy: "canvia-in canvia-in-fade").count - 1, 2)
        XCTAssertTrue(html.contains("prefers-reduced-motion:reduce"))
        // The controls and the settings the script reads.
        XCTAssertTrue(html.contains("<body data-auto=\"5\" data-loop=\"true\">"))
        XCTAssertTrue(html.contains("<button id=\"fs\" type=\"button\">Full screen</button>"))
        XCTAssertTrue(html.contains("<script>" + HTMLExporter.slidesJS + "</script>"))
        XCTAssertFalse(html.contains("<nav"))
        XCTAssertTrue((2000...4000).contains(HTMLExporter.slidesJS.utf8.count))
        // The clip plays over its place, in a .zip.
        XCTAssertTrue(html.contains("<video src=\"media/clip-9.mp4\""))
        let d = try deck()
        XCTAssertTrue(HTMLExporter.zipped(d, pages: d.visiblePageIndices, settings: try settings()))
    }

    /// Shared: a cut takes no time in the slide player, whatever length the
    /// page has of its own.
    @MainActor
    func testACutSlideTakesNoTime() throws {
        var design = try XCTUnwrap(fixture()["design"] as? [String: Any])
        var pages = try XCTUnwrap(design["pages"] as? [[String: Any]])
        pages[3]["transition"] = "cut"
        pages[3]["transitionSeconds"] = 1.0
        design["pages"] = pages
        let cut = try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(design))
        let standIns = SVGExporter.StandIns(letters: { _ in "M0 0L1 1Z" }, picture: { _ in Data([1, 2, 3]) })
        let html = HTMLExporter.slidePlayer(cut, pages: cut.visiblePageIndices, settings: try settings(),
                                            clipFile: { _ in nil }, poster: nil, standIns: standIns)
        XCTAssertTrue(html.contains("id=\"page-3\" aria-label=\"Dates\" data-t=\"cut\" data-s=\"0\">"))
    }

    func testTheLayoutIsSuggestedByTheTypeAndTheSettingsKeepTheirKeys() throws {
        XCTAssertEqual(ExportSuggestion.htmlLayout(try deck()), HTMLExporter.slides)
        XCTAssertEqual(ExportSuggestion.htmlLayout(try XCTUnwrap(SizePreset.byId("presentation-4x3")).makeDesign()),
                       HTMLExporter.slides)
        XCTAssertEqual(ExportSuggestion.htmlLayout(try XCTUnwrap(SizePreset.byId("insta-post")).makeDesign()),
                       HTMLExporter.scroll)
        let chosen = try settings()
        XCTAssertEqual(chosen.json,
                       #"{"nav":true,"mobileStack":true,"embedMedia":true,"layout":"slides","autoplay":5.0,"loop":true}"#)
        let last = ExportLast(format: "html", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false,
                              pages: "all", html: chosen)
        XCTAssertEqual(ExportLast.read(last.json), last)
        // A file from before reads as the scrolling site.
        XCTAssertEqual(ExportLast.read(#"{"format":"html","html":{"nav":false}}"#)?.html, HTMLExporter.Settings(nav: false))
        // Transitions as CSS plays them.
        XCTAssertEqual(MovieExporter.transitions.map(HTMLExporter.slideTransition),
                       ["fade", "cut", "slide", "push", "fade", "fade", "zoom"])
        XCTAssertNil(SVGExporter.entranceClass("typewriter"))
        XCTAssertEqual(HTMLExporter.autoplayChoices, [0, 3, 5, 10])
    }
}
