// The canvas viewport: a UIScrollView that owns zoom and pan, hosting the
// SwiftUI page inside it.
//
// Why UIKit for this one view. SwiftUI resolves gesture conflicts by nesting:
// a gesture on a child always outranks one attached to an ancestor with
// .gesture(). The page is covered by a transparent hit area per element, each
// carrying its own DragGesture, so a MagnifyGesture on the enclosing stack can
// never win — put two fingers down over any element and the element's drag
// claims the touch instead of the canvas zooming. That is exactly the reported
// symptom: "hard to zoom in and out of the whole image without touching the
// top layers", and it gets worse the more the page fills up.
//
// UIKit arbitrates by touch count instead of by nesting, which is the model
// every professional canvas app uses:
//
//   one finger on an element      move that element   (SwiftUI, inside)
//   one finger on empty page      pan the canvas      (backgroundPan, below)
//     or empty workspace
//   hold, then drag, empty page   draw the band       (SwiftUI, inside)
//   two fingers anywhere          pan the canvas      (scroll view)
//   pinch anywhere                zoom the canvas     (scroll view)
//   double tap                    toggle fit / 2x     (scroll view)
//
// Scrolling through pages (PageColumn), the content is the column of every
// page rather than the one page: "the page" above is the page being worked,
// one finger on another page or between pages scrolls the column, gliding
// on as it is let go, and a tap on another page is the canvas's, to make
// that page the one worked. One finger dragged from something on another
// page is the canvas's too: it makes that page the one worked and moves it.
//
// The scroll view's own pan is raised to two fingers so it never competes with
// dragging an element, and a separate one-finger recogniser handles panning
// from the empty workspace and the empty page — Canva's model and the
// Android twin's (see CanvasGestures). On the page it refuses a touch that
// lands on something to work, and a drag that began only after a hold, which
// is the band's.

import SwiftUI
import UIKit

/// A change of view asked of the canvas. Counted, so asking for the same
/// thing twice does it twice, and a canvas made afresh does not act on a
/// request it never saw.
struct CanvasRequest: Equatable {
    enum Kind: Equatable {
        /// The whole page, as a design opens.
        case fit
        /// This zoom, about the middle of the screen.
        case zoom(Double)
        /// Scroll just far enough that this box, in page units, is in sight —
        /// in the part of the canvas still showing when the bottom
        /// `covered` fraction of the window is under a sheet, and above the
        /// keyboard when one is up. While `typing`, the box's foot wins over
        /// its head, so the line being typed is the one kept in view.
        case reveal(CGRect, covered: Double = 0, typing: Bool = false)
    }
    var kind: Kind
    var serial: Int
}

/// The page being worked, when the canvas holds the column of every page
/// (PageColumn): where it lies in the content, in column units, how many of
/// those one page unit takes, and as many for the widest page, whose zoom
/// range is the column's.
struct CanvasColumn: Equatable {
    var page: CGRect
    var scale: Double
    var widest: Double
}

/// Where a one-finger drag from something on another page of the column
/// is (ZoomableCanvas.onOtherPageDrag).
enum CanvasDrag {
    case began, moved, ended
}

struct ZoomableCanvas<Content: View>: UIViewRepresentable {
    /// Size of the page in its own coordinate space.
    let contentSize: CGSize
    /// Mirrors the scroll view's zoomScale outward, so selection handles can
    /// stay a constant size on screen.
    @Binding var zoom: Double
    /// Changing this refits the page — a new document, or a resize.
    let fitToken: String
    /// Tapping the workspace outside the page, at this point of the content.
    let onBackgroundTap: (CGPoint) -> Void
    /// The Apple Pencil's double tap, when the user has it set to do anything.
    let onPencilTap: () -> Void
    /// Whether two fingers work the canvas — pinch to zoom, drag to pan. Off
    /// in crop mode, where a pinch zooms the picture instead.
    var pinchZooms = true
    /// Whether a double tap at this point on the page is the page's own — a
    /// photo opening crop, a text box its editor — rather than the canvas
    /// zooming. Without it, double-tapping a photo zoomed the canvas as well.
    var claimsDoubleTap: (CGPoint) -> Bool = { _ in false }
    /// Whether one finger dragged from this point on the page moves the
    /// view: nothing there to work.
    var pansFromPage: (CGPoint) -> Bool = { _ in false }
    /// The latest change of view asked for.
    var request: CanvasRequest? = nil
    /// Scrolling through pages: the page being worked in the column; nil
    /// when the content is that page alone.
    var column: CanvasColumn? = nil
    /// Whether this point of the content is one of the column's own buttons
    /// — a page's header, "+ Add page" — which keep their touches.
    var isControl: (CGPoint) -> Bool = { _ in false }
    /// Whether this point of the content is on something on a page other
    /// than the one worked, which one finger dragged from there moves
    /// rather than scrolling the column.
    var movesOtherPage: (CGPoint) -> Bool = { _ in false }
    /// That drag: where it landed and where the finger is now, in the
    /// content. Cut short, it is let go where it got to.
    var onOtherPageDrag: (CanvasDrag, CGPoint, CGPoint) -> Void = { _, _, _ in }
    /// Told the part of the page on screen, in page units, and the zoom that
    /// fits the page, whenever either changes.
    var onViewport: (CGRect, Double) -> Void = { _, _ in }
    /// Told when the view starts moving — a pan, a pinch, a glide — and when
    /// it comes to rest.
    var onMotion: (Bool) -> Void = { _ in }
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.backgroundColor = UIColor(Theme.workspace)
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.alwaysBounceVertical = true
        scroll.bouncesZoom = true
        scroll.decelerationRate = .fast
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.minimumZoomScale = 0.05
        scroll.maximumZoomScale = 8

        // Leave one-finger drags to the content, so dragging an element is
        // never mistaken for scrolling.
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2

        // Double-tapping the Pencil's barrel toggles the pen, the way it
        // switches tools in every drawing app.
        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        scroll.addInteraction(pencil)

        let host = context.coordinator.host
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(origin: .zero, size: contentSize)
        scroll.addSubview(host.view)
        scroll.contentSize = contentSize

        // One finger on the grey workspace or the empty page pans; the
        // delegate below refuses it a touch on something to work, or one held
        // before it moved.
        let backgroundPan = UIPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleBackgroundPan(_:)))
        backgroundPan.delegate = context.coordinator
        backgroundPan.maximumNumberOfTouches = 1
        scroll.addGestureRecognizer(backgroundPan)

        let backgroundTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleBackgroundTap(_:)))
        backgroundTap.delegate = context.coordinator
        scroll.addGestureRecognizer(backgroundTap)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        scroll.addGestureRecognizer(doubleTap)
        // A single tap should not wait on the double tap unless one is coming.
        backgroundTap.require(toFail: doubleTap)

        context.coordinator.scrollView = scroll
        context.coordinator.doubleTap = doubleTap
        context.coordinator.backgroundPan = backgroundPan
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.host.rootView = content()
        scroll.pinchGestureRecognizer?.isEnabled = pinchZooms
        scroll.panGestureRecognizer.isEnabled = pinchZooms
        // Fitting below drives the scroll view, which calls back into
        // scrollViewDidZoom, which writes the zoom binding — a SwiftUI state
        // write in the middle of a SwiftUI update. See publishZoom.
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        if coordinator.contentSize != contentSize {
            // The column of pages growing or shrinking down — a page added,
            // duplicated, deleted, or one of those undone — keeps the zoom
            // and the view where they are; only a new width fits afresh.
            let across = coordinator.contentSize.width == contentSize.width
            coordinator.contentSize = contentSize
            // By bounds and centre, not frame: the view is scaled by the
            // zoom, and a frame set on a scaled view is undefined — the
            // column of pages changes size with every page added.
            let z = scroll.zoomScale
            coordinator.host.view.bounds = CGRect(origin: .zero, size: contentSize)
            coordinator.host.view.center = CGPoint(x: contentSize.width * z / 2, y: contentSize.height * z / 2)
            scroll.contentSize = CGSize(width: contentSize.width * z, height: contentSize.height * z)
            if column != nil && across {
                // Which pages draw live, though the view has not moved.
                coordinator.publishViewport()
            } else {
                coordinator.needsFit = true
            }
        }
        if coordinator.fitToken != fitToken {
            coordinator.fitToken = fitToken
            coordinator.needsFit = true
        }
        // Laying out before the scroll view has a size would divide by zero.
        if coordinator.needsFit && scroll.bounds.width > 0 && scroll.bounds.height > 0 {
            coordinator.needsFit = false
            coordinator.fitToScreen(animated: false)
        }
        coordinator.centerContent()
        if let request, request.serial != coordinator.handledRequest {
            coordinator.handledRequest = request.serial
            coordinator.perform(request.kind)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        var parent: ZoomableCanvas

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            guard UIPencilInteraction.preferredTapAction != .ignore else { return }
            parent.onPencilTap()
        }
        let host: UIHostingController<Content>
        weak var scrollView: UIScrollView?
        weak var doubleTap: UITapGestureRecognizer?
        weak var backgroundPan: UIPanGestureRecognizer?
        /// When the touch the one-finger pan is following landed, and
        /// whether on the page, for telling a drag from a hold and a drag.
        private var panTouchStart: TimeInterval = 0
        private var panTouchOnPage = false
        /// Where the one-finger pan landed, in the content, when it landed on
        /// something on another page of the column and so moves that.
        private var otherPageStart: CGPoint?
        var contentSize: CGSize = .zero
        var fitToken: String = ""
        var needsFit = true
        /// True while updateUIView is running, so zoom changes it causes are
        /// published after the update rather than inside it.
        var isUpdating = false
        /// The serial of the last change of view acted on.
        var handledRequest = 0
        private var panOrigin: CGPoint = .zero
        /// Where the keyboard is, in screen coordinates, while one is up.
        private var keyboard: CGRect?

        init(_ parent: ZoomableCanvas) {
            self.parent = parent
            self.host = UIHostingController(rootView: parent.content())
            self.contentSize = parent.contentSize
            self.fitToken = parent.fitToken
            // A request made before this canvas existed is not for it.
            self.handledRequest = parent.request?.serial ?? 0
            super.init()
            host.view.backgroundColor = .clear
            // Selector observers: the centre holds them weakly, so there is
            // nothing to remove when the canvas goes.
            let centre = NotificationCenter.default
            centre.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            centre.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                               name: UIResponder.keyboardWillHideNotification, object: nil)
        }

        @objc private func keyboardWillChange(_ note: Notification) {
            keyboard = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        }

        @objc private func keyboardWillHide(_ note: Notification) {
            keyboard = nil
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent()
            // Writing through the binding on every frame of a pinch is what
            // keeps the selection handles the right size while zooming.
            publishZoom(Double(scrollView.zoomScale))
            publishViewport()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            publishViewport()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { publishMotion(true) }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { publishMotion(false) }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { publishMotion(false) }

        /// A glide cut short by a move asked for in code ends here instead.
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { publishMotion(false) }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { publishMotion(true) }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            publishMotion(false)
        }

        /// The view moving or at rest, told outward — after an update, as
        /// the zoom is, when one is under way.
        private func publishMotion(_ moving: Bool) {
            guard isUpdating else {
                parent.onMotion(moving)
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.parent.onMotion(moving)
            }
        }

        /// The part of the page on screen, and the zoom that fits it — for
        /// the zoom pill and the Bring it back chip. Deferred out of an
        /// update, as the zoom is.
        func publishViewport() {
            guard let scroll = scrollView, scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
            let visible = scroll.convert(scroll.bounds, to: host.view)
            let fit = Double(fitZoom(in: scroll))
            guard isUpdating else {
                parent.onViewport(visible, fit)
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.parent.onViewport(visible, fit)
            }
        }

        /// Acts on a change of view asked for from outside.
        func perform(_ kind: CanvasRequest.Kind) {
            guard let scroll = scrollView, scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
            switch kind {
            case .fit:
                fitToScreen(animated: true)
            case .zoom(let wanted):
                let target = min(max(CGFloat(wanted), scroll.minimumZoomScale), scroll.maximumZoomScale)
                let visible = scroll.convert(scroll.bounds, to: host.view)
                let size = CGSize(width: scroll.bounds.width / target, height: scroll.bounds.height / target)
                scroll.zoom(to: CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                       width: size.width, height: size.height),
                            animated: true)
            case .reveal(let box, let covered, let typing):
                // The least scroll that brings the box inside a margin of the
                // edges of what is still showing — the bottom and right
                // first, then the top and left, which win when the box is
                // bigger than that; while typing, the top first and the
                // bottom winning. Never a zoom, and never a move when it is
                // already in sight.
                let r = scroll.convert(box, from: host.view)
                let b = visibleBounds(of: scroll, covered: covered)
                let margin: CGFloat = 24
                guard b.height > margin * 2 else { return }
                var dx: CGFloat = 0, dy: CGFloat = 0
                if typing {
                    if r.minY < b.minY + margin { dy = b.minY + margin - r.minY }
                    if r.maxY + dy > b.maxY - margin { dy = b.maxY - margin - r.maxY }
                } else {
                    if r.maxY > b.maxY - margin { dy = b.maxY - margin - r.maxY }
                    if r.minY + dy < b.minY + margin { dy = b.minY + margin - r.minY }
                }
                if r.maxX > b.maxX - margin { dx = b.maxX - margin - r.maxX }
                if r.minX + dx < b.minX + margin { dx = b.minX + margin - r.minX }
                guard dx != 0 || dy != 0 else { return }
                let offset = CGPoint(x: scroll.contentOffset.x - dx, y: scroll.contentOffset.y - dy)
                scroll.setContentOffset(offset, animated: true)
            }
        }

        /// The scroll view's bounds, less what a sheet over the bottom
        /// `covered` fraction of the window hides, and less the keyboard.
        private func visibleBounds(of scroll: UIScrollView, covered: Double) -> CGRect {
            var b = scroll.bounds
            var bottom = b.maxY
            if covered > 0, let window = scroll.window {
                let top = CGPoint(x: 0, y: window.bounds.height * CGFloat(1 - min(max(covered, 0), 1)))
                bottom = min(bottom, scroll.convert(top, from: window).y)
            }
            if let keyboard, let screen = scroll.window?.screen {
                let local = scroll.convert(keyboard, from: screen.coordinateSpace)
                if local.intersects(b) { bottom = min(bottom, local.minY) }
            }
            b.size.height = max(bottom - b.minY, 0)
            return b
        }

        /// Mirror the scroll view's scale outward.
        ///
        /// Deferred when the change came from updateUIView — fitting a new
        /// document drives the scroll view, which calls back here, which would
        /// otherwise mutate SwiftUI state in the middle of a SwiftUI update.
        /// The fit itself stays synchronous: doing it a runloop later would
        /// show one frame of the page's top-left corner filling the screen
        /// before it snapped into place, on every design opened.
        private func publishZoom(_ scale: Double) {
            guard abs(parent.zoom - scale) > 0.0001 else { return }
            guard isUpdating else {
                parent.zoom = scale
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.parent.zoom - scale) > 0.0001 else { return }
                self.parent.zoom = scale
            }
        }

        /// A page smaller than the viewport sits in the middle rather than
        /// pinned to the top-left corner.
        func centerContent() {
            guard let scroll = scrollView else { return }
            let scaled = CGSize(width: contentSize.width * scroll.zoomScale,
                                height: contentSize.height * scroll.zoomScale)
            // Half a viewport of slack on every side, so the page can always be
            // dragged clear of the toolbars. The column has a gap round every
            // page of its own, so it only centres when it is the smaller.
            let least: CGFloat = parent.column == nil ? 0.5 : 0
            let slackX = max((scroll.bounds.width - scaled.width) / 2, scroll.bounds.width * least)
            let slackY = max((scroll.bounds.height - scaled.height) / 2, scroll.bounds.height * least)
            let inset = UIEdgeInsets(top: slackY, left: slackX, bottom: slackY, right: slackX)
            if scroll.contentInset != inset { scroll.contentInset = inset }
        }

        /// The zoom that fits: the whole page — or, scrolling through
        /// pages, the column across the width, which fits the widest page
        /// between the gutters.
        func fitZoom(in scroll: UIScrollView) -> CGFloat {
            guard parent.column != nil else { return Geometry.fitScale(content: contentSize, in: scroll.bounds.size) }
            return contentSize.width > 0 ? scroll.bounds.width / contentSize.width : 1
        }

        func fitToScreen(animated: Bool) {
            guard let scroll = scrollView,
                  contentSize.width > 0, contentSize.height > 0,
                  scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
            let fit = fitZoom(in: scroll)
            // Let the user zoom well past fit in both directions, but never so
            // far out that the page becomes a speck. The column's range is
            // the widest page's, whose zoom at the fit is its scale.
            let scale = parent.column?.widest ?? 1
            let range = Geometry.zoomRange(fit: Double(fit) * scale)
            scroll.minimumZoomScale = CGFloat(range.lowerBound / scale)
            scroll.maximumZoomScale = CGFloat(range.upperBound / scale)
            if let column = parent.column {
                // Across the width, from the top of the page being worked's
                // header and the gap over it.
                scroll.setZoomScale(fit, animated: animated)
                centerContent()
                let top = max(column.page.minY - PageColumn.room, 0) * fit
                scroll.setContentOffset(clamped(CGPoint(x: -scroll.contentInset.left, y: top), in: scroll),
                                        animated: animated)
                publishZoom(Double(fit))
                // Which pages draw live, though the view may not have moved.
                publishViewport()
                return
            }
            scroll.setZoomScale(fit, animated: animated)
            centerContent()
            let scaled = CGSize(width: contentSize.width * fit, height: contentSize.height * fit)
            scroll.setContentOffset(
                Geometry.centeredOffset(scaledContent: scaled, in: scroll.bounds.size),
                animated: animated)
            publishZoom(Double(fit))
        }

        /// `offset` kept to where the scroll view itself may go.
        private func clamped(_ offset: CGPoint, in scroll: UIScrollView) -> CGPoint {
            let inset = scroll.contentInset
            let maxX = max(scroll.contentSize.width + inset.right - scroll.bounds.width, -inset.left)
            let maxY = max(scroll.contentSize.height + inset.bottom - scroll.bounds.height, -inset.top)
            return CGPoint(x: min(max(offset.x, -inset.left), maxX), y: min(max(offset.y, -inset.top), maxY))
        }

        /// One finger let go of the column still moving: it glides on the way
        /// it was going, as a scroll view's own flick does, and comes to rest
        /// in the column — scrollViewDidEndScrollingAnimation says so.
        private func glide(_ scroll: UIScrollView, velocity: CGPoint) {
            // How far a flick carries, in seconds of its speed at let-go.
            let carry: CGFloat = 0.2
            let target = clamped(CGPoint(x: scroll.contentOffset.x - velocity.x * carry,
                                         y: scroll.contentOffset.y - velocity.y * carry), in: scroll)
            guard hypot(target.x - scroll.contentOffset.x, target.y - scroll.contentOffset.y) > 1 else {
                publishMotion(false)
                return
            }
            scroll.setContentOffset(target, animated: true)
        }

        // MARK: gestures

        @objc func handleBackgroundPan(_ pan: UIPanGestureRecognizer) {
            if let start = otherPageStart {
                moveOtherPage(pan, from: start)
                return
            }
            guard let scroll = scrollView else { return }
            switch pan.state {
            case .began:
                panOrigin = scroll.contentOffset
                publishMotion(true)
            case .changed:
                let t = pan.translation(in: scroll)
                scroll.contentOffset = CGPoint(x: panOrigin.x - t.x, y: panOrigin.y - t.y)
            case .ended where parent.column != nil:
                glide(scroll, velocity: pan.velocity(in: scroll))
            case .ended, .cancelled, .failed:
                publishMotion(false)
            default:
                break
            }
        }

        /// The one-finger pan moving something from another page of the
        /// column rather than the view.
        private func moveOtherPage(_ pan: UIPanGestureRecognizer, from start: CGPoint) {
            let now = pan.location(in: host.view)
            switch pan.state {
            case .began:
                parent.onOtherPageDrag(.began, start, now)
            case .changed:
                parent.onOtherPageDrag(.moved, start, now)
            case .ended, .cancelled, .failed:
                otherPageStart = nil
                parent.onOtherPageDrag(.ended, start, now)
            default:
                break
            }
        }

        @objc func handleBackgroundTap(_ tap: UITapGestureRecognizer) {
            parent.onBackgroundTap(tap.location(in: host.view))
        }

        @objc func handleDoubleTap(_ tap: UITapGestureRecognizer) {
            guard let scroll = scrollView else { return }
            let fit = fitZoom(in: scroll)
            if scroll.zoomScale > fit * 1.05 {
                fitToScreen(animated: true)
            } else {
                // Zoom in on the tapped point rather than the centre.
                let point = tap.location(in: host.view)
                let target = min(fit * 3, scroll.maximumZoomScale)
                let size = CGSize(width: scroll.bounds.width / target,
                                  height: scroll.bounds.height / target)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height),
                            animated: true)
            }
        }

        /// The background tap belongs to the workspace, not the page: it is
        /// refused a touch on the page, so the SwiftUI gestures inside keep
        /// working untouched. The one-finger pan takes the workspace and the
        /// page where there is nothing to work. The double tap zooms
        /// anywhere, except where the page claims it for itself.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            let content = touch.location(in: host.view)
            var point = content
            var onPage = host.view.bounds.contains(point)
            if let column = parent.column {
                // A header's buttons and "+ Add page" are left their taps.
                if parent.isControl(point) { return false }
                onPage = column.page.contains(point)
                point = CGPoint(x: (point.x - column.page.minX) / column.scale,
                                y: (point.y - column.page.minY) / column.scale)
            }
            if gestureRecognizer === doubleTap {
                return !(onPage && parent.claimsDoubleTap(point))
            }
            if gestureRecognizer === backgroundPan {
                // Moving something from another page, the pan is that one
                // finger's alone.
                if otherPageStart != nil && gestureRecognizer.state != .possible { return false }
                otherPageStart = nil
                // Scrolling through pages, a drag from something on another
                // page moves it, as a drag on the page worked does — that
                // page becoming the one worked (onOtherPageDrag) — unless
                // the page worked's own things hang over it there.
                if parent.column != nil && !onPage && parent.pansFromPage(point) && parent.movesOtherPage(content) {
                    otherPageStart = content
                    panTouchOnPage = false
                    return true
                }
                guard !onPage || parent.pansFromPage(point) else { return false }
                panTouchStart = touch.timestamp
                panTouchOnPage = onPage
                return true
            }
            return !onPage
        }

        /// On the page, a drag that waited for a hold before it moved is the
        /// band's, not the view's (CanvasGestures.holdSeconds).
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === backgroundPan, panTouchOnPage else { return true }
            let held = ProcessInfo.processInfo.systemUptime - panTouchStart
            return CanvasGestures.pansFromPage(onElement: false, held: held)
        }
    }
}
