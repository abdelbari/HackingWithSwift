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
        /// The topmost element shown under the finger is selected, with its
        /// group — or nothing, where there is nothing: a tap on the empty
        /// page lets the selection go. The Android twin's SELECT.
        case select
        case move, pan, band, toggleInSelection
        /// The menu at the finger: Paste, Select all, Add text here…
        case menu
        case panAndZoom
    }

    static func action(_ input: Input, on target: Target) -> Action {
        switch (input, target) {
        case (.twoFingers, _): return .panAndZoom
        // A tap is the same everywhere: what is on top there, or nothing.
        // Inside the selection it still picks the topmost thing, so the
        // element covering it can be tapped as before.
        case (.tap, _): return .select
        case (.drag, .element), (.drag, .selectedBody): return .move
        case (.drag, .emptyPage): return .pan
        case (.holdThenDrag, .emptyPage): return .band
        // A held element joins the selection as the hold ends, and the
        // drag that follows moves the selection.
        case (.holdThenDrag, .element), (.holdThenDrag, .selectedBody): return .move
        // The selection's body is the selection under the finger, so a hold
        // there takes the selected thing under it out, as a hold on it does
        // where it is on top.
        case (.hold, .element), (.hold, .selectedBody): return .toggleInSelection
        // A hold on the empty page let go without a drag draws no band: it
        // brings up the menu at the finger.
        case (.hold, .emptyPage): return .menu
        }
    }

    /// How long a finger may stay down, in seconds, for a touch to be a tap
    /// that types: past it, the touch is on its way to a hold.
    static let tapSeconds = 0.3

    /// Whether a tap on an element — one that did not drag, the move's own
    /// slop — held down for `held` seconds starts typing in it, as a tap on
    /// a text box already selected does in Canva: the element is the only
    /// thing selected, its words can be typed in (unlocked), Select multiple
    /// is off, and the tap was quick. A first tap only selects.
    static func tapTypes(onlySelected: Bool, typable: Bool, selectingMultiple: Bool, held: Double) -> Bool {
        onlySelected && typable && !selectingMultiple && held < tapSeconds
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
    /// several, any of them free to move, inside the box round those free
    /// to move (bodyBox) — what a drag there moves, as the Android twin's
    /// groupBox. A locked or hidden one alone has no body to drag.
    static func onSelectedBody(_ point: CGPoint, selected: [Element]) -> Bool {
        if selected.count == 1, let el = selected.first {
            guard !el.holdsPlace, !el.isHidden else { return false }
            let local = el.rotation == 0 ? point : Geometry.rotate(point, around: el.center, degrees: -el.rotation)
            return el.frame.contains(local)
        }
        return bodyBox(selected)?.contains(point) ?? false
    }

    /// The body of several selected: the box round the turned bounds of
    /// those free to move — what is locked in place is not part of it. Nil
    /// for one thing or nothing, or when none of them is free.
    static func bodyBox(_ selected: [Element]) -> CGRect? {
        let members = selected.filter { !$0.holdsPlace }
        guard selected.count > 1, !members.isEmpty else { return nil }
        return Geometry.union(members.map(Geometry.aabb))
    }
}
