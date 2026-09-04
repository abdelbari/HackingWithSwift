// Master pages, page-number tokens, guides and the eyedropper.

import XCTest
import UIKit
@testable import Canvia

@MainActor
final class MasterAndGuidesTests: XCTestCase {

    private func design() -> Design {
        var d = Design(title: "m", width: 400, height: 300)
        d.pages = [Page(elements: [Element.text("Header")]), Page(elements: [Element.shape("rect")]), Page()]
        return d
    }

    // MARK: master

    func testTheMasterShowsBehindEveryOtherPageThatWantsIt() {
        var d = design()
        XCTAssertTrue(d.masterElements(behind: d.pages[1]).isEmpty, "no master yet")
        d.masterPageId = d.pages[0].id
        XCTAssertEqual(d.masterElements(behind: d.pages[1]).map(\.id), d.pages[0].elements.map(\.id))
        XCTAssertTrue(d.masterElements(behind: d.pages[0]).isEmpty, "not behind itself")
        d.pages[2].usesMaster = false
        XCTAssertTrue(d.masterElements(behind: d.pages[2]).isEmpty, "opted out")
        d.masterPageId = "gone"
        XCTAssertNil(d.masterPage)
        XCTAssertTrue(d.masterElements(behind: d.pages[1]).isEmpty, "a deleted master is no master")
    }

    func testTogglingTheMasterIsUndoable() {
        let s = DesignStore(design: design())
        s.toggleMasterPage()
        XCTAssertTrue(s.isOnMasterPage)
        s.setPage(1)
        s.toggleUsesMaster()
        XCTAssertEqual(s.page.usesMaster, false)
        s.undo(); s.undo()
        XCTAssertNil(s.design.masterPageId)
    }

    func testTheSVGDrawsMasterElementsAndPageNumbers() {
        var d = design()
        d.masterPageId = d.pages[0].id
        d.pages[0].elements = [Element.shape("rect")]
        d.pages[1].elements = [Element.text("Page {page} of {pages}", fontSize: 24, w: 300)]
        let svg = SVGExporter.svg(design: d, page: d.pages[1])
        XCTAssertEqual(svg.components(separatedBy: "<g").count - 1, 2, "master rect plus the text: \(svg.prefix(200))")
        let straight = TextOutliner.path(for: {
            var e = d.pages[1].elements[0]; e.text = "Page 2 of 3"; return e
        }())
        let tokenised = TextOutliner.path(for: d.pages[1].elements[0])
        XCTAssertNotEqual(straight?.boundingBox.width, tokenised?.boundingBox.width,
                          "the sanity check: the resolved text and the raw tokens differ in width")
        XCTAssertTrue(svg.contains(TextOutliner.svgPathData(straight!).prefix(40)),
                      "the SVG carries the resolved 'Page 2 of 3', not the tokens")
    }

    func testTokensResolveOnlyWhenThePageIsKnown() {
        let el = Element.text("{page}/{pages}")
        XCTAssertEqual(FontLibrary.displayText(for: el), "{page}/{pages}")
        XCTAssertEqual(FontLibrary.displayText(for: el, pageNumber: 2, pageCount: 9), "2/9")
    }

    // MARK: guides

    func testGuidesSnapAndClampAndUndo() {
        let s = DesignStore(design: design())
        s.addGuide(vertical: true)
        s.addGuide(vertical: false, at: 50)
        XCTAssertEqual(s.design.guides.map(\.position), [200, 50])
        let lines = Geometry.snapLines(design: s.design, page: s.page, excluding: [],
                                       settings: SnapSettings(toPage: false, toElements: false))
        XCTAssertEqual(lines.x, [200]); XCTAssertEqual(lines.y, [50])
        let id = s.design.guides[0].id
        s.moveGuideTransient(id, to: 9999)
        s.commit()
        XCTAssertEqual(s.design.guides[0].position, 400, "clamped to the page")
        s.removeGuide(id)
        XCTAssertEqual(s.design.guides.count, 1)
        s.undo()
        XCTAssertEqual(s.design.guides.count, 2)
        s.clearGuides()
        XCTAssertTrue(s.design.guides.isEmpty)
    }

    // MARK: eyedropper

    func testTheEyedropperReadsTheRightPixel() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 50), format: format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 25))       // top-left
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 50, y: 0, width: 50, height: 25))     // top-right
            UIColor.green.setFill(); ctx.fill(CGRect(x: 0, y: 25, width: 50, height: 25))    // bottom-left
            UIColor.black.setFill(); ctx.fill(CGRect(x: 50, y: 25, width: 50, height: 25))   // bottom-right
        }
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(Eyedropper.color(in: cg, at: CGPoint(x: 0.25, y: 0.25)), "#ff0000")
        XCTAssertEqual(Eyedropper.color(in: cg, at: CGPoint(x: 0.75, y: 0.25)), "#0000ff")
        XCTAssertEqual(Eyedropper.color(in: cg, at: CGPoint(x: 0.25, y: 0.75)), "#00ff00")
        XCTAssertEqual(Eyedropper.color(in: cg, at: CGPoint(x: 0.75, y: 0.75)), "#000000")
        XCTAssertEqual(Eyedropper.color(in: cg, at: CGPoint(x: 1.5, y: -2)), "#0000ff", "out of range clamps to the edge")
    }
}
