// Things dropped onto the page from other apps — a photo or a clip from
// Photos, Files or Add's Gallery, a passage from Notes, a link from Safari —
// land where the finger let go, as the elements the Add sheet would have
// made; a photo or a clip let go over a frame goes into the frame, and a
// photo let go over a selected text box is offered to its letters
// (PhotoInLetters). Nothing lands on a locked page.

import SwiftUI
import UniformTypeIdentifiers

enum CanvasDrop {

    static let types: [UTType] = [.movie, .image, .text, .url]

    /// A dropped picture takes up to half the page's width, keeps its shape,
    /// is centred on the drop point and pulled back inside the page.
    static func imageFrame(natural: CGSize, page: CGSize, at point: CGPoint) -> CGRect {
        let w = min(page.width * 0.5, natural.width > 0 ? natural.width : page.width * 0.5)
        let h = natural.width > 0 ? w * natural.height / natural.width : w * 0.75
        return clamp(CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w.rounded(), height: h.rounded()), to: page)
    }

    /// Dropped text is a box six tenths of the page wide, centred on the
    /// drop point.
    static func textFrame(page: CGSize, at point: CGPoint, height: Double) -> CGRect {
        let w = (page.width * 0.6).rounded()
        return clamp(CGRect(x: point.x - w / 2, y: point.y - height / 2, width: w, height: height), to: page)
    }

    /// Slid, not shrunk, so the whole of it is on the page when it fits.
    static func clamp(_ rect: CGRect, to page: CGSize) -> CGRect {
        var r = rect
        r.origin.x = min(max(r.minX, 0), max(page.width - r.width, 0)).rounded()
        r.origin.y = min(max(r.minY, 0), max(page.height - r.height, 0)).rounded()
        return r
    }

    /// The frame or grid cell a dropped picture goes into: the one under
    /// `point`, unless this drop has already filled it, when the picture
    /// goes on the page beside it rather than over the one before, as on
    /// the Android twin.
    static func pictureTarget(at point: CGPoint, in elements: [Element], filled: Set<String>) -> Element? {
        guard let target = PhotoFrames.target(at: point, in: elements, excluding: nil),
              !filled.contains(target.id) else { return nil }
        return target
    }

    static func textElement(_ string: String, page: CGSize, at point: CGPoint) -> Element {
        let size = max(18, (page.width * 0.04).rounded())
        // Dropped words read as they are: their stars and underscores
        // literal (RichText.escapeLiteral), as on the Android twin.
        let words = RichText.escapeLiteral(string.trimmingCharacters(in: .whitespacesAndNewlines))
        var el = Element.text(words, fontSize: size, w: (page.width * 0.6).rounded())
        el.align = "left"
        el.h = FontLibrary.layoutHeight(for: el)
        let frame = textFrame(page: page, at: point, height: el.h)
        el.x = frame.minX
        el.y = frame.minY
        return el
    }

    /// Clips and pictures first, then text, then links as their address. Returns
    /// whether anything was taken; the elements arrive as each item loads,
    /// and once all have, it is said if none could be used — as the Android
    /// twin says it.
    @MainActor
    static func handle(_ providers: [NSItemProvider], at point: CGPoint, store: DesignStore) -> Bool {
        // Nothing dropped lands on a locked page.
        guard !store.refusesLockedPage() else { return false }
        let page = store.pageSize
        let tally = Tally(store: store)
        var taken = 0
        for provider in providers {
            let offset = Double(taken) * page.width * 0.04
            let at = CGPoint(x: point.x + offset, y: point.y + offset)
            let clip = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
            if clip || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                || provider.canLoadObject(ofClass: UIImage.self) {
                taken += 1
                let landed: @MainActor ((src: String, natural: CGSize)?) -> Void = { stored in
                    guard let stored else { tally.finished(landed: false); return }
                    // Let go over a selected text box, the picture may fill
                    // its letters: asked (PhotoInLettersPrompts), the photo
                    // kept for the page meanwhile. Only the first of several
                    // is offered; the rest go on as any photo does, as on the
                    // Android twin, so none is lost to a later offer. A clip
                    // never is.
                    if !clip, store.letterFillOffer == nil, let text = store.letterFillTarget(at: at) {
                        let frame = imageFrame(natural: stored.natural, page: page, at: at)
                        store.letterFillOffer = LetterFillOffer(id: text.id, src: stored.src, frame: frame)
                        tally.finished(landed: true)
                        return
                    }
                    // Let go over a frame or a grid's cell, the picture goes
                    // into it rather than onto the page beside it.
                    if let target = pictureTarget(at: at, in: store.page.elements, filled: tally.filled),
                       store.replacePicture(target.id, with: stored.src) {
                        tally.filled.insert(target.id)
                        store.selection = [target.id]
                        store.tipEvent = .dropped
                        tally.finished(landed: true)
                        return
                    }
                    let frame = imageFrame(natural: stored.natural, page: page, at: at)
                    var el = Element.image(stored.src, w: frame.width, h: frame.height)
                    el.x = frame.minX; el.y = frame.minY
                    store.add(el, centered: false)
                    store.tipEvent = .dropped
                    tally.finished(landed: true)
                }
                if clip { loadClip(provider, done: landed) } else { loadPicture(provider, done: landed) }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                taken += 1
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    let text = (object as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Task { @MainActor in
                        guard !text.isEmpty else { tally.finished(landed: false); return }
                        store.add(textElement(text, page: page, at: at), centered: false)
                        store.tipEvent = .dropped
                        tally.finished(landed: true)
                    }
                }
            } else if provider.canLoadObject(ofClass: NSURL.self) {
                taken += 1
                provider.loadObject(ofClass: NSURL.self) { object, _ in
                    let url = object as? URL
                    Task { @MainActor in
                        guard let url else { tally.finished(landed: false); return }
                        store.add(textElement(url.absoluteString, page: page, at: at), centered: false)
                        store.tipEvent = .dropped
                        tally.finished(landed: true)
                    }
                }
            }
        }
        tally.expect(taken)
        return taken > 0
    }

    /// A dropped picture's own bytes, through the same downsampling and
    /// storing as the photo picker's: PNG when it has see-through parts, so
    /// a logo dragged in from Files or Safari keeps its clear surround, and
    /// no wider than the picker would keep it. A provider with no data
    /// falls back to its UIImage, stored with its alpha. Either is kept
    /// among your uploads. `done` runs on the main actor.
    private static func loadPicture(_ provider: NSItemProvider,
                                    done: @escaping @MainActor ((src: String, natural: CGSize)?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                // Called off the main thread, where the decode belongs.
                var stored: (src: String, natural: CGSize)?
                if let data, let animated = AnimStore.bringIn(data) {
                    // An animated GIF or WebP, kept as it came, to play.
                    stored = animated
                } else if let data, let prepared = ImageDownsampler.prepare(data), let src = MediaStore.store(prepared) {
                    Uploads.record(source: src, name: provider.suggestedName)
                    stored = (src, prepared.natural)
                }
                let result = stored
                Task { @MainActor in done(result) }
            }
            return
        }
        provider.loadObject(ofClass: UIImage.self) { object, _ in
            var stored: (src: String, natural: CGSize)?
            if let image = object as? UIImage, let src = MediaStore.storeTransparent(image) {
                Uploads.record(source: src)
                stored = (src, image.size)
            }
            let result = stored
            Task { @MainActor in done(result) }
        }
    }

    /// A dropped clip — one dragged from Add's Gallery or Photos — kept as
    /// a picked one is: its bytes stored whole under a fresh id, among your
    /// uploads, and made light in the background (VideoImport); shown by its
    /// poster frame. `done` runs on the main actor.
    private static func loadClip(_ provider: NSItemProvider,
                                 done: @escaping @MainActor ((src: String, natural: CGSize)?) -> Void) {
        let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .movie) == true }
            ?? UTType.movie.identifier
        // Its file's name, kept with the upload as a picture's is: what a
        // suggested description is drawn from (AltText.suggest).
        let name = provider.suggestedName
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
            // The file is there only while this runs: its bytes kept at once,
            // off the main thread.
            var stored: (src: String, natural: CGSize)?
            if let url, let data = try? Data(contentsOf: url),
               let id = VideoStore.store(data, ext: UTType(type)?.preferredFilenameExtension ?? url.pathExtension),
               let poster = VideoStore.poster(id) {
                Uploads.record(id, kind: .video, name: name)
                VideoImport.optimiseSoon(id)
                stored = (VideoStore.src(id, at: nil), poster.size)
            }
            let result = stored
            Task { @MainActor in done(result) }
        }
    }

    /// Counts a drop's items home, and says how it went once all are in.
    @MainActor
    private final class Tally {
        let store: DesignStore
        /// The frames this drop has put a picture in.
        var filled: Set<String> = []
        private var expected: Int?
        private var finishedCount = 0
        private var landedCount = 0

        init(store: DesignStore) { self.store = store }

        func expect(_ count: Int) {
            expected = count
            settle()
        }

        func finished(landed: Bool) {
            finishedCount += 1
            if landed { landedCount += 1 }
            settle()
        }

        private func settle() {
            guard let expected, finishedCount >= expected else { return }
            self.expected = nil
            if landedCount == 0 {
                store.buzz(.reject)
                store.announce(tr("Nothing there this page can take"), undoable: false)
            } else {
                store.buzz(.confirm)
            }
        }
    }
}
