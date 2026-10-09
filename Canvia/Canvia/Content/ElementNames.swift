// What to call a thing on a page, in words a person would use.
//
// "Lined up with heading: SALE" says what a snap guide has found; a pink
// line on its own says only that something was decided. The names are the
// Android twin's (core/content/ElementNames.kt), word for word, so a guide
// reads the same on either phone: a heading or text by its words, a shape by
// its colour and kind or, when it carries words, by its kind and them, a
// photo by its frame.

import Foundation

enum ElementNames {

    /// The longest a quoted snippet of someone's own text gets.
    private static let snippet = 28

    static func name(of el: Element) -> String {
        switch el.type {
        case .text:
            let words = RichText.strip(el.text ?? "").replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let kind = (el.fontSize ?? 42) >= 64 ? "Heading" : "Text"
            return words.isEmpty ? kind : "\(kind): \(words.prefix(snippet))"
        case .shape:
            // Coloured, because "Oval" and "Oval" are the two circles behind
            // the heading, and "Red oval" and "Teal oval" are not.
            let colour = colours(of: el).first { !isFaint($0) }
            if Freehand.isStroke(el) { return withColour(el.stroke, "drawing") }
            if el.pathData != nil {
                if isFaint(el.fill?.color) && el.stroke != nil { return withColour(el.stroke, "line") }
                return withWords(el, "custom shape") ?? withColour(colour, "custom shape")
            }
            let noun = ContentLibrary.shape(el.shapeId).name.lowercased()
            return withWords(el, noun) ?? withColour(colour, noun)
        case .image:
            let frame = el.maskShapeId.map { ContentLibrary.shape($0).name.lowercased() }
            if let src = el.src, CodeGenerator.payload(from: src) != nil { return "QR code" }
            if el.src == nil { return frame.map { "Empty \($0) frame" } ?? "Empty photo frame" }
            return frame.map { "Photo in a \($0) frame" } ?? "Photo"
        case .sticker:
            return "Sticker \(el.glyph ?? "")".trimmingCharacters(in: .whitespaces)
        case .line:
            return withColour(el.color, "line")
        }
    }

    /// The same, short enough for a guide's label.
    static func shortName(of el: Element) -> String {
        let full = name(of: el)
        guard full.count > 20 else { return full }
        return String(full.prefix(19)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// What a snap guide lines the selection up with. `vertical` is a
    /// vertical line, one that places things across.
    static func guideLabel(_ source: Geometry.SnapSource, vertical: Bool, elements: [Element]) -> String {
        switch source {
        case .pageCentre: return vertical ? "Centre of the page" : "Middle of the page"
        case .pageEdge: return "Edge of the page"
        case .guide: return "Your guide"
        case .grid: return "Grid"
        case .margin: return "Page margin"
        case .element(let id):
            guard let other = elements.first(where: { $0.id == id }) else { return "Lined up" }
            // The first word is always one chosen here — Heading, Text,
            // Photo, a shape's colour — never one of the user's own, so it
            // can go into the sentence in lower case.
            let name = shortName(of: other)
            let lowered = name.prefix(1).lowercased() + String(name.dropFirst())
            return "Lined up with \(lowered)"
        }
    }

    // MARK: colour

    /// What a person would call a colour — "red", "dark blue", "light grey"
    /// — by hue, saturation and lightness bands, as the Android twin names
    /// it; "colour" when it is not one.
    static func colourName(_ hex: String?) -> String {
        guard let rgb = rgb(hex) else { return "colour" }
        let r = rgb.r, g = rgb.g, b = rgb.b
        let high = max(r, g, b), low = min(r, g, b)
        let chroma = high - low
        let light = (high + low) / 2
        let saturation = chroma == 0 ? 0 : chroma / (1 - abs(2 * light - 1))
        if light <= 0.10 { return "black" }
        if light >= 0.94 { return "white" }
        if saturation < 0.15 || chroma < 0.06 {
            return light < 0.30 ? "dark grey" : light > 0.75 ? "light grey" : "grey"
        }
        let hue: Double
        if high == r {
            let h = ((g - b) / chroma).truncatingRemainder(dividingBy: 6)
            hue = 60 * (h < 0 ? h + 6 : h)
        } else if high == g {
            hue = 60 * ((b - r) / chroma + 2)
        } else {
            hue = 60 * ((r - g) / chroma + 4)
        }
        // Brown is dark orange, and light red is what everyone calls pink.
        if hue >= 12 && hue < 45 && light < 0.42 { return "brown" }
        if (hue < 12 || hue >= 345) && light > 0.75 { return "pink" }
        let family: String
        switch hue {
        case ..<12: family = "red"
        case ..<40: family = "orange"
        case ..<68: family = "yellow"
        case ..<160: family = "green"
        case ..<188: family = "teal"
        case ..<245: family = "blue"
        case ..<290: family = "purple"
        case ..<345: family = "pink"
        default: family = "red"
        }
        return light < 0.28 ? "dark \(family)" : light > 0.72 ? "light \(family)" : family
    }

    /// A colour as a screen reader says a swatch: "Dark blue", not seven
    /// syllables of hex. The Android twin's swatches say the same words.
    static func spokenColour(_ hex: String?) -> String {
        let name = colourName(hex)
        return name.prefix(1).uppercased() + String(name.dropFirst())
    }

    /// A shape with words named by them, as a text box is, after its kind
    /// and not its colour: "Circle: SALE". Nil when it has none.
    private static func withWords(_ el: Element, _ noun: String) -> String? {
        guard let text = ShapeText.words(of: el) else { return nil }
        let words = RichText.strip(text).replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return noun.prefix(1).uppercased() + String(noun.dropFirst()) + ": \(words.prefix(snippet))"
    }

    private static func withColour(_ hex: String?, _ noun: String) -> String {
        let phrase = rgb(hex) == nil ? noun : "\(colourName(hex)) \(noun)"
        return phrase.prefix(1).uppercased() + String(phrase.dropFirst())
    }

    /// Every colour a shape paints with: its fill's, then its border's.
    private static func colours(of el: Element) -> [String] {
        var out: [String] = []
        if let fill = el.fill {
            switch fill.kind {
            case "gradient": out += (fill.stops ?? []).map(\.color)
            case "none": break
            default: if let c = fill.color { out.append(c) }
            }
        }
        if let stroke = el.stroke, (el.strokeWidth ?? 0) > 0 { out.append(stroke) }
        return out
    }

    /// Mostly see-through — a hairline, a clear fill — is no colour a person
    /// chose to see. Alpha is the last two of eight digits, as this app
    /// writes it.
    private static func isFaint(_ hex: String?) -> Bool {
        guard let digits = hex?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: ""),
              digits.count == 8, let alpha = Int(digits.suffix(2), radix: 16) else { return false }
        return alpha < 0x80
    }

    /// "#rgb", "#rrggbb" or "#rrggbbaa" as red, green and blue in 0…1.
    private static func rgb(_ hex: String?) -> (r: Double, g: Double, b: Double)? {
        guard var digits = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        switch digits.count {
        case 3: digits = digits.map { "\($0)\($0)" }.joined()
        case 6: break
        case 8: digits = String(digits.prefix(6))
        default: return nil
        }
        guard let value = Int(digits, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xff) / 255, Double((value >> 8) & 0xff) / 255, Double(value & 0xff) / 255)
    }
}
