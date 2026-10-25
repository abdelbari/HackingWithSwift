// Copy & resize: a new design per size, every id fresh, fitted exactly as
// Resize's Smart mode fits it in place, titled "<title> – <size>" under a name the shelf
// does not have — and the original never touched. Make a copy, from the
// editor, is "<title> copy". The Android twin's rows.

import XCTest
@testable import Canvia

final class CopyResizeTests: XCTestCase {

    /// Two pages, a master, a group, and an arrow joining two boxes.
    private func source() -> Design {
        var d = Design(title: "Spring sale", width: 1080, height: 1080)
        var a = Element.shape("rect", w: 200, h: 200)
        a.x = 80; a.y = 100
        var b = Element.shape("circle", w: 160, h: 160)
        b.x = 700; b.y = 760
        var arrow = Element.line(w: 300)
        arrow.connectFrom = a.id
        arrow.connectTo = b.id
        var heading = Element.text("Spring sale", fontSize: 72, w: 800)
        heading.x = 140; heading.y = 420
        heading.group = "grp_1"
        var sub = Element.text("This week only", fontSize: 32, w: 600)
        sub.x = 240; sub.y = 540
        sub.group = "grp_1"
        d.pages = [Page(elements: [a, b, arrow, heading, sub]),
                   Page(background: .color("#ffeedd"), elements: [Element.text("Page two", fontSize: 48)])]
        d.masterPageId = d.pages[1].id
        d.folder = "Campaigns"
        d.guides = [Guide(vertical: true, position: 540)]
        return d
    }

    private func ids(_ d: Design) -> Set<String> {
        var out: Set<String> = [d.id]
        for page in d.pages {
            out.insert(page.id)
            for el in page.elements { out.insert(el.id) }
        }
        return out
    }

    func testTheCopysIdsAreDisjointFromTheSource() throws {
        let original = source()
        let story = try XCTUnwrap(SizePreset.byId("insta-story"))
        let copy = CopyResize.copy(of: original, to: .preset(story), title: "Spring sale – Instagram Story")
        XCTAssertTrue(ids(copy).isDisjoint(with: ids(original)))
        XCTAssertEqual(copy.pages.count, original.pages.count)
    }

    func testTheSourceIsUnchanged() throws {
        let original = source()
        let before = original
        let targets = try ["insta-story", "x-post", "a4"].map { try XCTUnwrap(SizePreset.byId($0)) }.map(ResizeTarget.preset)
        _ = CopyResize.copies(of: original, to: targets, taken: [])
        XCTAssertEqual(original, before)
    }

    /// Element for element what Resize's Smart mode makes in place, ids
    /// aside.
    func testTheCopysElementsEqualTheInPlaceSmartResize() throws {
        let original = source()
        let target = ResizeTarget.custom(width: 1600, height: 900, unit: "px")
        let copy = CopyResize.copy(of: original, to: target, title: "Spring sale – 1600 × 900")
        let inPlace = DesignStore.resized(original, width: 1600, height: 900, mode: .smart)
        XCTAssertEqual(copy.width, 1600)
        XCTAssertEqual(copy.height, 900)
        for (p, page) in copy.pages.enumerated() {
            XCTAssertEqual(page.elements.count, inPlace.pages[p].elements.count)
            for (i, el) in page.elements.enumerated() {
                let expected = inPlace.pages[p].elements[i]
                XCTAssertEqual(el.x, expected.x, accuracy: 1e-9)
                XCTAssertEqual(el.y, expected.y, accuracy: 1e-9)
                XCTAssertEqual(el.w, expected.w, accuracy: 1e-9)
                XCTAssertEqual(el.h, expected.h, accuracy: 1e-9)
                XCTAssertEqual(el.fontSize, expected.fontSize)
                XCTAssertEqual(el.type, expected.type)
                XCTAssertEqual(el.text, expected.text)
            }
        }
        XCTAssertEqual(copy.guides.map(\.position), inPlace.guides.map(\.position))
    }

    /// The arrow joins the copies of its boxes, the group stays one group
    /// under a new key, and the master is still the master.
    func testConnectorsGroupsAndTheMasterFollowTheCopy() throws {
        let original = source()
        let copy = CopyResize.copy(of: original, to: .custom(width: 1080, height: 1920, unit: "px"), title: "t")
        let page = copy.pages[0]
        let arrow = try XCTUnwrap(page.elements.first { $0.type == .line })
        XCTAssertEqual(arrow.connectFrom, page.elements[0].id)
        XCTAssertEqual(arrow.connectTo, page.elements[1].id)
        let groups = Set(page.elements.compactMap(\.group))
        XCTAssertEqual(groups.count, 1)
        XCTAssertNotEqual(groups.first, "grp_1")
        XCTAssertEqual(copy.masterPageId, copy.pages[1].id)
        XCTAssertNotEqual(copy.guides.first?.id, original.guides.first?.id)
    }

    /// In the same folder, in the size's unit, named for good.
    func testTheCopyIsFiledTitledAndInItsUnit() throws {
        let original = source()
        let a4 = try XCTUnwrap(SizePreset.byId("a4"))
        let now = Date(timeIntervalSince1970: 1_000)
        let copy = CopyResize.copy(of: original, to: .preset(a4), title: "Spring sale – A4 Document", now: now)
        XCTAssertEqual(copy.folder, "Campaigns")
        XCTAssertFalse(copy.titleAuto)
        XCTAssertEqual(copy.unit, "mm")
        XCTAssertEqual(copy.dpi, 300)
        XCTAssertEqual(copy.width, 2480)
        XCTAssertEqual(copy.createdAt, 1_000_000)
        XCTAssertEqual(copy.updatedAt, 1_000_000)
        let back = CopyResize.copy(of: copy, to: .custom(width: 1080, height: 1080, unit: "px"), title: "t")
        XCTAssertNil(back.unit, "a size in pixels is pixels")
        XCTAssertNil(back.dpi)
    }

    func testTitlesAreTheSizeAndNeverRepeatTheShelf() throws {
        let story = try XCTUnwrap(SizePreset.byId("insta-story"))
        XCTAssertEqual(CopyResize.title("Spring sale", target: .preset(story)), "Spring sale – Instagram Story")
        XCTAssertEqual(CopyResize.title("Spring sale", target: .custom(width: 1600, height: 900, unit: "px")),
                       "Spring sale – 1600 × 900")
        XCTAssertEqual(CopyResize.title("Menu", target: .custom(width: 2480, height: 3508, unit: "mm")),
                       "Menu – 210 × 297 mm")
        XCTAssertEqual(CopyResize.title("  ", target: .preset(story)), "Untitled design – Instagram Story")

        let made = CopyResize.copies(of: source(),
                                     to: [.preset(story), .preset(story), .custom(width: 1600, height: 900, unit: "px")],
                                     taken: ["Spring sale – Instagram Story"])
        XCTAssertEqual(made.map(\.title), ["Spring sale – Instagram Story 2", "Spring sale – Instagram Story 3",
                                           "Spring sale – 1600 × 900"])
        XCTAssertEqual(Set(made.map(\.id)).count, 3)
    }

    func testMakeACopyIsTheDesignAgainUnderANewName() {
        let original = source()
        let copy = CopyResize.madeCopy(of: original, taken: ["Spring sale", "Spring sale copy"])
        XCTAssertEqual(copy.title, "Spring sale copy 2")
        XCTAssertFalse(copy.titleAuto)
        XCTAssertTrue(ids(copy).isDisjoint(with: ids(original)))
        XCTAssertEqual(copy.width, original.width)
        XCTAssertEqual(copy.folder, original.folder)
        XCTAssertEqual(copy.pages[0].elements.map(\.text), original.pages[0].elements.map(\.text))
        XCTAssertEqual(CopyResize.copyTitle("Poster"), "Poster copy")
    }

    func testTheWords() {
        XCTAssertEqual(CopyResize.buttonTitle(count: 1), "Make 1 copy")
        XCTAssertEqual(CopyResize.buttonTitle(count: 3), "Make 3 copies")
        XCTAssertEqual(CopyResize.progressText(2, of: 3), "Making copy 2 of 3…")
        XCTAssertEqual(CopyResize.doneText(count: 3), "Made 3 resized copies")
        XCTAssertEqual(CopyResize.doneText(count: 1), "Made 1 resized copy")
    }

    /// Copy & resize is where Resize opens when there is something to copy.
    func testCopyAndResizeIsTheDefaultWithContent() {
        XCTAssertTrue(CopyResize.hasContent(source()))
        XCTAssertFalse(CopyResize.hasContent(Design(title: "Blank")))
    }

    /// Shared by reference: the copy uses the same photo, so the sweep that
    /// keeps every photo a design uses keeps it.
    func testPhotosAreSharedByReference() {
        var original = Design(title: "Photo", width: 1080, height: 1080)
        original.pages[0].elements = [Element.image("media:abc123")]
        let copy = CopyResize.copy(of: original, to: .custom(width: 1080, height: 1920, unit: "px"), title: "t")
        XCTAssertEqual(copy.pages[0].elements[0].src, "media:abc123")
        XCTAssertTrue(DesignLibrary.photos(in: [copy]).contains("abc123"))
    }
}
