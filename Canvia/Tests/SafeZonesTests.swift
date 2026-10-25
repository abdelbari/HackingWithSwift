// Platform safe zones (SafeZones): the zones of SafeZones.json, the shared
// rows of safe-zones.json — which zone a page shows, its inner edges, which
// text boxes are under the app's buttons and where Move inside puts them —
// the design's `safeZone` key, the snap lines named "Safe zone" and Check
// accessibility's safeZone rule. The Android twin's SafeZonesTest, row for
// row.

import XCTest
import CoreGraphics
@testable import Canvia

final class SafeZonesTests: XCTestCase {

    private func box(_ value: Any?) -> CGRect {
        let n = (value as? [Double]) ?? []
        return n.count == 4 ? CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) : .null
    }

    private func story(_ elements: [Element] = [], safeZone: String? = nil) -> Design {
        var d = Design(title: "Story", width: 1080, height: 1920)
        d.pages = [Page(elements: elements)]
        d.safeZone = safeZone
        return d
    }

    func testTheFileHasTheSixZonesInOrder() {
        XCTAssertEqual(SafeZones.all.map(\.id),
                       ["instagram-story", "instagram-reel", "tiktok", "youtube-short", "facebook-story", "whatsapp-status"])
        let tiktok = SafeZones.zone(id: "tiktok")
        XCTAssertEqual(tiktok?.label, "TikTok")
        XCTAssertEqual(tiktok?.insets, SafeZones.ZoneInsets(top: 0.1, bottom: 0.2, left: 0, right: 0.12))
        XCTAssertTrue(SafeZones.all.allSatisfy { $0.fits(CGSize(width: 1080, height: 1920)) })
    }

    func testTheSharedSafeZoneRows() throws {
        let root = try SharedFixture.object("safe-zones")
        let size = CGSize(width: 1080, height: 1920)
        XCTAssertEqual(SafeZones.matching(size).map(\.id), root["matching"] as? [String])
        for row in try XCTUnwrap(root["shown"] as? [[String: Any]]) {
            let sides = try XCTUnwrap(row["size"] as? [Double])
            var d = Design(title: "Zone", width: sides[0], height: sides[1])
            d.safeZone = row["safeZone"] as? String
            XCTAssertEqual(SafeZones.shown(d, page: d.pages[0])?.id, row["shown"] as? String, "\(row)")
        }
        for row in try XCTUnwrap(root["edges"] as? [[String: Any]]) {
            let id = try XCTUnwrap(row["zone"] as? String)
            let zone = try XCTUnwrap(SafeZones.zone(id: id))
            let made = SafeZones.edges(zone, size: size)
            let xs = (row["x"] as? [Double]) ?? [], ys = (row["y"] as? [Double]) ?? []
            XCTAssertEqual(made.x.count, xs.count, id)
            XCTAssertEqual(made.y.count, ys.count, id)
            for (a, b) in zip(made.x, xs) { XCTAssertEqual(a, b, accuracy: 1e-6, id) }
            for (a, b) in zip(made.y, ys) { XCTAssertEqual(a, b, accuracy: 1e-6, id) }
        }
        for row in try XCTUnwrap(root["rows"] as? [[String: Any]]) {
            let zone = try XCTUnwrap(SafeZones.zone(id: row["zone"] as? String))
            let start = box(row["box"])
            XCTAssertEqual(SafeZones.isUnder(start, zone: zone, size: size), row["under"] as? Bool, "\(row)")
            let moved = SafeZones.movedInside(start, zone: zone, size: size)
            let expected = try XCTUnwrap(row["moved"] as? [Double])
            XCTAssertEqual(Double(moved.minX), expected[0], accuracy: 1e-6, "\(row)")
            XCTAssertEqual(Double(moved.minY), expected[1], accuracy: 1e-6, "\(row)")
            XCTAssertFalse(SafeZones.isUnder(moved, zone: zone, size: size), "moved, it is clear: \(row)")
        }
    }

    func testTheKeyIsWrittenOnlyWhenSetAndReadBack() throws {
        let plain = String(decoding: try JSONEncoder().encode(story()), as: UTF8.self)
        XCTAssertFalse(plain.contains("safeZone"))
        let off = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(story(safeZone: "none")))
        XCTAssertEqual(off.safeZone, SafeZones.off)
        XCTAssertNil(SafeZones.shown(off, page: off.pages[0]))
    }

    func testTheZoneEdgesSnapAndAreNamed() {
        let d = story(safeZone: "tiktok")
        let lines = Geometry.taggedSnapLines(design: d, page: d.pages[0], excluding: [])
        XCTAssertEqual(Geometry.snapSource(at: 1536, in: lines.y), .safeZone)
        XCTAssertTrue(lines.x.contains { $0.source == .safeZone && abs($0.position - 950.4) < 1e-6 })
        XCTAssertEqual(ElementNames.guideLabel(.safeZone, vertical: false, elements: []), "Safe zone")
        let off = story(safeZone: "none")
        let none = Geometry.taggedSnapLines(design: off, page: off.pages[0], excluding: [])
        XCTAssertFalse((none.x + none.y).contains { $0.source == .safeZone })
    }

    func testTextUnderTheButtonsIsFoundAndMovedInside() {
        var caption = Element.text("Follow for more", w: 400)
        caption.x = 100
        caption.y = 1600
        caption.h = 100
        var middle = Element.text("Sale", w: 400)
        middle.x = 100
        middle.y = 800
        middle.h = 100
        let d = story([caption, middle], safeZone: "tiktok")
        let found = AccessibilityAudit.findings(d).filter { $0.kind == .safeZone }
        XCTAssertEqual(found.map(\.elementId), [caption.id])
        XCTAssertEqual(found.first?.message, "Text sits under the app's buttons")
        XCTAssertEqual(found.first?.fix, .moveInside)
        let fixed = AccessibilityAudit.fixed(d, found[0])
        XCTAssertEqual(fixed.pages[0].elements[0].y, 1436, accuracy: 1e-6)
        XCTAssertTrue(AccessibilityAudit.findings(fixed).filter { $0.kind == .safeZone }.isEmpty)
        // A shape's words count, as on the Android twin; words all but
        // invisible (opacity 0.05 or less) and a shape with none do not.
        var tag = Element.shape("rect")
        tag.text = "Tap"
        tag.x = 100
        tag.y = 1700
        var bare = Element.shape("rect")
        bare.x = 400
        bare.y = 1700
        var faint = caption
        faint.id = "faint"
        faint.opacity = 0.05
        let more = story([caption, tag, bare, faint], safeZone: "tiktok")
        XCTAssertEqual(AccessibilityAudit.findings(more).filter { $0.kind == .safeZone }.map(\.elementId),
                       [caption.id, tag.id])
        // Off, or a square page, has nothing to say.
        XCTAssertTrue(AccessibilityAudit.findings(story([caption], safeZone: "none")).filter { $0.kind == .safeZone }.isEmpty)
    }
}
