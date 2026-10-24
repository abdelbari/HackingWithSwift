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
    /// The id of the page the elements were copied from — the payload's
    /// `sourcePage`, as the Android twin's clipboard keeps it — beside them,
    /// so a paste onto another page lands in place (Copies.pasteOffset).
    static let sourcePageType = "com.canvia.elements.sourcePage"
    /// The design's records of the fonts of your own the elements are set
    /// in (CustomFonts.carried), as the design writes them, so a paste into
    /// a design without them still names a font this phone does not have —
    /// the Android twin's clipboard keeps them as "fonts".
    static let fontsType = "com.canvia.elements.fonts"

    /// `sourcePage` empty when the page is not known.
    static func write(_ elements: [Element], sourcePage: String = "", fonts: [CustomFonts.Record] = [],
                      to pasteboard: UIPasteboard = .general) {
        guard let data = try? JSONEncoder().encode(elements) else { return }
        var item: [String: Any] = [type: data]
        if !sourcePage.isEmpty { item[sourcePageType] = Data(sourcePage.utf8) }
        if !fonts.isEmpty, let records = try? JSONEncoder().encode(fonts) { item[fontsType] = records }
        let text = plainText(of: elements)
        if !text.isEmpty { item["public.utf8-plain-text"] = text }
        pasteboard.items = [item]
    }

    /// The words of the text elements as another app should get them: the
    /// style marks gone — "**SALE** today" pasted into Messages came out with
    /// its asterisks — and blank ones left out, one text a line. Pasting back
    /// into Canvia reads the elements themselves, so the styling survives
    /// there. The Android twin copies the same words.
    static func plainText(of elements: [Element]) -> String {
        elements.compactMap { el -> String? in
            guard el.type == .text, let text = el.text else { return nil }
            let words = RichText.strip(text)
            return words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : words
        }
        .joined(separator: "\n")
    }

    /// Our own elements, if the pasteboard carries them.
    static func read(from pasteboard: UIPasteboard = .general) -> [Element]? {
        guard let data = pasteboard.data(forPasteboardType: type),
              let elements = try? JSONDecoder().decode([Element].self, from: data),
              !elements.isEmpty else { return nil }
        return elements
    }

    /// The page our own elements were copied from, when the pasteboard
    /// says; nil from a build that did not write it.
    static func sourcePage(from pasteboard: UIPasteboard = .general) -> String? {
        guard let data = pasteboard.data(forPasteboardType: sourcePageType),
              let id = String(data: data, encoding: .utf8), !id.isEmpty else { return nil }
        return id
    }

    /// The records of the fonts of your own beside our own elements, an
    /// entry that does not read passed over; none from a build that did not
    /// write them.
    static func fonts(from pasteboard: UIPasteboard = .general) -> [CustomFonts.Record] {
        guard let data = pasteboard.data(forPasteboardType: fontsType),
              let list = try? JSONDecoder().decode([CustomFonts.Lenient].self, from: data) else { return [] }
        return list.compactMap(\.record)
    }

    /// Whether the pasteboard carries our own elements. Asking what types are
    /// there brings up no paste prompt; reading another app's content does.
    static func hasElements(in pasteboard: UIPasteboard = .general) -> Bool {
        pasteboard.contains(pasteboardTypes: [type])
    }

    /// Whether a paste has anything to offer: our elements, a picture, or text.
    static func hasContent(in pasteboard: UIPasteboard = .general) -> Bool {
        pasteboard.contains(pasteboardTypes: [type]) || pasteboard.hasImages || pasteboard.hasStrings
    }

    /// Something from another app as an element: a picture becomes a photo
    /// (stored like an import, and kept among your uploads), text becomes a
    /// text element. Half the design's width, so it lands visible and not
    /// enormous.
    static func foreign(from pasteboard: UIPasteboard = .general, designWidth: Double) -> Element? {
        if pasteboard.hasImages, let image = pasteboard.image,
           let data = image.pngData(), let prepared = ImageDownsampler.prepare(data),
           let src = MediaStore.store(prepared) {
            Uploads.record(source: src)
            let w = (designWidth * 0.5).rounded()
            let h = prepared.natural.width > 0
                ? (w * prepared.natural.height / prepared.natural.width).rounded() : w
            return Element.image(src, w: w, h: h)
        }
        if pasteboard.hasStrings, let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            // Read as written, its stars stars, and its bulleted or numbered
            // lines a list (TextLists.fromPasted).
            let pasted = TextLists.fromPasted(text)
            var el = Element.text(RichText.escapeLiteral(pasted.text), fontSize: max(18, (designWidth / 24).rounded()),
                                  w: (designWidth * 0.6).rounded())
            if pasted.paragraphs.contains(where: \.isListed) { el.setLines(pasted.paragraphs) }
            el.h = FontLibrary.layoutHeight(for: el)
            return el
        }
        return nil
    }
}
