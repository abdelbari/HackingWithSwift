// Face retouch turned on and off (Filters ▸ Effects ▸ Face retouch): the
// photo's faces found once, off the main thread (FaceFinder), and kept on it
// with the usual amount as one step — or, when there are none, said, with
// the Retouch brush beside it to smooth by hand. As the Android twin's
// turnOnFaceRetouch.

import Foundation

extension DesignStore {

    /// Whether `el` is a still photo, which Face retouch and Expand work on:
    /// a picture in it — not an empty frame — and not a clip, an animated or
    /// moving picture, nor a code, which is used whole. Unlocked.
    static func isStillPhoto(_ el: Element?) -> Bool {
        guard let el, el.type == .image, !el.locked, let src = el.src, !src.isEmpty else { return false }
        return !VideoStore.isVideo(src) && !AnimStore.isAnim(src) && !MotionLibrary.isMotion(src)
            && !CodeGenerator.isCode(src)
    }

    /// Face retouch on for photo `id`: its faces found off the main thread
    /// and kept with FaceRetouch.defaultAmount, as one step; none found is
    /// felt and said, and `noFacesIn` names the photo. Not on a locked page;
    /// a photo moved off the page, locked or given another picture meanwhile
    /// keeps what it has — the faces were another picture's.
    @MainActor
    func turnOnFaceRetouch(_ id: String) {
        guard findingFaces == nil, let photo = element(id), Self.isStillPhoto(photo), let src = photo.src,
              !refusesLockedPage() else { return }
        guard let image = PhotoLibrary.resolve(src) else {
            buzz(.reject)
            return
        }
        findingFaces = id
        noFacesIn = nil
        Task { @MainActor in
            let faces = await Task.detached(priority: .userInitiated) { FaceFinder.faces(in: image) }.value
            self.findingFaces = nil
            guard let now = self.element(id), !now.locked, now.src == src, !self.isPageLocked else { return }
            guard !faces.isEmpty else {
                self.noFacesIn = id
                self.buzz(.reject)
                self.announce(tr("No faces found"), undoable: false)
                return
            }
            self.selection = [id]
            self.updateSelected { $0.retouchFace = FaceRetouch(faces: faces) }
            self.buzz(.confirm)
        }
    }

    /// Face retouch off for the selected photo, as one step; its faces go
    /// with it, and are found again when it is turned back on.
    func turnOffFaceRetouch() {
        guard singleSelection?.retouchFace != nil else { return }
        updateSelected { $0.retouchFace = nil }
    }
}
