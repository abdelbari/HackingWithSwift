// A frame or grid cell filled with a colour in place of a photo
// (PhotoFrames.colourOf), and the shared fixture frame-colour-fill.json the
// Android twin's FrameColourFillTest reads too.

import XCTest
@testable import Canvia

final class FrameColourFillTests: XCTestCase {

    private let dark = Paint.solid("#1f2430")

    private func gradient() -> Paint {
        Paint(kind: "gradient", color: nil, angle: 90,
              stops: [GradientStop(offset: 0, color: "#ff0000"), GradientStop(offset: 1, color: "#0000ff")])
    }

    private func fixtureElement() throws -> [String: Any] {
        try XCTUnwrap(try SharedFixture.object("frame-colour-fill")["element"] as? [String: Any])
    }

    private func cell() throws -> Element {
        try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(fixtureElement()))
    }

    private func emptyFrame() -> Element {
        var el = Element.image("", w: 200, h: 200)
        el.src = ""
        return el
    }

    func testTheSharedFixtureReadsAsAColouredFrameAndWritesBackUnchanged() throws {
        let el = try cell()
        XCTAssertEqual(el.type, .image)
        XCTAssertEqual(el.maskShapeId, "mask:blob-1")
        XCTAssertEqual(PhotoFrames.colourOf(el), dark)
        XCTAssertTrue(PhotoFrames.isFrameLike(el, among: [el]))
        let back = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any])
        for (key, value) in try fixtureElement() {
            if key == "fill" {
                let fill = try XCTUnwrap(back["fill"] as? [String: Any])
                XCTAssertEqual(fill["kind"] as? String, "solid")
                XCTAssertEqual(fill["color"] as? String, "#1f2430")
            } else if let text = value as? String {
                XCTAssertEqual(back[key] as? String, text, key)
            } else {
                XCTAssertEqual((back[key] as? NSNumber)?.doubleValue, (value as? NSNumber)?.doubleValue, key)
            }
        }
    }

    func testAColouredFrameIsSpokenAsFilledWithItsColour() throws {
        let spoken = try XCTUnwrap(try SharedFixture.object("frame-colour-fill")["spoken"] as? String)
        XCTAssertEqual(ElementNames.name(of: try cell()), spoken)
    }

    func testOnlyASolidColourOrAGradientOnAFrameWithNoPictureIsAColour() {
        var empty = emptyFrame()
        XCTAssertNil(PhotoFrames.colourOf(empty))
        empty.fill = dark
        XCTAssertEqual(PhotoFrames.colourOf(empty), dark)
        empty.fill = gradient()
        XCTAssertEqual(PhotoFrames.colourOf(empty), gradient())
        // A photo in it: its fill is not drawn.
        var photo = empty
        photo.src = "media:1"
        photo.fill = dark
        XCTAssertNil(PhotoFrames.colourOf(photo))
        empty.fill = .clear
        XCTAssertNil(PhotoFrames.colourOf(empty))
        empty.fill = .image("media:1")
        XCTAssertNil(PhotoFrames.colourOf(empty))
    }

    func testOnlyAnUnlockedFrameWithNoPictureTakesAColour() {
        let empty = emptyFrame()
        XCTAssertTrue(PhotoFrames.takesColour(empty))
        XCTAssertEqual(PhotoFrames.coloured(empty, dark).fill, dark)
        var photo = empty
        photo.src = "media:1"
        XCTAssertEqual(PhotoFrames.coloured(photo, dark), photo)
        var locked = empty
        locked.locked = true
        XCTAssertEqual(PhotoFrames.coloured(locked, dark), locked)
        // The colour sheet's swatches colour it, as they colour a shape,
        // and a gradient fills it; a photo keeps its own.
        XCTAssertEqual(DesignStore.recoloured(empty, to: "#ff0000").fill, .solid("#ff0000"))
        XCTAssertEqual(DesignStore.recoloured(photo, to: "#ff0000"), photo)
        XCTAssertEqual(DesignStore.withGradient(empty, gradient()).fill, gradient())
        XCTAssertEqual(DesignStore.withGradient(empty, .pattern("dots", color: "#000000", secondary: "#ffffff")), empty)
    }

    func testPickedPhotosSkipAColouredCell() {
        var top = emptyFrame()
        top.id = "top"
        top.fill = dark
        var bottom = emptyFrame()
        bottom.id = "bottom"
        bottom.y = 300
        XCTAssertEqual(PhotoFrames.fillOrder([top, bottom]).map(\.id), ["bottom"])
    }

    func testItsColoursAreThePagesColours() throws {
        let white = Background.color("#ffffff")
        XCTAssertEqual(ColorTools.pageColours(Page(background: white, elements: [try cell()])), ["#ffffff", "#1f2430"])
        var gradientCell = try cell()
        gradientCell.fill = gradient()
        XCTAssertEqual(ColorTools.pageColours(Page(background: white, elements: [gradientCell])),
                       ["#ffffff", "#ff0000", "#0000ff"])
        var photo = try cell()
        photo.src = "media:1"
        XCTAssertEqual(ColorTools.pageColours(Page(background: white, elements: [photo])), ["#ffffff"])
    }

    func testAPhotoPutInDropsTheColourAndDetachLeavesTheFrameWithNone() throws {
        let coloured = try cell()
        let filled = Copies.filled(coloured, with: Element.image("media:9"), foreign: true)
        XCTAssertEqual(filled.src, "media:9")
        XCTAssertNil(filled.fill)
        XCTAssertNil(Crop.replaced(coloured, src: nil).fill)
        // Dropped onto it from the page, a photo takes its place too.
        var photo = Element.image("media:2")
        photo.id = "photo"
        photo.x = 900
        let dropped = try XCTUnwrap(PhotoFrames.dropped([coloured, photo], dragged: "photo", onto: coloured.id,
                                                        home: .zero))
        XCTAssertNil(dropped.first { $0.id == coloured.id }?.fill)
        let detached = try XCTUnwrap(PhotoFrames.detached([filled], id: filled.id))
        let left = try XCTUnwrap(detached.first { $0.id == filled.id })
        XCTAssertNil(left.fill)
        XCTAssertTrue(PhotoFrames.isEmpty(left))
        // A shape replaced keeps its fill: only a photo's goes.
        let shape = Element.shape("rect")
        XCTAssertEqual(Crop.replaced(shape, src: nil).fill, shape.fill)
    }

    @MainActor
    func testSVGWritesAColouredFrameAsAPathInItsFramesShape() {
        var el = emptyFrame()
        el.x = 10
        el.y = 20
        el.fill = dark
        el.maskShapeId = "circle"
        var d = Design(title: "Frames", width: 1080, height: 1080)
        d.pages = [Page(background: .color("#ffffff"), elements: [el])]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("<g transform=\"translate(10 20)\"><path d=\"M"), svg)
        XCTAssertTrue(svg.contains("fill=\"#1f2430\""), svg)
        XCTAssertFalse(svg.contains("<image"), svg)
        // A plain cell, its rectangle; a gradient, by its def.
        var plain = emptyFrame()
        plain.w = 100
        plain.h = 50
        plain.fill = gradient()
        d.pages = [Page(background: .color("#ffffff"), elements: [plain])]
        let second = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(second.contains("fill=\"url(#grad0)\""), second)
        XCTAssertTrue(second.contains("id=\"grad0\""), second)
        XCTAssertFalse(second.contains("<image"), second)
    }

    func testPowerPointWritesAColouredFrameAsAShapeInItsOutline() {
        var el = emptyFrame()
        el.fill = dark
        el.maskShapeId = "circle"
        XCTAssertEqual(PptxExporter.form(of: el), .geometry)
        var plain = emptyFrame()
        plain.fill = dark
        XCTAssertEqual(PptxExporter.form(of: plain), .shape("rect"))
        plain.radius = 12
        XCTAssertEqual(PptxExporter.form(of: plain), .shape("roundRect"))
        var d = Design(title: "Frames", width: 800, height: 600)
        d.pages = [Page(background: .color("#ffffff"), elements: [el])]
        let xml = PptxExporter.slide(design: d, page: d.pages[0], number: 1, previous: nil, firstImage: 1).xml
        XCTAssertTrue(xml.contains("<a:custGeom>"), xml)
        XCTAssertTrue(xml.lowercased().contains("<a:solidfill><a:srgbclr val=\"1f2430\""), xml)
        XCTAssertFalse(xml.contains("<p:pic>"), xml)
        // An empty frame with no colour is still the picture the canvas draws.
        XCTAssertEqual(PptxExporter.form(of: emptyFrame()), .picture)
    }
}
