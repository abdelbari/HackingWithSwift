// Resize's Smart mode, as both phones run it: the shared pages and targets
// of templates/resize-smart.json, and the rules one at a time — the Android
// twin's PageResizeSmartTest, row for row.

import XCTest
@testable import Canvia

final class SmartResizeTests: XCTestCase {

    /// A text box's height as the fixture gives it: its own.
    private let ownHeight: (Element) -> Double = { $0.h }

    private func page(_ o: [String: Any]) throws -> (page: Page, size: CGSize) {
        let raw = try XCTUnwrap(o["elements"] as? [[String: Any]])
        let elements = try raw.map { try JSONDecoder().decode(Element.self, from: SharedFixture.encoded($0)) }
        let size = CGSize(width: try XCTUnwrap(o["width"] as? Double), height: try XCTUnwrap(o["height"] as? Double))
        return (Page(elements: elements), size)
    }

    func testEverySharedPageLandsWhereTheFixtureSaysAtEveryTarget() throws {
        let fixture = try SharedFixture.object("resize-smart")
        let pages = try XCTUnwrap(fixture["pages"] as? [[String: Any]])
        let targets = try XCTUnwrap(fixture["targets"] as? [[Double]])
        XCTAssertGreaterThanOrEqual(pages.count, 8)
        XCTAssertEqual(targets.count, 4)
        for p in pages {
            let name = p["name"] as? String ?? ""
            let (source, old) = try page(p)
            let expected = try XCTUnwrap(p["expected"] as? [String: [String: [Double]]])
            for t in targets {
                let key = "\(Int(t[0]))x\(Int(t[1]))"
                let out = DesignStore.smartReflow(source, from: old, to: CGSize(width: t[0], height: t[1]),
                                                  heightFor: ownHeight)
                let byId = Dictionary(out.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                for (id, want) in expected[key] ?? [:] {
                    let e = try XCTUnwrap(byId[id], "\(name) @ \(key): \(id)")
                    let have = [e.x, e.y, e.w, e.h] + (e.fontSize.map { [$0] } ?? [])
                    XCTAssertEqual(have.count, want.count, "\(name) @ \(key): \(id)")
                    for (a, b) in zip(want, have) { XCTAssertEqual(a, b, accuracy: 0.01, "\(name) @ \(key): \(id)") }
                }
            }
        }
    }

    private func one(_ elements: [Element], _ old: CGSize, _ new: CGSize) -> [String: Element] {
        let out = DesignStore.smartReflow(Page(elements: elements), from: old, to: new, heightFor: ownHeight)
        return Dictionary(out.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func testAFullBleedPhotoCoversTheNewPageAndKeepsItsCrop() throws {
        var photo = Element.shape("rect", w: 1920, h: 1080)
        photo.type = .image
        photo.src = "media:a"
        photo.cropScale = 1.3
        photo.cropX = 0.2
        let out = try XCTUnwrap(one([photo], CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920))[photo.id])
        XCTAssertEqual([out.x, out.y, out.w, out.h], [0, 0, 1080, 1920])
        XCTAssertEqual(out.cropScale, 1.3)
        XCTAssertEqual(out.cropX, 0.2)
    }

    func testSideBySideRestacksIntoAColumnWhenThePageTurnsTall() throws {
        let fixture = try SharedFixture.object("resize-smart")
        let pages = try XCTUnwrap(fixture["pages"] as? [[String: Any]])
        let (source, old) = try page(pages[1])
        let out = one(source.elements, old, CGSize(width: 1080, height: 1920))
        let photo = try XCTUnwrap(out["photo"]), title = try XCTUnwrap(out["title"])
        // One above the other, each as wide as the margins allow.
        XCTAssertLessThanOrEqual(photo.y + photo.h, title.y + 0.01)
        XCTAssertEqual(photo.w, 1080 * (1 - 2 * DesignStore.stackMargin), accuracy: 0.01)
        XCTAssertTrue(out.values.allSatisfy { $0.x >= 0 && $0.x + $0.w <= 1080.01 && $0.y >= 0 && $0.y + $0.h <= 1920.01 })
    }

    func testTypeNeverShrinksBelowTheReadableSize() throws {
        var body = Element.text("small", fontSize: 10, w: 600)
        body.x = 100
        body.y = 100
        body.h = 40
        var head = TextRoles.with(body, TextRoles.h1)
        head.id = UID.make()
        head.y = 300
        let out = one([body, head], CGSize(width: 1080, height: 1080), CGSize(width: 500, height: 500))
        XCTAssertEqual(try XCTUnwrap(out[body.id]?.fontSize), 500 * DesignStore.bodyMin, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(out[head.id]?.fontSize), 500 * DesignStore.headingMin, accuracy: 1e-9)
    }

    func testALockedElementStaysPutOnlyScaled() throws {
        var locked = Element.shape("rect", w: 300, h: 300)
        locked.x = 100
        locked.y = 200
        locked.locked = true
        let out = try XCTUnwrap(one([locked], CGSize(width: 1000, height: 1000), CGSize(width: 2000, height: 500))[locked.id])
        XCTAssertEqual([out.x, out.y, out.w, out.h], [200, 100, 150, 150])
    }

    func testTheModeIsKeptUnderResizeModeSmartUnlessSaid() {
        XCTAssertEqual(ResizeMode.key, "resizeMode")
        XCTAssertEqual(ResizeMode.of(nil), .smart)
        XCTAssertEqual(ResizeMode.of("reflow"), .reflow)
        XCTAssertEqual(ResizeMode.of("fit"), .fit)
        XCTAssertEqual(ResizeMode.allCases.map(\.label), ["Smart", "Keep layout", "Fit"])
        var d = Design(title: "T", width: 1000, height: 1000)
        d.pages = [Page(elements: [Element.shape("rect", w: 1000, h: 1000)])]
        XCTAssertEqual(DesignStore.resized(d, width: 500, height: 800, mode: .smart, heightFor: ownHeight).pages[0].elements[0].h, 800)
        XCTAssertEqual(DesignStore.resized(d, width: 500, height: 800, mode: .fit, heightFor: ownHeight).pages[0].elements[0].h, 500)
    }

    /// One step, named Resize, that Undo takes back whole.
    func testAResizeIsOneUndoStepNamedResize() {
        var d = Design(title: "T", width: 1000, height: 1000)
        d.pages = [Page(elements: [Element.shape("rect", w: 1000, h: 1000)])]
        let store = DesignStore(design: d)
        store.resize(width: 500, height: 800, mode: .smart, pageOnly: false, units: nil)
        XCTAssertEqual(store.design.width, 500)
        XCTAssertEqual(store.undoLabel, "Resize")
        store.undo()
        XCTAssertEqual(store.design.width, 1000)
    }
}
