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

    func testTheFileHasTheFiveZonesInOrder() {
        XCTAssertEqual(SafeZones.all.map(\.id),
                       ["instagram-story", "instagram-reel", "tiktok", "youtube-short", "facebook-story"])
        let tiktok = SafeZones.zone(id: "tiktok")
        XCTAssertEqual(tiktok?.label, "TikTok")
        XCTAssertEqual(tiktok?.insets, SafeZones.ZoneInsets(top: 0.1, bottom: 0.2, left: 0, right: 0.12))
        XCTAssertTrue(SafeZones.all.allSatisfy { $0.fits(CGSize(width: 1080, height: 1920)) })
    }

    func testTheSharedSafeZoneRows() throws {
        let root = try SharedFixture.object("safe-zones")
        let size = CGSize(width: 1080, height: 1920)
        for row in try XCTUnwrap(root["shown"] as? [[String: Any]]) {
            let sides = try XCTUnwrap(row["size"] as? [Double])
            var d = Design(title: "Zone", width: sides[0], height: sides[1])
            d.safeZone = row["safeZone"] as? String
            XCTAssertEqual(SafeZones.shown(d, page: d.pages[0])?.id, row["shown"] as? String, "\(row)")
        }
        let edges = try XCTUnwrap(root["edges"] as? [String: [String: [Double]]])
        for (id, expected) in edges {
            let zone = try XCTUnwrap(SafeZones.zone(id: id))
            let made = SafeZones.edges(zone, size: size)
            XCTAssertEqual(made.x.count, expected["x"]?.count, id)
            XCTAssertEqual(made.y.count, expected["y"]?.count, id)
            for (a, b) in zip(made.x, expected["x"] ?? []) { XCTAssertEqual(a, b, accuracy: 1e-6, id) }
            for (a, b) in zip(made.y, expected["y"] ?? []) { XCTAssertEqual(a, b, accuracy: 1e-6, id) }
        }
        for row in try XCTUnwrap(root["rows"] as? [[String: Any]]) {
            let zone = try XCTUnwrap(SafeZones.zone(id: row["zone"] as? String))
            XCTAssertEqual(SafeZones.isUnder(box(row["box"]), zone: zone, size: size), row["under"] as? Bool, "\(row)")
        }
        for row in try XCTUnwrap(root["moveInside"] as? [[String: Any]]) {
            let zone = try XCTUnwrap(SafeZones.zone(id: row["zone"] as? String))
            let moved = SafeZones.movedInside(box(row["box"]), zone: zone, size: size)
            let expected = box(row["moved"])
            XCTAssertEqual(moved.minX, expected.minX, accuracy: 1e-6, "\(row)")
            XCTAssertEqual(moved.minY, expected.minY, accuracy: 1e-6, "\(row)")
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
        // Off, or a square page, has nothing to say.
        XCTAssertTrue(AccessibilityAudit.findings(story([caption], safeZone: "none")).filter { $0.kind == .safeZone }.isEmpty)
    }
}
