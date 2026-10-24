// Edit shape's handles: the eight points a warp bends the words' box by, or
// the points of the path the words follow, as small discs to drag on the
// canvas (DesignStore.dragShapeHandle). Dragging one bends the words live,
// and letting go is one undo step — as the Android twin's shape handles.

import SwiftUI

struct ShapeHandles: View {
    @Bindable var store: DesignStore
    /// The handle a finger is dragging, and where its touch began.
    @State private var dragged: (index: Int, start: CGPoint)?

    private var iz: Double { 1 / max(store.zoom, 0.01) }

    var body: some View {
        ZStack {
            ForEach(Array(store.shapeHandles.enumerated()), id: \.offset) { i, point in
                handle(i, at: point)
            }
        }
    }

    private func handle(_ index: Int, at point: CGPoint) -> some View {
        let target = Touch.pageUnits(Touch.minTarget, zoom: store.zoom)
        let held = dragged?.index == index
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Theme.accent, lineWidth: (held ? 2.5 : 1.5) * iz))
            .frame(width: 14 * iz, height: 14 * iz)
            .frame(width: target, height: target)
            .contentShape(Rectangle())
            .position(point)
            .gesture(drag(index))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("Shape point %d", index + 1))
    }

    private func drag(_ index: Int) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
            .onChanged { value in
                // A drag the system cancelled never ends: a touch that
                // starts somewhere else closes the old step first.
                if let old = dragged, old.start != value.startLocation || old.index != index {
                    dragged = nil
                    store.commit()
                }
                if dragged == nil { dragged = (index, value.startLocation) }
                store.dragShapeHandle(index, to: value.location)
            }
            .onEnded { _ in
                guard dragged != nil else { return }
                dragged = nil
                store.commit()
            }
    }

    /// Whether `point`, in page units, is on one of the handles.
    static func takes(_ point: CGPoint, store: DesignStore) -> Bool {
        let half = Touch.pageUnits(Touch.minTarget, zoom: store.zoom) / 2
        return store.shapeHandles.contains { abs(Double(point.x - $0.x)) <= half && abs(Double(point.y - $0.y)) <= half }
    }
}
