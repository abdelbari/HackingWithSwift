// Design packages, the contrast audit, alt text and the brand kit.

import XCTest
import UIKit
@testable import Canvia

final class BrandAndAuditTests: XCTestCase {

    // MARK: package

    func testAPackageCarriesItsPhotosAndImportsUnderFreshIds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]).write(to: dir.appendingPathComponent("img_a.jpg"))

        var d = Design(title: "Trip", width: 400, height: 300)
        d.pages[0].elements = [Element.image("media:img_a"), Element.image("asset:sun"), Element.text("Hi")]
        let data = try DesignPackage.export(d, mediaDirectory: dir)
        XCTAssertEqual(DesignPackage.mediaIDs(in: d), ["img_a"])

        let back = try DesignPackage.import(data, mediaDirectory: dir)
        XCTAssertNotEqual(back.id, d.id)
        XCTAssertEqual(back.title, "Trip")
        XCTAssertEqual(back.pages[0].elements.count, 3)
        let moved = try XCTUnwrap(back.pages[0].elements[0].src)
        XCTAssertTrue(moved.hasPrefix("media:") && moved != "media:img_a", moved)
        let file = dir.appendingPathComponent("\(moved.dropFirst(6)).jpg")
        XCTAssertEqual(try Data(contentsOf: file), Data([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]))
        XCTAssertEqual(back.pages[0].elements[1].src, "asset:sun", "library assets are references, not files")
        XCTAssertThrowsError(try DesignPackage.import(Data("{}".utf8), mediaDirectory: dir))
    }

    /// A design file exactly as the Android twin writes it — the same bytes
    /// its own tests pin (core/src/test/resources/android-package.canvia.json
    /// in canvacloneandroid). If either side changes the format, one of the two
    /// tests fails before a real file does.
    func testADesignFileFromTheAndroidTwinOpens() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let android = ##"{"design":{"createdAt":1727000000000,"guides":[],"height":1350.0,"id":"doc-golden","pages":[{"background":{"type":"gradient","value":{"angle":135.0,"kind":"gradient","stops":[{"color":"#ffe066","offset":0.0},{"color":"#ff6b6b","offset":1.0}]}},"elements":[{"fill":{"color":"#8b5cf6","kind":"solid"},"flipH":false,"flipV":false,"h":300.0,"id":"e-oval","locked":false,"opacity":1.0,"radius":0.0,"rotation":0.0,"shapeId":"circle","type":"shape","w":300.0,"x":100.0,"y":120.0},{"fill":{"color":"#1f2430","kind":"solid"},"flipH":false,"flipV":false,"h":200.0,"id":"e-rect","locked":false,"opacity":1.0,"radius":24.0,"rotation":12.0,"shapeId":"rect","type":"shape","w":500.0,"x":50.0,"y":700.0},{"align":"center","color":"#1f2430","flipH":false,"flipV":false,"fontFamily":"didone","fontSize":96.0,"fontWeight":700,"h":240.0,"id":"e-text","letterSpacing":0.0,"lineHeight":1.25,"locked":false,"opacity":1.0,"rotation":0.0,"text":"Hello from Android","type":"text","w":900.0,"x":90.0,"y":480.0},{"cropScale":1.5,"cropX":0.25,"cropY":0.5,"flipH":true,"flipV":false,"h":360.0,"id":"e-photo","locked":false,"opacity":1.0,"radius":0.0,"rotation":0.0,"src":"media:img-golden","type":"image","w":480.0,"x":300.0,"y":900.0},{"color":"#1f2430","dash":"dashed","flipH":false,"flipV":false,"h":8.0,"id":"e-line","locked":false,"opacity":1.0,"rotation":0.0,"thickness":4.0,"type":"line","w":400.0,"x":340.0,"y":1300.0},{"flipH":false,"flipV":false,"glyph":"⭐","h":120.0,"id":"e-star","locked":false,"opacity":1.0,"rotation":0.0,"type":"sticker","w":120.0,"x":900.0,"y":60.0}],"id":"page-1"},{"background":{"type":"image","value":"media:img-golden"},"elements":[],"id":"page-2"},{"background":{"type":"color","value":"#fafafa"},"elements":[],"height":1920.0,"id":"page-3","width":1080.0}],"title":"Golden","titleAuto":false,"updatedAt":1727000100000,"width":1080.0},"format":"canvia-package","media":{"img-golden":{"data":"/9j/4AAQSkZJRgAB","ext":"jpg"}},"version":1}"##
        let d = try DesignPackage.import(Data(android.utf8), mediaDirectory: dir)
        XCTAssertEqual(d.title, "Golden")
        XCTAssertFalse(d.titleAuto)
        XCTAssertEqual(d.pages.count, 3)

        guard case .gradient(let paint) = d.pages[0].background else { return XCTFail("gradient background") }
        XCTAssertEqual(paint.stops?.map(\.offset), [0, 1])
        XCTAssertEqual(paint.stops?.first?.color, "#ffe066")

        let els = d.pages[0].elements
        XCTAssertEqual(els.map(\.type), [.shape, .shape, .text, .image, .line, .sticker])
        XCTAssertEqual(els[0].shapeId, "circle", "Android's oval arrives as iOS's circle")
        XCTAssertEqual(els[1].shapeId, "rect")
        XCTAssertEqual(els[1].rotation, 12)
        XCTAssertEqual(els[2].fontFamily, "didone")
        XCTAssertEqual(els[2].fontWeight, 700)
        XCTAssertEqual(els[3].cropScale, 1.5)
        XCTAssertEqual(els[3].cropX, 0.25)
        XCTAssertTrue(els[3].flipH)
        XCTAssertEqual(els[4].dash, "dashed")
        XCTAssertEqual(els[5].glyph, "⭐")

        // The photo was stored under a fresh id, and both references moved to it.
        let moved = try XCTUnwrap(els[3].src)
        XCTAssertTrue(moved.hasPrefix("media:") && moved != "media:img-golden", moved)
        guard case .image(let bg) = d.pages[1].background else { return XCTFail("image background") }
        XCTAssertEqual(bg, moved)
        XCTAssertEqual(d.pages[2].height, 1920)
    }

    func testALibraryPhotoTravelsAsAPictureInTheFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // A library photo this app can draw, used twice, and an id it cannot.
        let drawable = try XCTUnwrap(PhotoLibrary.photos.first?.id)
        var d = Design(title: "Library", width: 400, height: 300)
        d.pages[0].background = .image("asset:\(drawable)")
        d.pages[0].elements = [Element.image("asset:\(drawable)"), Element.image("asset:sun")]
        var media: [String: DesignPackage.Media] = [:]
        let packed = DesignPackage.packingLibraryPhotos(d, into: &media)
        XCTAssertEqual(media.count, 1, "one copy however often it is used")
        let src = try XCTUnwrap(packed.pages[0].elements[0].src)
        XCTAssertTrue(src.hasPrefix("media:"))
        guard case .image(let bg) = packed.pages[0].background else { return XCTFail("image background") }
        XCTAssertEqual(bg, src)
        XCTAssertEqual(packed.pages[0].elements[1].src, "asset:sun", "an id the library cannot draw stays a reference")
        XCTAssertEqual(d.pages[0].elements[0].src, "asset:\(drawable)", "the design itself is not changed")
    }

    func testAnImportedMasterPageFollowsItsPageToItsNewId() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var d = Design(title: "Deck", width: 400, height: 300)
        d.pages.append(Page())
        d.masterPageId = d.pages[1].id
        let back = try DesignPackage.import(try DesignPackage.export(d, mediaDirectory: dir), mediaDirectory: dir)
        XCTAssertNotEqual(back.pages[1].id, d.pages[1].id)
        XCTAssertEqual(back.masterPageId, back.pages[1].id)
        XCTAssertNotNil(back.masterPage)
    }

    // MARK: contrast

    func testTheRatioIsWCAG() {
        XCTAssertEqual(ContrastAudit.ratio("#000000", "#ffffff"), 21, accuracy: 0.01)
        XCTAssertEqual(ContrastAudit.ratio("#ffffff", "#000000"), 21, accuracy: 0.01)
        XCTAssertEqual(ContrastAudit.ratio("#777777", "#ffffff"), 4.48, accuracy: 0.02)
        XCTAssertEqual(ContrastAudit.ratio("#ff0000", "#ff0000"), 1, accuracy: 0.001)
    }

    func testLargeTextNeedsLessAndTheBackdropIsWhatIsBehind() {
        var d = Design(title: "c", width: 800, height: 600)
        var panel = Element.shape("rect", w: 800, h: 300); panel.fill = .solid("#000000")
        var onPanel = Element.text("Grey on dark", fontSize: 16, w: 300); onPanel.color = "#777777"; onPanel.y = 100
        var onPage = Element.text("Grey on white", fontSize: 16, w: 300); onPage.color = "#777777"; onPage.y = 450
        var big = Element.text("Big grey", fontSize: 40, w: 300); big.color = "#777777"; big.y = 500
        d.pages[0] = Page(background: .color("#ffffff"), elements: [panel, onPanel, onPage, big])

        XCTAssertEqual(ContrastAudit.backdrop(for: onPanel, in: d.pages[0]), "#000000")
        XCTAssertEqual(ContrastAudit.backdrop(for: onPage, in: d.pages[0]), "#ffffff")
        let findings = ContrastAudit.audit(d)
        XCTAssertEqual(findings.map(\.elementId), [onPage.id],
                       "#777 on white is 4.48:1, just under; on black it is 4.69:1 and passes; at 40px 4.48 passes 3:1")
        XCTAssertEqual(findings[0].required, 4.5)
        XCTAssertGreaterThanOrEqual(ContrastAudit.ratio(findings[0].suggestion, "#ffffff"), 4.5, "the suggestion must pass")
    }

    // MARK: alt text

    @MainActor
    func testAltTextWinsTheVoiceOverLabelAndTheSVGTitle() {
        var el = Element.image("asset:x")
        XCTAssertEqual(CanvasAccessibility.label(for: el), "Photo")
        el.altText = "A red bicycle against a wall"
        XCTAssertEqual(CanvasAccessibility.label(for: el), "A red bicycle against a wall")
        var d = Design(title: "alt", width: 200, height: 200)
        var shape = Element.shape("rect"); shape.altText = "Company & logo"
        d.pages[0].elements = [shape]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("<title>Company &amp; logo</title>"), svg)
    }

    func testTheSentenceReadsNaturally() {
        XCTAssertEqual(AltText.sentence(from: ["dog"]), "Photo of a dog")
        XCTAssertEqual(AltText.sentence(from: ["apple", "table"]), "Photo of an apple and table")
        XCTAssertEqual(AltText.sentence(from: ["dog", "grass", "sky"]), "Photo of a dog, grass and sky")
        XCTAssertNil(AltText.sentence(from: []))
    }

    func testDescribingDoesNotCrashOnAPlainPicture() {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
            UIColor.green.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let described = AltText.describe(image)
        if let described { XCTAssertTrue(described.hasPrefix("Photo of ")) }
    }

    // MARK: brand kit

    func testTheKitPersistsAndDedupsColours() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var kit = BrandKit()
        kit.addColor("#FF0000")
        kit.addColor("#00ff00")
        kit.addColor("#ff0000")
        XCTAssertEqual(kit.colors, ["#ff0000", "#00ff00"], "re-adding moves to the front, once")
        kit.headingFamily = "serif"
        kit.logos = ["asset:sun"]
        kit.save(to: url)
        XCTAssertEqual(BrandKit.load(from: url), kit)
        XCTAssertEqual(kit.pairing?.heading.fontFamily, "serif")
        XCTAssertEqual(kit.pairing?.body.fontFamily, "serif", "one face set: both roles use it")
        XCTAssertNil(BrandKit().pairing)
        XCTAssertTrue(BrandKit.load(from: url.appendingPathExtension("missing")).isEmpty)
    }
}
