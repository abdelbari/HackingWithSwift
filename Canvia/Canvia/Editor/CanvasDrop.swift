// Things dropped onto the page from other apps — a photo from Photos or
// Files, a passage from Notes, a link from Safari — land where the finger
// let go, as the elements the Add sheet would have made.

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
    /// whether anything was taken; the elements arrive as each item loads.
    @MainActor
    static func handle(_ providers: [NSItemProvider], at point: CGPoint, store: DesignStore) -> Bool {
        let page = store.pageSize
        var taken = 0
        for provider in providers {
            let offset = Double(taken) * page.width * 0.04
            let at = CGPoint(x: point.x + offset, y: point.y + offset)
            if provider.canLoadObject(ofClass: UIImage.self) {
                taken += 1
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    guard let image = object as? UIImage else { return }
                    Task.detached(priority: .userInitiated) {
                        guard let src = MediaStore.storeOpaque(image) else { return }
                        let natural = image.size
                        await MainActor.run {
                            let frame = imageFrame(natural: natural, page: page, at: at)
                            var el = Element.image(src, w: frame.width, h: frame.height)
                            el.x = frame.minX; el.y = frame.minY
                            store.add(el, centered: false)
                            store.tipEvent = .dropped
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                taken += 1
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { @MainActor in
                        store.add(textElement(text, page: page, at: at), centered: false)
                        store.tipEvent = .dropped
                    }
                }
            } else if provider.canLoadObject(ofClass: NSURL.self) {
                taken += 1
                provider.loadObject(ofClass: NSURL.self) { object, _ in
                    guard let url = object as? URL else { return }
                    Task { @MainActor in
                        store.add(textElement(url.absoluteString, page: page, at: at), centered: false)
                        store.tipEvent = .dropped
                    }
                }
            }
        }
        return taken > 0
    }
}
