// Font personalities mapped to fonts that ship with iOS, so every design is
// fully offline. Each stack resolves to a concrete UIFont for both canvas
// rendering and text measurement.

import SwiftUI
import UIKit

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

    /// Resolve a concrete UIFont for an element's typography.
    static func uiFont(family key: String?, size: Double, weight: Int, italic: Bool) -> UIFont {
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
            .paragraphStyle: paragraph,
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

    /// Natural height of a text element at its wrap width.
    static func measuredHeight(for el: Element) -> Double {
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
