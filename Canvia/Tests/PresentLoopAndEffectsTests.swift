// Present's Loop and the presenter's effects: the page after the last one
// shown with Loop on, hidden pages stepped over; "present":{"loop":true}
// kept in the design and left out when off; the effects' keys; the
// countdown as Presenter.clockText writes it; which effects stay; and the
// seeded particles both screens draw. The same cases as the Android twin's.

import XCTest
@testable import Canvia

final class PresentLoopAndEffectsTests: XCTestCase {

    private func design(hidden: [Bool]) -> Design {
        var d = Design(title: "p", width: 400, height: 300)
        d.pages = hidden.map { flag in
            var p = Page()
            p.hidden = flag ? true : nil
            return p
        }
        return d
    }

    // MARK: loop

    /// Round from the last page shown to the first shown, hidden pages at
    /// either end stepped over; nowhere without Loop, or with one page.
    func testTheLoopNextIndexAcrossHiddenPages() {
        let visible = design(hidden: [true, false, false, true, false, true]).visiblePageIndices
        XCTAssertEqual(visible, [1, 2, 4])
        XCTAssertEqual(Presenter.next(after: 1, in: visible, loop: true), 2)
        XCTAssertEqual(Presenter.next(after: 2, in: visible, loop: true), 4, "a hidden page stepped over")
        XCTAssertEqual(Presenter.next(after: 4, in: visible, loop: true), 1, "round to the first shown")
        XCTAssertNil(Presenter.next(after: 4, in: visible, loop: false))
        XCTAssertEqual(Presenter.next(after: 4, in: visible, loop: false), Presenter.next(after: 4, in: visible))
        XCTAssertNil(Presenter.next(after: 3, in: [3], loop: true), "one page goes nowhere")
        XCTAssertNil(Presenter.next(after: 0, in: [], loop: true))
    }

    /// Kept as {"loop":true}, and left out when off, so other designs read
    /// and write as before; a false or missing loop reads as none.
    @MainActor
    func testLoopIsKeptInTheDesign() throws {
        var d = design(hidden: [false, false])
        XCTAssertFalse(d.presentLoops)
        let off = String(decoding: try JSONEncoder().encode(d), as: UTF8.self)
        XCTAssertFalse(off.contains("\"present\""))
        d.presentLoops = true
        let on = String(decoding: try JSONEncoder().encode(d), as: UTF8.self)
        XCTAssertTrue(on.contains(#""present":{"loop":true}"#))
        XCTAssertTrue(try JSONDecoder().decode(Design.self, from: Data(on.utf8)).presentLoops)
        d.presentLoops = false
        XCTAssertNil(d.present)

        let written = #"{"id":"doc_a","title":"Kiosk","width":100,"height":100,"pages":[{"elements":[]}],"present":{"loop":false}}"#
        XCTAssertNil(try JSONDecoder().decode(Design.self, from: Data(written.utf8)).present)
        let none = #"{"id":"doc_b","title":"Plain","width":100,"height":100,"pages":[{"elements":[]}]}"#
        XCTAssertNil(try JSONDecoder().decode(Design.self, from: Data(none.utf8)).present)
        XCTAssertTrue(PresentSession(design: d.withLoop()).loop)
    }

    // MARK: effects

    func testTheEffectsAndTheirKeys() {
        XCTAssertEqual(Presenter.effects.map(\.id), [
            "timer1", "timer2", "timer3", "timer4", "timer5", "timer6", "timer7", "timer8", "timer9",
            "blur", "confetti", "bubbles", "quiet", "curtain", "clear",
        ])
        let rows: [(String, String?)] = [
            ("1", "timer1"), ("5", "timer5"), ("9", "timer9"), ("b", "blur"), ("B", "blur"),
            ("c", "confetti"), ("o", "bubbles"), ("q", "quiet"), ("u", "curtain"), ("x", "clear"),
            ("X", "clear"), ("0", nil), ("d", nil), ("z", nil), ("", nil),
        ]
        for (key, id) in rows {
            XCTAssertEqual(Presenter.effect(forKey: key)?.id, id, "key \(key)")
        }
    }

    /// The time left, rounded up to the second, as the clock writes it:
    /// "5:00" as it starts, "0:00" once up, and no lower.
    func testCountdownFormattingViaTheClock() {
        XCTAssertEqual(Presenter.countdown(minutes: 5, elapsed: 0), "5:00")
        XCTAssertEqual(Presenter.countdown(minutes: 5, elapsed: 0.4), "5:00")
        XCTAssertEqual(Presenter.countdown(minutes: 5, elapsed: 1), "4:59")
        XCTAssertEqual(Presenter.countdown(minutes: 5, elapsed: 61), "3:59")
        XCTAssertEqual(Presenter.countdown(minutes: 1, elapsed: 59.2), "0:01")
        XCTAssertEqual(Presenter.countdown(minutes: 1, elapsed: 60), "0:00")
        XCTAssertEqual(Presenter.countdown(minutes: 9, elapsed: 10_000), "0:00")
        XCTAssertEqual(Presenter.timerMinutes("timer7"), 7)
        XCTAssertNil(Presenter.timerMinutes("timer0"))
        XCTAssertNil(Presenter.timerMinutes("blur"))
    }

    /// A timer, the curtain and blur stay until X or the next page; the
    /// rest for three seconds. X clears them all; a timer replaces a timer.
    func testWhichEffectsStay() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(Presenter.lasts("timer3"))
        XCTAssertTrue(Presenter.lasts("curtain"))
        XCTAssertTrue(Presenter.lasts("blur"))
        XCTAssertFalse(Presenter.lasts("confetti"))
        XCTAssertFalse(Presenter.lasts("quiet"))

        var shown = Presenter.showing([], adding: "timer3", at: start)
        shown = Presenter.showing(shown, adding: "confetti", at: start)
        shown = Presenter.showing(shown, adding: "timer5", at: start.addingTimeInterval(1))
        XCTAssertEqual(shown.map(\.id), ["confetti", "timer5"], "a timer replaces a timer")
        XCTAssertEqual(Presenter.live(shown, at: start.addingTimeInterval(2.9)).map(\.id), ["confetti", "timer5"])
        XCTAssertEqual(Presenter.live(shown, at: start.addingTimeInterval(3)).map(\.id), ["timer5"], "three seconds")
        shown = Presenter.showing(shown, adding: "curtain", at: start.addingTimeInterval(1))
        XCTAssertEqual(Presenter.afterPageTurn(shown).map(\.id), ["confetti"], "the next page ends the lasting ones")
        XCTAssertTrue(Presenter.showing(shown, adding: "clear", at: start).isEmpty)
        XCTAssertEqual(Presenter.showing(shown, adding: "nonsense", at: start).map(\.id), shown.map(\.id))
    }

    /// The same particles every time, from Numerical Recipes' generator,
    /// so the phone and the screen — and both phones — draw the same.
    func testParticlesAreSeeded() {
        XCTAssertEqual(Presenter.particles(count: 60, seed: 1), Presenter.particles(count: 60, seed: 1))
        XCTAssertNotEqual(Presenter.particles(count: 3, seed: 1), Presenter.particles(count: 3, seed: 2))
        let first = Presenter.particles(count: 1, seed: 1)[0]
        XCTAssertEqual(first.x, 0.23645552527159452, accuracy: 1e-12)
        XCTAssertEqual(first.delay, 0.22156240423209964, accuracy: 1e-12)
        XCTAssertEqual(first.speed, 0.5516968129202724, accuracy: 1e-12)
        XCTAssertEqual(first.size, 0.023278132218867542, accuracy: 1e-12)
        XCTAssertEqual(first.spin, -0.8989127427339554, accuracy: 1e-12)
        XCTAssertEqual(first.colour, 2)
        XCTAssertEqual(Presenter.confetti.count, 60)
        XCTAssertEqual(Presenter.bubbles.count, 24)
        XCTAssertNil(Presenter.particlePosition(first, t: 0.1, rising: false), "not set off yet")
        let falling = Presenter.particlePosition(first, t: 1.22156240423209964, rising: false)
        XCTAssertEqual(Double(falling?.y ?? 0), -0.05 + 0.5516968129202724, accuracy: 1e-9)
    }
}

private extension Design {
    func withLoop() -> Design {
        var d = self
        d.presentLoops = true
        return d
    }
}
