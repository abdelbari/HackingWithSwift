// Interactive canvas: the page rendered in page-pixel coordinates, inside a
// scroll view that owns zoom and pan (see ZoomableCanvas), with a gesture
// layer for select/move and a selection overlay for handles. All gesture math
// runs in the "page" coordinate space so zoom never affects it.

import SwiftUI

struct CanvasView: View {
    @Bindable var store: DesignStore
    @State private var gesture = GestureState()
    @FocusState private var textFieldFocused: Bool

    /// Inverse zoom: ornaments are drawn in page units but should
    /// stay a constant size on screen.
    private var iz: Double { 1 / max(store.zoom, 0.01) }

    struct GestureState {
        var dragOriginals: [String: CGPoint] = [:]
        var dragActive = false
        // Siblings don't move during a drag, so their snap lines are computed
        // once at grab time rather than rebuilt every frame.
        var snapX: [Double] = []
        var snapY: [Double] = []
        /// Union of the dragged elements' bounding boxes as they were at grab
        /// time. Moving does not change any element's size or rotation, so the
        /// union per frame is just this one translated — no need to look the
        /// elements up and re-derive their boxes on every touch move.
        var dragUnion: CGRect = .zero
        var resizeOriginal: Element?
        var rotateCenter: CGPoint?
        var rotateOffset: Double = 0
        /// A multi-selection being resized or rotated as one: the members
        /// and their union as they were when the handle was grabbed.
        var groupOriginals: [Element] = []
        var groupBox: CGRect = .zero
        /// The rubber band, in page units, while one is being drawn.
        var marquee: CGRect?
    }

    var body: some View {
        // Zoom and pan live in a UIScrollView rather than in SwiftUI gestures.
        // See ZoomableCanvas for why: a MagnifyGesture on this stack can never
        // outrank the per-element DragGestures inside it, which is what made
        // pinching impossible once elements covered the page.
        ZoomableCanvas(
            contentSize: CGSize(width: store.design.width, height: store.design.height),
            zoom: $store.zoom,
            fitToken: "\(store.design.id)-\(store.design.width)x\(store.design.height)",
            onBackgroundTap: {
                commitTextEditIfAny()
                store.select(nil)
            }
        ) {
            pageContent
                .coordinateSpace(name: "page")
                .frame(width: store.design.width, height: store.design.height)
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: page + overlay

    private var pageContent: some View {
        ZStack {
            // The shadow casts from a plain rectangle, not from the page
            // content. A .shadow() on PageRenderView made the blur's source a
            // tree that changes on every frame of a drag, and whose radius
            // changes on every frame of a pinch — so Core Animation had to
            // re-render the blur continuously and could cache nothing. The
            // page is an opaque rectangle of exactly these bounds, so a
            // constant rect casts an identical shadow for free.
            Rectangle()
                .fill(Color.white)
                .frame(width: store.design.width, height: store.design.height)
                // Divided by zoom like every other ornament: this lives inside
                // the scroll view's zoomed subview, so a fixed radius was 4pt
                // of blur at fit zoom — the page looked pasted flat onto the
                // workspace — and a 42pt black halo at 3x.
                .shadow(color: .black.opacity(0.16), radius: 12 * iz, y: 3 * iz)

            // Deselect (and commit any inline text edit) on the page surface
            // itself: the workspace-background tap can't fire here because
            // the opaque page sits above it in the ZStack.
            PageRenderView(design: store.design, page: store.page)
                // Carries the document edge in dark mode, where a shadow on a
                // dark workspace is invisible.
                .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1 * iz))
                .contentShape(Rectangle())
                .onTapGesture {
                    commitTextEditIfAny()
                    store.select(nil)
                }
                // A one-finger drag from empty page draws a rubber band.
                // It starts on the page, so the workspace pan (which refuses
                // touches on the page) never competes with it.
                .gesture(marqueeGesture)

            if store.snapping.showGrid { gridOverlay }

            if store.page.elements.isEmpty {
                emptyPageHint
            }

            // Hit layer: one transparent overlay per element for taps/drags.
            ForEach(store.page.elements) { el in
                elementHitArea(el)
            }

            SelectionOverlay(store: store,
                             onHandleDrag: handleDrag,
                             onHandleEnd: { store.commit(); clearTransient() },
                             onRotateDrag: rotateDrag,
                             onRotateEnd: { store.commit(); clearTransient() })

            if let band = gesture.marquee { marqueeView(band) }

            if let id = store.editingTextId, let el = store.element(id) {
                inlineTextEditor(el)
            }
        }
    }

    /// What a blank page said before this was: nothing. A white square and a
    /// round button in the corner, with no indication that the button is where
    /// everything comes from.
    ///
    /// Drawn here rather than in PageRenderView on purpose — PageRenderView is
    /// what thumbnails and exports render, and a hint that shipped inside an
    /// exported PNG would be worse than no hint at all.
    private var emptyPageHint: some View {
        VStack(spacing: 10 * iz) {
            Image(systemName: "plus.circle")
                .font(.system(size: 34 * iz, weight: .light))
            Text("Tap + to add text, photos,\nshapes and QR codes")
                .font(.system(size: 15 * iz, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.onPage)
        .position(x: store.design.width / 2, y: store.design.height / 2)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: marquee

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: Touch.pageUnits(Touch.dragSlop, zoom: store.zoom),
                    coordinateSpace: .named("page"))
            .onChanged { value in
                if gesture.marquee == nil { commitTextEditIfAny() }
                let band = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y))
                gesture.marquee = band
                // Live: the selection follows the band as it grows, so you
                // see what you are about to get before you let go.
                store.select(within: band)
            }
            .onEnded { _ in
                gesture.marquee = nil
            }
    }

    private func marqueeView(_ band: CGRect) -> some View {
        Rectangle()
            .fill(Theme.accent.opacity(0.10))
            .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1 * iz))
            .frame(width: max(band.width, 1), height: max(band.height, 1))
            .position(x: band.midX, y: band.midY)
            .allowsHitTesting(false)
    }

    /// The snapping grid, as hairlines over the page. Drawn here and not in
    /// PageRenderView, so it is never in an export or a thumbnail.
    private var gridOverlay: some View {
        let spacing = store.snapping.grid
        let w = store.design.width, h = store.design.height
        return Canvas { context, _ in
            var path = Path()
            for x in Geometry.gridLines(across: w, spacing: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: h))
            }
            for y in Geometry.gridLines(across: h, spacing: spacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: w, y: y))
            }
            context.stroke(path, with: .color(Theme.accent.opacity(0.18)), lineWidth: 1 * iz)
        }
        .frame(width: w, height: h)
        .allowsHitTesting(false)
    }

    private func elementHitArea(_ el: Element) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: max(el.w, Touch.pageUnits(Touch.minTarget, zoom: store.zoom)),
                   height: max(el.h, Touch.pageUnits(Touch.minTarget, zoom: store.zoom)))
            .rotationEffect(.degrees(el.rotation))
            .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
            .onTapGesture(count: 2) {
                if el.type == .text && !el.locked {
                    startTextEdit(el)
                }
            }
            .onTapGesture {
                commitTextEditIfAny()
                store.select(el.id)
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                store.select(el.id, additive: true)
            }
            .gesture(moveGesture(el))
            .accessibilityElement()
            .accessibilityLabel(CanvasAccessibility.label(for: el))
            .accessibilityValue(CanvasAccessibility.value(for: el, design: store.design))
            .accessibilityAddTraits(store.selection.contains(el.id) ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(el.type == .text ? "Double tap to select; double tap and hold to edit" : "Double tap to select")
            .accessibilityActions { accessibilityActions(for: el) }
    }

    /// The edits that otherwise need a drag, as VoiceOver actions. Each acts
    /// on this element alone, selecting it first, and is one undo step.
    @ViewBuilder
    private func accessibilityActions(for el: Element) -> some View {
        let step = CanvasAccessibility.nudge(for: store.design)
        if !el.locked {
            Button("Move left") { nudge(el, dx: -step, dy: 0) }
            Button("Move right") { nudge(el, dx: step, dy: 0) }
            Button("Move up") { nudge(el, dx: 0, dy: -step) }
            Button("Move down") { nudge(el, dx: 0, dy: step) }
            Button("Duplicate") { store.select(el.id); store.duplicateSelected() }
            Button("Delete") { store.select(el.id); store.deleteSelected() }
        }
        Button("Bring forward") { store.select(el.id); store.reorderSelected(.forward) }
        Button("Send backward") { store.select(el.id); store.reorderSelected(.backward) }
        if el.type == .text && !el.locked {
            Button("Edit text") { startTextEdit(el) }
        }
    }

    private func nudge(_ el: Element, dx: Double, dy: Double) {
        store.select(el.id)
        store.nudgeSelected(dx: dx, dy: dy)
    }

    // MARK: move

    private func moveGesture(_ el: Element) -> some Gesture {
        // A real screen-point threshold. The gesture reads the "page" space,
        // so this has to be divided by zoom to mean 10 points on glass. The
        // old form capped the result at 6 page units to stay under an ancestor
        // pan gesture that the scroll view has since replaced — and the cap
        // inverted the intent: at the fit zoom every design opens at (~0.3),
        // it made the threshold ~2 points, so a tap moved the element and
        // pushed an undo step.
        DragGesture(minimumDistance: Touch.pageUnits(Touch.dragSlop, zoom: store.zoom),
                    coordinateSpace: .named("page"))
            .onChanged { value in
                guard !el.locked, store.editingTextId != el.id else { return }
                if !gesture.dragActive {
                    gesture.dragActive = true
                    store.beginGesture()
                    if !store.selection.contains(el.id) { store.select(el.id) }
                    gesture.dragOriginals = Dictionary(
                        uniqueKeysWithValues: store.selectedElements
                            .filter { !$0.locked }
                            .map { ($0.id, CGPoint(x: $0.x, y: $0.y)) })
                    let lines = Geometry.snapLines(design: store.design, page: store.page,
                                                   excluding: Set(gesture.dragOriginals.keys),
                                                   settings: store.snapping)
                    gesture.snapX = lines.x
                    gesture.snapY = lines.y
                    gesture.dragUnion = Geometry.union(
                        store.selectedElements.filter { !$0.locked }.map(Geometry.aabb))
                }
                var dx = value.location.x - value.startLocation.x
                var dy = value.location.y - value.startLocation.y

                // Snap the union of moved boxes against page + siblings.
                // Translating the grab-time union is exact, not an
                // approximation: rotation happens about each element's own
                // centre, which moves with it, so translating an element
                // translates its bounding box, and the union of translated
                // boxes is the translated union.
                if !gesture.dragUnion.isEmpty {
                    let moved = gesture.dragUnion.offsetBy(dx: dx, dy: dy)
                    let snap = Geometry.snap(box: moved,
                                             xLines: gesture.snapX, yLines: gesture.snapY,
                                             threshold: 6 / store.zoom)
                    dx += snap.dx
                    dy += snap.dy
                    store.guideX = snap.guideX
                    store.guideY = snap.guideY
                }

                for i in store.design.pages[store.pageIndex].elements.indices {
                    let id = store.design.pages[store.pageIndex].elements[i].id
                    if let origin = gesture.dragOriginals[id] {
                        store.design.pages[store.pageIndex].elements[i].x = origin.x + dx
                        store.design.pages[store.pageIndex].elements[i].y = origin.y + dy
                    }
                }
                // Report the element the user actually grabbed: Dictionary
                // ordering is undefined, so keys.first would flicker between
                // members of a multi-element drag.
                if let moved = store.element(el.id) {
                    store.badge = "\(Int(moved.x)), \(Int(moved.y))"
                }
            }
            .onEnded { value in
                // Crossing the threshold and landing back where you started is
                // a tap that wandered, not an edit: it must not enter history,
                // or undo fills up with steps that changed nothing.
                let moved = hypot(value.translation.width, value.translation.height) * store.zoom
                if gesture.dragActive && moved >= Touch.tapSlop {
                    store.commit()
                } else {
                    store.endGesture()
                }
                clearTransient()
            }
    }

    // MARK: resize / rotate (called from the overlay)

    private func handleDrag(_ handle: Handle, _ location: CGPoint) {
        if store.selection.count > 1 {
            groupHandleDrag(handle, location)
            return
        }
        guard let selected = store.singleSelection, !selected.locked else { return }
        if gesture.resizeOriginal?.id != selected.id || !gesture.dragActive {
            store.beginGesture()
            gesture.resizeOriginal = selected
            gesture.dragActive = true
        }
        guard let original = gesture.resizeOriginal else { return }
        let proportional = original.type != .line && handle.isCorner
        let minSize = original.type == .text ? 12.0 : 8.0
        let next = Geometry.resize(original, handle: handle, to: location,
                                   proportional: proportional, minSize: minSize)
        store.updateSelectedTransient { el in
            el.x = next.minX
            el.w = next.width
            switch el.type {
            case .text:
                el.y = next.minY
                if handle.isCorner {
                    let scale = next.width / original.w
                    el.fontSize = max(6, (original.fontSize ?? 42) * scale)
                    el.h = next.height
                } else if el.fitText == true || el.vAlign != nil {
                    // The box is the design here; the type follows it.
                    el.h = next.height
                } else {
                    el.h = FontLibrary.layoutHeight(for: el)
                }
            case .line:
                el.y = next.minY + (next.height - original.h) / 2
                el.h = original.h
            default:
                el.y = next.minY
                el.h = next.height
            }
        }
        if let el = store.singleSelection {
            store.badge = "\(Int(el.w)) × \(Int(el.h))"
        }
    }

    /// Resize a multi-selection from a corner of its box: the box resizes
    /// exactly as a single element would, and every member is scaled to
    /// follow it.
    private func groupHandleDrag(_ handle: Handle, _ location: CGPoint) {
        if gesture.groupOriginals.isEmpty || !gesture.dragActive {
            let members = store.selectedElements.filter { !$0.locked }
            guard !members.isEmpty else { return }
            store.beginGesture()
            gesture.dragActive = true
            gesture.groupOriginals = members
            gesture.groupBox = Geometry.union(members.map(Geometry.aabb))
        }
        let box = Geometry.resize(Geometry.boxElement(gesture.groupBox), handle: handle,
                                  to: location, proportional: true, minSize: 8)
        store.replaceTransient(Geometry.scale(gesture.groupOriginals, from: gesture.groupBox, to: box))
        store.badge = "\(Int(box.width)) × \(Int(box.height))"
    }

    private func groupRotateDrag(_ location: CGPoint) {
        if gesture.groupOriginals.isEmpty || !gesture.dragActive {
            let members = store.selectedElements.filter { !$0.locked }
            guard !members.isEmpty else { return }
            store.beginGesture()
            gesture.dragActive = true
            gesture.groupOriginals = members
            gesture.groupBox = Geometry.union(members.map(Geometry.aabb))
            gesture.rotateCenter = CGPoint(x: gesture.groupBox.midX, y: gesture.groupBox.midY)
            gesture.rotateOffset = Geometry.angle(from: gesture.rotateCenter!, to: location)
        }
        guard let center = gesture.rotateCenter else { return }
        var delta = Geometry.angle(from: center, to: location) - gesture.rotateOffset
        delta = (delta.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        delta = Geometry.snapAngle(delta, step: 45, threshold: 4)
        store.replaceTransient(Geometry.rotate(gesture.groupOriginals, around: center,
                                               by: (delta * 10).rounded() / 10))
        store.badge = "\(Int(delta))°"
    }

    private func rotateDrag(_ location: CGPoint) {
        if store.selection.count > 1 {
            groupRotateDrag(location)
            return
        }
        guard let selected = store.singleSelection, !selected.locked else { return }
        if gesture.rotateCenter == nil || !gesture.dragActive {
            store.beginGesture()
            gesture.dragActive = true
            gesture.rotateCenter = selected.center
            gesture.rotateOffset = Geometry.angle(from: selected.center, to: location) - selected.rotation
        }
        guard let center = gesture.rotateCenter else { return }
        var angle = Geometry.angle(from: center, to: location) - gesture.rotateOffset
        angle = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        angle = Geometry.snapAngle(angle, step: 45, threshold: 4)
        store.updateSelectedTransient { $0.rotation = (angle * 10).rounded() / 10 }
        store.badge = "\(Int(angle))°"
    }

    private func clearTransient() {
        gesture = GestureState()
        store.guideX = nil
        store.guideY = nil
        store.badge = nil
    }

    // MARK: inline text editing

    private func startTextEdit(_ el: Element) {
        store.beginGesture()
        store.editingTextId = el.id
        store.select(el.id)
        textFieldFocused = true
    }

    func commitTextEditIfAny() {
        guard let id = store.editingTextId else { return }
        store.editingTextId = nil
        textFieldFocused = false
        // Delete empty text elements on exit (Canva behavior).
        if let el = store.element(id), (el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.design.pages[store.pageIndex].elements.removeAll { $0.id == id }
            store.selection.remove(id)
        }
        store.commit()
    }

    @ViewBuilder
    private func inlineTextEditor(_ el: Element) -> some View {
        let binding = Binding<String>(
            get: { store.element(el.id)?.text ?? "" },
            set: { newValue in
                store.beginGesture()
                if let i = store.design.pages[store.pageIndex].elements.firstIndex(where: { $0.id == el.id }) {
                    store.design.pages[store.pageIndex].elements[i].text = newValue
                    let h = FontLibrary.layoutHeight(for: store.design.pages[store.pageIndex].elements[i])
                    store.design.pages[store.pageIndex].elements[i].h = h
                }
            })
        TextField("", text: binding, axis: .vertical)
            .focused($textFieldFocused)
            .font(FontLibrary.font(family: el.fontFamily, size: el.fontSize ?? 42,
                                          weight: el.fontWeight ?? 400, italic: el.italic ?? false))
            .foregroundStyle(Color(hex: el.color ?? "#1f2430"))
            .multilineTextAlignment(el.align == "left" ? .leading : el.align == "right" ? .trailing : .center)
            .frame(width: el.w)
            .background(Color.white.opacity(0.65))
            .rotationEffect(.degrees(el.rotation))
            .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
            .onSubmit { commitTextEditIfAny() }
    }
}
