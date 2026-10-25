// Selection overlay: outlines, resize handles, rotate handle, the move
// handle, a table's column edges, snap guides and the size/angle badge, and
// the selection's body, which a drag moves even where something lies on top
// of it. Rendered in page coordinates; visual sizes are divided by zoom so
// they stay constant on screen.

import SwiftUI

struct SelectionOverlay: View {
    @Bindable var store: DesignStore
    var onHandleDrag: (Handle, CGPoint) -> Void
    var onHandleEnd: () -> Void
    var onRotateDrag: (CGPoint) -> Void
    var onRotateEnd: () -> Void
    /// A drag on the selection's body or its move handle, from where it
    /// began to where the finger is, in page units: the selection moves as
    /// a drag on an element moves it. Let go, it ends there.
    var onMoveDrag: (CGPoint, CGPoint) -> Void = { _, _ in }
    var onMoveEnd: (CGPoint, CGPoint) -> Void = { _, _ in }
    /// A tap — `count` of them — on the selection's body, at this point,
    /// or a hold there: passed on to whatever is topmost where the finger
    /// is, as if it had landed on that thing itself (CanvasGestures: a tap
    /// inside the selection still picks the topmost thing).
    var onBodyTap: (CGPoint, Int) -> Void = { _, _ in }
    var onBodyHold: () -> Void = {}
    /// A finger landing on the body or lifting from it, for how long a tap
    /// there was down (a quick one on a text selected alone types in it).
    var onBodyPressing: (Bool) -> Void = { _ in }
    /// A line's start (true) or end (false) dragged to a point, in page
    /// units, and let go (LineRoutes).
    var onEndDrag: (Bool, CGPoint) -> Void = { _, _ in }
    var onEndDragEnd: (Bool) -> Void = { _ in }

    @Environment(\.colorSchemeContrast) private var contrast
    /// The badges and labels grow with Larger Text, by this much, up to
    /// accessibility2 (CanvasView caps the overlay); the handles keep their
    /// size, which is their reach.
    @ScaledMetric(relativeTo: .caption) private var badgeScale: Double = 1

    /// The handle a finger is working, where it took it relative to the
    /// handle, and the ring's outset then — held for the whole drag, since
    /// recomputed live the ring would slide in as the element grows and the
    /// handle would crawl out from under the thumb.
    private struct Held {
        var grab: HandleGrab
        var offset: CGPoint
        var outsetX: Double
        var outsetY: Double
        /// Where the touch that took it began.
        var start: CGPoint
    }
    @State private var held: Held?

    /// A line's end a finger is working: which, where it took it relative
    /// to the end, and where the touch began.
    private struct HeldEnd {
        var atStart: Bool
        var offset: CGPoint
        var start: CGPoint
    }
    @State private var heldEnd: HeldEnd?

    /// The bend handle a finger is working: where it took it relative to
    /// the handle, and where the touch began.
    private struct HeldBend {
        var offset: CGPoint
        var start: CGPoint
    }
    @State private var heldBend: HeldBend?

    /// A quick-flow + being dragged: which, and where the finger is.
    private struct FlowDrag {
        var side: QuickFlow.Side
        var at: CGPoint
    }
    @State private var flowDrag: FlowDrag?

    /// One of quick flow's +s: its side and where it sits, in page units.
    private struct FlowPoint: Identifiable {
        var side: QuickFlow.Side
        var at: CGPoint
        var id: QuickFlow.Side { side }
    }

    private var iz: Double { 1 / max(store.zoom, 0.01) }
    /// Settings ▸ Accessibility's Larger handles: the handles drawn 1.4
    /// times as big (AccessibilityPrefs), as Touch.handleReach takes them.
    @AppStorage(AccessibilityPrefs.largerHandlesKey) private var largerHandles = false
    private var handleScale: Double { AccessibilityPrefs.handleScale(larger: largerHandles) }
    /// Increase Contrast: heavier outlines, since a one-point accent line
    /// over a busy photo is exactly what that setting is asking to fix.
    private var weight: Double { contrast == .increased ? 1.8 : 1 }

    var body: some View {
        ZStack {
            let selected = store.selectedElements

            // Beneath the handles, over every element's own hit area.
            if let zone = Self.bodyZone(store) { bodyArea(zone) }

            ForEach(selected) { el in
                if el.isHidden {
                    dashedOutline(el, badge: "eye.slash.fill")
                } else if selected.count == 1 && el.holdsPlace {
                    // A padlock in outline for a position lock, filled for
                    // a whole one.
                    dashedOutline(el, badge: ElementLock.symbol(ElementLock.mode(of: el)))
                } else {
                    // A curve's outline goes round where it bows.
                    outline(LineRoutes.outlineOf(el), lineWidth: (selected.count > 1 ? 1 : 1.5) * weight)
                }
            }

            // Select multiple: a tick on everything in the selection.
            if store.selectingMultiple {
                ForEach(selected) { el in tick(el) }
            }

            if let el = store.singleSelection, !el.holdsPlace, !el.isHidden, store.editingTextId != el.id {
                // An elbowed or curved line stays level: no turn handle.
                if !LineRoutes.keepsLevel(el) { handleRing(for: el, handles: Touch.handleSet(for: el)) }
                // A line's ends, discs to drag in place of its stretch handles.
                if LineRoutes.hasEndHandles(el) { lineEnds(el) }
                // Its label, to slide along it.
                if el.type == .line, let box = LineLabels.rect(of: el) { labelSlide(box) }
            }
            Group {
                // A curved or elbowed line's middle: a diamond to bend it.
                if let el = store.bendLine, store.editingTextId != el.id, let at = LineRoutes.bendHandlePoint(el) {
                    bendHandle(at)
                }
                if let el = store.singleSelection,
                   Touch.showsMoveHandle(el, zoom: store.zoom, typing: store.editingTextId == el.id) {
                    moveHandle(el)
                }
                // Quick flow's +s, one a side, on a shape or sticky note.
                if let el = store.quickFlowSource, !store.canvasTouchActive || flowDrag != nil {
                    quickFlow(el)
                }
            }

            if selected.count > 1 { severalFrame(selected) }

            Group {
                // A whole table selected: its column edges, to drag.
                if let edges = store.tableColumnEdges {
                    TableColumnHandles(store: store, edges: edges)
                }
                // A table or a cell of it selected: its row edges, to drag.
                if let rows = store.tableRowEdges {
                    TableRowHandles(store: store, edges: rows)
                }
            }
            Group {
                // A whole photo grid selected: the dividers between its cells.
                if !store.gridDividers.isEmpty {
                    GridDividerHandles(store: store)
                }
                // Edit shape: a warp's handles, or a path's points.
                if !store.shapeHandles.isEmpty {
                    ShapeHandles(store: store)
                }
                // A star's, arrow's, callout's or notch's own handles.
                if !store.geometryHandles.isEmpty {
                    GeometryHandles(store: store)
                }
            }

            Group {
                guides
                spacingMarks
                distanceMarks
            }
            badgeView
        }
        .allowsHitTesting(!store.selection.isEmpty)
    }

    /// Round several selected: their box, dashed — turned with a whole
    /// group turned as one (store.turnedGroupFrame), tight round it, else
    /// upright — with its corner handles and turn handle, and how many.
    @ViewBuilder
    private func severalFrame(_ selected: [Element]) -> some View {
        let box = Self.severalBox(store, selected)
        let bounds = Geometry.aabb(box)
        Rectangle()
            .stroke(Theme.accent,
                    style: StrokeStyle(lineWidth: 1.5 * iz, dash: [6 * iz, 4 * iz]))
            .frame(width: box.w, height: box.h)
            .rotationEffect(.degrees(box.rotation))
            .position(x: box.x + box.w / 2, y: box.y + box.h / 2)
            .allowsHitTesting(false)
        // The group resizes and turns as one unit from its box.
        // Corners only: a uniform scale is the only one that keeps
        // rotated members exact (see Geometry.scale).
        if selected.contains(where: { !$0.holdsPlace }) {
            handleRing(for: box, handles: [.nw, .ne, .se, .sw])
        }
        // How many, over the box — but not while a drag's readout is
        // up there too.
        if store.badge == nil {
            pill(trn("%d selected|%d selected", selected.count), colour: Theme.accent,
                 at: CGPoint(x: bounds.midX, y: bounds.minY - 9 * iz), alignment: .bottom)
        }
    }

    /// The box round several selected, as a stand-in element: a turned
    /// group's turned frame, or the upright box round their turned bounds.
    private static func severalBox(_ store: DesignStore, _ selected: [Element]) -> Element {
        store.turnedGroupFrame?.element ?? Geometry.boxElement(Geometry.union(selected.map(Geometry.aabb)))
    }

    /// A locked element, selected on its own: a dashed outline, which says it
    /// will not move, and a padlock at its corner, which says why — rather
    /// than the solid outline that promised handles and then had none. A
    /// hidden one, picked in Layers, is the same outline round where it
    /// would be, with an eye struck through, and is still not drawn.
    private func dashedOutline(_ el: Element, badge: String) -> some View {
        let dash: [CGFloat] = [7 * iz, 5 * iz]
        let box = Geometry.aabb(el)
        return ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: 1 * iz)
                    .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 3.5 * iz * weight, dash: dash))
                RoundedRectangle(cornerRadius: 1 * iz)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5 * iz * weight, dash: dash))
            }
            .frame(width: el.w, height: el.h)
            .rotationEffect(.degrees(el.rotation))
            .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
            Image(systemName: badge)
                .font(.system(size: 11 * iz * badgeScale, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22 * iz * badgeScale, height: 22 * iz * badgeScale)
                .background(Circle().fill(Theme.accent))
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1 * iz))
                .position(x: box.minX, y: box.minY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Select multiple's tick: a 20-point disc at the top-right corner of
    /// the element's box, as the Android twin's 20dp one.
    private func tick(_ el: Element) -> some View {
        let box = Geometry.aabb(el)
        return Image(systemName: "checkmark")
            .font(.system(size: 10 * iz * badgeScale, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20 * iz * badgeScale, height: 20 * iz * badgeScale)
            .background(Circle().fill(Theme.accent))
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5 * iz))
            .position(x: box.maxX, y: box.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// A small label on the canvas, the same size on screen at any zoom,
    /// placed by one of its edges — `alignment` — at `point`.
    private func pill(_ text: String, colour: Color, at point: CGPoint, alignment: Alignment) -> some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: alignment) {
                Text(text)
                    .font(.system(size: 12.5 * iz * badgeScale, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9 * iz)
                    .padding(.vertical, 5.5 * iz)
                    .background(Capsule().fill(colour))
            }
            .position(point)
            .allowsHitTesting(false)
    }

    private func outline(_ el: Element, lineWidth: Double) -> some View {
        // Rounded by a hair: two square strokes meet in a miter that pokes
        // out past the corner handles.
        RoundedRectangle(cornerRadius: 1 * iz)
            .stroke(Theme.accent, lineWidth: lineWidth * iz)
            .frame(width: el.w, height: el.h)
            .rotationEffect(.degrees(el.rotation))
            .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
            .allowsHitTesting(false)
    }

    // MARK: handles

    /// The ring's outset on each axis, in page units: held while a handle is
    /// being dragged, otherwise what the element's size on screen needs.
    private func outsets(for el: Element) -> (x: Double, y: Double) {
        if let held { return (held.outsetX, held.outsetY) }
        return Self.outsets(for: el, zoom: store.zoom, page: Self.reachablePage(store))
    }

    /// What an element's size on screen needs of the ring's outset.
    private static func outsets(for el: Element, zoom: Double, page: CGRect) -> (x: Double, y: Double) {
        let x = Touch.handleOutset(side: el.w, zoom: zoom)
        let y = Touch.handleOutset(side: el.h, zoom: zoom)
        // Only the page takes a touch: a handle pushed past its edge would be
        // drawn where no finger can work it. Near an edge the ring stands off
        // only as far as keeps every handle on the page — on one axis, or on
        // neither, the handles then on the outline.
        for (ox, oy) in [(x, y), (x, 0), (0, y)] where ringFits(el, ox, oy, page: page) { return (ox, oy) }
        return ringFits(el, 0, 0, page: page) ? (0, 0) : (x, y)
    }

    /// The page, a hair wider, so a handle exactly on its edge counts.
    private static func reachablePage(_ store: DesignStore) -> CGRect {
        CGRect(x: 0, y: 0, width: store.pageWidth, height: store.pageHeight).insetBy(dx: -0.5, dy: -0.5)
    }

    /// What a finger can reach for the turn handle (Geometry.turnHandleSide):
    /// the part of the page in the canvas — which stops at the top bar, the
    /// bottom bar and the safe area — since only the page takes a touch;
    /// the whole page before the canvas has said what it shows.
    private static func reachable(_ store: DesignStore) -> CGRect {
        let page = reachablePage(store)
        let seen = store.viewport
        guard seen.width > 0, seen.height > 0 else { return page }
        let shown = page.intersection(seen.insetBy(dx: -0.5, dy: -0.5))
        return shown.isNull || shown.isEmpty ? page : shown
    }

    private static func ringFits(_ el: Element, _ outsetX: Double, _ outsetY: Double, page: CGRect) -> Bool {
        Handle.allCases.allSatisfy {
            page.contains(Geometry.handlePoint(el, $0, outsetX: outsetX, outsetY: outsetY))
        }
    }

    /// Where the rotate handle sits: below the bottom edge — and below the
    /// ring, when it stands off a small element — turned with the element;
    /// above the top edge instead when below is out of reach, where no
    /// finger could take it (turnSide).
    private func rotatePoint(_ el: Element, outsetY: Double) -> CGPoint {
        Self.rotatePoint(el, outsetY: outsetY, iz: iz, reach: Self.reachable(store))
    }

    private static func rotatePoint(_ el: Element, outsetY: Double, iz: Double, reach: CGRect) -> CGPoint {
        Geometry.rotateHandlePosition(el, offset: outsetY + 28 * iz,
                                      above: turnSide(el, outsetY: outsetY, iz: iz, reach: reach) == .above)
    }

    /// The side the turn and move handles take, 28 points beyond the ring
    /// (Geometry.turnHandleSide): below unless below is out of reach and
    /// above is not.
    private static func turnSide(_ el: Element, outsetY: Double, iz: Double, reach: CGRect) -> Geometry.TurnSide {
        Geometry.turnHandleSide(el, outsetY: outsetY, offset: 28 * iz, reachable: reach)
    }

    /// The side the turn and move handles are on for what is selected, for
    /// the quick actions to keep to the other (Geometry.bubbleAnchor);
    /// below when none is drawn.
    static func handlesSide(_ store: DesignStore) -> Geometry.TurnSide {
        guard let drawn = ring(store) else { return .below }
        let out = outsets(for: drawn.el, zoom: store.zoom, page: reachablePage(store))
        return turnSide(drawn.el, outsetY: out.y, iz: 1 / max(store.zoom, 0.01), reach: reachable(store))
    }

    /// What the handle ring is drawn round, and the handles it offers, as
    /// the body draws it: a single selection free to move, shown and not
    /// being typed in, with its own set; several, any of them free, as
    /// their box's corners. Nil when no handle is drawn.
    private static func ring(_ store: DesignStore) -> (el: Element, handles: [Handle])? {
        if let el = store.singleSelection {
            guard !el.holdsPlace, !el.isHidden, store.editingTextId != el.id, !LineRoutes.keepsLevel(el) else { return nil }
            return (el: el, handles: Touch.handleSet(for: el))
        }
        let selected = store.selectedElements
        guard selected.count > 1, selected.contains(where: { !$0.holdsPlace }) else { return nil }
        return (el: severalBox(store, selected), handles: [.nw, .ne, .se, .sw])
    }

    /// Whether a touch at `point`, in page units, is within reach of a
    /// handle drawn — the rotate handle and a whole table's column edges
    /// among them — and so the handles' rather than the empty page's. As on
    /// the Android twin, nothing else near the selection is: a locked one,
    /// which draws none, has none.
    static func handlesTake(_ point: CGPoint, store: DesignStore) -> Bool {
        if onColumnEdge(point, store: store) || onRowEdge(point, store: store) || onGridDivider(point, store: store) { return true }
        if ShapeHandles.takes(point, store: store) { return true }
        if GeometryHandles.takes(point, store: store) { return true }
        guard let drawn = ring(store) else { return false }
        let out = outsets(for: drawn.el, zoom: store.zoom, page: reachablePage(store))
        let rotateAt = rotatePoint(drawn.el, outsetY: out.y, iz: 1 / max(store.zoom, 0.01), reach: reachable(store))
        return Touch.grab(at: point, el: drawn.el, handles: drawn.handles,
                          outsetX: out.x, outsetY: out.y, rotateAt: rotateAt,
                          reach: Touch.pageUnits(Touch.handleReach, zoom: store.zoom),
                          inside: Touch.pageUnits(Touch.handleReachInside, zoom: store.zoom)) != nil
    }

    /// Whether a touch at `point`, in page units, is within reach of a
    /// selected line's end disc (lineEnds), so the view's own pan leaves it
    /// to the disc.
    static func lineEndsTake(_ point: CGPoint, store: DesignStore) -> Bool {
        guard let el = store.singleSelection, !el.holdsPlace, !el.isHidden,
              LineRoutes.hasEndHandles(el) else { return false }
        let ends = LineRoutes.ends(of: el)
        let reach = Touch.pageUnits(Touch.handleReach, zoom: store.zoom)
        return [ends.start, ends.end].contains { Double(hypot($0.x - point.x, $0.y - point.y)) <= reach }
    }

    /// Whether a touch at `point`, in page units, is on a selected line's
    /// label (labelSlide), so the view's own pan leaves it to the label.
    static func labelTakes(_ point: CGPoint, store: DesignStore) -> Bool {
        guard let el = store.slidableLabelLine, !el.isHidden, store.editingTextId != el.id,
              let box = LineLabels.rect(of: el) else { return false }
        return box.contains(point)
    }

    /// Whether a touch at `point`, in page units, is within reach of the
    /// move handle, when the selection has one (Touch.showsMoveHandle) — so
    /// the view's own pan leaves it to the handle, as handlesTake leaves the
    /// rotate handle.
    static func moveHandleTakes(_ point: CGPoint, store: DesignStore) -> Bool {
        guard let el = store.singleSelection,
              Touch.showsMoveHandle(el, zoom: store.zoom, typing: store.editingTextId == el.id) else { return false }
        let iz = 1 / max(store.zoom, 0.01)
        let outsetY = outsets(for: el, zoom: store.zoom, page: reachablePage(store)).y
        let above = turnSide(el, outsetY: outsetY, iz: iz, reach: reachable(store)) == .above
        let at = Geometry.moveHandlePosition(el, offset: outsetY + 28 * iz, above: above)
        let reach = Touch.pageUnits(Touch.handleReach, zoom: store.zoom)
        return hypot(Double(point.x - at.x), Double(point.y - at.y)) <= reach
    }

    /// The selection's body, in page units, where a drag moves the
    /// selection whatever lies on top (CanvasGestures.onSelectedBody): one
    /// element free to move, shown and not being typed in, as its turned
    /// frame; several, any of them free, as the box round those free to move
    /// (CanvasGestures.bodyBox). Nil when there is none — and in Select
    /// multiple, where a drag from a thing takes it in with the rest and a
    /// drag from the gap pans, as on the Android twin.
    static func bodyZone(_ store: DesignStore) -> CGPath? {
        guard !store.selectingMultiple else { return nil }
        if let el = store.singleSelection {
            guard !el.holdsPlace, !el.isHidden, store.editingTextId != el.id else { return nil }
            let c = el.center
            var turn = CGAffineTransform(translationX: c.x, y: c.y)
                .rotated(by: CGFloat(el.rotation * .pi / 180))
                .translatedBy(x: -c.x, y: -c.y)
            return CGPath(rect: el.frame, transform: &turn)
        }
        guard let box = CanvasGestures.bodyBox(store.selectedElements) else { return nil }
        return CGPath(rect: box, transform: nil)
    }

    /// Whether a touch at `point`, in page units, is the selection's body's.
    static func bodyTakes(_ point: CGPoint, store: DesignStore) -> Bool {
        guard bodyZone(store) != nil else { return false }
        return CanvasGestures.onSelectedBody(point, selected: store.selectedElements)
    }

    /// Whether `point` is on a grid divider's handle (GridDividerHandles):
    /// a touch target square centred on the divider's middle.
    private static func onGridDivider(_ point: CGPoint, store: DesignStore) -> Bool {
        let half = Touch.pageUnits(Touch.minTarget, zoom: store.zoom) / 2
        return store.gridDividers.contains { abs(Double(point.x - $0.at.x)) <= half && abs(Double(point.y - $0.at.y)) <= half }
    }

    /// Whether `point` is on a column edge's handle (TableColumnHandles):
    /// a touch target square centred on the table's foot, so half of it
    /// hangs below the table over the page.
    private static func onColumnEdge(_ point: CGPoint, store: DesignStore) -> Bool {
        guard let edges = store.tableColumnEdges else { return false }
        let half = Touch.pageUnits(Touch.minTarget, zoom: store.zoom) / 2
        guard abs(Double(point.y) - edges.bottom) <= half else { return false }
        return edges.xs.contains { abs(Double(point.x) - $0) <= half }
    }

    /// Whether `point` is on a row edge's handle (TableRowHandles): a touch
    /// target square centred where the row's bottom edge meets the table's
    /// left.
    private static func onRowEdge(_ point: CGPoint, store: DesignStore) -> Bool {
        guard let edges = store.tableRowEdges else { return false }
        let half = Touch.pageUnits(Touch.minTarget, zoom: store.zoom) / 2
        guard abs(Double(point.x) - edges.left) <= half else { return false }
        return edges.ys.contains { abs(Double(point.y) - $0) <= half }
    }

    /// Every handle the element offers, at any size or zoom. On a small or
    /// zoomed-out element the ring stands off the outline, joined to it by a
    /// short leader, so neighbouring handles stay a finger apart — as on the
    /// Android twin, where the old answer of hiding handles left a small
    /// element resizable only by numbers. One touch area takes them all and
    /// hands a touch to the nearest handle; see Touch.grab.
    private func handleRing(for el: Element, handles: [Handle]) -> some View {
        let out = outsets(for: el)
        let rotateAt = rotatePoint(el, outsetY: out.y)
        return ZStack {
            if out.x > 0 || out.y > 0 { leaders(el, handles: handles, outsetX: out.x, outsetY: out.y) }
            ForEach(handles, id: \.rawValue) { handle in
                handleDot(handle, at: Geometry.handlePoint(el, handle, outsetX: out.x, outsetY: out.y))
            }
            rotateGlyph(el, at: rotateAt)
            touchArea(el, handles: handles, outsetX: out.x, outsetY: out.y, rotateAt: rotateAt)
        }
    }

    /// Faint ticks from the outline out to each handle standing off it.
    private func leaders(_ el: Element, handles: [Handle], outsetX: Double, outsetY: Double) -> some View {
        let width = 1 * iz
        return Canvas { context, _ in
            var path = Path()
            for handle in handles {
                path.move(to: Geometry.handlePoint(el, handle))
                path.addLine(to: Geometry.handlePoint(el, handle, outsetX: outsetX, outsetY: outsetY))
            }
            context.stroke(path, with: .color(Theme.accent.opacity(0.55)), lineWidth: width)
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .allowsHitTesting(false)
    }

    private func handleDot(_ handle: Handle, at point: CGPoint) -> some View {
        let size = (handle.isCorner ? 11.0 : 9.0) * iz * handleScale
        return Circle()
            .fill(Color.white)
            // A coloured ring on white already separates the handle from the
            // page. The old grey ring plus a drop shadow made them read as
            // beads sitting on top of the design rather than part of the tool.
            .overlay(Circle().stroke(Theme.accent.opacity(0.9), lineWidth: 1 * iz))
            .frame(width: size, height: size)
            .position(point)
            .allowsHitTesting(false)
    }

    private func rotateGlyph(_ el: Element, at point: CGPoint) -> some View {
        // Was arrow.triangle.2.circlepath — the refresh/sync glyph, so the
        // control for rotating your text read as a reload button.
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 11 * iz * handleScale, weight: .semibold))
            .foregroundStyle(Theme.accent)
            // Track the element's angle, so the affordance says which way is up.
            .rotationEffect(.degrees(el.rotation))
            .frame(width: 24 * iz * handleScale, height: 24 * iz * handleScale)
            .background(Circle().fill(Color.white)
                .overlay(Circle().stroke(Theme.accent.opacity(0.9), lineWidth: 1 * iz)))
            .position(point)
            .allowsHitTesting(false)
    }

    /// The one place the handles take touches: a circle of reach round each
    /// handle and the rotate handle, less the element's body except right
    /// by a handle — so a touch on a small element's body still moves it.
    /// Everywhere else falls through to the elements beneath.
    private func touchArea(_ el: Element, handles: [Handle], outsetX: Double, outsetY: Double,
                           rotateAt: CGPoint) -> some View {
        let reach = Touch.pageUnits(Touch.handleReach, zoom: store.zoom)
        let inside = Touch.pageUnits(Touch.handleReachInside, zoom: store.zoom)
        let points = handles.map { Geometry.handlePoint(el, $0, outsetX: outsetX, outsetY: outsetY) }
        let zone = Self.touchZone(el, points: points, rotateAt: rotateAt, reach: reach, inside: inside)
        return Color.clear
            .frame(width: store.pageWidth, height: store.pageHeight)
            .contentShape(Path(zone))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
                    .onChanged { value in
                        // A drag the system cancelled — a call, Notification
                        // Center — never ends: a touch that starts somewhere
                        // else is a new one, so the old handle is let go and
                        // its step closed first, never worked again with a
                        // stale grip.
                        if let old = held, old.start != value.startLocation {
                            held = nil
                            end(old.grab)
                        }
                        if held == nil {
                            guard let grab = Touch.grab(at: value.startLocation, el: el, handles: handles,
                                                        outsetX: outsetX, outsetY: outsetY, rotateAt: rotateAt,
                                                        reach: reach, inside: inside) else { return }
                            // Against the handle on the outline, not the one
                            // drawn off it, so the first frame neither jumps
                            // the edge to the finger nor grows the element by
                            // the outset.
                            var offset = CGPoint.zero
                            if case .resize(let handle) = grab {
                                let edge = Geometry.handlePoint(el, handle)
                                offset = CGPoint(x: edge.x - value.startLocation.x, y: edge.y - value.startLocation.y)
                            }
                            held = Held(grab: grab, offset: offset, outsetX: outsetX, outsetY: outsetY,
                                        start: value.startLocation)
                        }
                        guard let held else { return }
                        switch held.grab {
                        case .resize(let handle):
                            onHandleDrag(handle, CGPoint(x: value.location.x + held.offset.x,
                                                         y: value.location.y + held.offset.y))
                        case .rotate:
                            onRotateDrag(value.location)
                        }
                    }
                    .onEnded { _ in
                        let grab = held?.grab
                        held = nil
                        if let grab { end(grab) }
                    }
            )
    }

    // MARK: a line's ends

    /// A selected line's two ends, each a disc to drag anywhere while the
    /// other holds (LineRoutes.endDragged): a circle of reach round each
    /// takes the touch, the nearer end when they overlap.
    private func lineEnds(_ el: Element) -> some View {
        let ends = LineRoutes.ends(of: el)
        let reach = Touch.pageUnits(Touch.handleReach, zoom: store.zoom)
        let zone = CGMutablePath()
        for p in [ends.start, ends.end] {
            zone.addEllipse(in: CGRect(x: p.x - reach, y: p.y - reach, width: reach * 2, height: reach * 2))
        }
        return ZStack {
            endDisc(at: ends.start)
            endDisc(at: ends.end)
            Color.clear
                .frame(width: store.pageWidth, height: store.pageHeight)
                .contentShape(Path(zone))
                .gesture(endDrag(ends))
        }
    }

    private func endDrag(_ ends: (start: CGPoint, end: CGPoint)) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
            .onChanged { value in
                // A touch that starts somewhere else is a new one: the old
                // end is let go and its step closed first.
                if let old = heldEnd, old.start != value.startLocation {
                    heldEnd = nil
                    onEndDragEnd(old.atStart)
                }
                if heldEnd == nil {
                    let p = value.startLocation
                    let toStart = Double(hypot(ends.start.x - p.x, ends.start.y - p.y))
                    let toEnd = Double(hypot(ends.end.x - p.x, ends.end.y - p.y))
                    let atStart = toStart <= toEnd
                    let at = atStart ? ends.start : ends.end
                    // Held where the finger landed against the end, so the
                    // first frame does not jump the end to the finger.
                    heldEnd = HeldEnd(atStart: atStart, offset: CGPoint(x: at.x - p.x, y: at.y - p.y), start: p)
                }
                guard let heldEnd else { return }
                onEndDrag(heldEnd.atStart, CGPoint(x: value.location.x + heldEnd.offset.x,
                                                   y: value.location.y + heldEnd.offset.y))
            }
            .onEnded { _ in
                let was = heldEnd
                heldEnd = nil
                if let was { onEndDragEnd(was.atStart) }
            }
    }

    /// A selected line's label: a drag on its words slides it along the
    /// line (DesignStore.slideLabel), held on the middle, one step a drag.
    private func labelSlide(_ box: CGRect) -> some View {
        Color.clear
            .frame(width: box.width, height: box.height)
            .contentShape(Rectangle())
            .position(x: box.midX, y: box.midY)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
                .onChanged { value in store.slideLabel(to: value.location) }
                .onEnded { _ in store.commit() })
    }

    /// A line's end: a white disc ringed in the accent, larger than a
    /// stretch handle, so it reads as the end itself.
    private func endDisc(at point: CGPoint) -> some View {
        let size = 14.0 * iz * handleScale
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Theme.accent, lineWidth: 2 * iz))
            .frame(width: size, height: size)
            .position(point)
            .allowsHitTesting(false)
    }

    // MARK: a line's bend

    /// The handle in the middle of a curved or elbowed line
    /// (LineRoutes.bendHandlePoint): a hollow diamond 14 points across,
    /// dragged to bend the curve or move the elbow's corner, live, the whole
    /// drag one step (DesignStore.dragLineBend). Over the body and the end
    /// discs, so it takes its touches first.
    private func bendHandle(_ at: CGPoint) -> some View {
        let half = 7.0 * iz * handleScale
        let reach = Touch.pageUnits(Touch.handleReach, zoom: store.zoom)
        let diamond = Path { p in
            p.move(to: CGPoint(x: at.x, y: at.y - half))
            p.addLine(to: CGPoint(x: at.x + half, y: at.y))
            p.addLine(to: CGPoint(x: at.x, y: at.y + half))
            p.addLine(to: CGPoint(x: at.x - half, y: at.y))
            p.closeSubpath()
        }
        return ZStack {
            diamond.stroke(Color.white, lineWidth: 4 * iz).allowsHitTesting(false)
            diamond.stroke(Theme.accent, lineWidth: 2 * iz).allowsHitTesting(false)
            Color.clear
                .contentShape(Path(ellipseIn: CGRect(x: at.x - reach, y: at.y - reach, width: reach * 2, height: reach * 2)))
                .gesture(bendDrag(at))
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .accessibilityHidden(true)
    }

    private func bendDrag(_ at: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
            .onChanged { value in
                // A touch that starts somewhere else is a new one: the old
                // drag's step closed first.
                if let old = heldBend, old.start != value.startLocation {
                    heldBend = nil
                    store.endLineBend()
                }
                if heldBend == nil {
                    // Held where the finger landed against the handle, so
                    // the first frame does not jump the bend to the finger.
                    let p = value.startLocation
                    heldBend = HeldBend(offset: CGPoint(x: at.x - p.x, y: at.y - p.y), start: p)
                    store.beginLineBend()
                }
                guard let heldBend else { return }
                store.dragLineBend(to: CGPoint(x: value.location.x + heldBend.offset.x,
                                               y: value.location.y + heldBend.offset.y))
            }
            .onEnded { _ in
                guard heldBend != nil else { return }
                heldBend = nil
                store.endLineBend()
            }
    }

    /// Whether a touch at `point`, in page units, is within reach of the
    /// bend handle, so the view's own pan leaves it to the handle.
    static func lineBendTakes(_ point: CGPoint, store: DesignStore) -> Bool {
        guard let el = store.bendLine, store.editingTextId != el.id,
              let at = LineRoutes.bendHandlePoint(el) else { return false }
        return Double(hypot(at.x - point.x, at.y - point.y)) <= Touch.pageUnits(Touch.handleReach, zoom: store.zoom)
    }

    // MARK: quick flow

    /// Where each side's + sits: 20 points beyond the handle ring, which on
    /// the turn handle's side reaches past the turn handle (28 points out,
    /// 12 across its half), so the + never covers it.
    private static func flowPoints(_ el: Element, store: DesignStore) -> [FlowPoint] {
        let iz = 1 / max(store.zoom, 0.01)
        let out = outsets(for: el, zoom: store.zoom, page: reachablePage(store))
        let turn: QuickFlow.Side = turnSide(el, outsetY: out.y, iz: iz, reach: reachable(store)) == .above ? .top : .bottom
        let beyond = (QuickFlow.discGap + QuickFlow.discSize / 2) * iz
        return QuickFlow.Side.allCases.map { side in
            let across = side == .left || side == .right
            var distance = (across ? out.x : out.y) + beyond
            if side == turn { distance += (28 + 12) * iz }
            return FlowPoint(side: side, at: QuickFlow.discPoint(el, side: side, distance: distance))
        }
    }

    /// Quick flow's four +s round a shape or sticky note: a tap adds a
    /// connected copy that way (DesignStore.addConnected); a drag draws the
    /// connector to the finger, let go on an element to tie to it or on
    /// empty space to put the copy there (DesignStore.quickFlowDrop).
    /// VoiceOver has the same as actions on the shape.
    private func quickFlow(_ el: Element) -> some View {
        let points = Self.flowPoints(el, store: store)
        return ZStack {
            if let drag = flowDrag {
                flowLine(from: QuickFlow.discPoint(el, side: drag.side, distance: 0), to: drag.at)
            }
            ForEach(points) { point in flowDisc(point.side, at: point.at) }
        }
    }

    /// A + 22 points across, in the accent, its touch target 44.
    private func flowDisc(_ side: QuickFlow.Side, at point: CGPoint) -> some View {
        let size = QuickFlow.discSize * iz
        let target = Touch.minTarget * iz
        return Image(systemName: "plus")
            .font(.system(size: 11 * iz, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.accent))
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5 * iz))
            .frame(width: target, height: target)
            .contentShape(Circle())
            .onTapGesture { store.addConnected(side) }
            .gesture(flowDragGesture(side))
            .position(point)
            .accessibilityHidden(true)
    }

    private func flowDragGesture(_ side: QuickFlow.Side) -> some Gesture {
        DragGesture(minimumDistance: Touch.pageUnits(Touch.dragSlop, zoom: store.zoom), coordinateSpace: .named("page"))
            .onChanged { value in flowDrag = FlowDrag(side: side, at: value.location) }
            .onEnded { value in
                flowDrag = nil
                store.quickFlowDrop(at: value.location)
            }
    }

    /// The connector being drawn from a +, dashed, to the finger.
    private func flowLine(from start: CGPoint, to end: CGPoint) -> some View {
        Path { p in
            p.move(to: start)
            p.addLine(to: end)
        }
        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2 * iz, dash: [6 * iz, 4 * iz]))
        .frame(width: store.pageWidth, height: store.pageHeight)
        .allowsHitTesting(false)
    }

    /// Whether a touch at `point`, in page units, is on one of quick
    /// flow's +s, so the view's own pan leaves it to them.
    static func quickFlowTakes(_ point: CGPoint, store: DesignStore) -> Bool {
        guard let el = store.quickFlowSource else { return false }
        let half = Touch.pageUnits(Touch.minTarget, zoom: store.zoom) / 2
        return flowPoints(el, store: store).contains { Double(hypot($0.at.x - point.x, $0.at.y - point.y)) <= half }
    }

    // MARK: body and move handle

    /// The selection's body, over the elements' own hit areas: a drag there
    /// moves the selection, even where an overlay or a clear text box lies
    /// on top of it — a photo under a tint, say. Taps and holds are passed
    /// on to the topmost thing there, so the thing on top is still tapped
    /// as before. Not for VoiceOver, whose actions move the selection.
    private func bodyArea(_ zone: CGPath) -> some View {
        Color.clear
            .frame(width: store.pageWidth, height: store.pageHeight)
            .contentShape(Path(zone))
            .onTapGesture(count: 2, coordinateSpace: .named("page")) { onBodyTap($0, 2) }
            .onTapGesture(count: 1, coordinateSpace: .named("page")) { onBodyTap($0, 1) }
            .onLongPressGesture(minimumDuration: CanvasGestures.holdSeconds,
                                perform: { onBodyHold() }, onPressingChanged: onBodyPressing)
            // As far on the glass as an element's own drag waits, so a tap
            // that wanders a little is still a tap.
            .gesture(moveDrag(after: Touch.dragSlop))
            .accessibilityHidden(true)
    }

    /// The selection moved by a drag on its body or its move handle, once
    /// the finger has gone `slop` points on the glass.
    private func moveDrag(after slop: Double) -> some Gesture {
        DragGesture(minimumDistance: Touch.pageUnits(slop, zoom: store.zoom), coordinateSpace: .named("page"))
            .onChanged { value in onMoveDrag(value.startLocation, value.location) }
            .onEnded { value in onMoveEnd(value.startLocation, value.location) }
    }

    /// Four-way arrows beside the rotate handle, on its side, for a small
    /// element or one being typed into: dragged, the selection moves without
    /// a finger over it, the finger kept where it took the handle.
    private func moveHandle(_ el: Element) -> some View {
        let outsetY = outsets(for: el).y
        let offset = outsetY + 28 * iz
        let above = Self.turnSide(el, outsetY: outsetY, iz: iz, reach: Self.reachable(store)) == .above
        let size = Touch.moveHandleSize * iz
        return Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 12 * iz, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white)
                .overlay(Circle().stroke(Theme.accent.opacity(0.9), lineWidth: 1 * iz)))
            .contentShape(Circle())
            .gesture(moveDrag(after: 1))
            .position(Geometry.moveHandlePosition(el, offset: offset, above: above))
            .accessibilityHidden(true)
    }

    private func end(_ grab: HandleGrab) {
        switch grab {
        case .resize: onHandleEnd()
        case .rotate: onRotateEnd()
        }
    }

    /// The handles' touch area as a path, in page units.
    private static func touchZone(_ el: Element, points: [CGPoint], rotateAt: CGPoint,
                                  reach: Double, inside: Double) -> CGPath {
        let far = CGMutablePath()
        let near = CGMutablePath()
        for p in points + [rotateAt] {
            far.addEllipse(in: CGRect(x: p.x - reach, y: p.y - reach, width: reach * 2, height: reach * 2))
        }
        for p in points {
            near.addEllipse(in: CGRect(x: p.x - inside, y: p.y - inside, width: inside * 2, height: inside * 2))
        }
        let c = el.center
        var turn = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: CGFloat(el.rotation * .pi / 180))
            .translatedBy(x: -c.x, y: -c.y)
        let body = CGPath(rect: el.frame, transform: &turn)
        return far.subtracting(body).union(near)
    }

    // MARK: guides + badge

    /// Each snap line, named for what it lines the selection up with —
    /// "Centre of the page", "Lined up with heading: SALE", "Your guide" —
    /// at the end of the line away from the selection, so the label is never
    /// under the finger. A guide of the person's own is teal, the rest
    /// magenta, and the page's centre gets a dot where its lines cross.
    @ViewBuilder
    private var guides: some View {
        let focus = store.selectionBox ?? CGRect(x: store.pageWidth / 2, y: store.pageHeight / 2, width: 0, height: 0)
        let reach = 24 * iz
        if let x = store.guideX {
            let source = store.guideXSource
            let colour = source == .guide ? Theme.userGuide : Theme.guide
            Rectangle()
                .fill(colour)
                .frame(width: 1.5 * iz, height: store.pageHeight + 2 * reach)
                .position(x: x, y: store.pageHeight / 2)
                .allowsHitTesting(false)
            if let source {
                let above = focus.midY >= store.pageHeight / 2
                let gap: Double = reach + 9 * iz
                let end: Double = above ? -gap : store.pageHeight + gap
                let label = ElementNames.guideLabel(source, vertical: true, elements: store.page.elements)
                pill(label, colour: colour, at: CGPoint(x: x, y: end), alignment: above ? .bottom : .top)
            }
            if source == .pageCentre { centreDot(colour) }
        }
        if let y = store.guideY {
            let source = store.guideYSource
            let colour = source == .guide ? Theme.userGuide : Theme.guide
            Rectangle()
                .fill(colour)
                .frame(width: store.pageWidth + 2 * reach, height: 1.5 * iz)
                .position(x: store.pageWidth / 2, y: y)
                .allowsHitTesting(false)
            if let source {
                let right = focus.midX <= store.pageWidth / 2
                let inset: Double = reach - 9 * iz
                let end: Double = right ? store.pageWidth + inset : -inset
                let label = ElementNames.guideLabel(source, vertical: false, elements: store.page.elements)
                pill(label, colour: colour, at: CGPoint(x: end, y: y - 9 * iz),
                     alignment: right ? .bottomTrailing : .bottomLeading)
            }
            if source == .pageCentre { centreDot(colour) }
        }
    }

    /// The equal gaps a move has landed on, each bracketed with its width
    /// in the design's unit, and the sizes a resize has matched, each marked
    /// "=" — in the guide colour, as the guides are (Geometry.matchingGap,
    /// Geometry.matchingSize). The snap haptic marks the landing; these say
    /// what it was.
    @ViewBuilder
    private var spacingMarks: some View {
        let gaps = store.gapMarks
        let sizes = store.sizeMarks
        if !gaps.isEmpty || !sizes.isEmpty {
            ZStack {
                gapBrackets(gaps)
                ForEach(gaps.indices, id: \.self) { i in gapLabel(gaps[i]) }
                ForEach(sizes.indices, id: \.self) { i in sizeLabel(sizes[i]) }
            }
        }
    }

    /// Show distances: from each side of what moves, or is held still to
    /// measure, a thin guide-colour line to the nearest edge facing it, its
    /// length in the design's unit in a pill at its middle. One the same as
    /// an equal gap keeps its "=" (Geometry.isEqualGap), reading "= 24 px",
    /// as on the Android twin; one of no length is not drawn.
    @ViewBuilder
    private var distanceMarks: some View {
        let marks = store.distanceMarks.filter { $0.distance > 0 }
        if !marks.isEmpty {
            ZStack {
                distanceLines(marks)
                ForEach(marks.indices, id: \.self) { i in distanceLabel(marks[i]) }
            }
        }
    }

    private func distanceLines(_ marks: [Geometry.Distance]) -> some View {
        let width = 1 * iz
        return Canvas { context, _ in
            var path = Path()
            for mark in marks {
                path.move(to: mark.from)
                path.addLine(to: mark.to)
            }
            context.stroke(path, with: .color(Theme.guide), lineWidth: width)
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .position(x: store.pageWidth / 2, y: store.pageHeight / 2)
        .allowsHitTesting(false)
    }

    private func distanceLabel(_ mark: Geometry.Distance) -> some View {
        let mid = CGPoint(x: (mark.from.x + mark.to.x) / 2, y: (mark.from.y + mark.to.y) / 2)
        let length = store.distanceText(mark.distance)
        let text = Geometry.isEqualGap(mark, store.gapMarks) ? "= " + length : length
        return pill(text, colour: Theme.guide, at: mid, alignment: .center)
    }

    /// A bracket across each gap: a line from edge to edge, a tick at each.
    private func gapBrackets(_ gaps: [Geometry.GapPair]) -> some View {
        let tick = 5 * iz
        let width = 1.5 * iz
        return Canvas { context, _ in
            var path = Path()
            for pair in gaps {
                let ends = pair.ends
                let across = pair.alongX ? CGVector(dx: 0, dy: tick) : CGVector(dx: tick, dy: 0)
                path.move(to: ends.from)
                path.addLine(to: ends.to)
                for end in [ends.from, ends.to] {
                    path.move(to: CGPoint(x: end.x - across.dx, y: end.y - across.dy))
                    path.addLine(to: CGPoint(x: end.x + across.dx, y: end.y + across.dy))
                }
            }
            context.stroke(path, with: .color(Theme.guide), lineWidth: width)
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .position(x: store.pageWidth / 2, y: store.pageHeight / 2)
        .allowsHitTesting(false)
    }

    /// A gap's width, over its bracket across, beside it down.
    private func gapLabel(_ pair: Geometry.GapPair) -> some View {
        let ends = pair.ends
        let mid = CGPoint(x: (ends.from.x + ends.to.x) / 2, y: (ends.from.y + ends.to.y) / 2)
        let width = Units.readout(pair.gap, store.design) + Units.suffix(store.design)
        let at = pair.alongX ? CGPoint(x: mid.x, y: mid.y - 6 * iz) : CGPoint(x: mid.x + 6 * iz, y: mid.y)
        return pill(width, colour: Theme.guide, at: at, alignment: pair.alongX ? .bottom : .leading)
    }

    /// "=" under a box whose width matches, beside one whose height does.
    private func sizeLabel(_ mark: Geometry.SizeMark) -> some View {
        let b = mark.box
        let at = mark.width ? CGPoint(x: b.midX, y: b.maxY + 6 * iz) : CGPoint(x: b.maxX + 6 * iz, y: b.midY)
        return pill("=", colour: Theme.guide, at: at, alignment: mark.width ? .top : .leading)
    }

    private func centreDot(_ colour: Color) -> some View {
        Circle()
            .fill(colour)
            .overlay(Circle().stroke(Color.white, lineWidth: 2 * iz))
            .frame(width: 9 * iz, height: 9 * iz)
            .position(x: store.pageWidth / 2, y: store.pageHeight / 2)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge = store.badge, let el = store.selectedElements.first {
            let box = Geometry.union(store.selectedElements.map(Geometry.aabb))
            badgeText(badge)
                .font(.system(size: 12 * iz * badgeScale, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8 * iz)
                .padding(.vertical, 4 * iz)
                .background(RoundedRectangle(cornerRadius: 6 * iz).fill(Color(hex: "#0d1216")))
                .position(x: box.midX, y: box.maxY + 22 * iz)
                .allowsHitTesting(false)
                .id(el.id)
        }
    }

    /// The badge's words, with a snapped axis, an equal gap or a held angle
    /// picked out in the guide colour — when the runs set with it are still
    /// the badge's; a plain badge set elsewhere is drawn plain.
    private func badgeText(_ badge: String) -> Text {
        guard let runs = store.badgeRuns, Readouts.text(runs) == badge else { return Text(badge) }
        return runs.reduce(Text("")) { line, run in
            line + Text(run.text).foregroundColor(run.accent ? Theme.guide : .white)
        }
    }
}
