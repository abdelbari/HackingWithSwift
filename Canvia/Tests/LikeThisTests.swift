// More like this: what is offered (ElementSearch.similar) and how one is
// swapped in (LikeThis.replaced, DesignStore.replaceSelected) — the Android
// twin's LikeThisTest's rows. The shape library's ids are this phone's own
// ("star-5", "rect"), its order the same rule.

import XCTest
@testable import Canvia

@MainActor
final class LikeThisTests: XCTestCase {

    func testAnIconIsOfferedItsCategoryMostTagsInCommonFirst() throws {
        let icon = try XCTUnwrap(IconLibrary.icon("favorite"))
        let heart = IconLibrary.element(icon, pageWidth: 1000, pageHeight: 1000, fill: "#ff0000")
        let hits = ElementSearch.similar(heart)
        XCTAssertEqual(hits.count, 24)
        XCTAssertEqual(hits.prefix(5).map(\.id), ["heart_broken", "star", "check", "check_circle", "close"])
        XCTAssertTrue(hits.allSatisfy { $0.kind == .icon && IconLibrary.icon($0.id)?.category == "Symbols" })
        XCTAssertFalse(hits.contains { $0.id == "favorite" })
    }

    func testAStickerIsOfferedItsGroupThenEmojiSharingAWord() {
        XCTAssertEqual(ElementSearch.similar(.sticker("🎉")).map(\.id),
                       ["🎊", "🎈", "🎂", "🎁", "🥳", "🍾", "✨", "🎆", "🏆", "🎖️", "💝"])
        let cat = ElementSearch.similar(.sticker("🐈")).map(\.id)
        XCTAssertTrue(cat.contains("🐱"))
        XCTAssertEqual(cat.first, "😸")
        XCTAssertTrue(ElementSearch.similar(.sticker("🐙")).isEmpty)
        // A toned one is offered as its plain self would be.
        XCTAssertEqual(ElementSearch.similar(.sticker("👍🏽")).first?.id, "👎")
    }

    func testAGraphicIsOfferedItsCategoryAShapeTheShapeSwaps() throws {
        let sparkle = GraphicsLibrary.elements(try XCTUnwrap(GraphicsLibrary.graphic("sparkle-03")),
                                               pageWidth: 1000, pageHeight: 1000)
        let hits = ElementSearch.similar(try XCTUnwrap(sparkle.last))
        XCTAssertEqual(hits.count, 16)
        XCTAssertEqual(hits.prefix(3).map(\.id), ["sparkle-01", "sparkle-02", "sparkle-04"])
        let star = ElementSearch.similar(.shape("star-5"))
        XCTAssertEqual(star.prefix(6).map(\.id), ["star-4", "star-6", "star-8", "seal", "burst-16", "rect"])
        XCTAssertEqual(star.count, 24)
        // A photo, or a drawn or traced outline, is no library shape:
        // nothing like it.
        XCTAssertTrue(ElementSearch.similar(.image("media:x")).isEmpty)
        var traced = Element.shape("rect")
        traced.pathData = "M0 0L100 0L50 100Z"
        XCTAssertTrue(ElementSearch.similar(traced).isEmpty)
    }

    func testASwapKeepsTheBoxFittedTheTurnOpacityMotionLinkAndMainColour() throws {
        var old = Element.shape("star-5", w: 200, h: 100)
        old.x = 100; old.y = 50
        old.rotation = 30
        old.opacity = 0.5
        old.fill = .solid("#123456")
        old.animation = ElementAnimation(kind: "pop", delay: 0, duration: 0.5)
        old.link = "https://example.com"
        var fresh = Element.shape("heart", w: 50, h: 50)
        fresh.fill = .solid("#ff0000")
        let swapped = try XCTUnwrap(LikeThis.replaced([old], with: [fresh]).first)
        XCTAssertEqual(swapped.id, old.id)
        XCTAssertEqual(swapped.shapeId, "heart")
        // A square in a 200 x 100 box: 100 x 100, centred.
        XCTAssertEqual(swapped.x, 150, accuracy: 1e-9)
        XCTAssertEqual(swapped.y, 50, accuracy: 1e-9)
        XCTAssertEqual(swapped.w, 100, accuracy: 1e-9)
        XCTAssertEqual(swapped.h, 100, accuracy: 1e-9)
        XCTAssertEqual(swapped.rotation, 30, accuracy: 1e-9)
        XCTAssertEqual(swapped.opacity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(swapped.fill?.color, "#123456")
        XCTAssertEqual(swapped.animation, old.animation)
        XCTAssertEqual(swapped.link, old.link)
    }

    func testAGraphicSwappedForAnotherKeepsItsGroupAndMapsItsFirstColour() throws {
        let old = GraphicsLibrary.elements(try XCTUnwrap(GraphicsLibrary.graphic("blob-02")), pageWidth: 1000, pageHeight: 1000)
        let fresh = GraphicsLibrary.elements(try XCTUnwrap(GraphicsLibrary.graphic("blob-03")), pageWidth: 500, pageHeight: 500)
        let swapped = LikeThis.replaced(old, with: fresh)
        XCTAssertEqual(swapped.count, fresh.count)
        XCTAssertTrue(swapped.allSatisfy { $0.group == old[0].group && GraphicsLibrary.graphic(of: $0)?.id == "blob-03" })
        XCTAssertEqual(ColourSwap.colours(swapped).first, ColourSwap.colours(old).first)
        // Fitted inside the old box.
        let minX = (old.map(\.x).min() ?? 0) - 1e-6
        let maxX = (old.map { $0.x + $0.w }.max() ?? 0) + 1e-6
        XCTAssertTrue(swapped.allSatisfy { $0.x >= minX && $0.x + $0.w <= maxX })
    }

    func testTheStoreSwapsTheSelectionInOneStepInItsPlaceAmongTheLayers() {
        let s = DesignStore(design: Design(title: "like", width: 1000, height: 1000))
        s.add(.shape("rect"))
        s.add(.sticker("🎉"))
        s.add(.shape("circle"))
        let sticker = s.page.elements[1]
        s.select(sticker.id)
        XCTAssertTrue(s.replaceSelected(with: [.sticker("🎊")]))
        XCTAssertEqual(s.page.elements[1].glyph, "🎊")
        XCTAssertEqual(s.page.elements[1].id, sticker.id)
        XCTAssertEqual(s.selection, [sticker.id])
        s.undo()
        XCTAssertEqual(s.page.elements[1].glyph, "🎉")
        // Something locked keeps what it is.
        s.select(sticker.id)
        s.updateSelected { $0.locked = true }
        XCTAssertFalse(s.replaceSelected(with: [.sticker("🎊")]))
        XCTAssertEqual(s.page.elements[1].glyph, "🎉")
    }
}
