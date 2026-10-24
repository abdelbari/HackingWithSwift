// Brush mode: a photo painted on where it sits. The Erase and Restore brush
// (Photo bar ▸ Erase) makes parts of it clear and brings them back; the
// Blur and Pixelate brushes (Filters ▸ Effects) blur or block out the parts
// painted. Every stroke is kept on the element (MaskRaster), never in the
// picture, so any of it can be taken back or painted over later.
//
// Like crop mode, the whole session is one open step: each stroke shows at
// once, Undo stroke takes back the last, Done keeps them all as one Undo
// and Cancel puts the photo back as it was.

import CoreGraphics
import Foundation

/// The photo being brushed, and the brush.
struct BrushSession: Equatable {
    enum Kind: String {
        /// Erase and Restore: the element's mask.
        case mask
        /// A retouch layer of that kind.
        case blur, pixelate
    }

    var id: String
    var kind: Kind
    /// The size of the picture the strokes are mapped into.
    var imageSize: CGSize
    /// Restore, for the mask; Erase from effect, for a blur or pixelate.
    var reverse = false
    /// The brush's width, as a share of the picture's shorter side.
    var size = BrushSession.defaultSize
    /// The share of the brush's half-width its edge fades over, for the
    /// mask.
    var softness = BrushSession.defaultSoftness
    /// The blur's or the blocks' strength, 0…1.
    var strength = BrushSession.defaultStrength
    /// The retouch layer painted, by its place in the element's list, once
    /// the first stroke has made or found it.
    var layer: Int?
    /// The strokes painted in this session, newest last, which Undo stroke
    /// takes back.
    var painted = 0
    /// Show original is held.
    var comparing = false

    static let defaultSize = 0.05
    static let defaultSoftness = 0.3
    static let defaultStrength = 0.5
    /// Where the Size slider runs: MaskStroke's width, a share of the
    /// picture's shorter side.
    static let sizeRange = MaskStroke.widthRange

    var retouching: Bool { kind != .mask }

    /// The retouch layer's kind this brush paints; nil for the mask.
    var layerKind: String? {
        switch kind {
        case .mask: return nil
        case .blur: return RetouchLayer.blur
        case .pixelate: return RetouchLayer.pixelate
        }
    }
}

extension DesignStore {

    /// The photo being brushed, as it is now.
    var brushElement: Element? {
        brushing.flatMap { element($0.id) }
    }

    /// Brush mode on photo `id`. Refused, with a word, on a locked page or
    /// photo, for a code, a clip or an animated picture — whose pictures are
    /// not one still to paint on — and for a picture that cannot be read.
    @discardableResult
    func beginBrush(_ id: String, kind: BrushSession.Kind) -> Bool {
        guard let photo = element(id), photo.type == .image, !refusesLockedPage() else { return false }
        if photo.locked {
            buzz(.reject)
            announce(tr("This photo is locked. Tap Unlock to edit it."), undoable: false)
            return false
        }
        guard let src = photo.src, !CodeGenerator.isCode(src), !VideoStore.isVideo(src),
              !AnimStore.isAnim(src), !MotionLibrary.isMotion(src), let image = PhotoLibrary.resolve(src),
              image.size.width > 0, image.size.height > 0 else {
            buzz(.reject)
            announce(tr("This picture can't be brushed."), undoable: false)
            return false
        }
        finishBrush()
        drawing = nil
        cancelErasing()
        finishCrop()
        stopPreview()
        endTextEdit()
        // Whatever was under way is its own step, not the start of the brush.
        if hasPendingChanges { commit() }
        selection = [id]
        var session = BrushSession(id: id, kind: kind, imageSize: image.size)
        if let kind = session.layerKind, let at = photo.retouch?.firstIndex(where: { $0.kind == kind }) {
            session.layer = at
            session.strength = photo.retouch?[at].share ?? BrushSession.defaultStrength
        }
        brushing = session
        return true
    }

    /// A finger stroke, in page units, painted with the brush: mapped into
    /// the picture (ObjectEraser.picturePoints), held to it and rounded as
    /// strokes are written (MaskStroke.written), and added to the mask, or
    /// to the retouch layer — made at the end of the list, at the brush's
    /// strength, by the first stroke when the photo has none of its kind.
    func brushStroke(_ stroke: [CGPoint]) {
        guard var session = brushing, let photo = brushElement, !stroke.isEmpty else { return }
        let points = MaskStroke.written(ObjectEraser.picturePoints(stroke, element: photo, imageSize: session.imageSize))
        guard !points.isEmpty else { return }
        let width = min(max(session.size, BrushSession.sizeRange.lowerBound), BrushSession.sizeRange.upperBound)
        if let kind = session.layerKind {
            let painted = RetouchStroke(w: width, points: points, erases: session.reverse)
            var layers = photo.retouch ?? []
            if let at = session.layer, layers.indices.contains(at) {
                layers[at].strokes.append(painted)
            } else {
                layers.append(RetouchLayer(kind: kind, amount: session.strength, strokes: [painted]))
                session.layer = layers.count - 1
            }
            brushEdit { $0.retouch = layers }
        } else {
            let mode = session.reverse ? MaskStroke.restore : MaskStroke.erase
            let painted = MaskStroke(mode: mode, w: width, soft: session.softness, points: points)
            var mask = photo.mask ?? ImageMask()
            mask.strokes.append(painted)
            brushEdit { $0.mask = mask }
        }
        session.painted += 1
        brushing = session
    }

    /// The last stroke of this session taken back. A mask or layer left
    /// with nothing in it is none at once, so it is never written empty: a
    /// layer this session made goes (it is the last), and the next stroke
    /// makes another.
    func undoBrushStroke() {
        guard var session = brushing, session.painted > 0, let photo = brushElement else { return }
        if let at = session.layer {
            guard var layers = photo.retouch, layers.indices.contains(at), !layers[at].strokes.isEmpty else { return }
            layers[at].strokes.removeLast()
            if layers[at].strokes.isEmpty {
                layers.remove(at: at)
                session.layer = nil
            }
            brushEdit { $0.retouch = layers.isEmpty ? nil : layers }
        } else {
            guard var mask = photo.mask, !mask.strokes.isEmpty else { return }
            mask.strokes.removeLast()
            brushEdit { $0.mask = ImageMask.kept(mask) }
        }
        session.painted -= 1
        brushing = session
    }

    /// The blur's or the blocks' strength, live; part of the session's step.
    func setBrushStrength(_ strength: Double) {
        guard var session = brushing, session.retouching else { return }
        session.strength = min(max(strength, 0), 1)
        brushing = session
        guard let at = session.layer, var layers = brushElement?.retouch, layers.indices.contains(at) else { return }
        layers[at].amount = (session.strength * 100).rounded() / 100
        brushEdit { $0.retouch = layers }
    }

    /// Done: the strokes kept as one step — or none, if nothing changed.
    func finishBrush() {
        guard brushing != nil else { return }
        brushing = nil
        if hasPendingChanges { commit() }
    }

    /// Cancel: the photo put back exactly as it was when the brush was
    /// taken up.
    func cancelBrush() {
        guard brushing != nil else { return }
        brushing = nil
        revertGesture()
    }

    /// Every edit in brush mode: live, inside the one open step.
    private func brushEdit(_ change: (inout Element) -> Void) {
        guard let session = brushing else { return }
        updateSelectedTransient { el in
            if el.id == session.id { change(&el) }
        }
    }
}
