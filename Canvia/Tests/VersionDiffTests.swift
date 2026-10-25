// Version history's page badges and Bring back this page, with the shared
// fixture Fixtures/versions/diff.json — the Android twin's VersionDiffTest
// reads the same file.

import XCTest
@testable import Canvia

final class VersionDiffTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("versions/diff") }

    private func design(_ key: String) throws -> Design {
        try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(fixture()[key])))
    }

    func testEachPageOfTheVersionIsTheSameChangedOrOnlyInTheVersion() throws {
        let expected = try XCTUnwrap(fixture()["pages"] as? [[String: String]])
        let found = VersionDiff.pages(try design("version"), try design("current"))
        XCTAssertEqual(found.map(\.pageId), expected.compactMap { $0["pageId"] })
        XCTAssertEqual(found.map(\.state.rawValue), expected.compactMap { $0["state"] })
    }

    func testAPageBroughtBackLandsWhereTheSharedFileSaysAsAFreshCopy() throws {
        let version = try design("version")
        let current = try design("current")
        let cases = try XCTUnwrap(fixture()["bringBack"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let id = try XCTUnwrap(c["pageId"] as? String)
            let brought = try XCTUnwrap(VersionDiff.bringBack(
                version, into: current, pageId: id,
                currentIndex: try XCTUnwrap(c["currentIndex"] as? Int),
                replace: try XCTUnwrap(c["replace"] as? Bool)))
            XCTAssertEqual(brought.index, c["index"] as? Int, id)
            XCTAssertEqual(brought.design.pages.count, c["pages"] as? Int, id)
            let copy = brought.design.pages[brought.index]
            let original = try XCTUnwrap(version.pages.first { $0.id == id })
            XCTAssertNotEqual(copy.id, original.id)
            XCTAssertEqual(copy.elements.map(\.text), original.elements.map(\.text))
            let originalIds = Set(original.elements.map(\.id))
            XCTAssertTrue(copy.elements.allSatisfy { !originalIds.contains($0.id) })
        }
    }

    func testAnArrowComesBackJoinedToTheCopyOfWhatItWasJoinedTo() throws {
        let brought = try XCTUnwrap(VersionDiff.bringBack(try design("version"), into: try design("current"),
                                                          pageId: "p3", currentIndex: 0, replace: false))
        let page = brought.design.pages[brought.index]
        let text = try XCTUnwrap(page.elements.first { $0.text == "Gone since" })
        let line = try XCTUnwrap(page.elements.first { $0.type == .line })
        XCTAssertEqual(line.connectFrom, text.id)
    }

    func testTheVersionIsLeftAsItIsAndALockedPageIsNeverReplaced() throws {
        let version = try design("version")
        let current = try design("current")
        let before = version
        _ = VersionDiff.bringBack(version, into: current, pageId: "p2", currentIndex: 0, replace: true)
        XCTAssertEqual(before, version)
        var locked = current
        if let i = locked.pages.firstIndex(where: { $0.id == "p2" }) { locked.pages[i].locked = true }
        XCTAssertNil(VersionDiff.bringBack(version, into: locked, pageId: "p2", currentIndex: 0, replace: true))
        // Added beside it, it comes.
        XCTAssertEqual(VersionDiff.bringBack(version, into: locked, pageId: "p2", currentIndex: 0, replace: false)?.index, 1)
        XCTAssertNil(VersionDiff.bringBack(version, into: current, pageId: "nope", currentIndex: 0, replace: false))
    }

    func testThumbnailsAndCachesDoNotMakeAPageChanged() throws {
        let a = try XCTUnwrap(try design("current").pages.first { $0.id == "p4" })
        let b = try XCTUnwrap(try design("version").pages.first { $0.id == "p4" })
        XCTAssertNotNil(VersionDiff.canonical(a))
        XCTAssertEqual(VersionDiff.canonical(a), VersionDiff.canonical(b))
    }
}
