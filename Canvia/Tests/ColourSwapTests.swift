// One colour of a selection changed on its own, and Change all across the
// design: the colours read, the swap that keeps each one's alpha, the count
// Change all offers, and the store's steps, in rows the Android twin's
// tests hold too.

import XCTest
@testable import Canvia

final class ColourSwapTests: XCTestCase {

    /// A red rectangle with a green border, a gradient from red to a
    /// half-see-through blue, green words with one dark blue word and a
    /// clear shadow, and a red line.
    private func sample() -> [Element] {
        var a = Element.shape("rect")
        a.fill = .solid("#FF0000")
        a.stroke = "#00ff00"
        a.strokeWidth = 2
        var b = Element.shape("circle")
        b.fill = Paint(kind: "gradient", color: nil, angle: 90,
                       stops: [GradientStop(offset: 0, color: "#f00"), GradientStop(offset: 1, color: "#0000ff80")])
        var t = Element.text("Hi")
        t.color = "#00FF00"
        t.spans = [TextSpan(start: 0, end: 1, color: "#123456")]
        t.shadow = Shadow(color: "#00000000")
        var l = Element.line()
        l.color = "#ff0000"
        return [a, b, t, l]
    }

    // MARK: colours

    func testColoursAreDistinctNormalisedMostUsedFirstAndSkipClearOnes() {
        // Red three times, green twice, then blue and dark blue once each in
        // the order met; the clear shadow is no colour in use.
        XCTAssertEqual(ColourSwap.colours(sample()), ["#ff0000", "#00ff00", "#0000ff", "#123456"])
    }

    func testColoursStopAtTwelve() {
        let shapes = (0..<13).map { i -> Element in
            var e = Element.shape("rect")
            e.fill = .solid(String(format: "#0000%02x", i))
            return e
        }
        let colours = ColourSwap.colours(shapes)
        XCTAssertEqual(colours.count, 12)
        XCTAssertEqual(colours.first, "#000000")
        XCTAssertEqual(colours.last, "#00000b")
    }

    func testPatternsAndPhotosGiveNoSwatch() {
        var e = Element.shape("rect")
        e.fill = .pattern("dots", color: "#ff0000", secondary: "#ffffff")
        XCTAssertEqual(ColourSwap.colours([e]), [])
        XCTAssertEqual(ColourSwap.colours([Element.image("media:x")]), [])
    }

    func testParseReadsShortLongAndAlphaForms() {
        XCTAssertEqual(ColourSwap.parse("#F0a")?.rgb, "#ff00aa")
        XCTAssertNil(ColourSwap.parse("#F0a")?.alpha)
        XCTAssertEqual(ColourSwap.parse("#12345680")?.rgb, "#123456")
        XCTAssertEqual(ColourSwap.parse("#12345680")?.alpha, "80")
        XCTAssertNil(ColourSwap.parse("red"))
        XCTAssertNil(ColourSwap.parse("#12345"))
    }

    // MARK: swapping

    func testSwapReplacesEveryUseAndKeepsEachAlpha() {
        let out = ColourSwap.swapped(sample(), from: "#FF0000", to: "#00AAFF")
        XCTAssertEqual(out[0].fill?.color, "#00aaff")
        XCTAssertEqual(out[0].stroke, "#00ff00")
        XCTAssertEqual(out[1].fill?.stops?.map(\.color), ["#00aaff", "#0000ff80"])
        XCTAssertEqual(out[3].color, "#00aaff")
        // What was not the colour is left as written.
        XCTAssertEqual(out[2].color, "#00FF00")
        XCTAssertEqual(out[2].spans?.first?.color, "#123456")

        var see = Element.shape("rect")
        see.fill = .solid("#ff000080")
        see.shadow = Shadow(color: "#FF0000")
        let swapped = ColourSwap.swapped([see], from: "#ff0000", to: "#00aaff")[0]
        XCTAssertEqual(swapped.fill?.color, "#00aaff80")
        XCTAssertEqual(swapped.shadow?.color, "#00aaff")
    }

    func testSwapReachesWordsAndLeavesWhatHasNoneOfTheColourAlone() {
        let input = sample()
        let out = ColourSwap.swapped(input, from: "#123456", to: "#abcdef")
        XCTAssertEqual(out[2].spans?.first?.color, "#abcdef")
        XCTAssertEqual(out[2].spans?.first?.start, 0)
        XCTAssertEqual(out[0], input[0])
        XCTAssertEqual(out[1], input[1])
        XCTAssertEqual(out[3], input[3])
    }

    func testCountTakesEveryPageAndLeavesOutLockedOnes() {
        var red = Element.shape("rect")
        red.fill = .solid("#ff0000")
        var line = Element.line()
        line.color = "#F00"
        var locked = red
        locked.id = "locked"
        locked.locked = true
        var held = red
        held.id = "held"
        held.lockPosition = true
        var d = Design(title: "d", width: 400, height: 300)
        d.pages = [Page(elements: [red, line]), Page(elements: [locked, held])]
        // The fully locked one keeps its colours; a position lock does not.
        XCTAssertEqual(ColourSwap.count(d, from: "#ff0000"), 3)
        XCTAssertEqual(ColourSwap.count(d, from: "#00ff00"), 0)
    }

    // MARK: the store

    @MainActor
    private func store(_ elements: [Element], more: [Element] = []) -> DesignStore {
        var d = Design(title: "d", width: 400, height: 300)
        d.pages = [Page(elements: elements)] + (more.isEmpty ? [] : [Page(elements: more)])
        let store = DesignStore(design: d)
        store.selection = Set(elements.map(\.id))
        return store
    }

    @MainActor
    func testASwapIsOneStepOnTheSelectionOnly() {
        var a = Element.shape("rect")
        a.fill = .solid("#ff0000")
        a.stroke = "#00ff00"
        a.strokeWidth = 2
        var b = Element.shape("circle")
        b.fill = .solid("#ff0000")
        let s = store([a, b])
        s.swapSelectionColour(from: "#ff0000", to: "#0000ff")
        XCTAssertEqual(s.page.elements.map { $0.fill?.color }, ["#0000ff", "#0000ff"])
        XCTAssertEqual(s.page.elements[0].stroke, "#00ff00")
        s.undo()
        XCTAssertEqual(s.page.elements.map { $0.fill?.color }, ["#ff0000", "#ff0000"])
    }

    @MainActor
    func testTheWheelSwapsFromWhereTheStepBeganSoNoOtherColourIsTakenAlong() {
        var a = Element.shape("rect")
        a.fill = .solid("#ff0000")
        a.stroke = "#00ff00"
        a.strokeWidth = 2
        let s = store([a])
        // A drag passing through the border's green, and on to blue.
        s.swapSelectionColourTransient(from: "#ff0000", to: "#00ff00")
        s.swapSelectionColourTransient(from: "#ff0000", to: "#0000ff")
        s.commit()
        XCTAssertEqual(s.page.elements[0].fill?.color, "#0000ff")
        XCTAssertEqual(s.page.elements[0].stroke, "#00ff00")
        s.undo()
        XCTAssertEqual(s.page.elements[0].fill?.color, "#ff0000")
        XCTAssertFalse(s.canUndo, "the whole drag was one step")
    }

    @MainActor
    func testChangeAllSwapsEveryPageAsOneStepWithAnUndo() {
        var a = Element.shape("rect")
        a.fill = .solid("#ff0000")
        var other = Element.text("Sale")
        other.color = "#ff0000"
        var locked = Element.shape("circle")
        locked.fill = .solid("#ff0000")
        locked.locked = true
        let s = store([a], more: [other, locked])
        s.swapSelectionColour(from: "#ff0000", to: "#0000ff")
        XCTAssertEqual(ColourSwap.count(s.design, from: "#ff0000"), 1, "Change all (1)")
        XCTAssertEqual(s.swapColourEverywhere(from: "#ff0000", to: "#0000ff"), 1)
        XCTAssertEqual(s.design.pages[1].elements[0].color, "#0000ff")
        XCTAssertEqual(s.design.pages[1].elements[1].fill?.color, "#ff0000", "a locked one keeps its colour")
        XCTAssertEqual(s.announcement, "Changed the colour of 1 element")
        XCTAssertTrue(s.announcementUndoes)
        s.undo()
        XCTAssertEqual(s.design.pages[1].elements[0].color, "#ff0000")
        XCTAssertEqual(s.design.pages[0].elements[0].fill?.color, "#0000ff", "the selection's own swap stays")
        XCTAssertEqual(DesignStore.changedAllNote(3), "Changed the colour of 3 elements")
    }

    @MainActor
    func testChangeAllWithNothingLeftChangesNothing() {
        var a = Element.shape("rect")
        a.fill = .solid("#ff0000")
        let s = store([a])
        s.swapSelectionColour(from: "#ff0000", to: "#0000ff")
        XCTAssertEqual(s.swapColourEverywhere(from: "#ff0000", to: "#0000ff"), 0)
        s.undo()
        XCTAssertFalse(s.canUndo)
    }
}
