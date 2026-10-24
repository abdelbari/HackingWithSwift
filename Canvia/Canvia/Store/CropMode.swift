// Crop mode: the photo cropped where it sits on the page.
//
// The crop sheet's three sliders — zoom, horizontal focus, vertical focus —
// asked you to steer a picture you could not touch, and stopped at three
// times. In crop mode the picture is worked directly, as in every photo
// editor and as on the Android twin: drag it behind the frame, pinch it up
// to ten times, pull the frame's brackets in across it. The whole of the
// picture shows faintly beyond the frame, so you can see what you are
// bringing in. Done keeps it all as one Undo; Cancel puts the photo back
// exactly as it was.
//
// Nothing new is stored: crop mode writes the same cropScale, cropX and
// cropY the sheet always wrote (and x/y/w/h on a trim), by the rules in
// Crop, which the Android twin shares — so a crop made on either phone looks
// the same on the other.

import CoreGraphics
import Foundation

/// The photo being cropped and the size its picture is drawn from.
struct CropSession: Equatable {
    var id: String
    var imageSize: CGSize
}

extension DesignStore {

    /// The photo in crop mode, as it is now.
    var cropElement: Element? {
        cropping.flatMap { element($0.id) }
    }

    /// Opens crop mode on photo `id`. Refused, with a word, when the photo
    /// is locked, is a code, is an empty frame, or its picture cannot be read
    /// — a crop of a picture that is not there would be a frame over nothing.
    @discardableResult
    func startCrop(_ id: String) -> Bool {
        if cropping != nil { return true }
        // A graphic, or a group of them, has crop mode of its own: the
        // window over it rather than the picture behind a frame.
        if let el = element(id), el.type != .image {
            if !selection.contains(id) { selection = [id] }
            return startGraphicCrop()
        }
        guard let photo = element(id), photo.type == .image, !refusesLockedPage() else { return false }
        if photo.locked {
            announce(tr("This photo is locked. Tap Unlock to crop it."), undoable: false)
            return false
        }
        if CodeGenerator.isCode(photo.src) {
            announce(tr("A QR code is used whole, so it can't be cropped."), undoable: false)
            return false
        }
        guard photo.src != nil else {
            announce(tr("This frame is empty. Tap Replace to put a photo in it."), undoable: false)
            return false
        }
        guard let image = PhotoLibrary.resolve(photo.src), image.size.width > 0, image.size.height > 0 else {
            announce(tr("This photo can't be opened, so it can't be cropped."), undoable: false)
            return false
        }
        drawing = nil
        cancelErasing()
        finishBrush()
        stopPreview()
        endTextEdit()
        // Whatever was under way is its own step, not the start of the crop.
        if hasPendingChanges { commit() }
        // Just this photo, even when it belongs to a group: it is the one
        // being cropped.
        selection = [photo.id]
        beginGesture()
        cropping = CropSession(id: photo.id, imageSize: image.size)
        // Cropping is choosing which part fills the frame, so a photo shown
        // whole goes back to filling it — inside the crop's step, so Cancel
        // puts that back too.
        if photo.cropFit == true { cropEdit { var e = $0; e.cropFit = nil; return e } }
        badge = nil
        guideX = nil
        guideY = nil
        return true
    }

    /// Keeps the crop, as one step — or as none, if nothing changed. Every
    /// way out that keeps a crop keeps a brush's strokes too, as its own
    /// step (finishBrush).
    func finishCrop() {
        finishBrush()
        guard cropping != nil else { return }
        cropping = nil
        // The dial's bar goes with crop mode, before it can say it was let go.
        cropDialHeld = false
        badge = nil
        if hasPendingChanges { commit() }
    }

    /// Puts the photo back exactly as it was when crop mode opened.
    func cancelCrop() {
        guard cropping != nil else { return }
        cropping = nil
        // The dial's bar goes with crop mode, before it can say it was let go.
        cropDialHeld = false
        badge = nil
        revertGesture()
    }

    /// The picture centred and just covering the frame again. The frame's
    /// shape is kept: a trim is undone by pulling the edge back out.
    func resetCrop() {
        cropEdit { Crop.reset($0) }
    }

    /// What the crop bar's slider sets: 1 just covers the frame.
    func setCropZoom(_ zoom: Double) {
        guard let crop = cropping else { return }
        cropEdit { Crop.zoomed($0, image: crop.imageSize, to: zoom) }
    }

    /// A frame shape from the crop bar's chips: the frame trimmed to the
    /// ratio (Crop.trimmedToRatio), inside the one open step. Free leaves
    /// the frame as it is. Not for a photo locked in position, whose frame
    /// stays put, as the brackets are not drawn for it.
    func setCropAspect(_ aspect: CropAspect) {
        guard let crop = cropping, let photo = cropElement, !photo.holdsPlace,
              let ratio = aspect.ratio(image: crop.imageSize) else { return }
        cropEdit { Crop.trimmedToRatio($0, ratio: ratio, image: crop.imageSize) }
        if let trimmed = cropElement {
            badge = Units.readout(width: trimmed.w.rounded(), height: trimmed.h.rounded(), design)
        }
    }

    /// The straighten dial: the existing `straighten` key, written live in
    /// half-degree steps (Crop.steppedStraighten), nil at level.
    func setCropStraighten(_ degrees: Double) {
        let was = cropElement?.straighten
        cropEdit { var e = $0; e.straighten = Crop.steppedStraighten(degrees); return e }
        // The detent: a tick as the dial lands on level.
        if was != nil, cropElement?.straighten == nil { buzz(.tick) }
    }

    /// Rotate 90: a quarter turn clockwise, the frame's sides swapped
    /// about its centre (Crop.rotated90). Not for a photo locked in
    /// position, whose frame stays put.
    func rotateCrop90() {
        guard let photo = cropElement, !photo.holdsPlace else { return }
        cropEdit { Crop.rotated90($0) }
    }

    /// Flip: the picture mirrored left to right, the existing `flipH` key.
    func flipCrop() {
        cropEdit { var e = $0; e.flipH.toggle(); return e }
    }

    /// A tenth of the frame in a direction on screen: how VoiceOver, Switch
    /// Control or a keyboard moves the picture.
    func nudgeCrop(dx: Double, dy: Double) {
        guard let crop = cropping, let photo = cropElement else { return }
        let step = min(photo.w, photo.h) * 0.1
        cropEdit { Crop.moved($0, image: crop.imageSize, by: CGPoint(x: dx * step, y: dy * step)) }
    }

    /// The picture moved by a page-space `delta`, under the finger.
    func moveCropPicture(by delta: CGPoint) {
        guard let crop = cropping else { return }
        cropEdit { Crop.moved($0, image: crop.imageSize, by: delta) }
    }

    /// The picture zoomed by `factor` about a page point — a pinch.
    func zoomCropPicture(by factor: Double, around point: CGPoint) {
        guard let crop = cropping else { return }
        cropEdit { Crop.zoomed($0, image: crop.imageSize, by: factor, around: point) }
        if let photo = cropElement {
            badge = tr("Zoom %@", "\(Int((max(1, photo.cropScale ?? 1) * 100).rounded()))%")
        }
    }

    /// The frame trimmed from `start`, the photo as the handle was grabbed,
    /// by dragging `handle` to a page point. Not for a photo locked in
    /// position: its frame stays put, and only the picture in it moves.
    func trimCrop(from start: Element, handle: Handle, to point: CGPoint, minSize: Double) {
        guard let crop = cropping, !start.holdsPlace else { return }
        let trimmed = Crop.trimmed(start, image: crop.imageSize, handle: handle, to: point, minSize: minSize)
        cropEdit { _ in trimmed }
        badge = Units.readout(width: trimmed.w.rounded(), height: trimmed.h.rounded(), design)
    }

    /// Every edit in crop mode: live, inside the one open step.
    func cropEdit(_ transform: (Element) -> Element) {
        guard let crop = cropping else { return }
        updateSelectedTransient { el in
            if el.id == crop.id { el = transform(el) }
        }
    }
}
