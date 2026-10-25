// The yellow diamonds a selected straight-edged shape shows beside its
// resize handles (DesignStore.geometryHandles): a star's inner corner, an
// arrow's head and shaft, a callout's tail, a chevron's notch. Dragging
// one reshapes it live, and letting go is one undo step named Shape — as
// the Android twin's shape handles. VoiceOver moves a star's or a notch's
// with Increment and Decrement.

import SwiftUI

struct GeometryHandles: View {
    @Bindable var store: DesignStore
    /// Where the touch dragging a handle began.
    @State private var dragStart: CGPoint?

    private var iz: Double { 1 / max(store.zoom, 0.01) }

    var body: some View {
        ZStack {
            ForEach(Array(store.geometryHandles.enumerated()), id: \.offset) { _, point in
                handle(at: point)
            }
        }
    }

    private func handle(at point: CGPoint) -> some View {
        let target = Touch.pageUnits(Touch.minTarget, zoom: store.zoom)
        let held = dragStart != nil
        let side = 12 * iz
        return Rectangle()
            .fill(Color.yellow)
            .overlay(Rectangle().stroke(Color.black.opacity(0.55), lineWidth: (held ? 2 : 1) * iz))
            .frame(width: side, height: side)
            .rotationEffect(.degrees(45))
            .frame(width: target, height: target)
            .contentShape(Rectangle())
            .position(point)
            .gesture(drag)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(spokenValue)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: nudge(1)
                case .decrement: nudge(-1)
                @unknown default: break
                }
            }
    }

    private var shapeId: String { store.shapedSelection?.shapeId ?? "" }

    private var name: String { ShapeGeometry.handleName(shapeId) }

    /// The parameter VoiceOver steps, and by how much: a star's inner
    /// radius, an arrow's head, a callout's tail across, a notch.
    private var stepped: (key: String, by: Double)? {
        let keys = ShapeGeometry.defaults(shapeId).keys
        if keys.contains("inner") { return ("inner", 0.05) }
        if keys.contains("head") { return ("head", 0.05) }
        if keys.contains("tailX") { return ("tailX", 0.05) }
        if keys.contains("notch") { return ("notch", 0.05) }
        return nil
    }

    private var spokenValue: String {
        guard let stepped else { return "" }
        let v = ShapeGeometry.value(shapeId, store.shapedSelection?.shapeParams, stepped.key)
        return "\(Int((v * 100).rounded()))%"
    }

    private func nudge(_ sign: Double) {
        guard let stepped else { return }
        let v = ShapeGeometry.value(shapeId, store.shapedSelection?.shapeParams, stepped.key)
        store.setShapeParameter(stepped.key, to: v + sign * stepped.by)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
            .onChanged { value in
                // A drag the system cancelled never ends: a touch that
                // starts somewhere else closes the old step first.
                if let start = dragStart, start != value.startLocation {
                    dragStart = nil
                    store.endGeometryDrag()
                }
                if dragStart == nil { dragStart = value.startLocation }
                store.dragGeometryHandle(to: value.location)
            }
            .onEnded { _ in
                guard dragStart != nil else { return }
                dragStart = nil
                store.endGeometryDrag()
            }
    }

    /// Whether `point`, in page units, is on one of the handles.
    static func takes(_ point: CGPoint, store: DesignStore) -> Bool {
        let half = Touch.pageUnits(Touch.minTarget, zoom: store.zoom) / 2
        return store.geometryHandles.contains { abs(Double(point.x - $0.x)) <= half && abs(Double(point.y - $0.y)) <= half }
    }
}
