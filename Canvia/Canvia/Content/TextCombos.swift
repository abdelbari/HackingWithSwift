// Font combinations: ready lockups of a heading, a subheading and body, or a
// title and a tagline — faces, weights, spacing, colours, effects, curves,
// small shapes and rules — that Add ▸ Text puts on the page in one tap, as
// Canva's do. The six font pairings the Text tab always had are the first
// six.
//
// They are textcombos.json, which the Android twin's
// tools/generate_textcombos.py writes — the very file Android ships, byte
// for byte. Each is an id, a name, the tags a search finds it by, its
// category (categories), and its elements in this phone's JSON, as a design
// file has them, in a box `w` wide from 0, 0 in a 1080-wide page's units; so
// both phones put the same elements down.
//
// The Animated category's drop in already moving: their texts carry the
// `animation` (and some an `exitAnimation`) ElementAnimation plays, kept as
// they go on the page; their tiles play them in a loop (loopHold), still
// under Reduce Motion.
//
// Add ▸ Text browses them by category, with this phone's Recently used
// (RecentCombos) and, when the brand kit sets a title, heading or body face,
// each one set in the kit's faces (branded).

import Foundation

enum TextCombos {

    /// The share of the page's width a combination takes as it goes on.
    static let pageShare = 0.72

    /// The categories the chips browse by, in their order.
    static let categories = ["Headline", "Sale", "Quote", "Event", "Wedding", "Social", "Retro", "Minimal", "Badge", "Kids",
                             animatedCategory]
    /// The category of the combinations that drop in already moving.
    static let animatedCategory = "Animated"

    /// How many combinations Recently used keeps.
    static let recentLimit = 8

    /// One combination as the file has it: its elements, bottom to top, in a
    /// box `w` wide and `h` tall — down to its lowest element's bottom.
    struct Combo: Identifiable {
        var id: String
        var name: String
        var tags: [String]
        var w: Double
        var h: Double
        var elements: [Element]
        /// One of `categories`; nil for an entry with none.
        var category: String?
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
        var category: String?

        private enum CodingKeys: String, CodingKey { case id, name, tags, w, elements, category }

        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            id = try? c.decode(String.self, forKey: .id)
            name = try? c.decode(String.self, forKey: .name)
            tags = (try? c.decode([String].self, forKey: .tags)) ?? []
            w = try? c.decode(Double.self, forKey: .w)
            elements = (try? c.decode([Element].self, forKey: .elements)) ?? []
            category = try? c.decode(String.self, forKey: .category)
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
            return Combo(id: id, name: name, tags: entry.tags, w: w, h: h, elements: entry.elements,
                         category: entry.category)
        }
    }

    /// Whether any of `combo`'s elements moves: an entrance or an exit.
    static func isAnimated(_ combo: Combo) -> Bool {
        combo.elements.contains { $0.animation != nil || $0.exitAnimation != nil }
    }

    /// How long a tile's loop of `combo` lasts, in seconds: its entrances
    /// to the last one's end, a second to read it, then its longest exit,
    /// and two seconds at least — the same on both phones.
    static func loopHold(_ combo: Combo) -> Double {
        let entrances = combo.elements.compactMap { $0.animation.map { $0.delay + $0.duration } }.max() ?? 0
        let exits = combo.elements.compactMap { $0.exitAnimation.map { $0.delay + $0.duration } }.max() ?? 0
        return max(2, entrances + 1 + exits)
    }

    static func combo(_ id: String?) -> Combo? {
        all.first { $0.id == id }
    }

    /// The combinations a search for `query` finds, in the file's order:
    /// those whose name, one of whose tags or whose category has it, case
    /// and accents aside, as the font picker searches — in `category` alone
    /// when one is chosen. A blank query finds them all.
    static func search(_ query: String, in category: String? = nil) -> [Combo] {
        all.filter { combo in
            guard category == nil || combo.category == category else { return false }
            return FontLibrary.matches(combo.name, query) || combo.tags.contains { FontLibrary.matches($0, query) }
                || combo.category.map { FontLibrary.matches($0, query) } == true
        }
    }

    /// Recently used after `id` is put on a page: it first, once, then the
    /// rest as they were, recentLimit in all — this phone's own.
    static func recent(_ list: [String], adding id: String) -> [String] {
        Array(([id] + list.filter { $0 != id }).prefix(recentLimit))
    }

    /// The combinations `ids` name, in their order, those no longer in the
    /// file left out.
    static func named(_ ids: [String]) -> [Combo] {
        ids.compactMap { combo($0) }
    }

    /// The prefix a combination in the brand's faces has before its id.
    static let brandPrefix = "brand:"

    /// `combo` in the brand's faces, the From your brand row's: its texts
    /// ranked by type size, biggest first and one size one rank — the
    /// biggest in the title's face, or the heading's when the kit sets no
    /// title; the next in the subheading's; the rest in the body's, each as
    /// BrandFonts.fontFor finds it — family and weight, sizes and
    /// everything else kept. Nil when the kit sets no title, heading or body
    /// face. Its id is the combination's after "brand:". The Android twin's
    /// TextCombos.branded, rank for rank.
    static func branded(_ combo: Combo, fonts: BrandFonts) -> Combo? {
        guard fonts.title != nil || fonts.heading != nil || fonts.body != nil else { return nil }
        let sizes = Array(Set(combo.elements.filter { $0.type == .text }.compactMap(\.fontSize))).sorted(by: >)
        func ranked(_ size: Double) -> BrandFont? {
            switch sizes.firstIndex(of: size) {
            case 0: return fonts.title ?? fonts.fontFor(.heading)
            case 1: return fonts.fontFor(.subheading)
            default: return fonts.fontFor(.body)
            }
        }
        var out = combo
        out.id = brandPrefix + combo.id
        out.elements = combo.elements.map { el in
            guard el.type == .text, let size = el.fontSize, let face = ranked(size) else { return el }
            var e = el
            e.fontFamily = face.family
            e.fontWeight = face.weight
            return e
        }
        return out
    }

    /// What the Text tab says when a search finds none.
    static func noneFound(_ query: String) -> String {
        tr("No font combinations match \u{201C}%@\u{201D}.", query.trimmingCharacters(in: .whitespacesAndNewlines))
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

/// The font combinations last put on a page on this phone, newest first,
/// eight of them (TextCombos.recent): Add ▸ Text's Recently used. Per
/// phone, as the Android twin keeps its own.
enum RecentCombos {
    private static let key = "canvia.recentCombos"

    static func all(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    /// `id` put on a page — one in the brand's faces by the combination's
    /// own id.
    static func record(_ id: String, defaults: UserDefaults = .standard) {
        let own = id.hasPrefix(TextCombos.brandPrefix) ? String(id.dropFirst(TextCombos.brandPrefix.count)) : id
        defaults.set(TextCombos.recent(all(defaults), adding: own), forKey: key)
    }
}
