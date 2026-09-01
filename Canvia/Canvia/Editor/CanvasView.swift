// Interactive canvas: the page rendered in page-pixel coordinates, scaled
// and offset for zoom/pan, with a gesture layer for select/move and a
// selection overlay for handles. All gesture math runs in the "page"
// coordinate space so zoom never affects it.

import SwiftUI

struct CanvasView: View {
    @Bindable var store: DesignStore
    @State private var gesture = GestureState()
    @State private var pinchBaseZoom: Double?
    @FocusState private var textFieldFocused: Bool

    struct GestureState {
        var dragOriginals: [String: CGPoint] = [:]
        var dragActive = false
        var resizeOriginal: Element?
        var rotateCenter: CGPoint?
        var rotateOffset: Double = 0
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "#ebecf0")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        commitTextEditIfAny()
                        store.select(nil)
                    }

                pageContent
                    .coordinateSpace(name: "page")
                    .frame(width: store.design.width, height: store.design.height)
                    .scaleEffect(store.zoom)
                    .offset(store.canvasOffset)
            }
            .onAppear { fitToScreen(in: geo.size) }
            .onChange(of: store.design.id) { fitToScreen(in: geo.size) }
            .onChange(of: store.design.width) { fitToScreen(in: geo.size) }
            .onChange(of: store.design.height) { fitToScreen(in: geo.size) }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        if pinchBaseZoom == nil { pinchBaseZoom = store.zoom }
                        store.zoom = min(4, max(0.05, (pinchBaseZoom ?? 1) * value.magnification))
                    }
                    .onEnded { _ in pinchBaseZoom = nil }
            )
            .simultaneousGesture(panGesture)
        }
        .clipped()
    }

    // MARK: page + overlay

    private var pageContent: some View {
        ZStack {
            PageRenderView(design: store.design, page: store.page)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 4)

            // Hit layer: one transparent overlay per element for taps/drags.
            ForEach(store.page.elements) { el in
                elementHitArea(el)
            }

            SelectionOverlay(store: store,
                             onHandleDrag: handleDrag,
                             onHandleEnd: { store.commit(); clearTransient() },
                             onRotateDrag: rotateDrag,
                             onRotateEnd: { store.commit(); clearTransient() })

            if let id = store.editingTextId, let el = store.element(id) {
                inlineTextEditor(el)
            }
        }
    }

    private func elementHitArea(_ el: Element) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: max(el.w, 24), height: max(el.h, 24))
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
    }

    // MARK: move

    private func moveGesture(_ el: Element) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("page"))
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
                }
                var dx = value.location.x - value.startLocation.x
                var dy = value.location.y - value.startLocation.y

                // Snap the union of moved boxes against page + siblings.
                let movingIds = Set(gesture.dragOriginals.keys)
                let boxes: [CGRect] = gesture.dragOriginals.compactMap { id, origin in
                    guard var moved = store.element(id) else { return nil }
                    moved.x = origin.x + dx
                    moved.y = origin.y + dy
                    return Geometry.aabb(moved)
                }
                if !boxes.isEmpty {
                    let lines = Geometry.snapLines(design: store.design, page: store.page,
                                                   excluding: movingIds)
                    let snap = Geometry.snap(box: Geometry.union(boxes),
                                             xLines: lines.x, yLines: lines.y,
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
                if let first = gesture.dragOriginals.keys.first, let moved = store.element(first) {
                    store.badge = "\(Int(moved.x)), \(Int(moved.y))"
                }
            }
            .onEnded { _ in
                if gesture.dragActive {
                    store.commit()
                } else {
                    store.endGesture()
                }
                clearTransient()
            }
    }

    // MARK: resize / rotate (called from the overlay)

    private func handleDrag(_ handle: Handle, _ location: CGPoint) {
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
                } else {
                    el.h = FontLibrary.measuredHeight(for: el)
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

    private func rotateDrag(_ location: CGPoint) {
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

    // MARK: pan

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Only pan when the drag started on empty workspace: element
                // drags run in the named space and consume their events.
                guard !gesture.dragActive else { return }
                store.canvasOffset = CGSize(
                    width: store.canvasOffset.width + value.translation.width - lastPan.width,
                    height: store.canvasOffset.height + value.translation.height - lastPan.height)
                lastPan = value.translation
            }
            .onEnded { _ in lastPan = .zero }
    }

    @State private var lastPan: CGSize = .zero

    // MARK: zoom helpers

    func fitToScreen(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let pad = 48.0
        store.zoom = min((size.width - pad) / store.design.width,
                         (size.height - pad) / store.design.height)
        store.zoom = min(max(store.zoom, 0.05), 2)
        store.canvasOffset = .zero
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
                    let h = FontLibrary.measuredHeight(for: store.design.pages[store.pageIndex].elements[i])
                    store.design.pages[store.pageIndex].elements[i].h = h
                }
            })
        TextField("", text: binding, axis: .vertical)
            .focused($textFieldFocused)
            .font(Font(FontLibrary.uiFont(family: el.fontFamily, size: el.fontSize ?? 42,
                                          weight: el.fontWeight ?? 400, italic: el.italic ?? false)))
            .foregroundStyle(Color(hex: el.color ?? "#1f2430"))
            .multilineTextAlignment(el.align == "left" ? .leading : el.align == "right" ? .trailing : .center)
            .frame(width: el.w)
            .background(Color.white.opacity(0.65))
            .rotationEffect(.degrees(el.rotation))
            .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
            .onSubmit { commitTextEditIfAny() }
    }
}
