// Check accessibility: one pass that finds low contrast, pictures with no
// alt text, text under 12 px (or 9 pt on paper), flashing, links with
// nothing to read and layers out of reading order — each naming its page and
// element — and the fixes the sheet offers. The rows and the words are the
// Android twin's AccessibilityAuditTest.

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
        XCTAssertEqual(found.map(\.message), ["Photo has no alt text", "Video has no alt text",
                                               "Sticker has no alt text", "Icon has no alt text"])
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
        XCTAssertEqual(f.message, "Text is 11 px, under 12 px")
        let fixed = AccessibilityAudit.fixed(d, f)
        XCTAssertEqual(fixed.pages[0].elements[0].fontSize, 12)
        XCTAssertTrue(AccessibilityAudit.findings(fixed).filter { $0.kind == .smallText }.isEmpty)
    }

    /// Android's rows: (font size, unit, small?). On paper the floor is
    /// 9 pt at the design's dpi — 37.5 px at 300 — and Make it 12 sets
    /// 12 pt, 50 px at 300.
    func testTypeUnder9PtOnPaperIsSmall() throws {
        let rows: [(Double, String?, Bool)] = [
            (11, nil, true), (11.9, nil, true), (12, nil, false),
            (30, "mm", true), (37, "mm", true), (37.5, "mm", false), (40, "in", false),
        ]
        for (size, unit, small) in rows {
            var d = page([Element.text("Fine print", fontSize: size)])
            d.unit = unit
            d.dpi = unit == nil ? nil : 300
            XCTAssertEqual(kinds(d).contains(.smallText), small, "\(size) \(unit ?? "px")")
        }
        var a4 = page([Element.text("Fine print", fontSize: 30)])
        a4.unit = "mm"
        a4.dpi = 300
        let f = try XCTUnwrap(AccessibilityAudit.findings(a4).first { $0.kind == .smallText })
        XCTAssertEqual(f.message, "Text is 7 pt, under 9 pt")
        XCTAssertEqual(AccessibilityAudit.legibleSize(a4), 50, accuracy: 1e-9)
        XCTAssertEqual(AccessibilityAudit.legibleSize(page([])), 12)
        XCTAssertEqual(AccessibilityAudit.fixed(a4, f).pages[0].elements[0].fontSize ?? 0, 50, accuracy: 1e-9)
    }

    /// A shape's words are type too; Make it 12 leaves its box as it is.
    func testAShapesWordsCanBeTooSmall() throws {
        var label = Element.shape("rect", w: 300, h: 100)
        label.text = "Tiny"
        label.fontSize = 8
        let d = page([label])
        let f = try XCTUnwrap(AccessibilityAudit.findings(d).first { $0.kind == .smallText })
        XCTAssertEqual(f.elementId, label.id)
        XCTAssertEqual(f.message, "Text is 8 px, under 12 px")
        let grown = AccessibilityAudit.fixed(d, f).pages[0].elements[0]
        XCTAssertEqual(grown.fontSize, 12)
        XCTAssertEqual(grown.h, 100)
    }

    // MARK: flashing

    /// The loops cycle every 1.2 s, slower than 0.33 s; a page that gives
    /// way to the next in under a third of a second — its hold in the
    /// video's timeline — changes more than three times a second. The last
    /// page gives way to nothing. Android's row.
    func testFlashing() {
        var spin = Element.sticker("⭐")
        spin.animation = ElementAnimation(kind: "spin", delay: 0, duration: 0.6)
        XCTAssertEqual(spin.animation?.period, 1.2)
        XCTAssertNil(ElementAnimation(kind: "fade", delay: 0, duration: 0.6).period)
        XCTAssertFalse(AccessibilityAudit.flashes(spin))

        var deck = Design(title: "Flicker", width: 1080, height: 1080)
        deck.pages = [Page(elements: [Element.text("One")]), Page(elements: [Element.text("Two")])]
        deck.pages[0].holdSeconds = 0.2
        deck.pages[1].holdSeconds = 0.2
        let found = AccessibilityAudit.findings(deck)
        XCTAssertEqual(found.map(\.kind), [.flashing])
        XCTAssertEqual(found.first?.pageIndex, 0)
        XCTAssertNil(found.first?.elementId)
        XCTAssertNil(found.first?.fix)
        XCTAssertEqual(found.first?.message, "Gives way to the next page faster than three times a second")
        deck.pages[0].holdSeconds = 0.4
        XCTAssertTrue(AccessibilityAudit.findings(deck).isEmpty)

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
        XCTAssertEqual(found.first?.message, "A link with no words and no alt text")
        XCTAssertEqual(found.first?.fix, .addAltText)
    }

    /// Android's row: a linked photo is asked for alt text twice over, a
    /// linked box once, linked words not at all.
    func testLinkedPicturesAndBoxes() {
        var photo = Element.image("media:a")
        photo.link = "https://canvia.app"
        var box = Element.shape("rect")
        box.link = "https://canvia.app"
        var words = Element.text("Shop now")
        words.link = "https://canvia.app"
        let d = page([photo, at(box, x: 500, y: 0), at(words, x: 100, y: 700)])
        let found = AccessibilityAudit.findings(d).filter { $0.kind != .contrast }
        XCTAssertEqual(found.map(\.kind), [.altText, .linkText, .linkText])
        XCTAssertEqual(found.map(\.elementId), [photo.id, photo.id, box.id])
    }

    // MARK: reading order

    /// Texts layered bottom first read top first: out of order, and the
    /// first one in reading order that is out of its place is named.
    func testTextsLayeredOutOfReadingOrder() {
        let footer = at(Element.text("Footer", fontSize: 30), x: 100, y: 900)
        let heading = at(Element.text("Heading", fontSize: 60), x: 100, y: 100)
        let mixed = page([footer, heading])
        let found = AccessibilityAudit.findings(mixed).filter { $0.kind == .readingOrder }
        XCTAssertEqual(found.map(\.elementId), [heading.id])
        XCTAssertNil(found.first?.fix)
        XCTAssertEqual(found.first?.message, "The layers are in a different order from how the page reads")
        XCTAssertFalse(kinds(page([heading, footer])).contains(.readingOrder))
        XCTAssertFalse(kinds(page([heading])).contains(.readingOrder))
    }

    /// A described picture is read too: one at the top, layered above the
    /// heading, is out of place. A decorative one is not read at all.
    func testDescribedPicturesAreInTheReadingOrder() {
        var photo = at(Element.image("media:a"), x: 0, y: 0)
        photo.altText = "A beach at dusk"
        let heading = at(Element.text("Heading"), x: 100, y: 600)
        let found = AccessibilityAudit.findings(page([heading, photo]))
        XCTAssertEqual(found.map(\.kind), [.readingOrder])
        XCTAssertEqual(found.first?.elementId, photo.id)
        var behind = at(Element.image("m"), x: 0, y: 0)
        behind.decorative = true
        XCTAssertTrue(AccessibilityAudit.findings(page([at(heading, x: 100, y: 100), behind])).isEmpty)
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

    /// Hidden pages are checked for nothing — not contrast, not alt text —
    /// so the sheet, its count and Fix all contrast leave them be.
    func testHiddenPagesAreNotChecked() {
        var pale = Element.text("Pale", fontSize: 20)
        pale.color = "#cccccc"
        var paler = Element.text("Pale", fontSize: 20)
        paler.color = "#cccccc"
        var d = Design(title: "Hidden", width: 1080, height: 1080)
        d.pages = [
            Page(elements: [pale]),
            Page(elements: [paler, Element.image("media:b")]),
        ]
        d.pages[1].hidden = true
        XCTAssertEqual(ContrastAudit.audit(d).count, 2)
        let found = AccessibilityAudit.findings(d)
        XCTAssertEqual(found.map(\.kind), [.contrast])
        XCTAssertEqual(found.map(\.elementId), [pale.id])
        XCTAssertEqual(found.first?.message, "Hard to read: 1.6:1, needs 4.5:1")
        XCTAssertEqual(AccessibilityAudit.summary(found), "1 thing on 1 page")
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
