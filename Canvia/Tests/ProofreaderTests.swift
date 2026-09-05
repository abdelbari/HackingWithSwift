// Spelling across the document.

import XCTest
import UIKit
@testable import Canvia

final class ProofreaderTests: XCTestCase {

    private func design(_ texts: [[String]]) -> Design {
        var d = Design(title: "spell", width: 800, height: 600)
        d.pages = texts.map { page in Page(elements: page.map { Element.text($0) }) }
        return d
    }

    private var english: Bool { UITextChecker.availableLanguages.contains { $0.hasPrefix("en") } }

    func testMisspellingsAreFoundWithSuggestionsInReadingOrder() throws {
        try XCTSkipUnless(english, "no English dictionary in this environment")
        let found = Proofreader.misspellings(in: design([["Teh quick brown fox"], ["Jumps ovr the dog"]]),
                                             language: "en_US")
        XCTAssertEqual(found.map(\.word), ["Teh", "ovr"])
        XCTAssertEqual(found.map(\.pageIndex), [0, 1])
        XCTAssertTrue(found[0].suggestions.contains { $0.lowercased() == "the" }, "\(found[0].suggestions)")
        XCTAssertEqual(found[0].range, NSRange(location: 0, length: 3))
    }

    func testCorrectTextIsClean() throws {
        try XCTSkipUnless(english, "no English dictionary in this environment")
        XCTAssertTrue(Proofreader.misspellings(in: design([["The quick brown fox"]]), language: "en_US").isEmpty)
    }

    func testThingsThatAreNotWordsAreNotFlagged() {
        XCTAssertFalse(Proofreader.isWorthFlagging("NASA"))
        XCTAssertFalse(Proofreader.isWorthFlagging("#summer2026"))
        XCTAssertFalse(Proofreader.isWorthFlagging("v2"))
        XCTAssertFalse(Proofreader.isWorthFlagging("canvia.app"))
        XCTAssertFalse(Proofreader.isWorthFlagging("x"))
        XCTAssertTrue(Proofreader.isWorthFlagging("Teh"))
        XCTAssertTrue(Proofreader.isWorthFlagging("recieve"))
    }

    func testReplacingOneRangeLeavesTheRestAlone() {
        let fixed = Proofreader.replacing(NSRange(location: 4, length: 3), in: "The teh cat", with: "the")
        XCTAssertEqual(fixed, "The the cat")
        XCTAssertEqual(Proofreader.replacing(NSRange(location: 40, length: 3), in: "short", with: "x"), "short",
                       "an out-of-range fix is a no-op, not a crash")
    }
}
