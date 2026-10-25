// Help's fifty topics and its Tools section, with the shared fixture
// Fixtures/help-search.json — the Android twin's HelpTopicsTest reads the
// same file — and What's new (WhatsNew), as its WhatsNewTest.

import XCTest
@testable import Canvia

final class HelpSearchTests: XCTestCase {

    func testThisPhonesNineteenThenHelpJsonsTopics() {
        XCTAssertEqual(HelpTopics.own.count, 19)
        XCTAssertEqual(HelpTopics.all.count, 50)
        XCTAssertEqual(HelpTopics.all[18].id, "screen-reader")
        XCTAssertEqual(HelpTopics.all[19].id, "crop-mode")
        XCTAssertEqual(Set(HelpTopics.all.map(\.id)).count, HelpTopics.all.count)
        for topic in HelpTopics.all {
            XCTAssertFalse(topic.title.isEmpty, topic.id)
            XCTAssertFalse(topic.body.isEmpty, topic.id)
            XCTAssertFalse(topic.keywords.isEmpty, topic.id)
        }
    }

    /// help.json's Presenting, worded for this phone's Present: how to
    /// point and draw, and Show me opens Present.
    func testPresentingSaysHowToPointAndDraw() throws {
        let presenting = try XCTUnwrap(HelpTopics.all.first { $0.id == "present" })
        XCTAssertEqual(presenting.opens, .present)
        for said in ["hold", "laser", "Pen", "Fade ink", "L ", "P ", "E ", "D a drumroll", "M a mic drop", "VoiceOver"] {
            XCTAssertTrue(presenting.body.contains(said), said)
        }
        XCTAssertTrue(presenting.keywords.contains("confetti"))
    }

    /// Each new place to go has a topic that opens it, by its name in
    /// help.json, and every name help.json uses is one this phone knows.
    func testEveryPlaceHelpJsonNamesOpensSomething() throws {
        let added: [HelpTarget] = [.brand, .planner, .present, .print, .timeline, .audio, .captions, .bulk,
                                   .a11yCheck, .draw, .chartData, .table, .backup]
        for target in added {
            XCTAssertTrue(HelpTopics.all.contains { $0.opens == target }, target.rawValue)
        }
        XCTAssertEqual(HelpTarget(rawValue: "a11yCheck"), .a11yCheck)
        XCTAssertEqual(HelpTarget(rawValue: "chartData"), .chartData)
        XCTAssertNil(HelpTarget(rawValue: "nowhere"))
        let url = try XCTUnwrap(Bundle.main.url(forResource: "help", withExtension: "json"))
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        for entry in raw {
            if let opens = entry["opens"] as? String { XCTAssertNotNil(HelpTarget(rawValue: opens), opens) }
        }
    }

    /// The shared vectors: help.json's topics found, and the tools.
    func testHelpJsonsTopicsAndToolsAreFoundAsTheSharedFileSays() throws {
        let fixture = try SharedFixture.object("help-search")
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        let shared = Set(HelpTopics.shared.map(\.id))
        for c in cases {
            let query = try XCTUnwrap(c["query"] as? String)
            XCTAssertEqual(HelpTopics.search(query).map(\.id).filter(shared.contains), c["topics"] as? [String], query)
            XCTAssertEqual(HelpTopics.tools(query).map(\.id).filter(shared.contains), c["tools"] as? [String], query)
        }
    }

    func testAToolHasSomewhereToGoAndIsFoundByTitleOrWordsNeverBody() {
        XCTAssertEqual(HelpTopics.tools("bulk create").map(\.id), ["bulk"])
        XCTAssertTrue(HelpTopics.tools("   ").isEmpty)
        XCTAssertTrue(HelpTopics.tools("captions").allSatisfy { $0.opens != nil })
        // "Removing a photo's background" has nowhere to go: a topic only.
        XCTAssertTrue(HelpTopics.tools("remove background").isEmpty)
        XCTAssertEqual(HelpTopics.search("remove background").first?.id, "cutout")
    }

    // MARK: What's new

    func testVersionsComparePartByPartBlankOldestOfAll() {
        XCTAssertGreaterThan(WhatsNew.compare("1.36", "1.4"), 0)
        XCTAssertEqual(WhatsNew.compare("1.36", "1.36.0"), 0)
        XCTAssertGreaterThan(WhatsNew.compare("2", "1.99"), 0)
        XCTAssertGreaterThan(WhatsNew.compare("1.0", ""), 0)
        XCTAssertGreaterThan(WhatsNew.compare("0.1", nil), 0)
        XCTAssertEqual(WhatsNew.compare("", nil), 0)
    }

    func testWhatsNewJsonsNewestVersionIsTheOneHomeCompares() {
        XCTAssertEqual(WhatsNew.current, "1.36")
        XCTAssertFalse(WhatsNew.all.first?.items.isEmpty ?? true)
        let items = WhatsNew.all.flatMap(\.items)
        XCTAssertTrue(items.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty })
        let places: Set<String> = [WhatsNew.tools, WhatsNew.trash, WhatsNew.templates]
        XCTAssertTrue(items.allSatisfy { $0.opens.map(places.contains) ?? true })
    }

    func testTheCardShowsOnceForEachVersionNewerThanTheOneSeen() {
        let text = #"[{"version":"1.36","items":[{"id":"a","title":"A","body":"a","opens":"tools"}]},"#
            + #"{"version":"1.35","items":[{"id":"b","title":"B","body":"b","opens":null}]}]"#
        let versions = WhatsNew.decode(Data(text.utf8))
        XCTAssertTrue(WhatsNew.shows("", versions: versions))
        XCTAssertTrue(WhatsNew.shows("1.35", versions: versions))
        XCTAssertFalse(WhatsNew.shows("1.36", versions: versions))
        XCTAssertFalse(WhatsNew.shows("1.40", versions: versions))
        XCTAssertEqual(WhatsNew.since("", versions: versions).map(\.id), ["a", "b"])
        XCTAssertEqual(WhatsNew.since("1.35", versions: versions).map(\.id), ["a"])
        XCTAssertEqual(WhatsNew.since("1.35", versions: versions).first?.opens, "tools")
        XCTAssertNil(WhatsNew.since("", versions: versions).last?.opens)
        XCTAssertTrue(WhatsNew.decode(Data("not json".utf8)).isEmpty)
    }

    func testTheVersionSeenTravelsInABackupAndNeverGoesBack() throws {
        let data = Backup.encodeSettings(autoLists: true, use: nil, exportA11yNudge: true, proofTypography: true,
                                         accessibility: AccessibilityPrefs.Settings(), recentSearches: [],
                                         recentTemplates: [], autoBackup: AutoBackup.Config(), whatsNewSeen: "1.36")
        XCTAssertEqual(Backup.decodeWhatsNewSeen(data), "1.36")
        XCTAssertNil(Backup.decodeWhatsNewSeen(Data(#"{"whatsNewSeen":36}"#.utf8)))
        let suite = "canvia.whatsnew.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        WhatsNew.restore("1.35", defaults: defaults)
        XCTAssertEqual(WhatsNew.seen(defaults), "1.35")
        WhatsNew.restore("1.20", defaults: defaults)
        XCTAssertEqual(WhatsNew.seen(defaults), "1.35")
        WhatsNew.restore(nil, defaults: defaults)
        XCTAssertEqual(WhatsNew.seen(defaults), "1.35")
    }
}
