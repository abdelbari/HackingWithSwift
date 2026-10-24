// A straight-edged shape's own geometry from the canvas and the Style
// panel (ShapeGeometry): its yellow handles — a star's inner corner, an
// arrow's head and shaft, a callout's tail, a notch — dragged live and let
// go as one step named Shape, its points or sides counted up and down, and
// Corner rounding on any of them. A locked shape, one held in place, or a
// locked page is left as it is.

import Foundation
import CoreGraphics

extension DesignStore {

    /// The library shape selected whose geometry can be set: one alone, a
    /// shape from the library that ShapeGeometry builds, neither locked nor
    /// held in place, on a page that is not locked.
    var shapedSelection: Element? {
        guard let el = singleSelection, el.type == .shape, !el.holdsPlace, !isPageLocked,
              el.pathData?.isEmpty ?? true, el.iconId == nil, let id = el.shapeId,
              ContentLibrary.shapeMap[id] != nil, ShapeGeometry.builds(id) else { return nil }
        return el
    }

    /// The yellow handles the selected shape shows, where they stand on the
    /// page, turned and flipped with its box; none while its words are typed.
    var geometryHandles: [CGPoint] {
        guard let el = shapedSelection, editingTextId == nil, let id = el.shapeId else { return [] }
        return ShapeGeometry.handles(id, el.shapeParams).map { Self.pagePoint(el, unit: $0) }
    }

    /// The selected shape's handle dragged to `page`, live; letting go
    /// closes the step (endGeometryDrag).
    func dragGeometryHandle(to page: CGPoint) {
        guard let el = shapedSelection, let id = el.shapeId else { return }
        let unit = Self.unitPoint(el, page: page)
        updateSelectedTransient { e in
            guard e.id == el.id else { return }
            e.shapeParams = ShapeGeometry.dragged(id, e.shapeParams, to: unit)
        }
    }

    /// A handle let go: the drag is one step, named Shape.
    func endGeometryDrag() {
        namedStep = tr("Shape")
        commit()
    }

    /// The selected shape's parameter `key` set to `value`, held to its
    /// range, as one step named Shape: a star's points or a polygon's sides
    /// from the stepper, or a handle moved by VoiceOver.
    func setShapeParameter(_ key: String, to value: Double) {
        guard let el = shapedSelection else { return }
        // Anything still open — words typed — is its own step first.
        if hasPendingChanges { commit() }
        namedStep = tr("Shape")
        updateSelected { e in
            guard e.id == el.id else { return }
            ShapeGeometry.setting(key, to: value, on: &e)
        }
        // A value that changed nothing records nothing, and names nothing.
        namedStep = nil
    }
}
