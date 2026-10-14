// The presenter's side of a talk given on a second screen: the slides on the
// display the room sees, and on the phone the page up (small), the page
// coming, the notes in large type, the talk's timer and the time on this
// page. The rules both phones keep, with the same tests as the Android
// twin's.

import CoreGraphics
import Foundation

enum Presenter {

    /// Where the page coming would be, after the last page shown.
    static let endOfPresentation = "End of presentation"

    /// A timer as the presenter reads it: "0:00", "12:05", "1:02:03". Whole
    /// seconds, rounded down; minutes and seconds two digits each after the
    /// first figure, hours only once there is one. Nothing below nought.
    static func clockText(_ seconds: Double) -> String {
        let whole = seconds.isFinite ? Int(min(max(seconds, 0), 1e9).rounded(.down)) : 0
        let hours = whole / 3600, minutes = whole / 60 % 60, rest = whole % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, rest) }
        return String(format: "%d:%02d", minutes, rest)
    }

    /// How long the page up has been showing, as `clockText` writes it,
    /// and how long it holds on autoplay to a tenth of a second, as the
    /// pages panel says it: "0:07 · holds 2.5 s".
    static func pageTime(_ seconds: Double, hold: Double) -> String {
        "\(clockText(seconds)) · holds \(String(format: "%.1f", hold)) s"
    }

    /// The page after page `index` among `visible` (the design's
    /// visiblePageIndices) — round 18's lookup, hidden pages stepped over;
    /// nil after the last, where the presenter reads `endOfPresentation`.
    static func next(after index: Int, in visible: [Int]) -> Int? {
        PageVisibility.next(after: index, in: visible)
    }

    /// The same, and with `loop` the first page shown after the last —
    /// never the page already up, so a talk of one page has nowhere to go.
    static func next(after index: Int, in visible: [Int], loop: Bool) -> Int? {
        if let next = next(after: index, in: visible) { return next }
        guard loop, let first = visible.first, first != index else { return nil }
        return first
    }

    /// The pages the page grid offers to jump to, by index: the pages shown,
    /// in order, hidden pages left out.
    static func gridPages(_ design: Design) -> [Int] {
        design.visiblePageIndices
    }

    // MARK: notes

    /// The notes' text size in points: 20 to begin with, A− and A+ stepping
    /// it by 2 between 14 and 40.
    static let defaultNotesSize: Double = 20
    static let notesSizes: ClosedRange<Double> = 14...40
    static let notesStep: Double = 2

    /// The size `steps` steps from `size` — negative for A−, positive for
    /// A+ — kept within `notesSizes`.
    static func notesSize(_ size: Double, steps: Int) -> Double {
        min(max(size + Double(steps) * notesStep, notesSizes.lowerBound), notesSizes.upperBound)
    }

    // MARK: pointer

    /// Where `location`, in a view of `size` with a page of `page` size
    /// fitted to its middle, falls on the page, in the page's own units; nil
    /// off the page, where the pointer draws nothing. The page's edges count
    /// as on it.
    static func pagePoint(_ location: CGPoint, in size: CGSize, page: CGSize) -> CGPoint? {
        let scale = min(size.width / max(page.width, 1), size.height / max(page.height, 1))
        guard scale > 0 else { return nil }
        let dx = (size.width - page.width * scale) / 2
        let dy = (size.height - page.height * scale) / 2
        let point = CGPoint(x: (location.x - dx) / scale, y: (location.y - dy) / scale)
        guard point.x >= 0, point.y >= 0, point.x <= page.width, point.y <= page.height else { return nil }
        return point
    }

    /// The pointer's red dot across, in the page's units: 3% of the page's
    /// shorter side, so it is the same share of the page on every screen.
    static func pointerDiameter(page: CGSize) -> Double {
        Double(min(page.width, page.height)) * 0.03
    }

    // MARK: effects

    /// One of the presenter's effects: its id, the key a keyboard or a
    /// clicker sends for it, what the grid calls it and its symbol there.
    struct Effect: Identifiable, Equatable {
        let id: String
        let key: String
        let name: String
        let symbol: String
    }

    /// Every effect, in the grid's order: a 1 to 9 minute countdown on the
    /// keys 1 to 9, then B blur, C confetti, O bubbles, Q quiet, U curtain
    /// and X to clear them all — the Android twin's Presenter.effects.
    static let effects: [Effect] = timers + others

    private static let timers: [Effect] = (1...9).map { (minutes: Int) -> Effect in
        Effect(id: "timer\(minutes)", key: "\(minutes)", name: "\(minutes) min timer", symbol: "timer")
    }

    private static let others: [Effect] = [
        Effect(id: "blur", key: "b", name: "Blur", symbol: "drop.halffull"),
        Effect(id: "confetti", key: "c", name: "Confetti", symbol: "party.popper"),
        Effect(id: "bubbles", key: "o", name: "Bubbles", symbol: "bubbles.and.sparkles"),
        Effect(id: "quiet", key: "q", name: "Quiet", symbol: "hand.raised"),
        Effect(id: "curtain", key: "u", name: "Curtain", symbol: "theatermasks"),
        Effect(id: "clear", key: "x", name: "Clear", symbol: "xmark.circle"),
    ]

    /// The effect a key asks for, capitals or not; nil for any other key.
    static func effect(forKey key: String) -> Effect? {
        let typed = key.lowercased()
        return effects.first { $0.key == typed }
    }

    /// How long confetti, bubbles and quiet stay up, in seconds.
    static let effectSeconds = 3.0
    /// How long the curtain takes to close.
    static let curtainSeconds = 1.0

    /// Whether an effect stays until X or the next page — a timer, the
    /// curtain and blur — rather than its three seconds.
    static func lasts(_ id: String) -> Bool {
        id == "blur" || id == "curtain" || timerMinutes(id) != nil
    }

    /// A timer's minutes: 4 for "timer4"; nil for anything else.
    static func timerMinutes(_ id: String) -> Int? {
        guard id.hasPrefix("timer"), let minutes = Int(id.dropFirst(5)), (1...9).contains(minutes) else { return nil }
        return minutes
    }

    /// A countdown of `minutes` read `elapsed` seconds in, as `clockText`
    /// writes it — the seconds left rounded up, so it reads "5:00" as it
    /// starts and "0:00" only once the time is up, and stays there.
    static func countdown(minutes: Int, elapsed: Double) -> String {
        let left = Double(minutes * 60) - (elapsed.isFinite ? elapsed : 0)
        return clockText(max(0, left).rounded(.up))
    }

    /// An effect showing, from when it was asked for.
    struct Shown: Equatable {
        let id: String
        let since: Date
    }

    /// The effects showing once `id` is asked for at `date`: "clear" takes
    /// every one away; a timer replaces any timer; any other starts again
    /// in place of itself; and those whose three seconds are over go.
    static func showing(_ shown: [Shown], adding id: String, at date: Date) -> [Shown] {
        guard effects.contains(where: { $0.id == id }) else { return live(shown, at: date) }
        guard id != "clear" else { return [] }
        let isTimer = timerMinutes(id) != nil
        let kept = live(shown, at: date).filter { other in
            other.id != id && !(isTimer && timerMinutes(other.id) != nil)
        }
        return kept + [Shown(id: id, since: date)]
    }

    /// Those still up at `date`: every lasting one, and the rest within
    /// their three seconds.
    static func live(_ shown: [Shown], at date: Date) -> [Shown] {
        shown.filter { lasts($0.id) || date.timeIntervalSince($0.since) < effectSeconds }
    }

    /// Those that carry on to the next page: none of the lasting ones.
    static func afterPageTurn(_ shown: [Shown]) -> [Shown] {
        shown.filter { !lasts($0.id) }
    }

    /// One piece of confetti or one bubble, in the page's unit square:
    /// where across it starts, how long after the effect it sets off, how
    /// far down (or up) it goes a second, how big it is against the page's
    /// shorter side, how many turns a second it spins and which colour.
    struct Particle: Equatable {
        var x: Double
        var delay: Double
        var speed: Double
        var size: Double
        var spin: Double
        var colour: Int
    }

    /// The colours confetti comes in, by Particle.colour.
    static let confettiColours = ["#ff595e", "#ffca3a", "#8ac926", "#1982c4", "#6a4c93", "#ff924c"]

    /// `count` particles from `seed`, the same on every screen and on both
    /// phones: a 32-bit linear congruential generator (Numerical Recipes'
    /// 1664525 and 1013904223), each draw its state over 2^32, six draws a
    /// particle in the order of Particle's fields.
    static func particles(count: Int, seed: UInt32) -> [Particle] {
        var state = seed
        func draw() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Double(state) / 4_294_967_296
        }
        return (0..<max(0, count)).map { _ in
            let x = draw(), delay = draw() * 0.6, speed = 0.35 + draw() * 0.4
            let size = 0.012 + draw() * 0.016, spin = draw() * 2 - 1
            let colour = min(confettiColours.count - 1, Int(draw() * Double(confettiColours.count)))
            return Particle(x: x, delay: delay, speed: speed, size: size, spin: spin, colour: colour)
        }
    }

    static let confetti = particles(count: 60, seed: 1)
    static let bubbles = particles(count: 24, seed: 2)

    /// Where a particle is `t` seconds into its effect, in the unit square:
    /// falling from just above the page, or rising from just below it, with
    /// a little sway; nil before it sets off.
    static func particlePosition(_ p: Particle, t: Double, rising: Bool) -> CGPoint? {
        let run = t - p.delay
        guard run >= 0 else { return nil }
        let travel = run * p.speed
        let x = p.x + 0.03 * sin(t * 4 + p.x * 6.283)
        return CGPoint(x: x, y: rising ? 1.05 - travel : -0.05 + travel)
    }

    /// The moment the still stand-in shows, with Reduce Motion on: the
    /// particles where they would be halfway through.
    static let stillTime = 1.5
}

/// The talk's timer, which the presenter can pause and set back to 0:00.
struct PresenterTimer: Equatable {
    /// Seconds counted before the latest start.
    private(set) var banked: Double = 0
    /// When the timer last started; nil while it is paused.
    private(set) var since: Date?

    /// A timer running from `date`.
    init(startingAt date: Date) {
        since = date
    }

    var paused: Bool { since == nil }

    /// The seconds counted by `date`.
    func elapsed(at date: Date) -> Double {
        banked + (since.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// Paused, keeping the time counted; or running again from it.
    mutating func toggle(at date: Date) {
        if let since {
            banked += max(0, date.timeIntervalSince(since))
            self.since = nil
        } else {
            since = date
        }
    }

    /// Back to 0:00 — running on from there when it was running, paused
    /// there when it was paused.
    mutating func reset(at date: Date) {
        banked = 0
        if since != nil { since = date }
    }
}
