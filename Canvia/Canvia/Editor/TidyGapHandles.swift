// The gap handles of a tidied row or column: a small pill in the middle of
// each gap (Geometry.tidyGapHandles). Dragging one changes every gap at
// once — along the row, or down the column — live, read out as "Gap 24 px",
// felt as it passes Tidy up's own gap, which holds it a moment, and one
// Spacing step as it lets go. VoiceOver has the Position sheet's Spacing
// instead, adjustable a unit at a time.

import SwiftUI

struct TidyGapHandles: View {
    @Bindable var store: DesignStore
    /// The gap as the handle was grabbed; nil while none is held.
    @State private var grabbed: Double?

    /// How near Tidy up's own gap, on screen, a dragged gap is held on it.
    private static let holdNear = 4.0

    var body: some View {
        if store.selection.count >= 2, let layout = store.tidyLayout, layout.mode != .grid {
            let iz = 1 / max(store.zoom, 0.01)
            let row = layout.mode == .row
            ForEach(Array(Geometry.tidyGapHandles(store.selectedElements).enumerated()), id: \.offset) { _, at in
                pill(row: row, iz: iz)
                    .position(at)
                    .gesture(drag(row: row, gap: layout.gap))
            }
            .accessibilityHidden(true)
        }
    }

    /// The pill across the gap, with a fingertip's target round it.
    private func pill(row: Bool, iz: Double) -> some View {
        Capsule()
            .fill(Color.white)
            .overlay(Capsule().stroke(Theme.accent, lineWidth: 1.5 * iz))
            .frame(width: (row ? 6 : 22) * iz, height: (row ? 22 : 6) * iz)
            .frame(width: Touch.minTarget * iz, height: Touch.minTarget * iz)
            .contentShape(Rectangle())
    }

    private func drag(row: Bool, gap: Double) -> some Gesture {
        DragGesture(minimumDistance: Touch.pageUnits(Touch.tapSlop, zoom: store.zoom), coordinateSpace: .named("page"))
            .onChanged { value in
                let start = grabbed ?? gap
                if grabbed == nil {
                    grabbed = gap
                    store.canvasTouchActive = true
                }
                let travel = Double(row ? value.translation.width : value.translation.height)
                store.setTidySpacingLive(held(max(0, start + travel)))
            }
            .onEnded { _ in
                grabbed = nil
                store.commitSpacing()
                store.spacingSnapped = false
                store.badge = nil
                store.badgeRuns = nil
                store.canvasTouchActive = false
            }
    }

    /// `gap` held on Tidy up's own gap when within holdNear of it on
    /// screen, felt as it lands there (spacingSnapped), and read out.
    private func held(_ gap: Double) -> Double {
        let standard = Geometry.defaultTidyGap(page: store.pageSize)
        let near = abs(gap - standard) <= Touch.pageUnits(Self.holdNear, zoom: store.zoom)
        let kept = near ? standard : gap
        if store.spacingSnapped != near { store.spacingSnapped = near }
        let design = store.design
        let unit = design.physicalUnit == nil ? " px" : Units.suffix(design)
        store.badge = tr("Gap %@", Units.readout(kept, design) + unit)
        store.badgeRuns = nil
        return kept
    }
}
