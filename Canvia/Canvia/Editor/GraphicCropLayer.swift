// Crop mode for a graphic, over the page (GraphicCropMode): the page dimmed
// but for the crop's window, the whole graphic showing faintly round it,
// and the window's brackets. A bracket trims the window from its side or
// corner, a drag inside it slides it over the graphic, and a tap anywhere
// else is Done — as a photo's crop mode has it, without the picture to
// move or zoom.

import SwiftUI

struct GraphicCropLayer: View {
    @Bindable var store: DesignStore
    let crop: GraphicCropSession
    /// What the finger took as it landed, and the window then.
    @State private var grab: Grab?

    private enum Grab {
        case handle(Handle, start: CGRect)
        case window(start: CGRect)
        case outside
    }

    private var iz: Double { 1 / max(store.zoom, 0.01) }

    var body: some View {
        let size = store.pageSize
        let window = store.graphicCropWindow ?? crop.frame.upright
        let turned = turnedPath(window)
        ZStack {
            dim(size: size, window: turned)
            turned.stroke(Color.white, lineWidth: 1.5 * iz)
            ForEach(Handle.allCases, id: \.self) { handle in
                bracket(handle, window: window)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(drag)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Crop"))
        .accessibilityHint(Text("Cropping the graphic. Pull the corners and edges to show only part of it. Done and Cancel are in the bar below."))
        .accessibilityValue(store.badge ?? Units.readout(width: Double(window.width).rounded(),
                                                          height: Double(window.height).rounded(), store.design))
    }

    /// The page dimmed, the window left clear.
    private func dim(size: CGSize, window: Path) -> some View {
        var path = Path(CGRect(origin: .zero, size: size))
        path.addPath(window)
        return path.fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
    }

    /// `window`, a box in the frame's upright box, turned with the frame
    /// onto the page.
    private func turnedPath(_ window: CGRect) -> Path {
        let c = crop.frame.center
        let turn = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: CGFloat(crop.frame.angle * .pi / 180))
            .translatedBy(x: -c.x, y: -c.y)
        return Path(window).applying(turn)
    }

    /// One bracket of the window, a fixed size on screen.
    private func bracket(_ handle: Handle, window: CGRect) -> some View {
        let at = onPage(point(handle, of: window))
        let side = (handle.isCorner ? 14 : 10) * iz
        return RoundedRectangle(cornerRadius: 2 * iz)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 2 * iz).stroke(Theme.accent, lineWidth: 1 * iz))
            .frame(width: side, height: side)
            .rotationEffect(.degrees(crop.frame.angle))
            .position(at)
            .allowsHitTesting(false)
    }

    private func point(_ handle: Handle, of window: CGRect) -> CGPoint {
        CGPoint(x: Double(window.minX) + Double(handle.unit.x) * Double(window.width),
                y: Double(window.minY) + Double(handle.unit.y) * Double(window.height))
    }

    /// A point of the frame's upright box on the page, and back.
    private func onPage(_ p: CGPoint) -> CGPoint {
        crop.frame.angle == 0 ? p : Geometry.rotate(p, around: crop.frame.center, degrees: crop.frame.angle)
    }

    private func upright(_ p: CGPoint) -> CGPoint {
        crop.frame.angle == 0 ? p : Geometry.rotate(p, around: crop.frame.center, degrees: -crop.frame.angle)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("page"))
            .onChanged { value in
                let window = store.graphicCropWindow ?? crop.frame.upright
                if grab == nil { grab = grabbed(at: upright(value.startLocation), window: window) }
                let from = upright(value.startLocation), now = upright(value.location)
                let dx = Double(now.x - from.x), dy = Double(now.y - from.y)
                switch grab {
                case .handle(let handle, let start):
                    store.setGraphicCropWindow(trimmed(start, handle: handle, dx: dx, dy: dy))
                case .window(let start):
                    store.setGraphicCropWindow(slid(start, dx: dx, dy: dy))
                case .outside, .none:
                    break
                }
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) * store.zoom
                if case .outside = grab, moved < Touch.dragSlop { store.finishGraphicCrop() }
                grab = nil
            }
    }

    /// What a finger landing at `p`, upright, takes: the nearest bracket in
    /// reach, else the window, else nothing.
    private func grabbed(at p: CGPoint, window: CGRect) -> Grab {
        let reach = Touch.pageUnits(Touch.handleReach, zoom: store.zoom)
        var best = reach
        var found: Handle?
        for handle in Handle.allCases {
            let at = point(handle, of: window)
            let d = Double(hypot(at.x - p.x, at.y - p.y))
            if d <= best {
                best = d
                found = handle
            }
        }
        if let found { return .handle(found, start: window) }
        return window.contains(p) ? .window(start: window) : .outside
    }

    /// `start` with the side or corner `handle` moved by (dx, dy), never
    /// narrower than the least share of the frame on that side or 8 units,
    /// as on Android, nor out of it.
    private func trimmed(_ start: CGRect, handle: Handle, dx: Double, dy: Double) -> CGRect {
        let frame = crop.frame.upright
        let fw = Double(frame.width), fh = Double(frame.height)
        let leastX = min(max(ClipBox.minShare * fw, 8), fw)
        let leastY = min(max(ClipBox.minShare * fh, 8), fh)
        var minX = Double(start.minX), maxX = Double(start.maxX)
        var minY = Double(start.minY), maxY = Double(start.maxY)
        if handle.unit.x == 0 { minX = min(max(minX + dx, Double(frame.minX)), maxX - leastX) }
        if handle.unit.x == 1 { maxX = max(min(maxX + dx, Double(frame.maxX)), minX + leastX) }
        if handle.unit.y == 0 { minY = min(max(minY + dy, Double(frame.minY)), maxY - leastY) }
        if handle.unit.y == 1 { maxY = max(min(maxY + dy, Double(frame.maxY)), minY + leastY) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `start` slid by (dx, dy), kept inside the frame.
    private func slid(_ start: CGRect, dx: Double, dy: Double) -> CGRect {
        let frame = crop.frame.upright
        let x = min(max(Double(start.minX) + dx, Double(frame.minX)), Double(frame.maxX) - Double(start.width))
        let y = min(max(Double(start.minY) + dy, Double(frame.minY)), Double(frame.maxY) - Double(start.height))
        return CGRect(x: x, y: y, width: start.width, height: start.height)
    }
}
