// Distances while moving, as Canva's smart guides measure them: from each
// side of the moving box to the nearest edge facing it — a neighbour beside
// it, or else the page's edge — drawn as thin guide-colour lines with their
// lengths while a selection is dragged or held still to measure. Nothing of
// the design. The Android twin's Geometry.nearestDistances, the same rows.

import CoreGraphics
import Foundation

extension Geometry {

    /// A side of the moving box.
    enum Side: String, CaseIterable {
        case left, top, right, bottom
    }

    /// One measured distance: from the moving box's `side` (`from`, on its
    /// edge) across to the facing edge (`to`), `distance` long.
    struct Distance: Equatable {
        var side: Side
        var from: CGPoint
        var to: CGPoint
        var distance: Double
        /// Whether it runs across (left and right) rather than down.
        var alongX: Bool { side == .left || side == .right }
    }

    /// For each side of `moving`, in the order left, top, right, bottom, the
    /// nearest edge facing it: of the boxes in `others` (the caller leaves
    /// out what is hidden or more than a screen away) one that overlaps it
    /// across that side — sharing some of its height for left and right, of
    /// its width for top and bottom — and lies wholly beyond it, the nearest
    /// winning and the first of equals; else the page's edge, from 0 to
    /// `page`. The line runs through the middle of the span the two share,
    /// or the middle of the side for a page edge. A side already past the
    /// page's edge, with no neighbour, has none.
    static func nearestDistances(moving: CGRect, others: [CGRect], page: CGSize) -> [Distance] {
        Side.allCases.compactMap { side in nearestEdge(side, of: moving, others: others, page: page) }
    }

    private static func nearestEdge(_ side: Side, of m: CGRect, others: [CGRect], page: CGSize) -> Distance? {
        let across = side == .left || side == .right
        var best: (gap: Double, box: CGRect)?
        for r in others {
            let overlaps = across ? (r.minY < m.maxY && m.minY < r.maxY) : (r.minX < m.maxX && m.minX < r.maxX)
            guard overlaps else { continue }
            let gap: Double
            switch side {
            case .left: gap = Double(m.minX - r.maxX)
            case .right: gap = Double(r.minX - m.maxX)
            case .top: gap = Double(m.minY - r.maxY)
            case .bottom: gap = Double(r.minY - m.maxY)
            }
            guard gap >= 0, gap < (best?.gap ?? .infinity) else { continue }
            best = (gap, r)
        }
        if let best {
            let mid = across ? (max(m.minY, best.box.minY) + min(m.maxY, best.box.maxY)) / 2
                : (max(m.minX, best.box.minX) + min(m.maxX, best.box.maxX)) / 2
            return distanceLine(side, of: m, gap: best.gap, at: mid)
        }
        let gap: Double
        switch side {
        case .left: gap = Double(m.minX)
        case .right: gap = Double(page.width - m.maxX)
        case .top: gap = Double(m.minY)
        case .bottom: gap = Double(page.height - m.maxY)
        }
        guard gap >= 0 else { return nil }
        return distanceLine(side, of: m, gap: gap, at: across ? m.midY : m.midX)
    }

    /// The line from `side` of `m` out `gap` long, through `at` on the
    /// other axis.
    private static func distanceLine(_ side: Side, of m: CGRect, gap: Double, at: CGFloat) -> Distance {
        let g = CGFloat(gap)
        switch side {
        case .left:
            return Distance(side: side, from: CGPoint(x: m.minX, y: at), to: CGPoint(x: m.minX - g, y: at), distance: gap)
        case .right:
            return Distance(side: side, from: CGPoint(x: m.maxX, y: at), to: CGPoint(x: m.maxX + g, y: at), distance: gap)
        case .top:
            return Distance(side: side, from: CGPoint(x: at, y: m.minY), to: CGPoint(x: at, y: m.minY - g), distance: gap)
        case .bottom:
            return Distance(side: side, from: CGPoint(x: at, y: m.maxY), to: CGPoint(x: at, y: m.maxY + g), distance: gap)
        }
    }

    /// Whether `distance` is one of the gaps a move made equal (`gaps`):
    /// its line keeps the "=" of an equal gap. Within half a unit.
    static func isEqualGap(_ distance: Distance, _ gaps: [GapPair]) -> Bool {
        gaps.contains { $0.alongX == distance.alongX && abs($0.gap - distance.distance) < 0.5 }
    }
}
