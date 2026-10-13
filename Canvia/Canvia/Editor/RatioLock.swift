// Keep proportions: the chain between the Position panel's Width and Height.
// On, a width typed brings the height with it in the box's own proportion,
// and a height the width, as a corner drag does — from the top-left corner,
// which stays put — so a photo or a group is never stretched by a number.
// It starts on for a photo and for a group, off for the rest, as on the
// Android twin; whether it is on is the panel's own, never saved.

import CoreGraphics
import Foundation

enum RatioLock {

    /// The smallest side the numbers make, on either axis.
    static let minSide = 8.0

    /// Whether the chain starts on for `selected`: one photo (a frame, a
    /// code and a clip are photos too), or several that are one group — a
    /// chart is one.
    static func startsOn(_ selected: [Element]) -> Bool {
        guard let first = selected.first else { return false }
        if selected.count == 1 { return first.type == .image }
        guard let group = first.group else { return false }
        return selected.allSatisfy { $0.group == group }
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
