// Font combinations: ready lockups of a heading, a subheading and body, or a
// title and a tagline — faces, weights, spacing, colours, effects, curves,
// small shapes and rules — that Add ▸ Text puts on the page in one tap, as
// Canva's do. The six font pairings the Text tab always had are the first
// six.
//
// They are textcombos.json, which the Android twin's
// tools/generate_textcombos.py writes — the very file Android ships, byte
// for byte. Each is an id, a name, the tags a search finds it by, and its
// elements in this phone's JSON, as a design file has them, in a box `w`
// wide from 0, 0 in a 1080-wide page's units; so both phones put the same
// elements down.

import Foundation

enum TextCombos {

    /// The share of the page's width a combination takes as it goes on.
    static let pageShare = 0.72

    /// One combination as the file has it: its elements, bottom to top, in a
    /// box `w` wide and `h` tall — down to its lowest element's bottom.
    struct Combo: Identifiable {
        var id: String
        var name: String
        var tags: [String]
        var w: Double
        var h: Double
        var elements: [Element]
    }

    /// One entry as it reads, whatever is missing from it: a number is read
    /// only as a number and words only as words, as the Android twin reads
    /// them.
    private struct RawCombo: Decodable {
        var id: String?
        var name: String?
        var tags: [String] = []
        var w: Double?
        var elements: [Element] = []

        private enum CodingKeys: String, CodingKey { case id, name, tags, w, elements }

        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            id = try? c.decode(String.self, forKey: .id)
            name = try? c.decode(String.self, forKey: .name)
            tags = (try? c.decode([String].self, forKey: .tags)) ?? []
            w = try? c.decode(Double.self, forKey: .w)
            elements = (try? c.decode([Element].self, forKey: .elements)) ?? []
        }
    }

    /// Read once, on first use.
    static let all: [Combo] = {
        guard let url = Bundle.main.url(forResource: "textcombos", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("textcombos.json missing")
            return []
        }
        return combos(from: data)
    }()

    /// The combinations in `data`, in its order: those with an id, a name, a
    /// width and elements; the rest passed over.
    static func combos(from data: Data) -> [Combo] {
        guard let entries = try? JSONDecoder().decode([RawCombo].self, from: data) else { return [] }
        return entries.compactMap { entry in
            guard let id = entry.id, !id.isEmpty, let name = entry.name, !name.isEmpty,
                  let w = entry.w, w > 0, !entry.elements.isEmpty else { return nil }
            let h = entry.elements.map { $0.y + $0.h }.max() ?? 0
            return Combo(id: id, name: name, tags: entry.tags, w: w, h: h, elements: entry.elements)
        }
    }

    static func combo(_ id: String?) -> Combo? {
        all.first { $0.id == id }
    }

    /// The combinations a search for `query` finds, in the file's order:
    /// those whose name or one of whose tags has it, case and accents aside,
    /// as the font picker searches. A blank query finds them all.
    static func search(_ query: String) -> [Combo] {
        all.filter { combo in
            FontLibrary.matches(combo.name, query) || combo.tags.contains { FontLibrary.matches($0, query) }
        }
    }

    /// What the Text tab says when a search finds none.
    static func noneFound(_ query: String) -> String {
        "No font combinations match \u{201C}\(query.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}."
    }

    /// `combo`'s elements `scale` times their size in its box: everything
    /// measured in page units scaled (Element.scaledSizes), and effects,
    /// curves and the words' own sizes, which are shares of the type, left
    /// as they are. Each with an id of its own.
    static func elements(_ combo: Combo, scale: Double) -> [Element] {
        combo.elements.map { el in
            var e = el.scaledSizes(by: scale)
            e.id = UID.make()
            e.x = el.x * scale
            e.y = el.y * scale
            return e
        }
    }

    /// `combo` as it goes on a page `pageWidth` × `pageHeight`, both phones'
    /// numbers: pageShare of the page's width wide, its box centred both
    /// ways, nothing rounded — every element with a fresh id, all of them
    /// one new group. A text's height is the file's; `measured` measures it
    /// again with the real faces, its top kept.
    static func placed(_ combo: Combo, pageWidth: Double, pageHeight: Double) -> [Element] {
        placed(combo, scale: pageWidth * pageShare / combo.w, pageWidth: pageWidth, pageHeight: pageHeight)
    }

    /// `combo` at `scale`, its box centred both ways on a page `pageWidth`
    /// × `pageHeight`, as one new group: what goes on the page, and what a
    /// tile shows.
    static func placed(_ combo: Combo, scale: Double, pageWidth: Double, pageHeight: Double) -> [Element] {
        let left = (pageWidth - combo.w * scale) / 2
        let top = (pageHeight - combo.h * scale) / 2
        let group = UID.make("grp")
        return elements(combo, scale: scale).map { el in
            var e = el
            e.x = left + el.x
            e.y = top + el.y
            e.group = group
            return e
        }
    }

    /// Each text at the height its words take in the real faces, its top
    /// kept, as the Android twin measures them; everything else as it is.
    static func measured(_ elements: [Element]) -> [Element] {
        elements.map { el in
            guard el.type == .text else { return el }
            var e = el
            e.h = FontLibrary.layoutHeight(for: el)
            return e
        }
    }
}
