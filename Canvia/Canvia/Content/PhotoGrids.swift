// Photo grid layouts: several empty frames at once, sharing one gutter.
//
// A collage is three photos in a row far more often than it is anything
// clever, and placing three frames by hand — same size, even gaps, flush to
// the margins — is ten minutes of nudging. A layout is those frames in one
// tap; the photos go in with Replace.

import Foundation

enum PhotoGrids {

    struct Layout: Identifiable {
        var id: String
        var name: String
        /// Cells in unit coordinates of the page's inner area.
        var cells: [CGRect]
    }

    static let layouts: [Layout] = [
        Layout(id: "two", name: "2 across", cells: [
            CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]),
        Layout(id: "three", name: "3 across", cells: [
            CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1), CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1),
            CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)]),
        Layout(id: "four", name: "2 by 2", cells: [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]),
        Layout(id: "onePlusTwo", name: "1 + 2", cells: [
            CGRect(x: 0, y: 0, width: 0.6, height: 1),
            CGRect(x: 0.6, y: 0, width: 0.4, height: 0.5), CGRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5)]),
        Layout(id: "bigTop", name: "1 over 3", cells: [
            CGRect(x: 0, y: 0, width: 1, height: 0.6),
            CGRect(x: 0, y: 0.6, width: 1.0 / 3, height: 0.4), CGRect(x: 1.0 / 3, y: 0.6, width: 1.0 / 3, height: 0.4),
            CGRect(x: 2.0 / 3, y: 0.6, width: 1.0 / 3, height: 0.4)]),
        Layout(id: "nine", name: "3 by 3", cells: (0..<9).map {
            CGRect(x: Double($0 % 3) / 3, y: Double($0 / 3) / 3, width: 1.0 / 3, height: 1.0 / 3) }),
    ]

    /// Empty photo frames for the layout on a page of `width` × `height`,
    /// with `margin` around the outside and `gutter` between cells, grouped
    /// so they move together.
    static func elements(for layout: Layout, width: Double, height: Double,
                         margin: Double, gutter: Double) -> [Element] {
        let innerW = max(width - 2 * margin, 1), innerH = max(height - 2 * margin, 1)
        let group = UID.make("grp")
        return layout.cells.map { cell in
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
            return el
        }
    }
}
