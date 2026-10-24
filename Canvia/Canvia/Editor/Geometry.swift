// Rotation-aware transform math, ported from the web module (which is
// covered by 73 unit checks): rotated-anchor resize, handle positions,
// bounding boxes, hit tests and snapping.

import CoreGraphics
import Foundation

/// Interaction constants that depend on zoom. Gesture code runs in page
/// coordinates, so every screen-point threshold has to be divided by the zoom
/// to mean what it says; getting this backwards is why a tap used to move an
/// element at fit zoom.
enum Touch {
    /// Apple's minimum comfortable target, in screen points.
    static let minTarget = 44.0
    /// How far a finger must travel on screen before a press becomes a drag.
    static let dragSlop = 10.0
    /// A drag shorter than this on screen is treated as a tap that wandered,
    /// and must not enter undo history.
    static let tapSlop = 2.0

    /// Convert a screen-point distance into page units at the current zoom.
    static func pageUnits(_ screenPoints: Double, zoom: Double) -> Double {
        screenPoints / max(zoom, 0.05)
    }

    /// Neighbouring handles along an edge are never closer than this on
    /// screen, the Android twin's HANDLE_MIN_GAP: on a small or zoomed-out
    /// element the ring of handles stands off the outline to keep them apart.
    static let handleMinGap = 17.0
    /// How far from a handle, on screen, a finger still takes it.
    static let handleReach = 22.0
    /// Inside the element a handle reaches only this far, so a touch on the
    /// body of a small element still moves it rather than resizing it.
    static let handleReachInside = 8.0

    /// The resize handles an element offers, whatever its size on screen —
    /// they stand off a small element rather than vanish from it (see
    /// handleOutset). A line's ends are discs of their own to drag
    /// (LineRoutes.hasEndHandles), so it offers none, unless both its ends
    /// are tied and it only stretches along its length; a text box follows
    /// its words, so its top and bottom are not the user's to drag unless the
    /// type is fitted to the box or aligned in it; a sticker and a QR code
    /// only scale, from their corners — a code's sides would cut into its
    /// finder squares — as on the Android twin.
    static func handleSet(for el: Element) -> [Handle] {
        let corners: [Handle] = [.nw, .ne, .se, .sw]
        switch el.type {
        // A line with ends to drag has those; an elbowed or curved one is
        // laid from its ends: neither stretches (Android Resize.offeredHandles).
        case .line: return LineRoutes.hasEndHandles(el) || LineRoutes.keepsLevel(el) ? [] : [.e, .w]
        case .text: return (el.fitText == true || el.vAlign != nil) ? Handle.allCases : [.nw, .ne, .se, .sw, .e, .w]
        case .sticker: return corners
        case .image:
            if let src = el.src, CodeGenerator.payload(from: src) != nil { return corners }
            return Handle.allCases
        case .shape: return Handle.allCases
        }
    }

    /// How far, in page units, the handle ring stands off an axis `side`
    /// page units long, so that the handles along it — corner, middle,
    /// corner — sit handleMinGap apart on screen. None once the element is
    /// big enough: a poster's handles sit exactly on its outline.
    static func handleOutset(side: Double, zoom: Double) -> Double {
        let z = max(zoom, 0.05)
        return max(0, handleMinGap - side * z / 2) / z
    }

    /// What a touch on the selection's handles takes: the NEAREST offered
    /// handle within reach — not the first, since on a small element the
    /// reaches overlap — or the rotate handle when that is nearer. Inside
    /// the element a handle reaches only handleReachInside, so the body
    /// still moves. Distances are in page units; `reach` and `inside` too.
    static func grab(at point: CGPoint, el: Element, handles: [Handle],
                     outsetX: Double, outsetY: Double, rotateAt: CGPoint?,
                     reach: Double, inside: Double) -> HandleGrab? {
        let local = el.rotation == 0 ? point : Geometry.rotate(point, around: el.center, degrees: -el.rotation)
        let onBody = el.frame.contains(local)
        var best = reach
        var found: HandleGrab?
        if let rotateAt {
            let d = Double(hypot(rotateAt.x - point.x, rotateAt.y - point.y))
            if d <= best { best = d; found = .rotate }
        }
        for handle in handles {
            let at = Geometry.handlePoint(el, handle, outsetX: outsetX, outsetY: outsetY)
            let d = Double(hypot(at.x - point.x, at.y - point.y))
            if d < best && (!onBody || d <= inside) {
                best = d
                found = .resize(handle)
            }
        }
        return found
    }

    /// The move handle's size on screen — the four-way arrows beside the
    /// rotate handle — and the on-screen short side under which an element
    /// gets one, both in points (dp on the Android twin).
    static let moveHandleSize = 28.0
    static let moveHandleBelow = 56.0

    /// Whether a single selection `el` gets the move handle, at `zoom`: free
    /// to move and shown, and either being typed into or with its shorter
    /// side under moveHandleBelow on screen — too small, or too busy, to
    /// drag by its body without covering it.
    static func showsMoveHandle(_ el: Element, zoom: Double, typing: Bool) -> Bool {
        guard !el.holdsPlace, !el.isHidden else { return false }
        return typing || min(el.w, el.h) * max(zoom, 0.05) < moveHandleBelow
    }
}

/// What a finger on the selection's handles is working.
enum HandleGrab: Equatable {
    case resize(Handle)
    case rotate
}

enum Handle: String, CaseIterable {
    case nw, n, ne, e, se, s, sw, w

    var isCorner: Bool { rawValue.count == 2 }

    var opposite: Handle {
        switch self {
        case .nw: return .se
        case .n: return .s
        case .ne: return .sw
        case .e: return .w
        case .se: return .nw
        case .s: return .n
        case .sw: return .ne
        case .w: return .e
        }
    }

    /// Fractional position of the handle on the element box.
    var unit: CGPoint {
        switch self {
        case .nw: return CGPoint(x: 0, y: 0)
        case .n: return CGPoint(x: 0.5, y: 0)
        case .ne: return CGPoint(x: 1, y: 0)
        case .e: return CGPoint(x: 1, y: 0.5)
        case .se: return CGPoint(x: 1, y: 1)
        case .s: return CGPoint(x: 0.5, y: 1)
        case .sw: return CGPoint(x: 0, y: 1)
        case .w: return CGPoint(x: 0, y: 0.5)
        }
    }
}

enum Geometry {

    static func rotate(_ p: CGPoint, around c: CGPoint, degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(
            x: c.x + dx * CoreGraphics.cos(a) - dy * CoreGraphics.sin(a),
            y: c.y + dx * CoreGraphics.sin(a) + dy * CoreGraphics.cos(a))
    }

    /// Canvas-space position of a named handle on a (possibly rotated) element.
    static func handlePoint(_ el: Element, _ handle: Handle) -> CGPoint {
        let u = handle.unit
        let local = CGPoint(x: el.x + el.w * u.x, y: el.y + el.h * u.y)
        guard el.rotation != 0 else { return local }
        return rotate(local, around: el.center, degrees: el.rotation)
    }

    /// The same, pushed out along the element's own axes by an outset in
    /// page units — where the handle is drawn on a small element, off its
    /// outline (see Touch.handleOutset).
    static func handlePoint(_ el: Element, _ handle: Handle, outsetX: Double, outsetY: Double) -> CGPoint {
        let u = handle.unit
        let sx = (u.x - 0.5) * 2, sy = (u.y - 0.5) * 2
        let c = el.center
        let local = CGPoint(x: c.x + sx * (el.w / 2 + outsetX), y: c.y + sy * (el.h / 2 + outsetY))
        guard el.rotation != 0 else { return local }
        return rotate(local, around: c, degrees: el.rotation)
    }

    /// The rotate handle: `offset` page units beyond the element's foot
    /// along its own "down" — or beyond its head when `above` — turned with
    /// it.
    static func rotateHandlePosition(_ el: Element, offset: Double, above: Bool = false) -> CGPoint {
        let c = el.center
        let reach = el.h / 2 + offset
        return rotate(CGPoint(x: c.x, y: c.y + (above ? -reach : reach)), around: c, degrees: el.rotation)
    }

    /// The move handle, beside the rotate handle: as far beyond the same
    /// edge, and that same `offset` along the element's own "left" of it —
    /// so the two never sit on each other, and the move handle stays on the
    /// rotate handle's side, away from the quick actions. The Android twin's
    /// Geometry.moveHandlePosition, row for row; its turn handle sits above,
    /// so it passes `above`.
    static func moveHandlePosition(_ el: Element, offset: Double, above: Bool = false) -> CGPoint {
        let c = el.center
        let reach = el.h / 2 + offset
        return rotate(CGPoint(x: c.x - offset, y: c.y + (above ? -reach : reach)), around: c, degrees: el.rotation)
    }

    /// Resize keeping the opposite anchor fixed in canvas space.
    /// Returns the new (x, y, w, h); rotation is unchanged.
    static func resize(_ el: Element, handle: Handle, to mouse: CGPoint,
                       proportional: Bool, minSize: Double = 8) -> CGRect {
        let anchorHandle = handle.opposite
        let anchor = handlePoint(el, anchorHandle)
        let hu = handle.unit, au = anchorHandle.unit

        // Un-rotate the anchor->mouse vector into the element's local frame.
        let v = rotate(mouse, around: anchor, degrees: -el.rotation)
        let dx = v.x - anchor.x
        let dy = v.y - anchor.y

        let sx: Double = hu.x == au.x ? 0 : (hu.x > au.x ? 1 : -1)
        let sy: Double = hu.y == au.y ? 0 : (hu.y > au.y ? 1 : -1)

        var w = sx == 0 ? el.w : max(minSize, dx * sx)
        var h = sy == 0 ? el.h : max(minSize, dy * sy)

        if proportional && sx != 0 && sy != 0 {
            let ratio = el.w / el.h
            if w / h > ratio { w = h * ratio } else { h = w / ratio }
            w = max(minSize, w); h = max(minSize, h)
            if w / h > ratio { h = w / ratio } else { w = h * ratio }
        }

        // Re-place so the anchor maps back to the same canvas position.
        let ux = (au.x - 0.5) * w
        let uy = (au.y - 0.5) * h
        let ru = rotate(CGPoint(x: ux, y: uy), around: .zero, degrees: el.rotation)
        let cx = anchor.x - ru.x
        let cy = anchor.y - ru.y
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// Angle (degrees, 0 = up, clockwise) of a point around a center.
    static func angle(from center: CGPoint, to p: CGPoint) -> Double {
        let deg = atan2(p.y - center.y, p.x - center.x) * 180 / .pi + 90
        return (deg.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    static func snapAngle(_ deg: Double, step: Double = 45, threshold: Double = 5) -> Double {
        let nearest = (deg / step).rounded() * step
        if abs(deg - nearest) <= threshold {
            return (nearest.truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360)
        }
        return deg
    }

    /// Axis-aligned bounding box of a rotated element.
    static func aabb(_ el: Element) -> CGRect {
        guard el.rotation != 0 else { return el.frame }
        let c = el.center
        let corners = [
            CGPoint(x: el.x, y: el.y),
            CGPoint(x: el.x + el.w, y: el.y),
            CGPoint(x: el.x + el.w, y: el.y + el.h),
            CGPoint(x: el.x, y: el.y + el.h),
        ].map { rotate($0, around: c, degrees: el.rotation) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!,
                      width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    static func union(_ rects: [CGRect]) -> CGRect {
        guard var result = rects.first else { return .zero }
        for r in rects.dropFirst() { result = result.union(r) }
        return result
    }

    /// Hit test respecting rotation: an elbowed or curved line on its
    /// route (LineRoutes.near), warped words in the hull of their bent box
    /// (TextWarp.hull), anything else in its turned frame — the part of it
    /// a crop shows (GraphicClip.visibleFrame). A hidden element is never
    /// hit.
    static func hits(_ el: Element, point: CGPoint) -> Bool {
        guard !el.isHidden else { return false }
        if LineRoutes.keepsLevel(el) { return LineRoutes.near(el, point, reach: 4) }
        let p = el.rotation == 0 ? point : rotate(point, around: el.center, degrees: -el.rotation)
        var frame = GraphicClip.visibleFrame(el)
        if TextWarp.isWarped(el), let warp = el.warp {
            frame = TextWarp.hull(warp, w: el.w, h: el.h).offsetBy(dx: el.x, dy: el.y)
        }
        return frame.insetBy(dx: -4, dy: -4).contains(p)
    }

    // MARK: snapping

    struct Snap {
        var dx: Double = 0
        var dy: Double = 0
        var guideX: Double?
        var guideY: Double?
    }

    /// Snap a moving box against candidate x/y lines within a threshold.
    static func snap(box: CGRect, xLines: [Double], yLines: [Double], threshold: Double) -> Snap {
        var result = Snap()
        let movingX = [box.minX, box.midX, box.maxX]
        let movingY = [box.minY, box.midY, box.maxY]
        var bestDx: Double?
        var bestDy: Double?
        for line in xLines {
            for mx in movingX {
                let d = line - mx
                if abs(d) <= threshold && (bestDx == nil || abs(d) < abs(bestDx!)) {
                    bestDx = d
                    result.guideX = line
                }
            }
        }
        for line in yLines {
            for my in movingY {
                let d = line - my
                if abs(d) <= threshold && (bestDy == nil || abs(d) < abs(bestDy!)) {
                    bestDy = d
                    result.guideY = line
                }
            }
        }
        result.dx = bestDx ?? 0
        result.dy = bestDy ?? 0
        return result
    }

    struct ResizeSnap {
        var box: CGRect
        var guideX: Double?
        var guideY: Double?
    }

    /// A box being resized from `handle`, its moving edges pulled onto the
    /// nearest of the lines a move snaps to, within `threshold`, while the
    /// edges across from them stay put. A side moves one edge; a free corner
    /// moves two, one on each axis, and each snaps. A corner that keeps the
    /// shape (`proportional`) snaps on one axis only — whichever needs the
    /// smaller correction — and the other follows through the shape. A snap
    /// that would take either side under `minSize`, or turn the box inside
    /// out, is not made. The box is an unturned element's: one turned is
    /// snapped through snapTurnedResize.
    static func snapResize(_ box: CGRect, handle: Handle, xLines: [Double], yLines: [Double],
                           threshold: Double, proportional: Bool, minSize: Double) -> ResizeSnap {
        let u = handle.unit
        // The fixed edge on each axis, and which way from it the moving one
        // lies: +1 when the handle is on the far side, -1 on the near side,
        // 0 when the handle moves no edge on that axis.
        let fixedX = Double(u.x == 0 ? box.maxX : box.minX)
        let fixedY = Double(u.y == 0 ? box.maxY : box.minY)
        let width = Double(box.width), height = Double(box.height)
        let sx: Double = u.x == 0.5 ? 0 : (u.x == 1 ? 1 : -1)
        let sy: Double = u.y == 0.5 ? 0 : (u.y == 1 ? 1 : -1)

        /// The line nearest the moving edge, within reach, that leaves the
        /// side at least `minSize` long; nil when there is none.
        func nearest(_ lines: [Double], fixed: Double, side: Double, sign: Double) -> Double? {
            guard sign != 0 else { return nil }
            let edge = fixed + sign * side
            var best: Double?
            for line in lines where abs(line - edge) <= threshold && (line - fixed) * sign >= minSize {
                if let found = best, abs(found - edge) <= abs(line - edge) { continue }
                best = line
            }
            return best
        }

        /// The box with sides `w` × `h`, grown from the fixed edges.
        func placed(_ w: Double, _ h: Double) -> CGRect {
            let x: Double = sx < 0 ? fixedX - w : (sx > 0 ? fixedX : Double(box.minX))
            let y: Double = sy < 0 ? fixedY - h : (sy > 0 ? fixedY : Double(box.minY))
            return CGRect(x: x, y: y, width: w, height: h)
        }

        var result = ResizeSnap(box: box)
        let lineX = nearest(xLines, fixed: fixedX, side: width, sign: sx)
        let lineY = nearest(yLines, fixed: fixedY, side: height, sign: sy)

        if proportional && sx != 0 && sy != 0 {
            guard width > 0, height > 0 else { return result }
            let ratio = width / height
            let edgeX = fixedX + sx * width, edgeY = fixedY + sy * height
            let byX: Double = lineX.map { abs($0 - edgeX) } ?? .infinity
            let byY: Double = lineY.map { abs($0 - edgeY) } ?? .infinity
            if let lx = lineX, byX <= byY {
                let w = (lx - fixedX) * sx
                guard w / ratio >= minSize else { return result }
                result.box = placed(w, w / ratio)
                result.guideX = lx
            } else if let ly = lineY {
                let h = (ly - fixedY) * sy
                guard h * ratio >= minSize else { return result }
                result.box = placed(h * ratio, h)
                result.guideY = ly
            }
            return result
        }

        let w: Double = lineX.map { ($0 - fixedX) * sx } ?? width
        let h: Double = lineY.map { ($0 - fixedY) * sy } ?? height
        result.box = placed(w, h)
        result.guideX = lineX
        result.guideY = lineY
        return result
    }

    /// snapResize for an element turned a whole number of quarter turns,
    /// as the Android twin snaps one: `box` is its own frame, turned
    /// `rotation` degrees about its centre. The handle is taken to where
    /// the turn points it, the frame's bounds on the page snap from there,
    /// and the bounds are made the element's frame again about the same
    /// centre. Nil for one turned off the square: its edges do not run
    /// along the lines.
    static func snapTurnedResize(_ box: CGRect, rotation: Double, handle: Handle,
                                 xLines: [Double], yLines: [Double],
                                 threshold: Double, proportional: Bool, minSize: Double) -> ResizeSnap? {
        let turn = (rotation.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let quarters = (turn / 90).rounded()
        guard abs(turn - quarters * 90) <= 1e-6 else { return nil }
        let turns = Int(quarters) % 4
        // A quarter turn clockwise points the right side down, and so on.
        var dx = handle.unit.x - 0.5, dy = handle.unit.y - 0.5
        for _ in 0..<turns { (dx, dy) = (-dy, dx) }
        let point = CGPoint(x: dx + 0.5, y: dy + 0.5)
        guard let turned = Handle.allCases.first(where: { $0.unit == point }) else { return nil }
        // Half a turn leaves the bounds the frame itself.
        guard turns % 2 == 1 else {
            return snapResize(box, handle: turned, xLines: xLines, yLines: yLines,
                              threshold: threshold, proportional: proportional, minSize: minSize)
        }
        let bounds = CGRect(x: box.midX - box.height / 2, y: box.midY - box.width / 2,
                            width: box.height, height: box.width)
        var snap = snapResize(bounds, handle: turned, xLines: xLines, yLines: yLines,
                              threshold: threshold, proportional: proportional, minSize: minSize)
        let w = snap.box.height, h = snap.box.width
        snap.box = CGRect(x: snap.box.midX - w / 2, y: snap.box.midY - h / 2, width: w, height: h)
        return snap
    }

    struct EqualGap {
        var dx: Double = 0
        var dy: Double = 0
        /// The gap made equal on each axis, when one was.
        var gapX: Double?
        var gapY: Double?
    }

    /// Equal-spacing detection: when the moving box sits between two
    /// neighbours on an axis (overlapping them on the other) and its two
    /// gaps are within `threshold` of each other, the shift that makes them
    /// equal — and the gap, for the badge.
    static func equalGap(moving: CGRect, siblings: [CGRect], threshold: Double) -> EqualGap {
        var result = EqualGap()
        let besideY = siblings.filter { $0.maxY > moving.minY && $0.minY < moving.maxY }
        let left = besideY.filter { $0.maxX <= moving.minX + 0.5 }.max { $0.maxX < $1.maxX }
        let right = besideY.filter { $0.minX >= moving.maxX - 0.5 }.min { $0.minX < $1.minX }
        if let left, let right {
            let gl = moving.minX - left.maxX, gr = right.minX - moving.maxX
            if abs(gl - gr) <= threshold * 2 {
                result.dx = (gr - gl) / 2
                result.gapX = ((gl + gr) / 2).rounded()
            }
        }
        let besideX = siblings.filter { $0.maxX > moving.minX && $0.minX < moving.maxX }
        let above = besideX.filter { $0.maxY <= moving.minY + 0.5 }.max { $0.maxY < $1.maxY }
        let below = besideX.filter { $0.minY >= moving.maxY - 0.5 }.min { $0.minY < $1.minY }
        if let above, let below {
            let ga = moving.minY - above.maxY, gb = below.minY - moving.maxY
            if abs(ga - gb) <= threshold * 2 {
                result.dy = (gb - ga) / 2
                result.gapY = ((ga + gb) / 2).rounded()
            }
        }
        return result
    }

    // MARK: matching gaps and sizes

    /// Two neighbours in a row (`alongX`) or a column, `a` before `b`.
    struct GapPair: Equatable {
        var a: CGRect
        var b: CGRect
        var alongX: Bool

        /// The gap between them.
        var gap: Double { Double(alongX ? b.minX - a.maxX : b.minY - a.maxY) }

        /// Where a bracket across the gap runs: from `a`'s near edge to
        /// `b`'s, through the middle of the span the two share.
        var ends: (from: CGPoint, to: CGPoint) {
            if alongX {
                let y = (max(a.minY, b.minY) + min(a.maxY, b.maxY)) / 2
                return (CGPoint(x: a.maxX, y: y), CGPoint(x: b.minX, y: y))
            }
            let x = (max(a.minX, b.minX) + min(a.maxX, b.maxX)) / 2
            return (CGPoint(x: x, y: a.maxY), CGPoint(x: x, y: b.minY))
        }
    }

    /// Whether `a` and `b` overlap across the axis a row (`alongX`) or a
    /// column runs along — share some height for a row, some width for a
    /// column; touching does not count.
    private static func beside(_ a: CGRect, _ b: CGRect, alongX: Bool) -> Bool {
        alongX ? a.maxY > b.minY && a.minY < b.maxY : a.maxX > b.minX && a.minX < b.maxX
    }

    /// Each box's nearest neighbour after it among some boxes, in rows
    /// (`alongX`) or columns — the one gapPairs pairs it with, touching or
    /// not — by its place among them, or -1 for none. Worked out once for
    /// the siblings of a drag, which do not move while it lasts, so that
    /// each frame's gap matching is a pass over them rather than a pass per
    /// box. The Android twin's Geometry.Neighbours.
    struct Neighbours {
        let alongX: Bool
        fileprivate let next: [Int]
    }

    /// The `Neighbours` of `boxes` in rows (`alongX`) or columns: each box's
    /// nearest after it that overlaps it across the axis, the first on a tie.
    static func neighbours(_ boxes: [CGRect], alongX: Bool) -> Neighbours {
        var next = [Int](repeating: -1, count: boxes.count)
        for (i, a) in boxes.enumerated() {
            var found = -1
            for (j, b) in boxes.enumerated() {
                if j == i || !beside(a, b, alongX: alongX) || (alongX ? b.minX < a.maxX : b.minY < a.maxY) { continue }
                if found < 0 || (alongX ? b.minX < boxes[found].minX : b.minY < boxes[found].minY) { found = j }
            }
            next[i] = found
        }
        return Neighbours(alongX: alongX, next: next)
    }

    /// Every gap between neighbours among `boxes` in rows (`alongX`) or
    /// columns: each box and the nearest box after it that overlaps it
    /// across the axis — the simplest rule, the same on both phones (the
    /// Android twin's Geometry.gapPairs). A gap of half a unit or less is
    /// two things touching, not a gap.
    static func gapPairs(_ boxes: [CGRect], alongX: Bool) -> [GapPair] {
        gapPairs(boxes, near: neighbours(boxes, alongX: alongX))
    }

    /// The gaps among `boxes` from their nearest neighbours, in their order.
    private static func gapPairs(_ boxes: [CGRect], near: Neighbours) -> [GapPair] {
        var out: [GapPair] = []
        for i in boxes.indices {
            let j = near.next[i]
            if j < 0 { continue }
            let pair = GapPair(a: boxes[i], b: boxes[j], alongX: near.alongX)
            if pair.gap > 0.5 { out.append(pair) }
        }
        return out
    }

    /// The gaps among `siblings` and `moving` together — gapPairs of the
    /// two, from the siblings' nearest neighbours alone: a sibling's gap to
    /// the moving box where it now comes before that sibling's own next,
    /// else its own; then the moving box's to the nearest sibling after it.
    /// In the siblings' order, the moving box's last, as gapPairs lists
    /// them; `mine` marks the moving box's own.
    private static func gapPairsWith(moving: CGRect, siblings: [CGRect],
                                     near: Neighbours) -> [(mine: Bool, pair: GapPair)] {
        let alongX = near.alongX
        func close(_ r: CGRect) -> CGFloat { alongX ? r.minX : r.minY }
        func far(_ r: CGRect) -> CGFloat { alongX ? r.maxX : r.maxY }
        var out: [(mine: Bool, pair: GapPair)] = []
        for (i, a) in siblings.enumerated() {
            let j = near.next[i]
            let movingNext = beside(a, moving, alongX: alongX) && close(moving) >= far(a)
                && (j < 0 || close(moving) < close(siblings[j]))
            if movingNext {
                let pair = GapPair(a: a, b: moving, alongX: alongX)
                if pair.gap > 0.5 { out.append((mine: true, pair: pair)) }
            } else if j >= 0 {
                let pair = GapPair(a: a, b: siblings[j], alongX: alongX)
                if pair.gap > 0.5 { out.append((mine: false, pair: pair)) }
            }
        }
        var next: CGRect?
        for b in siblings {
            if !beside(moving, b, alongX: alongX) || close(b) < far(moving) { continue }
            if let seen = next, close(b) >= close(seen) { continue }
            next = b
        }
        if let next {
            let pair = GapPair(a: moving, b: next, alongX: alongX)
            if pair.gap > 0.5 { out.append((mine: true, pair: pair)) }
        }
        return out
    }

    /// The gaps as wide as one of `moving`'s own to its neighbours among
    /// `siblings`, within `tolerance`, in rows (`alongX`) or columns — its
    /// own among them — where there are at least two: what draws a
    /// bracket. None where its gaps match nothing. `near` is the siblings'
    /// neighbours on that axis, worked out once for a drag; else they are
    /// worked out here.
    static func equalGapPairs(_ moving: CGRect, siblings: [CGRect], alongX: Bool,
                              tolerance: Double = 0.5, near: Neighbours? = .none) -> [GapPair] {
        let pairs = gapPairsWith(moving: moving, siblings: siblings,
                                 near: near ?? neighbours(siblings, alongX: alongX))
        var out: [GapPair] = []
        var taken: Set<Int> = []
        for own in pairs where own.mine {
            let same = pairs.indices.filter { abs(pairs[$0].pair.gap - own.pair.gap) <= tolerance }
            guard same.count >= 2 else { continue }
            for k in same where !taken.contains(k) {
                taken.insert(k)
                out.append(pairs[k].pair)
            }
        }
        return out
    }

    /// The shift that makes a moving box's gap to a neighbour match a gap
    /// already there, per axis; the gap matched (whole) for the readout,
    /// and the equal gaps to bracket.
    struct MatchingGap {
        var dx: Double = 0
        var dy: Double = 0
        var gapX: Double?
        var gapY: Double?
        var pairs: [GapPair] = []
    }

    /// Gap matching, as Canva's smart guides find it — a third card added to
    /// a row at the gap the first two have: the gaps between every pair of
    /// neighbours among `siblings` (gapPairs); when the moving box's gap to
    /// its nearest neighbour on either side (overlapping it on the other
    /// axis, touching counting, as equalGap finds them) is within
    /// `threshold` of one of them, the shift that makes it that gap — the
    /// smallest such shift, the left (top) side on a tie — and the equal
    /// gaps then, its own among them. The page's edges are never
    /// neighbours. `nearX` and `nearY` are the siblings' neighbours in rows
    /// and columns, worked out once for a drag, which does not move them;
    /// else they are worked out here. The Android twin's
    /// Geometry.matchingGap, over the same test vectors.
    static func matchingGap(moving: CGRect, siblings: [CGRect], threshold: Double,
                            nearX: Neighbours? = .none, nearY: Neighbours? = .none) -> MatchingGap {
        let rows = nearX ?? neighbours(siblings, alongX: true)
        let columns = nearY ?? neighbours(siblings, alongX: false)
        func axis(_ alongX: Bool) -> (shift: Double, gap: Double)? {
            let existing = gapPairs(siblings, near: alongX ? rows : columns).map(\.gap)
            guard !existing.isEmpty else { return nil }
            let near = siblings.filter { beside($0, moving, alongX: alongX) }
            let low = Double(alongX ? moving.minX : moving.minY)
            let high = Double(alongX ? moving.maxX : moving.maxY)
            func far(_ r: CGRect) -> Double { Double(alongX ? r.maxX : r.maxY) }
            func close(_ r: CGRect) -> Double { Double(alongX ? r.minX : r.minY) }
            let before = near.filter { far($0) <= low + 0.5 }.max { far($0) < far($1) }
            let after = near.filter { close($0) >= high - 0.5 }.min { close($0) < close($1) }
            // The gap before it grows as it moves on; the gap after shrinks.
            var sides: [(now: Double, sign: Double)] = []
            if let before { sides.append((now: low - far(before), sign: 1)) }
            if let after { sides.append((now: close(after) - high, sign: -1)) }
            var best: (shift: Double, gap: Double)?
            for side in sides {
                for gap in existing where abs(side.now - gap) <= threshold {
                    let shift = (gap - side.now) * side.sign
                    if best == nil || abs(shift) < abs(best?.shift ?? 0) { best = (shift: shift, gap: gap) }
                }
            }
            return best
        }
        let x = axis(true), y = axis(false)
        var result = MatchingGap(dx: x?.shift ?? 0, dy: y?.shift ?? 0,
                                 gapX: x.map { $0.gap.rounded() }, gapY: y.map { $0.gap.rounded() })
        let moved = moving.offsetBy(dx: result.dx, dy: result.dy)
        if x != nil { result.pairs += equalGapPairs(moved, siblings: siblings, alongX: true, near: rows) }
        if y != nil { result.pairs += equalGapPairs(moved, siblings: siblings, alongX: false, near: columns) }
        return result
    }

    /// Whether a resize of `el` matches sizes at all: only an element square
    /// to the page — turned by nothing, or by whole turns — whose edges lie
    /// along the lines a snap finds, as they do, and never a line, whose
    /// length is its own. The same rule on both phones.
    static func matchesSizes(_ el: Element) -> Bool {
        let turn = (el.rotation.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return el.type != .line && turn == 0
    }

    /// A box whose width (else its height) a resize has matched, the
    /// resized one among them: the canvas marks it "=".
    struct SizeMark: Equatable {
        var box: CGRect
        var width: Bool
    }

    /// A resized box's width and height, matched to another's where one
    /// came within reach, and which siblings it matched each to.
    struct MatchingSize {
        var w: Double
        var h: Double
        var widthOf: [String] = []
        var heightOf: [String] = []
    }

    /// Size matching, as Canva's guides find it while resizing: the side
    /// `handle` stretches — its width for a left or right edge, its height
    /// for a top or bottom one, both for a corner — snapped to the width
    /// (height) of a sibling's turned bounds within `threshold`, the nearest
    /// one. A corner that keeps the proportions (`proportional`) matches one
    /// side, the one needing the smaller change (the width on a tie), and
    /// scales the other with it. The matched siblings are every one of that
    /// size, within half a unit. The Android twin's Geometry.matchingSize.
    static func matchingSize(_ box: CGRect, handle: Handle, siblings: [Element], threshold: Double,
                             proportional: Bool = false) -> MatchingSize {
        let sizes = siblings.map { ($0.id, aabb($0)) }
        func nearest(_ value: Double, _ of: (CGRect) -> Double) -> Double? {
            sizes.map { of($0.1) }.filter { abs($0 - value) <= threshold }.min { abs($0 - value) < abs($1 - value) }
        }
        func matching(_ value: Double, _ of: (CGRect) -> Double) -> [String] {
            sizes.filter { abs(of($0.1) - value) <= 0.5 }.map { $0.0 }
        }
        let width: (CGRect) -> Double = { Double($0.width) }
        let height: (CGRect) -> Double = { Double($0.height) }
        let bw = Double(box.width), bh = Double(box.height)
        var w = handle.unit.x != 0.5 ? nearest(bw, width) : nil
        var h = handle.unit.y != 0.5 ? nearest(bh, height) : nil
        if proportional && (w != nil || h != nil) {
            let byWidth: Bool
            if let w, let h { byWidth = abs(w - bw) <= abs(h - bh) } else { byWidth = w != nil }
            if byWidth, let matched = w {
                h = bw > 0 ? bh * matched / bw : bh
            } else if let matched = h {
                w = bh > 0 ? bw * matched / bh : bw
            }
            let sw = w ?? bw, sh = h ?? bh
            return MatchingSize(w: sw, h: sh, widthOf: byWidth ? matching(sw, width) : [],
                                heightOf: byWidth ? [] : matching(sh, height))
        }
        return MatchingSize(w: w ?? bw, h: h ?? bh,
                            widthOf: w.map { matching($0, width) } ?? [],
                            heightOf: h.map { matching($0, height) } ?? [])
    }

    /// Candidate snap lines: page edges/center — and a bleed's edges — plus
    /// sibling edges/centers, plus every grid line when a grid is on — each
    /// source only if its switch is.
    static func snapLines(design: Design, page: Page, excluding ids: Set<String>,
                          settings: SnapSettings = SnapSettings()) -> (x: [Double], y: [Double]) {
        let tagged = taggedSnapLines(design: design, page: page, excluding: ids, settings: settings)
        return (tagged.x.map(\.position), tagged.y.map(\.position))
    }

    /// Where a snap line comes from, so the guide can say what it has lined
    /// the selection up with.
    enum SnapSource: Equatable {
        case pageEdge, pageCentre, guide, grid, margin
        /// The outer edge of a print bleed shown (Bleed).
        case bleedEdge
        case element(String)

        /// Which of two lines in the same place names the guide: one placed
        /// on purpose first, then another element, then the page's own lines
        /// — as the Android twin, where the later of page, elements and
        /// guides wins a tie.
        var rank: Int {
            switch self {
            case .guide: return 0
            case .element: return 1
            case .pageCentre: return 2
            case .pageEdge: return 3
            case .bleedEdge: return 4
            case .margin: return 5
            case .grid: return 6
            }
        }
    }

    struct SnapLine: Equatable {
        var position: Double
        var source: SnapSource
    }

    /// The snap lines, each with where it comes from.
    static func taggedSnapLines(design: Design, page: Page, excluding ids: Set<String>,
                                settings: SnapSettings = SnapSettings()) -> (x: [SnapLine], y: [SnapLine]) {
        var xs: [SnapLine] = []
        var ys: [SnapLine] = []
        let size = design.size(for: page)
        let pw = Double(size.width), ph = Double(size.height)
        if settings.toPage {
            xs += [SnapLine(position: 0, source: .pageEdge), SnapLine(position: pw / 2, source: .pageCentre),
                   SnapLine(position: pw, source: .pageEdge)]
            ys += [SnapLine(position: 0, source: .pageEdge), SnapLine(position: ph / 2, source: .pageCentre),
                   SnapLine(position: ph, source: .pageEdge)]
            // With a print bleed shown, its outer edge is a line of the
            // page's too, the bleed beyond each side, so a photo can be
            // pulled out to it.
            let bleed = Bleed.of(design)
            if bleed > 0 {
                xs += [SnapLine(position: -bleed, source: .bleedEdge), SnapLine(position: pw + bleed, source: .bleedEdge)]
                ys += [SnapLine(position: -bleed, source: .bleedEdge), SnapLine(position: ph + bleed, source: .bleedEdge)]
            }
        }
        if settings.toElements {
            for el in page.elements where !ids.contains(el.id) && !el.isHidden {
                let b = aabb(el)
                xs += [b.minX, b.midX, b.maxX].map { SnapLine(position: $0, source: .element(el.id)) }
                ys += [b.minY, b.midY, b.maxY].map { SnapLine(position: $0, source: .element(el.id)) }
            }
        }
        if settings.gridEnabled {
            xs += gridLines(across: pw, spacing: settings.grid).map { SnapLine(position: $0, source: .grid) }
            ys += gridLines(across: ph, spacing: settings.grid).map { SnapLine(position: $0, source: .grid) }
        }
        if settings.marginEnabled {
            let m = settings.marginInset(for: size)
            xs += [SnapLine(position: m, source: .margin), SnapLine(position: pw - m, source: .margin)]
            ys += [SnapLine(position: m, source: .margin), SnapLine(position: ph - m, source: .margin)]
        }
        // Guides are placed on purpose, so they snap whatever else is off.
        for guide in design.guides {
            let line = SnapLine(position: guide.position, source: .guide)
            if guide.vertical { xs.append(line) } else { ys.append(line) }
        }
        return (xs, ys)
    }

    /// What the line at `position` — the one a snap landed on — is: of the
    /// lines there, the one that best names it.
    static func snapSource(at position: Double?, in lines: [SnapLine]) -> SnapSource? {
        guard let position else { return nil }
        return lines.filter { abs($0.position - position) < 1e-9 }
            .min { $0.source.rank < $1.source.rank }?.source
    }

    /// 0, spacing, 2·spacing … up to and including the far edge.
    static func gridLines(across length: Double, spacing: Double) -> [Double] {
        guard spacing > 0, length > 0 else { return [] }
        return stride(from: 0, through: length, by: spacing).map { $0 }
    }

    /// The spacing the grid is drawn at, `scale` screen points to a page
    /// unit: doubled until its lines stand at least `minGap` apart, so a
    /// dense grid never turns the page into a tint, as on the Android twin.
    /// It is still snapped to line by line.
    static func drawnGridSpacing(_ spacing: Double, scale: Double, minGap: Double) -> Double {
        guard spacing > 0, scale > 0 else { return spacing }
        var step = spacing
        while step * scale < minGap { step *= 2 }
        return step
    }

    /// How much a `width` × `height` picture turned by `degrees` has to grow
    /// to still cover a frame of the same size. A levelled horizon must not
    /// show the frame's corners through the picture's.
    static func coverScale(width: Double, height: Double, degrees: Double) -> Double {
        guard width > 0, height > 0 else { return 1 }
        let r = abs(degrees) * .pi / 180
        let c = abs(cos(r)), s = abs(sin(r))
        // The rotated frame's bounding box, which the unrotated picture must
        // span in both directions.
        let needW = width * c + height * s
        let needH = width * s + height * c
        return max(needW / width, needH / height, 1)
    }

    // MARK: selection and group transforms

    /// The elements a rubber band drawn over `rect` picks up: anything
    /// unlocked and shown whose box it touches. Touching, not containing — a
    /// marquee that had to swallow an element whole would miss everything
    /// larger than the screen at the current zoom.
    static func intersecting(_ elements: [Element], _ rect: CGRect) -> [Element] {
        guard rect.width > 0 || rect.height > 0 else { return [] }
        return elements.filter { !$0.locked && !$0.isHidden && aabb(LineRoutes.outlineOf($0)).intersects(rect) }
    }

    /// Scale a set of elements together so that the box `from` (their
    /// union, at grab time) becomes `to`. Positions, sizes and text sizes all
    /// scale; rotations are kept, which is exact only for a uniform scale —
    /// which is why a group offers corner handles and nothing else. A table
    /// cell's spacing scales as its type does (TableCell.scaledPad).
    static func scale(_ elements: [Element], from: CGRect, to: CGRect,
                      minSize: Double = 4) -> [Element] {
        guard from.width > 0, from.height > 0 else { return elements }
        let sx = to.width / from.width
        let sy = to.height / from.height
        return elements.map { el in
            var e = el
            let cx = to.minX + (el.center.x - from.minX) * sx
            let cy = to.minY + (el.center.y - from.minY) * sy
            e.w = max(minSize, el.w * sx)
            // A straight line's height is its stroke, not a dimension of its
            // box; an elbow's or a curve's is its route's.
            e.h = el.type == .line && !LineRoutes.keepsLevel(el) ? el.h : max(minSize, el.h * sy)
            e.x = cx - e.w / 2
            e.y = cy - e.h / 2
            e.table = TableCell.scaledPad(el.table, by: min(sx, sy))
            if el.type == .text {
                let type = Double(min(sx, sy))
                // To one decimal place, as a size is typed, and past 800
                // if the drag takes it there.
                e.fontSize = max(6, TypeReadouts.tenth((el.fontSize ?? 42) * type))
                // Letter spacing is in page units, so it scales with the
                // type, as one box's corner scales it and the Android twin's
                // scaleAll does.
                e.letterSpacing = el.letterSpacing.map { $0 * type }
            }
            return e
        }
    }

    /// Turn a set of elements as one about `center` by `degrees`: each moves
    /// around the pivot and turns by the same amount on its own axis.
    static func rotate(_ elements: [Element], around center: CGPoint,
                       by degrees: Double) -> [Element] {
        elements.map { el in
            var e = el
            let c = rotate(el.center, around: center, degrees: degrees)
            e.x = c.x - el.w / 2
            e.y = c.y - el.h / 2
            e.rotation = ((el.rotation + degrees).truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360)
            return e
        }
    }

    /// The smallest type a pinch scales text down to: the Android twin's
    /// Resize.MIN_FONT_SIZE.
    static let minFontSize = 4.0

    /// `elements` pinched with two fingers about `centre`: scaled `scale`
    /// times — the ratio of the fingers' distances — and turned `turnDeg`,
    /// the change in the angle between them, each as a corner scales it
    /// (the Android twin's Resize.Kind.SCALE). Text scales its type and
    /// letter spacing; photos, stickers and shapes scale evenly, a photo's
    /// crop being all proportions; a straight line changes its length and
    /// keeps its thickness; a group scales and turns about its middle — when
    /// they are all one group's members, more than one, its groupTurn goes
    /// on with them, as on Android; anything else keeps its own. One
    /// factor for
    /// them all, never so small that a side goes under `minSize` or type
    /// under minFontSize (nor forced up for what is already smaller). What
    /// holds its place stays as it is. The Android twin's Geometry.pinched.
    static func pinched(_ elements: [Element], centre: CGPoint, scale: Double, turnDeg: Double,
                        minSize: Double = 8) -> [Element] {
        let free = elements.filter { !$0.holdsPlace }
        guard !free.isEmpty, scale.isFinite, scale > 0, turnDeg.isFinite else { return elements }
        let floor = free.map { pinchFloor($0, minSize: minSize) }.max() ?? 0
        let s = max(scale, min(floor, 1))
        let group = elements.first?.group
        let wholeGroup = elements.count > 1 && group != nil && elements.allSatisfy { $0.group == group }
        return elements.map { el in
            guard !el.holdsPlace else { return el }
            var e = el
            let straight = el.type == .line && !LineRoutes.keepsLevel(el)
            e.w = el.w * s
            e.h = straight ? el.h : el.h * s
            let spread = CGPoint(x: Double(centre.x) + Double(el.center.x - centre.x) * s,
                                 y: Double(centre.y) + Double(el.center.y - centre.y) * s)
            let c = rotate(spread, around: centre, degrees: turnDeg)
            e.x = Double(c.x) - e.w / 2
            e.y = Double(c.y) - e.h / 2
            e.table = TableCell.scaledPad(el.table, by: s)
            if el.type == .text {
                e.fontSize = max(minFontSize, TypeReadouts.tenth((el.fontSize ?? 42) * s))
                e.letterSpacing = el.letterSpacing.map { $0 * s }
            }
            if turnDeg != 0 {
                e.rotation = Groups.normalisedTurn(el.rotation + turnDeg)
                if wholeGroup { e.groupTurn = Groups.keptTurn(Groups.normalisedTurn((el.groupTurn ?? 0) + turnDeg)) }
            }
            return e
        }
    }

    /// The least a pinch may scale `el` by: its shorter side — a straight
    /// line's length — kept at `minSize`, and its type at minFontSize.
    private static func pinchFloor(_ el: Element, minSize: Double) -> Double {
        let side = el.type == .line && !LineRoutes.keepsLevel(el) ? el.w : min(el.w, el.h)
        var least = side > 0 ? minSize / side : 0
        if el.type == .text { least = max(least, minFontSize / max(el.fontSize ?? 42, 0.01)) }
        return least
    }

    /// A group or a multi-selection flipped as one unit about `box`, the
    /// selection's box: each member's frame (x, y, w, h, before its turn)
    /// mirrored across the box — horizontally x' = box.minX + box.maxX −
    /// (x + w), vertically y' = box.minY + box.maxY − (y + h) — and its turn
    /// mirrored, rotation' = (360 − rotation) mod 360, so the arrangement
    /// reads as a mirror image. Members that keep their place stay as they
    /// are. A shape or photo has its flipH or flipV toggled too, which makes
    /// it the exact mirror image; text, a table's cells and a chart's parts
    /// are not flipped, so the words stay readable, as in Canva. A line is
    /// not flipped either: the mirrored turn runs it end to end on a
    /// horizontal flip, so its start and end caps swap, and a tie at one end
    /// with them; a vertical one keeps its direction. A connector tied at
    /// both ends keeps its caps — it is laid again between the things it
    /// joins. The Android twin's Geometry.flipAll.
    static func flipAll(_ elements: [Element], box: CGRect, horizontal: Bool) -> [Element] {
        elements.map { el in
            guard !el.holdsPlace else { return el }
            var e = el
            if horizontal {
                e.x = Double(box.minX + box.maxX) - (el.x + el.w)
            } else {
                e.y = Double(box.minY + box.maxY) - (el.y + el.h)
            }
            let turned = (360 - el.rotation).truncatingRemainder(dividingBy: 360)
            e.rotation = turned < 0 ? turned + 360 : turned
            // A turned group's frame is mirrored with it.
            e.groupTurn = el.groupTurn.flatMap { Groups.keptTurn(Groups.normalisedTurn(360 - $0)) }
            let readable = el.type == .text || el.table != nil || el.chart != nil
            if el.type == .line && LineRoutes.keepsLevel(el) {
                // An elbowed or curved line's route is mirrored in its box
                // instead.
                return LineRoutes.mirrored(e, horizontal: horizontal)
            } else if el.type == .line {
                // Run end to end: its caps swap, and a tie at one end goes
                // with that end, so it stays on its element's mirrored edge.
                if horizontal && LineRoutes.hasEndHandles(el) {
                    e.startCap = el.endCap
                    e.endCap = el.startCap
                    e.connectFrom = el.connectTo
                    e.connectTo = el.connectFrom
                }
            } else if !readable {
                if horizontal { e.flipH.toggle() } else { e.flipV.toggle() }
            }
            return e
        }
    }

    enum TidyMode { case row, column, grid }

    /// A messy selection made regular: a row (left to right, centred on the
    /// union's middle), a column (top to bottom, centred on its middle) or a
    /// grid (reading order, square-ish, cells the size of the largest box).
    /// Everything stays inside the union's top-left corner; gaps are equal.
    static func tidy(_ elements: [Element], mode: TidyMode, gap: Double) -> [Element] {
        guard elements.count >= 2 else { return elements }
        let union = self.union(elements.map(aabb))
        var out = elements
        switch mode {
        case .row:
            let ordered = elements.indices.sorted { aabb(elements[$0]).minX < aabb(elements[$1]).minX }
            var x = union.minX
            for i in ordered {
                let box = aabb(elements[i])
                out[i].x += x - box.minX
                out[i].y += union.midY - box.midY
                x += box.width + gap
            }
        case .column:
            let ordered = elements.indices.sorted { aabb(elements[$0]).minY < aabb(elements[$1]).minY }
            var y = union.minY
            for i in ordered {
                let box = aabb(elements[i])
                out[i].y += y - box.minY
                out[i].x += union.midX - box.midX
                y += box.height + gap
            }
        case .grid:
            // Reading order as they sit now: by row band, then left to right.
            let boxes = elements.map(aabb)
            let cellW = boxes.map(\.width).max() ?? 0
            let cellH = boxes.map(\.height).max() ?? 0
            let columns = Int(Double(elements.count).squareRoot().rounded(.up))
            let ordered = elements.indices.sorted {
                let a = boxes[$0], b = boxes[$1]
                let rowA = ((a.midY - union.minY) / max(cellH, 1)).rounded(.down)
                let rowB = ((b.midY - union.minY) / max(cellH, 1)).rounded(.down)
                return rowA != rowB ? rowA < rowB : a.minX < b.minX
            }
            for (n, i) in ordered.enumerated() {
                let col = Double(n % columns), row = Double(n / columns)
                let cellX = union.minX + col * (cellW + gap)
                let cellY = union.minY + row * (cellH + gap)
                // Centred in its cell, so mixed sizes still read as a grid.
                out[i].x += (cellX + (cellW - boxes[i].width) / 2) - boxes[i].minX
                out[i].y += (cellY + (cellH - boxes[i].height) / 2) - boxes[i].minY
            }
        }
        return out
    }

    /// A stand-in element for a multi-selection's box, so the single-element
    /// handle geometry (which handle sits where, what resizing from it means)
    /// applies to the group unchanged.
    static func boxElement(_ box: CGRect) -> Element {
        var e = Element()
        e.type = .shape
        e.x = box.minX; e.y = box.minY
        e.w = box.width; e.h = box.height
        return e
    }

    /// A group turned as a whole (groupTurn): its frame, turned with it,
    /// tight round its members — the middle of it, its size in its own
    /// axes, and its angle.
    struct GroupFrame: Equatable {
        var center: CGPoint
        var size: CGSize
        var angle: Double

        /// The frame in its own axes: upright, about the same middle.
        var upright: CGRect {
            CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                   width: size.width, height: size.height)
        }

        /// A stand-in element for the frame, turned, so the single-element
        /// handle geometry places its handles, as boxElement does upright.
        var element: Element {
            var e = Geometry.boxElement(upright)
            e.rotation = angle
            return e
        }
    }

    /// The frame of `members` turned `angle` degrees as a group: their
    /// corners turned back by -angle about their centroid — the mean of
    /// their middles — boxed, and the box's middle turned on again. At 0 it
    /// is the upright box round them. The Android twin's Geometry.groupFrame.
    static func groupFrame(_ members: [Element], angle: Double) -> GroupFrame {
        guard !members.isEmpty else { return GroupFrame(center: .zero, size: .zero, angle: angle) }
        let count = Double(members.count)
        let centroid = CGPoint(x: members.map { Double($0.center.x) }.reduce(0, +) / count,
                               y: members.map { Double($0.center.y) }.reduce(0, +) / count)
        let box = union(rotate(members, around: centroid, by: -angle).map(aabb))
        let middle = rotate(CGPoint(x: box.midX, y: box.midY), around: centroid, degrees: angle)
        return GroupFrame(center: middle, size: box.size, angle: angle)
    }

    /// `elements` scaled with their turned group's frame `frame` as it
    /// becomes `to`, a box in the frame's own axes: turned back upright
    /// about the frame's middle, scaled from its upright box (scale), and
    /// turned again about the same middle, so what stays put in the frame's
    /// axes stays put on the page. A corner's uniform scale keeps turned
    /// members exact, as an upright group's does.
    static func scale(_ elements: [Element], frame: GroupFrame, to box: CGRect, minSize: Double = 4) -> [Element] {
        guard frame.angle != 0 else { return scale(elements, from: frame.upright, to: box, minSize: minSize) }
        let upright = rotate(elements, around: frame.center, by: -frame.angle)
        let scaled = scale(upright, from: frame.upright, to: box, minSize: minSize)
        return rotate(scaled, around: frame.center, by: frame.angle)
    }

    // MARK: viewport

    /// The scale at which `content` fits inside `viewport` with `padding`
    /// points to spare on the tighter axis.
    static func fitScale(content: CGSize, in viewport: CGSize, padding: Double = 48) -> Double {
        guard content.width > 0, content.height > 0,
              viewport.width > 0, viewport.height > 0 else { return 1 }
        return min((viewport.width - padding) / content.width,
                   (viewport.height - padding) / content.height)
    }

    /// How far a pinch may zoom, given the zoom that fits the page: past
    /// eight times the fit or 400%, and down to half the fit or 5% — so a
    /// tiny custom page, fitted large, can still be looked into. The Android
    /// twin's Viewport.zoomRange.
    static func zoomRange(fit: Double) -> ClosedRange<Double> {
        min(fit * 0.5, 0.05)...max(fit * 8, 4)
    }

    /// The scroll offset that centres already-scaled content in a viewport.
    ///
    /// A content point p appears on screen at p - offset, whatever the scroll
    /// view's content inset is: an inset widens the scrollable range, it does
    /// not move the content's origin. Folding the inset in here is what put
    /// every opened design half a viewport down and right of centre.
    static func centeredOffset(scaledContent content: CGSize, in viewport: CGSize) -> CGPoint {
        CGPoint(x: (content.width - viewport.width) / 2,
                y: (content.height - viewport.height) / 2)
    }

    /// A box in page units as it stands on screen, in the canvas's own
    /// points: `visible` is the part of the page on screen, at `zoom`.
    static func screenRect(_ box: CGRect, visible: CGRect, zoom: Double) -> CGRect {
        let z = CGFloat(zoom)
        return CGRect(x: (box.minX - visible.minX) * z, y: (box.minY - visible.minY) * z,
                      width: box.width * z, height: box.height * z)
    }

    // MARK: quick actions

    /// Which side of the selection the quick-action bubble sits on.
    enum BubbleSide: Equatable { case above, below }

    /// Where the quick-action bubble goes: `point` is the middle of its foot
    /// when it sits above, of its head when below.
    struct BubbleAnchor: Equatable {
        var point: CGPoint
        var side: BubbleSide
    }

    /// The bubble's distance from the selection, beyond its handles, and how
    /// near the top of the canvas it may sit before it goes below instead,
    /// in screen points — the Android twin's numbers, in dp.
    static let bubbleGap = 12.0
    static let bubbleTopRoom = 56.0

    /// Where the quick-action bubble sits for a selection whose box on
    /// screen is `selection`, its handles standing `handleOutset` off it,
    /// in a canvas showing `viewport`: centred over it, bubbleGap above the
    /// handles — or as far below them when that would leave the bubble
    /// within bubbleTopRoom of the canvas's top, kept bubbleTopRoom up from
    /// the canvas's bottom (over the selection, when nothing else fits).
    /// Across, its middle is kept on the canvas. All in screen points; the
    /// Android twin's Geometry.bubbleAnchor, with the same tests.
    static func bubbleAnchor(_ selection: CGRect, viewport: CGRect, handleOutset: Double) -> BubbleAnchor {
        let x = Double(min(max(selection.midX, viewport.minX), viewport.maxX))
        let above = Double(selection.minY) - handleOutset - bubbleGap
        if above - Double(viewport.minY) >= bubbleTopRoom {
            return BubbleAnchor(point: CGPoint(x: x, y: above), side: .above)
        }
        let below = min(Double(selection.maxY) + handleOutset + bubbleGap, Double(viewport.maxY) - bubbleTopRoom)
        return BubbleAnchor(point: CGPoint(x: x, y: max(below, Double(viewport.minY))), side: .below)
    }
}

// MARK: - scroll through pages

/// Scroll through pages: every page stacked top to bottom in one column,
/// each under a header row, with "+ Add page" beneath the last — the Android
/// twin's Viewport.pageOrigins and the rest, with the same test rows.
///
/// "Column space" is the canvas's content before the pinch zooms it: one
/// unit is one point on screen while the column fits the width. Every page is
/// fitted to the viewport's width less a gutter each side, so each is as wide
/// on screen as every other, and each has a gap above it — the room for its
/// header and the space between it and the page before, which the canvas
/// passes as `room`. The first page is a gap down.
enum PageColumn {

    /// The More menu's "Scroll through pages": on unless turned off. The
    /// Android twin's Prefs key.
    static let key = "pageScroll"
    /// Between one page and the next page's header, in points.
    static let gap = 24.0
    /// Either side of every page.
    static let gutter = 16.0
    /// The header row over each page.
    static let header = 32.0
    /// The gap above each page: its header and the gap over that.
    static let room = gap + header
    /// "+ Add page": how far under the last page, and how tall — inside the
    /// gap the column leaves there.
    static let addPageDrop = 8.0
    static let addPageHeight = 40.0

    /// Where a page lies in the column: its top-left corner and how many
    /// column units one page unit takes, with the page's own size.
    struct Slot: Equatable {
        var origin: CGPoint
        var scale: Double
        var size: CGSize

        /// The page itself, in column units.
        var rect: CGRect {
            CGRect(x: origin.x, y: origin.y, width: size.width * scale, height: size.height * scale)
        }

        /// A point on this page, in column units.
        func toColumn(_ p: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
        }

        /// A point in column units, in this page's own.
        func toPage(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
        }

        /// A box on this page, in column units.
        func columnBox(_ box: CGRect) -> CGRect {
            CGRect(origin: toColumn(box.origin), size: CGSize(width: box.width * scale, height: box.height * scale))
        }

        /// A box in column units, in this page's own.
        func pageBox(_ box: CGRect) -> CGRect {
            CGRect(origin: toPage(box.origin), size: CGSize(width: box.width / scale, height: box.height / scale))
        }
    }

    /// The pages of `sizes`, in order, stacked top to bottom in a viewport
    /// `viewportWidth` wide: each fitted to the width less a `gutter` each
    /// side, with `gap` above it. A page with no width is drawn one to one.
    static func pageOrigins(_ sizes: [CGSize], gap: Double, gutter: Double, viewportWidth: Double) -> [Slot] {
        let inner = max(viewportWidth - 2 * gutter, 1)
        var y = 0.0
        return sizes.map { size in
            y += gap
            let scale = size.width > 0 ? inner / Double(size.width) : 1
            let slot = Slot(origin: CGPoint(x: gutter, y: y), scale: scale, size: size)
            y += max(Double(size.height), 0) * scale
            return slot
        }
    }

    /// How tall the whole column is: the last page's bottom and one more
    /// `gap` under it, where "+ Add page" goes.
    static func columnHeight(_ slots: [Slot], gap: Double) -> Double {
        (slots.last.map { Double($0.rect.maxY) } ?? 0) + gap
    }

    /// Where Fit puts the page worked on screen, and where a page picked
    /// elsewhere is brought to: its top this far down a viewport
    /// `viewportHeight` tall — in the middle of the height when the page,
    /// `pageHeight` tall on screen, fits there, but never closer to the top
    /// than `gap`, the room for its header. One rule for both phones (the
    /// Android twin's Viewport.fitTop).
    static func fitTop(viewportHeight: Double, pageHeight: Double, gap: Double) -> Double {
        max(gap, (viewportHeight - pageHeight) / 2)
    }

    /// The page whose rect holds `point`, in column units, edges included —
    /// the earlier of two that touch — or nil over the gaps and gutters.
    static func pageAt(_ point: CGPoint, in slots: [Slot]) -> Int? {
        slots.firstIndex { slot in
            let r = slot.rect
            return point.x >= r.minX && point.x <= r.maxX && point.y >= r.minY && point.y <= r.maxY
        }
    }

    /// The page that is current once a scroll settles: the one covering the
    /// middle of `viewport` (in column units) — by height alone, the page
    /// whose top-to-bottom span is nearest the middle's height, nothing when
    /// the middle is inside it. Ties, the middle exactly halfway down a gap,
    /// go to the earlier page. 0 with no pages.
    static func currentPage(_ viewport: CGRect, in slots: [Slot]) -> Int {
        let y = Double(viewport.midY)
        var best = 0
        var bestDistance = Double.infinity
        for (i, slot) in slots.enumerated() {
            let r = slot.rect
            let distance: Double
            if y < Double(r.minY) {
                distance = Double(r.minY) - y
            } else if y > Double(r.maxY) {
                distance = y - Double(r.maxY)
            } else {
                distance = 0
            }
            if distance < bestDistance {
                best = i
                bestDistance = distance
            }
        }
        return best
    }

    /// The pages drawn as themselves: those within one viewport height of
    /// `visible` (in column units), above or below it — unless `drawMode`
    /// makes one a picture. The rest are drawn from a thumbnail.
    static func livePages(_ slots: [Slot], visible: CGRect) -> [Int] {
        pages(slots, within: 1, of: visible)
    }

    /// The pages given a thumbnail: those within two viewport heights of
    /// `visible`. The rest are a white page until they come nearer, so a
    /// long deck makes none of theirs.
    static func thumbnailPages(_ slots: [Slot], visible: CGRect) -> [Int] {
        pages(slots, within: 2, of: visible)
    }

    /// How a page of the column near the view is drawn: as itself, every
    /// element live, or as a picture of it from the thumbnail cache.
    enum DrawMode: Equatable {
        case live, picture
    }

    /// A page narrower on screen than this share of the view's width is
    /// drawn as a picture.
    static let pictureShare = 0.35
    /// More pages than this in view, and all but the one worked are drawn
    /// as pictures.
    static let liveInView = 6
    /// The widths, in pixels, a page's picture is made at.
    static let pictureWidths = [256, 512, 1024]

    /// How page `pageIndex` is drawn, `pageScreenWidth` wide on screen in a
    /// view `viewportWidth` wide (in any one unit), with `inViewCount`
    /// pages in view: the page worked (`workedIndex`) always live; another
    /// a picture when it is narrower than `pictureShare` of the view —
    /// exactly that share is live — or when more than `liveInView` pages
    /// are in view; else live. So a long design zoomed out pans over
    /// pictures rather than drawing every element of thirty pages on every
    /// frame. The Android twin's Viewport.drawMode, the same rule.
    static func drawMode(pageIndex: Int, workedIndex: Int, pageScreenWidth: Double,
                         viewportWidth: Double, inViewCount: Int) -> DrawMode {
        if pageIndex == workedIndex { return .live }
        if pageScreenWidth < pictureShare * viewportWidth || inViewCount > liveInView { return .picture }
        return .live
    }

    /// The width a page's picture is made at, from its width on screen in
    /// pixels: the first of `pictureWidths` at least that wide, the widest
    /// for any wider — so a pinch makes a page's picture again only when
    /// it crosses into another.
    static func pictureWidth(screenPixels: Double) -> Int {
        pictureWidths.first { Double($0) >= screenPixels } ?? pictureWidths[pictureWidths.count - 1]
    }

    /// The pages within `heights` viewport heights of `visible`, above or
    /// below it — 0, those in view.
    static func pages(_ slots: [Slot], within heights: Double, of visible: CGRect) -> [Int] {
        let top = Double(visible.minY) - Double(visible.height) * heights
        let bottom = Double(visible.maxY) + Double(visible.height) * heights
        return slots.indices.filter { i in
            let r = slots[i].rect
            return Double(r.maxY) >= top && Double(r.minY) <= bottom
        }
    }

    /// Where `box` lands when dropped on a page of `page` size, as a
    /// top-left: moved by the least that keeps it inside the page, so a box
    /// hanging over an edge comes in just far enough. A box wider or taller
    /// than the page sits at its left or top edge.
    static func clampToPage(_ box: CGRect, page: CGSize) -> CGPoint {
        CGPoint(x: clampSpan(Double(box.minX), Double(box.width), Double(page.width)),
                y: clampSpan(Double(box.minY), Double(box.height), Double(page.height)))
    }

    /// A span starting at `start`, `length` long, kept within 0…`limit`:
    /// back from the far edge first, then off the near one, which wins.
    private static func clampSpan(_ start: Double, _ length: Double, _ limit: Double) -> Double {
        var at = start
        if at + length > limit { at = limit - length }
        if at < 0 { at = 0 }
        return at
    }

    /// Where `box`, on page `from` in that page's units, lands on page `to`
    /// when let go there with the finger at `finger` in column units, as a
    /// top-left in that page's units: the finger kept on the same point of
    /// the box, in page units — so on a page of another scale the box is
    /// still under the finger where it was held.
    static func landing(_ box: CGRect, finger: CGPoint, from: Slot, to: Slot) -> CGPoint {
        let here = from.toPage(finger)
        let there = to.toPage(finger)
        return CGPoint(x: there.x + box.minX - here.x, y: there.y + box.minY - here.y)
    }

    /// `rect` cut across to `across`, the part of the column on screen from
    /// left to right, so a header row's buttons stay in reach however far
    /// the column is zoomed; nil when less than `least` of it is left.
    static func trimmed(_ rect: CGRect, to across: ClosedRange<Double>?, least: Double) -> CGRect? {
        guard let across else { return rect }
        let left = max(Double(rect.minX), across.lowerBound)
        let right = min(Double(rect.maxX), across.upperBound)
        guard right - left >= least else { return nil }
        return CGRect(x: left, y: Double(rect.minY), width: right - left, height: Double(rect.height))
    }

    /// The header row over `slot`, `unit` column units to a point on
    /// screen: as wide as the page, and the same height on screen however
    /// far the column is zoomed.
    static func headerRect(_ slot: Slot, unit: Double) -> CGRect {
        let r = slot.rect
        return CGRect(x: Double(r.minX), y: Double(r.minY) - header * unit, width: Double(r.width), height: header * unit)
    }

    /// "+ Add page" under the last of `slots`, `unit` column units to a
    /// point; nil with no pages.
    static func addPageRect(_ slots: [Slot], unit: Double) -> CGRect? {
        guard let r = slots.last?.rect else { return nil }
        return CGRect(x: Double(r.minX), y: Double(r.maxY) + addPageDrop * unit,
                      width: Double(r.width), height: addPageHeight * unit)
    }
}
