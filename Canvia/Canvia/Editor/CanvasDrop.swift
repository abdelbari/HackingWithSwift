// Things dropped onto the page from other apps — a photo from Photos or
// Files, a passage from Notes, a link from Safari — land where the finger
// let go, as the elements the Add sheet would have made; a photo let go over
// a frame goes into the frame.

import SwiftUI
import UniformTypeIdentifiers

enum CanvasDrop {

    static let types: [UTType] = [.image, .text, .url]

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

    static func textElement(_ string: String, page: CGSize, at point: CGPoint) -> Element {
        let size = max(18, (page.width * 0.04).rounded())
        var el = Element.text(string.trimmingCharacters(in: .whitespacesAndNewlines), fontSize: size, w: (page.width * 0.6).rounded())
        el.align = "left"
        el.h = FontLibrary.layoutHeight(for: el)
        let frame = textFrame(page: page, at: point, height: el.h)
        el.x = frame.minX
        el.y = frame.minY
        return el
    }

    /// Pictures first, then text, then links as their address. Returns
    /// whether anything was taken; the elements arrive as each item loads,
    /// and once all have, it is said if none could be used — as the Android
    /// twin says it.
    @MainActor
    static func handle(_ providers: [NSItemProvider], at point: CGPoint, store: DesignStore) -> Bool {
        let page = store.pageSize
        let tally = Tally(store: store)
        var taken = 0
        for provider in providers {
            let offset = Double(taken) * page.width * 0.04
            let at = CGPoint(x: point.x + offset, y: point.y + offset)
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                || provider.canLoadObject(ofClass: UIImage.self) {
                taken += 1
                loadPicture(provider) { stored in
                    guard let stored else { tally.finished(landed: false); return }
                    // Let go over a frame or a grid's cell, the picture goes
                    // into it rather than onto the page beside it.
                    if let target = PhotoFrames.target(at: at, in: store.page.elements, excluding: nil),
                       store.replacePicture(target.id, with: stored.src) {
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
    /// falls back to its UIImage, stored with its alpha. `done` runs on the
    /// main actor.
    private static func loadPicture(_ provider: NSItemProvider,
                                    done: @escaping @MainActor ((src: String, natural: CGSize)?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                // Called off the main thread, where the decode belongs.
                var stored: (src: String, natural: CGSize)?
                if let data, let prepared = ImageDownsampler.prepare(data), let src = MediaStore.store(prepared) {
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
                stored = (src, image.size)
            }
            let result = stored
            Task { @MainActor in done(result) }
        }
    }

    /// Counts a drop's items home, and says how it went once all are in.
    @MainActor
    private final class Tally {
        let store: DesignStore
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
                store.announce("Nothing there this page can take", undoable: false)
            } else {
                store.buzz(.confirm)
            }
        }
    }
}
