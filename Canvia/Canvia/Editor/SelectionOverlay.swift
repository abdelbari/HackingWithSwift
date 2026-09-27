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

    /// The handle a finger is working, where it took it relative to the
    /// handle, and the ring's outset then — held for the whole drag, since
    /// recomputed live the ring would slide in as the element grows and the
    /// handle would crawl out from under the thumb.
    private struct Held {
        var grab: HandleGrab
        var offset: CGPoint
        var outsetX: Double
        var outsetY: Double
    }
    @State private var held: Held?

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
                handleRing(for: el, handles: Touch.handleSet(for: el))
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
                    handleRing(for: Geometry.boxElement(bounds), handles: [.nw, .ne, .se, .sw])
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

    /// The ring's outset on each axis, in page units: held while a handle is
    /// being dragged, otherwise what the element's size on screen needs.
    private func outsets(for el: Element) -> (x: Double, y: Double) {
        if let held { return (held.outsetX, held.outsetY) }
        return (Touch.handleOutset(side: el.w, zoom: store.zoom),
                Touch.handleOutset(side: el.h, zoom: store.zoom))
    }

    /// Where the rotate handle sits: below the bottom edge — and below the
    /// ring, when it stands off a small element — turned with the element.
    private func rotatePoint(_ el: Element, outsetY: Double) -> CGPoint {
        Geometry.rotate(CGPoint(x: el.x + el.w / 2, y: el.y + el.h + outsetY + 28 * iz),
                        around: el.center, degrees: el.rotation)
    }

    /// Every handle the element offers, at any size or zoom. On a small or
    /// zoomed-out element the ring stands off the outline, joined to it by a
    /// short leader, so neighbouring handles stay a finger apart — as on the
    /// Android twin, where the old answer of hiding handles left a small
    /// element resizable only by numbers. One touch area takes them all and
    /// hands a touch to the nearest handle; see Touch.grab.
    private func handleRing(for el: Element, handles: [Handle]) -> some View {
        let out = outsets(for: el)
        let rotateAt = rotatePoint(el, outsetY: out.y)
        return ZStack {
            if out.x > 0 || out.y > 0 { leaders(el, handles: handles, outsetX: out.x, outsetY: out.y) }
            ForEach(handles, id: \.rawValue) { handle in
                handleDot(handle, at: Geometry.handlePoint(el, handle, outsetX: out.x, outsetY: out.y))
            }
            rotateGlyph(el, at: rotateAt)
            touchArea(el, handles: handles, outsetX: out.x, outsetY: out.y, rotateAt: rotateAt)
        }
    }

    /// Faint ticks from the outline out to each handle standing off it.
    private func leaders(_ el: Element, handles: [Handle], outsetX: Double, outsetY: Double) -> some View {
        let width = 1 * iz
        return Canvas { context, _ in
            var path = Path()
            for handle in handles {
                path.move(to: Geometry.handlePoint(el, handle))
                path.addLine(to: Geometry.handlePoint(el, handle, outsetX: outsetX, outsetY: outsetY))
            }
            context.stroke(path, with: .color(Theme.accent.opacity(0.55)), lineWidth: width)
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .allowsHitTesting(false)
    }

    private func handleDot(_ handle: Handle, at point: CGPoint) -> some View {
        let size = (handle.isCorner ? 11.0 : 9.0) * iz
        return Circle()
            .fill(Color.white)
            // A coloured ring on white already separates the handle from the
            // page. The old grey ring plus a drop shadow made them read as
            // beads sitting on top of the design rather than part of the tool.
            .overlay(Circle().stroke(Theme.accent.opacity(0.9), lineWidth: 1 * iz))
            .frame(width: size, height: size)
            .position(point)
            .allowsHitTesting(false)
    }

    private func rotateGlyph(_ el: Element, at point: CGPoint) -> some View {
        // Was arrow.triangle.2.circlepath — the refresh/sync glyph, so the
        // control for rotating your text read as a reload button.
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 11 * iz, weight: .semibold))
            .foregroundStyle(Theme.accent)
            // Track the element's angle, so the affordance says which way is up.
            .rotationEffect(.degrees(el.rotation))
            .frame(width: 24 * iz, height: 24 * iz)
            .background(Circle().fill(Color.white)
                .overlay(Circle().stroke(Theme.accent.opacity(0.9), lineWidth: 1 * iz)))
            .position(point)
            .allowsHitTesting(false)
    }

    /// The one place the handles take touches: a circle of reach round each
    /// handle and the rotate handle, less the element's body except right
    /// by a handle — so a touch on a small element's body still moves it.
    /// Everywhere else falls through to the elements beneath.
    private func touchArea(_ el: Element, handles: [Handle], outsetX: Double, outsetY: Double,
                           rotateAt: CGPoint) -> some View {
        let reach = Touch.pageUnits(Touch.handleReach, zoom: store.zoom)
        let inside = Touch.pageUnits(Touch.handleReachInside, zoom: store.zoom)
        let points = handles.map { Geometry.handlePoint(el, $0, outsetX: outsetX, outsetY: outsetY) }
        let zone = Self.touchZone(el, points: points, rotateAt: rotateAt, reach: reach, inside: inside)
        return Color.clear
            .frame(width: store.pageWidth, height: store.pageHeight)
            .contentShape(Path(zone))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
                    .onChanged { value in
                        if held == nil {
                            guard let grab = Touch.grab(at: value.startLocation, el: el, handles: handles,
                                                        outsetX: outsetX, outsetY: outsetY, rotateAt: rotateAt,
                                                        reach: reach, inside: inside) else { return }
                            // Against the handle on the outline, not the one
                            // drawn off it, so the first frame neither jumps
                            // the edge to the finger nor grows the element by
                            // the outset.
                            var offset = CGPoint.zero
                            if case .resize(let handle) = grab {
                                let edge = Geometry.handlePoint(el, handle)
                                offset = CGPoint(x: edge.x - value.startLocation.x, y: edge.y - value.startLocation.y)
                            }
                            held = Held(grab: grab, offset: offset, outsetX: outsetX, outsetY: outsetY)
                        }
                        guard let held else { return }
                        switch held.grab {
                        case .resize(let handle):
                            onHandleDrag(handle, CGPoint(x: value.location.x + held.offset.x,
                                                         y: value.location.y + held.offset.y))
                        case .rotate:
                            onRotateDrag(value.location)
                        }
                    }
                    .onEnded { _ in
                        let grab = held?.grab
                        held = nil
                        switch grab {
                        case .some(.resize): onHandleEnd()
                        case .some(.rotate): onRotateEnd()
                        case .none: break
                        }
                    }
            )
    }

    /// The handles' touch area as a path, in page units.
    private static func touchZone(_ el: Element, points: [CGPoint], rotateAt: CGPoint,
                                  reach: Double, inside: Double) -> CGPath {
        let far = CGMutablePath()
        let near = CGMutablePath()
        for p in points + [rotateAt] {
            far.addEllipse(in: CGRect(x: p.x - reach, y: p.y - reach, width: reach * 2, height: reach * 2))
        }
        for p in points {
            near.addEllipse(in: CGRect(x: p.x - inside, y: p.y - inside, width: inside * 2, height: inside * 2))
        }
        let c = el.center
        var turn = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: CGFloat(el.rotation * .pi / 180))
            .translatedBy(x: -c.x, y: -c.y)
        let body = CGPath(rect: el.frame, transform: &turn)
        return far.subtracting(body).union(near)
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
            badgeText(badge)
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

    /// The badge's words, with a snapped axis, an equal gap or a held angle
    /// picked out in the guide colour — when the runs set with it are still
    /// the badge's; a plain badge set elsewhere is drawn plain.
    private func badgeText(_ badge: String) -> Text {
        guard let runs = store.badgeRuns, Readouts.text(runs) == badge else { return Text(badge) }
        return runs.reduce(Text("")) { line, run in
            line + Text(run.text).foregroundColor(run.accent ? Theme.guide : .white)
        }
    }
}
