// Make brand guidelines: one kit laid out as an A4 landscape design, page by
// page, frame by frame — the same kit and the same frames as the Android
// twin's BrandGuidelinesTest.

import XCTest
@testable import Canvia

final class BrandGuidelinesTests: XCTestCase {

    private func kit() -> BrandKit {
        var kit = BrandKit()
        kit.name = "Acme"
        kit.palettes = [BrandPalette(name: "Core", colors: ["#e53935", "#1e88e5", "#ffffff", "#16181d", "#fdd835"]),
                        BrandPalette(name: "Empty", colors: [])]
        kit.fonts.heading = BrandFont(family: "playfair-display", weight: 700, size: 96)
        kit.fonts.body = BrandFont(family: "lato", weight: 400)
        kit.logos = ["media:logo1", "media:logo2", "media:logo3"]
        kit.photos = ["media:photo1", "media:photo2"]
        kit.graphics = ["media:shape1", "svg:icon1"]
        return kit
    }

    private func frame(_ el: Element) -> [Double] { [el.x, el.y, el.w, el.h] }

    private func assertFrame(_ el: Element, _ want: [Double], file: StaticString = #filePath, line: UInt = #line) {
        let got = frame(el)
        for (a, b) in zip(got, want) { XCTAssertEqual(a, b, accuracy: 0.001, "\(got) vs \(want)", file: file, line: line) }
    }

    func testTheDesignIsA4LandscapeInMillimetres() {
        let d = BrandGuidelines.design(kit(), now: 1_700_000_000_000)
        XCTAssertEqual(d.title, "Acme guidelines")
        XCTAssertEqual(d.width, 3508)
        XCTAssertEqual(d.height, 2480)
        XCTAssertEqual(d.unit, "mm")
        XCTAssertEqual(d.dpi, 300)
        XCTAssertEqual(d.createdAt, 1_700_000_000_000)
        XCTAssertFalse(d.titleAuto)
        // Cover, one palette (the empty one has no page), typography, two
        // pages of logos, imagery.
        XCTAssertEqual(d.pages.count, 6)
    }

    func testCover() {
        let cover = BrandGuidelines.design(kit(), now: 0).pages[0]
        XCTAssertEqual(cover.elements.count, 3 + 5)
        assertFrame(cover.elements[0], [200, 200, 600, 600])
        XCTAssertEqual(cover.elements[0].cropFit, true)
        assertFrame(cover.elements[1], [200, 1000, 3108, 100])
        XCTAssertEqual(cover.elements[1].text, "Brand guidelines")
        assertFrame(cover.elements[2], [200, 1120, 3108, 325])
        XCTAssertEqual(cover.elements[2].text, "Acme")
        // The title role falls back to the heading's face.
        XCTAssertEqual(cover.elements[2].fontFamily, "playfair-display")
        XCTAssertEqual(cover.elements[1].fontFamily, "lato")
        assertFrame(cover.elements[3], [200, 2080, 621.6, 200])
        assertFrame(cover.elements[7], [200 + 4 * 621.6, 2080, 621.6, 200])
        XCTAssertEqual(cover.elements[7].fill?.color, "#fdd835")
    }

    func testColoursPage() {
        let page = BrandGuidelines.design(kit(), now: 0).pages[1]
        XCTAssertEqual(page.elements[0].text, "Colours")
        assertFrame(page.elements[0], [200, 200, 3108, 75])
        XCTAssertEqual(page.elements[1].text, "Core")
        assertFrame(page.elements[1], [200, 300, 3108, 175])
        // Swatch 1 and its words, then swatch 5 starting the second row.
        assertFrame(page.elements[2], [200, 560, 717, 280])
        XCTAssertEqual(page.elements[2].stroke, "#d6dbe4")
        assertFrame(page.elements[3], [200, 864, 717, 200])
        assertFrame(page.elements[4], [997, 560, 717, 280])
        assertFrame(page.elements[10], [200, 1120, 717, 280])
        assertFrame(page.elements[11], [200, 1424, 717, 200])
    }

    func testASwatchSaysItsCodes() {
        XCTAssertEqual(BrandGuidelines.describe("#FFFFFF"), "White\nHEX #ffffff\nRGB 255 255 255\nCMYK 0 0 0 0")
        let black = BrandGuidelines.describe("#000000").split(separator: "\n").map(String.init)
        XCTAssertEqual(Array(black.dropFirst()), ["HEX #000000", "RGB 0 0 0", "CMYK 0 0 0 100"])
    }

    func testTypographyPage() {
        let page = BrandGuidelines.design(kit(), now: 0).pages[2]
        XCTAssertEqual(page.elements.count, 2 + 2 * 2)
        XCTAssertEqual(page.elements[2].text, "Heading · playfair-display · 700 · 312 px")
        assertFrame(page.elements[2], [200, 560, 3108, 50])
        let heading = page.elements[3]
        assertFrame(heading, [200, 624, 3108, 275])
        XCTAssertEqual(heading.fontSize, 220)
        XCTAssertEqual(heading.fontFamily, "playfair-display")
        XCTAssertEqual(heading.fontWeight, 700)
        XCTAssertEqual(page.elements[4].text, "Body · lato · 400 · 98 px")
        assertFrame(page.elements[4], [200, 1420, 3108, 50])
        XCTAssertEqual(page.elements[5].fontSize, 98.2)
        XCTAssertEqual(page.elements[5].y, 1484)
    }

    /// No faces: a heading and body text in the default face.
    func testTypographyWithNoFaces() {
        var bare = kit()
        bare.fonts = BrandFonts()
        XCTAssertEqual(BrandGuidelines.roles(bare), [.heading, .body])
        let page = BrandGuidelines.design(bare, now: 0).pages[2]
        XCTAssertEqual(page.elements[3].fontFamily, "sans")
        XCTAssertEqual(page.elements[3].fontWeight, 700)
    }

    func testLogosOnLightAndDarkWithClearSpace() {
        let d = BrandGuidelines.design(kit(), now: 0)
        let first = d.pages[3]
        XCTAssertEqual(first.elements.count, 2 + 2 * 4)
        XCTAssertEqual(first.elements[0].text, "Logos")
        assertFrame(first.elements[2], [200, 560, 1514, 820])
        XCTAssertEqual(first.elements[2].fill?.color, "#ffffff")
        assertFrame(first.elements[3], [364, 724, 1186, 492])
        XCTAssertEqual(first.elements[3].src, "media:logo1")
        assertFrame(first.elements[4], [1794, 560, 1514, 820])
        XCTAssertEqual(first.elements[4].fill?.color, "#16181d")
        assertFrame(first.elements[6], [200, 1460, 1514, 820])
        XCTAssertEqual(d.pages[4].elements.count, 2 + 4)
        XCTAssertEqual(d.pages[4].elements[3].src, "media:logo3")
    }

    /// Photos fill their cells; a graphic shows whole; an SVG is left out.
    func testImagery() {
        let page = BrandGuidelines.design(kit(), now: 0).pages[5]
        XCTAssertEqual(page.elements.map(\.src), [nil, nil, "media:photo1", "media:photo2", "media:shape1"])
        let cellW = (3108.0 - 160) / 3
        assertFrame(page.elements[2], [200, 560, cellW, 820])
        assertFrame(page.elements[4], [200 + 2 * (cellW + 80), 560, cellW, 820])
        XCTAssertNil(page.elements[2].cropFit)
        XCTAssertEqual(page.elements[4].cropFit, true)
    }

    func testAnEmptyKitIsACoverAndTypography() {
        var empty = BrandKit()
        empty.name = "Blank"
        let d = BrandGuidelines.design(empty, now: 0)
        XCTAssertEqual(d.pages.count, 2)
        XCTAssertEqual(d.pages[0].elements.count, 2)
    }

    // MARK: the shared fixture

    /// Shared: the same kit gives the same pages and frames on both phones —
    /// the Android twin's fixtures/brand-guidelines.json.
    func testTheSharedFixture() throws {
        let fixture = try SharedFixture.object("brand-guidelines")
        let kit = try JSONDecoder().decode(BrandKit.self, from: SharedFixture.encoded(try XCTUnwrap(fixture["kit"])))
        let design = BrandGuidelines.design(kit, now: 1000)
        XCTAssertEqual(design.title, fixture["title"] as? String)
        XCTAssertEqual(design.width, fixture["width"] as? Double)
        XCTAssertEqual(design.height, fixture["height"] as? Double)
        XCTAssertEqual(design.unit, fixture["unit"] as? String)
        let pages = try XCTUnwrap(fixture["pages"] as? [[[String: Any]]])
        XCTAssertEqual(design.pages.count, pages.count)
        for (p, list) in pages.enumerated() where design.pages.indices.contains(p) {
            let elements = design.pages[p].elements
            XCTAssertEqual(elements.count, list.count, "page \(p)")
            for (i, o) in list.enumerated() where elements.indices.contains(i) {
                let el = elements[i]
                let at = "page \(p) element \(i)"
                XCTAssertEqual(el.type.rawValue, o["type"] as? String, at)
                let frame = o["frame"] as? [Double] ?? []
                assertFrame(el, frame)
                if let text = o["text"] as? String { XCTAssertEqual(el.text, text, at) }
                if let font = o["font"] as? String { XCTAssertEqual(el.fontFamily, font, at) }
                if let size = o["size"] as? Double { XCTAssertEqual(el.fontSize ?? 0, size, accuracy: 1e-3, at) }
                if let src = o["src"] as? String { XCTAssertEqual(el.src, src, at) }
                if let fill = o["fill"] as? String { XCTAssertEqual(el.fill?.color, fill, at) }
            }
        }
    }
}
