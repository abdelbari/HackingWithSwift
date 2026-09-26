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
        guard let photo = element(id), photo.type == .image else { return false }
        if photo.locked {
            announce("This photo is locked. Tap Unlock to crop it.")
            return false
        }
        if let src = photo.src, CodeGenerator.payload(from: src) != nil {
            announce("A QR code is used whole, so it can't be cropped.")
            return false
        }
        guard photo.src != nil else {
            announce("This frame is empty. Tap Replace to put a photo in it.")
            return false
        }
        guard let image = PhotoLibrary.resolve(photo.src), image.size.width > 0, image.size.height > 0 else {
            announce("This photo can't be opened, so it can't be cropped.")
            return false
        }
        drawing = nil
        cancelErasing()
        stopPreview()
        editingTextId = nil
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

    /// Keeps the crop, as one step — or as none, if nothing changed.
    func finishCrop() {
        guard cropping != nil else { return }
        cropping = nil
        badge = nil
        if hasPendingChanges { commit() }
    }

    /// Puts the photo back exactly as it was when crop mode opened.
    func cancelCrop() {
        guard cropping != nil else { return }
        cropping = nil
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
            badge = "Zoom \(Int((max(1, photo.cropScale ?? 1) * 100).rounded()))%"
        }
    }

    /// The frame trimmed from `start`, the photo as the handle was grabbed,
    /// by dragging `handle` to a page point.
    func trimCrop(from start: Element, handle: Handle, to point: CGPoint, minSize: Double) {
        guard let crop = cropping else { return }
        let trimmed = Crop.trimmed(start, image: crop.imageSize, handle: handle, to: point, minSize: minSize)
        cropEdit { _ in trimmed }
        badge = "\(Int(trimmed.w.rounded())) × \(Int(trimmed.h.rounded()))"
    }

    /// Every edit in crop mode: live, inside the one open step.
    func cropEdit(_ transform: (Element) -> Element) {
        guard let crop = cropping else { return }
        updateSelectedTransient { el in
            if el.id == crop.id { el = transform(el) }
        }
    }
}
