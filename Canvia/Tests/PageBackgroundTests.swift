// A page's background from a photo on it, and a background picture taken
// back out as a photo: what may become one, what is baked first, and that
// each is one step.

import XCTest
@testable import Canvia

@MainActor
final class PageBackgroundTests: XCTestCase {

    private var stored: [String] = []

    override func tearDown() {
        for src in stored where src.hasPrefix("media:") {
            MediaStore.delete(String(src.dropFirst(6)))
        }
        stored = []
        super.tearDown()
    }

    private func store(_ elements: [Element], background: Background = .color("#ffffff")) -> DesignStore {
        var design = Design(title: "backgrounds", width: 800, height: 600)
        design.pages[0].elements = elements
        design.pages[0].background = background
        return DesignStore(design: design)
    }

    // MARK: what may become the background

    func testOnlyAnUnlockedStillPhotoCanBecomeTheBackground() {
        XCTAssertTrue(DesignStore.canBecomeBackground(Element.image("asset:mesh-sunset")))
        XCTAssertFalse(DesignStore.canBecomeBackground(Element.image("video:vid_1")), "a clip")
        XCTAssertFalse(DesignStore.canBecomeBackground(Element.image(CodeGenerator.source(for: "hi"))), "a code")
        var empty = Element.image("")
        empty.src = nil
        XCTAssertFalse(DesignStore.canBecomeBackground(empty), "an empty frame")
        var locked = Element.image("asset:mesh-sunset")
        locked.locked = true
        XCTAssertFalse(DesignStore.canBecomeBackground(locked))
        XCTAssertFalse(DesignStore.canBecomeBackground(Element.shape("rect")))
    }

    func testEveryLookCountsAndAPlainPhotoHasNone() {
        let plain = Element.image("asset:mesh-sunset")
        XCTAssertFalse(DesignStore.hasLook(plain))
        let looks: [(String, (inout Element) -> Void)] = [
            ("filter", { $0.filter = "noir" }),
            ("adjustments", { el in
                var dials = Adjustments()
                dials.brightness = 0.2
                el.adjustments = dials
            }),
            ("duotone", { $0.duotone = Duotone.presets[0].tone }),
            ("crop", { $0.cropScale = 1.5 }),
            ("frame", { $0.maskShapeId = "circle" }),
            ("flip", { $0.flipH = true }),
            ("straighten", { $0.straighten = 4 }),
            ("corners", { $0.radius = 12 }),
        ]
        for (name, give) in looks {
            var el = plain
            give(&el)
            XCTAssertTrue(DesignStore.hasLook(el), name)
        }
    }

    // MARK: use as background

    /// A plain photo's own picture goes behind the page, and the photo
    /// leaves it, in one step.
    func testAPlainPhotoBecomesTheBackgroundInOneStep() {
        var el = Element.image("asset:mesh-sunset", w: 300, h: 200)
        el.rotation = 30
        let other = Element.shape("rect")
        let s = store([el, other])
        s.selection = [el.id]
        s.useAsBackground(el.id)
        XCTAssertEqual(s.page.background, .image("asset:mesh-sunset"))
        XCTAssertEqual(s.page.elements.map(\.id), [other.id])
        XCTAssertTrue(s.selection.isEmpty)
        s.undo()
        XCTAssertEqual(s.page.background, .color("#ffffff"))
        XCTAssertEqual(s.page.elements.count, 2)
        XCTAssertFalse(s.canUndo)
    }

    /// A photo with a look goes behind the page as it showed: a new picture
    /// of its own, never the plain one it was drawn from.
    func testAPhotoWithALookIsBakedIntoAPictureOfItsOwn() throws {
        var el = Element.image("asset:mesh-sunset", w: 300, h: 200)
        el.flipH = true
        el.radius = 40
        let s = store([el])
        s.useAsBackground(el.id)
        guard case .image(let src) = s.page.background else { return XCTFail("no picture behind the page") }
        stored.append(src)
        XCTAssertTrue(src.hasPrefix("media:"))
        let picture = try XCTUnwrap(PhotoLibrary.resolve(src))
        XCTAssertEqual(picture.size.width / picture.size.height, 1.5, accuracy: 0.02)
        XCTAssertTrue(s.page.elements.isEmpty)
    }

    func testALockedPhotoStaysOnThePage() {
        var el = Element.image("asset:mesh-sunset")
        el.locked = true
        let s = store([el])
        s.useAsBackground(el.id)
        XCTAssertEqual(s.page.elements.count, 1)
        XCTAssertEqual(s.page.background, .color("#ffffff"))
        XCTAssertFalse(s.canUndo)
    }

    /// Baked at the picture's own detail, but never past a kept photo's edge.
    func testBakingKeepsThePicturesDetailWithinTheKeptEdge() {
        let el = Element.image("asset:x", w: 300, h: 200)
        // A 1200 × 900 picture covering 300 × 200 shows 4 pixels a unit.
        XCTAssertEqual(DesignStore.bakeScale(el, picture: CGSize(width: 1200, height: 900)), 4, accuracy: 1e-9)
        var zoomed = el
        zoomed.cropScale = 2
        XCTAssertEqual(DesignStore.bakeScale(zoomed, picture: CGSize(width: 1200, height: 900)), 2, accuracy: 1e-9)
        let huge = DesignStore.bakeScale(el, picture: CGSize(width: 12000, height: 9000))
        XCTAssertEqual(huge * 300, Double(ImageDownsampler.keptEdge), accuracy: 1e-6)
    }

    // MARK: detach

    /// The picture comes out as a photo covering the page, behind the rest,
    /// selected; the page is left white. One step.
    func testDetachingTheBackgroundMakesAPhotoBehindEverything() throws {
        let top = Element.shape("rect")
        let s = store([top], background: .image("asset:mesh-ocean"))
        s.detachBackground()
        XCTAssertEqual(s.page.background, .color("#ffffff"))
        XCTAssertEqual(s.page.elements.count, 2)
        let photo = s.page.elements[0]
        XCTAssertEqual(photo.type, .image)
        XCTAssertEqual(photo.src, "asset:mesh-ocean")
        XCTAssertEqual(photo.frame, CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(photo.cropScale, 1)
        XCTAssertEqual(photo.cropX, 0.5)
        XCTAssertEqual(s.page.elements[1].id, top.id)
        XCTAssertEqual(s.selection, [photo.id])
        s.undo()
        XCTAssertEqual(s.page.background, .image("asset:mesh-ocean"))
        XCTAssertEqual(s.page.elements.map(\.id), [top.id])
    }

    func testNothingToDetachFromAColour() {
        let s = store([])
        s.detachBackground()
        XCTAssertTrue(s.page.elements.isEmpty)
        XCTAssertFalse(s.canUndo)
    }

    // MARK: setting it

    func testTheSameBackgroundAgainRecordsNothing() {
        let s = store([], background: .color("#112233"))
        s.setBackground(.color("#112233"))
        XCTAssertFalse(s.canUndo)
        s.setBackground(.image("media:img_mine"))
        XCTAssertEqual(s.page.background, .image("media:img_mine"))
        XCTAssertTrue(s.canUndo)
    }

    /// A turn of the colour wheel is one step, however many colours it
    /// passed through.
    func testAWheelTurnIsOneStep() {
        let s = store([])
        s.setBackgroundTransient(.color("#101010"))
        s.setBackgroundTransient(.color("#202020"))
        s.setBackgroundTransient(.color("#303030"))
        s.commit()
        XCTAssertEqual(s.page.background, .color("#303030"))
        s.undo()
        XCTAssertEqual(s.page.background, .color("#ffffff"))
        XCTAssertFalse(s.canUndo)
    }
}
