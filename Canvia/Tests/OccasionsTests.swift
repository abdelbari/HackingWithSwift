// The occasions calendar and its Coming up rule, as both phones read them:
// the shared dates (templates/occasions-cases.json), the computus, and the
// round 35 templates made for each occasion. The Android twin's
// OccasionsTest, row for row.

import XCTest
@testable import Canvia

final class OccasionsTests: XCTestCase {

    private typealias Day = Occasions.CivilDay

    private func day(_ y: Int, _ m: Int, _ d: Int) throws -> Day { try XCTUnwrap(Day(year: y, month: m, day: d)) }

    func testEverySharedDateHasTheSameOccasionsComingUpNearestFirst() throws {
        let cases = try XCTUnwrap(try JSONSerialization.jsonObject(with: SharedFixture.data("occasions-cases")) as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for c in cases {
            let today = try XCTUnwrap(Day.parse(c["today"] as? String ?? ""))
            let locale = Locale(identifier: c["locale"] as? String ?? "")
            let up = Occasions.upcoming(today, region: locale.region?.identifier)
            let label = "\(c["today"] ?? "") \(c["locale"] ?? "")"
            XCTAssertEqual(up.map(\.occasion.id), c["expected"] as? [String] ?? [], label)
            XCTAssertEqual(up.map(\.days), c["days"] as? [Int] ?? [], label)
        }
    }

    func testTheAppsCalendarIsTheSharedOne() throws {
        let shared = try JSONDecoder().decode([OccasionSpec].self, from: SharedFixture.data("occasions")).compactMap(\.occasion)
        XCTAssertEqual(Occasions.all, shared)
        XCTAssertEqual(Occasions.all.count, 14)
    }

    func testEasterFallsByTheComputus() throws {
        XCTAssertEqual(Occasions.easter(2026), try day(2026, 4, 5))
        XCTAssertEqual(Occasions.easter(2027), try day(2027, 3, 28))
        XCTAssertEqual(Occasions.easter(2035), try day(2035, 3, 25))
        XCTAssertEqual(Occasions.easter(2000), try day(2000, 4, 23))
    }

    func testAWeekdayRuleAnOffsetAndATableFallWhereTheySay() throws {
        let thanksgiving = try XCTUnwrap(Occasions.byId("thanksgiving"))
        XCTAssertEqual(thanksgiving.rule.day(in: 2026), try day(2026, 11, 26))
        XCTAssertEqual(thanksgiving.rule(for: "CA").day(in: 2026), try day(2026, 10, 12))
        XCTAssertEqual(Occasions.byId("black-friday")?.rule.day(in: 2026), try day(2026, 11, 27))
        XCTAssertEqual(Occasions.byId("diwali")?.rule.day(in: 2026), try day(2026, 11, 8))
        // Beyond its table a moving feast has no day.
        XCTAssertNil(Occasions.byId("diwali")?.rule.day(in: 2036))
        let last = Occasions.Rule(rule: "weekday", month: 5, weekday: 1, nth: -1)
        XCTAssertEqual(last.day(in: 2026), try day(2026, 5, 25))
    }

    func testADayCountsAndNamesItsWeekday() throws {
        XCTAssertEqual(Day(ordinal: 0), try day(1970, 1, 1))
        XCTAssertEqual(try day(2026, 10, 25).weekday, 7)
        XCTAssertEqual(try day(2026, 10, 25).adding(days: 6), try day(2026, 10, 31))
        XCTAssertNil(Day(year: 2026, month: 4, day: 31))
        XCTAssertEqual(Day(ordinal: try day(2024, 2, 29).ordinal), try day(2024, 2, 29))
    }

    func testHomesRowSaysWhatIsComingUpAndWhen() throws {
        let up = Occasions.upcoming(try day(2026, 10, 25), region: "US")
        XCTAssertEqual(Occasions.comingUp(try XCTUnwrap(up.first)), "Coming up: Halloween · 6 days")
        let today = Occasions.upcoming(try day(2026, 10, 31), region: "US")
        XCTAssertEqual(Occasions.comingUp(try XCTUnwrap(today.first)), "Coming up: Halloween · Today")
    }

    func testFourteenOccasionsInSixTypesEachBaseWithAColourway() {
        let seasonal = ContentLibrary.templates.filter { $0.occasion != nil }
        XCTAssertEqual(seasonal.count, 168)
        XCTAssertEqual(seasonal.filter { $0.variantOf == nil }.count, 84)
        XCTAssertEqual(Set(Occasions.all.map(\.id)), Set(seasonal.compactMap(\.occasion)))
        for occasion in Occasions.all {
            XCTAssertEqual(seasonal.filter { $0.occasion == occasion.id && $0.variantOf == nil }.count, 6, occasion.id)
        }
        // The Occasion facet narrows to one occasion.
        let halloween = ContentLibrary.filteredTemplates(in: nil, matching: "", facets: TemplateFilter(occasion: "halloween"))
        XCTAssertEqual(halloween.count, 12)
        XCTAssertTrue(halloween.allSatisfy { $0.occasion == "halloween" })
        XCTAssertEqual(TemplateFilter(occasion: "halloween").chips.map(\.label), ["Halloween"])
        XCTAssertFalse(TemplateFilter(occasion: "halloween").isEmpty)
    }

    func testTheComingUpRowLeadsWithTheTypesThePhoneIsUsedForEachLayoutOnce() {
        let row = Occasions.templates("halloween", use: nil)
        XCTAssertEqual(row.count, 6)
        XCTAssertTrue(row.allSatisfy { $0.variantOf == nil && $0.occasion == "halloween" })
        let hero = Set(UseProfile.hero(nil).map { "\($0.w)x\($0.h)" })
        let leading = row.prefix { hero.contains("\($0.width)x\($0.height)") }
        XCTAssertFalse(leading.isEmpty)
        XCTAssertTrue(row.dropFirst(leading.count).allSatisfy { !hero.contains("\($0.width)x\($0.height)") })
    }

    /// The preference both phones keep the row's switch under.
    func testTheSeasonalSwitchIsKeptUnderTheSharedKey() {
        XCTAssertEqual(Occasions.seasonalKey, "homeSeasonal")
    }
}
