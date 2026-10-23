// One font swapped for another throughout a design: the font picker's
// "Replace everywhere…" on a font In this design, and its "Change all (N)"
// after a font is chosen for a box whose old font is used elsewhere.
//
// A font is used — and swapped — wherever the design names it: a text's or
// a shape's words' face (a table's cells and a chart's labels are texts, as
// are the boxes that follow a saved text style), the faces chosen for words
// (Spans' "font"), and a chart's own "font", which its Update draws its
// labels in. Each element, each span and each chart counts once. Keys are
// compared as the families they mean (FontLibrary.resolve), so "didone" is
// Playfair Display. A locked element and a locked page are left as they
// are, as Find and replace leaves them. A text's weight goes to the weight
// nearest it that the new font has (FontLibrary.resolveWeight, ties to the
// heavier), a word's own weight too, and each text changed is measured
// again. The Android twin's FontSwap, rule for rule, over the same rows.

import Foundation

enum FontSwap {

    /// A font the design uses, and in how many places.
    struct Use: Equatable {
        var family: String
        var count: Int
    }

    /// The fonts the design uses where they can be swapped, each with how
    /// many places use it, in the order first met: page by page, element
    /// by element, a box's face before its words' and its chart's.
    static func uses(_ design: Design) -> [Use] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        func count(_ key: String) {
            let family = FontLibrary.resolve(key)
            if counts[family] == nil { order.append(family) }
            counts[family, default: 0] += 1
        }
        var charts = Set<String>()
        for page in design.pages where !PageLocks.isLocked(page) {
            for el in page.elements where !el.locked {
                if ShapeText.carriesWords(el), let face = el.fontFamily { count(face) }
                for span in el.liveSpans { if let font = span.font { count(font) } }
                if let spec = el.chart, let font = spec.font, charts.insert(spec.id).inserted { count(font) }
            }
        }
        return order.map { Use(family: $0, count: counts[$0] ?? 0) }
    }

    /// How many places use `family` (uses).
    static func count(_ design: Design, family: String) -> Int {
        let wanted = FontLibrary.resolve(family)
        return uses(design).first { $0.family == wanted }?.count ?? 0
    }

    /// `design` with `from` swapped for `to` wherever it is used (uses):
    /// each text's face, weight to the nearest `to` has, measured again by
    /// `heightFor`; each word's face and its own weight; each chart's font.
    /// The same design when `from` and `to` are one family.
    static func replaced(_ design: Design, from: String, to: String,
                         heightFor: (Element) -> Double) -> Design {
        let source = FontLibrary.resolve(from)
        guard source != FontLibrary.resolve(to) else { return design }
        func matches(_ key: String?) -> Bool { key.map { FontLibrary.resolve($0) == source } ?? false }
        var out = design
        for p in out.pages.indices where !PageLocks.isLocked(out.pages[p]) {
            for i in out.pages[p].elements.indices where !out.pages[p].elements[i].locked {
                let was = out.pages[p].elements[i]
                var el = was
                if ShapeText.carriesWords(el), matches(el.fontFamily) {
                    el.fontFamily = to
                    let nearest = FontLibrary.resolveWeight(to, el.fontWeight ?? 400)
                    if el.fontWeight != nil || nearest != 400 { el.fontWeight = nearest }
                }
                let spans = el.liveSpans
                if spans.contains(where: { matches($0.font) }) {
                    el.setSpans(spans.map { span in
                        guard matches(span.font) else { return span }
                        var swapped = span
                        swapped.font = to
                        swapped.weight = span.weight.map { FontLibrary.resolveWeight(to, $0) }
                        return swapped
                    })
                }
                if var spec = el.chart, matches(spec.font) {
                    spec.font = to
                    el.chart = spec
                }
                guard el != was else { continue }
                if el.type == .text {
                    el.h = heightFor(el)
                } else if el.type == .shape {
                    ShapeText.fitWords(&el)
                }
                out.pages[p].elements[i] = el
            }
        }
        return out
    }
}
