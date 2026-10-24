// Home's search history and the templates used lately: the Android twin's
// RecentSearchesTest, row for row.

import XCTest
@testable import Canvia

final class RecentSearchesTests: XCTestCase {

    /// Shared: what a search does to the list, row by row.
    func testASearchIsRememberedTrimmedOnceWhateverItsCapitalsNewestFirst() {
        let cases: [([String], String, [String])] = [
            ([], "  poster  ", ["poster"]),
            (["poster", "logo"], "Logo", ["Logo", "poster"]),
            (["poster"], "   ", ["poster"]),
            (["a", "b"], "b", ["b", "a"]),
            ((1...10).map { "q\($0)" }, "new", ["new"] + (1...9).map { "q\($0)" }),
        ]
        for (before, query, after) in cases {
            XCTAssertEqual(RecentSearches.remembered(before, query), after, query)
        }
    }

    func testRemovingOneTakesEverySpellingOfItAndNothingElse() {
        XCTAssertEqual(RecentSearches.removed(["Poster", "logo"], " poster "), ["logo"])
        XCTAssertEqual(RecentSearches.removed(["logo"], "flyer"), ["logo"])
    }

    func testTemplatesUsedAreKeptByIdTwelveAtMostNewestFirst() {
        let ids = (1...12).map { "t\($0)" }
        XCTAssertEqual(RecentSearches.usedTemplate(ids, "t5"), ["t5"] + ids.filter { $0 != "t5" })
        XCTAssertEqual(RecentSearches.usedTemplate(ids, "new"), ["new"] + Array(ids.prefix(11)))
        // One no longer in the library is passed over.
        XCTAssertEqual(RecentSearches.templates(["gone", "mega-sale-post"]).map(\.id), ["mega-sale-post"])
    }

    /// Shared: the stored form, a JSON array of strings.
    func testTheListsAreJSONArraysOfStringsReadForgivingly() {
        XCTAssertEqual(RecentSearches.encode(["poster", "Logo"]), #"["poster","Logo"]"#)
        XCTAssertEqual(RecentSearches.decode(#"["poster"," Logo ","logo",3,""]"#), ["poster", "Logo"])
        XCTAssertEqual(RecentSearches.decode("not json"), [])
        XCTAssertEqual(RecentSearches.decode(nil), [])
        XCTAssertEqual(RecentSearches.decode(RecentSearches.encode((1...15).map { "q\($0)" })).count, 10)
        let templates = RecentSearches.encode((1...15).map { "t\($0)" })
        XCTAssertEqual(RecentSearches.decode(templates, limit: RecentSearches.templateLimit, searches: false).count, 12)
    }

    func testKeptUnderTheKeysBothPhonesUse() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RecentSearchesTests"))
        defaults.removePersistentDomain(forName: "RecentSearchesTests")
        RecentSearches.remember(" poster ", defaults)
        RecentSearches.remember("Logo", defaults)
        XCTAssertEqual(defaults.string(forKey: "recentSearches"), #"["Logo","poster"]"#)
        RecentSearches.forget("LOGO", defaults)
        XCTAssertEqual(RecentSearches.searches(defaults), ["poster"])
        RecentSearches.used("mega-sale-post", defaults)
        XCTAssertEqual(defaults.string(forKey: "recentTemplates"), #"["mega-sale-post"]"#)
    }

    /// A backup carries both under this phone's names, as the Android
    /// twin's Backup.Settings writes them.
    func testABackupCarriesBoth() throws {
        let data = Backup.encodeSettings(autoLists: true, use: nil, exportA11yNudge: true,
                                         accessibility: AccessibilityPrefs.Settings(),
                                         recentSearches: ["poster"], recentTemplates: ["mega-sale-post"])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["recentSearches"] as? [String], ["poster"])
        XCTAssertEqual(object["recentTemplates"] as? [String], ["mega-sale-post"])
        let read = Backup.decodeRecents(data)
        XCTAssertEqual(read.searches, ["poster"])
        XCTAssertEqual(read.templates, ["mega-sale-post"])
        XCTAssertNil(Backup.decodeRecents(Data("{}".utf8)).searches)
        XCTAssertNil(Backup.decodeRecents(Data("{}".utf8)).templates)
    }
}
