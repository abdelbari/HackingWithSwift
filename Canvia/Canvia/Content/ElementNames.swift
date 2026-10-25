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

    /// The element's name: its own (`layerName`) when it has one, else the
    /// one made from what it is.
    static func name(of el: Element) -> String {
        if let own = LayerNames.custom(of: el) { return own }
        // Any part of a chart is its chart's summary, as a reader meets the
        // chart as one thing — as on the Android twin.
        if let chart = ChartSpeech.summary(of: el) { return chart }
        // A diagram's part, the diagram as a whole: "Cycle diagram, 4 items".
        if let diagram = el.diagram, el.diagramPart != nil { return Diagrams.summary(diagram) }
        switch el.type {
        case .text:
            let words = RichText.strip(el.text ?? "").replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let heading = (el.fontSize ?? 42) >= 64
            guard !words.isEmpty else { return heading ? tr("Heading") : tr("Text") }
            let quoted = String(words.prefix(snippet))
            return heading ? tr("Heading: %@", quoted) : tr("Text: %@", quoted)
        case .shape:
            // Coloured, because "Oval" and "Oval" are the two circles behind
            // the heading, and "Red oval" and "Teal oval" are not.
            let colour = colours(of: el).first { !isFaint($0) }
            // Named for what it shows, as the icons tab names it.
            if let icon = IconLibrary.icon(of: el) { return tr("%@ icon", icon.name) }
            if let graphic = GraphicsLibrary.graphic(of: el) { return tr("%@ graphic", graphic.name) }
            if Freehand.isStroke(el) { return withColour(el.stroke, tr("drawing"), tr("%@ drawing", colourName(el.stroke))) }
            if el.pathData != nil {
                if isFaint(el.fill?.color) && el.stroke != nil {
                    return withColour(el.stroke, tr("line"), tr("%@ line", colourName(el.stroke)))
                }
                return withWords(el, tr("custom shape"))
                    ?? withColour(colour, tr("custom shape"), tr("%@ custom shape", colourName(colour)))
            }
            let english = englishNoun(ContentLibrary.shape(el.shapeId))
            let noun = tr(english)
            return withWords(el, noun) ?? withColour(colour, noun, tr("%@ " + english, colourName(colour)))
        case .image:
            // A grid's cut cell is named as any cell is (its cut is no
            // frame); a mask frame by its name, as its tile says it.
            let shape = ContentLibrary.frameShape(el.maskShapeId)
            let frame = MaskFrames.mask(el.maskShapeId).map { tr($0.shape.name) } ?? shape.map { tr(englishNoun($0)) }
            // Named for what it holds, as its sheet names it: "Wi-Fi QR
            // code", "EAN-13 barcode".
            if let src = el.src, CodeGenerator.payload(from: src) != nil {
                return QRForms.form(of: el).map { tr("%@ QR code", $0.kind.name) } ?? tr("QR code")
            }
            if let code = Barcodes.parse(el.src) { return tr("%@ barcode", code.kind.name) }
            // A frame filled with a colour in place of a photo is named for
            // it, as a shape is: "Frame, filled dark blue" — a gradient by
            // its first colour, as on the Android twin.
            if let fill = PhotoFrames.colourOf(el) { return tr("Frame, filled %@", colourName(fill.primaryColor)) }
            // A letter frame is named for its glyph, as its tile is: "Empty
            // A letter frame", the same on both phones.
            if let glyph = GlyphFrames.frame(shape?.id)?.glyph {
                return PhotoFrames.isEmpty(el) ? tr("Empty %@ letter frame", glyph) : tr("Photo in the %@ letter frame", glyph)
            }
            if el.src == nil { return frame.map { tr("Empty %@ frame", $0) } ?? tr("Empty photo frame") }
            return frame.map { tr("Photo in a %@ frame", $0) } ?? tr("Photo")
        case .sticker:
            return tr("Sticker %@", el.glyph ?? "").trimmingCharacters(in: .whitespaces)
        case .line:
            return withColour(el.color, tr("line"), tr("%@ line", colourName(el.color)))
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
        case .pageCentre: return vertical ? tr("Centre of the page") : tr("Middle of the page")
        case .pageEdge: return tr("Edge of the page")
        case .bleedEdge: return tr("Edge of the bleed")
        case .safeZone: return tr("Safe zone")
        case .guide: return tr("Your guide")
        case .grid: return tr("Grid")
        case .margin: return tr("Page margin")
        case .element(let id):
            guard let other = elements.first(where: { $0.id == id }) else { return tr("Lined up") }
            // The first word of a made name is always one chosen here —
            // Heading, Text, Photo, a shape's colour — never one of the
            // user's own, so it can go into the sentence in lower case. A
            // name the user gave it is theirs, and kept as typed.
            let name = shortName(of: other)
            if LayerNames.custom(of: other) != nil { return tr("Lined up with %@", name) }
            let lowered = name.prefix(1).lowercased() + String(name.dropFirst())
            return tr("Lined up with %@", lowered)
        }
    }

    // MARK: colour

    /// What a person would call a colour — "red", "dark blue", "light grey"
    /// — by hue, saturation and lightness bands, as the Android twin names
    /// it; "colour" when it is not one. In the app's language.
    static func colourName(_ hex: String?) -> String {
        tr(englishColourName(hex))
    }

    /// A colour's family, in English, without its "dark" or "light": "blue"
    /// for #023e8a — what a photo is said to be mostly (AltText.suggest).
    /// The Android twin's Palettes.familyOf.
    static func colourFamily(_ hex: String?) -> String {
        var name = englishColourName(hex)
        for depth in ["dark ", "light "] where name.hasPrefix(depth) { name.removeFirst(depth.count) }
        return name
    }

    /// colourName's English, the catalogue's key for it.
    static func englishColourName(_ hex: String?) -> String {
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

    /// A library shape's name inside a sentence, "speech bubble": lower
    /// case in English only. The catalogue has each name as each language
    /// writes it there ("Sprechblase"), and "%@ speech bubble" for it with
    /// a colour, each language putting the colour where it goes.
    private static func englishNoun(_ shape: ShapeDef) -> String {
        (shape.englishName ?? shape.name).lowercased()
    }

    /// A shape with words named by them, as a text box is, after its kind
    /// and not its colour: "Circle: SALE". Nil when it has none.
    private static func withWords(_ el: Element, _ noun: String) -> String? {
        guard let text = ShapeText.words(of: el) else { return nil }
        let words = RichText.strip(text).replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return tr("%@: %@", noun.prefix(1).uppercased() + String(noun.dropFirst()), String(words.prefix(snippet)))
    }

    /// `noun` alone when `hex` is no colour, else `coloured`, the noun
    /// with colourName's words: "red line".
    private static func withColour(_ hex: String?, _ noun: String, _ coloured: String) -> String {
        let phrase = rgb(hex) == nil ? noun : coloured
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
