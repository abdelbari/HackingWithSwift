// Present's Loop and the presenter's effects: the page after the last one
// shown with Loop on, hidden pages stepped over; "present":{"loop":true}
// kept in the design and left out when off; the effects' keys; the
// countdown as Presenter.clockText writes it; which effects stay, one at a
// time; the loop's transition; and the seeded particles both screens draw.
// The same cases as the Android twin's.

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

    /// Going on, the page left; going back, the page returned to; round the
    /// loop from the last page to the first, the first page's own
    /// transition, played forward — the Android twin's row.
    func testGoingRoundTheLoopPlaysTheFirstPagesTransition() {
        XCTAssertEqual(Presenter.transitionPage(from: 1, to: 2, looping: false), 1)
        XCTAssertEqual(Presenter.transitionPage(from: 2, to: 1, looping: false), 1)
        XCTAssertEqual(Presenter.transitionPage(from: 3, to: 1, looping: true), 1)
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
        XCTAssertEqual(Presenter.effects.first?.name, "1 min")
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
    /// rest for three seconds. One effect is up at a time, as on the
    /// Android twin: a new one takes the place of the last, and X clears it.
    func testWhichEffectsStay() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(Presenter.lasts("timer3"))
        XCTAssertTrue(Presenter.lasts("curtain"))
        XCTAssertTrue(Presenter.lasts("blur"))
        XCTAssertFalse(Presenter.lasts("confetti"))
        XCTAssertFalse(Presenter.lasts("quiet"))

        var shown = Presenter.showing([], adding: "blur", at: start)
        shown = Presenter.showing(shown, adding: "confetti", at: start)
        XCTAssertEqual(shown.map(\.id), ["confetti"], "B then C: confetti alone")
        XCTAssertEqual(Presenter.live(shown, at: start.addingTimeInterval(2.9)).map(\.id), ["confetti"])
        XCTAssertEqual(Presenter.live(shown, at: start.addingTimeInterval(3)).map(\.id), [], "three seconds")
        shown = Presenter.showing(shown, adding: "timer5", at: start.addingTimeInterval(1))
        XCTAssertEqual(Presenter.live(shown, at: start.addingTimeInterval(600)).map(\.id), ["timer5"], "a timer stays")
        XCTAssertTrue(Presenter.showing(shown, adding: "clear", at: start).isEmpty)
        XCTAssertEqual(Presenter.showing(shown, adding: "nonsense", at: start).map(\.id), shown.map(\.id))
    }

    /// The same particles every time, from the Android twin's generator
    /// and seed, so the phone and the screen — and both phones — draw the
    /// same: 80 pieces of confetti, 30 bubbles.
    func testParticlesAreSeeded() {
        let a = Presenter.particles("confetti", t: 1)
        XCTAssertEqual(a.count, Presenter.confettiCount)
        XCTAssertEqual(Presenter.confettiCount, 80)
        XCTAssertEqual(a, Presenter.particles("confetti", t: 1))
        XCTAssertEqual(Presenter.particles("bubbles", t: 0).count, 30)
        XCTAssertTrue(Presenter.particles("blur", t: 1).isEmpty)
        // The seed's first four draws place the first piece: across
        // 0.3604736328125, start 0.1904144287109375, speed
        // 0.404571533203125, size 0.02386474609375 — the Android twin's
        // PresentLoopTest row.
        let first = Presenter.particles("confetti", t: 0)[0]
        XCTAssertEqual(first.x, 0.3604736328125 + 0.03 * sin(2 * Double.pi * 0.1904144287109375), accuracy: 1e-12)
        XCTAssertEqual(first.y, -0.05 - 0.1904144287109375 * 0.5, accuracy: 1e-12)
        XCTAssertEqual(first.size, 0.012 + 0.02386474609375 * 0.012, accuracy: 1e-12)
        XCTAssertEqual(first.colour, 0)
        // Confetti falls, bubbles rise.
        XCTAssertGreaterThan(Presenter.particles("confetti", t: 2)[0].y, a[0].y)
        XCTAssertLessThan(Presenter.particles("bubbles", t: 2)[0].y, Presenter.particles("bubbles", t: 1)[0].y)
        XCTAssertTrue(a.allSatisfy { Presenter.effectColours.indices.contains($0.colour) })
        XCTAssertEqual(Presenter.effectColours, ["#f2545b", "#ffc145", "#3ec1d3", "#7b5ea7", "#4caf50", "#ff8a3d"])
    }
}

private extension Design {
    func withLoop() -> Design {
        var d = self
        d.presentLoops = true
        return d
    }
}
