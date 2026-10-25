// Adjustments on part of a photo: a retouch layer of kind "adjust" — its
// dials (no selective colour), strokes and area — read and written as both
// phones do, the cover and mixing maths (Fixtures/area-adjust.json, byte
// for byte the Android twin's), and Filters ▸ Adjust's Apply to row in the store.

import XCTest
@testable import Canvia

final class AreaAdjustTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("area-adjust") }

    /// Shared: how much a layer shows for its area.
    func testTheCoverForEachArea() throws {
        let cover = try XCTUnwrap(try fixture()["cover"] as? [String: Any])
        for row in try XCTUnwrap(cover["rows"] as? [[Any]]) {
            let area = row[0] as? String
            let strokes = try XCTUnwrap(row[1] as? Double), subject = try XCTUnwrap(row[2] as? Double)
            XCTAssertEqual(RetouchLayer.cover(area: area, strokes: strokes, subject: subject),
                           try XCTUnwrap(row[3] as? Double), accuracy: 1e-9, "\(area ?? "none")")
        }
    }

    /// Shared: a channel of the adjusted copy mixed into the picture's.
    func testTheMixingMaths() throws {
        let mix = try XCTUnwrap(try fixture()["mix"] as? [String: Any])
        for row in try XCTUnwrap(mix["rows"] as? [[Any]]) {
            let base = UInt8(try XCTUnwrap(row[0] as? Int)), adjusted = UInt8(try XCTUnwrap(row[1] as? Int))
            let cover = try XCTUnwrap(row[2] as? Double)
            XCTAssertEqual(Int(RetouchLayer.mixed(base, adjusted, cover: cover)), row[3] as? Int, "\(row)")
        }
    }

    /// Shared: an adjust layer written and read back, and read leniently.
    func testAnAdjustLayerIsWrittenAndReadAsBothPhonesDo() throws {
        let written = try XCTUnwrap((try fixture()["layer"] as? [String: Any])?["written"] as? String)
        var dials = Adjustments()
        dials.brightness = 0.3
        dials.warmth = -0.2
        dials.hsl = ["red": HueShift(h: 0.5, s: 0, l: 0)]
        dials.vignette = 0.6
        let layer = RetouchLayer(adjustOver: RetouchLayer.subjectArea, adjust: dials)
        XCTAssertTrue(layer.adjust?.hsl.isEmpty == true, "an adjust layer keeps no selective colour")
        XCTAssertEqual(layer.adjust?.vignette, 0, "nor a vignette, which is never drawn on part of a photo")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(layer), as: UTF8.self), written)
        XCTAssertEqual(try JSONDecoder().decode(RetouchLayer.self, from: Data(written.utf8)), layer)

        let read = try JSONDecoder().decode([Lossy<RetouchLayer>].self, from: Data(##"""
        [{"kind": "adjust", "adjust": {"contrast": 0.5}, "strokes": [], "area": "brush"},
         {"kind": "adjust", "adjust": {"contrast": 0.5}, "strokes": [{"w": 0.1, "pts": [[0.5, 0.5]]}], "area": "sky"},
         {"kind": "adjust", "area": "background"},
         {"kind": "recolour", "strokes": [{"w": 0.1, "pts": [[0.5, 0.5]]}]},
         {"kind": "blur", "amount": 0.4, "strokes": [{"w": 0.1, "pts": [[0.5, 0.5]]}]}]
        """##.utf8)).compactMap(\.value)
        XCTAssertEqual(read.map(\.kind), ["adjust", "adjust", "blur"],
                       "a painted area with no stroke and an unknown kind are left out")
        XCTAssertEqual(read[0].area, "brush", "an unknown area is a painted one")
        XCTAssertEqual(read[0].adjust?.contrast, 0.5)
        XCTAssertEqual(read[1].area, "background")
        XCTAssertEqual(read[1].adjust, .neutral)
        XCTAssertFalse(read[1].paintsArea)
        XCTAssertNil(read[2].adjust)
        // Kept on an element with no strokes, as the subject's or background's.
        XCTAssertEqual(RetouchLayer.kept([RetouchLayer(adjustOver: "subject")])?.count, 1)
        XCTAssertNil(RetouchLayer.kept([RetouchLayer(adjustOver: "brush")]))
        // A blur is written as it was, with no adjust keys.
        let blur = String(decoding: try encoder.encode(read[2]), as: UTF8.self)
        XCTAssertFalse(blur.contains("adjust") || blur.contains("area"), blur)
    }

    // MARK: the Apply to row

    private var libraryPhoto: Element {
        var el = Element.image("asset:" + (PhotoLibrary.photos.first?.id ?? "none"), w: 300, h: 300)
        el.x = 50; el.y = 50
        return el
    }

    @MainActor
    private func store(with photo: Element) -> DesignStore {
        var design = Design(title: "areas", width: 600, height: 600)
        design.pages[0].elements = [photo]
        return DesignStore(design: design)
    }

    @MainActor
    func testTheDialsGoToTheChosenAreaAndBack() throws {
        let photo = libraryPhoto
        let s = store(with: photo)
        s.select(photo.id)
        XCTAssertEqual(s.adjustAreaShown, .whole)
        XCTAssertFalse(s.applyAdjust(to: .subject))
        XCTAssertEqual(s.adjustAreaShown, .subject)
        s.setDial(\.brightness, to: 0.4, live: false)
        let layer = try XCTUnwrap(s.element(photo.id)?.retouch?.first)
        XCTAssertEqual(layer.kind, "adjust")
        XCTAssertEqual(layer.area, "subject")
        XCTAssertEqual(layer.adjust?.brightness, 0.4)
        XCTAssertNil(s.element(photo.id)?.adjustments, "the whole photo's dials are untouched")
        // The subject's layer is found again rather than made twice.
        s.applyAdjust(to: .whole)
        s.applyAdjust(to: .subject)
        XCTAssertEqual(s.adjustLayers.count, 1)
        // The whole photo again.
        s.applyAdjust(to: .whole)
        s.setDial(\.contrast, to: 0.2, live: false)
        XCTAssertEqual(s.element(photo.id)?.adjustments?.contrast, 0.2)
        XCTAssertEqual(s.dialsShown?.contrast, 0.2)
        // Deleted, the dials go back to the whole photo.
        s.applyAdjust(to: .background)
        XCTAssertEqual(s.adjustLayers.count, 2)
        s.removeAdjustLayer(at: 1)
        XCTAssertNil(s.adjustTarget)
        XCTAssertEqual(s.adjustLayers.map { $0.layer.area }, ["subject"])
        XCTAssertEqual(s.adjustLayerName(0), "Subject")
    }

    @MainActor
    func testAPhotoTakesUpToFourAdjustedAreas() throws {
        var photo = libraryPhoto
        photo.retouch = [RetouchLayer(adjustOver: "subject"), RetouchLayer(adjustOver: "background"),
                         RetouchLayer(adjustOver: "brush", strokes: [RetouchStroke(points: [CGPoint(x: 0.5, y: 0.5)])]),
                         RetouchLayer(adjustOver: "brush", strokes: [RetouchStroke(points: [CGPoint(x: 0.2, y: 0.2)])])]
        let s = store(with: photo)
        s.select(photo.id)
        XCTAssertEqual(s.adjustLayers.count, RetouchLayer.maxAdjust)
        XCTAssertFalse(s.applyAdjust(to: .painted), "a fifth is refused")
        XCTAssertNil(s.brushing)
        XCTAssertEqual(s.adjustLayerName(2), "Painted area 1")
        XCTAssertEqual(s.adjustLayerName(3), "Painted area 2")
    }

    @MainActor
    func testAPaintedAreaIsBrushedThenItsDialsOpen() throws {
        let photo = libraryPhoto
        let s = store(with: photo)
        s.select(photo.id)
        XCTAssertTrue(s.applyAdjust(to: .painted))
        XCTAssertEqual(s.brushing?.kind, .adjust)
        s.brushStroke([CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)])
        s.finishBrush()
        let layer = try XCTUnwrap(s.element(photo.id)?.retouch?.first)
        XCTAssertEqual(layer.area, "brush")
        XCTAssertEqual(layer.strokes.count, 1)
        XCTAssertEqual(s.adjustTarget, 0)
        XCTAssertTrue(s.adjustAreaAsked)
        XCTAssertEqual(s.adjustAreaShown, .painted)
    }
}
