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

    @MainActor
    private func storeWithPhoto(locked: Bool) -> (DesignStore, String) {
        var design = Design(title: "D", width: 400, height: 400)
        var photo = Element.image("asset:sun")
        photo.locked = locked
        design.pages[0].elements = [photo]
        return (DesignStore(design: design), photo.id)
    }

    @MainActor
    func testTheEraserIsRefusedOnALockedPhoto() {
        let (store, id) = storeWithPhoto(locked: true)
        store.beginErasing(id)
        XCTAssertNil(store.erasing)
        XCTAssertEqual(store.haptic.kind, .reject)
        let (open, other) = storeWithPhoto(locked: false)
        open.beginErasing(other)
        XCTAssertEqual(open.erasing, other)
    }

    @MainActor
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

    // MARK: corners

    func testARoundDragKeepsWhichCornersRound() {
        var card = Element.shape("rect", w: 200, h: 100)
        card.radius = 10
        card.corners = [10, 10, 0, 0]
        let held = CornerPatterns.pattern(of: card)
        XCTAssertEqual(held?.name, "Top only")
        // Through zero and back: the pattern read as the drag began is kept.
        CornerPatterns.setRadius(0, keeping: held, on: &card)
        CornerPatterns.setRadius(24, keeping: held, on: &card)
        XCTAssertEqual(card.radius, 24)
        XCTAssertEqual(card.corners ?? [], [24, 24, 0, 0])
    }

    func testAPatternCanBeChosenFromSquare() {
        var card = Element.shape("rect", w: 200, h: 100)
        XCTAssertNil(CornerPatterns.pattern(of: card))
        CornerPatterns.apply(CornerPatterns.choices[2], to: &card)
        XCTAssertEqual(card.radius ?? 0, 20, accuracy: 0.001, "a fifth of the shorter side")
        XCTAssertEqual(card.corners ?? [], [0, 0, 20, 20])
        CornerPatterns.apply(CornerPatterns.choices[0], to: &card)
        XCTAssertNil(card.corners, "all corners is the plain radius")
        XCTAssertEqual(CornerPatterns.pattern(of: card)?.name, "All corners")
    }

    func testRadiiOfTheirOwnAreNoPattern() {
        var card = Element.shape("rect", w: 200, h: 100)
        card.corners = [10, 20, 0, 0]
        XCTAssertNil(CornerPatterns.pattern(of: card))
    }

    // MARK: fills and photo edits

    func testTheFillThereNowIsRecognised() {
        let pattern = Paint.pattern("dots", color: "#000000", secondary: "#ffffff")
        XCTAssertTrue(FillChoices.isPattern(pattern, named: "dots"))
        XCTAssertFalse(FillChoices.isPattern(pattern, named: "stripes"))
        XCTAssertTrue(FillChoices.isPhoto(.image("asset:sun"), src: "asset:sun"))
        XCTAssertFalse(FillChoices.isPhoto(.solid("#000000"), src: "asset:sun"))
        if let preset = ContentLibrary.gradients.first {
            XCTAssertTrue(FillChoices.isGradient(preset.paint(kind: "radial"), preset.paint(kind: "radial")))
            XCTAssertFalse(FillChoices.isGradient(preset.paint(kind: "linear"), preset.paint(kind: "radial")))
        }
    }

    func testOnlyShapesAreOfferedPatterns() {
        XCTAssertFalse(FillChoices.offersPatterns(for: [Element.text("Hi")]))
        XCTAssertTrue(FillChoices.offersPatterns(for: [Element.text("Hi"), Element.shape("rect")]))
    }

    func testResetPhotoEditsTakesOffTheLookAndKeepsTheCrop() {
        var photo = Element.image("asset:sun")
        XCTAssertFalse(PhotoEdits.any(photo))
        photo.filter = "vivid"
        photo.duotone = Duotone.presets.first?.tone
        photo.straighten = 4
        photo.cropFit = true
        photo.cropScale = 2
        photo.radius = 12
        XCTAssertTrue(PhotoEdits.any(photo))
        PhotoEdits.reset(&photo)
        XCTAssertFalse(PhotoEdits.any(photo))
        XCTAssertNil(photo.filter)
        XCTAssertNil(photo.duotone)
        XCTAssertNil(photo.straighten)
        XCTAssertEqual(photo.cropScale, 2)
        XCTAssertEqual(photo.radius, 12)
    }

    // MARK: matched with the Android side's own round

    func testTheTableSummaryUsesSingularWords() {
        XCTAssertEqual(DataGraphics.tableSummary([]), "Nothing to tabulate yet.")
        XCTAssertEqual(DataGraphics.tableSummary([["a"]]), "1 row × 1 column; the first row is the header.")
        XCTAssertEqual(DataGraphics.tableSummary([["a", "b", "c"], ["d"], ["e", "f"]]),
                       "3 rows × 3 columns; the first row is the header.")
    }

    func testFaintColoursAreLeftOutOfTheDesignsColours() {
        var d = Design(title: "D", width: 100, height: 100)
        var wash = Element.shape("rect")
        wash.fill = .solid("#00000033")
        var a = Element.shape("rect")
        a.fill = .solid("#ff0000")
        // Red twice, so it outranks the page's white; the wash, three times, would outrank both.
        d.pages[0].elements = [wash, wash, wash, a, a]
        XCTAssertEqual(ColorTools.documentColors(d, limit: 1), ["#ff0000"])
    }

    func testPhotoFillsLeaveOutCodesAndSayWhichPictureTheyAre() {
        var d = Design(title: "D", width: 100, height: 100)
        d.pages[0].elements = [Element.image("media:a"), Element.image(CodeGenerator.source(for: "hi")),
                               Element.image("media:b"), Element.image("media:a")]
        let sources = FillChoices.photoFillSources(d)
        XCTAssertEqual(Array(sources.suffix(2)), ["media:a", "media:b"])
        XCTAssertEqual(FillChoices.photoFillLabel("media:b", sources: sources),
                       "Fill with photo 2 of 2 from this design")
        XCTAssertEqual(FillChoices.photoFillLabel("media:z", sources: sources), "Fill with photo")
        if let first = PhotoLibrary.photos.first {
            XCTAssertEqual(FillChoices.photoFillLabel("asset:\(first.id)", sources: sources), "Fill with \(first.name)")
        }
    }

    func testAFillThatIsNotOneColourIsSaidForWhatItIs() {
        XCTAssertEqual(FillChoices.spokenFill(.image("asset:sun")), "photo")
        XCTAssertEqual(FillChoices.spokenFill(.clear), "no fill")
        XCTAssertNil(FillChoices.spokenFill(.solid("#ff0000")))
        XCTAssertTrue(FillChoices.spokenFill(.pattern("dots", color: "#ff0000", secondary: "#ffffff"))?
            .hasSuffix(" pattern") ?? false)
    }

    func testTheLoupeGoesBelowTheFingerWhenThereIsNoRoomAbove() {
        let size = CGSize(width: 300, height: 400)
        XCTAssertEqual(Eyedropper.loupeCentre(for: CGPoint(x: 150, y: 200), in: size), CGPoint(x: 150, y: 160))
        XCTAssertEqual(Eyedropper.loupeCentre(for: CGPoint(x: 150, y: 10), in: size), CGPoint(x: 150, y: 50))
        XCTAssertEqual(Eyedropper.loupeCentre(for: CGPoint(x: 2, y: 10), in: size).x, 22)
    }

    @MainActor
    func testConnectingTheWrongSelectionIsRefused() {
        let (store, id) = storeWithPhoto(locked: false)
        store.selection = [id]
        store.connectSelected()
        XCTAssertEqual(store.haptic.kind, .reject)
        XCTAssertEqual(store.page.elements.count, 1)
    }
}
