// Crop mode for graphics: an icon, a shape, a sticker or a group of them —
// the generated graphics among them — shows only part of itself, as Canva
// crops an illustration (GraphicClip). It is the photo's crop mode without
// the picture to move or zoom, nor the straighten dial — a vector has no
// pixels to place: the crop bar's ratios and Reset, and brackets on the
// window that trim it. The window is kept as the element's `clip`, shares
// of its own box — of the group's frame, on every member, for a group.
// One open step: Done keeps it as a single Undo, Cancel puts it back, and
// Reset shows the whole again.

import CoreGraphics
import Foundation

/// What is being cropped: the element, or a whole group's members, and the
/// box the crop is in shares of — the element's own frame, or the group's,
/// turned with it. A lone element flipped shows its crop mirrored, so the
/// window is too.
struct GraphicCropSession: Equatable {
    var ids: [String]
    var frame: Geometry.GroupFrame
    var flipH = false
    var flipV = false
}

extension DesignStore {

    /// Whether Crop is offered for the selection as a graphic: one shape or
    /// sticker, or one whole group of things that are not photos, nothing
    /// in it locked or held in place, on a page that is not locked.
    var canCropGraphic: Bool {
        let members = selectedElements
        if members.count == 1, let el = members.first {
            return GraphicClip.croppable(el) && !el.holdsPlace
        }
        return Groups.whole(page.elements, selection: selection) != nil && GraphicClip.croppableGroup(members)
    }

    /// Opens crop mode on the selected graphic or group, its step opened.
    /// Refused on a locked page, and for anything else.
    @discardableResult
    func startGraphicCrop() -> Bool {
        if graphicCropping != nil { return true }
        guard canCropGraphic, !refusesLockedPage() else { return false }
        let members = selectedElements
        drawing = nil
        cancelErasing()
        finishBrush()
        stopPreview()
        endTextEdit()
        if hasPendingChanges { commit() }
        beginGesture()
        if members.count == 1, let el = members.first {
            let frame = Geometry.GroupFrame(center: el.center, size: CGSize(width: el.w, height: el.h), angle: el.rotation)
            graphicCropping = GraphicCropSession(ids: [el.id], frame: frame, flipH: el.flipH, flipV: el.flipV)
        } else {
            let turn = Groups.turn(page.elements, selection: selection)
            graphicCropping = GraphicCropSession(ids: members.map(\.id), frame: Geometry.groupFrame(members, angle: turn))
        }
        badge = nil
        return true
    }

    /// The crop window as it shows, in the frame's own upright box — the
    /// whole frame when nothing is cropped yet.
    var graphicCropWindow: CGRect? {
        guard let crop = graphicCropping, let first = crop.ids.first.flatMap(element) else { return nil }
        let upright = crop.frame.upright
        return GraphicClip.window(Self.mirrored(first.clipBox, crop), in: upright)
    }

    /// The window set to `window`, a box in the frame's upright box, kept
    /// inside it and at least the least share across: live, inside the
    /// open step, on every member alike.
    func setGraphicCropWindow(_ window: CGRect) {
        guard let crop = graphicCropping else { return }
        let upright = crop.frame.upright
        let kept = window.intersection(upright)
        guard !kept.isNull else { return }
        let box = Self.mirrored(GraphicClip.clip(window: kept, in: upright), crop)
        let ids = Set(crop.ids)
        updateSelectedTransient { el in
            if ids.contains(el.id) { el.clipBox = box }
        }
        badge = Units.readout(width: Double(kept.width).rounded(), height: Double(kept.height).rounded(), design)
    }

    /// A ratio from the crop bar: the window cut to it about its middle,
    /// inside the frame; Free leaves it, Original is the frame's own.
    func setGraphicCropAspect(_ aspect: CropAspect) {
        guard let crop = graphicCropping, let window = graphicCropWindow,
              let ratio = aspect.ratio(image: crop.frame.size), ratio > 0 else { return }
        var w = Double(window.width), h = Double(window.height)
        if w / max(h, 0.0001) > ratio { w = h * ratio } else { h = w / ratio }
        let upright = crop.frame.upright
        let x = min(max(Double(window.midX) - w / 2, Double(upright.minX)), Double(upright.maxX) - w)
        let y = min(max(Double(window.midY) - h / 2, Double(upright.minY)), Double(upright.maxY) - h)
        setGraphicCropWindow(CGRect(x: x, y: y, width: w, height: h))
    }

    /// Reset: the whole graphic again, no `clip` left.
    func resetGraphicCrop() {
        guard let crop = graphicCropping else { return }
        let ids = Set(crop.ids)
        updateSelectedTransient { el in
            if ids.contains(el.id) { el.clipBox = nil }
        }
        badge = nil
    }

    /// Keeps the crop, as one step named Crop — or none, if nothing changed.
    func finishGraphicCrop() {
        guard graphicCropping != nil else { return }
        graphicCropping = nil
        badge = nil
        if hasPendingChanges {
            namedStep = tr("Crop")
            commit()
        }
    }

    /// Puts the graphic back exactly as it was when crop mode opened.
    func cancelGraphicCrop() {
        guard graphicCropping != nil else { return }
        graphicCropping = nil
        badge = nil
        revertGesture()
    }

    /// A crop as shares of the frame on screen, or back: mirrored across
    /// for a lone element flipped, as it is drawn (the same both ways).
    static func mirrored(_ box: ClipBox?, _ crop: GraphicCropSession) -> ClipBox? {
        guard var box, crop.flipH || crop.flipV else { return box }
        if crop.flipH { box.x = 1 - box.x - box.w }
        if crop.flipV { box.y = 1 - box.y - box.h }
        return box
    }
}
