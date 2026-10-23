// A paste over a frame, a grid cell or a photo: the picture goes into it
// rather than onto the page as a loose photo. The rule's table is the
// Android twin's Copies.pasteTarget table.

import XCTest
@testable import Canvia

@MainActor
final class PasteIntoFrameTests: XCTestCase {

    private func frame(_ id: String = "frame", locked: Bool = false) -> Element {
        var el = Element.image("", w: 300, h: 300)
        el.id = id
        el.src = nil
        el.maskShapeId = "circle"
        el.locked = locked
        return el
    }

    private func photo(_ id: String = "photo", src: String = "asset:beach") -> Element {
        var el = Element.image(src, w: 200, h: 100)
        el.id = id
        return el
    }

    func testTheTargetRuleTable() {
        let f = frame(), other = frame("other"), locked = frame("locked", locked: true)
        let plain = photo("plain")
        let text = Element.text("Hello")
        let picture = photo()
        let page = [f, other, locked, plain]
        let rows: [(String, [Element], [Element], Bool, Copies.PasteTarget)] = [
            ("frame + picture", [f], [picture], true, .fill("frame")),
            ("frame + a copied photo", [f], [picture], false, .fill("frame")),
            ("frame + text", [f], [text], true, .add),
            ("frame + two copied photos", [f], [picture, photo("p2")], false, .add),
            ("two selected", [f, other], [picture], true, .add),
            ("locked", [locked], [picture], true, .add),
            ("nothing selected", [], [picture], true, .add),
            ("photo + a picture from another app", [plain], [picture], true, .replace("plain")),
            ("photo + a copied photo", [plain], [picture], false, .add),
            ("frame + an empty frame copied", [f], [frame("copied")], false, .add),
        ]
        for (name, selected, payload, foreign, target) in rows {
            XCTAssertEqual(Copies.pasteTarget(selected, among: page, payload: payload, foreign: foreign), target, name)
        }
    }

    func testAFilledFrameKeepsItsShapeAndSizeAndThePastedLook() {
        var pasted = photo()
        pasted.filter = "vivid"
        pasted.cropScale = 2
        let filled = Copies.filled(frame(), with: pasted)
        XCTAssertEqual(filled.src, "asset:beach")
        XCTAssertEqual(filled.maskShapeId, "circle")
        XCTAssertEqual([filled.w, filled.h], [300, 300])
        XCTAssertEqual(filled.filter, "vivid")
        XCTAssertEqual(filled.cropScale ?? 1, 1, "the crop reset to cover")
    }

    func testPastingACopiedPhotoIntoASelectedFrameIsOneStepAndKeepsTheFrameSelected() {
        var d = Design(title: "frames", width: 1080, height: 1080)
        d.pages = [Page(elements: [frame(), photo()])]
        let s = DesignStore(design: d)
        s.select("photo")
        s.copySelected()
        s.select("frame")
        s.paste()
        XCTAssertEqual(s.page.elements.count, 2, "nothing added")
        XCTAssertEqual(s.element("frame")?.src, "asset:beach")
        XCTAssertEqual(s.selection, ["frame"])
        s.undo()
        XCTAssertNil(s.element("frame")?.src)
        // A photo selected: a copied photo is added, as a duplicate.
        s.select("photo")
        s.paste()
        XCTAssertEqual(s.page.elements.count, 3)
    }
}
