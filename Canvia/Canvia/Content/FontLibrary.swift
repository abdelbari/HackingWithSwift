// Font personalities mapped to fonts that ship with iOS, so every design is
// fully offline. Each stack resolves to a concrete UIFont for both canvas
// rendering and text measurement.

import SwiftUI
import UIKit
import CoreText

struct FontStack: Identifiable {
    var key: String
    var name: String
    /// Candidate PostScript family names, tried in order.
    var families: [String]

    var id: String { key }
}

enum FontLibrary {
    static let stacks: [FontStack] = [
        FontStack(key: "sans", name: "Modern Sans", families: ["HelveticaNeue"]),
        FontStack(key: "grotesk", name: "Grotesk", families: ["AvenirNext-Bold", "HelveticaNeue-Bold"]),
        FontStack(key: "serif", name: "Classic Serif", families: ["Georgia"]),
        FontStack(key: "didone", name: "Editorial", families: ["Didot", "Georgia"]),
        FontStack(key: "slab", name: "Slab", families: ["Rockwell", "AmericanTypewriter"]),
        FontStack(key: "mono", name: "Typewriter", families: ["Menlo-Regular", "CourierNewPSMT"]),
        FontStack(key: "rounded", name: "Rounded", families: ["ArialRoundedMTBold", "AvenirNext-Medium"]),
        FontStack(key: "condensed", name: "Condensed", families: ["AvenirNextCondensed-Medium", "DINCondensed-Bold"]),
        FontStack(key: "humanist", name: "Humanist", families: ["Verdana", "TrebuchetMS"]),
        FontStack(key: "script", name: "Script", families: ["SnellRoundhand-Bold", "MarkerFelt-Wide"]),
        FontStack(key: "elegant", name: "Elegant", families: ["Palatino-Roman", "HoeflerText-Regular"]),
        FontStack(key: "impact", name: "Display", families: ["Futura-CondensedExtraBold", "AvenirNextCondensed-Heavy"]),
    ]

    static let stackMap: [String: FontStack] = Dictionary(
        uniqueKeysWithValues: stacks.map { ($0.key, $0) })

    static func stack(_ key: String?) -> FontStack {
        stackMap[key ?? "sans"] ?? stacks[0]
    }

    // MARK: memoisation
    //
    // None of this was cached. attributes(for:) walks a font-family stack
    // calling UIFont(name:), rebuilds a descriptor, allocates a paragraph
    // style and parses a hex colour; measuredHeight(for:) then runs a full
    // CoreText layout on top. They are called on every keystroke while
    // editing text, on every frame of a text resize, and once per text
    // element when a document opens — always with the same handful of
    // distinct inputs. Memoising turns a per-frame layout into a dictionary
    // lookup.
    //
    // Guarded by a lock rather than isolated to the main actor: document
    // decoding measures text off the main thread.

    private struct TypographyKey: Hashable {
        let family: String?
        let size: Double
        let weight: Int
        let italic: Bool
        let underline: Bool
        let align: String?
        let lineHeight: Double
        let letterSpacing: Double
        let color: String?
        let listStyle: String?
        let indent: Int
        let paragraphSpacing: Double

        init(_ el: Element) {
            listStyle = el.listStyle
            indent = FontLibrary.indentLevel(of: el)
            paragraphSpacing = el.paragraphSpacing ?? 0
            family = el.fontFamily
            size = el.fontSize ?? 42
            weight = el.fontWeight ?? 400
            italic = el.italic ?? false
            underline = el.underline ?? false
            align = el.align
            lineHeight = el.lineHeight ?? 1.25
            letterSpacing = el.letterSpacing ?? 0
            color = el.color
        }
    }

    private struct MeasureKey: Hashable {
        let typography: TypographyKey
        let text: String?
        let listStyle: String?
        let width: Double
    }

    private struct FontKey: Hashable {
        let family: String?
        let size: Double
        let weight: Int
        let italic: Bool
    }

    private static let lock = NSLock()
    private static var fontCache: [FontKey: UIFont] = [:]
    private static var attrCache: [TypographyKey: [NSAttributedString.Key: Any]] = [:]
    private static var heightCache: [MeasureKey: Double] = [:]

    /// Scrubbing a size slider would otherwise grow these without bound.
    private static let cacheLimit = 256

    private static func memoized<K: Hashable, V>(_ key: K,
                                                 _ cache: inout [K: V],
                                                 _ make: () -> V) -> V {
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let value = make()
        lock.lock()
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = value
        lock.unlock()
        return value
    }

    /// Resolve a concrete UIFont for an element's typography.
    static func uiFont(family key: String?, size: Double, weight: Int, italic: Bool) -> UIFont {
        memoized(FontKey(family: key, size: size, weight: weight, italic: italic),
                 &fontCache) { buildFont(family: key, size: size, weight: weight, italic: italic) }
    }

    private static func buildFont(family key: String?, size: Double,
                                  weight: Int, italic: Bool) -> UIFont {
        let stack = stack(key)
        var base: UIFont?
        for family in stack.families {
            if let f = UIFont(name: family, size: size) { base = f; break }
        }
        var font = base ?? UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        var traits: UIFontDescriptor.SymbolicTraits = []
        if weight >= 600 { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let d = font.fontDescriptor.withSymbolicTraits(
            font.fontDescriptor.symbolicTraits.union(traits)) {
            font = UIFont(descriptor: d, size: size)
        }
        return font
    }

    /// SwiftUI Font for an element's typography (UIFont is toll-free
    /// bridged to CTFont, but Swift needs the explicit cast).
    static func font(family key: String?, size: Double, weight: Int, italic: Bool) -> Font {
        Font(uiFont(family: key, size: size, weight: weight, italic: italic) as CTFont)
    }

    static func uiWeight(_ weight: Int) -> UIFont.Weight {
        switch weight {
        case ..<300: return .light
        case ..<500: return .regular
        case ..<600: return .medium
        case ..<700: return .semibold
        case ..<800: return .bold
        case ..<900: return .heavy
        default: return .black
        }
    }

    /// Attributes shared by canvas rendering, measurement and export.
    static func attributes(for el: Element) -> [NSAttributedString.Key: Any] {
        memoized(TypographyKey(el), &attrCache) { buildAttributes(for: el) }
    }

    private static func buildAttributes(for el: Element) -> [NSAttributedString.Key: Any] {
        let size = el.fontSize ?? 42
        let font = uiFont(family: el.fontFamily, size: size,
                          weight: el.fontWeight ?? 400, italic: el.italic ?? false)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = {
            switch el.align ?? "center" {
            case "left": return .left
            case "right": return .right
            case "justify": return .justified
            default: return .center
            }
        }()
        paragraph.paragraphSpacing = size * max(0, el.paragraphSpacing ?? 0)
        let lineHeight = size * (el.lineHeight ?? 1.25)
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        // Indent levels push the whole paragraph in; a list marker then
        // hangs: the first line starts at the marker, wrapped lines start
        // where the text after the marker does.
        let indent = Double(indentLevel(of: el)) * size * indentEm
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent + (isList(el) ? size * markerEm : 0)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph.copy(),
            .foregroundColor: UIColor(hex: el.color ?? "#1f2430"),
            .kern: el.letterSpacing ?? 0,
        ]
        if el.underline == true {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    /// Display text including bullet prefixes.
    static func displayText(for el: Element) -> String {
        displayText(for: el, pageNumber: nil, pageCount: nil)
    }

    /// "{page}" and "{pages}" in a text element become the page's number and
    /// the document's page count when the caller knows them; left as they
    /// are when it does not, so measuring is honest about the width. Inline
    /// style markers (**bold** and the like) are stripped: this is what is
    /// measured and what plain drawing shows.
    static func displayText(for el: Element, pageNumber: Int?, pageCount: Int?) -> String {
        RichText.strip(markedDisplayText(for: el, pageNumber: pageNumber, pageCount: pageCount))
    }

    /// The text as drawn with its inline styles applied: the plain display
    /// text with bold, italic, underline and strike runs on top of the
    /// element's own attributes.
    static func attributedString(for el: Element) -> NSAttributedString {
        let marked = markedDisplayText(for: el, pageNumber: nil, pageCount: nil)
        let base = attributes(for: el)
        guard RichText.hasMarkup(marked) else { return NSAttributedString(string: marked, attributes: base) }
        let size = el.fontSize ?? 42
        let weight = el.fontWeight ?? 400
        return RichText.attributed(marked, base: base) { bold, italic in
            uiFont(family: el.fontFamily, size: size,
                   weight: bold ? (weight >= 700 ? 900 : 700) : weight,
                   italic: italic || el.italic == true)
        }
    }

    /// Display text with the inline style markers still in it.
    static func markedDisplayText(for el: Element, pageNumber: Int?, pageCount: Int?) -> String {
        var raw = el.text ?? ""
        if let pageNumber { raw = raw.replacingOccurrences(of: "{page}", with: String(pageNumber)) }
        if let pageCount { raw = raw.replacingOccurrences(of: "{pages}", with: String(pageCount)) }
        guard isList(el) else { return raw }
        var n = 0
        return raw.components(separatedBy: "\n")
            .map { line in
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
                n += 1
                return (listMarker(style: el.listStyle, index: n) ?? "") + line
            }
            .joined(separator: "\n")
    }

    /// One indent level, in ems.
    static let indentEm = 1.5
    /// Room a list marker takes, in ems; wrapped lines hang under the text.
    static let markerEm = 1.4

    static let listStyles = ["none", "bullet", "number", "letter"]
    static let maxIndent = 4

    static func isList(_ el: Element) -> Bool {
        el.listStyle.map { $0 != "none" } ?? false
    }

    static func indentLevel(of el: Element) -> Int {
        min(maxIndent, max(0, el.indent ?? 0))
    }

    /// The prefix a line gets, by style and one-based position among the
    /// non-blank lines. Letters run a…z then aa, ab… so the 27th item is
    /// not a crash and not "{".
    static func listMarker(style: String?, index: Int) -> String? {
        switch style {
        case "bullet": return "•  "
        case "number": return "\(index).  "
        case "letter":
            var n = index, s = ""
            while n > 0 {
                n -= 1
                s = String(UnicodeScalar(UInt8(97 + n % 26))) + s
                n /= 26
            }
            return s + ".  "
        default: return nil
        }
    }

    /// The height a text element's box needs — the one everything outside this
    /// file should ask for.
    ///
    /// Curving a line makes it much taller than its flat measurement, so a
    /// caller that reached past this to measuredHeight would keep resetting a
    /// curved element's box to the straight height and clip the arc away. That
    /// is why this exists rather than each call site deciding.
    static func layoutHeight(for el: Element) -> Double {
        if let degrees = el.curve, abs(degrees) >= TextOutliner.straightBelowDegrees,
           let curved = TextOutliner.curvedSize(for: el, degrees: degrees) {
            return max(curved.height, el.fontSize ?? 42)
        }
        // A fitted box is the size the user made it; the type fits inside.
        if el.fitText == true { return max(el.h, 8) }
        let measured = measuredHeight(for: el)
        // A vertically aligned box may be taller than its text — that is
        // the whole point of aligning within it — and must not snap shut.
        if el.vAlign != nil { return max(el.h, measured) }
        return measured
    }

    /// The largest type size, up to `maxSize`, at which the text fits inside
    /// the element's own box. Binary search over the measurement, which is
    /// what the box would do by hand: bigger until it spills, then back.
    static func fittingFontSize(for el: Element, maxSize: Double = 400) -> Double {
        guard el.w > 8, el.h > 8, !(el.text ?? "").isEmpty else { return el.fontSize ?? 42 }
        var probe = el
        probe.fitText = nil
        probe.vAlign = nil
        var lo = 6.0, hi = maxSize
        for _ in 0..<18 {
            let mid = (lo + hi) / 2
            probe.fontSize = mid
            let fits = measuredHeight(for: probe) <= el.h && naturalWidth(for: probe) <= el.w
            if fits { lo = mid } else { hi = mid }
        }
        // Down to the half-point, never up: `lo` is the largest size proven
        // to fit, and rounding above it spilled by a pixel.
        return (lo * 2).rounded(.down) / 2
    }

    /// The width the longest word needs at this size — the point below which
    /// a box does not narrow the text, it breaks it.
    static func naturalWidth(for el: Element) -> Double {
        let attrs = attributes(for: el)
        let words = displayText(for: el).split(whereSeparator: { $0 == " " || $0 == "\n" })
        return words.reduce(0.0) { widest, word in
            max(widest, ceil(NSAttributedString(string: String(word), attributes: attrs).size().width))
        }
    }

    /// The width of the widest line, so a box can shrink onto its text.
    static func lineWidth(for el: Element) -> Double {
        let attrs = attributes(for: el)
        return displayText(for: el).components(separatedBy: "\n").reduce(0.0) { widest, line in
            max(widest, ceil(NSAttributedString(string: line, attributes: attrs).size().width))
        }
    }

    // MARK: drop caps

    static let dropCapLines = 3.0

    /// The drop cap's letter and box, and the rest of the text: the cap is
    /// the first letter at three lines' height, the body wraps beside and
    /// then below it.
    struct DropCapLayout {
        var letter: String
        var rest: String
        var capRect: CGRect
        var capFontSize: Double
    }

    static func dropCapLayout(for el: Element) -> DropCapLayout? {
        let text = displayText(for: el)
        guard el.dropCap == true, el.curve == nil, !isList(el),
              let first = text.first, first.isLetter || first.isNumber else { return nil }
        let size = el.fontSize ?? 42
        let line = size * (el.lineHeight ?? 1.25)
        let capSize = line * dropCapLines * 0.82
        var capEl = el
        capEl.fontSize = capSize
        capEl.lineHeight = 1
        let letter = String(first)
        let width = ceil(NSAttributedString(string: letter, attributes: attributes(for: capEl)).size().width)
        let rest = String(text.dropFirst()).trimmingCharacters(in: .init(charactersIn: " "))
        return DropCapLayout(letter: letter, rest: rest,
                             capRect: CGRect(x: 0, y: 0, width: width + size * 0.25, height: line * dropCapLines),
                             capFontSize: capSize)
    }

    /// The size the canvas draws a text element at: its own, or the one
    /// that fits its box.
    static func effectiveFontSize(for el: Element) -> Double {
        el.fitText == true ? fittingFontSize(for: el) : (el.fontSize ?? 42)
    }

    /// Natural height of a text element at its wrap width, ignoring any curve.
    static func measuredHeight(for el: Element) -> Double {
        let key = MeasureKey(typography: TypographyKey(el), text: el.text,
                             listStyle: el.listStyle, width: el.w)
        return memoized(key, &heightCache) { measure(el) }
    }

    private static func measure(_ el: Element) -> Double {
        if let layout = dropCapLayout(for: el) {
            // The body beside the cap, then below it: measured as the text
            // at the narrow width for three lines, and the full width after.
            let attrs = attributes(for: el)
            let line = (el.fontSize ?? 42) * (el.lineHeight ?? 1.25)
            let narrow = max(el.w - layout.capRect.width, 20)
            let body = NSAttributedString(string: layout.rest, attributes: attrs)
            let besideHeight = body.boundingRect(with: CGSize(width: narrow, height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
            if besideHeight <= line * dropCapLines + 1 { return ceil(max(besideHeight, layout.capRect.height)) }
            let overflowLines = (besideHeight - line * dropCapLines) / max(line, 1)
            // Lines that spill below the cap get the full width, so fewer.
            let below = ceil(overflowLines * narrow / el.w) * line
            return ceil(layout.capRect.height + below)
        }
        let attrs = attributes(for: el)
        let str = NSAttributedString(string: displayText(for: el), attributes: attrs)
        let bounds = str.boundingRect(
            with: CGSize(width: el.w, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil)
        let lineHeight = (el.fontSize ?? 42) * (el.lineHeight ?? 1.25)
        return max(ceil(bounds.height), lineHeight)
    }
}
