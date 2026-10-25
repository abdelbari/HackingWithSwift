// The export sheet's Share to row, the Android twin's ShareTargetsTest row
// for row: the apps and their ids, which show and in what order, what each
// is sent, and the recent ones kept under the shared key.

import XCTest
@testable import Canvia

final class ShareTargetsTests: XCTestCase {

    private let everyApp = Set(ShareTargets.all.map(\.id))

    func testTheAppsAndTheirIdsAreTheSharedTable() {
        XCTAssertEqual(ShareTargets.all.map(\.id), ["instagram", "tiktok", "whatsapp", "facebook", "pinterest", "linkedin"])
        XCTAssertEqual(ShareTargets.all.map(\.packageName),
                       ["com.instagram.android", "com.zhiliaoapp.musically", "com.whatsapp", "com.facebook.katana",
                        "com.pinterest", "com.linkedin.android"])
        XCTAssertEqual(ShareTargets.all.map(\.scheme), ["instagram", "tiktok", "whatsapp", "fb", "pinterest", "linkedin"])
        // Every scheme is one Info.plist lets canOpenURL ask about, and
        // every app's own type is in the catalogue.
        for target in ShareTargets.all {
            XCTAssertNotNil(target.url, target.id)
            if let id = target.sizeId { XCTAssertNotNil(SizePreset.byId(id), id) }
        }
    }

    func testTheRowShowsOnlyWhatIsInstalledTheTypesOwnAppFirstFiveAtMost() {
        XCTAssertEqual(ShareTargets.ordered(nil, installed: everyApp).map(\.id),
                       ["instagram", "tiktok", "whatsapp", "facebook", "pinterest"])
        XCTAssertEqual(ShareTargets.ordered("pinterest-pin", installed: everyApp).map(\.id),
                       ["pinterest", "instagram", "tiktok", "whatsapp", "facebook"])
        XCTAssertEqual(ShareTargets.ordered("insta-story", installed: ["whatsapp", "instagram"]).map(\.id),
                       ["instagram", "whatsapp"])
        XCTAssertEqual(ShareTargets.ordered("linkedin-post", installed: everyApp, recent: ["whatsapp", "tiktok"]).map(\.id),
                       ["linkedin", "whatsapp", "tiktok", "instagram", "facebook"])
        XCTAssertEqual(ShareTargets.ordered("insta-post", installed: []).map(\.id), [])
    }

    func testAMovingDesignGoesAsAVideoAStillAsItsPictureAtTheAppsWidth() throws {
        var still = Design(title: "Post", width: 540, height: 540)
        still.pages = [Page(elements: [Element.text("Hi")])]
        XCTAssertEqual(ShareTargets.format(still), "png")
        var moving = still
        moving.pages = [Page(elements: [Element.image("video:v1")])]
        XCTAssertEqual(ShareTargets.format(moving), "mp4")
        XCTAssertEqual(ShareTargets.scale(still, target: try XCTUnwrap(ShareTargets.byId("instagram"))), 2, accuracy: 1e-9)
        XCTAssertEqual(ShareTargets.scale(still, target: try XCTUnwrap(ShareTargets.byId("whatsapp"))), 1, accuracy: 1e-9)
    }

    func testACarouselIsSharedAsItsSlidesEachAtTheAppsWidth() throws {
        var wide = Design(title: "Carousel", width: 3240, height: 1350)
        wide.pages = [Page(elements: [Element.text("Hi")])]
        var carousel = wide
        carousel.pages[0].split = PageSplit(columns: 3)
        let instagram = try XCTUnwrap(ShareTargets.byId("instagram"))
        XCTAssertEqual(ShareTargets.scale(wide, target: instagram), 1080.0 / 3240.0, accuracy: 1e-9)
        XCTAssertEqual(ShareTargets.scale(carousel, target: instagram), 1, accuracy: 1e-9)
        XCTAssertEqual(ShareTargets.scale(carousel, target: try XCTUnwrap(ShareTargets.byId("whatsapp"))), 1, accuracy: 1e-9)
    }

    func testRecentTargetsAreKeptNewestFirstAsTheAndroidTwinKeepsThem() throws {
        let kept = ShareTargets.remembered(ShareTargets.remembered([], id: "tiktok"), id: "instagram")
        XCTAssertEqual(kept, ["instagram", "tiktok"])
        XCTAssertEqual(ShareTargets.encode(kept), #"["instagram","tiktok"]"#)
        XCTAssertEqual(ShareTargets.decode(ShareTargets.encode(kept)), kept)
        XCTAssertEqual(ShareTargets.remembered(kept, id: "tiktok"), ["tiktok", "instagram"])
        XCTAssertEqual(ShareTargets.decode(#"["whatsapp","myspace",3,"whatsapp"]"#), ["whatsapp"])
        let many = (1...10).reduce([String]()) { acc, i in ShareTargets.remembered(acc, id: ShareTargets.all[i % 6].id) }
        XCTAssertEqual(many.count, 6)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ShareTargetsTests"))
        defaults.removePersistentDomain(forName: "ShareTargetsTests")
        ShareTargets.remember("whatsapp", defaults)
        XCTAssertEqual(defaults.string(forKey: "shareTargets"), #"["whatsapp"]"#)
        XCTAssertEqual(ShareTargets.recent(defaults), ["whatsapp"])
    }

    func testWhatIsSaid() throws {
        let instagram = try XCTUnwrap(ShareTargets.byId("instagram"))
        XCTAssertEqual(ShareTargets.notInstalled(instagram), "Instagram isn't installed on this phone")
        XCTAssertEqual(ShareTargets.shareTo(instagram), "Share to Instagram")
    }
}
