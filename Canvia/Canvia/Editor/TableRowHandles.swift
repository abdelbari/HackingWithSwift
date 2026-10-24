// The row edges of a selected table, to drag: a small capsule lying along
// the bottom edge of each row, at the table's left. Dragging one makes that
// row taller (or back, never under its words or DataGraphics.minRowHeight),
// the rows below moving with it and its height and the change read out in
// the design's unit as it goes; letting go is one undo step. A row taller
// than its words keeps that height (TableCell.minH). The Android twin's row
// handles do the same, by the same rule (withRowDragged). VoiceOver has
// Taller row and Shorter row on the table's cells in their place.

import SwiftUI

struct TableRowHandles: View {
    @Bindable var store: DesignStore
    let edges: (ys: [Double], rows: [Int], left: Double)

    /// The row whose edge a finger is dragging, where its touch began, its
    /// height then, and the page's elements then: each frame of the drag
    /// lays the table out from those, so the edge follows the finger and
    /// does not creep.
    private struct HeldRow {
        var row: Int
        var start: CGPoint
        var height: Double
        var elements: [Element]
    }
    @State private var dragged: HeldRow?

    private var iz: Double { 1 / max(store.zoom, 0.01) }

    var body: some View {
        ZStack {
            ForEach(edges.rows.indices, id: \.self) { i in
                handle(edges.rows[i], at: CGPoint(x: edges.left, y: edges.ys[i]))
            }
        }
        .accessibilityHidden(true)
    }

    private func handle(_ row: Int, at point: CGPoint) -> some View {
        let target = Touch.pageUnits(Touch.minTarget, zoom: store.zoom)
        let held = dragged?.row == row
        return Capsule()
            .fill(held ? Theme.accent : Color.white)
            .overlay(Capsule().stroke(Theme.accent, lineWidth: 1.5 * iz))
            .frame(width: 20 * iz, height: 7 * iz)
            .frame(width: target, height: target)
            .contentShape(Rectangle())
            .position(point)
            .gesture(drag(row))
    }

    private func drag(_ row: Int) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
            .onChanged { value in
                // A drag the system cancelled never ends: a touch that
                // starts somewhere else closes the old step first.
                if let old = dragged, old.start != value.startLocation || old.row != row {
                    dragged = nil
                    store.badge = nil
                    store.commit()
                }
                if dragged == nil {
                    dragged = HeldRow(row: row, start: value.startLocation, height: store.tableRowHeights[row] ?? 0,
                                      elements: store.page.elements)
                }
                guard let dragged else { return }
                store.dragTableRowTransient(from: dragged.elements, row: row, by: value.translation.height)
                let now = store.tableRowHeights[row] ?? dragged.height
                store.badge = Self.readout(now, change: now - dragged.height, in: store.design)
            }
            .onEnded { _ in
                guard dragged != nil else { return }
                dragged = nil
                store.badge = nil
                store.commit()
            }
    }

    /// The row's height and how far it moved, in the design's unit: "76
    /// (+30)", or "20.1 mm (+7.9 mm)".
    static func readout(_ height: Double, change: Double, in design: Design) -> String {
        let sign = change < 0 ? "−" : "+"
        return length(height, design) + " (" + sign + length(abs(change), design) + ")"
    }

    /// One length so: "76", or "20.1 mm" (Units.readout).
    private static func length(_ px: Double, _ design: Design) -> String {
        Units.readout(px, design) + Units.suffix(design)
    }
}
