// Round 32's Apply colours to page, with the rows the Android twin's
// PhotoColoursTest holds too — the same page, palette and expectations: a
// page and a photo's palette in, the page recoloured by the theme's
// lightness mapping out — turned one place a tap, photos, locked things and
// the photo itself kept, and words that would drop under AA given an ink
// that reads.

import XCTest
@testable import Canvia

final class PhotoColoursTests: XCTestCase {

    // Darkest first: #112233, #cc4400, #ddeeff.
    private let palette = ["#112233", "#ddeeff", "#cc4400"]

    private func page() -> Page {
        var shape = Element.shape("rectangle", w: 100, h: 100)
        shape.id = "s"
        shape.x = 0; shape.y = 0
        shape.fill = .solid("#ff0000")
        var words = Element.text("Hello", fontSize: 12, w: 200)
        words.id = "t"
        words.x = 500; words.y = 500; words.h = 50
        words.color = "#000000"
        var photo = Element.image("media:p", w: 100, h: 100)
        photo.id = "p"
        photo.x = 600; photo.y = 0
        var locked = Element.shape("rectangle", w: 100, h: 100)
        locked.id = "k"
        locked.x = 0; locked.y = 600
        locked.fill = .solid("#00ff00")
        locked.locked = true
        return Page(id: "pg", background: .color("#ffffff"), elements: [shape, words, photo, locked])
    }

    func testThePagesColoursGoOntoThePhotosByLightness() {
        let out = PhotoColours.applied(page(), palette: palette, turn: 0, photo: "p")
        // Rows: the page's colour, darkest to lightest -> the palette's.
        XCTAssertEqual(out.background, .color("#ddeeff"))
        XCTAssertEqual(out.elements[0].fill?.color, "#cc4400")
        XCTAssertEqual(out.elements[1].color, "#112233")
        // The photo and what is locked keep theirs.
        XCTAssertEqual(out.elements[2], page().elements[2])
        XCTAssertEqual(out.elements[3], page().elements[3])
    }

    func testEachTapTurnsThePaletteAndTextThatWouldNotReadIsGivenAnInkThatDoes() {
        let out = PhotoColours.applied(page(), palette: palette, turn: 1, photo: "p")
        XCTAssertEqual(out.background, .color("#112233"))
        XCTAssertEqual(out.elements[0].fill?.color, "#ddeeff")
        // #cc4400 on #112233 is under 4.5:1 for small text: white instead.
        XCTAssertEqual(out.elements[1].color, "#ffffff")
        let again = PhotoColours.applied(page(), palette: palette, turn: 2, photo: "p")
        XCTAssertEqual(again.background, .color("#cc4400"))
        XCTAssertEqual(again.elements[0].fill?.color, "#112233")
        // Round again: the first pairing.
        XCTAssertEqual(PhotoColours.applied(page(), palette: palette, turn: 0, photo: "p"),
                       PhotoColours.applied(page(), palette: palette, turn: 3, photo: "p"))
    }

    func testALockedPageOrNoPaletteIsLeftAsItIs() {
        var shut = page()
        shut.locked = true
        XCTAssertEqual(PhotoColours.applied(shut, palette: palette, turn: 0, photo: "p"), shut)
        XCTAssertEqual(PhotoColours.applied(page(), palette: [], turn: 0, photo: "p"), page())
    }

    func testThePaletteTurnsAPlaceATap() {
        XCTAssertEqual(PhotoColours.turned(palette, by: 0), ["#112233", "#cc4400", "#ddeeff"], "dark to light")
        XCTAssertEqual(PhotoColours.turned(palette, by: 1), ["#cc4400", "#ddeeff", "#112233"])
        XCTAssertEqual(PhotoColours.turned(palette, by: 3), PhotoColours.turned(palette, by: 0), "round again")
        XCTAssertEqual(PhotoColours.turned([], by: 1), [])
        XCTAssertEqual(PhotoColours.pageColours(page(), photo: "p"), ["#ffffff", "#ff0000", "#000000"])
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
        s.selection = ["s"]
        XCTAssertNil(s.photoForColours, "a shape offers none")
        s.photoColourTurn = 4
        s.selection = ["p"]
        XCTAssertEqual(s.photoColourTurn, 0, "a new selection starts again")
    }
}
