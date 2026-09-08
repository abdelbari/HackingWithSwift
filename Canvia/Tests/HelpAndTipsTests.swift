// The help centre and the tip engine.

import XCTest
@testable import Canvia

final class HelpAndTipsTests: XCTestCase {

    // MARK: help

    func testEveryTopicIsCompleteAndUnique() {
        XCTAssertGreaterThan(HelpTopics.all.count, 10)
        XCTAssertEqual(Set(HelpTopics.all.map(\.id)).count, HelpTopics.all.count)
        for t in HelpTopics.all {
            XCTAssertFalse(t.title.isEmpty); XCTAssertFalse(t.body.isEmpty); XCTAssertFalse(t.keywords.isEmpty, t.id)
        }
    }

    func testSearchRanksTitleHitsFirstAndFindsKeywords() {
        let byTitle = HelpTopics.search("Exporting")
        XCTAssertEqual(byTitle.first?.id, "export")
        let byKeyword = HelpTopics.search("pinch")
        XCTAssertTrue(byKeyword.contains { $0.id == "zoom" })
        XCTAssertEqual(HelpTopics.search("   ").count, HelpTopics.all.count)
        XCTAssertTrue(HelpTopics.search("zzzz").isEmpty)
        // Title hits come before body-only hits even when both match.
        let mixed = HelpTopics.search("page")
        XCTAssertEqual(mixed.first?.id, "add", "\(mixed.map(\.id))")
    }

    // MARK: tips

    private func engine(now: @escaping () -> Date) throws -> (TipEngine, UserDefaults, String) {
        let suite = "canvia.tips.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (TipEngine(defaults: defaults, now: now), defaults, suite)
    }

    func testEachTipFiresOnceAndIsRemembered() throws {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let (engine, defaults, suite) = try engine { clock }
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNotNil(engine.tip(for: .textAdded))
        XCTAssertNil(engine.tip(for: .textAdded), "twice")
        clock = clock.addingTimeInterval(3600)
        XCTAssertNil(engine.tip(for: .textAdded), "not even an hour later")
        // A fresh engine on the same store remembers.
        let again = TipEngine(defaults: defaults, now: { clock })
        XCTAssertNil(again.tip(for: .textAdded))
        XCTAssertNotNil(again.tip(for: .photoAdded))
    }

    func testTipsAreRateLimited() throws {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let (engine, defaults, suite) = try engine { clock }
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNotNil(engine.tip(for: .firstElementAdded))
        XCTAssertNil(engine.tip(for: .textAdded), "too soon")
        clock = clock.addingTimeInterval(engine.minimumInterval + 1)
        XCTAssertNotNil(engine.tip(for: .textAdded), "the held-back tip is not lost forever, only that moment")
    }

    func testResetForgetsEverything() throws {
        let (engine, defaults, suite) = try engine { Date() }
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNotNil(engine.tip(for: .manyElements))
        engine.reset()
        XCTAssertNotNil(engine.tip(for: .manyElements))
    }

    @MainActor
    func testTheStoreRaisesTheRightEvents() {
        let s = DesignStore(design: Design(title: "tips", width: 500, height: 500))
        s.add(Element.shape("rect"))
        XCTAssertEqual(s.tipEvent, .firstElementAdded)
        s.add(Element.text("Hi"))
        XCTAssertEqual(s.tipEvent, .textAdded)
        s.add(Element.image("asset:x"))
        XCTAssertEqual(s.tipEvent, .photoAdded)
        s.tipEvent = nil
        s.add(Element.shape("circle"))
        XCTAssertNil(s.tipEvent, "a fourth shape is nothing to remark on")
        s.select(s.page.elements[0].id)
        s.select(s.page.elements[1].id, additive: true)
        XCTAssertEqual(s.tipEvent, .multiSelected)
    }
}
