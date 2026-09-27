// The media and content parity with the Android twin: templates fitted to
// the page's own size, the editor's template list, shape groups, the brand
// kit's logo list, the Add sheet's spoken names and the SVG import cap.

import XCTest
@testable import Canvia

final class MediaContentParityTests: XCTestCase {

    private func template(width: Double, height: Double, elements: [Element]) -> Template {
        Template(id: "t", name: "T", category: "Test", width: width, height: height,
                 background: .color("#ffffff"), elements: elements)
    }

    // MARK: templates

    func testATemplateIsFittedToTheSizeItIsGivenAndCentred() {
        var card = Element.shape("rect", w: 400, h: 200)
        card.x = 100; card.y = 100
        let t = template(width: 1080, height: 1080, elements: [card])
        // A page of its own, half the width of the document it sits in.
        let page = t.makePage(width: 540, height: 960)
        let el = page.elements[0]
        XCTAssertEqual(el.w, 200, accuracy: 0.001)
        XCTAssertEqual(el.h, 100, accuracy: 0.001)
        XCTAssertEqual(el.x, 50, accuracy: 0.001)
        // (960 − 540) / 2 down, then the element's own 100 × 0.5.
        XCTAssertEqual(el.y, 210 + 50, accuracy: 0.001)
    }

    func testFittingToADesignIsFittingToItsSize() {
        var card = Element.shape("rect", w: 400, h: 200)
        card.x = 10; card.y = 20
        let t = template(width: 1080, height: 1920, elements: [card])
        let design = Design(title: "D", width: 1080, height: 1080)
        let a = t.makePage(for: design).elements[0]
        let b = t.makePage(width: 1080, height: 1080).elements[0]
        XCTAssertEqual(a.x, b.x, accuracy: 0.001)
        XCTAssertEqual(a.y, b.y, accuracy: 0.001)
        XCTAssertEqual(a.w, b.w, accuracy: 0.001)
    }

    func testRoundingScalesWithTheTemplateAsOnAndroid() {
        var card = Element.shape("rect", w: 400, h: 200)
        card.radius = 24
        card.corners = [24, 24, 0, 0]
        let t = template(width: 1080, height: 1080, elements: [card])
        let el = t.makePage(width: 2160, height: 2160).elements[0]
        XCTAssertEqual(el.radius ?? 0, 48, accuracy: 0.001)
        XCTAssertEqual(el.corners ?? [], [24, 24, 0, 0], "per-corner radii are left as they are on both phones")
    }

    func testTheEditorListLeadsWithThisSizeAndOffersEverySize() {
        guard let first = ContentLibrary.templates.first else { return XCTFail("no templates") }
        let exact = ContentLibrary.editorTemplates(width: first.width, height: first.height,
                                                   everySize: false, matching: "")
        XCTAssertFalse(exact.isEmpty)
        XCTAssertTrue(exact.allSatisfy { $0.width == first.width && $0.height == first.height })
        let every = ContentLibrary.editorTemplates(width: first.width, height: first.height,
                                                   everySize: true, matching: "")
        XCTAssertEqual(every.count, ContentLibrary.templates.count)
    }

    func testASizeNothingIsMadeForGetsEveryTemplateAndSaysSo() {
        let list = ContentLibrary.editorTemplates(width: 1234, height: 567, everySize: false, matching: "")
        XCTAssertEqual(list.count, ContentLibrary.templates.count)
        XCTAssertTrue(ContentLibrary.editorTemplatesNote(exactCount: 0).hasPrefix("Nothing is made for this exact size"))
        XCTAssertEqual(ContentLibrary.editorTemplatesNote(exactCount: 3),
                       "Replaces what is on this page. Undo brings it back.")
    }

    func testTheEditorListIsSearchedByNameOrKind() {
        guard let first = ContentLibrary.templates.first else { return XCTFail("no templates") }
        let found = ContentLibrary.editorTemplates(width: 1, height: 1, everySize: true, matching: first.category)
        XCTAssertTrue(found.contains { $0.id == first.id })
        XCTAssertTrue(found.allSatisfy {
            $0.name.localizedCaseInsensitiveContains(first.category)
                || $0.category.localizedCaseInsensitiveContains(first.category)
        })
    }

    // MARK: shapes

    func testShapeGroupsAreNamedAsOnAndroidAndFoundBySearch() {
        XCTAssertEqual(ContentLibrary.shapeGroupName("Stars"), "Stars and badges")
        XCTAssertEqual(ContentLibrary.shapeGroupName("Callouts"), "Speech and labels")
        XCTAssertEqual(ContentLibrary.shapeGroupName("Decor"), "Decorative")
        for category in ContentLibrary.shapeCategories {
            XCTAssertNotNil(ContentLibrary.shapeGroupNames[category], "\(category) has no group name")
        }
        let badges = ContentLibrary.shapes.filter { ContentLibrary.shape($0, matches: "badge") }
        let stars = ContentLibrary.shapes.filter { $0.category == "Stars" }
        XCTAssertEqual(Set(badges.map(\.id)).isSuperset(of: stars.map(\.id)), true,
                       "a search for the group finds the whole group")
    }

    // MARK: brand kit

    func testLogoCandidatesKeepWhatTheSheetOpenedWithAndLeaveOutCodes() {
        var design = Design(title: "D", width: 400, height: 400)
        design.pages[0].elements = [
            Element.image("media:photo"),
            Element.image(CodeGenerator.source(for: "https://canvia.app")),
            Element.image("media:logo"),
        ]
        // The logo was on when the sheet opened and has been switched off.
        let list = BrandKit.logoCandidates(openedWith: ["media:old"], current: [], design: design)
        XCTAssertEqual(list, ["media:old", "media:photo", "media:logo"])
        let again = BrandKit.logoCandidates(openedWith: ["media:logo"], current: ["media:logo"], design: design)
        XCTAssertEqual(again, ["media:logo", "media:photo"], "each picture once")
    }

    // MARK: add sheet names

    func testPictureTilesSayWhichTheyAreAndWhetherStarredOrInTheFrame() {
        XCTAssertEqual(AddSheetNames.picture(AddSheetNames.upload(2, of: 12), starred: false, inFrame: false),
                       "Uploaded picture 3 of 12")
        XCTAssertEqual(AddSheetNames.picture(AddSheetNames.logo(0, of: 2), starred: true, inFrame: true),
                       "Brand logo 1 of 2, favourite, the one in this frame now")
        let photo = PhotoDef(id: "sun", name: "Sunrise", category: "Nature")
        XCTAssertEqual(AddSheetNames.artwork(photo, 0, of: 5), "Sunrise, nature, artwork 1 of 5")
    }

    // MARK: svg

    func testAnSVGOverTheCapIsNoShape() throws {
        let dir = FileManager.default.temporaryDirectory
        let small = dir.appendingPathComponent("shape-\(UUID().uuidString).svg")
        let big = dir.appendingPathComponent("shape-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: small); try? FileManager.default.removeItem(at: big) }
        let svg = #"<svg viewBox="0 0 10 10"><path d="M0,0L10,0L10,10Z"/></svg>"#
        try Data(svg.utf8).write(to: small)
        XCTAssertNotNil(SVGPath.importFirstPath(fromFileAt: small))
        let padding = String(repeating: " ", count: SVGPath.maxImportBytes)
        try Data((svg + padding).utf8).write(to: big)
        XCTAssertNil(SVGPath.importFirstPath(fromFileAt: big))
    }

    // MARK: photos and drawing

    private func storeWithPhoto(locked: Bool) -> (DesignStore, String) {
        var design = Design(title: "D", width: 400, height: 400)
        var photo = Element.image("asset:sun")
        photo.locked = locked
        design.pages[0].elements = [photo]
        return (DesignStore(design: design), photo.id)
    }

    func testTheEraserIsRefusedOnALockedPhoto() {
        let (store, id) = storeWithPhoto(locked: true)
        store.beginErasing(id)
        XCTAssertNil(store.erasing)
        XCTAssertEqual(store.haptic.kind, .reject)
        let (open, other) = storeWithPhoto(locked: false)
        open.beginErasing(other)
        XCTAssertEqual(open.erasing, other)
    }

    func testThePenIsRememberedBetweenDrawingSessions() {
        let (store, _) = storeWithPhoto(locked: false)
        store.toggleDrawing()
        store.drawing?.pen = .highlighter
        store.drawing?.width = 24
        store.drawing?.color = "#e5484d"
        store.toggleDrawing()
        XCTAssertNil(store.drawing)
        store.toggleDrawing()
        XCTAssertEqual(store.drawing, Freehand.Tool(color: "#e5484d", width: 24, pen: .highlighter))
    }

    func testTheDrawingHintFollowsThePen() {
        XCTAssertEqual(Freehand.Pen.pen.hint, "One finger draws, two move the page")
        XCTAssertEqual(Freehand.Pen.eraser.hint, "Drag over strokes to take them away")
        XCTAssertFalse(Freehand.Pen.eraser.hasInk)
        XCTAssertTrue(Freehand.Pen.highlighter.hasInk)
    }
}
