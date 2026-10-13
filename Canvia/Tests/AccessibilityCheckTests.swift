// Check accessibility: one pass that finds low contrast, pictures with no
// alt text, text under 12 px, flashing, links with nothing to read and texts
// layered out of reading order — each naming its page and element — and the
// fixes the sheet offers. The rows are the Android twin's.

import XCTest
@testable import Canvia

final class AccessibilityCheckTests: XCTestCase {

    private func page(_ elements: [Element]) -> Design {
        var d = Design(title: "Check", width: 1080, height: 1080)
        d.pages = [Page(background: .color("#ffffff"), elements: elements)]
        return d
    }

    private func kinds(_ d: Design) -> [AccessibilityAudit.Kind] {
        AccessibilityAudit.findings(d).map(\.kind)
    }

    private func at(_ el: Element, x: Double, y: Double) -> Element {
        var e = el
        e.x = x
        e.y = y
        return e
    }

    // MARK: alt text

    func testPicturesWithoutAltTextAreFound() throws {
        let photo = Element.image("media:abc")
        let video = Element.image("video:clip1")
        let sticker = Element.sticker("🌸")
        var icon = Element.shape("rect", w: 80, h: 80)
        icon.iconId = "star"
        let d = page([photo, video, sticker, icon])
        let found = AccessibilityAudit.findings(d)
        XCTAssertEqual(found.map(\.kind), [.altText, .altText, .altText, .altText])
        XCTAssertEqual(found.map(\.message), ["Photo with no alt text", "Video with no alt text",
                                               "Sticker with no alt text", "Icon with no alt text"])
        XCTAssertEqual(found.map(\.elementId), [photo.id, video.id, sticker.id, icon.id])
        XCTAssertEqual(found.first?.fix, .addAltText)
        XCTAssertEqual(found.first?.pageIndex, 0)
    }

    /// Described, marked decorative, an empty frame, a plain shape or a
    /// hidden picture: nothing to ask.
    func testDescribedDecorativeAndEmptyPicturesPass() {
        var described = Element.image("media:abc")
        described.altText = "A dog on a beach"
        var decorative = Element.image("media:def")
        decorative.decorative = true
        var empty = Element.image("media:x")
        empty.src = nil
        var hidden = Element.image("media:ghi")
        hidden.hidden = true
        var blank = Element.image("media:jkl")
        blank.altText = "   "
        let d = page([described, decorative, empty, Element.shape("rect"), hidden, blank])
        XCTAssertEqual(AccessibilityAudit.findings(d).map(\.elementId), [blank.id], "blank alt text is none")
    }

    /// "decorative" is written only when true, read by both phones and kept.
    func testDecorativeIsAnOptionalKey() throws {
        var el = Element.image("media:abc")
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any]
        XCTAssertNil(plain?["decorative"])
        el.decorative = true
        let data = try JSONEncoder().encode(el)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["decorative"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: data).decorative, true)
        let falsy = #"{"id":"e1","type":"image","src":"media:a","decorative":false}"#
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(falsy.utf8)).decorative)

        let d = page([Element.image("media:abc")])
        let id = d.pages[0].elements[0].id
        let marked = AccessibilityAudit.markedDecorative(d, pageIndex: 0, elementId: id)
        XCTAssertEqual(marked.pages[0].elements[0].decorative, true)
        XCTAssertTrue(AccessibilityAudit.findings(marked).isEmpty)
    }

    // MARK: small text

    func testTextUnder12PxIsSmallAndMakeIt12FixesIt() throws {
        let tiny = Element.text("Terms apply", fontSize: 11)
        let twelve = Element.text("Fine print", fontSize: 12)
        let empty = Element.text("  ", fontSize: 8)
        let d = page([at(tiny, x: 40, y: 40), at(twelve, x: 40, y: 400), at(empty, x: 40, y: 800)])
        let found = AccessibilityAudit.findings(d).filter { $0.kind == .smallText }
        XCTAssertEqual(found.map(\.elementId), [tiny.id])
        let f = try XCTUnwrap(found.first)
        XCTAssertEqual(f.fix, .makeIt12)
        XCTAssertEqual(f.message, "Text at 11 px — under 12 px is hard to read")
        let fixed = AccessibilityAudit.fixed(d, f)
        XCTAssertEqual(fixed.pages[0].elements[0].fontSize, 12)
        XCTAssertTrue(AccessibilityAudit.findings(fixed).filter { $0.kind == .smallText }.isEmpty)
    }

    // MARK: flashing

    /// The loops cycle every 1.2 s, slower than 0.33 s; a page held under a
    /// third of a second changes more than three times a second.
    func testFlashing() {
        var spin = Element.sticker("⭐")
        spin.animation = ElementAnimation(kind: "spin", delay: 0, duration: 0.6)
        XCTAssertEqual(spin.animation?.period, 1.2)
        XCTAssertNil(ElementAnimation(kind: "fade", delay: 0, duration: 0.6).period)
        XCTAssertFalse(AccessibilityAudit.flashes(spin))

        var deck = Design(title: "Flicker", width: 1080, height: 1080)
        deck.pages = [Page(elements: [Element.text("One")]), Page(elements: [Element.text("Two")])]
        deck.pages[1].holdSeconds = 0.2
        let found = AccessibilityAudit.findings(deck).filter { $0.kind == .flashing }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.pageIndex, 1)
        XCTAssertNil(found.first?.elementId)
        XCTAssertEqual(found.first?.message, "Page changes faster than three times a second")

        var single = page([Element.text("Alone")])
        single.pages[0].holdSeconds = 0.2
        XCTAssertFalse(kinds(single).contains(.flashing), "one page never changes")
    }

    // MARK: links

    func testALinkWithNothingToReadIsFound() {
        var button = Element.shape("rect", w: 300, h: 80)
        button.link = "https://example.com"
        var labelled = Element.text("Visit our shop", fontSize: 36)
        labelled.link = "https://example.com/shop"
        var described = Element.shape("circle", w: 80, h: 80)
        described.link = "https://example.com"
        described.altText = "Our website"
        let d = page([button, at(labelled, x: 0, y: 300), at(described, x: 0, y: 600)])
        let found = AccessibilityAudit.findings(d).filter { $0.kind == .linkText }
        XCTAssertEqual(found.map(\.elementId), [button.id])
        XCTAssertEqual(found.first?.message, "Link with nothing to read")
        XCTAssertEqual(found.first?.fix, .addAltText)
    }

    // MARK: reading order

    /// Texts layered bottom first read top first: out of order, and the
    /// first one layered out of its place is named.
    func testTextsLayeredOutOfReadingOrder() {
        let footer = at(Element.text("Footer", fontSize: 30), x: 100, y: 900)
        let heading = at(Element.text("Heading", fontSize: 60), x: 100, y: 100)
        let mixed = page([footer, heading])
        let found = AccessibilityAudit.findings(mixed).filter { $0.kind == .readingOrder }
        XCTAssertEqual(found.map(\.elementId), [footer.id])
        XCTAssertEqual(found.first?.message, "Layers run in a different order from how the page reads")
        XCTAssertFalse(kinds(page([heading, footer])).contains(.readingOrder))
        XCTAssertFalse(kinds(page([heading])).contains(.readingOrder))
    }

    // MARK: contrast

    func testLowContrastIsFoundAndFixAllIsOneStep() throws {
        var pale = Element.text("Barely there", fontSize: 30)
        pale.color = "#dddddd"
        var paler = Element.text("Even less", fontSize: 30)
        paler.color = "#eeeeee"
        let d = page([at(pale, x: 40, y: 100), at(paler, x: 40, y: 500)])
        let found = AccessibilityAudit.findings(d).filter { $0.kind == .contrast }
        XCTAssertEqual(found.map(\.elementId), [pale.id, paler.id])
        XCTAssertEqual(found.first?.fix, .fixColour)
        XCTAssertNotNil(found.first?.contrast)
        XCTAssertTrue(found.first?.message.hasPrefix("Hard to read: ") ?? false)

        let store = DesignStore(design: d)
        let next = AccessibilityAudit.fixedAllContrast(store.design, found)
        store.apply { $0 = next }
        XCTAssertTrue(AccessibilityAudit.findings(store.design).filter { $0.kind == .contrast }.isEmpty)
        store.undo()
        XCTAssertEqual(store.design.pages, d.pages, "one undo step")
    }

    // MARK: the sheet's words and order

    /// Page by page; within a page contrast, alt text, small text,
    /// flashing, links, reading order.
    func testFindingsComeInPageAndKindOrder() {
        var pale = Element.text("Pale", fontSize: 10)
        pale.color = "#eeeeee"
        var d = Design(title: "Order", width: 1080, height: 1080)
        d.pages = [
            Page(elements: [Element.image("media:a")]),
            Page(elements: [at(pale, x: 40, y: 40)]),
            Page(elements: [Element.sticker("🌸")]),
        ]
        let found = AccessibilityAudit.findings(d)
        XCTAssertEqual(found.map(\.kind), [.altText, .contrast, .smallText, .altText])
        XCTAssertEqual(found.map(\.pageIndex), [0, 1, 1, 2])
        XCTAssertEqual(AccessibilityAudit.summary(found), "4 things on 3 pages")
        XCTAssertEqual(AccessibilityAudit.byPage(found).map(\.pageIndex), [0, 1, 2])
        XCTAssertEqual(AccessibilityAudit.byPage(found)[1].findings.count, 2)
        XCTAssertEqual(AccessibilityAudit.summary(Array(found.prefix(1))), "1 thing on 1 page")
        XCTAssertEqual(AccessibilityAudit.summary([]), "Nothing to fix")
    }

    /// Hidden elements are met by nobody; a page with nothing wrong has
    /// nothing to say.
    func testAPageWithNothingWrongPasses() {
        var hidden = Element.text("Tiny", fontSize: 6)
        hidden.hidden = true
        let fine = at(Element.text("A good heading", fontSize: 48), x: 100, y: 100)
        XCTAssertTrue(AccessibilityAudit.findings(page([fine, hidden])).isEmpty)
    }
}
