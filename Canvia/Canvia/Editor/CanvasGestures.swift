// What a touch on the canvas does, as one table both phones keep — Canva's
// model, and the Android twin's (its EditorViewModel.onLongPress and the
// marquee): one finger on an element moves it, one finger on the empty page
// moves the view, a hold on the empty page and then a drag draws the
// selection band, a hold there let go without a drag brings up the menu at
// the finger, a hold on an element adds it to the selection or takes it
// out, and two fingers pan and zoom anywhere. The same goes for a backdrop —
// a locked thing, or one that covers the page — and for the workspace round
// the page: a hold there and a drag draws the band, so a page covered by a
// full-bleed photo can still be band-selected, as in Canva. Inside what is selected — its
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
        /// The topmost thing there is a backdrop (isBackdrop): locked, or
        /// covering the page, and not selected.
        case backdrop
        /// The grey area off every page.
        case workspace
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
        /// The next page, or the one before (flingAction). The Android
        /// twin's STEP_PAGE.
        case stepPage
    }

    static func action(_ input: Input, on target: Target) -> Action {
        switch (input, target) {
        case (.twoFingers, _): return .panAndZoom
        // A tap is the same everywhere: what is on top there, or nothing.
        // Inside the selection it still picks the topmost thing, so the
        // element covering it can be tapped as before.
        case (.tap, _): return .select
        // A plain drag moves a backdrop as ever, and pans off the elements.
        case (.drag, .element), (.drag, .selectedBody), (.drag, .backdrop): return .move
        case (.drag, .emptyPage), (.drag, .workspace): return .pan
        case (.holdThenDrag, .emptyPage), (.holdThenDrag, .backdrop), (.holdThenDrag, .workspace): return .band
        // A held element joins the selection as the hold ends, and the
        // drag that follows moves the selection.
        case (.holdThenDrag, .element), (.holdThenDrag, .selectedBody): return .move
        // The selection's body is the selection under the finger, so a hold
        // there takes the selected thing under it out, as a hold on it does
        // where it is on top.
        case (.hold, .element), (.hold, .selectedBody): return .toggleInSelection
        // A hold on the empty page — or a backdrop, or the workspace — let
        // go without a drag draws no band: it brings up the menu at the
        // finger.
        case (.hold, .emptyPage), (.hold, .backdrop), (.hold, .workspace): return .menu
        }
    }

    // MARK: a swipe to the next page

    /// How fast a one-finger fling across the page must go to turn it, in
    /// points a second (the Android twin's dp a second).
    static let flingSpeed = 800.0

    /// How near the zoom that fits the page counts as fit: within 2%.
    static let fitSlack = 0.02

    /// What a one-finger drag let go at `velocityX` across, having gone `dx`
    /// across and `dy` down, does on `target`: with Scroll through pages off
    /// (`singlePage`), at the zoom that fits (within fitSlack of `fitZoom`),
    /// from the empty page or the workspace, faster than flingSpeed and more
    /// than twice as far across as down, it turns the page (stepPage) —
    /// never an undo step; anything else is the drag's own action, a pan,
    /// as today. As the Android twin's Gestures table.
    static func flingAction(on target: Target, velocityX: Double, dx: Double, dy: Double,
                            singlePage: Bool, zoom: Double, fitZoom: Double) -> Action {
        let atFit = fitZoom > 0 && abs(zoom / fitZoom - 1) <= fitSlack
        guard singlePage, atFit, target == .emptyPage || target == .workspace,
              abs(velocityX) > flingSpeed, abs(dx) > 2 * abs(dy) else { return action(.drag, on: target) }
        return .stepPage
    }

    /// Which way a page-turning fling goes: +1, the next page, for one to
    /// the left, -1 for one to the right — the other way round when the
    /// screen reads right to left. Pages keep the design's own order.
    static func pageStep(velocityX: Double, rightToLeft: Bool) -> Int {
        (velocityX < 0) != rightToLeft ? 1 : -1
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

    // MARK: the band from anywhere

    /// How much of the page's area a shown thing covers, at least, to be a
    /// backdrop: nine tenths.
    static let backdropCover = 0.9

    /// Whether `el` is a backdrop to a band on a page of `page` size: locked
    /// (wholly, not just in place), or shown and covering at least
    /// backdropCover of the page's area with its turned bounds — and not
    /// part of the `selection`, which a hold takes out instead. As the
    /// Android twin's Gestures.isBackdrop.
    static func isBackdrop(_ el: Element, page: CGSize, selection: Set<String>) -> Bool {
        if selection.contains(el.id) { return false }
        if el.locked { return true }
        guard !el.isHidden, page.width > 0, page.height > 0 else { return false }
        let b = Geometry.aabb(el)
        let w = min(b.maxX, page.width) - max(b.minX, 0)
        let h = min(b.maxY, page.height) - max(b.minY, 0)
        guard w > 0, h > 0 else { return false }
        return Double(w * h) >= backdropCover * Double(page.width * page.height)
    }

    /// What a band `rect` catches among `elements`: what it touches, whole
    /// groups and all, never a locked or hidden thing — and not `startedOn`,
    /// the backdrop it was drawn from, unless nothing else is caught, when
    /// it is that backdrop (and its group) alone.
    static func bandCaught(_ elements: [Element], rect: CGRect, startedOn: String?) -> Set<String> {
        let touched = Geometry.intersecting(elements, rect).filter { $0.id != startedOn }
        let caught = touched.isEmpty ? elements.filter { $0.id == startedOn && !$0.isHidden } : touched
        let groups = Set(caught.compactMap(\.group))
        let ids = Set(caught.map(\.id))
        return Set(elements.filter { ids.contains($0.id) || $0.group.map(groups.contains) == true }.map(\.id))
    }

    /// A band from the workspace, held to the page of `page` size it is
    /// drawn over: from `start` to `end`, each kept on the page.
    static func clampedBand(from start: CGPoint, to end: CGPoint, page: CGSize) -> CGRect {
        let a = onPage(start, page: page), b = onPage(end, page: page)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// `point` moved onto a page of `page` size, by the least.
    static func onPage(_ point: CGPoint, page: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), max(page.width, 0)), y: min(max(point.y, 0), max(page.height, 0)))
    }
}
