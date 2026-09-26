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

    @Environment(\.colorSchemeContrast) private var contrast

    private var iz: Double { 1 / max(store.zoom, 0.01) }
    /// Increase Contrast: heavier outlines, since a one-point accent line
    /// over a busy photo is exactly what that setting is asking to fix.
    private var weight: Double { contrast == .increased ? 1.8 : 1 }

    var body: some View {
        ZStack {
            let selected = store.selectedElements

            ForEach(selected) { el in
                if selected.count == 1 && el.locked {
                    lockedOutline(el)
                } else {
                    outline(el, lineWidth: (selected.count > 1 ? 1 : 1.5) * weight)
                }
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
                    .allowsHitTesting(false)
                // The group resizes and turns as one unit from its box.
                // Corners only: a uniform scale is the only one that keeps
                // rotated members exact (see Geometry.scale).
                if selected.contains(where: { !$0.locked }) {
                    let box = Geometry.boxElement(bounds)
                    ForEach(Touch.handleSet(for: box, zoom: store.zoom).filter(\.isCorner),
                            id: \.rawValue) { handle in
                        handleDot(handle, el: box)
                    }
                    rotateHandle(for: box)
                }
                // How many, over the box — but not while a drag's readout is
                // up there too.
                if store.badge == nil {
                    pill("\(selected.count) selected", colour: Theme.accent,
                         at: CGPoint(x: bounds.midX, y: bounds.minY - 9 * iz), alignment: .bottom)
                }
            }

            guides
            badgeView
        }
        .allowsHitTesting(!store.selection.isEmpty)
    }

    /// A locked element, selected on its own: a dashed outline, which says it
    /// will not move, and a padlock at its corner, which says why — rather
    /// than the solid outline that promised handles and then had none.
    private func lockedOutline(_ el: Element) -> some View {
        let dash: [CGFloat] = [7 * iz, 5 * iz]
        let box = Geometry.aabb(el)
        return ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: 1 * iz)
                    .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 3.5 * iz * weight, dash: dash))
                RoundedRectangle(cornerRadius: 1 * iz)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5 * iz * weight, dash: dash))
            }
            .frame(width: el.w, height: el.h)
            .rotationEffect(.degrees(el.rotation))
            .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
            Image(systemName: "lock.fill")
                .font(.system(size: 11 * iz, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22 * iz, height: 22 * iz)
                .background(Circle().fill(Theme.accent))
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1 * iz))
                .position(x: box.minX, y: box.minY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A small label on the canvas, the same size on screen at any zoom,
    /// placed by one of its edges — `alignment` — at `point`.
    private func pill(_ text: String, colour: Color, at point: CGPoint, alignment: Alignment) -> some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: alignment) {
                Text(text)
                    .font(.system(size: 12.5 * iz, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9 * iz)
                    .padding(.vertical, 5.5 * iz)
                    .background(Capsule().fill(colour))
            }
            .position(point)
            .allowsHitTesting(false)
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

    /// Each snap line, named for what it lines the selection up with —
    /// "Centre of the page", "Lined up with heading: SALE", "Your guide" —
    /// at the end of the line away from the selection, so the label is never
    /// under the finger. A guide of the person's own is teal, the rest
    /// magenta, and the page's centre gets a dot where its lines cross.
    @ViewBuilder
    private var guides: some View {
        let focus = store.selectionBox ?? CGRect(x: store.pageWidth / 2, y: store.pageHeight / 2, width: 0, height: 0)
        let reach = 24 * iz
        if let x = store.guideX {
            let source = store.guideXSource
            let colour = source == .guide ? Theme.userGuide : Theme.guide
            Rectangle()
                .fill(colour)
                .frame(width: 1.5 * iz, height: store.pageHeight + 2 * reach)
                .position(x: x, y: store.pageHeight / 2)
                .allowsHitTesting(false)
            if let source {
                let above = focus.midY >= store.pageHeight / 2
                let gap: Double = reach + 9 * iz
                let end: Double = above ? -gap : store.pageHeight + gap
                let label = ElementNames.guideLabel(source, vertical: true, elements: store.page.elements)
                pill(label, colour: colour, at: CGPoint(x: x, y: end), alignment: above ? .bottom : .top)
            }
            if source == .pageCentre { centreDot(colour) }
        }
        if let y = store.guideY {
            let source = store.guideYSource
            let colour = source == .guide ? Theme.userGuide : Theme.guide
            Rectangle()
                .fill(colour)
                .frame(width: store.pageWidth + 2 * reach, height: 1.5 * iz)
                .position(x: store.pageWidth / 2, y: y)
                .allowsHitTesting(false)
            if let source {
                let right = focus.midX <= store.pageWidth / 2
                let inset: Double = reach - 9 * iz
                let end: Double = right ? store.pageWidth + inset : -inset
                let label = ElementNames.guideLabel(source, vertical: false, elements: store.page.elements)
                pill(label, colour: colour, at: CGPoint(x: end, y: y - 9 * iz),
                     alignment: right ? .bottomTrailing : .bottomLeading)
            }
            if source == .pageCentre { centreDot(colour) }
        }
    }

    private func centreDot(_ colour: Color) -> some View {
        Circle()
            .fill(colour)
            .overlay(Circle().stroke(Color.white, lineWidth: 2 * iz))
            .frame(width: 9 * iz, height: 9 * iz)
            .position(x: store.pageWidth / 2, y: store.pageHeight / 2)
            .allowsHitTesting(false)
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
