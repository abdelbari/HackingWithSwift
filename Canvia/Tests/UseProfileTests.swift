// "What will you use Canvia for?": the uses Content.json carries (the
// Android twin's templates/uses.json), and how Home's design types and
// templates follow the answer — the twin's UseProfileTest, case for case.

import XCTest
@testable import Canvia

final class UseProfileTests: XCTestCase {

    private func defaults() -> UserDefaults {
        let name = "UseProfileTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func preset(_ id: String, _ category: String = "Social") -> SizePreset {
        SizePreset(id: id, name: id, category: category, width: 100, height: 100)
    }

    func testTheSevenUsesInTheChipsOrder() {
        XCTAssertEqual(UseProfile.all.map(\.id),
                       ["personal", "student", "teacher", "small-business", "marketing", "content-creator", "nonprofit"])
        XCTAssertEqual(UseProfile.all.map(\.name),
                       ["Personal", "Student", "Teacher", "Small business", "Marketing", "Content creator", "Nonprofit"])
        XCTAssertEqual(UseProfile.byId("teacher")?.sizes,
                       ["worksheet-a4", "presentation", "certificate", "planner", "poster"])
        // Every design type a use names is one the catalogue has.
        for use in UseProfile.all {
            for id in use.sizes { XCTAssertNotNil(SizePreset.byId(id), "\(use.id): \(id)") }
        }
    }

    /// The use's types that are there, in its order, then the rest in
    /// theirs; no use, or an unknown one, leaves them be.
    func testOrderPutsTheUsesTypesFirst() {
        let presets = ["insta-post", "poster", "presentation", "flyer", "certificate"].map { preset($0) }
        XCTAssertEqual(UseProfile.order("teacher", presets).map(\.id),
                       ["presentation", "certificate", "poster", "insta-post", "flyer"])
        XCTAssertEqual(UseProfile.order(nil, presets).map(\.id), presets.map(\.id))
        XCTAssertEqual(UseProfile.order("astronaut", presets).map(\.id), presets.map(\.id))
    }

    func testHeroKeepsTheRowsLength() {
        XCTAssertEqual(UseProfile.hero(nil).map(\.id), SizePreset.hero.map(\.id))
        let teacher = UseProfile.hero("teacher")
        XCTAssertEqual(teacher.count, SizePreset.hero.count)
        XCTAssertEqual(Array(teacher.prefix(5)).map(\.id),
                       ["worksheet-a4", "presentation", "certificate", "planner", "poster"])
    }

    func testCategoriesAndTemplatesFollowTheUse() {
        XCTAssertEqual(UseProfile.categories("teacher", ["Business", "Events", "Education", "Food"]),
                       ["Education", "Events", "Business", "Food"])
        XCTAssertEqual(UseProfile.categories(nil, ["Business", "Events"]), ["Business", "Events"])
        let items = [("a", "Business"), ("b", "Events"), ("c", "Education"), ("d", "Education"), ("e", "Food")]
        XCTAssertEqual(UseProfile.templatesFirst("teacher", items) { $0.1 }.map(\.0), ["c", "d", "b", "a", "e"])
        XCTAssertEqual(UseProfile.templatesFirst(nil, items) { $0.1 }.map(\.0), ["a", "b", "c", "d", "e"])
    }

    /// Asked once, before the tour; kept under canvia.use; skipping keeps
    /// none.
    func testTheAnswerIsKeptAndAskedOnce() {
        let d = defaults()
        XCTAssertTrue(UseProfile.needsAsking(defaults: d, arguments: []))
        XCTAssertFalse(UseProfile.needsAsking(defaults: d, arguments: ["-canviaSkipTour"]))
        UseProfile.set("student", d)
        XCTAssertEqual(d.string(forKey: "canvia.use"), "student")
        XCTAssertEqual(UseProfile.current(d), "student")
        XCTAssertFalse(UseProfile.needsAsking(defaults: d, arguments: []))
        UseProfile.set(nil, d)
        XCTAssertNil(UseProfile.current(d))
        XCTAssertFalse(UseProfile.needsAsking(defaults: d, arguments: []))
        d.set("astronaut", forKey: UseProfile.key)
        XCTAssertNil(UseProfile.current(d))
    }

    func testBackupSettingsRoundTrip() {
        let data = UseProfile.encodeSettings("nonprofit")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"canvia.use":"nonprofit"}"#)
        XCTAssertEqual(UseProfile.decodeSettings(data), "nonprofit")
        XCTAssertNil(UseProfile.decodeSettings(Data(#"{"canvia.use":"astronaut"}"#.utf8)))
        XCTAssertNil(UseProfile.decodeSettings(Data("not json".utf8)))
        XCTAssertNil(UseProfile.decodeSettings(nil))
        XCTAssertEqual(UseProfile.settingsFile, "settings.json")
    }

    /// Shared: Home's hero row for each use, and the categories' order —
    /// the Android twin's fixtures/use-profile.json.
    func testTheSharedFixture() throws {
        let fixture = try SharedFixture.object("use-profile")
        for row in try XCTUnwrap(fixture["cases"] as? [[String: Any]]) {
            let use = row["use"] as? String
            XCTAssertEqual(UseProfile.hero(use).map(\.id), row["hero"] as? [String], "\(use ?? "none")")
        }
        for row in try XCTUnwrap(fixture["categories"] as? [[String: Any]]) {
            let use = row["use"] as? String
            let from = row["from"] as? [String] ?? []
            XCTAssertEqual(UseProfile.categories(use, from), row["expect"] as? [String], "\(use ?? "none")")
        }
    }
}
