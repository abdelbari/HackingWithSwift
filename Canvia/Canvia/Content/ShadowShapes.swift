// A shadow's silhouette, for the styles beyond an offset copy: curved,
// page lift, angle and backdrop. Each is a path in the element's own space
// — its box at the origin, w × h, before its turn and flip — that the
// renderers blur and fill in the shadow's colour behind the element, as
// they do the offset copy of a drop shadow; the angle style's path is the
// box's corners through its projective transform, and a renderer that can
// shear the element's own alpha silhouette does that instead. The Android
// twin's ShadowShapes, number for number (ShadowStylesTests).
//
// The rules, chosen simply so both phones draw the same:
//   curved    the box with its bottom edge bowed down by curve × 6% of the
//             height and its top corners drawn in by curve × 8% of the
//             width, so the card seems to lift at its ends;
//   pageLift  two wedges under the lower corners: each a triangle up the
//             side by curve × 50% of the height and along the bottom edge
//             by 40% of the width, inside the box, so only its blur shows;
//   angle     the box sheared and squashed as if lying on the ground behind
//             its base: the bottom edge stays, the far edge is distance% of
//             the height up from it, moved sideways by that length × tan
//             (angle), and 80% of the width wide — the one projective
//             transform taking the four corners to those four;
//   backdrop  the box moved `distance` right and down, drawn with no blur.
// Every style keeps the shadow's own offset on top, as a drop shadow does.
// Text casts only the drop shadow (`cast`): a styled shadow on a text
// element is drawn as the drop shadow, on the canvas and in every export.

import CoreGraphics
import Foundation

enum ShadowShapes {

    /// The styles, the drop shadow first: what an unknown one is drawn as.
    static let styles = ["drop", "curved", "pageLift", "angle", "backdrop"]

    /// What a setting reads as when the shadow does not hold it.
    static let defaultCurve = 0.5
    static let defaultAngle = 30.0
    static let defaultDistance = 40.0

    /// How far a curve of 1 bows the bottom edge, as a share of the height.
    static let bow = 0.06
    /// How far a curve of 1 draws the top corners in, as a share of the width.
    static let taper = 0.08
    /// A page lift's wedges: how tall at a curve of 1 (of the height), and
    /// how wide (of the width).
    static let liftHeight = 0.5
    static let liftWidth = 0.4
    /// How wide the angle shadow's far edge is, as a share of the width.
    static let farWidth = 0.8

    /// The settings' tracks.
    static let curveRange = 0.0...1.0
    static let angleRange = -60.0...60.0
    static let distanceRange = 0.0...100.0

    /// The settings as drawn: the shadow's own, held to their tracks, or
    /// the default for one it does not hold or that is no number.
    static func curve(_ shadow: Shadow) -> Double { held(shadow.curve, defaultCurve, curveRange) }
    static func angle(_ shadow: Shadow) -> Double { held(shadow.angle, defaultAngle, angleRange) }
    static func distance(_ shadow: Shadow) -> Double { held(shadow.distance, defaultDistance, distanceRange) }

    private static func held(_ value: Double?, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        guard let value, value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// The shadow's style as drawn: its own when this build knows it, else
    /// drop — so a style from a newer build falls back to an offset copy.
    static func style(of shadow: Shadow) -> String {
        guard let style = shadow.style, styles.contains(style) else { return "drop" }
        return style
    }

    /// `element`'s shadow as it is drawn: its own, with the style taken off
    /// a text element's. Text casts only the drop shadow, from its letters
    /// — the styled ones are not offered for it — so a styled shadow on
    /// text, from a file or a mixed selection, is drawn as the drop shadow
    /// on both phones (the Android twin's ShadowShapes.cast).
    static func cast(_ element: Element) -> Shadow? {
        guard var shadow = element.shadow else { return nil }
        if element.type == .text { shadow.style = nil }
        return shadow
    }

    /// Whether the shadow is drawn from a silhouette of its own rather
    /// than an offset copy of the element.
    static func isStyled(_ shadow: Shadow) -> Bool {
        style(of: shadow) != "drop"
    }

    /// The blur the shadow is drawn with: none for a backdrop, which is a
    /// hard block; its own otherwise.
    static func blur(of shadow: Shadow) -> Double {
        style(of: shadow) == "backdrop" ? 0 : max(0, shadow.blur)
    }

    /// The silhouette of `shadow` behind an element `w` × `h`, in element
    /// space, before the shadow's own offset; nil for a drop shadow, which
    /// has none of its own, and for an angle whose transform is degenerate
    /// (no distance at all).
    static func path(for shadow: Shadow, w: Double, h: Double) -> CGPath? {
        guard w > 0, h > 0 else { return nil }
        switch style(of: shadow) {
        case "curved": return curved(w: w, h: h, curve: curve(shadow))
        case "pageLift": return pageLift(w: w, h: h, curve: curve(shadow))
        case "angle": return angle(w: w, h: h, angle: angle(shadow), distance: distance(shadow))?.path
        case "backdrop": return backdrop(w: w, h: h, distance: distance(shadow))
        default: return nil
        }
    }

    /// How far past the element's box, on any side, the silhouette reaches
    /// before it is blurred or offset: what an export pads its room by.
    static func reach(of shadow: Shadow, w: Double, h: Double) -> Double {
        guard let path = path(for: shadow, w: w, h: h) else { return 0 }
        let box = path.boundingBoxOfPath
        return max(0, -box.minX, -box.minY, box.maxX - w, box.maxY - h)
    }

    // MARK: the silhouettes

    static func curved(w: Double, h: Double, curve: Double) -> CGPath {
        let k = min(max(curve, curveRange.lowerBound), curveRange.upperBound)
        let sag = k * bow * h
        let inset = k * taper * w
        let p = CGMutablePath()
        p.move(to: CGPoint(x: inset, y: 0))
        p.addLine(to: CGPoint(x: w - inset, y: 0))
        p.addLine(to: CGPoint(x: w, y: h))
        // A quadratic curve bows half as far as its control point, so the
        // control sits two sags down for the edge to sag one — the curve
        // the Android twin draws in sixteen straight pieces.
        p.addQuadCurve(to: CGPoint(x: 0, y: h), control: CGPoint(x: w / 2, y: h + 2 * sag))
        p.closeSubpath()
        return p
    }

    static func pageLift(w: Double, h: Double, curve: Double) -> CGPath {
        let lift = min(max(curve, curveRange.lowerBound), curveRange.upperBound) * liftHeight * h
        let reach = liftWidth * w
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: h - lift))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: reach, y: h))
        p.closeSubpath()
        p.move(to: CGPoint(x: w - reach, y: h))
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: w, y: h - lift))
        p.closeSubpath()
        return p
    }

    /// The four corners of the box, clockwise from the top left.
    static func corners(w: Double, h: Double) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: w, y: h), CGPoint(x: 0, y: h)]
    }

    /// Where the angle style takes the box's corners — far left, far
    /// right, base right, base left: the base kept, the far edge
    /// `distance`% of the height up, sheared by tan(angle) × that height
    /// and narrowed to `farWidth` of the width.
    static func angleCorners(w: Double, h: Double, angle: Double, distance: Double) -> [CGPoint] {
        let a = min(max(angle, angleRange.lowerBound), angleRange.upperBound)
        let d = min(max(distance, distanceRange.lowerBound), distanceRange.upperBound)
        let far = h * d / 100
        let shear = tan(a * .pi / 180) * far
        let inset = (1 - farWidth) / 2 * w
        return [CGPoint(x: inset + shear, y: h - far), CGPoint(x: w - inset + shear, y: h - far),
                CGPoint(x: w, y: h), CGPoint(x: 0, y: h)]
    }

    /// The angle style's silhouette and the transform behind it (nine
    /// entries, row by row); nil when there is no distance to fall.
    static func angle(w: Double, h: Double, angle: Double, distance: Double) -> (path: CGPath, matrix: [Double])? {
        let to = angleCorners(w: w, h: h, angle: angle, distance: distance)
        guard let m = homography(from: corners(w: w, h: h), to: to) else { return nil }
        let p = CGMutablePath()
        p.addLines(between: to)
        p.closeSubpath()
        return (p, m)
    }

    static func backdrop(w: Double, h: Double, distance: Double) -> CGPath {
        let d = min(max(distance, distanceRange.lowerBound), distanceRange.upperBound)
        return CGPath(rect: CGRect(x: d, y: d, width: w, height: h), transform: nil)
    }

    // MARK: the projective transform

    /// The projective transform that takes each of the four points `from`
    /// to the one at the same place in `to`, as the nine entries of its 3×3
    /// matrix row by row, the last of them 1 — the Android twin's
    /// Deskew.homography, step for step. nil when three of either four lie
    /// on one line, which no such transform can take to a rectangle.
    static func homography(from: [CGPoint], to: [CGPoint]) -> [Double]? {
        guard from.count == 4, to.count == 4, inGeneralPosition(from), inGeneralPosition(to) else { return nil }
        // u = (h0 x + h1 y + h2) / (h6 x + h7 y + 1), and v likewise with
        // h3…h5: two equations a point, linear in the eight unknowns.
        var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let x = Double(from[i].x), y = Double(from[i].y)
            let u = Double(to[i].x), v = Double(to[i].y)
            a[2 * i] = [x, y, 1, 0, 0, 0, -x * u, -y * u, u]
            a[2 * i + 1] = [0, 0, 0, x, y, 1, -x * v, -y * v, v]
        }
        // Gauss–Jordan, taking the largest pivot in each column.
        for col in 0..<8 {
            var pivot = col
            for r in (col + 1)..<8 where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
            if a[pivot][col] == 0 { return nil }
            a.swapAt(col, pivot)
            for r in 0..<8 where r != col {
                let f = a[r][col] / a[col][col]
                if f == 0 { continue }
                for c in col..<9 { a[r][c] -= f * a[col][c] }
            }
        }
        return (0..<9).map { $0 == 8 ? 1 : a[$0][8] / a[$0][$0] }
    }

    /// `p` taken through the transform `m` (see `homography`).
    static func taken(_ p: CGPoint, through m: [Double]) -> CGPoint {
        let x = Double(p.x), y = Double(p.y)
        let d = m[6] * x + m[7] * y + m[8]
        return CGPoint(x: (m[0] * x + m[1] * y + m[2]) / d, y: (m[3] * x + m[4] * y + m[5]) / d)
    }

    /// Whether no three of the four points lie on one line.
    private static func inGeneralPosition(_ points: [CGPoint]) -> Bool {
        for i in 0..<4 {
            for j in (i + 1)..<4 {
                for k in (j + 1)..<4 where abs(turn(points[i], points[j], points[k])) < 1e-9 { return false }
            }
        }
        return true
    }

    /// The cross product of ab and ac: positive for a clockwise turn on a
    /// screen whose y runs down.
    private static func turn(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        Double((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
    }
}
