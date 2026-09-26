// The palette that goes with a page, the brand kit as a theme palette, and
// colours said in words — each as the Android twin has it.

import XCTest
@testable import Canvia

final class PalettesAndColourNamesTests: XCTestCase {

    private func page(background: Background, _ elements: [Element]) -> Page {
        var page = Page(elements: elements)
        page.background = background
        return page
    }

    private func shape(fill: Paint?, stroke: String? = nil, width: Double = 0) -> Element {
        var el = Element.shape("rect")
        el.fill = fill
        el.stroke = stroke
        el.strokeWidth = width
        return el
    }

    private func text(_ color: String) -> Element {
        var el = Element.text("Hello")
        el.color = color
        return el
    }

    // MARK: a page's colours

    /// Background, then back to front; repeats kept; a border only when it
    /// has a width; photos and stickers give nothing.
    func testAPageGivesTheColoursItPaintsWith() {
        let gradient = Paint(kind: "gradient", color: nil, angle: 90,
                             stops: [GradientStop(offset: 0, color: "#111111"), GradientStop(offset: 1, color: "#222222")])
        var line = Element.line()
        line.color = "#333333"
        let colours = ColorTools.pageColours(page(background: .gradient(gradient), [
            text("#444444"),
            line,
            shape(fill: .solid("#555555"), stroke: "#666666", width: 2),
            shape(fill: .solid("#555555"), stroke: "#777777", width: 0),
            shape(fill: gradient),
            shape(fill: .clear),
            Element.image("media:x"),
            Element.sticker("🙂"),
        ]))
        XCTAssertEqual(colours, ["#111111", "#222222", "#444444", "#333333", "#555555", "#666666",
                                 "#555555", "#111111", "#222222"])
        XCTAssertTrue(ColorTools.pageColours(page(background: .image("asset:x"), [])).isEmpty)
    }

    // MARK: the suggestion

    func testThePaletteClosestToThePageIsSuggested() throws {
        let blues = Palette(id: "blues", name: "Blues", colors: ["#03045e", "#0077b6", "#90e0ef"])
        let greens = Palette(id: "greens", name: "Greens", colors: ["#1b4332", "#2d6a4f", "#b7e4c7"])
        let library = [blues, greens]
        let sea = page(background: .color("#90e0ef"), [text("#03045e"), shape(fill: .solid("#0077b6"))])
        XCTAssertEqual(ColorTools.suggestedPalette(for: sea, from: library)?.id, "blues")
        let wood = page(background: .color("#f1faee"), [text("#1b4332"), shape(fill: .solid("#2d6a4f"))])
        XCTAssertEqual(ColorTools.suggestedPalette(for: wood, from: library)?.id, "greens")

        // Nothing to go by: the first palette.
        let photo = page(background: .image("asset:x"), [Element.image("media:x")])
        XCTAssertEqual(ColorTools.suggestedPalette(for: photo, from: [greens, blues])?.id, "greens")
        // A tie goes to the earlier; a palette of nothing readable is passed over.
        let twin = Palette(id: "twin", name: "Twin", colors: blues.colors)
        XCTAssertEqual(ColorTools.suggestedPalette(for: sea, from: [blues, twin])?.id, "blues")
        let broken = Palette(id: "broken", name: "Broken", colors: ["teal-ish"])
        XCTAssertEqual(ColorTools.suggestedPalette(for: sea, from: [broken, greens, blues])?.id, "blues")
        XCTAssertNil(ColorTools.suggestedPalette(for: sea, from: []))
    }

    /// The Android twin's pinned pages, against this app's own palettes.
    func testTheLibrarySuggestsOceanForTheSeaAndForestForTheWoods() throws {
        let sea = page(background: .color("#ffffff"),
                       [shape(fill: .solid("#0077b6")), shape(fill: .solid("#00b4d8")), text("#023e8a")])
        XCTAssertEqual(ColorTools.suggestedPalette(for: sea)?.name, "Deep Current")
        let woods = page(background: .color("#f1faee"), [shape(fill: .solid("#2d6a4f")), text("#1b4332")])
        XCTAssertEqual(ColorTools.suggestedPalette(for: woods)?.name, "Botanical Grove")
    }

    func testAColourReadsFromThreeSixOrEightDigits() throws {
        let short = try XCTUnwrap(ColorTools.rgb255("#abc"))
        XCTAssertEqual([short.r, short.g, short.b], [0xaa, 0xbb, 0xcc])
        let alpha = try XCTUnwrap(ColorTools.rgb255("#10203080"))
        XCTAssertEqual([alpha.r, alpha.g, alpha.b], [0x10, 0x20, 0x30], "alpha last, ignored")
        XCTAssertNil(ColorTools.rgb255("#12345"))
        XCTAssertNil(ColorTools.rgb255("#ggg"))
        XCTAssertEqual(ColorTools.redmean((0, 0, 0), (0, 0, 0)), 0)
        XCTAssertEqual(ColorTools.redmean((0, 10, 0), (0, 0, 0)), 400, "green weighs four")
    }

    // MARK: brand kit

    func testTheBrandKitIsAPaletteOnceItHasTwoColours() throws {
        var kit = BrandKit()
        XCTAssertNil(kit.palette)
        kit.addColor("#112233")
        XCTAssertNil(kit.palette, "one colour is nothing to map a design onto")
        kit.addColor("#445566")
        let palette = try XCTUnwrap(kit.palette)
        XCTAssertEqual(palette.id, "brand-kit")
        XCTAssertEqual(palette.name, "Brand kit")
        XCTAssertEqual(palette.colors, ["#445566", "#112233"], "in kit order, newest first")
    }

    // MARK: colours in words

    /// Android's pinned names, word for word.
    func testSwatchesAreNamedAsTheAndroidTwinNamesThem() {
        let pinned: [(String, String)] = [
            ("#00a000", "green"), ("#0077b6", "blue"), ("#f6d55c", "yellow"), ("#ff8c00", "orange"),
            ("#1e8c7e", "teal"), ("#0d1216", "black"), ("#7c828a", "grey"), ("#023e8a", "dark blue"),
            ("#90e0ef", "light blue"), ("#3a3f47", "dark grey"), ("#e3e6ea", "light grey"),
            ("#1b4332", "dark green"), ("#6b4bff", "purple"), ("#9aa4b2", "grey"), ("#ffb3b3", "pink"),
            ("not a colour", "colour"), ("#ff000080", "red"),
        ]
        for (hex, name) in pinned {
            XCTAssertEqual(ElementNames.colourName(hex), name, hex)
        }
        XCTAssertEqual(ElementNames.spokenColour("#023e8a"), "Dark blue")
        XCTAssertEqual(ElementNames.spokenColour(nil), "Colour")
    }
}
