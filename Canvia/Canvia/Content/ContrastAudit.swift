// WCAG contrast, checked where it matters: each text element against what
// is actually behind it.
//
// The ratio is the standard one (relative luminance, 1:1 to 21:1). The
// threshold is WCAG AA: 4.5:1 for ordinary text, 3:1 for large text — 24px
// and up, or 19px bold — because a poster headline at 3.5:1 is fine and a
// caption at 3.5:1 is not. The backdrop is the topmost solid shape under
// the text's centre, or the page's own colour.

import UIKit

enum ContrastAudit {

    struct Finding: Identifiable, Equatable {
        var id: String { "\(pageIndex)|\(elementId)" }
        var pageIndex: Int
        var elementId: String
        var text: String
        var ratio: Double
        var required: Double
        var backdrop: String
        /// A colour that would pass on this backdrop.
        var suggestion: String
    }

    static func luminance(_ hex: String) -> Double {
        let c = UIColor(hex: hex).srgbComponents
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// WCAG contrast ratio, 1…21, order-independent.
    static func ratio(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func isLarge(_ el: Element) -> Bool {
        let size = el.fontSize ?? 42
        return size >= 24 || (size >= 19 && (el.fontWeight ?? 400) >= 700)
    }

    static func required(for el: Element) -> Double { isLarge(el) ? 3 : 4.5 }

    /// The colour behind a text element: the topmost shape or photo below it
    /// whose box holds the text's centre — a flat fill's colour, a gradient's
    /// first colour, a photo or pattern taken as mid-grey — else the page. A
    /// see-through fill (a chart's clear plot) is looked through, as the
    /// Android twin does.
    static func backdrop(for el: Element, in page: Page) -> String {
        guard let index = page.elements.firstIndex(where: { $0.id == el.id }) else { return pageColor(page) }
        let centre = el.center
        for other in page.elements[..<index].reversed() where other.type == .shape || other.type == .image {
            guard Geometry.aabb(other).contains(centre), other.opacity > 0.5 else { continue }
            if other.type == .image { return "#808080" }   // a photo: assume mid-grey
            guard let fill = other.fill else { continue }
            switch fill.kind {
            case "solid":
                if let hex = fill.color, !isFaint(hex) { return hex }
            case "gradient":
                return fill.stops?.first?.color ?? fill.color ?? "#808080"
            case "pattern", "image":
                return "#808080"
            default:
                break
            }
        }
        return pageColor(page)
    }

    /// Mostly see-through: an 8-digit colour whose alpha is under half.
    static func isFaint(_ hex: String) -> Bool {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 8, let alpha = UInt8(digits.suffix(2), radix: 16) else { return false }
        return alpha < 0x80
    }

    /// `ink` as it is drawn over `back`: faded by the text's opacity and the
    /// colour's own alpha — what a reader sees, and what is measured.
    static func drawn(_ ink: String, over back: String, opacity: Double) -> String {
        var digits = ink.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        var alpha: Double = 1
        if digits.count == 8, let a = UInt8(digits.suffix(2), radix: 16) { alpha = Double(a) / 255 }
        let a: Double = min(max(opacity, 0), 1) * alpha
        if a >= 1 { return ink }
        let i = UIColor(hex: ink).srgbComponents
        let b = UIColor(hex: back).srgbComponents
        func mix(_ x: CGFloat, _ y: CGFloat) -> Int {
            let v: Double = Double(y) + (Double(x) - Double(y)) * a
            return Int((v * 255).rounded())
        }
        let r: Int = mix(i.r, b.r), g: Int = mix(i.g, b.g), bl: Int = mix(i.b, b.b)
        return String(format: "#%02x%02x%02x", r, g, bl)
    }

    /// An ink that passes on `back`: the usual choice when it passes, else
    /// the other, else whichever of black and white reads best — the better
    /// of those always clears 4.5:1.
    static func suggestion(on back: String, need: Double) -> String {
        let first: String = ColorTheory.readableInk(on: back)
        let second: String = first == "#ffffff" ? "#16181d" : "#ffffff"
        for candidate in [first, second] where ratio(candidate, back) >= need { return candidate }
        return ratio("#000000", back) >= ratio("#ffffff", back) ? "#000000" : "#ffffff"
    }

    /// The element with a finding fixed: the suggested ink, and fully opaque
    /// when faded it would still fall short.
    static func fixed(_ el: Element, for f: Finding) -> Element {
        var out = el
        out.color = f.suggestion
        let readable: Bool = ratio(drawn(f.suggestion, over: f.backdrop, opacity: el.opacity), f.backdrop) >= f.required
        if !readable { out.opacity = 1 }
        return out
    }

    static func pageColor(_ page: Page) -> String {
        switch page.background {
        case .color(let hex): return hex
        case .gradient(let paint): return paint.stops?.first?.color ?? paint.color ?? "#ffffff"
        case .image: return "#808080"
        }
    }

    /// Every text element that falls short, page by page.
    static func audit(_ design: Design) -> [Finding] {
        var findings: [Finding] = []
        for (p, page) in design.pages.enumerated() {
            for el in page.elements where el.type == .text {
                guard el.textFill == nil, el.opacity > 0.05 else { continue }
                let ink = el.color ?? "#1f2430"
                let back = backdrop(for: el, in: page)
                // Measured as drawn: faded text reads fainter than its ink.
                let r = ratio(drawn(ink, over: back, opacity: el.opacity), back)
                let need = required(for: el)
                if r < need {
                    findings.append(Finding(pageIndex: p, elementId: el.id,
                                            text: (el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                            ratio: r, required: need, backdrop: back,
                                            suggestion: suggestion(on: back, need: need)))
                }
            }
        }
        return findings
    }
}
