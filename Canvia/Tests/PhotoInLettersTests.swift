// A photo inside a text's letters, and the letter and number frames — the
// rows the Android twin's PhotoFillsTest, PhotoFramesTest, TextEffectsTest,
// PhotoPaletteTest, PptxWriterTest, SvgWriterTest and
// AccessibilityAuditTest run too: the paint's keys through JSON, where the
// window puts the picture, the effects a photo pours through, the shared
// file's thirty-six frames, the average colour, the deck's blipFill, the
// SVG's clipPath and Check accessibility's note.

import XCTest
import UIKit
@testable import Canvia

@MainActor
final class PhotoInLettersTests: XCTestCase {

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "letters", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    /// Shared: the photo paint on a text's letters is the shape fill's keys
    /// — "kind" image, "src", and "focusX", "focusY", "zoom" each written
    /// only away from its default — and round-trips through the JSON the
    /// phones exchange unchanged.
    func testAPhotoPouredIntoLettersKeepsTheShapeFillsKeysThroughJSON() throws {
        let paint = Paint.photo("media:sea", focusX: 0.25, focusY: 0.5, zoom: 1.5)
        XCTAssertEqual(paint.kind, "image")
        XCTAssertEqual(paint.src, "media:sea")
        XCTAssertTrue(paint.isPhoto)
        XCTAssertEqual(paint.focus.x, 0.25)
        XCTAssertEqual(paint.focus.y, 0.5)
        XCTAssertEqual(paint.zoomFactor, 1.5)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(String(decoding: try encoder.encode(paint), as: UTF8.self),
                       ##"{"focusX":0.25,"kind":"image","src":"media:sea","zoom":1.5}"##)
        // The defaults, and a plain image paint, read the same.
        XCTAssertEqual(Paint.image("media:sea"), Paint.photo("media:sea"))
        XCTAssertEqual(Paint.image("media:sea").focus.x, 0.5)
        XCTAssertEqual(Paint.image("media:sea").zoomFactor, 1)
        XCTAssertFalse(Paint.solid("#ff0000").isPhoto)
        // Held to their ranges.
        XCTAssertEqual(Paint.photo("media:sea", zoom: 9).zoomFactor, 4)
        XCTAssertEqual(Paint.photo("media:sea", zoom: 0.2).zoomFactor, 1)
        XCTAssertEqual(Paint.photo("media:sea", focusX: 3).focus.x, 1)
        var text = Element.text("Sea")
        text.textFill = paint
        let back = try JSONDecoder().decode(Element.self, from: try encoder.encode(text))
        XCTAssertEqual(back.textFill, paint)
        XCTAssertEqual(back, text)
        let read = try JSONDecoder().decode(Paint.self, from: Data(##"{"kind":"image","src":"media:sea","focusY":0.75}"##.utf8))
        XCTAssertEqual(read, Paint.photo("media:sea", focusY: 0.75))
    }

    /// Shared rows: where the picture is drawn through the letters —
    /// covering the box, times the zoom, slid by the focus.
    func testTheWindowCoversTheBoxZoomedAndSlidByTheFocus() {
        func window(_ focusX: Double, _ focusY: Double, _ zoom: Double) -> CGRect {
            PhotoFills.window(imageW: 400, imageH: 200, boxW: 100, boxH: 100,
                              paint: Paint.photo("x", focusX: focusX, focusY: focusY, zoom: zoom))
        }
        // A wide picture in a square box: scaled to the box's height, centred.
        XCTAssertEqual(window(0.5, 0.5, 1), CGRect(x: -50, y: 0, width: 200, height: 100))
        XCTAssertEqual(window(0, 0.5, 1), CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(window(1, 0.5, 1), CGRect(x: -100, y: 0, width: 200, height: 100))
        XCTAssertEqual(window(0.5, 0.5, 2), CGRect(x: -150, y: -50, width: 400, height: 200))
        XCTAssertEqual(window(1, 1, 2), CGRect(x: -300, y: -100, width: 400, height: 200))
        // A tall picture in a wide box: scaled to the box's width.
        XCTAssertEqual(PhotoFills.window(imageW: 100, imageH: 200, boxW: 200, boxH: 100, paint: Paint.photo("x")),
                       CGRect(x: 0, y: -150, width: 200, height: 400))
        // Nothing to draw by is the box itself.
        XCTAssertEqual(PhotoFills.window(imageW: 0, imageH: 0, boxW: 100, boxH: 50, paint: Paint.photo("x")),
                       CGRect(x: 0, y: 0, width: 100, height: 50))
        // Adjust photo: a drag moves the focus against the slack, a pinch the zoom.
        let moved = PhotoFills.moved(Paint.photo("x"), imageW: 400, imageH: 200, boxW: 100, boxH: 100, dx: -25, dy: 10)
        XCTAssertEqual(moved.focus.x, 0.75, accuracy: 1e-9)
        XCTAssertEqual(moved.focus.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(PhotoFills.moved(moved, imageW: 400, imageH: 200, boxW: 100, boxH: 100, dx: -200, dy: 0).focus.x, 1, accuracy: 1e-9)
        XCTAssertEqual(PhotoFills.zoomed(Paint.photo("x"), by: 2).zoomFactor, 2, accuracy: 1e-9)
        XCTAssertEqual(PhotoFills.zoomed(Paint.photo("x"), by: 0.5).zoomFactor, 1, accuracy: 1e-9)
        XCTAssertEqual(PhotoFills.zoomed(Paint.photo("x", zoom: 3), by: 2).zoomFactor, 4, accuracy: 1e-9)
    }

    /// Shared rows: the effects a photo pours through — the same ones a
    /// gradient does.
    func testAPhotoPoursThroughTheEffectsAGradientDoes() {
        let rows: [TextEffect: Bool] = [
            .none: true, .shadow: true, .lift: true, .outline: false, .outlined: true,
            .splice: false, .echo: false, .glitch: false, .neon: true, .highlight: true,
        ]
        XCTAssertEqual(Set(rows.keys), Set(TextEffect.allCases))
        for (effect, takes) in rows {
            XCTAssertEqual(effect.takesPhoto, takes, effect.rawValue)
            XCTAssertEqual(effect.takesGradient, effect.takesPhoto, effect.rawValue)
        }
        // Colours on words are left out under a photo, as under a gradient.
        var el = Element.text("Big sale")
        el.setSpans([TextSpan(start: 0, end: 3, color: "#ff0000")])
        el.textFill = Paint.photo("media:sea")
        XCTAssertTrue(FontLibrary.paintsLetters(el))
        XCTAssertEqual(FontLibrary.displayColours(for: el), [])
    }

    /// Shared: thirty-six letter and number frames from the shared file,
    /// each a path in its own 0…100 box — A to Z then 0 to 9 — whose
    /// outline reaches every edge of the box, and with the glyph's own
    /// proportions.
    func testTheLetterAndNumberFramesAreTheSharedFilesThirtySix() throws {
        let frames = GlyphFrames.all
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }
        XCTAssertEqual(frames.map(\.glyph), letters + (0...9).map { String($0) })
        XCTAssertEqual(frames[0].shape.id, "glyph-A")
        XCTAssertEqual(frames[0].shape.englishName, "A")
        XCTAssertEqual(frames[0].shape.category, "Frames")
        // The taller side is 100; I is the narrowest.
        XCTAssertTrue(frames.allSatisfy { $0.height == 100 && $0.width >= 10 && $0.width <= 100 })
        XCTAssertEqual(GlyphFrames.of("I")?.width, 15.71)
        XCTAssertEqual(GlyphFrames.of("A")?.width, 53.86)
        for frame in frames {
            let path = frame.shape.path
            // Absolute M, L, C and Z only, so the numbers pair off as points.
            XCTAssertTrue(path.allSatisfy { "MLCZ0123456789. -".contains($0) }, frame.glyph)
            let numbers = path.split(whereSeparator: { "MLCZ ".contains($0) }).compactMap { Double($0) }
            let xs = numbers.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            let ys = numbers.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            XCTAssertEqual(xs.min() ?? -1, 0, accuracy: 0.02, frame.glyph)
            XCTAssertEqual(xs.max() ?? -1, 100, accuracy: 0.02, frame.glyph)
            XCTAssertEqual(ys.min() ?? -1, 0, accuracy: 0.02, frame.glyph)
            XCTAssertEqual(ys.max() ?? -1, 100, accuracy: 0.02, frame.glyph)
        }
        // A frame on the page is an empty photo clipped to the glyph, its
        // taller side half the page's shorter side, centred.
        let a = GlyphFrames.element(try XCTUnwrap(GlyphFrames.of("A")), page: CGSize(width: 1000, height: 800))
        XCTAssertTrue(PhotoFrames.isEmpty(a))
        XCTAssertEqual(a.maskShapeId, "glyph-A")
        XCTAssertEqual(ContentLibrary.frameShape(a.maskShapeId)?.id, "glyph-A")
        XCTAssertNil(ContentLibrary.frameShape("glyph-é"))
        XCTAssertEqual(a.h, 400, accuracy: 1e-9)
        XCTAssertEqual(a.w, 215.44, accuracy: 1e-9)
        XCTAssertEqual(a.x, 392.28, accuracy: 1e-9)
        XCTAssertEqual(a.y, 200, accuracy: 1e-9)
        XCTAssertTrue(PhotoFrames.isFrameLike(a, among: [a]))
        XCTAssertEqual(GlyphFrames.label(frames[0]), "A letter frame")
        // A photo dropped in goes into the letter, as into any frame.
        var photo = Element.image("media:x", w: 100, h: 100)
        photo.id = "p"
        let out = try XCTUnwrap(PhotoFrames.dropped([a, photo], dragged: "p", onto: a.id, home: .zero))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.src, "media:x")
        XCTAssertEqual(out.first?.maskShapeId, "glyph-A")
        // Added from the sheet, it lands on the page selected, as one step.
        let s = store([])
        XCTAssertTrue(s.add(a, centered: false))
        XCTAssertEqual(s.page.elements.map(\.maskShapeId), ["glyph-A"])
    }

    /// Shared: the average is one colour, clear pixels left out, grey for
    /// none.
    func testTheAverageIsOneColourClearPixelsLeftOutGreyForNone() {
        let pixels: [UInt8] = [255, 0, 0, 255, 0, 0, 255, 255, 100, 100, 100, 0]
        XCTAssertEqual(PhotoPalette.average(pixels), "#800080")
        XCTAssertEqual(PhotoPalette.average([0x10, 0x20, 0x30, 255]), "#102030")
        XCTAssertEqual(PhotoPalette.average([]), "#808080")
        XCTAssertNil(PhotoPalette.averageColour("media:nowhere"))
    }

    /// Shared: letters full of a photo say their contrast cannot be
    /// measured, with nothing to fix.
    func testPhotoFilledLettersSayTheirContrastCannotBeMeasured() {
        var poured = Element.text("Sea", fontSize: 40)
        poured.id = "t"
        poured.textFill = Paint.photo("media:sea")
        var design = Design(title: "Check", width: 1080, height: 1080)
        design.pages = [Page(background: .color("#ffffff"), elements: [poured])]
        let found = AccessibilityAudit.findings(design)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.kind, .contrast)
        XCTAssertEqual(found.first?.elementId, "t")
        XCTAssertEqual(found.first?.message, "Contrast can't be measured for photo-filled text")
        XCTAssertNil(found.first?.fix)
        XCTAssertNil(found.first?.contrast)
    }

    func testPouringAPhotoIsOneStepAndRemoveGivesTheColourBack() {
        let text = Element.text("Sea")
        let s = store([text])
        s.select(text.id)
        s.pourPhoto("media:sea")
        XCTAssertEqual(s.element(text.id)?.textFill, Paint.photo("media:sea"))
        s.removePhotoFromLetters()
        XCTAssertNil(s.element(text.id)?.textFill)
        s.undo()
        XCTAssertEqual(s.element(text.id)?.textFill, Paint.photo("media:sea"))
        s.undo()
        XCTAssertNil(s.element(text.id)?.textFill)
        // The colour sheet's Photo fill row pours into text as into a shape.
        s.recolourSelection(gradient: Paint.photo("media:sea"))
        XCTAssertEqual(s.element(text.id)?.textFill, Paint.photo("media:sea"))
        // A photo dropped over the selected box is offered to its letters,
        // or kept on the page where it was let go.
        XCTAssertNotNil(s.letterFillTarget(at: CGPoint(x: text.x + 1, y: text.y + 1)))
        XCTAssertNil(s.letterFillTarget(at: CGPoint(x: text.x - 50, y: text.y - 50)))
        s.letterFillOffer = LetterFillOffer(id: text.id, src: "media:drop", frame: CGRect(x: 10, y: 20, width: 100, height: 80))
        s.acceptLetterFill()
        XCTAssertEqual(s.element(text.id)?.textFill, Paint.photo("media:drop"))
        XCTAssertNil(s.letterFillOffer)
        s.letterFillOffer = LetterFillOffer(id: text.id, src: "media:kept", frame: CGRect(x: 10, y: 20, width: 100, height: 80))
        s.declineLetterFill()
        XCTAssertEqual(s.page.elements.last?.src, "media:kept")
        XCTAssertEqual(s.page.elements.last?.x, 10)
        // Adjust photo needs a picture this phone can open.
        XCTAssertFalse(s.startPhotoAdjust(text.id))
        XCTAssertNil(s.photoAdjustTarget)
    }

    /// Shared: letters full of a photo are a blipFill of the photo's media,
    /// cropped by srcRect to the window the focus and zoom give, where the
    /// effect holds a photo; else the letters in its average colour.
    func testLettersFullOfAPhotoAreABlipFillCroppedToTheWindow() {
        // Stands in for the phone: every photo 400 by 200, averaging to a blue.
        let photos = PptxExporter.PhotoLookup(size: { _ in CGSize(width: 400, height: 200) },
                                              average: { _ in "#336699" }, type: { _ in "jpeg" })
        var poured = Element.text("Sea")
        poured.id = "t"
        poured.w = 100; poured.h = 100
        poured.textFill = Paint.photo("media:sea", focusX: 0.25, zoom: 2)
        func slide(_ el: Element) -> PptxExporter.SlideParts {
            var d = Design(title: "Deck", width: 800, height: 600)
            d.pages = [Page(id: "p", elements: [el])]
            return PptxExporter.slide(design: d, page: d.pages[0], number: 1, previous: nil, firstImage: 1, photos: photos)
        }
        let parts = slide(poured)
        // 400 by 200 in a square box at zoom 2: the window is 400 by 200
        // over the 100 box, slid a quarter — 18.75% off the left, 56.25%
        // off the right, a quarter off the top and the bottom.
        XCTAssertTrue(parts.xml.contains("<a:rPr sz=\"3150\"><a:blipFill><a:blip r:embed=\"rId2\"/>"
                                         + "<a:srcRect l=\"18750\" t=\"25000\" r=\"56250\" b=\"25000\"/><a:stretch><a:fillRect/></a:stretch></a:blipFill>"
                                         + "<a:latin typeface=\"Modern Sans\"/></a:rPr>"), parts.xml)
        XCTAssertEqual(parts.media.map(\.name), ["image1.jpeg"])
        XCTAssertEqual(parts.media.first?.source, .photo("media:sea"))
        XCTAssertTrue(parts.rels.contains("Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image1.jpeg\""), parts.rels)
        // Just covering, centred: no crop across, none down.
        var centred = poured
        centred.textFill = Paint.photo("media:sea")
        XCTAssertTrue(slide(centred).xml.contains("<a:blipFill><a:blip r:embed=\"rId2\"/><a:srcRect l=\"25000\" r=\"25000\"/><a:stretch>"))
        // Hollow letters hold no photo: the ink is the photo's average.
        var hollow = poured
        hollow.effect = TextEffectSpec(type: "outline")
        let hollowed = slide(hollow)
        XCTAssertTrue(hollowed.xml.contains("<a:ln w=\"23813\"><a:solidFill><a:srgbClr val=\"336699\"/></a:solidFill></a:ln><a:noFill/>"), hollowed.xml)
        XCTAssertFalse(hollowed.xml.contains("blipFill"))
        XCTAssertEqual(hollowed.media, [])
        XCTAssertEqual(PptxExporter.blipFill("rId9", size: CGSize(width: 400, height: 200), paint: Paint.photo("x", focusX: 0), w: 100, h: 100),
                       "<a:blipFill><a:blip r:embed=\"rId9\"/><a:srcRect r=\"50000\"/><a:stretch><a:fillRect/></a:stretch></a:blipFill>")
    }

    /// Shared: letters full of a photo are a clipPath of their outlines with
    /// the picture inside it, where the window puts it; an effect that
    /// cannot hold the photo writes the letters in its average colour.
    func testLettersFullOfAPhotoClipThePictureToTheirOutlines() throws {
        let src = "asset:\(try XCTUnwrap(PhotoLibrary.photos.first).id)"
        let stored = try XCTUnwrap(PhotoFills.stored(src))
        XCTAssertEqual(stored.type, "jpeg")
        XCTAssertTrue(stored.size.width > 0)
        var poured = Element.text("Sea", fontSize: 40, w: 100)
        poured.x = 10; poured.y = 20; poured.h = 100
        poured.textFill = Paint.photo(src, focusX: 0)
        var design = Design(title: "SVG", width: 400, height: 300)
        design.pages = [Page(background: .color("#ffffff"), elements: [poured])]
        let out = SVGExporter.svg(design: design, page: design.pages[0])
        XCTAssertTrue(out.contains("<g transform=\"translate(10 20)\"><clipPath id=\"textclip0\"><path d=\""), out.prefix(2000).description)
        XCTAssertTrue(out.contains("<image clip-path=\"url(#textclip0)\" x=\"0\" y=\""))
        XCTAssertTrue(out.contains("preserveAspectRatio=\"none\" xlink:href=\"data:image/jpeg;base64,"))
        // Hollow letters cannot hold the picture: drawn in its average.
        var hollow = poured
        hollow.effect = TextEffectSpec(type: "outline")
        design.pages[0].elements = [hollow]
        let hollowed = SVGExporter.svg(design: design, page: design.pages[0])
        XCTAssertFalse(hollowed.contains("clipPath"))
        XCTAssertTrue(hollowed.contains("fill=\"\(try XCTUnwrap(PhotoPalette.averageColour(src)))\""), hollowed.prefix(2000).description)
    }
}
