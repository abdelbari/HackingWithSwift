// The mockup scenes and where a page goes in one — MockupGeometry's rows
// are the Android twin's MockupsTest's.

import XCTest
@testable import Canvia

final class MockupGeometryTests: XCTestCase {

    func testTheScenesAreTheSharedFileAboutTwentyInFourCategories() {
        XCTAssertEqual(MockupScenes.all.count, 21)
        XCTAssertEqual(Set(MockupScenes.all.map(\.id)).count, MockupScenes.all.count)
        XCTAssertEqual(Set(MockupScenes.all.map(\.category)), Set(MockupScenes.categories))
        for s in MockupScenes.all {
            XCTAssertEqual(s.screen.corners.count, 4, s.id)
            XCTAssertTrue(s.screen.aspect > 0 && s.width > 0 && s.height > 0, s.id)
            XCTAssertTrue(s.screen.corners.allSatisfy { p in
                (0...s.width).contains(Double(p.x)) && (0...s.height).contains(Double(p.y))
            }, s.id)
            XCTAssertTrue(s.layers.allSatisfy { !SVGPath.parse($0.path).isEmpty }, s.id)
            // A scene with tinted layers says what colour they start in.
            if s.layers.contains(where: { $0.tinted == true }) { XCTAssertNotNil(s.tint, s.id) }
        }
        XCTAssertEqual(MockupScenes.scene("phone-tilt")?.name, "Phone, tilted")
        XCTAssertEqual(MockupScenes.scene("mug")?.screen.cylinder?.angle, 1.05)
        XCTAssertEqual(MockupScenes.inCategory("Apparel").map(\.id), ["tshirt", "hoodie", "tote-bag"])
        // A scene's gradient reads its stops' positions.
        let phone = MockupScenes.scene("phone-front")
        XCTAssertEqual(phone?.background.paint.kind, "gradient")
        XCTAssertEqual(phone?.background.paint.stops?.map(\.offset), [0, 1])
    }

    func testAPageIsCutToTheWindowsShapeCentred() {
        // A story in a laptop's screen: its middle band.
        XCTAssertEqual(MockupGeometry.cover(width: 1080, height: 1920, aspect: 1.6), CGRect(x: 0, y: 622.5, width: 1080, height: 675))
        // A slide in a phone: its middle column.
        XCTAssertEqual(MockupGeometry.cover(width: 1920, height: 1080, aspect: 0.5625),
                       CGRect(x: 656.25, y: 0, width: 607.5, height: 1080))
        // The same shape: all of it.
        XCTAssertEqual(MockupGeometry.cover(width: 1600, height: 1000, aspect: 1.6), CGRect(x: 0, y: 0, width: 1600, height: 1000))
        XCTAssertEqual(MockupGeometry.cover(width: 0, height: 10, aspect: 1), CGRect(x: 0, y: 0, width: 0, height: 10))
    }

    func testASceneFitsABoxWholeCentredAndItsWindowGoesWithIt() {
        let fit = MockupGeometry.fit(sceneWidth: 1600, sceneHeight: 1200, boxWidth: 400, boxHeight: 400)
        XCTAssertEqual(fit.scale, 0.25, accuracy: 1e-12)
        XCTAssertEqual(fit.x, 0, accuracy: 1e-12)
        XCTAssertEqual(fit.y, 50, accuracy: 1e-12)
        let screen = MockupScenes.Screen(quad: [[100, 100], [500, 100], [500, 900], [100, 900]], aspect: 0.5)
        XCTAssertEqual(MockupGeometry.mapped(screen, fit: fit),
                       [CGPoint(x: 25, y: 75), CGPoint(x: 125, y: 75), CGPoint(x: 125, y: 275), CGPoint(x: 25, y: 275)])
    }

    func testAMugsMeshWrapsThePageRoundCrowdingToTheSidesItsMiddleSagging() {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 50), CGPoint(x: 0, y: 50)]
        let mesh = MockupGeometry.mesh(corners, cylinder: MockupScenes.Cylinder(angle: Double.pi / 2, sag: 10),
                                       columns: 4, rows: 2)
        XCTAssertEqual(mesh.count, 15)
        // Top row: the corners stay put; the middle sags the whole sag.
        XCTAssertEqual(Double(mesh[0].x), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(mesh[0].y), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(mesh[4].x), 100, accuracy: 1e-9)
        XCTAssertEqual(Double(mesh[4].y), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(mesh[2].x), 50, accuracy: 1e-9)
        XCTAssertEqual(Double(mesh[2].y), 10, accuracy: 1e-9)
        // A quarter of the way round is sin(45°) of the way out: crowded.
        XCTAssertEqual(Double(mesh[1].x), 50 - 50 * 0.5.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(Double(mesh[1].y), 10 * 0.5.squareRoot(), accuracy: 1e-9)
        // Bottom row: the bottom edge, sagging alike.
        XCTAssertEqual(Double(mesh[10].x), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(mesh[10].y), 50, accuracy: 1e-9)
        XCTAssertEqual(Double(mesh[12].y), 60, accuracy: 1e-9)
    }
}
