// Keep proportions: the chain between the Position panel's Width and Height.
// On, a width typed brings the height with it in the box's own proportion,
// and a height the width, as a corner drag does — from the top-left corner,
// which stays put — so a photo or a group is never stretched by a number.
// It starts on for a photo and for a group's member, off for the rest, as on
// the Android twin; whether it is on is the panel's own, never saved. Several
// things selected have no chain: their box always scales evenly, as there.

import CoreGraphics
import Foundation

enum RatioLock {

    /// The smallest side the numbers make, on either axis.
    static let minSide = 8.0

    /// Whether the chain starts on for one selected element: a photo (a
    /// frame, a code and a clip are photos too), or a member of a group — a
    /// chart is one — picked out of it. The Android twin's
    /// Resize.keepsProportionsAtFirst, with the same rows.
    static func startsOn(_ el: Element) -> Bool {
        el.type == .image || el.group != nil
    }

    /// `el`'s box at `size`, its top-left corner — turned with it — held
    /// where it is, as a corner drag holds the opposite one: the Android
    /// twin's Resize.anchored(el, -1, -1, …), which its keptProportions uses.
    static func placed(_ el: Element, at size: CGSize) -> CGRect {
        let w = Double(size.width), h = Double(size.height)
        let corner = Geometry.rotate(CGPoint(x: -el.w / 2, y: -el.h / 2), around: .zero, degrees: el.rotation)
        let sized = Geometry.rotate(CGPoint(x: -w / 2, y: -h / 2), around: .zero, degrees: el.rotation)
        let centre = el.center
        let x = Double(centre.x + corner.x - sized.x) - w / 2
        let y = Double(centre.y + corner.y - sized.y) - h / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// A width typed with the chain on, for a box `box`: that width and the
    /// height in proportion, neither under minSide — the other side grown
    /// to keep the proportion when one would be.
    static func size(width typed: Double, from box: CGSize) -> CGSize {
        let boxW = Double(box.width), boxH = Double(box.height)
        guard boxW > 0, boxH > 0 else {
            return CGSize(width: max(minSide, typed), height: max(minSide, boxH))
        }
        let ratio = boxH / boxW
        var w = max(minSide, typed)
        var h = w * ratio
        if h < minSide {
            h = minSide
            w = h / ratio
        }
        return CGSize(width: w, height: h)
    }

    /// A height typed with the chain on: the same, the other way round.
    static func size(height typed: Double, from box: CGSize) -> CGSize {
        let turned = size(width: typed, from: CGSize(width: box.height, height: box.width))
        return CGSize(width: turned.height, height: turned.width)
    }
}
