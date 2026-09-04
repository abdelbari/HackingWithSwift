// Elements on the system pasteboard.
//
// The in-memory clipboard is instant and exact, and gone when the editor
// is. This mirrors it onto UIPasteboard so a copy survives switching
// designs or quitting, and adds two fallbacks a person expects: the text
// of a text element as plain text for other apps, and a picture or text
// copied *from* another app pasting in as a photo or a text element.

import UIKit

enum ElementClipboard {

    static let type = "com.canvia.elements"

    static func write(_ elements: [Element], to pasteboard: UIPasteboard = .general) {
        guard let data = try? JSONEncoder().encode(elements) else { return }
        var item: [String: Any] = [type: data]
        let text = elements.compactMap { $0.type == .text ? $0.text : nil }.joined(separator: "\n")
        if !text.isEmpty { item["public.utf8-plain-text"] = text }
        pasteboard.items = [item]
    }

    /// Our own elements, if the pasteboard carries them.
    static func read(from pasteboard: UIPasteboard = .general) -> [Element]? {
        guard let data = pasteboard.data(forPasteboardType: type),
              let elements = try? JSONDecoder().decode([Element].self, from: data),
              !elements.isEmpty else { return nil }
        return elements
    }

    /// Whether a paste has anything to offer: our elements, a picture, or text.
    static func hasContent(in pasteboard: UIPasteboard = .general) -> Bool {
        pasteboard.contains(pasteboardTypes: [type]) || pasteboard.hasImages || pasteboard.hasStrings
    }

    /// Something from another app as an element: a picture becomes a photo
    /// (stored like an import), text becomes a text element. Half the
    /// design's width, so it lands visible and not enormous.
    static func foreign(from pasteboard: UIPasteboard = .general, designWidth: Double) -> Element? {
        if pasteboard.hasImages, let image = pasteboard.image,
           let data = image.pngData(), let prepared = ImageDownsampler.prepare(data),
           let src = MediaStore.store(prepared) {
            let w = (designWidth * 0.5).rounded()
            let h = prepared.natural.width > 0
                ? (w * prepared.natural.height / prepared.natural.width).rounded() : w
            return Element.image(src, w: w, h: h)
        }
        if pasteboard.hasStrings, let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            var el = Element.text(text, fontSize: max(18, (designWidth / 24).rounded()), w: (designWidth * 0.6).rounded())
            el.h = FontLibrary.layoutHeight(for: el)
            return el
        }
        return nil
    }
}
