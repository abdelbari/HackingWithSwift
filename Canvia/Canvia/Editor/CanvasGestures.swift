// What a touch on the canvas does, as one table both phones keep — Canva's
// model, and the Android twin's (its EditorViewModel.onLongPress and the
// marquee): one finger on an element moves it, one finger on the empty page
// moves the view, a hold on the empty page and then a drag draws the
// selection band, a hold there let go without a drag brings up the menu at
// the finger, a hold on an element adds it to the selection or takes it
// out, and two fingers pan and zoom anywhere. Inside what is selected — its
// body — a drag moves the selection even where something else lies on top
// of it, while a tap there still picks the topmost thing. The tests on both
// phones hold the same rows.

import CoreGraphics
import Foundation

enum CanvasGestures {

    /// How long a finger stays still on the empty page before a drag from
    /// there draws the band rather than moving the view, in seconds.
    static let holdSeconds = 0.4

    enum Input: CaseIterable {
        /// One finger, put down and lifted without moving.
        case tap
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
        /// An element that is not part of the selection's body there.
        case element
        case emptyPage
        /// Inside the selection (onSelectedBody), whatever lies on top.
        case selectedBody
    }

    enum Action: Equatable {
        /// The topmost element shown under the finger is selected.
        case select
        /// The selection goes.
        case deselect
        case move, pan, band, toggleInSelection
        /// The menu at the finger: Paste, Select all, Add text here…
        case menu
        case panAndZoom
    }

    static func action(_ input: Input, on target: Target) -> Action {
        switch (input, target) {
        case (.twoFingers, _): return .panAndZoom
        case (.tap, .emptyPage): return .deselect
        // A tap inside the selection still picks the topmost thing there,
        // so the element covering it can be tapped as before.
        case (.tap, .element), (.tap, .selectedBody): return .select
        case (.drag, .element), (.drag, .selectedBody): return .move
        case (.drag, .emptyPage): return .pan
        case (.holdThenDrag, .emptyPage): return .band
        // A held element joins the selection as the hold ends, and the
        // drag that follows moves the selection.
        case (.holdThenDrag, .element), (.holdThenDrag, .selectedBody): return .move
        case (.hold, .element), (.hold, .selectedBody): return .toggleInSelection
        // A hold on the empty page let go without a drag draws no band: it
        // brings up the menu at the finger.
        case (.hold, .emptyPage): return .menu
        }
    }

    /// Whether one finger dragging from a point on the page, after holding
    /// still for `held` seconds, moves the view: only from the empty page,
    /// and only when it did not hold first.
    static func pansFromPage(onElement: Bool, held: Double) -> Bool {
        let input: Input = held >= holdSeconds ? .holdThenDrag : .drag
        return action(input, on: onElement ? .element : .emptyPage) == .pan
    }

    /// Whether `point`, in page units, is inside the selection's body: one
    /// element free to move and shown, tested in its own turned frame; or
    /// several, any of them free to move, inside the box round them all —
    /// the box their handles are drawn on. A locked or hidden one alone has
    /// no body to drag.
    static func onSelectedBody(_ point: CGPoint, selected: [Element]) -> Bool {
        if selected.count == 1, let el = selected.first {
            guard !el.holdsPlace, !el.isHidden else { return false }
            let local = el.rotation == 0 ? point : Geometry.rotate(point, around: el.center, degrees: -el.rotation)
            return el.frame.contains(local)
        }
        guard selected.count > 1, selected.contains(where: { !$0.holdsPlace }) else { return false }
        return Geometry.union(selected.map(Geometry.aabb)).contains(point)
    }
}
