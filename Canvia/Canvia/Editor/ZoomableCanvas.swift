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
//   one finger on empty workspace pan the canvas      (backgroundPan, below)
//   two fingers anywhere          pan the canvas      (scroll view)
//   pinch anywhere                zoom the canvas     (scroll view)
//   double tap                    toggle fit / 2x     (scroll view)
//
// The scroll view's own pan is raised to two fingers so it never competes with
// dragging an element, and a separate one-finger recogniser handles panning
// from the empty workspace, refusing to begin when the touch lands on the page.

import SwiftUI
import UIKit

struct ZoomableCanvas<Content: View>: UIViewRepresentable {
    /// Size of the page in its own coordinate space.
    let contentSize: CGSize
    /// Mirrors the scroll view's zoomScale outward, so selection handles can
    /// stay a constant size on screen.
    @Binding var zoom: Double
    /// Changing this refits the page — a new document, or a resize.
    let fitToken: String
    /// Tapping the workspace outside the page.
    let onBackgroundTap: () -> Void
    /// The Apple Pencil's double tap, when the user has it set to do anything.
    let onPencilTap: () -> Void
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

        // One finger on the grey workspace pans; the delegate below refuses to
        // start it when the touch begins over the page itself.
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
        scroll.addGestureRecognizer(doubleTap)
        // A single tap should not wait on the double tap unless one is coming.
        backgroundTap.require(toFail: doubleTap)

        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.host.rootView = content()
        // Fitting below drives the scroll view, which calls back into
        // scrollViewDidZoom, which writes the zoom binding — a SwiftUI state
        // write in the middle of a SwiftUI update. See publishZoom.
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        if coordinator.contentSize != contentSize {
            coordinator.contentSize = contentSize
            coordinator.host.view.frame = CGRect(origin: .zero, size: contentSize)
            scroll.contentSize = contentSize
            coordinator.needsFit = true
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
        var contentSize: CGSize = .zero
        var fitToken: String = ""
        var needsFit = true
        /// True while updateUIView is running, so zoom changes it causes are
        /// published after the update rather than inside it.
        var isUpdating = false
        private var panOrigin: CGPoint = .zero

        init(_ parent: ZoomableCanvas) {
            self.parent = parent
            self.host = UIHostingController(rootView: parent.content())
            self.contentSize = parent.contentSize
            self.fitToken = parent.fitToken
            super.init()
            host.view.backgroundColor = .clear
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent()
            // Writing through the binding on every frame of a pinch is what
            // keeps the selection handles the right size while zooming.
            publishZoom(Double(scrollView.zoomScale))
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
            // dragged clear of the toolbars.
            let slackX = max((scroll.bounds.width - scaled.width) / 2, scroll.bounds.width / 2)
            let slackY = max((scroll.bounds.height - scaled.height) / 2, scroll.bounds.height / 2)
            let inset = UIEdgeInsets(top: slackY, left: slackX, bottom: slackY, right: slackX)
            if scroll.contentInset != inset { scroll.contentInset = inset }
        }

        func fitToScreen(animated: Bool) {
            guard let scroll = scrollView,
                  contentSize.width > 0, contentSize.height > 0,
                  scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
            let fit = Geometry.fitScale(content: contentSize, in: scroll.bounds.size)
            // Let the user zoom well past fit in both directions, but never so
            // far out that the page becomes a speck.
            scroll.minimumZoomScale = min(fit * 0.5, 0.05)
            scroll.maximumZoomScale = max(fit * 8, 4)
            scroll.setZoomScale(fit, animated: animated)
            centerContent()
            let scaled = CGSize(width: contentSize.width * fit, height: contentSize.height * fit)
            scroll.setContentOffset(
                Geometry.centeredOffset(scaledContent: scaled, in: scroll.bounds.size),
                animated: animated)
            publishZoom(Double(fit))
        }

        // MARK: gestures

        @objc func handleBackgroundPan(_ pan: UIPanGestureRecognizer) {
            guard let scroll = scrollView else { return }
            switch pan.state {
            case .began:
                panOrigin = scroll.contentOffset
            case .changed:
                let t = pan.translation(in: scroll)
                scroll.contentOffset = CGPoint(x: panOrigin.x - t.x, y: panOrigin.y - t.y)
            default:
                break
            }
        }

        @objc func handleBackgroundTap(_ tap: UITapGestureRecognizer) {
            parent.onBackgroundTap()
        }

        @objc func handleDoubleTap(_ tap: UITapGestureRecognizer) {
            guard let scroll = scrollView else { return }
            let fit = Geometry.fitScale(content: contentSize, in: scroll.bounds.size)
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

        /// The one-finger pan and the background tap belong to the workspace,
        /// not the page: refuse them when the touch lands on the page, so the
        /// SwiftUI gestures inside keep working untouched.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            !host.view.bounds.contains(touch.location(in: host.view))
        }
    }
}
