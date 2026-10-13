// Quick actions at the selection: a small pill floating just above what is
// selected — below it when there is no room above — with Copy, Paste,
// Duplicate and Delete, as Canva puts them by the element and as the Android
// twin does. Each does what the menu's own does: Delete still says so with
// its Undo. It keeps out of the way of the work — gone while a finger drags,
// the view pans or pinches, a photo is cropped, words are typed or the pen
// is out — and fades back once things are still, at once under Reduce
// Motion. Where it sits is Geometry.bubbleAnchor's, which both phones share.
//
// In a view of its own, over the canvas, so that only it redraws as the
// canvas scrolls.

import SwiftUI

struct SelectionBubble: View {
    @Bindable var store: DesignStore
    /// The menu's "Quick actions at the selection": on unless turned off.
    @AppStorage(SelectionBubble.key) private var on = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let key = "canvia.quickActions"
    /// The pill's height, and one button's width, in points.
    private static let height = 44.0
    private static let slot = 44.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let at = anchor(in: proxy.size) {
                    pill
                        .position(at)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: shown)
    }

    /// Whether the pill shows: switched on, something selected, and nothing
    /// under way. Select multiple has its own bar.
    private var shown: Bool {
        on && !store.selection.isEmpty && !store.canvasTouchActive && !store.canvasMoving
            && store.cropping == nil && store.editingTextId == nil && store.drawing == nil
            && store.erasing == nil && !store.selectingMultiple && store.previewTime == nil
    }

    /// The pill's middle on screen, or nil when it is not shown or the
    /// selection is out of sight.
    private func anchor(in size: CGSize) -> CGPoint? {
        guard shown, size.width > 0, let box = store.selectionBox else { return nil }
        let screen = Geometry.screenRect(box, visible: store.viewport, zoom: store.zoom)
        let canvas = CGRect(origin: .zero, size: size)
        guard screen.intersects(canvas) else { return nil }
        // A single thing free to turn has its rotate handle below it, the
        // furthest of its handles, and several have "N selected" over their
        // box: the pill keeps clear of either.
        let turns = store.singleSelection.map { !$0.holdsPlace } ?? false
        let clears = turns || store.selection.count > 1
        let place = Geometry.bubbleAnchor(screen, viewport: canvas, handleOutset: clears ? 40 : 8)
        let half = CGFloat(width / 2 + 8)
        let x = size.width > half * 2 ? min(max(place.point.x, half), size.width - half) : size.width / 2
        let rise = CGFloat(Self.height / 2)
        let y = place.side == .above ? place.point.y - rise : place.point.y + rise
        return CGPoint(x: x, y: y)
    }

    private var pastes: Bool { store.hasClipboard }

    private var width: Double { Self.slot * Double(pastes ? 4 : 3) + 12 }

    private var pill: some View {
        HStack(spacing: 0) {
            action("doc.on.doc", "Copy") { store.copySelected() }
            if pastes {
                action("doc.on.clipboard", "Paste") { store.paste() }
            }
            action("plus.square.on.square", "Duplicate") { store.duplicateSelected() }
            action("trash", "Delete", destructive: true) { store.deleteSelected() }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick actions")
        // After the selection, in reading order.
        .accessibilitySortPriority(-1)
    }

    private func action(_ system: String, _ label: String, destructive: Bool = false,
                        perform: @escaping () -> Void) -> some View {
        Button(role: destructive ? .destructive : nil, action: perform) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(destructive ? Color.red : Color.primary)
                .frame(width: Self.slot, height: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
