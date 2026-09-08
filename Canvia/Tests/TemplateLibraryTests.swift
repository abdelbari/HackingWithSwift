// The bundled template library. Most of it is generated from the shared
// spec under the Android repo's `templates/` directory, so these are the
// checks that keep a regenerated Content.json from quietly shipping a
// template that renders wrong — an unknown shape id draws a rectangle and
// an unknown font falls back to the system one, neither of which throws.

import XCTest
@testable import Canvia

final class TemplateLibraryTests: XCTestCase {

    private var templates: [Template] { ContentLibrary.templates }

    func testTheLibraryIsBigEnoughToBrowse() {
        XCTAssertGreaterThanOrEqual(templates.count, 40,
                                    "only \(templates.count) templates in the library")
        XCTAssertEqual(Set(templates.map(\.id)).count, templates.count, "duplicate template id")
        XCTAssertEqual(Set(templates.map(\.name)).count, templates.count, "duplicate template name")
        for t in templates {
            XCTAssertFalse(t.name.isEmpty, "\(t.id) has no name")
            XCTAssertFalse(t.category.isEmpty, "\(t.id) has no category")
            XCTAssertTrue(t.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" },
                          "\(t.id) is not a kebab-case id")
        }
    }

    func testEveryTemplateIsAUsablePage() {
        for t in templates {
            XCTAssertGreaterThan(t.width, 0, "\(t.id) has no width")
            XCTAssertGreaterThan(t.height, 0, "\(t.id) has no height")
            XCTAssertFalse(t.elements.isEmpty, "\(t.id) is empty")
            XCTAssertLessThanOrEqual(t.elements.count, 20, "\(t.id) has \(t.elements.count) elements")

            for el in t.elements {
                let where_ = "\(t.id)/\(el.type)"
                XCTAssertGreaterThan(el.w, 0, "\(where_) has no width")
                XCTAssertGreaterThan(el.h, 0, "\(where_) has no height")
                XCTAssertTrue((0...1).contains(el.opacity), "\(where_) opacity \(el.opacity)")

                // A deliberate bleed may hang off an edge; nothing may sit
                // entirely outside the page, where it can never be found.
                XCTAssertTrue(el.x + el.w > 0 && el.y + el.h > 0, "\(where_) is off the top-left")
                XCTAssertTrue(el.x < t.width && el.y < t.height, "\(where_) is off the bottom-right")
            }
        }
    }

    func testEveryShapeAndFontResolves() {
        for t in templates {
            for el in t.elements where el.type == .shape {
                guard let id = el.shapeId else {
                    XCTFail("\(t.id): a shape with no shapeId")
                    continue
                }
                XCTAssertEqual(ContentLibrary.shape(id).id, id,
                               "\(t.id) names shape \(id), which the library does not have")
            }
            for el in t.elements where el.type == .text {
                XCTAssertFalse((el.text ?? "").isEmpty, "\(t.id): empty text element")
                XCTAssertGreaterThanOrEqual(el.fontSize ?? 0, 14, "\(t.id): tiny type")
                XCTAssertNotNil(el.color, "\(t.id): text with no colour")
                if let family = el.fontFamily {
                    XCTAssertNotNil(FontLibrary.stackMap[family],
                                    "\(t.id) names font \(family), which FontLibrary does not have")
                }
            }
        }
    }

    func testEveryCategoryAndCommonSizeIsRepresented() {
        let categories = ContentLibrary.templateCategories
        XCTAssertGreaterThanOrEqual(categories.count, 4)
        for c in categories {
            XCTAssertFalse(ContentLibrary.filteredTemplates(in: c, matching: "").isEmpty, "\(c) is empty")
        }
        // The sizes someone actually opens the app to make.
        let sizes = Set(templates.map { "\(Int($0.width))x\(Int($0.height))" })
        for expected in ["1080x1080", "1080x1920", "1920x1080", "1280x720", "1050x600"] {
            XCTAssertTrue(sizes.contains(expected), "nothing in the library is \(expected)")
        }
    }

    func testInstantiatingGivesFreshIdsAndMeasuredText() {
        for t in templates {
            let a = t.instantiate()
            let b = t.instantiate()
            XCTAssertNotEqual(a.id, b.id, "\(t.id) reused a document id")
            let aIds = Set(a.pages[0].elements.map(\.id))
            let bIds = Set(b.pages[0].elements.map(\.id))
            XCTAssertTrue(aIds.isDisjoint(with: bIds), "\(t.id) reused element ids")
            XCTAssertEqual(a.pages[0].elements.count, t.elements.count)
            for el in a.pages[0].elements where el.type == .text {
                XCTAssertGreaterThan(el.h, 0, "\(t.id): text measured to nothing")
            }
        }
    }

    func testApplyingATemplateToAnotherSizeKeepsItOnThePage() {
        var target = Design(title: "Story", width: 1080, height: 1920)
        target.pages = [Page()]
        for t in templates {
            let page = t.makePage(for: target)
            let scale = min(target.width / t.width, target.height / t.height)
            for (i, el) in page.elements.enumerated() {
                XCTAssertEqual(el.w, t.elements[i].w * scale, accuracy: 0.01, "\(t.id) did not scale")
                // Anything that fitted its own page still fits this one.
                let source = t.elements[i]
                let fitted = source.x >= 0 && source.y >= 0
                    && source.x + source.w <= t.width && source.y + source.h <= t.height
                if fitted {
                    XCTAssertGreaterThanOrEqual(el.x, -1, "\(t.id) spilled left")
                    XCTAssertLessThanOrEqual(el.x + el.w, target.width + 1, "\(t.id) spilled right")
                }
            }
        }
    }
}
