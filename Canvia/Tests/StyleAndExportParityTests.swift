// Colour for a multi-selection, line ends, page gradients in any shape,
// export sized page by page, and design files opened from elsewhere — each
// as the Android twin has it.

import XCTest
import UIKit
@testable import Canvia

final class StyleAndExportParityTests: XCTestCase {

    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    // MARK: colour for several things

    /// Each takes the colour its own way; photos and stickers keep theirs.
    func testEveryKindTakesTheColourItsOwnWay() {
        var text = Element.text("Hi")
        text.textFill = Paint(kind: "gradient", color: nil, angle: 90,
                              stops: [GradientStop(offset: 0, color: "#000000"), GradientStop(offset: 1, color: "#ffffff")])
        XCTAssertEqual(DesignStore.recoloured(text, to: "#ff0000").color, "#ff0000")
        XCTAssertNil(DesignStore.recoloured(text, to: "#ff0000").textFill, "a gradient on the letters is cleared")

        XCTAssertEqual(DesignStore.recoloured(Element.line(), to: "#ff0000").color, "#ff0000")
        let shape = DesignStore.recoloured(Element.shape("rect"), to: "#ff0000")
        XCTAssertEqual(shape.fill, .solid("#ff0000"))

        var stroke = Element.shape("rect")
        stroke.pathData = "M0 0 L10 10"
        stroke.fill = .clear
        stroke.stroke = "#000000"
        XCTAssertTrue(Freehand.isStroke(stroke))
        let inked = DesignStore.recoloured(stroke, to: "#ff0000")
        XCTAssertEqual(inked.stroke, "#ff0000", "a drawn stroke changes its ink")
        XCTAssertEqual(inked.fill, .clear)

        let photo = Element.image("media:x")
        XCTAssertEqual(DesignStore.recoloured(photo, to: "#ff0000"), photo)
        var red = Element.shape("rect")
        red.fill = .solid("#FF0000")
        XCTAssertEqual(DesignStore.recoloured(red, to: "#ff0000"), red, "the same colour in capitals is the same colour")
    }

    /// One step for the lot, and none when nothing would change; locked
    /// things stay as they are.
    func testRecolouringASelectionIsOneStepOrNone() {
        let s = DesignStore(design: Design(title: "colours", width: 400, height: 400))
        var locked = Element.shape("rect")
        locked.locked = true
        let text = Element.text("Hi")
        let box = Element.shape("rect")
        s.applyToPage { $0.elements = [locked, text, box] }
        s.selection = [locked.id, text.id, box.id]
        XCTAssertTrue(s.selectionTakesColour)
        XCTAssertTrue(s.selectionTakesGradient)
        s.recolourSelection("#00ff00")
        XCTAssertEqual(s.element(text.id)?.color, "#00ff00")
        XCTAssertEqual(s.element(box.id)?.fill, .solid("#00ff00"))
        XCTAssertEqual(s.element(locked.id)?.fill, locked.fill, "a locked shape was recoloured")
        s.undo()
        XCTAssertEqual(s.element(text.id)?.color, text.color, "more than one step")
        s.redo()
        // The same colour again changes nothing, so records nothing: the
        // step Undo takes back is still the recolour.
        s.recolourSelection("#00ff00")
        s.undo()
        XCTAssertEqual(s.element(box.id)?.fill, box.fill, "an unchanged colour recorded a step")
    }

    // MARK: line ends

    @MainActor
    func testLineEndsReadAsNoneArrowOrDot() {
        XCTAssertEqual(ContextToolbar.lineEnd("arrow"), "arrow")
        XCTAssertEqual(ContextToolbar.lineEnd("dot"), "dot")
        XCTAssertEqual(ContextToolbar.lineEnd("none"), "none")
        XCTAssertEqual(ContextToolbar.lineEnd(nil), "none")
        XCTAssertEqual(ContextToolbar.lineEnd("feather"), "none", "an end this app does not know reads as none")
        XCTAssertEqual(ContextToolbar.lineEnds.map(\.key), ["none", "arrow", "dot"])
    }

    // MARK: background gradients

    func testAGradientComesInThreeShapes() throws {
        let preset = try XCTUnwrap(ContentLibrary.gradients.first)
        XCTAssertNil(preset.paint(kind: "linear").gradientKind, "linear is written as no shape")
        XCTAssertEqual(preset.paint(kind: "radial").gradientKind, "radial")
        XCTAssertEqual(GradientPreset.kind(of: preset.paint(kind: "angular")), "angular")
        XCTAssertEqual(GradientPreset.kind(of: nil), "linear")
        var odd = preset.paint
        odd.gradientKind = "diamond"
        XCTAssertEqual(GradientPreset.kind(of: odd), "linear")

        XCTAssertTrue(GradientPreset.same(preset.paint(kind: "radial"), preset.paint(kind: "radial")))
        XCTAssertFalse(GradientPreset.same(preset.paint(kind: "radial"), preset.paint(kind: "angular")))
        var shouted = preset.paint
        shouted.stops = shouted.stops?.map { GradientStop(offset: $0.offset, color: $0.color.uppercased()) }
        XCTAssertTrue(GradientPreset.same(shouted, preset.paint), "colours compared ignoring case")
        XCTAssertFalse(GradientPreset.same(nil, preset.paint))
    }

    /// SVG has no conic gradient: an angular background ships as pixels
    /// rather than quietly turning linear.
    @MainActor
    func testAnAngularBackgroundExportsToSVGAsPixels() throws {
        let preset = try XCTUnwrap(ContentLibrary.gradients.first)
        var design = Design(title: "bg", width: 120, height: 80)
        design.pages[0].background = .gradient(preset.paint(kind: "angular"))
        let angular = SVGExporter.svg(design: design, page: design.pages[0])
        XCTAssertFalse(angular.contains("url(#bg)"))
        XCTAssertTrue(angular.contains("data:image/jpeg;base64,"))
        design.pages[0].background = .gradient(preset.paint(kind: "radial"))
        XCTAssertTrue(SVGExporter.svg(design: design, page: design.pages[0]).contains("url(#bg)"))
    }

    // MARK: export sizing

    /// Each page is budgeted and sized at its own size, not the design's.
    func testEveryPageIsSizedAtItsOwnSize() {
        let big = CGSize(width: 4000, height: 4000)
        XCTAssertEqual(DesignExporter.effectiveScale(size: big, requested: 3), (32_000_000.0 / 16_000_000).squareRoot(),
                       accuracy: 1e-9, "a big page is held to the budget whatever the design's size")
        XCTAssertTrue(DesignExporter.isClamped(size: big, requested: 3))
        XCTAssertEqual(DesignExporter.scale(forLongEdge: 1080, size: CGSize(width: 540, height: 960)), 1.125, accuracy: 1e-9)
        XCTAssertEqual(DesignExporter.outputSize(size: CGSize(width: 540, height: 960), requested: 1.125),
                       CGSize(width: 608, height: 1080))
        XCTAssertEqual(DesignExporter.longEdge(size: CGSize(width: 100, height: 50), requested: 2), 200)
    }

    /// With a long edge, every page of a mixed deck comes out that long on
    /// its own longer side.
    @MainActor
    func testALongEdgeAppliesToEveryPageAtItsOwnSize() async throws {
        var design = Design(title: "mixed", width: 100, height: 50)
        var tall = Page()
        tall.width = 40; tall.height = 80
        design.pages = [Page(), tall]
        let urls = try await DesignExporter.exportPages(design: design, range: .all, current: 0,
                                                  format: .png, scale: 1, longEdge: 200)
        written = urls
        let sizes = try urls.map { url -> CGSize in
            let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
            return CGSize(width: image.width, height: image.height)
        }
        XCTAssertEqual(sizes, [CGSize(width: 200, height: 100), CGSize(width: 100, height: 200)])
    }

    // MARK: design files from elsewhere

    /// A design file handed over opens as a new design, with a title the
    /// shelf does not already have; anything else says what it is not.
    func testADesignFileOpensUnderATitleNotOnTheShelf() throws {
        let data = try DesignPackage.export(Design(title: "Poster", width: 100, height: 100))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("design-\(UUID()).canvia.json")
        try data.write(to: url)
        written.append(url)
        let opened = try DesignPackage.importFile(at: url, taken: ["poster", "Flyer"])
        XCTAssertEqual(opened.title, "Poster 2")

        let text = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID()).json")
        try Data(#"{"hello":"world"}"#.utf8).write(to: text)
        written.append(text)
        XCTAssertThrowsError(try DesignPackage.importFile(at: text, taken: [])) { error in
            XCTAssertEqual(error.localizedDescription, "This file is not a Canvia design.")
        }
    }

    /// Only the system's hand-over copy is deleted after reading, never a
    /// file somewhere else.
    func testOnlyTheInboxCopyIsDiscarded() throws {
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("keep-\(UUID()).json")
        try Data("{}".utf8).write(to: elsewhere)
        written.append(elsewhere)
        DesignPackage.discardInboxCopy(elsewhere)
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.path))

        let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let handed = inbox.appendingPathComponent("handed-\(UUID()).json")
        try Data("{}".utf8).write(to: handed)
        written.append(handed)
        DesignPackage.discardInboxCopy(handed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: handed.path))
    }
}
