// Photo frames.
//
// The trap this feature is built around: the shape library's paths live in a
// 100x100 box and are scaled non-uniformly onto whatever the element's box
// is. A shape tolerates that — a stretched star is a star. A circle frame on
// a 480x360 photo is an ellipse, which is exactly the portrait-in-a-circle
// case the feature exists for.

import XCTest
import SwiftUI
@testable import Canvia

final class FrameTests: XCTestCase {

    // MARK: the shape

    /// No frame is the rounded rectangle every image had before frames, and
    /// a zero radius is a plain rectangle.
    func testNoFrameIsARoundedRectangle() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        let plain = FrameShape(definition: nil, cornerRadius: 0).path(in: rect)
        XCTAssertEqual(plain.boundingRect, rect)
        let rounded = FrameShape(definition: nil, cornerRadius: 20).path(in: rect)
        XCTAssertEqual(rounded.boundingRect.width, rect.width, accuracy: 0.5)
        XCTAssertFalse(rounded.contains(CGPoint(x: 0.5, y: 0.5)),
                       "a rounded frame still has square corners")
    }

    /// A radius larger than the box would otherwise fold the path inside out.
    func testAnOversizedRadiusIsClamped() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        let path = FrameShape(definition: nil, cornerRadius: 900).path(in: rect)
        XCTAssertEqual(path.boundingRect.width, rect.width, accuracy: 0.5)
        XCTAssertEqual(path.boundingRect.height, rect.height, accuracy: 0.5)
    }

    /// A frame is the same geometry the shape tool draws — the same code, so
    /// the two cannot drift.
    func testAFramedShapeMatchesTheShapeElement() throws {
        let rect = CGRect(x: 0, y: 0, width: 120, height: 120)
        let definition = try XCTUnwrap(ContentLibrary.shapeMap["circle"])
        let frame = FrameShape(definition: definition, cornerRadius: 0).path(in: rect)
        let shape = LibraryShape(definition: definition, cornerRadius: 0).path(in: rect)
        XCTAssertEqual(frame.boundingRect, shape.boundingRect)
        XCTAssertEqual(frame.description, shape.description)
    }

    /// The corners of a circle frame are outside the path and its centre is
    /// inside — which a rectangle would fail and an inverted winding rule
    /// would fail the other way round.
    func testACircleFrameActuallyClipsTheCorners() throws {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let definition = try XCTUnwrap(ContentLibrary.shapeMap["circle"])
        let path = FrameShape(definition: definition, cornerRadius: 0).path(in: rect)
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 50)), "the middle is not inside the circle")
        XCTAssertFalse(path.contains(CGPoint(x: 2, y: 2)), "the corner was not clipped away")
        XCTAssertFalse(path.contains(CGPoint(x: 98, y: 98)))
    }

    // MARK: the model

    func testAnUnknownFrameIdMeansNoFrameRatherThanARectangle() {
        // ContentLibrary.shape(_:) falls back to "rect"; the frame lookup must
        // not, or a document from a build with more shapes silently crops
        // someone's photo to a square.
        XCTAssertNil(ContentLibrary.shapeMap["a-shape-this-build-does-not-have"])
        XCTAssertEqual(ContentLibrary.shape("a-shape-this-build-does-not-have").id, "rect")
    }

    func testTheFrameSurvivesAJSONRoundTrip() throws {
        var el = Element.image("asset:x", w: 200, h: 200)
        el.maskShapeId = "star"
        let restored = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(restored.maskShapeId, "star")
        XCTAssertEqual(restored, el)
    }

    /// An unknown id has to round-trip even though it does not render, or
    /// opening a newer document in an older build quietly destroys it.
    func testAnUnknownFrameIdStillRoundTrips() throws {
        var el = Element.image("asset:x", w: 200, h: 200)
        el.maskShapeId = "from-a-later-build"
        let restored = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(restored.maskShapeId, "from-a-later-build")
    }

    func testADocumentWithoutAFrameDecodesUnframed() throws {
        let json = #"{"id":"el_1","type":"image","src":"asset:x","w":100,"h":100}"#
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(json.utf8)).maskShapeId)
    }

    func testTheStylePainterCarriesTheFrame() {
        var source = Element.image("asset:a", w: 100, h: 100)
        source.maskShapeId = "heart"
        var target = Element.image("asset:b", w: 100, h: 100)
        DesignStore.apply(DesignStore.style(of: source), to: &target)
        XCTAssertEqual(target.maskShapeId, "heart")
        XCTAssertEqual(target.src, "asset:b")
    }

    // MARK: page notes

    /// Notes are about the page, not on it — nothing that renders reads them,
    /// so they cannot appear in an export.
    func testPageNotesRoundTripAndAreNotContent() throws {
        var page = Page(background: .color("#ffffff"), elements: [])
        page.notes = "Mention the Q3 numbers here"
        let restored = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(restored.notes, "Mention the Q3 numbers here")
        XCTAssertTrue(restored.elements.isEmpty)
    }

    func testAPageWithoutNotesDecodesWithNone() throws {
        let json = #"{"id":"page_1","elements":[]}"#
        XCTAssertNil(try JSONDecoder().decode(Page.self, from: Data(json.utf8)).notes)
    }

    /// Notes must not make two otherwise identical pages compare equal, or the
    /// thumbnail cache keyed on Page would show a stale render.
    func testNotesArePartOfPageEquality() {
        var a = Page(background: .color("#ffffff"), elements: [])
        var b = a
        b.notes = "different"
        XCTAssertNotEqual(a, b)
        a.notes = "different"
        XCTAssertEqual(a, b)
    }

    // MARK: jpeg quality

    /// The estimate is a guess, but it has to move the right way: more pixels
    /// or more quality means a bigger file.
    func testTheJPEGEstimateGrowsWithQualityAndSize() {
        let design = Design(width: 1080, height: 1080)
        let low = DesignExporter.estimatedJPEGBytes(design: design, requested: 1, quality: 0.3)
        let high = DesignExporter.estimatedJPEGBytes(design: design, requested: 1, quality: 1)
        XCTAssertGreaterThan(high, low * 2)

        let small = DesignExporter.estimatedJPEGBytes(design: design, requested: 1, quality: 0.9)
        let large = DesignExporter.estimatedJPEGBytes(design: design, requested: 3, quality: 0.9)
        XCTAssertGreaterThan(large, small * 4)
    }

    func testTheJPEGEstimateIsNeverAbsurd() {
        let design = Design(width: 40, height: 40)
        let bytes = DesignExporter.estimatedJPEGBytes(design: design, requested: 1, quality: 0.05)
        XCTAssertGreaterThanOrEqual(bytes, 2_048, "a plausible floor, not zero")
    }
}
