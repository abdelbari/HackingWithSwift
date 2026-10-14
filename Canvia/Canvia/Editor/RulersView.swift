// Rulers along the top and left of the canvas, from the More menu's
// "Rulers": in the design's unit — pixels, millimetres, centimetres or
// inches — with the page's 0 at its top left edge, and ticks that thin out
// or fill in with the zoom (Guides.rulerStep). The selection's extent is
// shaded on each, and while it moves its leading edge is marked.
//
// Dragging from a ruler pulls out a guide — down from the top one a
// horizontal guide, across from the left one a vertical one — that follows
// the finger, snaps to whole units and to the elements, and is made as one
// step through addGuide once let go; let go back over the ruler, nothing is.
// A guide dragged back onto its ruler goes (CanvasView.guideLine).
//
// Over the canvas's view, not the page, so nothing of them is ever in an
// export; and in a view of their own, as CanvasChips are, so only they
// redraw as the canvas scrolls. Hidden from VoiceOver, for whom the
// Snapping menu's Add guide is the way.

import SwiftUI

struct RulersView: View {
    @Bindable var store: DesignStore
    /// The guide being pulled out of a ruler, while it is.
    @State private var pulling: Pull?

    private struct Pull: Equatable {
        var vertical: Bool
        /// Where it would go, in page units.
        var position: Double
        /// Whether the finger is back over its ruler, where letting go
        /// makes nothing.
        var onRuler: Bool
    }

    /// What one ruler shows: where the view starts along it, in page units,
    /// the zoom, its unit, the selection's extent along it and whether that
    /// is moving.
    private struct Ruler {
        var start: Double
        var zoom: Double
        var unitPixels: Double
        var span: ClosedRange<Double>?
        var moving: Bool
    }

    private static let space = "rulers"
    private var thickness: Double { Guides.rulerThickness }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let pulling { pulledGuide(pulling, in: proxy.size) }
                ruler(vertical: false, length: Double(proxy.size.width))
                ruler(vertical: true, length: Double(proxy.size.height))
                corner
            }
            .coordinateSpace(name: Self.space)
        }
        // Along the canvas, which is left to right in any language.
        .designDirection()
        .accessibilityHidden(true)
    }

    // MARK: drawing

    /// The top ruler (`vertical` false: it makes horizontal guides) or the
    /// left one, `length` points long.
    private func ruler(vertical: Bool, length: Double) -> some View {
        let info = rulerInfo(vertical: vertical)
        let edge = thickness
        return Canvas { context, _ in
            Self.draw(&context, info, length: length, thickness: edge, vertical: vertical)
        }
        .frame(width: vertical ? edge : length, height: vertical ? length : edge)
        .background(Theme.chrome)
        .contentShape(Rectangle())
        .gesture(pullGesture(vertical: vertical))
    }

    private func rulerInfo(vertical: Bool) -> Ruler {
        let view = store.viewport
        let box = selectionBox
        let span: ClosedRange<Double>? = box.map { b in
            vertical ? Double(b.minY)...Double(b.maxY) : Double(b.minX)...Double(b.maxX)
        }
        return Ruler(start: Double(vertical ? view.minY : view.minX), zoom: max(store.zoom, 0.0001),
                     unitPixels: Guides.rulerUnit(store.design).pixels, span: span,
                     moving: store.canvasTouchActive)
    }

    /// The selection's box on the page, in page units.
    private var selectionBox: CGRect? {
        let chosen = store.selectedElements.filter { !$0.isHidden }
        guard !chosen.isEmpty else { return nil }
        return Geometry.union(chosen.map(Geometry.aabb))
    }

    /// One ruler: the selection's extent shaded, the ticks rising from the
    /// edge it shares with the canvas, the labelled ones numbered, the
    /// moving selection's edge marked, and a hairline along that edge.
    private static func draw(_ context: inout GraphicsContext, _ ruler: Ruler,
                             length: Double, thickness: Double, vertical: Bool) {
        // `along` the ruler and `across` it, from its outer edge in.
        func point(_ along: Double, _ across: Double) -> CGPoint {
            vertical ? CGPoint(x: across, y: along) : CGPoint(x: along, y: across)
        }
        func screen(_ page: Double) -> Double { (page - ruler.start) * ruler.zoom }
        if let span = ruler.span {
            let a = screen(span.lowerBound), b = screen(span.upperBound)
            let rect = vertical ? CGRect(x: 0, y: a, width: thickness, height: b - a)
                                : CGRect(x: a, y: 0, width: b - a, height: thickness)
            context.fill(Path(rect), with: .color(Theme.accent.opacity(0.16)))
        }
        let unit = max(ruler.unitPixels, 1e-6)
        let step = Guides.rulerStep(ruler.zoom * unit)
        let ticks = Guides.rulerTicks(from: ruler.start / unit, to: (ruler.start + length / ruler.zoom) / unit, step: step)
        var lines = Path()
        for tick in ticks {
            let at = screen(tick.value * unit)
            lines.move(to: point(at, thickness - (tick.major ? thickness / 2 : thickness / 5)))
            lines.addLine(to: point(at, thickness))
            if tick.major { tickLabel(&context, Guides.rulerLabel(tick.value, step: step), at: at, vertical: vertical) }
        }
        lines.move(to: point(0, thickness - 0.5))
        lines.addLine(to: point(length, thickness - 0.5))
        context.stroke(lines, with: .color(Theme.inkSecondary), lineWidth: 0.5)
        if ruler.moving, let span = ruler.span {
            var mark = Path()
            mark.move(to: point(screen(span.lowerBound), 0))
            mark.addLine(to: point(screen(span.lowerBound), thickness))
            context.stroke(mark, with: .color(Theme.accent), lineWidth: 1.5)
        }
    }

    /// A labelled tick's number, just past it: across the top ruler, and up
    /// the left one, turned to fit.
    private static func tickLabel(_ context: inout GraphicsContext, _ text: String, at: Double, vertical: Bool) {
        let shown = Text(text).font(.system(size: 9).monospacedDigit()).foregroundColor(Theme.inkSecondary)
        guard vertical else {
            context.draw(shown, at: CGPoint(x: at + 2, y: 1), anchor: .topLeading)
            return
        }
        var turned = context
        turned.translateBy(x: 1, y: at - 2)
        turned.rotate(by: .degrees(-90))
        turned.draw(shown, at: .zero, anchor: .topLeading)
    }

    /// The square where the rulers meet, naming their unit.
    private var corner: some View {
        Text(Guides.rulerUnit(store.design).unit)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
            .frame(width: thickness, height: thickness)
            .background(Theme.chrome)
    }

    // MARK: pulling out a guide

    /// A drag from a ruler: a guide across the page, `vertical` from the
    /// left ruler, following the finger.
    private func pullGesture(vertical: Bool) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let next = pull(vertical: vertical, at: value.location)
                if pulling != next { pulling = next }
            }
            .onEnded { value in
                let made = pull(vertical: vertical, at: value.location)
                pulling = nil
                guard !made.onRuler else { return }
                store.addGuide(vertical: vertical, at: made.position)
            }
    }

    /// The guide a finger at `point` on the canvas's view would make: on
    /// the page, snapped to whole units and to the elements and the page
    /// (Guides.rulerGuidePosition).
    private func pull(vertical: Bool, at point: CGPoint) -> Pull {
        let view = store.viewport
        let zoom = max(store.zoom, 0.0001)
        let start = Double(vertical ? view.minX : view.minY)
        let raw = start + Double(vertical ? point.x : point.y) / zoom
        let position = Guides.rulerGuidePosition(raw, lines: snapLines(vertical: vertical), threshold: 6 / zoom,
                                                 unitPixels: Guides.rulerUnit(store.design).pixels,
                                                 limit: vertical ? store.pageWidth : store.pageHeight)
        return Pull(vertical: vertical, position: position,
                    onRuler: Guides.onRuler(raw, viewportStart: start, zoom: zoom))
    }

    /// What a pulled guide snaps to across the page: the elements' edges
    /// and middles, and the page's, as the Snapping switches allow.
    private func snapLines(vertical: Bool) -> [Double] {
        let lines = Geometry.taggedSnapLines(design: store.design, page: store.page, excluding: [],
                                             settings: store.snapping)
        return (vertical ? lines.x : lines.y).filter { line in
            switch line.source {
            case .element, .pageEdge, .pageCentre: return true
            default: return false
            }
        }.map(\.position)
    }

    /// The guide being pulled out, across the canvas where it would go;
    /// faint while the finger is back over the ruler.
    private func pulledGuide(_ pull: Pull, in size: CGSize) -> some View {
        let view = store.viewport
        let start = Double(pull.vertical ? view.minX : view.minY)
        let at = (pull.position - start) * max(store.zoom, 0.0001)
        return Rectangle()
            .fill(Theme.guide.opacity(pull.onRuler ? 0.35 : 0.9))
            .frame(width: pull.vertical ? 1.5 : size.width, height: pull.vertical ? size.height : 1.5)
            .offset(x: pull.vertical ? at - 0.75 : 0, y: pull.vertical ? 0 : at - 0.75)
            .allowsHitTesting(false)
    }
}
