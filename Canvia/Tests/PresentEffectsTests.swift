// Present's magic shortcuts frame by frame, from the fixture both phones
// read (Fixtures/present_effects.json, the Android twin's
// PresentEffectsTest), so the two draw the same pictures: the grid's
// effects and keys, how long each plays, the seeded confetti and bubbles,
// the drumroll's roll and spotlight, and the mic drop.

import XCTest
@testable import Canvia

final class PresentEffectsTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("present_effects") }

    private func number(_ row: [String: Any], _ key: String) throws -> Double {
        try XCTUnwrap((row[key] as? NSNumber)?.doubleValue, key)
    }

    private func assertParticle(_ expected: [String: Any], _ actual: Presenter.Particle, _ what: String) throws {
        XCTAssertEqual(actual.x, try number(expected, "x"), accuracy: 1e-9, what)
        XCTAssertEqual(actual.y, try number(expected, "y"), accuracy: 1e-9, what)
        XCTAssertEqual(actual.size, try number(expected, "size"), accuracy: 1e-9, what)
        XCTAssertEqual(actual.colour, expected["color"] as? Int, what)
        XCTAssertEqual(actual.turn, try number(expected, "turn"), accuracy: 1e-9, what)
    }

    func testTheGridsEffectsAndTheirKeysDrumrollDAndMicDropM() throws {
        let f = try fixture()
        XCTAssertEqual(Presenter.effects.map(\.id), f["effects"] as? [String])
        XCTAssertEqual(Presenter.effects.map(\.key).joined(), f["keys"] as? String)
        XCTAssertEqual(Presenter.effect(forKey: "D")?.id, "drumroll")
        XCTAssertEqual(Presenter.effect(forKey: "m")?.id, "micdrop")
        // The pen's keys play no effect.
        for key in ["l", "p", "e"] { XCTAssertNil(Presenter.effect(forKey: key), key) }
    }

    func testTheDrumrollAndTheMicDropPassAfterTheirSounds() throws {
        let seconds = try XCTUnwrap(try fixture()["seconds"] as? [String: Double])
        for (id, expected) in seconds { XCTAssertEqual(Presenter.seconds(of: id), expected, id) }
        for id in ["drumroll", "micdrop"] {
            XCTAssertFalse(Presenter.lasts(id), id)
            XCTAssertTrue(Presenter.sounds(id), id)
            let effect = try XCTUnwrap(SoundEffects.effect(id), id)
            XCTAssertEqual(effect.seconds, Presenter.seconds(of: id), accuracy: 0.001, id)
        }
        XCTAssertFalse(Presenter.sounds("confetti"))
        // Sound off is offered with nothing else to hear, so they can be silenced.
        XCTAssertTrue(Presenter.offersSound(heard: false))
        XCTAssertTrue(Presenter.offersSound(heard: true))
        // Up for its whole sound, then gone.
        let start = Date(timeIntervalSince1970: 1_000)
        let shown = Presenter.showing([], adding: "drumroll", at: start)
        XCTAssertEqual(Presenter.live(shown, at: start.addingTimeInterval(2.4)).map(\.id), ["drumroll"])
        XCTAssertTrue(Presenter.live(shown, at: start.addingTimeInterval(2.5)).isEmpty)
    }

    func testParticlesMatchTheFixture() throws {
        for row in try XCTUnwrap(try fixture()["particles"] as? [[String: Any]]) {
            let id = try XCTUnwrap(row["id"] as? String)
            let got = Presenter.particles(id, t: try number(row, "t"))
            XCTAssertEqual(got.count, row["count"] as? Int)
            try assertParticle(try XCTUnwrap(row["first"] as? [String: Any]), try XCTUnwrap(got.first), "\(id) first")
            try assertParticle(try XCTUnwrap(row["last"] as? [String: Any]), try XCTUnwrap(got.last), "\(id) last")
        }
    }

    func testTheRollSpeedsUpToTheCrash() throws {
        let expected = try XCTUnwrap(try fixture()["rollStrokes"] as? [String: Any])
        let strokes = Presenter.rollStrokes()
        XCTAssertEqual(strokes.count, expected["count"] as? Int)
        for (i, t) in try XCTUnwrap(expected["first"] as? [Double]).enumerated() {
            XCTAssertEqual(strokes[i], t, accuracy: 1e-9)
        }
        XCTAssertEqual(try XCTUnwrap(strokes.last), try number(expected, "last"), accuracy: 1e-9)
        let gaps = zip(strokes.dropFirst(), strokes).map { $0 - $1 }
        XCTAssertTrue(zip(gaps.dropFirst(), gaps).allSatisfy { $0 <= $1 + 1e-12 }, "each gap no longer than the last")
    }

    func testTheSpotlightClosesWithTheRollAndOpensAtTheCrash() throws {
        for row in try XCTUnwrap(try fixture()["spotlight"] as? [[String: Any]]) {
            let t = try number(row, "t")
            let got = Presenter.spotlight(t)
            XCTAssertEqual(got.x, try number(row, "x"), accuracy: 1e-9, "x at \(t)")
            XCTAssertEqual(got.y, try number(row, "y"), accuracy: 1e-9, "y at \(t)")
            XCTAssertEqual(got.radius, try number(row, "radius"), accuracy: 1e-9, "radius at \(t)")
            XCTAssertEqual(got.dim, try number(row, "dim"), accuracy: 1e-9, "dim at \(t)")
        }
    }

    func testTheMicrophoneFallsBouncesAndTheSlideGoesToBlack() throws {
        for row in try XCTUnwrap(try fixture()["micDrop"] as? [[String: Any]]) {
            let t = try number(row, "t")
            let got = Presenter.micDrop(t)
            XCTAssertEqual(got.y, try number(row, "y"), accuracy: 1e-9, "y at \(t)")
            XCTAssertEqual(got.turn, try number(row, "turn"), accuracy: 1e-9, "turn at \(t)")
            XCTAssertEqual(got.black, try number(row, "black"), accuracy: 1e-9, "black at \(t)")
            XCTAssertEqual(got.dust.count, row["dust"] as? Int, "dust at \(t)")
            if let first = row["firstDust"] as? [String: Any] {
                try assertParticle(first, try XCTUnwrap(got.dust.first), "dust at \(t)")
            }
        }
    }
}
