// Plan a post (PostPlanner) and Settings ▸ Accessibility
// (AccessibilityPrefs), over the Android twin's PostPlannerTest rows.

import XCTest
@testable import Canvia

final class PostPlannerTests: XCTestCase {

    private func design() -> Design {
        var d = Design(title: "Launch")
        d.id = "d1"
        d.pages = [Page(), Page(), Page()]
        d.pages[0].id = "p1"
        d.pages[1].id = "p2"
        d.pages[2].id = "p3"
        return d
    }

    /// Shared: the JSON both phones write, every key.
    func testPlannedPostsAreWrittenInTheSharedShape() throws {
        let post = PlannedPost(id: "post_1", at: "2026-11-02T09:30:00Z", caption: "New #launch", format: "png", pages: ["p2"])
        let planned = PostPlanner.saved(design(), post)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(planned)) as? [String: Any])
        let posts = try XCTUnwrap(json["plannedPosts"] as? [[String: Any]])
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(Set(posts[0].keys), ["id", "at", "caption", "format", "pages", "done"])
        XCTAssertEqual(posts[0]["at"] as? String, "2026-11-02T09:30:00Z")
        XCTAssertEqual(posts[0]["pages"] as? [String], ["p2"])
        XCTAssertEqual(posts[0]["done"] as? Bool, false)
        // Through the design file and back, as a backup carries it.
        let round = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(planned))
        XCTAssertEqual(PostPlanner.of(round), [post])
        // None: no key at all.
        let none = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(PostPlanner.removed(planned, id: "post_1"))) as? [String: Any])
        XCTAssertNil(none["plannedPosts"])
    }

    /// The Android twin's file reads here.
    func testTheTwinsPostsRead() throws {
        let text = #"{"id":"d1","title":"Launch","pages":[{"id":"p1"}],"plannedPosts":[{"id":"post_1","at":"2026-11-02T09:30:00Z","caption":"New #launch","format":"png","pages":["p2"],"done":false}]}"#
        let d = try JSONDecoder().decode(Design.self, from: Data(text.utf8))
        XCTAssertEqual(PostPlanner.of(d), [PlannedPost(id: "post_1", at: "2026-11-02T09:30:00Z", caption: "New #launch",
                                                       format: "png", pages: ["p2"])])
    }

    func testPostsAreKeptSoonestFirstReplacedByIdMarkedDone() {
        let later = PlannedPost(id: "b", at: "2026-12-01T08:00:00Z")
        let sooner = PlannedPost(id: "a", at: "2026-11-01T08:00:00Z")
        var d = PostPlanner.saved(PostPlanner.saved(design(), later), sooner)
        XCTAssertEqual(PostPlanner.of(d).map(\.id), ["a", "b"])
        var edited = sooner
        edited.caption = "Edited"
        d = PostPlanner.saved(d, edited)
        XCTAssertEqual(PostPlanner.of(d).count, 2)
        XCTAssertEqual(PostPlanner.of(d).first?.caption, "Edited")
        d = PostPlanner.markedDone(d, id: "a")
        XCTAssertEqual(PostPlanner.of(d).first?.done, true)
        var other = Design(title: "Other")
        other.id = "d2"
        other = PostPlanner.saved(other, PlannedPost(id: "c", at: "2026-11-15T08:00:00Z"))
        XCTAssertEqual(PostPlanner.upcoming([d, other]).map { $0.designId + ":" + $0.post.id }, ["d2:c", "d1:b"])
    }

    func testAnEntryThatDoesNotReadIsLeftOutAFormatItCannotMakeIsPng() throws {
        let text = #"{"id":"d1","pages":[{"id":"p1"}],"plannedPosts":[{"id":"x","at":"tomorrow"},{"at":"2026-11-02T09:30:00Z"},{"id":"y","at":"2026-11-02T09:30:00Z","format":"tiff","done":"yes"}]}"#
        let posts = PostPlanner.of(try JSONDecoder().decode(Design.self, from: Data(text.utf8)))
        XCTAssertEqual(posts.map(\.id), ["y"])
        XCTAssertEqual(posts.first?.format, "png")
        XCTAssertEqual(posts.first?.done, false)
    }

    func testTheCaptionLimitIsXsForAnXTypeElse2200() throws {
        let x = try XCTUnwrap(ContentLibrary.sizes.first { $0.id == "x-post" })
        let insta = try XCTUnwrap(ContentLibrary.sizes.first { $0.id == "insta-post" })
        XCTAssertEqual(PostPlanner.captionLimit(Design(width: x.w, height: x.h)), 280)
        XCTAssertEqual(PostPlanner.captionLimit(Design(width: insta.w, height: insta.h)), 2200)
        XCTAssertEqual(PostPlanner.captionLimit(Design(width: 777, height: 333)), 2200)
        XCTAssertEqual(PostPlanner.counter("Hi!", limit: 280), "3 / 280")
        XCTAssertTrue(PostPlanner.isTooLong(String(repeating: "a", count: 281), limit: 280))
    }

    func testThePagesAreThoseChosenElseEveryShownPage() {
        var hidden = design()
        hidden.pages[1].hidden = true
        XCTAssertEqual(PostPlanner.pageIndices(hidden, PlannedPost(id: "a", at: "2026-11-02T09:30:00Z")), [0, 2])
        XCTAssertEqual(PostPlanner.pageIndices(hidden, PlannedPost(id: "a", at: "2026-11-02T09:30:00Z", pages: ["p2", "gone"])), [1])
        XCTAssertEqual(PostPlanner.pageIndices(hidden, PlannedPost(id: "a", at: "2026-11-02T09:30:00Z", pages: ["gone"])), [0, 2])
        let instant = try? XCTUnwrap(PostPlanner.date("2026-11-02T09:30:00.750Z"))
        XCTAssertEqual(instant.map(PostPlanner.iso), "2026-11-02T09:30:00Z")
        XCTAssertEqual(PostPlanner.defaultFormat(design()), "png")
        XCTAssertTrue(PostPlanner.newId().hasPrefix("post_"))
        XCTAssertEqual(PostPlanner.newId().count, 17)
    }

    // MARK: Settings ▸ Accessibility

    /// Shared: the settings' keys and what each reads as.
    func testAccessibilitySettingsTravelInABackupUnderTheirKeys() throws {
        let all = AccessibilityPrefs.Settings(reduceMotion: "on", autoplayClips: false, altTextPrompt: true,
                                              underlineLinks: true, largerHandles: true)
        let data = Backup.encodeSettings(autoLists: true, use: nil, accessibility: all)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["a11yReduceMotion"] as? String, "on")
        XCTAssertEqual(object["a11yAutoplayClips"] as? Bool, false)
        XCTAssertEqual(object["a11yAltTextPrompt"] as? Bool, true)
        XCTAssertEqual(object["a11yUnderlineLinks"] as? Bool, true)
        XCTAssertEqual(object["a11yLargerHandles"] as? Bool, true)
        XCTAssertEqual(AccessibilityPrefs.decodeSettings(data), all)
        XCTAssertEqual(Backup.decodeSettings(data), true)
        // As the twin writes it, alone.
        let twin = #"{"a11yReduceMotion":"on","a11yAutoplayClips":false,"a11yAltTextPrompt":true,"a11yUnderlineLinks":true,"a11yLargerHandles":true}"#
        XCTAssertEqual(AccessibilityPrefs.decodeSettings(Data(twin.utf8)), all)
        // A choice it does not know, or a flag in words or a number, is none.
        let odd = #"{"a11yReduceMotion":"sometimes","a11yLargerHandles":"yes","a11yUnderlineLinks":1}"#
        XCTAssertEqual(AccessibilityPrefs.decodeSettings(Data(odd.utf8)), AccessibilityPrefs.Settings())
        // None given: none written.
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: Backup.encodeSettings(autoLists: true, use: nil))
            as? [String: Any])
        XCTAssertNil(plain["a11yReduceMotion"])
    }

    func testSettingsAreKeptOnThePhoneAndReadBack() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PostPlannerTests"))
        defaults.removePersistentDomain(forName: "PostPlannerTests")
        XCTAssertEqual(AccessibilityPrefs.current(defaults),
                       AccessibilityPrefs.Settings(reduceMotion: "system", autoplayClips: true, altTextPrompt: false,
                                                   underlineLinks: false, largerHandles: false))
        AccessibilityPrefs.apply(AccessibilityPrefs.Settings(reduceMotion: "off", largerHandles: true), to: defaults)
        XCTAssertEqual(AccessibilityPrefs.current(defaults).reduceMotion, "off")
        XCTAssertEqual(AccessibilityPrefs.current(defaults).largerHandles, true)
        XCTAssertEqual(AccessibilityPrefs.current(defaults).autoplayClips, true)
        defaults.removePersistentDomain(forName: "PostPlannerTests")
    }

    func testReduceMotionFollowsThePhoneUnlessSetAndHandlesGrowBy1_4() {
        XCTAssertTrue(AccessibilityPrefs.reducesMotion("system", systemReduces: true))
        XCTAssertFalse(AccessibilityPrefs.reducesMotion(nil, systemReduces: false))
        XCTAssertTrue(AccessibilityPrefs.reducesMotion("on", systemReduces: false))
        XCTAssertFalse(AccessibilityPrefs.reducesMotion("off", systemReduces: true))
        XCTAssertEqual(AccessibilityPrefs.reduceMotionOf("loud"), "system")
        XCTAssertEqual(AccessibilityPrefs.handleScale(larger: true), 1.4)
        XCTAssertEqual(AccessibilityPrefs.handleScale(larger: false), 1)
        XCTAssertTrue(AccessibilityPrefs.prompts(Element.image("media:a")))
        XCTAssertFalse(AccessibilityPrefs.prompts(Element.text("Hi")))
        var graphic = Element.shape("rect")
        graphic.graphicId = "g1"
        XCTAssertTrue(AccessibilityPrefs.prompts(graphic))
    }
}
