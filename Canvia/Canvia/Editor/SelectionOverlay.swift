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
                outline(el, lineWidth: selected.count > 1 ? 1.5 : 2)
            }

            if let el = store.singleSelection, !el.locked, store.editingTextId != el.id {
                handles(for: el)
                rotateHandle(for: el)
            }

            if selected.count > 1 {
                let bounds = Geometry.union(selected.map(Geometry.aabb))
                Rectangle()
                    .stroke(Color(hex: "#7c2ae8"),
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
        Rectangle()
            .stroke(Color(hex: "#7c2ae8"), lineWidth: lineWidth * iz)
            .frame(width: el.w, height: el.h)
            .rotationEffect(.degrees(el.rotation))
            .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
            .allowsHitTesting(false)
    }

    // MARK: handles

    private func handles(for el: Element) -> some View {
        let handleSet: [Handle] = {
            switch el.type {
            case .line: return [.e, .w]
            case .text: return [.nw, .ne, .se, .sw, .e, .w]
            default: return Handle.allCases
            }
        }()
        return ForEach(handleSet, id: \.rawValue) { handle in
            handleDot(handle, el: el)
        }
    }

    private func handleDot(_ handle: Handle, el: Element) -> some View {
        let point = Geometry.handlePoint(el, handle)
        let size = (handle.isCorner ? 14.0 : 12.0) * iz
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color(hex: "#b3b9c4"), lineWidth: 1 * iz))
            .shadow(color: .black.opacity(0.3), radius: 2 * iz, y: 1 * iz)
            .frame(width: size, height: size)
            // Generous invisible touch target around the visible dot.
            .contentShape(Circle().inset(by: -14 * iz))
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
            CGPoint(x: el.x + el.w / 2, y: el.y + el.h + 34 * iz),
            around: el.center, degrees: el.rotation)
        return Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 13 * iz, weight: .bold))
            .foregroundStyle(Color(hex: "#5f6b7a"))
            .frame(width: 26 * iz, height: 26 * iz)
            .background(Circle().fill(Color.white)
                .shadow(color: .black.opacity(0.3), radius: 2 * iz, y: 1 * iz))
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
                .fill(Color(hex: "#ff2fa0"))
                .frame(width: 1.5 * iz, height: store.design.height * 2)
                .position(x: x, y: store.design.height / 2)
                .allowsHitTesting(false)
        }
        if let y = store.guideY {
            Rectangle()
                .fill(Color(hex: "#ff2fa0"))
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
