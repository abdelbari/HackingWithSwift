// One font swapped for another throughout a design — the rows the Android
// twin's FontSwapTest runs too.

import XCTest
@testable import Canvia

@MainActor
final class FontSwapTests: XCTestCase {

    private func text(_ words: String, _ font: String, y: Double = 0) -> Element {
        var el = Element.text(words, fontSize: 30, w: 300)
        el.fontFamily = font
        el.y = y
        return el
    }

    private func design() -> Design {
        var d = Design(title: "fonts", width: 800, height: 600)
        var worded = text("Big sale", "lora", y: 300)
        worded.setSpans([TextSpan(start: 0, end: 3, font: "serif")])
        d.pages[0].elements = [text("One", "serif"), text("Two", "serif", y: 100), text("Three", "serif", y: 200), worded]
        return d
    }

    /// Shared: 'serif' on three boxes and one span is four places, and
    /// replaced by 'sans' all four change.
    func testEveryPlaceAFontIsUsedIsReplaced() {
        let start = design()
        XCTAssertEqual(FontSwap.uses(start), [FontSwap.Use(family: "serif", count: 4), FontSwap.Use(family: "lora", count: 1)])
        let after = FontSwap.replaced(start, from: "serif", to: "sans", heightFor: { _ in 40 })
        let els = after.pages[0].elements
        XCTAssertEqual(els.prefix(3).map(\.fontFamily), ["sans", "sans", "sans"])
        XCTAssertEqual(els[3].fontFamily, "lora")
        XCTAssertEqual(els[3].liveSpans.first?.font, "sans")
        XCTAssertEqual(els.prefix(3).map(\.h), [40, 40, 40], "measured again")
        XCTAssertEqual(FontSwap.count(after, family: "serif"), 0)
        XCTAssertEqual(FontSwap.count(after, family: "sans"), 4)
    }

    /// Shared: a locked box, and a locked page, are left as they are.
    func testALockedBoxIsUnchanged() {
        var start = design()
        start.pages[0].elements[1].locked = true
        XCTAssertEqual(FontSwap.count(start, family: "serif"), 3)
        let after = FontSwap.replaced(start, from: "serif", to: "sans", heightFor: { _ in 40 })
        XCTAssertEqual(after.pages[0].elements[1], start.pages[0].elements[1])
        XCTAssertEqual(after.pages[0].elements[0].fontFamily, "sans")
        var locked = design()
        locked.pages[0].locked = true
        XCTAssertEqual(FontSwap.replaced(locked, from: "serif", to: "sans", heightFor: { _ in 40 }), locked)
    }

    /// Shared: a weight the new font lacks goes to the nearest it has,
    /// ties to the heavier: Light in Roboto is Regular in Lora.
    func testAWeightGoesToTheNearestTheNewFontHas() {
        var d = Design(title: "weights", width: 800, height: 600)
        var light = text("Light", "roboto")
        light.fontWeight = 300
        var heavy = text("Heavy", "roboto", y: 100)
        heavy.fontWeight = 900
        d.pages[0].elements = [light, heavy]
        let after = FontSwap.replaced(d, from: "roboto", to: "lora", heightFor: { _ in 40 })
        XCTAssertEqual(after.pages[0].elements.map(\.fontWeight), [400, 700])
    }

    /// Shared: no weight set, replaced by a family with only a Bold, is set
    /// at 700; an alias is stored as the family it means.
    func testNoWeightSetTakesTheOnlyWeightANewFamilyHas() throws {
        let bytes = try Data(contentsOf: try XCTUnwrap(FontLibrary.bundledURL("lora-700.ttf")))
        defer { FontStore.remove(CustomFonts.sha12(bytes)) }
        let heavy = try FontStore.add(bytes).get()
        XCTAssertEqual(FontLibrary.weights(heavy), [700])
        var d = Design(title: "weights", width: 800, height: 600)
        d.pages[0].elements = [text("None", "serif")]
        d.pages[0].elements[0].fontWeight = nil
        let after = FontSwap.replaced(d, from: "serif", to: heavy, heightFor: { _ in 40 })
        XCTAssertEqual(after.pages[0].elements[0].fontWeight, 700)
        XCTAssertEqual(after.pages[0].elements[0].fontFamily, heavy)
        let aliased = FontSwap.replaced(d, from: "serif", to: "didone", heightFor: { _ in 40 })
        XCTAssertEqual(aliased.pages[0].elements[0].fontFamily, "playfair-display")
    }

    /// A chart's own font is swapped with its labels, and an alias counts
    /// as the family it means.
    func testAChartsFontAndAnAliasAreSwapped() {
        var d = Design(title: "chart", width: 800, height: 600)
        let spec = ChartSpec(id: "chart_f", kind: "column", data: "A, 1", font: "didone")
        var label = text("A", "didone")
        label.chart = spec
        label.chartPart = "label"
        d.pages[0].elements = [label]
        XCTAssertEqual(FontSwap.uses(d), [FontSwap.Use(family: "playfair-display", count: 2)])
        let after = FontSwap.replaced(d, from: "playfair-display", to: "lora", heightFor: { _ in 40 })
        XCTAssertEqual(after.pages[0].elements[0].fontFamily, "lora")
        XCTAssertEqual(after.pages[0].elements[0].chart?.font, "lora")
    }

    /// Shared: a chart's spec counts once a chart, beside its labels; what
    /// is counted is what changes, so a locked page's boxes are not.
    func testAChartCountsOnceAndALockedPageNotAtAll() {
        var d = Design(title: "chart", width: 800, height: 600)
        let spec = ChartSpec(id: "chart_f", kind: "column", data: "A, 1", font: "didone")
        var label = text("A", "didone")
        label.chart = spec
        label.chartPart = "label"
        var second = text("B", "serif", y: 100)
        second.chart = spec
        second.chartPart = "label"
        d.pages[0].elements = [label, second]
        XCTAssertEqual(FontSwap.uses(d), [FontSwap.Use(family: "playfair-display", count: 2),
                                          FontSwap.Use(family: "serif", count: 1)])
        var locked = design()
        locked.pages[0].locked = true
        XCTAssertEqual(FontSwap.count(locked, family: "serif"), 0)
    }

    /// One step, named Replace font, that one Undo takes back.
    func testReplaceFontIsOneStepNamedReplaceFont() {
        let store = DesignStore(design: design())
        store.measure = { _ in 40 }
        XCTAssertEqual(store.replaceFontEverywhere(from: "serif", to: "sans"), 4)
        XCTAssertEqual(store.undoLabel, "Replace font")
        store.undo()
        XCTAssertEqual(store.design.pages[0].elements.prefix(3).map(\.fontFamily), ["serif", "serif", "serif"])
        XCTAssertEqual(store.replaceFontEverywhere(from: "mono", to: "sans"), 0, "nothing uses it")
    }
}
