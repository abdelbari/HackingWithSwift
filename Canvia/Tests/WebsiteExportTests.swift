// The web page export (HTMLExporter) and the Website type: the shared golden
// page, fixtures website.json and website.html, which the Android twin's
// HtmlWriterTest reads too.
//
// The whole page — head, styles, menu, sections, each page's SVG, clips — is
// compared byte for byte, the pictures' base64 aside. Glyph outlines come
// from each phone's own type engine, so both phones' tests draw every text
// with the same stand-in letters and every picture with stand-in bytes
// (SVGExporter.StandIns here, SvgWriter.Renderer on Android).

import XCTest
@testable import Canvia

final class WebsiteExportTests: XCTestCase {

    private func design() throws -> Design {
        let fixture = try SharedFixture.object("website")
        return try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(fixture["design"])))
    }

    /// Every embedded picture emptied: what the golden comparison ignores.
    private func withoutPictures(_ html: String) -> String {
        html.replacingOccurrences(of: "(;base64,)[A-Za-z0-9+/=]*", with: "$1", options: .regularExpression)
    }

    /// The Android twin's test letters and pictures (HtmlWriterTest.Fixed).
    private let standIns = SVGExporter.StandIns(letters: { _ in "M0 0L1 1Z" }, picture: { _ in Data([1, 2, 3]) })

    @MainActor
    private func golden(_ d: Design, settings: HTMLExporter.Settings = HTMLExporter.Settings()) -> String {
        let standIns = self.standIns
        return HTMLExporter.html(d, pages: d.visiblePageIndices, settings: settings,
                                 clipFile: { el in
                                     guard let id = el.src.flatMap(VideoStore.split)?.id else { return nil }
                                     return HTMLExporter.mediaPath(id, ext: "mp4")
                                 },
                                 svg: { page in SVGExporter.svg(design: d, page: page, aria: true, standIns: standIns) },
                                 poster: { _ in Data([1, 2, 3]) })
    }

    /// Shared: the same page as the twin's, byte for byte but the pictures.
    @MainActor
    func testThePageIsTheSharedGoldenPage() throws {
        let want = try SharedFixture.text("website", ext: "html")
        XCTAssertEqual(withoutPictures(golden(try design())), withoutPictures(want))
    }

    @MainActor
    func testSectionsMenuAndClipsAreWhereTheyBelong() throws {
        let d = try design()
        let html = golden(d)
        // The hidden page is not a section.
        XCTAssertTrue(html.contains("<section id=\"page-1\" aria-label=\"Home\">"))
        XCTAssertTrue(html.contains("<section id=\"page-2\" aria-label=\"Page 2\">"))
        XCTAssertFalse(html.contains("page-3"))
        XCTAssertFalse(html.contains("Secret"))
        XCTAssertTrue(html.contains("<nav aria-label=\"Pages\"><a href=\"#page-1\">Home</a><a href=\"#page-2\">Page 2</a></nav>"))
        XCTAssertTrue(html.contains("<video src=\"media/clip-1.mp4\" controls playsinline preload=\"none\" aria-label=\"Pouring a flat white\" poster=\"data:image/png;base64,AQID\""))
        XCTAssertTrue(html.contains("style=\"left:65.8858%;top:13.02083%;width:29.28258%;height:39.0625%;transform:rotate(5deg)\""))
        XCTAssertTrue(html.contains("<title>Corner Café &amp; Co</title>"))
        XCTAssertTrue(HTMLExporter.zipped(d, pages: [0, 1], settings: HTMLExporter.Settings()))
        // Without the clips: one page, each clip its still, no menu when asked.
        let plain = golden(d, settings: HTMLExporter.Settings(nav: false, embedMedia: false))
        XCTAssertFalse(plain.contains("<video"))
        XCTAssertFalse(plain.contains("<nav"))
        XCTAssertFalse(plain.contains("@media"))
        XCTAssertFalse(HTMLExporter.zipped(d, pages: [0, 1], settings: HTMLExporter.Settings(embedMedia: false)))
    }

    /// The SVG a section holds keeps links as <a> and says alt text as
    /// aria-label.
    @MainActor
    func testTheSectionsSVGKeepsLinksAndAltText() throws {
        let d = try design()
        let svg = SVGExporter.svg(design: d, page: d.pages[0], aria: true)
        XCTAssertTrue(svg.contains("<a href=\"https://example.com/menu\""))
        XCTAssertTrue(svg.contains("role=\"img\" aria-label=\"View the menu\""))
        XCTAssertTrue(svg.contains("role=\"img\" aria-label=\"Pouring a flat white\""))
        // An SVG export on its own says alt text as a title only, as before.
        XCTAssertFalse(SVGExporter.svg(design: d, page: d.pages[0]).contains("aria-label"))
    }

    /// The Website type suggests HTML, and the settings travel under "html".
    func testAWebsiteSuggestsHTMLAndTheSettingsTravel() throws {
        let website = try XCTUnwrap(SizePreset.byId("website"))
        XCTAssertEqual(website.category, "Marketing")
        XCTAssertEqual(website.w, 1366)
        XCTAssertEqual(website.h, 768)
        XCTAssertEqual(ExportSuggestion.suggest(website.makeDesign()), "html")
        XCTAssertEqual(ExportSuggestion.suggest(try design()), "html")
        XCTAssertEqual(ExportSuggestion.suggest(Design(width: 1080, height: 1080)), "png")
        let settings = ExportLast(format: "html", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false,
                                  pages: "all", html: HTMLExporter.Settings(nav: false))
        XCTAssertTrue(settings.json.contains(#""html":{"nav":false,"mobileStack":true,"embedMedia":true,"layout":"scroll","autoplay":0.0,"loop":false}"#))
        XCTAssertEqual(ExportLast.read(settings.json), settings)
        XCTAssertEqual(ExportLast.read(#"{"format":"html"}"#)?.html, HTMLExporter.Settings())
        XCTAssertEqual(ExportLast.fileTypes.suffix(3), ["html", "docx", "m4a"])
        XCTAssertEqual(ContentLibrary.templates.filter { $0.width == 1366 && $0.height == 768 }.count, 6)
    }
}
