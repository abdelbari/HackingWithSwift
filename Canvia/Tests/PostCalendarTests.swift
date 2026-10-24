// The Planned calendar's arithmetic (PostPlanner.month and its helpers): the
// Android twin's PostCalendarTest, row for row.

import XCTest
@testable import Canvia

final class PostCalendarTests: XCTestCase {

    private func planned(_ id: String, _ at: String, done: Bool = false) -> PostPlanner.Planned {
        PostPlanner.Planned(designId: "d", title: "Design", post: PlannedPost(id: id, at: at, done: done))
    }

    private func zone(_ id: String) throws -> TimeZone { try XCTUnwrap(TimeZone(identifier: id)) }

    /// Shared: which day each post lands on, in the zone it is seen in.
    func testPostsFallOnTheDayOfTheirZoneSoonestFirstEveryDayABucket() throws {
        let posts = [
            planned("b", "2026-11-02T18:00:00Z"),
            planned("a", "2026-11-02T09:30:00Z"),
            planned("c", "2026-11-30T23:30:00Z"),
            planned("x", "2026-12-01T00:30:00Z"),
            planned("y", "2026-10-31T23:59:59Z", done: true),
        ]
        let utc = PostPlanner.month(posts, year: 2026, month: 11, zone: try zone("UTC"))
        XCTAssertEqual(utc.count, 30)
        XCTAssertEqual(utc.map(\.day), Array(1...30))
        XCTAssertEqual(utc[1].posts.map(\.post.id), ["a", "b"])
        XCTAssertEqual(utc[29].posts.map(\.post.id), ["c"])
        XCTAssertEqual(utc.reduce(0) { $0 + $1.posts.count }, 3)
        // An hour east, the last of November is December's, and the
        // October one is November's first.
        let paris = PostPlanner.month(posts, year: 2026, month: 11, zone: try zone("Europe/Paris"))
        XCTAssertEqual(paris[0].posts.map(\.post.id), ["y"])
        XCTAssertEqual(paris[29].posts.map(\.post.id), [])
        // February of a leap year.
        XCTAssertEqual(PostPlanner.month([], year: 2028, month: 2, zone: try zone("UTC")).count, 29)
    }

    /// Shared: blanks before the 1st by the first day of the week (1 is
    /// Sunday, 2 Monday, 7 Saturday).
    func testTheGridStartsOnTheLocalesFirstWeekday() {
        // 1 November 2026 is a Sunday.
        XCTAssertEqual(PostPlanner.leadingBlanks(year: 2026, month: 11, firstWeekday: 1), 0)
        XCTAssertEqual(PostPlanner.leadingBlanks(year: 2026, month: 11, firstWeekday: 2), 6)
        XCTAssertEqual(PostPlanner.leadingBlanks(year: 2026, month: 11, firstWeekday: 7), 1)
        // 1 December 2026 is a Tuesday.
        XCTAssertEqual(PostPlanner.leadingBlanks(year: 2026, month: 12, firstWeekday: 2), 1)
    }

    /// Shared: a move keeps the time of day; a new one starts at 9:00.
    func testMovingKeepsTheTimeAndADaysNewPostIsAtNine() throws {
        let newYork = try zone("America/New_York")
        let post = PlannedPost(id: "p", at: "2026-11-02T14:30:00Z")
        // 9:30 in New York on the 2nd, moved across the clocks going back.
        XCTAssertEqual(PostPlanner.movedTo(post, year: 2026, month: 10, day: 30, zone: newYork).at, "2026-10-30T13:30:00Z")
        XCTAssertEqual(PostPlanner.movedTo(post, year: 2026, month: 11, day: 9, zone: newYork).at, "2026-11-09T14:30:00Z")
        XCTAssertEqual(PostPlanner.morningOf(year: 2026, month: 11, day: 5, zone: newYork), "2026-11-05T14:00:00Z")
        XCTAssertEqual(PostPlanner.morningOf(year: 2026, month: 11, day: 5, zone: try zone("UTC")), "2026-11-05T09:00:00Z")
        let bad = PlannedPost(id: "q", at: "soon")
        XCTAssertEqual(PostPlanner.movedTo(bad, year: 2026, month: 11, day: 9, zone: newYork), bad)
    }

    func testOverdueIsAPostNotDoneWhoseTimeHasGone() throws {
        let now = try XCTUnwrap(PostPlanner.date("2026-11-02T12:00:00Z"))
        XCTAssertTrue(PostPlanner.overdue(PlannedPost(id: "p", at: "2026-11-02T11:00:00Z"), now: now))
        XCTAssertFalse(PostPlanner.overdue(PlannedPost(id: "p", at: "2026-11-02T11:00:00Z", done: true), now: now))
        XCTAssertFalse(PostPlanner.overdue(PlannedPost(id: "p", at: "2026-11-02T13:00:00Z"), now: now))
    }

    /// Every post, done ones too, soonest first, for the calendar and list.
    func testAllListsEveryPostSoonestFirst() {
        var design = Design(width: 1080, height: 1080)
        design = PostPlanner.saved(design, PlannedPost(id: "late", at: "2026-11-09T09:00:00Z"))
        design = PostPlanner.saved(design, PlannedPost(id: "early", at: "2026-11-02T09:00:00Z", done: true))
        XCTAssertEqual(PostPlanner.all([design]).map(\.post.id), ["early", "late"])
        XCTAssertEqual(PostPlanner.upcoming([design]).map(\.post.id), ["late"])
    }
}
