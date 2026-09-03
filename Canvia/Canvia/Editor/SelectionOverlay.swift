// Selection overlay: outlines, resize handles, rotate handle, snap guides
// and the size/angle badge. Rendered in page coordinates; visual sizes are
// divided by zoom so they stay constant on screen.

import SwiftUI

struct SelectionOverlay: View {
    @Bindable var store: DesignStore
    var onHandleDrag: (Handle, CGPoint) -> Void
    var onHandleEnd: () -> Void
    var onRotateDrag: (CGPoint) -> Void
    var onRotateEnd: () -> Void

    private var iz: Double { 1 / max(store.zoom, 0.01) }

    var body: some View {
        ZStack {
            let selected = store.selectedElements

            ForEach(selected) { el in
                outline(el, lineWidth: selected.count > 1 ? 1 : 1.5)
            }

            if let el = store.singleSelection, !el.locked, store.editingTextId != el.id {
                handles(for: el)
                rotateHandle(for: el)
            }

            if selected.count > 1 {
                let bounds = Geometry.union(selected.map(Geometry.aabb))
                Rectangle()
                    .stroke(Theme.accent,
                            style: StrokeStyle(lineWidth: 1.5 * iz, dash: [6 * iz, 4 * iz]))
                    .frame(width: bounds.width, height: bounds.height)
                    .position(x: bounds.midX, y: bounds.midY)
            }

            guides
            badgeView
        }
        .allowsHitTesting(store.singleSelection != nil)
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

    private func handles(for el: Element) -> some View {
        // Adaptive: on a small or zoomed-out element the expanded touch
        // targets tile the whole interior, so selecting something would take
        // away the ability to drag it. See Touch.handleSet.
        let handleSet = Touch.handleSet(for: el, zoom: store.zoom)
        return ForEach(handleSet, id: \.rawValue) { handle in
            handleDot(handle, el: el)
        }
    }

    private func handleDot(_ handle: Handle, el: Element) -> some View {
        let point = Geometry.handlePoint(el, handle)
        let size = (handle.isCorner ? 11.0 : 9.0) * iz
        return Circle()
            .fill(Color.white)
            // A coloured ring on white already separates the handle from the
            // page. The old grey ring plus a drop shadow made them read as
            // beads sitting on top of the design rather than part of the tool.
            .overlay(Circle().stroke(Theme.accent.opacity(0.9), lineWidth: 1 * iz))
            .frame(width: size, height: size)
            // Generous invisible touch target around the visible dot.
            .contentShape(Circle().inset(by: -10 * iz))
            // Gesture BEFORE position: .position() wraps the view in a
            // parent-sized container, so a gesture attached after it would
            // hit-test across the whole canvas instead of just this handle.
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
                    .onChanged { value in onHandleDrag(handle, value.location) }
                    .onEnded { _ in onHandleEnd() }
            )
            .position(point)
    }

    private func rotateHandle(for el: Element) -> some View {
        // Below the bottom edge of the (rotated) element.
        let bottomCenter = Geometry.rotate(
            CGPoint(x: el.x + el.w / 2, y: el.y + el.h + 28 * iz),
            around: el.center, degrees: el.rotation)
        // Was arrow.triangle.2.circlepath — the refresh/sync glyph, so the
        // control for rotating your text read as a reload button.
        return Image(systemName: "arrow.clockwise")
            .font(.system(size: 11 * iz, weight: .semibold))
            .foregroundStyle(Theme.accent)
            // Track the element's angle, so the affordance says which way is up.
            .rotationEffect(.degrees(el.rotation))
            .frame(width: 24 * iz, height: 24 * iz)
            .background(Circle().fill(Color.white)
                .overlay(Circle().stroke(Theme.accent.opacity(0.9), lineWidth: 1 * iz)))
            .contentShape(Circle().inset(by: -12 * iz))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
                    .onChanged { value in onRotateDrag(value.location) }
                    .onEnded { _ in onRotateEnd() }
            )
            .position(bottomCenter)
    }

    // MARK: guides + badge

    @ViewBuilder
    private var guides: some View {
        if let x = store.guideX {
            Rectangle()
                .fill(Theme.guide)
                .frame(width: 1.5 * iz, height: store.design.height * 2)
                .position(x: x, y: store.design.height / 2)
                .allowsHitTesting(false)
        }
        if let y = store.guideY {
            Rectangle()
                .fill(Theme.guide)
                .frame(width: store.design.width * 2, height: 1.5 * iz)
                .position(x: store.design.width / 2, y: y)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge = store.badge, let el = store.selectedElements.first {
            let box = Geometry.union(store.selectedElements.map(Geometry.aabb))
            Text(badge)
                .font(.system(size: 12 * iz, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8 * iz)
                .padding(.vertical, 4 * iz)
                .background(RoundedRectangle(cornerRadius: 6 * iz).fill(Color(hex: "#0d1216")))
                .position(x: box.midX, y: box.maxY + 22 * iz)
                .allowsHitTesting(false)
                .id(el.id)
        }
    }
}
