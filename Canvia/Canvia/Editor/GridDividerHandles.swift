// The dividers of a whole photo grid selected, to drag: a small pill in
// the middle of each lattice line no cell runs across, lying across the
// line it slides (PhotoGrids.dividers). Dragging one moves that line —
// no cell narrower than eight percent of the grid's side, snapped to the
// middle — and the whole grid is laid out again on it, the line's place
// read out as it goes; letting go is one undo step. The Android twin's
// divider handles do the same, by the same rule (PhotoGrids.dragged).

import SwiftUI

struct GridDividerHandles: View {
    @Bindable var store: DesignStore

    /// The divider a finger is dragging, where its touch began, and the
    /// grid's box then: the line is placed within it, so the box never
    /// creeps as the cells follow the finger.
    private struct DividerDrag {
        var index: Int
        var start: CGPoint
        var box: CGRect
    }
    @State private var dragged: DividerDrag?

    private var iz: Double { 1 / max(store.zoom, 0.01) }

    var body: some View {
        ZStack {
            ForEach(Array(store.gridDividers.enumerated()), id: \.offset) { i, entry in
                handle(i, entry.divider, at: entry.at)
            }
        }
    }

    private func handle(_ index: Int, _ divider: PhotoGrids.GridDivider, at point: CGPoint) -> some View {
        let target = Touch.pageUnits(Touch.minTarget, zoom: store.zoom)
        let held = dragged?.index == index
        return Capsule()
            .fill(Color.white)
            .overlay(Capsule().stroke(Theme.accent, lineWidth: (held ? 2.5 : 1.5) * iz))
            .frame(width: (divider.vertical ? 20 : 7) * iz, height: (divider.vertical ? 7 : 20) * iz)
            .frame(width: target, height: target)
            .contentShape(Rectangle())
            .position(point)
            .gesture(drag(index, divider))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("Divider %d", index + 1))
            .accessibilityValue(Self.readout(divider.at))
            .accessibilityAdjustableAction { direction in
                let step: Double
                switch direction {
                case .increment: step = 0.02
                case .decrement: step = -0.02
                @unknown default: return
                }
                store.dragGridDivider(index, to: divider.at + step)
                store.commit()
            }
    }

    private func drag(_ index: Int, _ divider: PhotoGrids.GridDivider) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
            .onChanged { value in
                // A drag the system cancelled never ends: a touch that
                // starts somewhere else closes the old step first.
                if let old = dragged, old.start != value.startLocation || old.index != index {
                    dragged = nil
                    store.badge = nil
                    store.commit()
                }
                if dragged == nil, let box = store.selectedGridBox {
                    dragged = DividerDrag(index: index, start: value.startLocation, box: box)
                }
                guard let dragged, dragged.box.width > 0, dragged.box.height > 0 else { return }
                let to = divider.vertical
                    ? Double(value.location.x - dragged.box.minX) / Double(dragged.box.width)
                    : Double(value.location.y - dragged.box.minY) / Double(dragged.box.height)
                if let now = store.dragGridDivider(index, to: to) { store.badge = Self.readout(now) }
            }
            .onEnded { _ in
                guard dragged != nil else { return }
                dragged = nil
                store.badge = nil
                store.commit()
            }
    }

    /// Where the line stands, as the drag reads it out: "33%".
    static func readout(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}
