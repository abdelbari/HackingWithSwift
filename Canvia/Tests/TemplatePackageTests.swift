// A template sent as a file: the shared package both phones read and write
// — Fixtures/template-package.canvia-template.json, which the Android
// twin's TemplatePackageTest reads too.

import XCTest
@testable import Canvia

final class TemplatePackageTests: XCTestCase {

    private func text() throws -> String {
        try SharedFixture.text("template-package", ext: "canvia-template.json")
    }

    private func read(_ text: String) throws -> DesignPackage.Package {
        try JSONDecoder().decode(DesignPackage.Package.self, from: Data(text.utf8))
    }

    func testATemplatesNameAndCategoryAreReadFromThePackage() throws {
        let package = try read(text())
        XCTAssertEqual(DesignPackage.template(of: package), DesignPackage.AsTemplate(name: "Bake sale", category: "Events"))
        XCTAssertEqual(package.design.title, "Bake sale poster")
        XCTAssertEqual(Set(package.media.keys), ["cake"])
    }

    func testWrittenAgainItIsTheSameTemplateItsKeyInSortedPlace() throws {
        let package = try read(text())
        let written = String(decoding: try DesignPackage.encode(package), as: UTF8.self)
        XCTAssertTrue(written.hasPrefix(#"{"asTemplate":{"category":"Events","name":"Bake sale"},"design":"#), written)
        let again = try read(written)
        XCTAssertEqual(DesignPackage.template(of: again), DesignPackage.template(of: package))
        XCTAssertEqual(again.design, package.design)
        XCTAssertEqual(again.media["cake"]?.data, package.media["cake"]?.data)
    }

    func testAPlainDesignFileIsNoTemplateAndATemplateIsNamedForItsFile() throws {
        var package = try read(text())
        package.asTemplate = nil
        XCTAssertNil(DesignPackage.template(of: try read(String(decoding: try DesignPackage.encode(package), as: UTF8.self))))
        XCTAssertEqual(DesignPackage.templateFileName("Bake sale"), "Bake sale.canvia-template.json")
        // No name is no template; no category is filed under Personal.
        let nameless = try text().replacingOccurrences(of: #""name": "Bake sale""#, with: #""name": " ""#)
        XCTAssertNil(DesignPackage.template(of: try read(nameless)))
        let uncategorised = try text().replacingOccurrences(of: #""category": "Events","#, with: "")
        XCTAssertEqual(DesignPackage.template(of: try read(uncategorised)),
                       DesignPackage.AsTemplate(name: "Bake sale", category: "Personal"))
        // A key of the wrong kind is read as none, and the design still reads.
        let odd = try text().replacingOccurrences(of: #""asTemplate": {"#, with: #""asTemplate": 3, "x": {"#)
        XCTAssertNil(DesignPackage.template(of: try read(odd)))
    }
}
