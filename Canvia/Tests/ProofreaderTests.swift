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

    // MARK: style marks

    /// A misspelling at plain characters `from..<to` of the only box.
    private func miss(_ stored: String, _ from: Int, _ to: Int, _ word: String) -> (Design, Proofreader.Misspelling) {
        let d = design([[stored]])
        let (plain, rawAt) = RichText.mapped(stored)
        let lower = plain.index(plain.startIndex, offsetBy: from)
        let upper = plain.index(plain.startIndex, offsetBy: to)
        let range = Proofreader.storedRange(NSRange(lower..<upper, in: plain), plain: plain, rawAt: rawAt, in: stored)!
        let m = Proofreader.Misspelling(pageIndex: 0, elementId: d.pages[0].elements[0].id, range: range,
                                        word: String(plain[lower..<upper]), suggestions: [])
        return (d, m)
    }

    private func fix(_ stored: String, _ from: Int, _ to: Int, _ word: String) -> String? {
        let (d, m) = miss(stored, from, to, word)
        return Proofreader.fixed(d, m, with: word)?.pages[0].elements[0].text
    }

    func testAWordIsReadAcrossStyleMarks() throws {
        try XCTSkipUnless(english, "no English dictionary in this environment")
        let found = Proofreader.misspellings(in: design([["Big **sael** today"]]), language: "en_US")
        XCTAssertEqual(found.map(\.word), ["sael"])
        XCTAssertEqual(found.first?.range, NSRange(location: 6, length: 4), "placed where it is stored")
        let split = Proofreader.misspellings(in: design([["Say he**llo** now"]]), language: "en_US")
        XCTAssertTrue(split.isEmpty, "he**llo** is one word, hello: \(split.map(\.word))")
    }

    func testAFixKeepsTheStylesAndRefusesAStaleRow() {
        let (d, m) = miss("Big **sael** today", 4, 8, "sale")
        XCTAssertEqual(m.range, NSRange(location: 6, length: 4))
        let fixed = Proofreader.fixed(d, m, with: "sale")
        XCTAssertEqual(fixed?.pages[0].elements[0].text, "Big **sale** today")
        XCTAssertNil(Proofreader.fixed(fixed!, m, with: "sale"), "the word is no longer there")
    }

    func testMarksMoveAsTheAndroidTwinMovesThem() {
        XCTAssertEqual(fix("he**lo** there", 0, 4, "hello"), "**hello** there")
        XCTAssertEqual(fix("he**lo world**", 0, 4, "hello"), "**hello world**")
        XCTAssertEqual(fix("**big he**lo", 4, 8, "hello"), "**big hello**")
        XCTAssertEqual(fix("he__lo world__", 0, 4, "hello"), "__hello world__")
        XCTAssertEqual(fix("he~~lo world~~", 0, 4, "hello"), "~~hello world~~")
        XCTAssertEqual(fix("_Photo_**grahpy studio**", 0, 11, "Photography"), "_**Photography_ studio**")
        XCTAssertEqual(fix("**Photo***grahpy studio*", 0, 11, "Photography"), "***Photography** studio*")
    }

    // MARK: ignored words, the dictionary and the language

    /// Shared rows: the design's Ignore list and the phone's dictionary are
    /// passed over, whatever the case — the Android twin's ProofingTest.
    func testWordsIgnoredInTheDesignOrInTheDictionaryAreNotFlagged() throws {
        let ignored = Proofreader.ignoring(Proofreader.ignoring(Design(), "Canvia"), "  qwerty ")
        XCTAssertEqual(Proofreader.ignored(in: ignored), ["canvia", "qwerty"])
        let skip = Proofreader.skipped(ignored, dictionary: ["Zorb"])
        XCTAssertEqual(skip, ["canvia", "qwerty", "zorb"])
        // word, flagged
        let rows: [(String, Bool)] = [("Canvia", false), ("CANVIA", false), ("canvia", false), ("Qwerty", false),
                                      ("zorb", false), ("recieve", true)]
        for (word, flagged) in rows {
            XCTAssertEqual(Proofreader.isWorthFlagging(word, skip: skip), flagged, word)
        }
        try XCTSkipUnless(english, "no English dictionary in this environment")
        var d = design([["Canvia recieve"]])
        d.spellIgnore = ignored.spellIgnore
        let found = Proofreader.misspellings(in: d, language: "en_US", skip: skip).map(\.word)
        XCTAssertFalse(found.contains("Canvia"))
        XCTAssertTrue(found.contains("recieve"), "\(found)")
    }

    func testTheIgnoreListAndTheLanguageAreWrittenOnlyWhenSet() throws {
        let plain = Design()
        func json(_ d: Design) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as? [String: Any])
        }
        XCTAssertNil(try json(plain)["spellIgnore"])
        XCTAssertNil(try json(plain)["language"])
        let ignored = Proofreader.ignoring(Proofreader.ignoring(plain, "zeta"), "Alpha")
        XCTAssertEqual(try json(ignored)["spellIgnore"] as? [String], ["alpha", "zeta"])
        XCTAssertEqual(Proofreader.ignoring(ignored, "ALPHA"), ignored, "already there: the same design")
        let british = Proofreader.withLanguage(plain, "en-GB")
        XCTAssertEqual(british.language, "en-GB")
        XCTAssertEqual(try json(british)["language"] as? String, "en-GB")
        XCTAssertNil(Proofreader.withLanguage(british, nil).language)
        XCTAssertNil(Proofreader.withLanguage(british, "  ").language)
        // Read back as the Android twin writes them, a stray entry passed over.
        let android = #"{"title":"x","spellIgnore":["Zeta","alpha",3],"language":"fr-FR"}"#
        let read = try JSONDecoder().decode(Design.self, from: Data(android.utf8))
        XCTAssertEqual(read.spellIgnore, ["alpha", "zeta"])
        XCTAssertEqual(read.language, "fr-FR")
        XCTAssertEqual(Proofreader.languageName("fr-FR"), "French")
        XCTAssertEqual(Proofreader.languageName(nil), "This phone's language")
    }

    func testTheDictionaryFileIsASortedArrayOfLowerCasedWords() throws {
        let written = String(data: Proofreader.encodeDictionary(["Zorb", "canvia", "CANVIA", " "]), encoding: .utf8)
        XCTAssertEqual(written, #"["canvia","zorb"]"#)
        XCTAssertEqual(Proofreader.decodeDictionary(Data(#"["zorb", "Canvia", 3]"#.utf8)), ["canvia", "zorb"])
        XCTAssertEqual(Proofreader.decodeDictionary(Data(#"{"words": []}"#.utf8)), [])
        XCTAssertEqual(Proofreader.decodeDictionary(nil), [])
        XCTAssertEqual(Proofreader.decodeDictionary(Data("not json".utf8)), [])
        // Kept on the phone: words added once, never taken away.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictionary-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(SpellingDictionary.load(from: url), [])
        XCTAssertEqual(SpellingDictionary.add(["Zorb", "canvia"], to: url, learn: false), 2)
        XCTAssertEqual(SpellingDictionary.add(["ZORB"], to: url, learn: false), 0)
        XCTAssertEqual(SpellingDictionary.load(from: url), ["canvia", "zorb"])
    }

    /// Ignore is one step in the design, and a language is too.
    @MainActor
    func testIgnoreAndTheLanguageAreStepsOfTheirOwn() {
        let s = DesignStore(design: design([["Canvia"]]))
        s.ignoreSpelling("Canvia")
        XCTAssertEqual(s.design.spellIgnore, ["canvia"])
        s.ignoreSpelling("canvia")
        s.setLanguage("de-DE")
        XCTAssertEqual(s.design.language, "de-DE")
        s.undo()
        XCTAssertNil(s.design.language)
        s.undo()
        XCTAssertNil(s.design.spellIgnore)
        XCTAssertFalse(s.canUndo, "ignoring a word already ignored is no step")
    }
}
