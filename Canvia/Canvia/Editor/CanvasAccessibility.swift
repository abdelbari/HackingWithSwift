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

    /// Alt text when there is some; "Empty text" for a box with no words;
    /// otherwise the same name the Layers sheet and the snap guides use —
    /// "Heading: SALE", "Red oval", "Blue line", "QR code", "Empty photo
    /// frame" — as the Android twin names its TalkBack nodes.
    static func label(for el: Element) -> String {
        if let alt = el.altText?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty {
            return alt
        }
        if el.type == .text, RichText.strip(el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Empty text"
        }
        return ElementNames.name(of: el)
    }

    /// Position and size as percentages of the page: "at 12% across, 40%
    /// down; 50% wide, 30% tall". Pixels would be true and meaningless.
    static func value(for el: Element, design: Design) -> String {
        let w = max(design.width, 1), h = max(design.height, 1)
        func pct(_ v: Double, of total: Double) -> Int { Int((v / total * 100).rounded()) }
        var parts = [
            "at \(pct(el.x, of: w))% across, \(pct(el.y, of: h))% down",
            "\(pct(el.w, of: w))% wide, \(pct(el.h, of: h))% tall",
        ]
        let turn = Int(el.rotation.rounded()) % 360
        if turn != 0 { parts.append("rotated \(turn) degrees") }
        if el.locked { parts.append("locked") }
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
