// Round 34's drop to replace, with the rows the Android twin's
// DropFromLibraryTest holds too: a photo or clip held over a plain photo,
// clip or moving picture replaces its picture in place — the topmost thing
// under the finger, never a locked or hidden one, a frame or a code — and
// a photo dragged and held over another swaps pictures with it.

import XCTest
import CoreGraphics
@testable import Canvia

final class ReplaceDropTests: XCTestCase {

    private let page = CGSize(width: 1000, height: 800)

    private func photo(_ id: String, _ src: String?, x: Double, y: Double, side: Double = 200) -> Element {
        var e = Element.image(src ?? "", w: side, h: side)
        e.id = id
        e.src = src
        e.x = x; e.y = y
        return e
    }

    /// Two photos overlapping, the second on top, with a shape over the
    /// second's corner; a locked photo; a photo under a hidden one; an
    /// empty frame; a clip; a QR code; and a moving picture.
    private func elements() -> [Element] {
        var cover = Element.shape("rect", w: 50, h: 50)
        cover.id = "cover"
        cover.x = 250; cover.y = 250
        var locked = photo("locked", "asset:l", x: 400, y: 0, side: 100)
        locked.locked = true
        var hidden = photo("hidden", "asset:h", x: 600, y: 0, side: 100)
        hidden.hidden = true
        return [photo("under", "asset:a", x: 0, y: 0), photo("over", "asset:b", x: 100, y: 100), cover, locked,
                photo("beneath", "asset:c", x: 600, y: 0, side: 100), hidden,
                photo("frame", nil, x: 800, y: 0, side: 100),
                photo("clip", "video:v1", x: 0, y: 500, side: 100),
                photo("code", CodeGenerator.prefix + "hello", x: 200, y: 500, side: 100),
                photo("moving", "anim:g1", x: 400, y: 500, side: 100)]
    }

    func testWhatAHeldPictureWouldReplace() {
        let rows: [(CGPoint, String?)] = [
            (CGPoint(x: 50, y: 50), "under"),
            // Where the two overlap, the one on top.
            (CGPoint(x: 150, y: 150), "over"),
            // A shape over it covers it.
            (CGPoint(x: 275, y: 275), nil),
            // Locked: nothing; a hidden one is not there, the one under it is.
            (CGPoint(x: 450, y: 50), nil),
            (CGPoint(x: 650, y: 50), "beneath"),
            // A frame takes a picture as a frame; a code is no picture.
            (CGPoint(x: 850, y: 50), nil),
            (CGPoint(x: 250, y: 550), nil),
            // A clip and a moving picture are replaced as photos are.
            (CGPoint(x: 50, y: 550), "clip"),
            (CGPoint(x: 450, y: 550), "moving"),
            (CGPoint(x: 900, y: 700), nil),
        ]
        for (point, id) in rows {
            XCTAssertEqual(DropFromLibrary.replaceTarget(at: point, in: elements())?.id, id, "\(point)")
        }
        // The photo being dragged is never its own target.
        XCTAssertEqual(DropFromLibrary.replaceTarget(at: CGPoint(x: 150, y: 150), in: elements(), excluding: "over")?.id,
                       "under")
    }

    func testOnlyAPictureHeldThereReplaces() {
        let at = CGPoint(x: 50, y: 50)
        XCTAssertEqual(DropFromLibrary.target(at, elements: elements(), kind: .photo, page: page), .page)
        XCTAssertEqual(DropFromLibrary.target(at, elements: elements(), kind: .photo, page: page, held: "under"),
                       .replace("under"))
        XCTAssertEqual(DropFromLibrary.target(at, elements: elements(), kind: .clip, page: page, held: "under"),
                       .replace("under"))
        // Moved off it before letting go: the page, as before.
        XCTAssertEqual(DropFromLibrary.target(at, elements: elements(), kind: .photo, page: page, held: "over"), .page)
        // A sticker or graphic never replaces; a frame stays a frame.
        XCTAssertEqual(DropFromLibrary.target(at, elements: elements(), kind: .sticker, page: page, held: "under"), .page)
        XCTAssertEqual(DropFromLibrary.target(CGPoint(x: 850, y: 50), elements: elements(), kind: .photo, page: page,
                                              held: "frame"), .frame("frame"))
        XCTAssertEqual(DropFromLibrary.replaceHoldSeconds, 0.45)
    }

    private func store() -> DesignStore {
        var d = Design(title: "replace", width: 1000, height: 800)
        var looked = photo("under", "asset:a", x: 0, y: 0)
        looked.filter = "noir"
        looked.cropScale = 2
        looked.altText = "Photo of a dog"
        looked.altTextSource = "asset:a"
        looked.link = "https://example.com"
        var typed = photo("over", "asset:b", x: 300, y: 0)
        typed.altText = "Our team"
        d.pages = [Page(id: "p1", elements: [looked, typed])]
        return DesignStore(design: d)
    }

    func testAHeldDropReplacesInPlaceAsOneStep() {
        let s = store()
        let carried = LibraryDrag.Carried(kind: .photo, src: "asset:new", place: { _ in XCTFail("not on the page") })
        XCTAssertTrue(s.dropLibraryItem(carried, at: CGPoint(x: 50, y: 50), onPage: 0, held: "under"))
        let replaced = s.element("under")
        XCTAssertEqual(replaced?.src, "asset:new")
        XCTAssertEqual(replaced?.filter, "noir", "its look kept")
        XCTAssertEqual(replaced?.cropScale, 1, "its crop back to filling")
        XCTAssertEqual(replaced?.link, "https://example.com")
        XCTAssertNil(replaced?.altText, "alt text drawn from the old picture goes")
        XCTAssertNil(replaced?.altTextSource)
        XCTAssertEqual(s.undoLabel, "Replace")
        XCTAssertEqual(s.selection, ["under"])
        s.undo()
        XCTAssertEqual(s.element("under")?.src, "asset:a")
        // Alt text typed for it stays.
        XCTAssertEqual(Crop.replaced(s.element("over")!, src: "asset:x").altText, "Our team")
    }

    func testAPhotoHeldOverAnotherSwapsPictures() {
        let s = store()
        s.select("over")
        s.beginGesture()
        s.updateSelectedTransient { $0.x = 20; $0.y = 20 }
        XCTAssertTrue(s.swapPictures("over", with: "under", home: CGPoint(x: 300, y: 0)))
        XCTAssertEqual(s.element("over")?.src, "asset:a")
        XCTAssertEqual(s.element("under")?.src, "asset:b")
        XCTAssertEqual(s.element("over")?.x, 300, "back where it started")
        XCTAssertEqual(s.undoLabel, "Replace")
        s.undo()
        XCTAssertEqual(s.element("over")?.src, "asset:b")
        XCTAssertEqual(s.element("over")?.x, 300, "one step")
    }

    @MainActor
    func testTheReplaceActionNamesTheSelectedPhoto() {
        let s = store()
        XCTAssertNil(s.replaceablePhoto)
        s.select("over")
        XCTAssertEqual(s.replaceablePhoto?.id, "over")
        XCTAssertTrue(InsertSheet.replaceLabel(s.replaceablePhoto!).hasPrefix("Replace "))
    }
}
