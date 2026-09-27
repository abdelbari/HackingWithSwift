// The shelf: when each design was last touched, in the Android twin's words.

import XCTest
@testable import Canvia

final class HomeShelfTests: XCTestCase {

    private let gmt: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT") ?? .current
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) throws -> Date {
        try XCTUnwrap(gmt.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)))
    }

    private func said(_ then: Date, at now: Date) -> String {
        RelativeTime.text(ms: then.timeIntervalSince1970 * 1000, now: now, calendar: gmt,
                          locale: Locale(identifier: "en_US_POSIX"))
    }

    func testTheTimeReadsAsThePhoneReadsIt() throws {
        let now = try date(2026, 3, 15, 12)
        XCTAssertEqual(said(now.addingTimeInterval(90), at: now), "Just now", "a clock that runs ahead")
        XCTAssertEqual(said(now.addingTimeInterval(-30), at: now), "Just now")
        XCTAssertEqual(said(now.addingTimeInterval(-60), at: now), "1 minute ago")
        XCTAssertEqual(said(now.addingTimeInterval(-59 * 60), at: now), "59 minutes ago")
        XCTAssertEqual(said(try date(2026, 3, 15, 11), at: now), "1 hour ago")
        XCTAssertEqual(said(try date(2026, 3, 15, 0, 5), at: now), "11 hours ago")
        XCTAssertEqual(said(try date(2026, 3, 14, 23), at: now), "Yesterday")
        XCTAssertEqual(said(try date(2026, 3, 14, 1), at: now), "Yesterday")
        XCTAssertEqual(said(try date(2026, 3, 10, 12), at: now), "5 days ago")
        XCTAssertEqual(said(try date(2026, 3, 5, 9), at: now), "5 Mar")
        XCTAssertEqual(said(try date(2025, 9, 8, 9), at: now), "8 Sep 2025")
    }

    /// Minutes before midnight are still minutes; two calendar days back is
    /// never "1 days ago".
    func testTheEdgesOfADay() throws {
        let justAfterMidnight = try date(2026, 3, 18, 0, 10)
        XCTAssertEqual(said(try date(2026, 3, 17, 23, 50), at: justAfterMidnight), "20 minutes ago")
        let early = try date(2026, 3, 18, 1)
        XCTAssertEqual(said(try date(2026, 3, 16, 23), at: early), "2 days ago")
    }

    /// On until turned off, as the Android twin's switch starts.
    func testVibrationIsOnUntilTurnedOff() throws {
        let name = "haptics-\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertTrue(Haptics.isOn(defaults))
        defaults.set(false, forKey: Haptics.key)
        XCTAssertFalse(Haptics.isOn(defaults))
        defaults.set(true, forKey: Haptics.key)
        XCTAssertTrue(Haptics.isOn(defaults))
    }

    // MARK: quick actions

    private func recent(_ id: String, _ title: String, at: Double) -> RecentDesign {
        RecentDesign(id: id, title: title, width: 1080, height: 1080, pages: 1, updatedAt: at)
    }

    /// New post, New story, then the two most recently touched designs.
    func testQuickActionsStartOrPickUp() {
        let items = QuickActions.items(recents: [recent("a", "Old", at: 1), recent("b", "  ", at: 3),
                                                 recent("c", "Newest", at: 5)])
        XCTAssertEqual(items.map(\.title), ["New post", "New story", "Newest", "Untitled design"])
        XCTAssertEqual(items.map(\.type), [QuickActions.newType, QuickActions.newType,
                                           QuickActions.openType, QuickActions.openType])
        XCTAssertEqual(items[1].info[QuickActions.presetKey], "insta-story")
        XCTAssertEqual(items[2].info[QuickActions.designKey], "c")
        XCTAssertEqual(QuickActions.items(recents: []).count, 2)
    }

    /// A new design at the size, named after it; an open for a safe id only;
    /// nothing for an action this app does not know.
    func testAQuickActionBecomesALaunchRequest() throws {
        XCTAssertEqual(QuickActions.request(type: QuickActions.newType, info: [QuickActions.presetKey: "insta-story"]),
                       .newDesign(width: 1080, height: 1920, title: "Instagram Story"))
        XCTAssertEqual(QuickActions.request(type: QuickActions.newType, info: [:]),
                       .newDesign(width: 1080, height: 1080, title: "Instagram Post"))
        let first = try XCTUnwrap(SizePreset.all.first)
        XCTAssertEqual(QuickActions.request(type: QuickActions.newType, info: [QuickActions.presetKey: "billboard"]),
                       .newDesign(width: first.w, height: first.h, title: first.name))
        XCTAssertEqual(QuickActions.request(type: QuickActions.openType, info: [QuickActions.designKey: "doc_ab-12"]),
                       .open(id: "doc_ab-12"))
        XCTAssertNil(QuickActions.request(type: QuickActions.openType, info: [QuickActions.designKey: "../secrets"]))
        XCTAssertNil(QuickActions.request(type: QuickActions.openType, info: [:]))
        XCTAssertNil(QuickActions.request(type: "app.canvia.dance", info: [:]))
        XCTAssertFalse(QuickActions.isSafeId("é"))
        XCTAssertFalse(QuickActions.isSafeId(""))
    }

    func testPagesAndMidSentence() {
        XCTAssertEqual(RelativeTime.pages(1), "1 page")
        XCTAssertEqual(RelativeTime.pages(4), "4 pages")
        XCTAssertEqual(RelativeTime.lowercasedFirst("Yesterday"), "yesterday")
        XCTAssertEqual(RelativeTime.lowercasedFirst("5 Mar"), "5 Mar")
    }
}
