// Copies that keep their arrows, designs that name themselves, text that
// leaves without its style marks, the page's photos as colours, and music
// that keeps its name — each as the Android twin has it.

import XCTest
import UIKit
@testable import Canvia

final class CopiesAndTitlesTests: XCTestCase {

    // MARK: copies

    /// An arrow copied with one of its boxes keeps that end, joined to the
    /// copy, and lets go of the other rather than reaching back.
    func testACopiedArrowJoinsTheCopiesOfItsEnds() {
        let box = Element.shape("rect")
        let other = Element.shape("rect")
        var arrow = Element.line(w: 100)
        arrow.connectFrom = box.id
        arrow.connectTo = other.id
        let copies = Copies.of([box, arrow], offset: 24)
        XCTAssertNotEqual(copies[0].id, box.id)
        XCTAssertEqual(copies[0].x, box.x + 24)
        XCTAssertEqual(copies[1].connectFrom, copies[0].id)
        XCTAssertNil(copies[1].connectTo, "an end that did not come along is let go")

        let alone = Copies.of([arrow])
        XCTAssertNil(alone[0].connectFrom)
        XCTAssertNil(alone[0].connectTo)
    }

    /// Duplicating two boxes and their arrow gives a second arrow following
    /// the copies — not one stacked on the original.
    func testDuplicatingBoxesAndTheirArrowJoinsTheCopies() throws {
        let s = DesignStore(design: Design(title: "arrows", width: 800, height: 800))
        var a = Element.shape("rect", w: 100, h: 100)
        a.x = 50; a.y = 50
        var b = Element.shape("rect", w: 100, h: 100)
        b.x = 400; b.y = 50
        s.applyToPage { $0.elements = [a, b] }
        s.selection = [a.id, b.id]
        s.connectSelected()
        let arrow = try XCTUnwrap(s.selectedElements.first)
        s.selection = [a.id, b.id, arrow.id]
        s.duplicateSelected()
        let copies = s.selectedElements
        let copiedArrow = try XCTUnwrap(copies.first { $0.type == .line })
        let boxes = Set(copies.filter { $0.type == .shape }.map(\.id))
        XCTAssertTrue(boxes.contains(copiedArrow.connectFrom ?? ""))
        XCTAssertTrue(boxes.contains(copiedArrow.connectTo ?? ""))
        XCTAssertEqual(copiedArrow.y, arrow.y + 24, accuracy: 0.001, "laid between the copies, not on the original")
    }

    /// A page copied whole keeps its arrows following its boxes, and its locks.
    func testACopiedPageKeepsItsArrowsAndLocks() {
        var box = Element.shape("rect")
        box.locked = true
        let other = Element.shape("rect")
        var arrow = Element.line(w: 100)
        arrow.connectFrom = box.id
        arrow.connectTo = other.id
        let page = Page(elements: [box, other, arrow])
        let copy = Copies.of(page)
        XCTAssertNotEqual(copy.id, page.id)
        XCTAssertTrue(Set(copy.elements.map(\.id)).isDisjoint(with: page.elements.map(\.id)))
        XCTAssertEqual(copy.elements[2].connectFrom, copy.elements[0].id)
        XCTAssertEqual(copy.elements[2].connectTo, copy.elements[1].id)
        XCTAssertTrue(copy.elements[0].locked, "a copied page keeps its locks")

        let landed = PageClipboard.fitted(PageClipboard.Payload(page: page, width: 1000, height: 1000),
                                          width: 500, height: 500)
        XCTAssertEqual(landed.elements[2].connectFrom, landed.elements[0].id)
        XCTAssertEqual(landed.elements[2].connectTo, landed.elements[1].id)
    }

    func testAComponentsArrowsJoinItsOwnCopies() {
        var a = Element.shape("rect", w: 100, h: 50)
        a.id = "a"
        var arrow = Element.line(w: 100)
        arrow.y = 60
        arrow.connectFrom = "a"
        arrow.connectTo = "elsewhere"
        let component = Component(name: "Tag", width: 100, height: 70, elements: [a, arrow])
        let placed = Components.instance(of: component, width: 200, at: .zero)
        XCTAssertEqual(placed[1].connectFrom, placed[0].id)
        XCTAssertNil(placed[1].connectTo)
        XCTAssertEqual(Set(placed.compactMap(\.group)).count, 1)
    }

    // MARK: titles

    func testTheHeadlineIsTheBiggestTextOnTheFirstPage() {
        var d = Design(title: "t")
        d.pages[0].elements = [Element.text("Small print", fontSize: 20),
                               Element.text("Rooftop Cinema\nFridays in July", fontSize: 120),
                               Element.text("A subheading here", fontSize: 40)]
        XCTAssertEqual(Titles.headline(d), "Rooftop Cinema")
        XCTAssertNil(Titles.headline(Design(title: "empty")))
    }

    func testTitlesAreTidiedAndPlaceholdersRefused() throws {
        XCTAssertEqual(Titles.title(from: Element.text("  Sofia's    40th  ")), "Sofia's 40th")
        XCTAssertEqual(Titles.title(from: Element.text("**Summer** sale")), "Summer sale")
        XCTAssertNil(Titles.title(from: Element.text("YOUR HEADING")))
        XCTAssertNil(Titles.title(from: Element.text("A")))
        XCTAssertNil(Titles.title(from: Element.text("— — —")))
        let long = "The quick brown fox jumps over the lazy dog again and again"
        let title = try XCTUnwrap(Titles.title(from: Element.text(long)))
        XCTAssertEqual(title, "The quick brown fox jumps over the lazy")
        XCTAssertLessThanOrEqual(title.count, Titles.maxLength)
        XCTAssertTrue(long.hasPrefix(title))
    }

    func testANewDesignNeverRepeatsATitleOnTheShelf() {
        XCTAssertEqual(Titles.unique("Poster", taken: ["Flyer"]), "Poster")
        XCTAssertEqual(Titles.unique("Poster", taken: ["poster ", "Poster 2"]), "Poster 3")
        XCTAssertEqual(Titles.unique("  ", taken: []), "Untitled design")
    }

    /// While the title is the app's, editing the headline names the design,
    /// in the same step; nothing else does.
    func testADesignNamesItselfAfterItsHeadline() {
        var d = Design(title: "Untitled Poster")
        let head = Element.text("Your heading", fontSize: 96)
        let sub = Element.text("A subheading", fontSize: 40)
        d.pages[0].elements = [head, sub]
        let s = DesignStore(design: d)

        s.select(head.id)
        s.updateSelected { $0.text = "Rooftop Cinema" }
        XCTAssertEqual(s.design.title, "Rooftop Cinema")
        s.undo()
        XCTAssertEqual(s.design.title, "Untitled Poster", "one Undo takes back the words and the name")
        XCTAssertEqual(s.element(head.id)?.text, "Your heading")

        s.select(sub.id)
        s.updateSelected { $0.text = "Fridays in July" }
        XCTAssertEqual(s.design.title, "Untitled Poster", "the subheading is not the headline")

        s.add(Element.text("Something new and big", fontSize: 200))
        XCTAssertEqual(s.design.title, "Untitled Poster", "a new text becoming the headline names nothing")

        s.apply { $0.title = "My poster"; $0.titleAuto = false }
        s.select(head.id)
        s.updateSelected { $0.text = "Open Air Films"; $0.fontSize = 300 }
        XCTAssertEqual(s.design.title, "My poster", "a name a person chose stays")
    }

    // MARK: text to other apps

    func testCopiedTextLeavesWithoutItsStyleMarks() {
        let elements = [Element.text("**SALE** today"), Element.shape("rect"), Element.text("   "),
                        Element.text("_Fridays_")]
        XCTAssertEqual(ElementClipboard.plainText(of: elements), "SALE today\nFridays")
    }

    // MARK: photo colours

    func testThePagesPhotosAreEveryPhotoOnItOnce() {
        var page = Page(background: .image("asset:bg"))
        page.elements = [Element.image("media:a"), Element.image(CodeGenerator.source(for: "x")),
                         Element.image("media:a"), Element.shape("rect"), Element.image("video:v")]
        XCTAssertEqual(PhotoPalette.sources(on: page), ["asset:bg", "media:a", "video:v"])
        XCTAssertEqual(PhotoPalette.merged([["#111111", "#222222", "#333333"], ["#111111", "#444444"], ["#555555"]]),
                       ["#111111", "#555555", "#222222", "#444444", "#333333"])
        let many = (0..<10).map { ["#\(String(repeating: String($0), count: 6))"] }
        XCTAssertEqual(PhotoPalette.merged(many).count, 8)
    }

    // MARK: soundtrack name

    func testASoundtrackKeepsItsOwnName() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Summer Song.mp3")
        try Data([1, 2, 3, 4]).write(to: source)
        let id = try XCTUnwrap(AudioStore.store(source))
        defer { AudioStore.delete(id) }
        XCTAssertEqual(AudioStore.label(for: id), "Summer Song.mp3")
        XCTAssertEqual(AudioStore.all().filter { $0.hasPrefix(id) }, [id], "the name beside it is no soundtrack")
        AudioStore.delete(id)
        XCTAssertEqual(AudioStore.label(for: id), "Audio (MP3)")
    }
}
