// Where Present starts from the editor, the Android twin's PresentFromTest
// row for row: offered past the first of several pages, hidden pages
// skipped either way, the choice kept per design under the shared key.

import XCTest
@testable import Canvia

final class PresentFromTests: XCTestCase {

    private func design(_ hidden: Bool...) -> Design {
        var d = Design(title: "Talk", width: 1920, height: 1080)
        d.id = "d1"
        d.pages = hidden.enumerated().map { i, h in
            var page = Page(id: "p\(i)")
            page.hidden = h ? true : nil
            return page
        }
        return d
    }

    func testTheChoiceIsOfferedPastTheFirstPageOfSeveral() {
        XCTAssertFalse(PresentFrom.offersChoice(design(false), pageIndex: 0))
        XCTAssertFalse(PresentFrom.offersChoice(design(false, false), pageIndex: 0))
        XCTAssertTrue(PresentFrom.offersChoice(design(false, false), pageIndex: 1))
    }

    func testEitherWayHiddenPagesAreSkipped() {
        let d = design(true, false, false, true, false)
        XCTAssertEqual(PresentFrom.startPage(d, choice: PresentFrom.start, pageIndex: 4), 1)
        XCTAssertEqual(PresentFrom.startPage(d, choice: PresentFrom.current, pageIndex: 2), 2)
        // A hidden page N: the next shown one.
        XCTAssertEqual(PresentFrom.startPage(d, choice: PresentFrom.current, pageIndex: 3), 4)
        // Hidden and last: the one before, as Present always started.
        XCTAssertEqual(PresentFrom.startPage(design(false, false, false, true), choice: PresentFrom.current, pageIndex: 3), 2)
        XCTAssertNil(PresentFrom.startPage(design(true, true), choice: PresentFrom.start, pageIndex: 1))
    }

    func testTheChoiceIsKeptPerDesignAsTheAndroidTwinKeepsIt() throws {
        let kept = PresentFrom.remembered(PresentFrom.remembered([:], designId: "b", choice: PresentFrom.current),
                                          designId: "a", choice: PresentFrom.start)
        XCTAssertEqual(PresentFrom.encode(kept), #"{"a":"start","b":"current"}"#)
        XCTAssertEqual(PresentFrom.decode(PresentFrom.encode(kept)), kept)
        XCTAssertEqual(PresentFrom.decode(#"{"x":"current","y":"middle","z":3}"#), ["x": "current"])
        XCTAssertEqual(PresentFrom.decode("not json"), [:])
        XCTAssertEqual(PresentFrom.chosen(kept, designId: "new"), PresentFrom.start)
        XCTAssertEqual(PresentFrom.chosen(kept, designId: "b"), PresentFrom.current)
        XCTAssertEqual(PresentFrom.remembered(kept, designId: "a", choice: "elsewhere"), kept)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PresentFromTests"))
        defaults.removePersistentDomain(forName: "PresentFromTests")
        PresentFrom.remember("d1", choice: PresentFrom.current, defaults)
        XCTAssertEqual(defaults.string(forKey: "presentFrom"), #"{"d1":"current"}"#)
        XCTAssertEqual(PresentFrom.choices(defaults), ["d1": "current"])
    }

    /// F5 from the beginning, ⇧F5 from this page — the Android twin's
    /// EditorKeys rows — named in the keyboard's list and in Help.
    func testF5PresentsFromTheBeginningAndShiftF5FromThisPage() throws {
        XCTAssertEqual(PresentFrom.choice(shift: false), PresentFrom.start)
        XCTAssertEqual(PresentFrom.choice(shift: true), PresentFrom.current)
        XCTAssertEqual(PresentFrom.keys.map(\.name), ["Present from the beginning", "Present from this page"])
        let keyboard = try XCTUnwrap(HelpTopics.all.first { $0.id == "keyboard" })
        XCTAssertTrue(keyboard.body.contains("⇧F5"))
    }

    func testWhatTheMenuAndAScreenReaderSay() {
        XCTAssertEqual(PresentFrom.fromPage(6), "From page 7")
        XCTAssertEqual(PresentFrom.announcement(design(true, false, false, true, false), index: 2),
                       "Presenting from page 2 of 3")
    }
}
