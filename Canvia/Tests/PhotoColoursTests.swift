// Round 32's Apply colours to page, with the rows the Android twin's
// PhotoColoursTest holds too: a page and a photo's palette in, the page
// recoloured by the theme's lightness mapping out — turned one place a tap,
// photos, locked things and the photo itself kept, and words that would
// drop under AA given an ink that reads.

import XCTest
@testable import Canvia

final class PhotoColoursTests: XCTestCase {

    private let palette = ["#112233", "#ddeeff", "#88aa44"]

    private func page() -> Page {
        var shape = Element.shape("rect", w: 200, h: 200)
        shape.id = "a"
        shape.fill = .solid("#000000")
        var words = Element.text("Hello", fontSize: 42, w: 300)
        words.id = "t"
        words.x = 500; words.y = 500
        words.color = "#333333"
        var photo = Element.image("asset:p", w: 300, h: 200)
        photo.id = "p"
        photo.x = 600
        var locked = Element.shape("rect", w: 100, h: 100)
        locked.id = "l"
        locked.x = 300
        locked.fill = .solid("#ff0000")
        locked.locked = true
        return Page(id: "p1", background: .color("#ffffff"), elements: [shape, words, photo, locked])
    }

    private func element(_ page: Page, _ id: String) -> Element? {
        page.elements.first { $0.id == id }
    }

    func testThePaletteTurnsAPlaceATap() {
        XCTAssertEqual(PhotoColours.turned(palette, by: 0), ["#112233", "#88aa44", "#ddeeff"], "dark to light")
        XCTAssertEqual(PhotoColours.turned(palette, by: 1), ["#88aa44", "#ddeeff", "#112233"])
        XCTAssertEqual(PhotoColours.turned(palette, by: 2), ["#ddeeff", "#112233", "#88aa44"])
        XCTAssertEqual(PhotoColours.turned(palette, by: 3), PhotoColours.turned(palette, by: 0), "round again")
        XCTAssertEqual(PhotoColours.turned([], by: 1), [])
    }

    func testThePageColoursAreItsOwnButThePhotosAndTheLocked() {
        XCTAssertEqual(PhotoColours.pageColours(page(), photo: "p"), ["#ffffff", "#000000", "#333333"])
    }

    func testTheFirstTapMapsByLightness() {
        let out = PhotoColours.applied(page(), palette: palette, turn: 0, photo: "p")
        XCTAssertEqual(out.background, .color("#ddeeff"))
        XCTAssertEqual(element(out, "a")?.fill, .solid("#112233"))
        XCTAssertEqual(element(out, "l")?.fill, .solid("#ff0000"), "locked: kept")
        XCTAssertEqual(element(out, "p"), element(page(), "p"), "the photo: kept")
        // #88aa44 on #ddeeff falls under AA for large text: given an ink
        // that reads there instead.
        let words = element(out, "t")
        XCTAssertNotEqual(words?.color, "#88aa44")
        XCTAssertGreaterThanOrEqual(ContrastAudit.ratio(words?.color ?? "#000000", "#ddeeff"), 3)
    }

    func testTheNextTapGivesAnotherCombination() {
        let out = PhotoColours.applied(page(), palette: palette, turn: 1, photo: "p")
        XCTAssertEqual(out.background, .color("#112233"))
        XCTAssertEqual(element(out, "a")?.fill, .solid("#88aa44"))
        XCTAssertEqual(element(out, "t")?.color, "#ddeeff", "reads on the dark page as it is")
    }

    func testNothingToGoOn() {
        XCTAssertEqual(PhotoColours.applied(page(), palette: [], turn: 0, photo: "p"), page())
    }

    func testWhatOffersIt() {
        XCTAssertTrue(PhotoColours.offered(Element.image("asset:p")))
        XCTAssertFalse(PhotoColours.offered(Element.image("qr:https://canvia.app")))
        var frame = Element.image("asset:p")
        frame.src = nil
        XCTAssertFalse(PhotoColours.offered(frame), "an empty frame")
        XCTAssertFalse(PhotoColours.offered(Element.shape("rect")))
    }

    func testEachTapIsOneStepNamedApplyPhotoColours() {
        var d = Design(title: "colours", width: 1080, height: 1080)
        d.pages = [page()]
        let s = DesignStore(design: d)
        s.selection = ["p"]
        XCTAssertNotNil(s.photoForColours)
        s.selection = ["a"]
        XCTAssertNil(s.photoForColours, "a shape offers none")
        s.photoColourTurn = 4
        s.selection = ["p"]
        XCTAssertEqual(s.photoColourTurn, 0, "a new selection starts again")
    }
}
