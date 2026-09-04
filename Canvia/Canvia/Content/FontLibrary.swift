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

        init(_ el: Element) {
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
            default: return .center
            }
        }()
        let lineHeight = size * (el.lineHeight ?? 1.25)
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byWordWrapping
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
        let raw = el.text ?? ""
        guard el.listStyle == "bullet" else { return raw }
        return raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? $0 : "•  \($0)" }
            .joined(separator: "\n")
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
        return measuredHeight(for: el)
    }

    /// Natural height of a text element at its wrap width, ignoring any curve.
    static func measuredHeight(for el: Element) -> Double {
        let key = MeasureKey(typography: TypographyKey(el), text: el.text,
                             listStyle: el.listStyle, width: el.w)
        return memoized(key, &heightCache) { measure(el) }
    }

    private static func measure(_ el: Element) -> Double {
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
