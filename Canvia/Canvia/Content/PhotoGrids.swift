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

import Foundation

enum PhotoGrids {

    struct Layout: Identifiable {
        var id: String
        var name: String
        /// Cells in unit coordinates of the page's inner area, in reading
        /// order: a cell's index is its place here.
        var cells: [CGRect]
    }

    /// Spacing's track, in page units.
    static let maxSpacing: Double = 40
    /// Corners' track: a share of each cell's own shorter side, in percent.
    static let maxCorners: Double = 50

    /// One layout as the file has it: cells of [column, row, columns
    /// spanned, rows spanned] on a lattice of `columns` × `rows`.
    fileprivate struct GridDef: Decodable {
        var id: String
        var name: String
        var columns: Int
        var rows: Int
        var cells: [[Int]]
    }

    /// PhotoFrames.json: the grids here, the frames in DecorativeFrames.
    struct File: Decodable {
        fileprivate var photoGrids: [GridDef]
        var photoFrames: [FrameDef]
    }

    /// Read once, on first use.
    static let file: File = {
        guard let url = Bundle.main.url(forResource: "PhotoFrames", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(File.self, from: data) else {
            assertionFailure("PhotoFrames.json missing or invalid")
            return File(photoGrids: [], photoFrames: [])
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
        return Layout(id: entry.id, name: entry.name, cells: cells)
    }

    static func layout(_ id: String?) -> Layout? {
        layouts.first { $0.id == id }
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

    /// The cells of `layout` laid in `bounds` with `gutter` between them, by
    /// the same half-gutter rule as `elements` but not rounded: laid out
    /// again and again as Spacing is dragged, a rounded grid would creep a
    /// pixel at a time, and unrounded its outer edges stay exactly on
    /// `bounds`. No cell is narrower or shorter than 1.
    static func frames(_ layout: Layout, in bounds: CGRect, gutter: Double) -> [CGRect] {
        layout.cells.map { cell in
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

    /// The grid `cells` (as `grid(of:)` gives them) laid out again within
    /// the box round them now — wherever the grid has been moved or
    /// stretched — `gutter` apart, and each cell rounded `corners` percent of
    /// its own shorter side (`radius`). Each keeps its picture, crop, look
    /// and turn; the cells record the new spacing and, should the grid's
    /// group have changed, its group as their grid's id. Spacing within
    /// 0…maxSpacing, corners within 0…maxCorners.
    static func relaid(_ layout: Layout, cells: [Element], gutter: Double, corners: Double) -> [Element] {
        guard !cells.isEmpty else { return cells }
        let left = cells.map(\.x).min() ?? 0
        let top = cells.map(\.y).min() ?? 0
        let right = cells.map { $0.x + $0.w }.max() ?? 0
        let bottom = cells.map { $0.y + $0.h }.max() ?? 0
        let bounds = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        let spacing = min(max(gutter, 0), maxSpacing)
        let share = min(max(corners, 0), maxCorners) / 100
        let frames = Self.frames(layout, in: bounds, gutter: spacing)
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
            out.grid = cell
            return out
        }
    }
}
