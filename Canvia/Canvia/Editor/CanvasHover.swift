// The outline under a pointer: with a trackpad, a mouse or an Apple Pencil
// hovering over the page, what a click there would select — by a tap's own
// rule, a group's box for a group — is outlined thinly in the selection
// colour, so you see what a click will take before you click. Never over
// what is already selected, nor while a drag, typing, a crop, the pen, the
// eraser or a brush has the page; gone 150 ms after the pointer leaves.
// Not part of the design or any export, and not read by VoiceOver.
// Settings ▸ Editing ▸ Outline under pointer turns it off. As on the
// Android twin.

import SwiftUI

enum HoverOutline {

    /// Settings ▸ Editing's "Outline under pointer": on unless turned off.
    /// A setting of the phone, never of the design.
    static let key = "canvia.hoverOutline"
    /// How long the outline stays once the pointer leaves, in milliseconds.
    static let lingerMs = 150

    /// What a click at `point` on the page would select, as a tap does
    /// (CanvasView.elementTap): the topmost shown element within
    /// `touchRadius` (Layers.touches); inside a selected group, the next
    /// level down (Groups.deeper); otherwise the element with every member
    /// of its group. Nil over the empty page.
    static func target(_ elements: [Element], selection: Set<String>, at point: CGPoint,
                       touchRadius: Double) -> Set<String>? {
        guard let hit = elements.last(where: { !$0.isHidden && Layers.touches($0, point, touchRadius: touchRadius) }) else {
            return nil
        }
        if let deeper = Groups.deeper(elements, selection: selection, tapped: hit.id) { return deeper }
        guard let group = hit.group else { return [hit.id] }
        return Set(elements.filter { $0.group == group }.map(\.id))
    }

    /// Whether the outline round `target` is drawn: not when the selection
    /// already holds all of it.
    static func shows(_ target: Set<String>, selection: Set<String>) -> Bool {
        !target.isEmpty && !target.isSubset(of: selection)
    }
}

/// Follows the pointer over the page and outlines what a click would take.
struct HoverTracking: ViewModifier {
    @Bindable var store: DesignStore
    @AppStorage(HoverOutline.key) private var on = true
    @State private var hovered: Set<String>?
    @State private var leaving: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay { outline }
            .onContinuousHover(coordinateSpace: .named("page")) { phase in track(phase) }
    }

    private func track(_ phase: HoverPhase) {
        switch phase {
        case .active(let point):
            leaving?.cancel()
            leaving = nil
            let radius = Touch.pageUnits(Touch.minTarget, zoom: store.zoom) / 2
            let next = on ? HoverOutline.target(store.page.elements, selection: store.selection, at: point,
                                                touchRadius: radius) : nil
            if next != hovered { hovered = next }
        case .ended:
            leaving?.cancel()
            leaving = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(HoverOutline.lingerMs))
                guard !Task.isCancelled else { return }
                hovered = nil
            }
        }
    }

    /// Nothing else has the page: no drag, typing, crop, pen, eraser or brush.
    private var quiet: Bool {
        !store.canvasTouchActive && store.editingTextId == nil && store.cropping == nil
            && store.graphicCropping == nil && store.drawing == nil && store.erasing == nil && store.brushing == nil
    }

    @ViewBuilder
    private var outline: some View {
        if on, quiet, let ids = hovered, HoverOutline.shows(ids, selection: store.selection) {
            let elements = store.page.elements.filter { ids.contains($0.id) && !$0.isHidden }
            let iz = 1 / max(store.zoom, 0.01)
            Canvas { context, _ in
                context.stroke(Self.path(elements), with: .color(Theme.accent.opacity(0.6)), lineWidth: iz)
            }
            .frame(width: store.pageWidth, height: store.pageHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// One element's own turned frame — a curve's round where it bows —
    /// or the upright box round several.
    private static func path(_ elements: [Element]) -> Path {
        guard elements.count == 1, let el = elements.first.map(LineRoutes.outlineOf) else {
            return Path(Geometry.union(elements.map(Geometry.aabb)))
        }
        let c = el.center
        let turn = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: CGFloat(el.rotation * .pi / 180))
            .translatedBy(x: -c.x, y: -c.y)
        return Path(el.frame).applying(turn)
    }
}
