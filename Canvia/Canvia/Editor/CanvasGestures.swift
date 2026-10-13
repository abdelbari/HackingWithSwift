// What a touch on the canvas does, as one table both phones keep — Canva's
// model, and the Android twin's (its EditorViewModel.onLongPress and the
// marquee): one finger on an element moves it, one finger on the empty page
// moves the view, a hold on the empty page and then a drag draws the
// selection band, a hold on an element adds it to the selection or takes it
// out, and two fingers pan and zoom anywhere. The tests on both phones hold
// the same rows.

import Foundation

enum CanvasGestures {

    /// How long a finger stays still on the empty page before a drag from
    /// there draws the band rather than moving the view, in seconds.
    static let holdSeconds = 0.4

    enum Input: CaseIterable {
        /// One finger, dragged straight away.
        case drag
        /// One finger held still for holdSeconds, then dragged.
        case holdThenDrag
        /// One finger held still for holdSeconds, then lifted.
        case hold
        /// Two fingers, pinched or dragged.
        case twoFingers
    }

    enum Target: CaseIterable {
        case element, emptyPage
    }

    enum Action: Equatable {
        case move, pan, band, toggleInSelection, panAndZoom, nothing
    }

    static func action(_ input: Input, on target: Target) -> Action {
        switch (input, target) {
        case (.twoFingers, _): return .panAndZoom
        case (.drag, .element): return .move
        case (.drag, .emptyPage): return .pan
        case (.holdThenDrag, .emptyPage): return .band
        // A held element joins the selection as the hold ends, and the
        // drag that follows moves the selection.
        case (.holdThenDrag, .element): return .move
        case (.hold, .element): return .toggleInSelection
        // A hold on the empty page let go without a drag draws no band,
        // and the view stays where it is.
        case (.hold, .emptyPage): return .nothing
        }
    }

    /// Whether one finger dragging from a point on the page, after holding
    /// still for `held` seconds, moves the view: only from the empty page,
    /// and only when it did not hold first.
    static func pansFromPage(onElement: Bool, held: Double) -> Bool {
        let input: Input = held >= holdSeconds ? .holdThenDrag : .drag
        return action(input, on: onElement ? .element : .emptyPage) == .pan
    }
}
