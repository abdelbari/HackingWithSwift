// What VoiceOver says about an element on the canvas, and what it can do
// to it.
//
// The hit areas are plain rectangles with gestures on them; to VoiceOver
// that is a page of unlabelled buttons. Each one gets a name that says what
// it is (and, for text, what it says), a value that says where it is and
// how big, and the edits that otherwise need a drag: move, delete,
// duplicate, layer order. All pure functions of the element, so the words
// are testable.

import Foundation

enum CanvasAccessibility {

    /// Alt text when there is some; the name given it in Layers; "Empty
    /// text" for a box with no words; otherwise the same name the Layers
    /// sheet and the snap guides use — "Heading: SALE", "Red oval", "Blue
    /// line", "QR code", "Empty photo frame" — as the Android twin names its
    /// TalkBack nodes.
    static func label(for el: Element) -> String {
        if let alt = el.altText?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty {
            return alt
        }
        if let own = LayerNames.custom(of: el) { return own }
        if el.type == .text, RichText.strip(el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tr("Empty text")
        }
        return ElementNames.name(of: el)
    }

    /// Position and size as percentages of the page: "at 12% across, 40%
    /// down; 50% wide, 30% tall". Pixels would be true and meaningless.
    static func value(for el: Element, design: Design) -> String {
        let w = max(design.width, 1), h = max(design.height, 1)
        func pct(_ v: Double, of total: Double) -> String { "\(Int((v / total * 100).rounded()))%" }
        var parts = [
            tr("at %@ across, %@ down", pct(el.x, of: w), pct(el.y, of: h)),
            tr("%@ wide, %@ tall", pct(el.w, of: w), pct(el.h, of: h)),
        ]
        let turn = Int(el.rotation.rounded()) % 360
        if turn != 0 { parts.append(trn("rotated %d degrees|rotated %d degrees", turn)) }
        if el.locked { parts.append(tr("locked")) } else if el.lockPosition == true { parts.append(tr("position locked")) }
        return parts.joined(separator: "; ")
    }

    /// One step of a nudge action, in page units: a hundredth of the page's
    /// longer side, so it means the same thing on a business card and a
    /// poster.
    static func nudge(for design: Design) -> Double {
        (max(design.width, design.height) / 100).rounded()
    }
}

extension CanvasAccessibility {
    /// The order a sighted reader takes the page in — rows top to bottom,
    /// left to right within a row — so VoiceOver reads it the same way
    /// rather than in the order things were added. Elements whose tops are
    /// within a twelfth of the page height of the row's first share a row.
    static func readingOrder(_ elements: [Element], pageHeight: Double) -> [String] {
        let tolerance = max(pageHeight, 1) / 12
        let byTop = elements.sorted { a, b in a.y != b.y ? a.y < b.y : a.x < b.x }
        var rows: [[Element]] = []
        for el in byTop {
            if let last = rows.last, let head = last.first, abs(el.y - head.y) <= tolerance {
                rows[rows.count - 1].append(el)
            } else {
                rows.append([el])
            }
        }
        return rows.flatMap { row in row.sorted { a, b in a.x != b.x ? a.x < b.x : a.y < b.y } }.map(\.id)
    }
}

extension CanvasAccessibility {
    /// How much Make larger and Make smaller change an element: a tenth.
    static let sizeStep = 0.1
    /// How far Turn clockwise and Turn anticlockwise turn it, in degrees.
    static let turnStep = 15.0

    /// `el` made larger (or smaller) by `sizeStep` about its centre, as a
    /// corner handle dragged that far would make it: a text's type scales
    /// with its box, and its tracking with it; a photo, a shape, anything
    /// else keeps its proportions; a line grows along its length and keeps
    /// its thickness. No side goes under the least a corner leaves — 12 for
    /// a text, 8 for anything else — as on the Android twin; nil when it is
    /// there already.
    static func scaled(_ el: Element, larger: Bool) -> Element? {
        let least = el.type == .text ? 12.0 : 8.0
        let w = max(el.w * (larger ? 1 + sizeStep : 1 - sizeStep), least)
        let factor = el.w > 0 ? w / el.w : 1
        let h = el.type == .line ? el.h : max(el.h * factor, least)
        guard w != el.w || h != el.h else { return nil }
        let c = el.center
        var out = el
        out.w = w
        out.h = h
        out.x = c.x - w / 2
        out.y = c.y - h / 2
        if el.type == .text {
            out.fontSize = max(6, (el.fontSize ?? 42) * factor)
            out.letterSpacing = el.letterSpacing.map { $0 * factor }
        }
        return out
    }

    /// A turn of `turnStep` clockwise (or anticlockwise) from `rotation`,
    /// landing on a multiple of it: 7° goes to 15° clockwise and to 0°
    /// anticlockwise. In 0..<360.
    static func turned(_ rotation: Double, clockwise: Bool) -> Double {
        let steps = rotation / turnStep
        // Within a hair of a multiple, it is on it.
        let next = clockwise ? (steps + 1e-9).rounded(.down) + 1 : (steps - 1e-9).rounded(.up) - 1
        let degrees = next * turnStep
        return (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
}
