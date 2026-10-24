// Scrolling through a long design fast: a slim thumb at the column's
// trailing edge, as Canva's page position indicator is, sized to the share
// of the column on screen. Dragged, it moves the view by the same share of
// the column — linearly — a bubble beside it naming the page under it, and
// let go, the view settles on that page's top. Shown for a moment after
// any scroll, only with six pages or more, and never on a page alone or
// while typing, cropping or drawing. The Android twin's PageScrubber, with
// the same rows in its tests.

import Foundation

enum PageScrubber {

    /// The fewest pages the scrubber shows for.
    static let minPages = 6
    /// How long it stays after the view stops, in seconds.
    static let shownSeconds = 1.5
    /// The least its thumb is along the track, and across where a finger
    /// takes it: 44 points, the Android twin's 48 dp.
    static let minThumb = 44.0

    /// Whether it shows: the column of pages, `pages` of them at least
    /// minPages, and nothing holding the view to its page — typing,
    /// cropping, drawing (`busy`).
    static func shows(pages: Int, column: Bool, busy: Bool) -> Bool {
        column && !busy && pages >= minPages
    }

    /// The thumb's length along a track `track` long: the share of the
    /// column on screen, `visible` of `column`, never less than minThumb
    /// and never more than the track.
    static func thumbLength(visible: Double, column: Double, track: Double) -> Double {
        guard column > 0, track > 0 else { return 0 }
        let share = min(max(visible / column, 0), 1)
        return min(max(track * share, minThumb), track)
    }

    /// How far down the column the view's top may go: the column less what
    /// is on screen.
    static func travel(visible: Double, column: Double) -> Double {
        max(column - visible, 0)
    }

    /// The thumb's top along the track for a view whose top is `top` down
    /// the column: the same share of the room the thumb has to move.
    static func thumbTop(top: Double, visible: Double, column: Double, track: Double) -> Double {
        let room = track - thumbLength(visible: visible, column: column, track: track)
        let reach = travel(visible: visible, column: column)
        guard room > 0, reach > 0 else { return 0 }
        return min(max(top / reach, 0), 1) * room
    }

    /// The view's top down the column for the thumb dragged to `thumbTop`:
    /// thumbTop turned back, linearly, held to the column.
    static func columnTop(thumbTop: Double, visible: Double, column: Double, track: Double) -> Double {
        let room = track - thumbLength(visible: visible, column: column, track: track)
        guard room > 0 else { return 0 }
        return min(max(thumbTop / room, 0), 1) * travel(visible: visible, column: column)
    }

    /// The page a screen-reader's swipe up (or, `by` -1, down) goes to
    /// from `page` of `count`: the next, held to the first and the last.
    static func stepped(_ page: Int, by step: Int, count: Int) -> Int {
        min(max(page + step, 0), max(count - 1, 0))
    }

    /// The bubble's words: "Page 37 · Title", as the page's header reads.
    static func bubble(_ index: Int, title: String?) -> String {
        PageTitles.named(index + 1, title: title)
    }

    /// What VoiceOver reads for the thumb's value: "37 of 60".
    static func spoken(_ index: Int, count: Int) -> String {
        tr("%d of %d", index + 1, count)
    }
}
