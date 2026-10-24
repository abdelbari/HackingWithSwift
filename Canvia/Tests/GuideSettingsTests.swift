// Round 33's Show guides and Lock guides: the design's "guidesHidden" and
// "guidesLocked", written only when true and read as false when absent —
// the Android twin's rows — hit-testing that passes over hidden or locked
// guides, snapping that passes over hidden ones, one undo step each, and
// a guide added showing them again.

import XCTest
import CoreGraphics
@testable import Canvia

@MainActor
final class GuideSettingsTests: XCTestCase {

    private func json(_ design: Design) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(design)) as? [String: Any])
    }

    private func design() -> Design {
        var d = Design(title: "guides", width: 1000, height: 800)
        d.guides = [Guide(vertical: true, position: 300), Guide(vertical: false, position: 200)]
        return d
    }

    func testTheKeysAreWrittenOnlyWhenTrueAndRoundTrip() throws {
        var d = design()
        XCTAssertNil(try json(d)["guidesHidden"])
        XCTAssertNil(try json(d)["guidesLocked"])
        d.guidesHidden = true
        d.guidesLocked = true
        XCTAssertEqual(try json(d)["guidesHidden"] as? Bool, true)
        XCTAssertEqual(try json(d)["guidesLocked"] as? Bool, true)
        let again = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(again, d)
        // As the twin writes them; false, or anything else, is none.
        let read = { (text: String) in try JSONDecoder().decode(Design.self, from: Data(text.utf8)) }
        let on = try read(#"{"id":"d","guides":[],"guidesHidden":true,"guidesLocked":true}"#)
        XCTAssertEqual(on.guidesHidden, true)
        XCTAssertEqual(on.guidesLocked, true)
        let off = try read(#"{"id":"d","guidesHidden":false,"guidesLocked":"yes"}"#)
        XCTAssertNil(off.guidesHidden)
        XCTAssertNil(off.guidesLocked)
    }

    func testHitTestingSkipsHiddenOrLockedGuides() {
        var d = design()
        let near = CGPoint(x: 305, y: 600)
        XCTAssertEqual(Guides.grabbed(d, at: near, reach: 12)?.position, 300)
        XCTAssertNil(Guides.grabbed(d, at: CGPoint(x: 330, y: 600), reach: 12), "out of reach")
        d.guidesLocked = true
        XCTAssertNil(Guides.grabbed(d, at: near, reach: 12), "a locked guide lets the touch through")
        XCTAssertEqual(Guides.shown(d).count, 2, "but is drawn")
        d.guidesLocked = nil
        d.guidesHidden = true
        XCTAssertNil(Guides.grabbed(d, at: near, reach: 12))
        XCTAssertTrue(Guides.shown(d).isEmpty, "a hidden guide is not drawn")
    }

    func testHiddenGuidesDoNotSnapButLockedOnesDo() {
        var d = design()
        let page = d.pages[0]
        let off = SnapSettings(toPage: false, toElements: false)
        func guideLines(_ design: Design) -> [Double] {
            Geometry.taggedSnapLines(design: design, page: page, excluding: [], settings: off).x
                .filter { $0.source == .guide }.map(\.position)
        }
        XCTAssertEqual(guideLines(d), [300])
        d.guidesLocked = true
        XCTAssertEqual(guideLines(d), [300])
        d.guidesHidden = true
        XCTAssertEqual(guideLines(d), [])
    }

    func testEachSwitchIsOneEditStepAndAddingShowsThemAgain() {
        let s = DesignStore(design: design())
        s.setGuidesShown(false)
        XCTAssertEqual(s.design.guidesHidden, true)
        XCTAssertEqual(s.undoLabel, "Edit")
        s.setGuidesLocked(true)
        XCTAssertEqual(s.design.guidesLocked, true)
        XCTAssertEqual(s.undoLabel, "Edit")
        s.addGuide(vertical: true, at: 500)
        XCTAssertNil(s.design.guidesHidden, "adding a guide shows them again")
        XCTAssertEqual(s.design.guides.count, 3)
        s.undo()
        XCTAssertEqual(s.design.guidesHidden, true)
        s.undo()
        XCTAssertNil(s.design.guidesLocked)
        s.undo()
        XCTAssertNil(s.design.guidesHidden)
        XCTAssertFalse(s.canUndo)
    }

    func testALockedGuideIsRefusedWithUnlock() {
        let s = DesignStore(design: design())
        XCTAssertFalse(s.refusesLockedGuides())
        s.setGuidesLocked(true)
        XCTAssertTrue(s.refusesLockedGuides())
        XCTAssertEqual(s.haptic.kind, .reject)
        XCTAssertTrue(s.announcementUnlocksGuides)
        XCTAssertEqual(s.announcement, "Guides are locked")
    }
}
