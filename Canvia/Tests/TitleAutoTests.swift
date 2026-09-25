//
//  TitleAutoTests.swift
//  CanviaTests
//
import XCTest
@testable import Canvia

/// `titleAuto` is written by the Android twin and must survive a trip through
/// this app: dropped on save, a design renamed on Android would come back from
/// the iPhone treating its title as the app's to change again.
final class TitleAutoTests: XCTestCase {

    private func decode(_ json: String) throws -> Design {
        try JSONDecoder().decode(Design.self, from: Data(json.utf8))
    }

    func testAnOlderDocumentWithoutTheFieldDefaultsToTrue() throws {
        let design = try decode(#"{"id":"doc-1","title":"Poster"}"#)
        XCTAssertTrue(design.titleAuto)
    }

    func testFalseIsReadAsFalse() throws {
        let design = try decode(#"{"id":"doc-1","title":"Rooftop Cinema","titleAuto":false}"#)
        XCTAssertFalse(design.titleAuto)
    }

    func testFalseSurvivesARoundTrip() throws {
        var design = Design(title: "Sofia's 40th")
        design.titleAuto = false
        let back = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertFalse(back.titleAuto)
        XCTAssertEqual(back.title, "Sofia's 40th")
    }

    func testTheFieldIsWrittenOut() throws {
        var design = Design(title: "Poster")
        design.titleAuto = false
        let json = String(decoding: try JSONEncoder().encode(design), as: UTF8.self)
        XCTAssertTrue(json.contains(#""titleAuto":false"#), json)
    }

    func testAMalformedValueFallsBackToTrueRatherThanFailingTheDocument() throws {
        let design = try decode(#"{"id":"doc-1","title":"Poster","titleAuto":"yes"}"#)
        XCTAssertTrue(design.titleAuto)
    }
}
