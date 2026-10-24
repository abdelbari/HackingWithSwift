// Round 32's cropped graphics, with the rows the Android twin's tests hold
// too: the `clip` {x, y, w, h} through the file — a photo's `clip` still its
// playback — the part shown, alone and in a group, where a touch takes it,
// what the renderer draws and the exports write, and crop mode's step.

import XCTest
import SwiftUI
@testable import Canvia

final class GraphicClipTests: XCTestCase {

    private func sticker(_ clip: ClipBox?) -> Element {
        var el = Element.sticker("⭐", size: 100)
        el.id = "s"
        el.w = 200
        el.clipBox = clip
        return el
    }

    // MARK: the file

    func testTheClipRoundTripsThroughTheFile() throws {
        var shape = Element.shape("rect", w: 200, h: 100)
        shape.clipBox = ClipBox(x: 0.25, y: 0, w: 0.5, h: 1)
        let data = try JSONEncoder().encode(shape)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let clip = try XCTUnwrap(json["clip"] as? [String: Double])
        XCTAssertEqual(clip, ["x": 0.25, "y": 0, "w": 0.5, "h": 1])
        let back = try JSONDecoder().decode(Element.self, from: data)
        XCTAssertEqual(back.clipBox, ClipBox(x: 0.25, y: 0, w: 0.5, h: 1))
        XCTAssertNil(back.clip, "a shape has no playback")

        // A photo's `clip` is still its playback.
        var photo = Element.image("video:abc", w: 200, h: 100)
        photo.clip = ClipPlayback(start: 2)
        let read = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(photo))
        XCTAssertEqual(read.clip, ClipPlayback(start: 2))
        XCTAssertNil(read.clipBox)
    }

    func testAClipIsReadAsKept() throws {
        func read(_ clip: String) throws -> Element {
            try JSONDecoder().decode(Element.self, from: Data("{\"type\":\"sticker\",\"glyph\":\"⭐\",\"clip\":\(clip)}".utf8))
        }
        XCTAssertNil(try read("{\"x\":0,\"y\":0,\"w\":1,\"h\":1}").clipBox, "the whole: no clip")
        XCTAssertEqual(try read("{\"x\":-0.5,\"y\":0.5,\"w\":2,\"h\":0.25}").clipBox, ClipBox(x: 0, y: 0.5, w: 1, h: 0.25))
        XCTAssertEqual(try read("{\"x\":0.5,\"y\":0,\"w\":0,\"h\":1}").clipBox?.w, 0.05)
        // Without all four keys as numbers, no crop — Android's rows.
        XCTAssertNil(try read("{\"x\":0.2,\"y\":0,\"w\":0.6}").clipBox)
        XCTAssertNil(try read("{\"x\":\"0.2\",\"y\":0,\"w\":0.6,\"h\":1}").clipBox)
        XCTAssertNil(try read("{\"start\":2}").clipBox, "a playback on a sticker is no crop")
        XCTAssertEqual(ClipBox.kept(ClipBox(x: 0.2, y: 0.2, w: 0.5, h: 0.5)), ClipBox(x: 0.2, y: 0.2, w: 0.5, h: 0.5))
        XCTAssertNil(ClipBox.kept(.whole))
    }

    // MARK: what shows

    func testThePartShownAndWhereATouchTakesIt() {
        let cropped = sticker(ClipBox(x: 0.25, y: 0, w: 0.5, h: 1))
        XCTAssertEqual(GraphicClip.ownRect(cropped), CGRect(x: 50, y: 0, width: 100, height: 100))
        XCTAssertEqual(GraphicClip.visibleFrame(cropped), CGRect(x: 50, y: 0, width: 100, height: 100))
        XCTAssertTrue(Geometry.hits(cropped, point: CGPoint(x: 100, y: 50)))
        XCTAssertFalse(Geometry.hits(cropped, point: CGPoint(x: 20, y: 50)), "cropped away")

        // Flipped, the crop is drawn mirrored in its box.
        var flipped = sticker(ClipBox(x: 0, y: 0, w: 0.25, h: 1))
        flipped.flipH = true
        XCTAssertEqual(GraphicClip.visibleFrame(flipped), CGRect(x: 150, y: 0, width: 50, height: 100))
        XCTAssertNil(GraphicClip.ownRect(sticker(nil)))
        XCTAssertEqual(GraphicClip.visibleFrame(sticker(nil)), CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    /// A group's crop, in its frame, put into each member's own box.
    func testAGroupsCropIsInItsFrame() {
        var a = Element.shape("rect", w: 100, h: 100)
        a.id = "a"
        a.group = "g"
        var b = a
        b.id = "b"
        b.x = 100
        let crop = ClipBox(x: 0, y: 0, w: 0.75, h: 1)
        a.clipBox = crop
        b.clipBox = crop
        XCTAssertNil(GraphicClip.ownRect(a), "not yet in its own box")
        let shown = GraphicClip.shown([a, b])
        XCTAssertEqual(shown[0].clipBox, ClipBox(x: 0, y: 0, w: 1, h: 1))
        XCTAssertEqual(shown[1].clipBox, ClipBox(x: 0, y: 0, w: 0.5, h: 1))
        XCTAssertTrue(shown.allSatisfy(\.clipIsOwn))
        XCTAssertEqual(GraphicClip.ownRect(shown[1]), CGRect(x: 0, y: 0, width: 50, height: 100))
        XCTAssertTrue(GraphicClip.croppableGroup([a, b]))
        XCTAssertFalse(GraphicClip.croppableGroup([a, Element.image("asset:p")]), "a photo's clip is its playback")
        // What the design holds keeps the group's crop; only drawing turns it.
        var d = Design(title: "g", width: 400, height: 400)
        d.pages = [Page(id: "p1", elements: [a, b])]
        XCTAssertEqual(d.drawnElements(on: d.pages[0]).map(\.clipBox), shown.map(\.clipBox))
        XCTAssertEqual(d.pages[0].elements[1].clipBox, crop)
    }

    /// Android's ClipsTest rows: a member leaving its cropped group keeps
    /// what shows where it was.
    func testACroppedGroupsMembersKeepWhatShowsWhenTheyLeaveIt() {
        var a = Element.shape("rect", w: 100, h: 100)
        a.id = "a"
        a.group = "g"
        var b = a
        b.id = "b"
        b.x = 100
        a.clipBox = ClipBox(x: 0, y: 0, w: 0.75, h: 1)
        b.clipBox = a.clipBox
        // Ungrouped: all of a showed, so no crop; half of b.
        let out = Groups.ungrouped([a, b], ids: ["a", "b"])
        XCTAssertNil(out[0].group)
        XCTAssertNil(out[0].clipBox)
        XCTAssertEqual(out[1].clipBox, ClipBox(x: 0, y: 0, w: 0.5, h: 1))
        XCTAssertEqual(GraphicClip.visibleFrame(out[1]), CGRect(x: 100, y: 0, width: 50, height: 100))
        // A member cropped wholly away has its crop let go.
        var halfA = a, halfB = b
        halfA.clipBox = ClipBox(x: 0, y: 0, w: 0.5, h: 1)
        halfB.clipBox = halfA.clipBox
        XCTAssertNil(Groups.ungrouped([halfA, halfB], ids: ["a", "b"])[1].clipBox)
        // One deleted: what is left keeps what showed.
        XCTAssertEqual(GraphicClip.regrouped(before: [a, b], after: [b])[0].clipBox, ClipBox(x: 0, y: 0, w: 0.5, h: 1))
        // Moved as a group, the same members: the crop moves with it.
        var movedA = a, movedB = b
        movedA.x = 10
        movedB.x = 110
        XCTAssertEqual(GraphicClip.regrouped(before: [a, b], after: [movedA, movedB]), [movedA, movedB])
    }

    /// Android's ClipsTest row: part of a cropped group copied shows what
    /// it showed.
    func testPartOfACroppedGroupCopiedShowsWhatItShowed() {
        let spots: [(String, Double)] = [("a", 0), ("b", 100), ("c", 200)]
        let members: [Element] = spots.map { spot -> Element in
            var el = Element.shape("rect", w: 100, h: 100)
            el.id = spot.0
            el.x = spot.1
            el.y = 0
            el.group = "g"
            el.clipBox = ClipBox(x: 0, y: 0, w: 0.5, h: 1)
            return el
        }
        // The left half of the three shows all of a and half of b: copied
        // without a, b and c's crop is on the frame of the two.
        let copied = GraphicClip.copied(members, Array(members.dropFirst()))
        XCTAssertEqual(copied.map(\.clipBox), [ClipBox(x: 0, y: 0, w: 0.25, h: 1), ClipBox(x: 0, y: 0, w: 0.25, h: 1)])
        // Its copies keep it, a group of their own.
        XCTAssertEqual(Copies.of(copied).map(\.clipBox), copied.map(\.clipBox))
        // The whole group as it is.
        XCTAssertEqual(GraphicClip.copied(members, members), members)
    }

    /// Android's ClipsTest row: part of a cropped group that showed nothing
    /// is left out of a copy.
    func testPartOfACroppedGroupThatShowedNothingIsLeftOutOfACopy() {
        // Cropped to its left third, the three show only a; c alone copies
        // as nothing, as it showed.
        let spots: [(String, Double)] = [("a", 0), ("b", 100), ("c", 200)]
        let members: [Element] = spots.map { spot -> Element in
            var el = Element.shape("rect", w: 100, h: 100)
            el.id = spot.0
            el.x = spot.1
            el.y = 0
            el.group = "g"
            el.clipBox = ClipBox(x: 0, y: 0, w: 1.0 / 3, h: 1)
            return el
        }
        XCTAssertTrue(GraphicClip.copied(members, [members[2]]).isEmpty)
        XCTAssertTrue(GraphicClip.copied(members, Array(members.dropFirst())).isEmpty)
        // Deleted instead, what stays lets its crop go: a shows whole.
        XCTAssertNil(GraphicClip.regrouped(before: members, after: [members[0]])[0].clipBox)
    }

    @MainActor
    func testTheRendererDrawsOnlyTheCrop() throws {
        var square = Element.shape("rect", w: 100, h: 100)
        square.fill = .solid("#ff0000")
        square.clipBox = ClipBox(x: 0, y: 0, w: 0.5, h: 1)
        let renderer = ImageRenderer(content: ElementView(element: square))
        renderer.scale = 1
        renderer.isOpaque = false
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertGreaterThan(try alpha(image, x: 25, y: 50), 200, "inside the crop")
        XCTAssertLessThan(try alpha(image, x: 75, y: 50), 10, "cropped away")
    }

    /// Alpha, 0…255, at (x, y) from the top left.
    private func alpha(_ cg: CGImage, x: Int, y: Int) throws -> Int {
        var bytes: [UInt8] = [0, 0, 0, 0]
        try bytes.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        }
        return Int(bytes[3])
    }

    // MARK: the exports

    @MainActor
    func testTheSVGAndPowerPointCutToTheCrop() {
        var shape = Element.shape("rect", w: 200, h: 100)
        shape.x = 10
        shape.y = 20
        shape.clipBox = ClipBox(x: 0.25, y: 0, w: 0.5, h: 1)
        var d = Design(title: "crop", width: 400, height: 300)
        d.pages = [Page(id: "p1", elements: [shape])]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("<clipPath id=\"crop0\"><rect x=\"60\" y=\"20\" width=\"100\" height=\"100\"/></clipPath>"), svg)
        XCTAssertTrue(svg.contains("<g clip-path=\"url(#crop0)\">"), svg)
        XCTAssertEqual(PptxExporter.form(of: shape), .picture, "a vector cut to its crop goes as its picture")
        shape.clipBox = nil
        XCTAssertEqual(PptxExporter.form(of: shape), .shape("rect"))
    }

    // MARK: crop mode

    @MainActor
    func testCropModeIsOneStepAndResetShowsTheWhole() {
        var star = Element.sticker("⭐", size: 100)
        star.id = "s"
        var d = Design(title: "crop", width: 400, height: 400)
        d.pages = [Page(id: "p1", elements: [star])]
        let s = DesignStore(design: d)
        s.selection = ["s"]
        XCTAssertTrue(s.canCropGraphic)
        XCTAssertTrue(s.startGraphicCrop())
        XCTAssertEqual(s.graphicCropWindow, CGRect(x: 0, y: 0, width: 100, height: 100))
        s.setGraphicCropWindow(CGRect(x: 0, y: 0, width: 50, height: 100))
        s.finishGraphicCrop()
        XCTAssertEqual(s.element("s")?.clipBox, ClipBox(x: 0, y: 0, w: 0.5, h: 1))
        XCTAssertEqual(s.undoLabel, "Crop")

        XCTAssertTrue(s.startGraphicCrop())
        s.resetGraphicCrop()
        s.cancelGraphicCrop()
        XCTAssertEqual(s.element("s")?.clipBox, ClipBox(x: 0, y: 0, w: 0.5, h: 1), "Cancel puts it back")
        XCTAssertTrue(s.startGraphicCrop())
        s.setGraphicCropAspect(.square)
        XCTAssertEqual(s.graphicCropWindow, CGRect(x: 0, y: 25, width: 50, height: 50))
        s.resetGraphicCrop()
        s.finishGraphicCrop()
        XCTAssertNil(s.element("s")?.clipBox, "Reset: the whole again")
    }
}
