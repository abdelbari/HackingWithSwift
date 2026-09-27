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
    /// handleOutset). A line stretches along its length; a text box follows
    /// its words, so its top and bottom are not the user's to drag unless the
    /// type is fitted to the box or aligned in it; a sticker and a QR code
    /// only scale, from their corners — a code's sides would cut into its
    /// finder squares — as on the Android twin.
    static func handleSet(for el: Element) -> [Handle] {
        let corners: [Handle] = [.nw, .ne, .se, .sw]
        switch el.type {
        case .line: return [.e, .w]
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

    /// Hit test respecting rotation.
    static func hits(_ el: Element, point: CGPoint) -> Bool {
        let p = el.rotation == 0 ? point : rotate(point, around: el.center, degrees: -el.rotation)
        return el.frame.insetBy(dx: -4, dy: -4).contains(p)
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
    /// out, is not made. The box is an unturned element's: turned, its edges
    /// do not run along the lines.
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

    /// Candidate snap lines: page edges/center plus sibling edges/centers,
    /// plus every grid line when a grid is on — each source only if its
    /// switch is.
    static func snapLines(design: Design, page: Page, excluding ids: Set<String>,
                          settings: SnapSettings = SnapSettings()) -> (x: [Double], y: [Double]) {
        let tagged = taggedSnapLines(design: design, page: page, excluding: ids, settings: settings)
        return (tagged.x.map(\.position), tagged.y.map(\.position))
    }

    /// Where a snap line comes from, so the guide can say what it has lined
    /// the selection up with.
    enum SnapSource: Equatable {
        case pageEdge, pageCentre, guide, grid, margin
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
            case .margin: return 4
            case .grid: return 5
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
        }
        if settings.toElements {
            for el in page.elements where !ids.contains(el.id) {
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
    /// unlocked whose box it touches. Touching, not containing — a marquee
    /// that had to swallow an element whole would miss everything larger than
    /// the screen at the current zoom.
    static func intersecting(_ elements: [Element], _ rect: CGRect) -> [Element] {
        guard rect.width > 0 || rect.height > 0 else { return [] }
        return elements.filter { !$0.locked && aabb($0).intersects(rect) }
    }

    /// Scale a set of elements together so that the box `from` (their
    /// union, at grab time) becomes `to`. Positions, sizes and text sizes all
    /// scale; rotations are kept, which is exact only for a uniform scale —
    /// which is why a group offers corner handles and nothing else.
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
            // A line's height is its stroke, not a dimension of its box.
            e.h = el.type == .line ? el.h : max(minSize, el.h * sy)
            e.x = cx - e.w / 2
            e.y = cy - e.h / 2
            if el.type == .text {
                e.fontSize = max(6, (el.fontSize ?? 42) * min(sx, sy))
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

    // MARK: viewport

    /// The scale at which `content` fits inside `viewport` with `padding`
    /// points to spare on the tighter axis.
    static func fitScale(content: CGSize, in viewport: CGSize, padding: Double = 48) -> Double {
        guard content.width > 0, content.height > 0,
              viewport.width > 0, viewport.height > 0 else { return 1 }
        return min((viewport.width - padding) / content.width,
                   (viewport.height - padding) / content.height)
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
}
