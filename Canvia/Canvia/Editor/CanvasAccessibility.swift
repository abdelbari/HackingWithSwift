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

    static func label(for el: Element) -> String {
        switch el.type {
        case .text:
            let body = (el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { return "Empty text" }
            let clipped = body.count > 80 ? String(body.prefix(80)) + "…" : body
            return "Text: \(clipped)"
        case .shape:
            return "\(ContentLibrary.shape(el.shapeId).name) shape"
        case .image:
            return el.maskShapeId == nil ? "Photo" : "Photo in a \(ContentLibrary.shape(el.maskShapeId).name) frame"
        case .sticker:
            return "Sticker \(el.glyph ?? "")"
        case .line:
            return "Line"
        }
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
