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
