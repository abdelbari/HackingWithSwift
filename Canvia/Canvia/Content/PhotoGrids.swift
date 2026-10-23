// Photo grid layouts: several empty frames at once, sharing one gutter.
//
// A collage is three photos in a row far more often than it is anything
// clever, and placing three frames by hand — same size, even gaps, flush to
// the margins — is ten minutes of nudging. A layout is those frames in one
// tap; the photos go in by being dragged onto the cells, picked while the
// grid is selected, or with Replace (see PhotoFrames).
//
// The layouts are the `photoGrids` of PhotoFrames.json, which the Android
// twin's tools/generate_frames.py writes — the very file Android ships, byte
// for byte, so a grid is the same cells on both phones. Each cell a grid
// makes carries `grid` {id, layout, cell, gutter, margin} (GridCell): that
// is what lets Spacing and Corners lay the whole grid out again after it is
// placed. A grid made before there was a `grid` key offers neither.
//
// Once placed, a grid can be moved to another layout with its pictures
// handed on (`relayout`), and the dividers between its cells dragged: a
// custom split is kept as `grid.splits` {x: [fractions], y: [fractions]}
// (GridSplits), the lattice lines moved from the layout's own even ones,
// written only when they differ from those. The Android twin's PhotoGrids,
// rule for rule (PhotoGridLayoutTests).

import Foundation

/// Where a grid's lattice lines stand, as shares of the grid's width (`x`,
/// the inner column boundaries, ascending) and height (`y`, the row
/// boundaries).
struct GridSplits: Codable, Equatable, Hashable {
    var x: [Double]
    var y: [Double]
}

enum PhotoGrids {

    struct Layout: Identifiable {
        var id: String
        var name: String
        /// Cells in unit coordinates of the page's inner area, in reading
        /// order: a cell's index is its place here.
        var cells: [CGRect]
        /// The lattice the cells sit on, and each cell as the file has it,
        /// [column, row, columns spanned, rows spanned] — what a custom
        /// split moves.
        var columns: Int = 1
        var rows: Int = 1
        var lattice: [[Int]] = []
    }

    /// Spacing's track, in page units.
    static let maxSpacing: Double = 40
    /// Corners' track: a share of each cell's own shorter side, in percent.
    static let maxCorners: Double = 50
    /// The smallest a cell may be made by dragging a divider, as a share
    /// of the grid's side.
    static let minCell = 0.08
    /// How near the grid's middle a dragged divider snaps to it.
    static let snap = 0.02

    /// One layout as the file has it: cells of [column, row, columns
    /// spanned, rows spanned] on a lattice of `columns` × `rows`.
    fileprivate struct GridDef: Decodable {
        var id: String
        var name: String
        var columns: Int
        var rows: Int
        var cells: [[Int]]
    }

    /// PhotoFrames.json: the grids here, the frames in DecorativeFrames,
    /// the letter and number frames in GlyphFrames (a file without them,
    /// from an earlier build, has none).
    struct File: Decodable {
        fileprivate var photoGrids: [GridDef]
        var photoFrames: [FrameDef]
        var glyphFrames: [GlyphFrameDef]?
    }

    /// Read once, on first use.
    static let file: File = {
        guard let url = Bundle.main.url(forResource: "PhotoFrames", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(File.self, from: data) else {
            assertionFailure("PhotoFrames.json missing or invalid")
            return File(photoGrids: [], photoFrames: [], glyphFrames: nil)
        }
        return decoded
    }()

    /// Every layout, in the file's order. A cell's unit rectangle is its
    /// lattice numbers over the lattice's — 3/5 is 0.6 to the last bit, as
    /// the literal is, on either phone.
    static let layouts: [Layout] = file.photoGrids.compactMap { entry in
        guard entry.columns > 0, entry.rows > 0 else { return nil }
        let cols = Double(entry.columns), rows = Double(entry.rows)
        let cells = entry.cells.compactMap { n -> CGRect? in
            guard n.count == 4 else { return nil }
            return CGRect(x: Double(n[0]) / cols, y: Double(n[1]) / rows,
                          width: Double(n[2]) / cols, height: Double(n[3]) / rows)
        }
        return Layout(id: entry.id, name: entry.name, cells: cells, columns: entry.columns, rows: entry.rows,
                      lattice: entry.cells.filter { $0.count == 4 })
    }

    static func layout(_ id: String?) -> Layout? {
        layouts.first { $0.id == id }
    }

    /// The layouts a grid of `count` cells can move to: those with as many
    /// cells or more, in the file's order.
    static func layoutsFor(_ count: Int) -> [Layout] {
        layouts.filter { $0.cells.count >= count }
    }

    /// The margin a grid is laid out with on a page `width` wide.
    static func margin(forWidth width: Double) -> Double {
        (width * 0.04).rounded()
    }

    /// The gutter a grid is laid out with inside `margin`: half of it, but
    /// never past Spacing's track, so the slider can always set a grid back
    /// to the spacing it came with — as on the Android twin.
    static func gutter(margin: Double) -> Double {
        min((margin / 2).rounded(), maxSpacing)
    }

    /// Empty photo frames for the layout on a page of `width` × `height`,
    /// with `margin` around the outside and `gutter` between cells, grouped
    /// so they move together, each carrying its `grid`.
    static func elements(for layout: Layout, width: Double, height: Double,
                         margin: Double, gutter: Double) -> [Element] {
        let innerW = max(width - 2 * margin, 1), innerH = max(height - 2 * margin, 1)
        let group = UID.make("grp")
        return layout.cells.enumerated().map { index, cell in
            var el = Element()
            el.type = .image
            el.src = nil
            el.radius = 0
            // Half a gutter is shaved off every inner edge, so neighbours
            // end up exactly one gutter apart and outer edges stay flush.
            let left = cell.minX > 0.001 ? gutter / 2 : 0
            let right = cell.maxX < 0.999 ? gutter / 2 : 0
            let top = cell.minY > 0.001 ? gutter / 2 : 0
            let bottom = cell.maxY < 0.999 ? gutter / 2 : 0
            el.x = (margin + cell.minX * innerW + left).rounded()
            el.y = (margin + cell.minY * innerH + top).rounded()
            el.w = (cell.width * innerW - left - right).rounded()
            el.h = (cell.height * innerH - top - bottom).rounded()
            el.group = group
            el.grid = GridCell(id: group, layout: layout.id, cell: index, gutter: gutter, margin: margin)
            return el
        }
    }

    // MARK: splits

    /// The layout's own lattice lines: its columns and rows evenly spaced.
    static func ownSplits(_ layout: Layout) -> GridSplits {
        GridSplits(x: (1..<max(layout.columns, 1)).map { Double($0) / Double(layout.columns) },
                   y: (1..<max(layout.rows, 1)).map { Double($0) / Double(layout.rows) })
    }

    /// `splits` as a grid of `layout` keeps them: both lists of the
    /// lattice's size, each ascending within 0…1, and not the layout's
    /// own; anything else is nil, the layout's own.
    static func kept(_ splits: GridSplits?, for layout: Layout?) -> GridSplits? {
        guard let splits, let layout else { return nil }
        func sound(_ list: [Double], _ count: Int) -> Bool {
            guard list.count == count, list.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 1 }) else { return false }
            return zip(list, list.dropFirst()).allSatisfy { $0 < $1 }
        }
        guard sound(splits.x, layout.columns - 1), sound(splits.y, layout.rows - 1) else { return nil }
        return splits == ownSplits(layout) ? nil : splits
    }

    /// The grid's custom splits, as its first cell records them; nil for
    /// the layout's own.
    static func splits(of cells: [Element]) -> GridSplits? {
        cells.lazy.compactMap(\.grid).first?.splits
    }

    /// The layout's cells in unit coordinates with its lattice lines at
    /// `splits` — its own when nil: a cell on columns c…c+cw of the lattice
    /// runs from the c-th line to the (c+cw)-th, 0 and 1 the outer edges.
    static func unitCells(_ layout: Layout, splits: GridSplits?) -> [CGRect] {
        guard let splits, !layout.lattice.isEmpty else { return layout.cells }
        let xs = [0.0] + splits.x + [1.0]
        let ys = [0.0] + splits.y + [1.0]
        func at(_ lines: [Double], _ i: Int, _ fallback: Double) -> Double {
            lines.indices.contains(i) ? lines[i] : fallback
        }
        return layout.lattice.map { cell in
            let x0 = at(xs, cell[0], 0), x1 = at(xs, cell[0] + cell[2], 1)
            let y0 = at(ys, cell[1], 0), y1 = at(ys, cell[1] + cell[3], 1)
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }

    /// A divider: one of the grid's lattice lines that runs straight from
    /// one side of the grid to the other, with no cell across it — the
    /// `index`th of the splits' x (vertical) or y — and where it stands, a
    /// share of the grid's side.
    struct GridDivider: Equatable {
        var vertical: Bool
        var index: Int
        var at: Double
    }

    /// The lines of `layout` at `splits` a handle is shown on: each inner
    /// lattice line no cell spans across.
    static func dividers(_ layout: Layout, splits: GridSplits?) -> [GridDivider] {
        let lines = splits ?? ownSplits(layout)
        guard !layout.lattice.isEmpty else { return [] }
        var out: [GridDivider] = []
        for (i, at) in lines.x.enumerated() {
            let line = i + 1
            if !layout.lattice.contains(where: { $0[0] < line && line < $0[0] + $0[2] }) {
                out.append(GridDivider(vertical: true, index: i, at: at))
            }
        }
        for (i, at) in lines.y.enumerated() {
            let line = i + 1
            if !layout.lattice.contains(where: { $0[1] < line && line < $0[1] + $0[3] }) {
                out.append(GridDivider(vertical: false, index: i, at: at))
            }
        }
        return out
    }

    /// `splits` with `divider` moved to `to` (a share of the grid's side):
    /// held between its neighbouring lines by `minCell`, so no cell gets
    /// narrower than that, and snapped to the grid's middle within `snap`.
    /// nil once the result is the layout's own spacing.
    static func dragged(_ layout: Layout, splits: GridSplits?, divider: GridDivider, to: Double) -> GridSplits? {
        let current = splits ?? ownSplits(layout)
        let lines = divider.vertical ? current.x : current.y
        guard lines.indices.contains(divider.index) else { return splits }
        let low = (divider.index > 0 ? lines[divider.index - 1] : 0) + minCell
        let high = (divider.index + 1 < lines.count ? lines[divider.index + 1] : 1) - minCell
        var at = to.isFinite ? to : lines[divider.index]
        if abs(at - 0.5) <= snap { at = 0.5 }
        at = min(max(at, low), high)
        if low > high { at = lines[divider.index] }
        var moved = lines
        moved[divider.index] = at
        var next = current
        if divider.vertical { next.x = moved } else { next.y = moved }
        return next == ownSplits(layout) ? nil : next
    }

    // MARK: laying out

    /// The cells of `layout` laid in `bounds` with `gutter` between them,
    /// its lattice lines at `splits` (its own for nil), by the same
    /// half-gutter rule as `elements` but not rounded: laid out again and
    /// again as Spacing is dragged, a rounded grid would creep a pixel at a
    /// time, and unrounded its outer edges stay exactly on `bounds`. No
    /// cell is narrower or shorter than 1.
    static func frames(_ layout: Layout, in bounds: CGRect, gutter: Double) -> [CGRect] {
        frames(layout, in: bounds, gutter: gutter, splits: nil)
    }

    static func frames(_ layout: Layout, in bounds: CGRect, gutter: Double, splits: GridSplits?) -> [CGRect] {
        unitCells(layout, splits: splits).map { cell in
            let left = cell.minX > 0.001 ? gutter / 2 : 0
            let right = cell.maxX < 0.999 ? gutter / 2 : 0
            let top = cell.minY > 0.001 ? gutter / 2 : 0
            let bottom = cell.maxY < 0.999 ? gutter / 2 : 0
            return CGRect(x: bounds.minX + cell.minX * bounds.width + left,
                          y: bounds.minY + cell.minY * bounds.height + top,
                          width: max(cell.width * bounds.width - left - right, 1),
                          height: max(cell.height * bounds.height - top - bottom, 1))
        }
    }

    /// `selection` as one grid's cells in cell order, with its layout, when
    /// it is exactly that: every one an image that is a cell of a layout
    /// this build has, all of one grid and one group, and each of the
    /// layout's cells there once. Anything else — a grid with a cell deleted
    /// or ungrouped, a cell with something else, a grid from before `grid` —
    /// is nil, and Spacing and Corners are not offered.
    static func grid(of selection: [Element]) -> (layout: Layout, cells: [Element])? {
        guard let first = selection.first, first.type == .image, let cell = first.grid,
              let layout = Self.layout(cell.layout), let group = first.group,
              selection.count == layout.cells.count else { return nil }
        for el in selection {
            guard el.type == .image, let g = el.grid, g.id == cell.id, g.layout == cell.layout,
                  el.group == group else { return nil }
        }
        let indices = selection.compactMap { $0.grid?.cell }.sorted()
        guard indices == Array(layout.cells.indices) else { return nil }
        return (layout, selection.sorted { ($0.grid?.cell ?? 0) < ($1.grid?.cell ?? 0) })
    }

    /// The grid's spacing, as its first cell records it.
    static func spacing(of cells: [Element]) -> Double {
        cells.lazy.compactMap(\.grid).first?.gutter ?? 0
    }

    /// The grid's corners, in percent of a cell's shorter side, as its first
    /// cell's radius has them, within the track.
    static func corners(of cells: [Element]) -> Double {
        guard let first = cells.first else { return 0 }
        let side = min(first.w, first.h)
        guard side > 0 else { return 0 }
        return min(max((first.radius ?? 0) / side * 100, 0), maxCorners)
    }

    /// The box round `cells`.
    static func bounds(of cells: [Element]) -> CGRect {
        let left = cells.map(\.x).min() ?? 0
        let top = cells.map(\.y).min() ?? 0
        let right = cells.map { $0.x + $0.w }.max() ?? 0
        let bottom = cells.map { $0.y + $0.h }.max() ?? 0
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The grid `cells` (as `grid(of:)` gives them) laid out again within
    /// the box round them now — wherever the grid has been moved or
    /// stretched — `gutter` apart, and each cell rounded `corners` percent of
    /// its own shorter side (`radius`). Each keeps its picture, crop, look
    /// and turn; the cells record the new spacing and, should the grid's
    /// group have changed, its group as their grid's id. Spacing within
    /// 0…maxSpacing, corners within 0…maxCorners. The lattice lines stand
    /// at `splits` — the grid's own custom ones when nil; the layout's own
    /// (`ownSplits`) puts them back even — and each cell keeps its crop as
    /// it is: the crop is a share of the frame, so a picture goes on
    /// covering a cell however the cell is resized.
    static func relaid(_ layout: Layout, cells: [Element], gutter: Double, corners: Double) -> [Element] {
        relaid(layout, cells: cells, gutter: gutter, corners: corners, splits: nil)
    }

    static func relaid(_ layout: Layout, cells: [Element], gutter: Double, corners: Double,
                       splits: GridSplits?) -> [Element] {
        guard !cells.isEmpty else { return cells }
        let bounds = Self.bounds(of: cells)
        let spacing = min(max(gutter, 0), maxSpacing)
        let share = min(max(corners, 0), maxCorners) / 100
        let kept = Self.kept(splits ?? Self.splits(of: cells), for: layout)
        let frames = Self.frames(layout, in: bounds, gutter: spacing, splits: kept)
        return cells.map { el in
            guard var cell = el.grid, frames.indices.contains(cell.cell) else { return el }
            let f = frames[cell.cell]
            var out = el
            out.x = f.minX
            out.y = f.minY
            out.w = f.width
            out.h = f.height
            out.radius = Double(min(f.width, f.height)) * share
            cell.id = el.group ?? cell.id
            cell.gutter = spacing
            cell.splits = kept
            out.grid = cell
            return out
        }
    }

    /// The grid `cells` (as `grid(of:)` gives them) moved to the layout
    /// `to`: the box round the grid, its gutter, margin, corners and group
    /// kept, the new layout's cells laid in it at its own spacing — the
    /// first ones the old cell elements themselves, so what was selected
    /// stays selected, the rest new — and the pictures handed to the new
    /// cells in PhotoFrames.fillOrder, each with its crop, look and border.
    /// With fewer cells than pictures, the pictures left over become free
    /// photos beside the grid: at their old cells' size, one under another
    /// down the grid's right, a gutter away. The new cells in cell order,
    /// then those free photos — one undo step for the caller.
    static func relayout(_ cells: [Element], to: Layout) -> [Element] {
        guard !cells.isEmpty else { return cells }
        let sorted = cells.sorted { ($0.grid?.cell ?? 0) < ($1.grid?.cell ?? 0) }
        guard let first = sorted[0].grid else { return cells }
        let bounds = Self.bounds(of: cells)
        let spacing = min(max(first.gutter, 0), maxSpacing)
        let share = corners(of: sorted) / 100
        let group = sorted[0].group ?? first.id
        let frames = Self.frames(to, in: bounds, gutter: spacing)
        // The pictures in the order their old cells fill, to the new cells
        // in the order theirs do — reading order, as Android's fillOrder
        // sorts every cell (iOS's own fillOrder keeps only the empty ones,
        // which would leave no picture to hand on).
        let pictures = PhotoFrames.readingOrder(sorted).filter { !PhotoFrames.isEmpty($0) }
        // An empty cell as the grid makes one: nothing of a picture's look
        // left on it.
        var newCells: [Element] = frames.enumerated().map { index, f in
            var blank = Element()
            blank.type = .image
            blank.radius = Double(min(f.width, f.height)) * share
            blank.group = group
            if sorted.indices.contains(index) { blank.id = sorted[index].id }
            blank.x = f.minX
            blank.y = f.minY
            blank.w = f.width
            blank.h = f.height
            blank.grid = GridCell(id: group, layout: to.id, cell: index, gutter: spacing, margin: first.margin)
            return blank
        }
        let order = PhotoFrames.readingOrder(newCells).map(\.id)
        var freed: [Element] = []
        var below = bounds.minY
        for (n, picture) in pictures.enumerated() {
            if n < order.count, let at = newCells.firstIndex(where: { $0.id == order[n] }) {
                // The picture, as it was, in its new cell: its own keys —
                // its fx, its mask, a frame shape — with the cell's grid key.
                let target = newCells[at]
                var placed = picture
                placed.id = target.id
                placed.x = target.x
                placed.y = target.y
                placed.w = target.w
                placed.h = target.h
                placed.radius = target.radius
                placed.group = group
                placed.rotation = 0
                placed.grid = target.grid
                newCells[at] = placed
            } else {
                var free = picture
                free.id = UID.make()
                free.x = bounds.maxX + spacing
                free.y = below
                free.group = nil
                free.subgroups = nil
                free.groupTurn = nil
                free.rotation = 0
                free.grid = nil
                freed.append(free)
                below += picture.h + spacing
            }
        }
        return newCells + freed
    }
}
