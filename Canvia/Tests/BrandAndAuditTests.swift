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

    // MARK: contrast

    func testTheRatioIsWCAG() {
        XCTAssertEqual(ContrastAudit.ratio("#000000", "#ffffff"), 21, accuracy: 0.01)
        XCTAssertEqual(ContrastAudit.ratio("#ffffff", "#000000"), 21, accuracy: 0.01)
        XCTAssertEqual(ContrastAudit.ratio("#777777", "#ffffff"), 4.48, accuracy: 0.02)
        XCTAssertEqual(ContrastAudit.ratio("#ff0000", "#ff0000"), 1, accuracy: 0.001)
    }

    func testLargeTextNeedsLessAndTheBackdropIsWhatIsBehind() {
        var d = Design(title: "c", width: 800, height: 600)
        var panel = Element.shape("rect", w: 800, h: 300); panel.fill = .solid("#222222")
        var onPanel = Element.text("Grey on dark", fontSize: 16, w: 300); onPanel.color = "#777777"; onPanel.y = 100
        var onPage = Element.text("Grey on white", fontSize: 16, w: 300); onPage.color = "#777777"; onPage.y = 450
        var big = Element.text("Big grey", fontSize: 40, w: 300); big.color = "#777777"; big.y = 500
        d.pages[0] = Page(background: .color("#ffffff"), elements: [panel, onPanel, onPage, big])

        XCTAssertEqual(ContrastAudit.backdrop(for: onPanel, in: d.pages[0]), "#222222")
        XCTAssertEqual(ContrastAudit.backdrop(for: onPage, in: d.pages[0]), "#ffffff")
        let findings = ContrastAudit.audit(d)
        XCTAssertEqual(findings.map(\.elementId), [onPage.id], "#777 on white is 4.48:1, just under; on #222 it passes; at 40px 4.48 passes 3:1")
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
