// The spacing of a tidied selection, changed all at once after Tidy up, as
// in Canva: a row, a column or a grid with equal gaps is recognised from
// where its members sit — nothing is written to the file, the layout is
// derived — and laid out again at another gap, every gap kept equal. The
// Android twin's Geometry.tidyLayout, with the same rows.

import CoreGraphics
import Foundation

extension Geometry {

    /// A tidied selection: how its members are laid out, and the gap
    /// between each two, in page units.
    struct TidyLayout: Equatable {
        var mode: TidyMode
        var gap: Double
    }

    /// How far, in page units, two gaps or two middles may differ and still
    /// count as the same.
    static let tidyTolerance = 0.5

    /// How the members of a tidied selection lie: the layout, their order
    /// along it, a grid's columns, the top left of its first cell and the
    /// cell's size.
    private struct TidyArrangement {
        var layout: TidyLayout
        var order: [Int]
        var columns = 1
        var origin = CGPoint.zero
        var cell = CGSize.zero
    }

    /// The layout `members` already form, by their turned bounds: a row —
    /// left to right, their middles level, equal gaps — or else a column —
    /// top to bottom, their middles in line, equal gaps — or else a grid as
    /// Tidy up lays one: square-ish, reading order, each centred in a cell
    /// the size of the largest, equal gaps across and down. Within
    /// tidyTolerance; a gap a hair under 0 is 0. Nil for fewer than two, or
    /// anything else.
    static func tidyLayout(_ members: [Element]) -> TidyLayout? {
        tidyArrangement(members)?.layout
    }

    /// `members`, a tidied selection, laid out again with `gap` (never under
    /// 0) between each two: a row keeps its left end and its level, a column
    /// its top and its line, a grid its first cell. Nil when they are not
    /// tidied (tidyLayout).
    static func respaced(_ members: [Element], gap: Double) -> [Element]? {
        guard let arrangement = tidyArrangement(members) else { return nil }
        let gap = max(0, gap)
        let boxes = members.map(aabb)
        var out = members
        switch arrangement.layout.mode {
        case .row:
            var x = Double(boxes[arrangement.order[0]].minX)
            for i in arrangement.order {
                out[i].x += x - Double(boxes[i].minX)
                x += Double(boxes[i].width) + gap
            }
        case .column:
            var y = Double(boxes[arrangement.order[0]].minY)
            for i in arrangement.order {
                out[i].y += y - Double(boxes[i].minY)
                y += Double(boxes[i].height) + gap
            }
        case .grid:
            for (n, i) in arrangement.order.enumerated() {
                let middle = cellMiddle(n, arrangement, gap: gap)
                out[i].x += Double(middle.x - boxes[i].midX)
                out[i].y += Double(middle.y - boxes[i].midY)
            }
        }
        return out
    }

    /// Where the gap handles of a tidied row or column sit: the middle of
    /// each gap, in page units, in order along it. None for a grid, or for
    /// what is not tidied.
    static func tidyGapHandles(_ members: [Element]) -> [CGPoint] {
        guard let arrangement = tidyArrangement(members), arrangement.layout.mode != .grid else { return [] }
        let boxes = arrangement.order.map { aabb(members[$0]) }
        let row = arrangement.layout.mode == .row
        return zip(boxes, boxes.dropFirst()).map { a, b in
            row ? CGPoint(x: (a.maxX + b.minX) / 2, y: a.midY) : CGPoint(x: a.midX, y: (a.maxY + b.minY) / 2)
        }
    }

    /// What the Spacing slider runs over on a page of `page` size: 0 to a
    /// quarter of its shorter side.
    static func tidySpacingRange(page: CGSize) -> ClosedRange<Double> {
        0...max(1, Double(min(page.width, page.height)) / 4)
    }

    /// Tidy up's own gap on a page of `page` size: a fiftieth of its shorter
    /// side, to the whole unit (DesignStore.tidySelected).
    static func defaultTidyGap(page: CGSize) -> Double {
        (Double(min(page.width, page.height)) / 50).rounded()
    }

    // MARK: recognising the layout

    private static func tidyArrangement(_ members: [Element]) -> TidyArrangement? {
        let boxes = members.map(aabb)
        guard boxes.count >= 2 else { return nil }
        let byX = boxes.indices.sorted { boxes[$0].minX < boxes[$1].minX }
        if level(byX.map { Double(boxes[$0].midY) }),
           let gap = equalGap(zip(byX, byX.dropFirst()).map { Double(boxes[$1].minX - boxes[$0].maxX) }) {
            return TidyArrangement(layout: TidyLayout(mode: .row, gap: gap), order: byX)
        }
        let byY = boxes.indices.sorted { boxes[$0].minY < boxes[$1].minY }
        if level(byY.map { Double(boxes[$0].midX) }),
           let gap = equalGap(zip(byY, byY.dropFirst()).map { Double(boxes[$1].minY - boxes[$0].maxY) }) {
            return TidyArrangement(layout: TidyLayout(mode: .column, gap: gap), order: byY)
        }
        return gridArrangement(boxes)
    }

    /// A grid as Tidy up lays one, or nil.
    private static func gridArrangement(_ boxes: [CGRect]) -> TidyArrangement? {
        let count = boxes.count
        guard count >= 3 else { return nil }
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let cell = CGSize(width: boxes.map(\.width).max() ?? 0, height: boxes.map(\.height).max() ?? 0)
        // Rows by their middles, top to bottom, each left to right.
        var rows: [[Int]] = []
        for i in boxes.indices.sorted(by: { boxes[$0].midY < boxes[$1].midY }) {
            if let last = rows.last?.first, abs(Double(boxes[i].midY - boxes[last].midY)) <= tidyTolerance {
                rows[rows.count - 1].append(i)
            } else {
                rows.append([i])
            }
        }
        rows = rows.map { $0.sorted { boxes[$0].midX < boxes[$1].midX } }
        guard rows.count >= 2, rows.count == (count + columns - 1) / columns,
              rows.dropLast().allSatisfy({ $0.count == columns }) else { return nil }
        let first = boxes[rows[0][0]]
        let across = Double(boxes[rows[0][1]].midX - first.midX - cell.width)
        let down = Double(boxes[rows[1][0]].midY - first.midY - cell.height)
        guard abs(across - down) <= tidyTolerance, let gap = equalGap([across]) else { return nil }
        let origin = CGPoint(x: first.midX - cell.width / 2, y: first.midY - cell.height / 2)
        let arrangement = TidyArrangement(layout: TidyLayout(mode: .grid, gap: gap), order: rows.flatMap { $0 },
                                          columns: columns, origin: origin, cell: cell)
        for (n, i) in arrangement.order.enumerated() {
            let middle = cellMiddle(n, arrangement, gap: across)
            guard abs(Double(middle.x - boxes[i].midX)) <= tidyTolerance,
                  abs(Double(middle.y - boxes[i].midY)) <= tidyTolerance else { return nil }
        }
        return arrangement
    }

    /// The middle of the `n`th cell, in reading order, of a grid laid out
    /// with `gap`.
    private static func cellMiddle(_ n: Int, _ grid: TidyArrangement, gap: Double) -> CGPoint {
        let col = Double(n % grid.columns), row = Double(n / grid.columns)
        return CGPoint(x: Double(grid.origin.x) + col * (Double(grid.cell.width) + gap) + Double(grid.cell.width) / 2,
                       y: Double(grid.origin.y) + row * (Double(grid.cell.height) + gap) + Double(grid.cell.height) / 2)
    }

    /// Whether every value is the first within tidyTolerance.
    private static func level(_ values: [Double]) -> Bool {
        guard let first = values.first else { return false }
        return values.allSatisfy { abs($0 - first) <= tidyTolerance }
    }

    /// The gap, when every one is the first within tidyTolerance and none
    /// is under 0 by more than it: the first, 0 at the least.
    private static func equalGap(_ gaps: [Double]) -> Double? {
        guard let first = gaps.first, first >= -tidyTolerance,
              gaps.allSatisfy({ abs($0 - first) <= tidyTolerance }) else { return nil }
        return max(0, first)
    }
}
