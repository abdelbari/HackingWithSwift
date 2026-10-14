// The presenter's side of a talk given on a second screen: the slides on the
// display the room sees, and on the phone the page up (small), the page
// coming, the notes in large type, the talk's timer and the time on this
// page. The rules both phones keep, with the same tests as the Android
// twin's.

import CoreGraphics
import Foundation

enum Presenter {

    /// Where the page coming would be, after the last page shown.
    static let endOfPresentation = tr("End of presentation")

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
        tr("%@ · holds %@ s", clockText(seconds), String(format: "%.1f", hold))
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

    /// The page whose transition plays on a turn from `index` to `next`:
    /// the earlier of the two — the page left going on, the page returned
    /// to going back, in reverse — and round the loop, the first page's own
    /// played forward, as the Android twin's PresentScreen.goTo(wrap) has
    /// it: the page arrived at, not the last page left.
    static func transitionPage(from index: Int, to next: Int, looping: Bool) -> Int {
        looping ? next : min(index, next)
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
    /// and X to clear — the Android twin's Presenter.effects, names and all.
    static let effects: [Effect] = timers + others

    private static let timers: [Effect] = (1...9).map { (minutes: Int) -> Effect in
        Effect(id: "timer\(minutes)", key: "\(minutes)", name: tr("%d min", minutes), symbol: "timer")
    }

    private static let others: [Effect] = [
        Effect(id: "blur", key: "b", name: tr("Blur"), symbol: "drop.halffull"),
        Effect(id: "confetti", key: "c", name: tr("Confetti"), symbol: "party.popper"),
        Effect(id: "bubbles", key: "o", name: tr("Bubbles"), symbol: "bubbles.and.sparkles"),
        Effect(id: "quiet", key: "q", name: tr("Quiet"), symbol: "hand.raised"),
        Effect(id: "curtain", key: "u", name: tr("Curtain"), symbol: "theatermasks"),
        Effect(id: "clear", key: "x", name: tr("Clear"), symbol: "xmark.circle"),
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

    /// The effects showing once `id` is asked for at `date`. One effect is
    /// up at a time, as on the Android twin: a new one takes the place of
    /// the last, "clear" takes it away, and one whose three seconds are over
    /// goes. A page turn ends whichever is up (PresentationView.turn).
    static func showing(_ shown: [Shown], adding id: String, at date: Date) -> [Shown] {
        guard effects.contains(where: { $0.id == id }) else { return live(shown, at: date) }
        guard id != "clear" else { return [] }
        return [Shown(id: id, since: date)]
    }

    /// Those still up at `date`: every lasting one, and the rest within
    /// their three seconds.
    static func live(_ shown: [Shown], at date: Date) -> [Shown] {
        shown.filter { lasts($0.id) || date.timeIntervalSince($0.since) < effectSeconds }
    }

    /// A piece of confetti or a bubble at a moment, in the page's unit
    /// square: where it is across and down, its size against the page's
    /// shorter side, its colour by `effectColours`, and its turn in degrees.
    struct Particle: Equatable {
        var x: Double
        var y: Double
        var size: Double
        var colour: Int
        var turn: Double
    }

    /// The effects' colours, as #rrggbb — the Android twin's EFFECT_COLORS.
    static let effectColours = ["#f2545b", "#ffc145", "#3ec1d3", "#7b5ea7", "#4caf50", "#ff8a3d"]

    /// The pieces of confetti, and the bubbles.
    static let confettiCount = 80
    static let bubbleCount = 30

    /// Where every piece of effect `id`'s particles is `t` seconds in — the
    /// same on every screen and on both phones, the Android twin's
    /// Presenter.particles sum for sum: from seed 26, a linear congruential
    /// generator with the C library's constants (1103515245, 12345, modulo
    /// 2^31), each draw its top 16 bits over 65536. Each piece takes four
    /// draws, in order: across, start, speed, size; its colour is its
    /// number round `effectColours`. Confetti falls from up to half a page
    /// above the top, a third to two thirds of a page a second, swaying and
    /// turning; bubbles rise from below the bottom. None for another id.
    static func particles(_ id: String, t: Double) -> [Particle] {
        let count: Int
        switch id {
        case "confetti": count = confettiCount
        case "bubbles": count = bubbleCount
        default: return []
        }
        var seed: Int64 = 26
        func draw() -> Double {
            seed = (seed &* 1_103_515_245 &+ 12_345) & 0x7fff_ffff
            return Double(seed >> 15) / 65_536
        }
        return (0..<count).map { (n: Int) -> Particle in
            let across = draw(), start = draw(), speed = draw(), size = draw()
            let colour = n % effectColours.count
            guard id == "confetti" else {
                let y = 1.05 + start * 0.3 - (0.25 + speed * 0.2) * t
                return Particle(x: across, y: y, size: 0.03 + size * 0.04, colour: colour, turn: 0)
            }
            let y = -0.05 - start * 0.5 + (0.33 + speed * 0.33) * t
            let sway = 0.03 * sin(2 * Double.pi * (t * (0.5 + speed) + start))
            return Particle(x: across + sway, y: y, size: 0.012 + size * 0.012, colour: colour,
                            turn: 360 * (start + t * (0.5 + speed)))
        }
    }

    /// The moment the still stand-in shows, with Reduce Motion on:
    /// confetti and bubbles as they are a second and a half in.
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
