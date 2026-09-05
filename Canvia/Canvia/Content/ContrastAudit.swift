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

    /// The colour behind a text element: the topmost element below it whose
    /// box contains the text's centre and has a flat fill, else the page.
    static func backdrop(for el: Element, in page: Page) -> String {
        guard let index = page.elements.firstIndex(where: { $0.id == el.id }) else { return pageColor(page) }
        let centre = el.center
        for other in page.elements[..<index].reversed() where other.type == .shape || other.type == .image {
            guard Geometry.aabb(other).contains(centre), other.opacity > 0.5 else { continue }
            if other.type == .shape, let fill = other.fill, fill.kind == "solid", let hex = fill.color {
                return hex
            }
            if other.type == .image { return "#808080" }   // a photo: assume mid-grey
        }
        return pageColor(page)
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
                let r = ratio(ink, back)
                let need = required(for: el)
                if r < need {
                    findings.append(Finding(pageIndex: p, elementId: el.id,
                                            text: (el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                            ratio: r, required: need, backdrop: back,
                                            suggestion: ColorTheory.readableInk(on: back)))
                }
            }
        }
        return findings
    }
}
