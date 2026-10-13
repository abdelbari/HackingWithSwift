// The column edges of a whole table selected, to drag: a small upright bar
// at the foot of each edge between two columns. Dragging one widens the
// column on one side of it and narrows the other, the table as wide as it
// was and neither column under DataGraphics.minColumnWidth, the rows growing
// or shrinking with the words and the two widths read out as it goes;
// letting go is one undo step. The Android twin's column handles do the
// same, by the same rule (draggedColumns).

import SwiftUI

struct TableColumnHandles: View {
    @Bindable var store: DesignStore
    let edges: (xs: [Double], top: Double, bottom: Double)

    /// The edge a finger is dragging, where its touch began, and the
    /// widths the columns had then: each frame of the drag sets them from
    /// those, so the edge follows the finger and does not creep.
    private struct Dragged {
        var edge: Int
        var start: CGPoint
        var widths: [Double]
    }
    @State private var dragged: Dragged?

    private var iz: Double { 1 / max(store.zoom, 0.01) }

    var body: some View {
        ZStack {
            // The edge being dragged, down the whole table.
            if let dragged, edges.xs.indices.contains(dragged.edge) {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 1.5 * iz, height: max(0, edges.bottom - edges.top))
                    .position(x: edges.xs[dragged.edge], y: (edges.top + edges.bottom) / 2)
                    .allowsHitTesting(false)
            }
            ForEach(Array(edges.xs.enumerated()), id: \.offset) { i, x in
                handle(i, at: CGPoint(x: x, y: edges.bottom))
            }
        }
    }

    private func handle(_ edge: Int, at point: CGPoint) -> some View {
        let target = Touch.pageUnits(Touch.minTarget, zoom: store.zoom)
        return Capsule()
            .fill(Color.white)
            .overlay(Capsule().stroke(Theme.accent, lineWidth: 1.5 * iz))
            .frame(width: 7 * iz, height: 20 * iz)
            .frame(width: target, height: target)
            .contentShape(Rectangle())
            .position(point)
            .gesture(drag(edge))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Column edge \(edge + 1)")
            .accessibilityValue(widthsReadout(edge))
            .accessibilityAdjustableAction { direction in
                let step: Double
                switch direction {
                case .increment: step = 8
                case .decrement: step = -8
                @unknown default: return
                }
                guard let widths = DataGraphics.draggedColumns(store.tableColumnWidths, edge: edge, by: step) else { return }
                store.setTableColumnWidths(widths)
            }
    }

    private func drag(_ edge: Int) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
            .onChanged { value in
                // A drag the system cancelled never ends: a touch that
                // starts somewhere else closes the old step first.
                if let old = dragged, old.start != value.startLocation || old.edge != edge {
                    dragged = nil
                    store.badge = nil
                    store.commit()
                }
                if dragged == nil {
                    dragged = Dragged(edge: edge, start: value.startLocation, widths: store.tableColumnWidths)
                }
                guard let dragged else { return }
                let widths = DataGraphics.draggedColumns(dragged.widths, edge: edge, by: value.translation.width) ?? dragged.widths
                store.setTableColumnWidthsTransient(widths)
                store.badge = Self.readout(widths, edge: edge)
            }
            .onEnded { _ in
                guard dragged != nil else { return }
                dragged = nil
                store.badge = nil
                store.commit()
            }
    }

    /// The two columns either side of the edge, as the drag reads them
    /// out: "287 | 113", as on the Android twin.
    static func readout(_ widths: [Double], edge: Int) -> String {
        widths.dropFirst(edge).prefix(2).map { String(Int($0.rounded())) }.joined(separator: " | ")
    }

    /// The two columns either side of the edge, as VoiceOver reads them.
    private func widthsReadout(_ edge: Int) -> String {
        let widths = store.tableColumnWidths
        guard edge + 1 < widths.count else { return "" }
        return "\(Int(widths[edge].rounded())) and \(Int(widths[edge + 1].rounded())) wide"
    }
}
