// Reopening a design where it was left (LastPlace): the "lastPlace" record,
// capped at two hundred designs, the page a design opens on, the zoom kept
// unless at fit, "resumePlace", forgetting a deleted design, and a backup
// that leaves the record out. The Android twin's LastPlaceTest, row for row.

import XCTest
@testable import Canvia

final class LastPlaceTests: XCTestCase {

    private func defaults() -> UserDefaults {
        let name = "LastPlaceTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testThePlaceIsKeptAsJSONAndCappedAtTwoHundred() {
        let place = LastPlace.Place(page: "p2", zoom: 1.5, scroll: nil, t: 1000)
        let text = LastPlace.encode(["d1": place, "d2": LastPlace.Place(page: "x", zoom: nil, scroll: 0.42, t: 5)])
        XCTAssertEqual(text, #"{"d1":{"page":"p2","t":1000,"zoom":1.5},"d2":{"page":"x","scroll":0.42,"t":5}}"#)
        XCTAssertEqual(LastPlace.decode(text)["d1"], place)
        XCTAssertEqual(LastPlace.decode(text)["d2"]?.scroll, 0.42)
        XCTAssertTrue(LastPlace.decode("not json").isEmpty)
        var many: [String: LastPlace.Place] = [:]
        for i in 0..<LastPlace.limit {
            many = LastPlace.remembered(many, designId: "d\(i)", place: LastPlace.Place(page: "p", t: Double(i)))
        }
        let next = LastPlace.remembered(many, designId: "new", place: LastPlace.Place(page: "p", t: 9999))
        XCTAssertEqual(next.count, LastPlace.limit)
        XCTAssertNil(next["d0"], "the longest unopened goes first")
        XCTAssertNotNil(next["new"])
    }

    func testTheSharedRowsOfWhereADesignOpens() throws {
        let root = try SharedFixture.object("last-place")
        for row in try XCTUnwrap(root["rows"] as? [[String: Any]]) {
            let hidden = Set((row["hidden"] as? [String]) ?? [])
            var d = Design(title: "Deck", width: 1080, height: 1080)
            d.pages = ((row["pages"] as? [String]) ?? []).map { id in
                var page = Page(id: id)
                page.hidden = hidden.contains(id) ? true : nil
                return page
            }
            let left = try XCTUnwrap(row["left"] as? String)
            XCTAssertEqual(LastPlace.pageIndex(d, place: LastPlace.Place(page: left, t: 0)), row["opens"] as? Int, "\(row)")
        }
    }

    func testADesignOpensOnItsPageOrTheNearestShownOneBefore() {
        var d = Design(title: "Deck", width: 1080, height: 1080)
        d.pages = ["a", "b", "c", "d"].map { Page(id: $0) }
        d.pages[2].hidden = true
        d.pages[1].hidden = true
        XCTAssertEqual(LastPlace.pageIndex(d, place: LastPlace.Place(page: "d", t: 0)), 3)
        XCTAssertEqual(LastPlace.pageIndex(d, place: LastPlace.Place(page: "c", t: 0)), 0)
        XCTAssertEqual(LastPlace.pageIndex(d, place: LastPlace.Place(page: "gone", t: 0)), 0)
        XCTAssertEqual(LastPlace.pageIndex(d, place: nil), 0)
        XCTAssertTrue(LastPlace.offersPresent(d, place: LastPlace.Place(page: "d", t: 0)))
        XCTAssertFalse(LastPlace.offersPresent(d, place: LastPlace.Place(page: "a", t: 0)))
        XCTAssertNil(LastPlace.keptZoom(0.401, fit: 0.4), "within 2% of fit is fit")
        XCTAssertEqual(LastPlace.keptZoom(1, fit: 0.4), 1)
    }

    func testForgettingADesignAndTheSetting() {
        let prefs = defaults()
        XCTAssertTrue(LastPlace.resumes(prefs), "on unless turned off")
        prefs.set(false, forKey: LastPlace.resumeKey)
        XCTAssertFalse(LastPlace.resumes(prefs))
        LastPlace.remember("d1", LastPlace.Place(page: "p", t: 1), prefs)
        LastPlace.remember("d2", LastPlace.Place(page: "q", t: 2), prefs)
        LastPlace.forget(["d1"], prefs)
        XCTAssertNil(LastPlace.place(for: "d1", prefs))
        XCTAssertEqual(LastPlace.place(for: "d2", prefs)?.page, "q")
    }

    func testABackupLeavesThePlaceOut() {
        let data = Backup.encodeSettings(autoLists: true, use: nil)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(LastPlace.key))
    }
}
