// Tone-curve presets, connectors that follow their ends, and the launch
// requests App Intents leave for the app.

import XCTest
import CoreImage
import AppIntents
@testable import Canvia

final class CurvesConnectorsIntentsTests: XCTestCase {

    // MARK: tone curve

    func testPresetsAreMonotonicCurvesAcrossTheUnitSquare() {
        XCTAssertFalse(ToneCurve.presets.isEmpty)
        for p in ToneCurve.presets {
            XCTAssertEqual(p.points.count, 5, p.id)
            XCTAssertEqual(p.points.first?.x, 0, p.id)
            XCTAssertEqual(p.points.last?.x, 1, p.id)
            for (a, b) in zip(p.points, p.points.dropFirst()) {
                XCTAssertLessThan(a.x, b.x, p.id)
                XCTAssertLessThanOrEqual(a.y, b.y, "\(p.id) is not monotonic")
            }
            XCTAssertTrue(p.points.allSatisfy { (0...1).contains($0.y) }, p.id)
        }
        XCTAssertNil(ToneCurve.preset("nope"))
        XCTAssertNil(ToneCurve.preset(nil))
    }

    func testCurveIsAnAdjustmentWithItsOwnSignatureAndSurvivesEncoding() throws {
        var a = Adjustments.neutral
        XCTAssertTrue(a.isNeutral)
        a.curve = "fade"
        XCTAssertFalse(a.isNeutral)
        XCTAssertEqual(a.signature, "adjtfade")
        let back = try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back.curve, "fade")
        let old = try JSONDecoder().decode(Adjustments.self, from: Data(#"{"brightness":0.5}"#.utf8))
        XCTAssertNil(old.curve)
    }

    func testCrushingBlacksDarkensAMidGrey() throws {
        let grey = CIImage(color: CIColor(red: 0.25, green: 0.25, blue: 0.25)).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let out = ToneCurve.apply("crush", to: grey)
        let ctx = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var before = [UInt8](repeating: 0, count: 4), after = [UInt8](repeating: 0, count: 4)
        ctx.render(grey, toBitmap: &before, rowBytes: 4, bounds: CGRect(x: 1, y: 1, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        ctx.render(out, toBitmap: &after, rowBytes: 4, bounds: CGRect(x: 1, y: 1, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        XCTAssertLessThan(after[0], before[0], "crush: \(before) -> \(after)")
        XCTAssertEqual(ToneCurve.apply(nil, to: grey), grey)
    }

    // MARK: connectors

    func testAnchorLeavesTheRectTowardTheTarget() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertEqual(Connectors.anchor(of: r, toward: CGPoint(x: 300, y: 25)), CGPoint(x: 100, y: 25))
        XCTAssertEqual(Connectors.anchor(of: r, toward: CGPoint(x: 50, y: -100)), CGPoint(x: 50, y: 0))
        // Diagonal: leaves through the nearer edge.
        let d = Connectors.anchor(of: r, toward: CGPoint(x: 150, y: 125))
        XCTAssertEqual(d.y, 50, accuracy: 0.001)
        XCTAssertEqual(d.x, 75, accuracy: 0.001)
        // A target inside the rect is the target itself; the centre is the centre.
        XCTAssertEqual(Connectors.anchor(of: r, toward: CGPoint(x: 60, y: 30)), CGPoint(x: 60, y: 30))
        XCTAssertEqual(Connectors.anchor(of: r, toward: CGPoint(x: 50, y: 25)), CGPoint(x: 50, y: 25))
    }

    func testGeometryJoinsEdgesAndPointsFromAToB() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100), b = CGRect(x: 300, y: 0, width: 100, height: 100)
        let g = Connectors.geometry(from: a, to: b, thickness: 4)
        XCTAssertEqual(g.w, 200, accuracy: 0.001)
        XCTAssertEqual(g.x, 100, accuracy: 0.001)
        XCTAssertEqual(g.y, 50 - 4, accuracy: 0.001)     // 8 tall, centred on y = 50
        XCTAssertEqual(g.rotation, 0)
        let back = Connectors.geometry(from: b, to: a, thickness: 4)
        XCTAssertEqual(back.rotation, 180)
        let down = Connectors.geometry(from: a, to: CGRect(x: 0, y: 300, width: 100, height: 100), thickness: 4)
        XCTAssertEqual(down.rotation, 90)
        XCTAssertEqual(down.h, 8)
    }

    @MainActor
    func testConnectorFollowsItsEndsAndLetsGoWhenOneIsDeleted() {
        var d = Design(title: "c", width: 1000, height: 600)
        var a = Element.shape("rect", w: 100, h: 100); a.x = 0; a.y = 0
        var b = Element.shape("rect", w: 100, h: 100); b.x = 300; b.y = 0
        d.pages[0].elements = [a, b]
        let store = DesignStore(design: d)
        store.selection = [a.id, b.id]
        store.connectSelected()
        XCTAssertEqual(store.page.elements.count, 3)
        let line = store.page.elements[2]
        XCTAssertEqual(line.type, .line)
        XCTAssertEqual(line.connectFrom, a.id)
        XCTAssertEqual(line.endCap, "arrow")
        XCTAssertEqual(line.w, 200, accuracy: 0.001)
        XCTAssertEqual(store.selection, [line.id])

        // Move b down and to the right: the arrow turns and stretches.
        store.selection = [b.id]
        store.updateSelected { $0.x = 300; $0.y = 300 }
        let moved = store.page.elements[2]
        XCTAssertNotEqual(moved.rotation, 0)
        XCTAssertGreaterThan(moved.w, 200)
        // Undo puts the arrow back too.
        store.undo()
        XCTAssertEqual(store.page.elements[2].w, 200, accuracy: 0.001)
        XCTAssertEqual(store.page.elements[2].rotation, 0)

        // Delete a: the line stays where it is, as a plain line.
        store.selection = [a.id]
        store.deleteSelected()
        let loose = store.page.elements.first { $0.type == .line }
        XCTAssertNil(loose?.connectFrom)
        XCTAssertNil(loose?.connectTo)
        XCTAssertEqual(loose?.w ?? 0, 200, accuracy: 0.001)
    }

    func testConnectorsEncode() throws {
        var line = Element.line(w: 50)
        line.connectFrom = "a"; line.connectTo = "b"
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(back.connectFrom, "a")
        XCTAssertEqual(back.connectTo, "b")
    }

    // MARK: launch requests

    func testLaunchRequestIsServedOnce() {
        let defaults = UserDefaults(suiteName: "launch-\(UUID())")!
        XCTAssertNil(LaunchRequest.take(defaults))
        LaunchRequest.set(.newDesign(width: 1080, height: 1920, title: "Story"), defaults: defaults)
        XCTAssertEqual(LaunchRequest.take(defaults), .newDesign(width: 1080, height: 1920, title: "Story"))
        XCTAssertNil(LaunchRequest.take(defaults), "served once")
        LaunchRequest.set(.open(id: "doc-1"), defaults: defaults)
        XCTAssertEqual(LaunchRequest.take(defaults), .open(id: "doc-1"))
        defaults.set(["kind": "new", "width": 0.0, "height": 10.0], forKey: LaunchRequest.key)
        XCTAssertNil(LaunchRequest.take(defaults), "a zero size is refused")
    }

    func testEverySizeChoiceHasAPreset() {
        for choice in DesignSizeChoice.allCases {
            XCTAssertNotNil(choice.preset, choice.rawValue)
        }
        XCTAssertEqual(DesignSizeChoice.instagramStory.preset?.h, 1920)
    }
}
