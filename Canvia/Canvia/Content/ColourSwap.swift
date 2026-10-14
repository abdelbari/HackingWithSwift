// Changing one colour of several: the colours a selection uses, each a
// swatch of its own, and one of them swapped for another wherever it is —
// in the selection, or with Change all across the whole design.
//
// A colour is read from every field that paints with one: a solid fill,
// each stop of a gradient fill, the border, a text's or a line's colour,
// the colours on chosen words and the shadow's. Only those fields change,
// so a design stays readable by any build. The Android twin reads the same
// fields in the same order, and the shared rows in ColourSwapTests hold
// both to it.

import Foundation

enum ColourSwap {

    /// The most swatches the selection row shows.
    static let maxColours = 12

    /// The distinct colours `elements` use, as lowercase "#rrggbb", the
    /// most used first and those used equally often in the order first met
    /// — element by element, and within one in the order above. Each field
    /// or gradient stop is one use. A fully transparent one ("#rrggbb00")
    /// is no colour in use, and is left out.
    static func colours(_ elements: [Element]) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for el in elements {
            for raw in fields(of: el) {
                guard let parsed = parse(raw), parsed.alpha != "00" else { continue }
                if counts[parsed.rgb] == nil { order.append(parsed.rgb) }
                counts[parsed.rgb, default: 0] += 1
            }
        }
        let ranked = Array(order.enumerated())
        let sorted = ranked.sorted { (a: (offset: Int, element: String), b: (offset: Int, element: String)) -> Bool in
            let ca: Int = counts[a.element] ?? 0
            let cb: Int = counts[b.element] ?? 0
            if ca != cb { return ca > cb }
            return a.offset < b.offset
        }
        return Array(sorted.map { $0.element }.prefix(maxColours))
    }

    /// `elements` with every use of `from` painted `to` instead, each one
    /// keeping its own alpha: "#ff000080" swapped to "#00ff00" is
    /// "#00ff0080". Colours are compared as "#rrggbb", whatever case or
    /// short form they are written in; what is swapped is written as
    /// lowercase "#rrggbb", its alpha after it when it had one. Every other
    /// field is left as written, and so is a use wholly see-through
    /// ("#rrggbb00"), which nobody sees — as on the Android twin.
    static func swapped(_ elements: [Element], from: String, to: String) -> [Element] {
        guard let source = parse(from)?.rgb, let target = parse(to)?.rgb else { return elements }
        func swap(_ raw: String?) -> String? {
            guard let raw, let parsed = parse(raw), parsed.rgb == source, parsed.alpha != "00" else { return raw }
            return target + (parsed.alpha ?? "")
        }
        return elements.map { el in
            var e = el
            if var fill = e.fill {
                if fill.kind == "solid" { fill.color = swap(fill.color) }
                if fill.kind == "gradient", let stops = fill.stops {
                    fill.stops = stops.map { stop in
                        var s = stop
                        s.color = swap(s.color) ?? s.color
                        return s
                    }
                }
                e.fill = fill
            }
            e.stroke = swap(e.stroke)
            e.color = swap(e.color)
            if let spans = e.spans {
                e.spans = spans.map { span in
                    var s = span
                    s.color = swap(s.color)
                    return s
                }
            }
            if var shadow = e.shadow {
                shadow.color = swap(shadow.color) ?? shadow.color
                e.shadow = shadow
            }
            return e
        }
    }

    /// How many elements on every page of `design` use `colour` and would
    /// take Change all (see `takesChangeAll`).
    static func count(_ design: Design, from colour: String) -> Int {
        guard let rgb = parse(colour)?.rgb else { return 0 }
        var n = 0
        for page in design.pages {
            for el in page.elements where takesChangeAll(el) && colours([el]).contains(rgb) { n += 1 }
        }
        return n
    }

    /// Whether Change all reaches an element: not one locked whole, which
    /// keeps its colours (a position lock still takes a new colour), nor a
    /// hidden one, which is not on the page to be seen changing — as Find
    /// and replace and the Android twin pass them over.
    static func takesChangeAll(_ el: Element) -> Bool {
        takesSwap(el) && !el.isHidden
    }

    /// Whether an element's colours may be swapped: not when it is locked
    /// whole.
    static func takesSwap(_ el: Element) -> Bool {
        ElementLock.allows(ElementLock.mode(of: el), ElementLock.Action.recolour)
    }

    /// Every colour field of an element, in reading order: the fill (its
    /// colour, or each stop of a gradient), the border, the text's or
    /// line's colour, each coloured word, the shadow.
    static func fields(of el: Element) -> [String] {
        var out: [String] = []
        if let fill = el.fill {
            if fill.kind == "solid", let c = fill.color { out.append(c) }
            if fill.kind == "gradient" { out += (fill.stops ?? []).map(\.color) }
        }
        if let stroke = el.stroke { out.append(stroke) }
        if let color = el.color { out.append(color) }
        for span in el.spans ?? [] {
            if let c = span.color { out.append(c) }
        }
        if let shadow = el.shadow { out.append(shadow.color) }
        return out
    }

    /// "#rgb", "#rrggbb" or "#rrggbbaa" as lowercase "#rrggbb" and the two
    /// alpha digits when there are any; nil when it is not a colour.
    static func parse(_ hex: String) -> (rgb: String, alpha: String?)? {
        var digits = hex.trimmingCharacters(in: .whitespaces).lowercased()
        guard digits.hasPrefix("#") else { return nil }
        digits.removeFirst()
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        switch digits.count {
        case 3:
            return ("#" + digits.map { "\($0)\($0)" }.joined(), nil)
        case 6:
            return ("#" + digits, nil)
        case 8:
            return ("#" + String(digits.prefix(6)), String(digits.suffix(2)))
        default:
            return nil
        }
    }
}
