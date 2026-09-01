// Rotation-aware transform math, ported from the web module (which is
// covered by 73 unit checks): rotated-anchor resize, handle positions,
// bounding boxes, hit tests and snapping.

import CoreGraphics
import Foundation

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

    /// Candidate snap lines: page edges/center plus sibling edges/centers.
    static func snapLines(design: Design, page: Page, excluding ids: Set<String>) -> (x: [Double], y: [Double]) {
        var xs: [Double] = [0, design.width / 2, design.width]
        var ys: [Double] = [0, design.height / 2, design.height]
        for el in page.elements where !ids.contains(el.id) {
            let b = aabb(el)
            xs.append(contentsOf: [b.minX, b.midX, b.maxX])
            ys.append(contentsOf: [b.minY, b.midY, b.maxY])
        }
        return (xs, ys)
    }
}
